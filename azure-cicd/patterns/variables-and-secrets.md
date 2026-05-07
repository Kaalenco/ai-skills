# Pattern: Variable Groups & Key Vault Secrets (Azure DevOps)

Reference shared variables and Key Vault-linked secrets without hardcoding values in YAML.

## Variable group reference

```yaml
variables:
- group: 'my-app-dev-vars'       # Azure DevOps Library group
- name: buildConfiguration
  value: 'Release'
```

Reference secrets in steps as `$(SecretName)` — identical syntax to regular variables.

## Key Vault-linked group

Key Vault linking is configured in **Pipelines → Library → Variable Groups**, not in YAML:

1. Create a variable group in Library
2. Enable **Link secrets from an Azure Key Vault**
3. Select the Key Vault and authorize the service connection
4. Select which secrets to expose

The pipeline YAML just references the group name. No secrets appear in the YAML file.

## Stage-scoped variables

```yaml
stages:
- stage: DeployDev
  variables:
  - group: 'my-app-dev-vars'
  jobs:
  - deployment: Deploy
    ...

- stage: DeployProd
  variables:
  - group: 'my-app-prod-vars'
  jobs:
  - deployment: Deploy
    ...
```

Scoping variable groups to a stage prevents the prod Key Vault from being accessed during the Dev stage.

## Runtime parameters (not secrets)

For non-secret configuration that varies per run, prefer `parameters` over variables:

```yaml
parameters:
- name: environment
  displayName: Target environment
  type: string
  default: dev
  values: [dev, test, prod]

stages:
- stage: Deploy_${{ parameters.environment }}
  ...
```

## Notes

- Never set `isSecret: true` on a variable defined inline in YAML — the value would still be visible in the file. Use Library groups for all secrets.
- Pipeline variables set via the Azure DevOps UI override YAML variables of the same name, which is useful for one-off overrides without changing the file.
- Key Vault-linked groups require a service connection with **Get** and **List** permissions on the vault's secrets.
