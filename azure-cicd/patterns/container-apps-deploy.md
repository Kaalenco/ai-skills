# Pattern: Container Apps Deploy (Azure DevOps)

Update a Container App to a new image, run a pre-deploy migration job, and optionally verify with a smoke test. Covers the full deploy sequence: Key Vault secret load → ACA Job migration → Container App update.

Placeholders follow the skill naming convention (`<app>`, `<env>`, `<region>`). Replace with concrete values — e.g. `<app>` = `myapp`, `<env>` = `dev`, `<region>` = `ne` → `Azure-SC-myapp-dev`, `myappne.azurecr.io`.

## Container App — image update

The deployment step is a single `az containerapp update` call. Container Apps performs a zero-downtime revision swap automatically.

```yaml
- task: AzureCLI@2
  displayName: Deploy API
  inputs:
    azureSubscription: Azure-SC-<app>-<env>    # literal — never from a variable group; see Notes
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      az containerapp update \
        --name $(appName) \
        --resource-group $(resourceGroupApi) \
        --image <app><region>.azurecr.io/<app>-api:$(Build.BuildId) \
        --output none
```

## ACA Job — migration runner (pre-deploy)

Run a Container App Job before the API update to apply database migrations. The pattern: update the job image, start an execution with ephemeral env vars, poll until done, then fetch stdout from Log Analytics.

```yaml
- task: AzureKeyVault@2
  displayName: Load connection strings from Key Vault
  inputs:
    azureSubscription: Azure-SC-<app>-<env>    # literal — never from a variable group; see Notes
    KeyVaultName: <app>-<env>-<region>-kv
    SecretsFilter: db-connection
    RunAsPreJob: false

- task: AzureCLI@2
  displayName: Run database migrations
  inputs:
    azureSubscription: Azure-SC-<app>-<env>
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      set -euo pipefail

      # az containerapp job update --image is broken in CLI ≤2.85 — image never reaches the PATCH body.
      # Workaround: read the current template, patch with jq, push via az rest. See Notes.
      NEW_IMAGE="<app><region>.azurecr.io/<app>-db:$(Build.BuildId)"
      echo "Updating $(dbJobName) image to: $NEW_IMAGE"
      SUB_ID=$(az account show --query id --output tsv)
      UPDATED_TEMPLATE=$(az containerapp job show \
        --name "$(dbJobName)" \
        --resource-group "$(resourceGroupApi)" \
        --query "properties.template" \
        --output json | \
        jq -c --arg img "$NEW_IMAGE" '(.containers[] | .image) = $img')
      az rest \
        --method PATCH \
        --url "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$(resourceGroupApi)/providers/Microsoft.App/jobs/$(dbJobName)?api-version=2024-03-01" \
        --body "{\"properties\":{\"template\":$UPDATED_TEMPLATE}}" \
        --output none
      echo "Image updated"

      # Pass config as --env-vars, not --args — see the critical gotcha in Notes.
      # Values are ephemeral: present only in this execution record, never in the job definition.
      JOB_EXEC=$(az containerapp job start \
        --name $(dbJobName) \
        --resource-group $(resourceGroupApi) \
        --env-vars "Database__Provider=sqlserver" \
                   "ConnectionStrings__DefaultConnection=$(db-connection)" \
        --query "name" \
        --output tsv)
      echo "Execution: $JOB_EXEC"

      FINAL_STATUS="Unknown"
      for i in {1..60}; do
        STATUS=$(az containerapp job execution show \
          --name $(dbJobName) \
          --resource-group $(resourceGroupApi) \
          --job-execution-name "$JOB_EXEC" \
          --query "properties.status" \
          --output tsv)
        echo "[$i/60] $STATUS"
        if [ "$STATUS" = "Succeeded" ] || [ "$STATUS" = "Failed" ]; then
          FINAL_STATUS="$STATUS"
          break
        fi
        sleep 10
      done

      echo "Fetching container logs for $JOB_EXEC (waiting 30s for Log Analytics ingestion)"
      sleep 30

      ENV_ID=$(az containerapp job show \
        --name "$(dbJobName)" \
        --resource-group "$(resourceGroupApi)" \
        --query "properties.environmentId" \
        --output tsv)

      WORKSPACE_ID=$(az containerapp env show \
        --ids "$ENV_ID" \
        --query "properties.appLogsConfiguration.logAnalyticsConfiguration.customerId" \
        --output tsv)

      az monitor log-analytics query \
        --workspace "$WORKSPACE_ID" \
        --analytics-query "ContainerAppConsoleLogs_CL | where ContainerJobExecutionName_s == '$JOB_EXEC' | project TimeGenerated, Log_s | order by TimeGenerated asc | limit 200" \
        --output table \
        || echo "(Log Analytics query failed — check workspace permissions or table name)"

      [ "$FINAL_STATUS" = "Succeeded" ] && { echo "Migrations applied"; exit 0; }
      [ "$FINAL_STATUS" = "Failed" ]    && { echo "Migration job failed"; exit 1; }
      echo "Migration timed out after 10 minutes"; exit 1
```

