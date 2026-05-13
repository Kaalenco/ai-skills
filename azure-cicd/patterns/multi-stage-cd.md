# Pattern: Multi-Stage CD (Azure DevOps)

Build once, deploy through Dev → Prod. Uses `deployment` job type so environment approval gates work.

## YAML

```yaml
stages:
- stage: Build
  displayName: Build & Test
  jobs:
  - job: Build
    pool:
      vmImage: 'windows-latest'
    steps:
    - task: DotNetCoreCLI@2
      displayName: Restore packages
      inputs:
        command: restore
        projects: 'src/**/*.csproj'

    - task: DotNetCoreCLI@2
      displayName: Build
      inputs:
        command: build
        projects: 'src/**/*.csproj'
        arguments: '--no-restore --configuration Release'

    - task: DotNetCoreCLI@2
      displayName: Publish
      inputs:
        command: publish
        publishWebProjects: false
        projects: 'src/MyApp/*.csproj'
        arguments: '--no-build --configuration Release --output $(Build.ArtifactStagingDirectory)'

    - task: PublishBuildArtifacts@1
      displayName: Publish artifact
      inputs:
        PathtoPublish: $(Build.ArtifactStagingDirectory)
        ArtifactName: drop

- stage: DeployDev
  displayName: Deploy to Dev
  dependsOn: Build
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/trunk'))
  variables:
  - group: <app>-dev-vars
  jobs:
  - deployment: Deploy
    environment: <app>-dev
    pool:
      vmImage: 'windows-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureWebApp@1
            displayName: Deploy to App Service
            inputs:
              azureSubscription: Azure-SC-<app>-dev    # literal — never from a variable group
              appType: webApp
              appName: $(appName)
              package: '$(Pipeline.Workspace)/drop/**/*.zip'

- stage: DeployProd
  displayName: Deploy to Production
  dependsOn: DeployDev
  condition: succeeded()
  variables:
  - group: <app>-prod-vars
  jobs:
  - deployment: Deploy
    environment: <app>-prod
    pool:
      vmImage: 'windows-latest'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureWebApp@1
            displayName: Deploy to App Service
            inputs:
              azureSubscription: Azure-SC-<app>-prod    # literal — never from a variable group
              appType: webApp
              appName: $(appName)
              package: '$(Pipeline.Workspace)/drop/**/*.zip'
```

## Notes

- **Environment approval gates** are configured in the Azure DevOps **Environments** UI, not in YAML. The `environment: <app>-prod` key links the deployment to that environment's approval policy.
- `$(Pipeline.Workspace)/drop` resolves to the artifact published in the Build stage. The artifact name (`drop`) must match `PublishBuildArtifacts.ArtifactName`.
- Use separate service connections per environment — never share a connection between Dev and Prod. Service connection names follow the convention `Azure-SC-<app>-<env>` and must be literal strings in the YAML (Azure DevOps validates them before expanding variable groups).
- The `condition` on `DeployDev` gates deployment to the main branch. `DeployProd` inherits this transitively via `dependsOn: DeployDev`.
- For slot-based deployments (zero-downtime), use `AzureWebApp@1` with `deployToSlotOrASE: true` and swap afterward with `AzureAppServiceManage@0`.
