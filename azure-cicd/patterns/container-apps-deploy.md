# Pattern: Container Apps Deploy (Azure DevOps)

Update a Container App to a new image, run a pre-deploy migration job, and optionally verify with a smoke test. Covers the full deploy sequence: sync Key Vault references to ACA → ACA Job migration → Container App update.

Placeholders follow the skill naming convention (`<app>`, `<env>`, `<region>`). Replace with concrete values — e.g. `<app>` = `myapp`, `<env>` = `dev`, `<region>` = `ne` → `Azure-SC-myapp-dev`, `myappne.azurecr.io`.

## Sync Key Vault references to ACA (pre-deploy)

Run this step first when secrets are stored in Key Vault and referenced by the Container App and ACA Job via `secretref:`. It registers the Key Vault references on both resources — idempotent, safe to run on every deploy.

Requires two variable group entries: `keyVaultUri` (e.g. `https://<app>-<env>-<region>-kv.vault.azure.net`) and `managedIdentityId` (full ARM resource ID of the user-assigned managed identity — retrieve with `az identity show ... --query id`).

```yaml
- task: AzureCLI@2
  displayName: Sync Key Vault secrets to ACA
  inputs:
    azureSubscription: Azure-SC-<app>-<env>
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      set -euo pipefail
      KV_BASE="$(keyVaultUri)/secrets"
      IDENTITY="$(managedIdentityId)"

      az containerapp job secret set \
        --name $(dbJobName) \
        --resource-group $(resourceGroupApi) \
        --secrets \
          "db-vault-connection=keyvaultref:$KV_BASE/db-vault-connection,identityref:$IDENTITY" \
          "db-identity-connection=keyvaultref:$KV_BASE/db-identity-connection,identityref:$IDENTITY"

      az containerapp secret set \
        --name $(appName) \
        --resource-group $(resourceGroupApi) \
        --secrets \
          "db-vault-connection=keyvaultref:$KV_BASE/db-vault-connection,identityref:$IDENTITY" \
          "db-identity-connection=keyvaultref:$KV_BASE/db-identity-connection,identityref:$IDENTITY"
```

The migration job start and container app update then reference secrets by name:

```bash
# Migration job — secretref: in --env-vars resolves against secrets defined on the job
--env-vars "ConnectionStrings__DefaultConnection=secretref:db-vault-connection"

# Container App — secretref: in --set-env-vars resolves against secrets defined on the app
--set-env-vars "ConnectionStrings__DefaultConnection=secretref:db-vault-connection"
```

Secret *values* never appear in the pipeline, in pipeline logs, or in the ACA revision configuration. ACA fetches them from Key Vault at runtime using the managed identity.

**Prerequisite:** the managed identity must have **Key Vault Secrets User** role on the Key Vault. Without it the sync step succeeds (it only stores the reference URI) but ACA will fail to resolve the value at runtime with `SecretValueRetrievalFailed`.

**ACA Jobs caveat:** `az containerapp job secret set` does not reliably support `keyvaultref:` in all CLI versions (known to fail with `ContainerAppSecretKeyVaultUrlInvalid / from a different cloud` even when the URL and identity are correct). For migration jobs and other short-lived runners, prefer the `AzureKeyVault@2` task to load secrets as pipeline variables and pass them as plain `--env-vars` to `az containerapp job start`. Job execution env vars are ephemeral — they exist only in the execution record, not in the persistent job definition — so this is an acceptable trade-off.

---

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

      # Pass --image explicitly: az containerapp job start with --env-vars constructs an
      # execution-override template with a container entry but no image field, triggering
      # ContainerAppImageRequired (CLI ≤2.85.0 bug). --image includes it in the same body.
      NEW_IMAGE="<app><region>.azurecr.io/<app>-db:$(Build.BuildId)"
      JOB_EXEC=$(az containerapp job start \
        --name $(dbJobName) \
        --resource-group $(resourceGroupApi) \
        --image "$NEW_IMAGE" \
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

      echo "##vso[task.setvariable variable=dbJobExec]$JOB_EXEC"
      [ "$FINAL_STATUS" = "Succeeded" ] && { echo "Migrations applied"; exit 0; }
      [ "$FINAL_STATUS" = "Failed" ]    && { echo "Migration job failed"; exit 1; }
      echo "Migration timed out after 10 minutes"; exit 1

- task: AzureCLI@2
  displayName: Show migration logs
  condition: always()
  inputs:
    azureSubscription: Azure-SC-<app>-<env>
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      az containerapp job logs show \
        --name $(dbJobName) \
        --resource-group $(resourceGroupApi) \
        --execution "$(dbJobExec)" \
        --container "$(dbJobName)" \
        --format text \
        --tail 300 \
        || echo "(Log retrieval failed — az containerapp job logs show may not be available on this CLI version)"
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

### `az containerapp job start --env-vars` drops the image (CLI ≤2.85.0)

When `--env-vars` is passed, the CLI constructs an execution-override template with a container entry for the env vars but omits the `image` field. The ARM API rejects it:

```
ERROR: (ContainerAppImageRequired) Container with name '<job-name>' must have an 'Image' property specified.
```

**Fix:** pass `--image <image>:<tag>` explicitly to `az containerapp job start`. The flag includes the image in the same execution body, satisfying the ARM API. No PATCH to the job definition is needed — the execution-level image overrides the stored definition for that run.

Note: `az containerapp job update --image` has a separate but similar bug (image never reaches the PATCH body regardless of `--container-name`). Avoid `az containerapp job update` for image updates entirely; rely on `--image` at start time.

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