## Smoke test

Run after the deployment stage to verify the new revision is serving traffic. ACA revision activation can take up to 60 seconds — the loop retries before failing.

```yaml
- stage: SmokeTest
  displayName: Smoke Test
  dependsOn: DeployProd
  variables:
  - group: <app>-prod-vars
  jobs:
  - job: SmokeTest
    displayName: Verify deployment
    pool:
      vmImage: ubuntu-latest
    steps:
    - task: AzureCLI@2
      displayName: Resolve API hostname
      inputs:
        azureSubscription: Azure-SC-<app>-prod
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          FQDN=$(az containerapp show \
            --name $(appName) \
            --resource-group $(resourceGroupApi) \
            --query "properties.configuration.ingress.fqdn" \
            --output tsv)
          echo "API FQDN: $FQDN"
          echo "##vso[task.setvariable variable=API_FQDN]$FQDN"

    - script: |
        set -euo pipefail
        BASE="https://$(API_FQDN)"
        for i in {1..6}; do
          echo "=== Attempt $i ==="
          HTTP=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 10 "$BASE/health")
          [ "$HTTP" = "200" ] && echo "  -> $HTTP OK" && exit 0
          echo "  -> $HTTP (retrying in 10s)"
          sleep 10
        done
        echo "Smoke test failed after 60 seconds"; exit 1
      displayName: Verify health endpoint
```

## Notes

### Critical: `--args` vs `--env-vars` for ACA Jobs

`az containerapp job start --args` is implemented with Python argparse `nargs='+'`. Argparse stops collecting values at the first token beginning with `--`, treating it as a new CLI flag. Passing application CLI flags this way — e.g. `--args "--database" "sqlserver"` — silently drops all values from the first `--`-prefixed token onward:

```
ERROR: unrecognized arguments: --database sqlserver --connection-string <value>
```

**Always use `--env-vars KEY=VALUE` to pass runtime config to a job execution.** Keys are plain identifiers (no leading `--`), so argparse collects them all. The values are ephemeral — stored only in the RBAC-protected execution record, never written to the persistent job definition.

### .NET environment variable naming convention

The .NET Generic Host maps environment variables to config keys using `__` as the section separator:

| Environment variable | Config key |
|---|---|
| `Database__Provider` | `builder.Configuration["Database:Provider"]` |
| `ConnectionStrings__DefaultConnection` | `builder.Configuration.GetConnectionString("DefaultConnection")` |

### `azureSubscription` must be a literal value

Azure DevOps validates service connection references before expanding variable groups. If `azureSubscription` is sourced from a variable group, validation fails with "service connection could not be found". Hardcode the connection name directly in the YAML.

### `az containerapp job update --image` CLI bug (≤2.85.0)

`az containerapp job update --image ... --container-name ...` produces:

```
ERROR: (ContainerAppImageRequired) Container with name '<job-name>' must have an 'Image' property specified.
```

The CLI sends a PATCH where the container object is present but the `image` field is missing — regardless of whether `--container-name` is supplied. The Azure API correctly rejects it. Both forms of the command fail:

```bash
# without --container-name — fails
az containerapp job update --name ... --image ...

# with --container-name — also fails identically
az containerapp job update --name ... --container-name ... --image ...
```

**Workaround:** bypass `az containerapp job update` entirely. Read `properties.template` from `az containerapp job show`, patch the image with `jq`, then push via `az rest PATCH`. This preserves all other template settings (volumes, env vars, scale rules) and is not affected by the CLI bug. See the YAML above for the full implementation.

### Migration job retry limit

Create migration jobs with `--replica-retry-limit 0`. Database migrations are not idempotent — retrying a partially-applied migration can corrupt the schema. A failed migration must be investigated and resolved manually before the next deployment.

### Log Analytics query timing

Container stdout/stderr reaches Log Analytics 30–90 seconds after the container exits. The 30-second sleep before querying is a minimum — if the output is empty, the ingestion delay exceeded 30 seconds. The `|| echo "..."` guard prevents a failed query from overriding the job's exit code.

### Job creation recovery

If `az containerapp job create` fails partway through (e.g. due to a validation error), the resource may exist in a broken state. A second `create` attempt errors with "identity already assigned". Delete and recreate:

```bash
az containerapp job delete --name my-app-db-dev --resource-group my-app-dev-rg --yes
```

### Library group pipeline permissions

After creating variable groups in Library, explicitly grant each pipeline access: **Library → variable group → Pipeline permissions → +**. Without this, the pipeline fails at queue time when resolving the group's variables.
