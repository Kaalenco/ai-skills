# Pattern: Docker Build & Push (Azure DevOps)

Build a Docker image and push it to Azure Container Registry via a service connection.

## YAML

```yaml
variables:
  imageRepository: 'my-app'
  containerRegistry: 'ACR-ServiceConnection'
  dockerfilePath: '**/Dockerfile'
  tag: $(Build.BuildId)

steps:
- task: Docker@2
  displayName: Build image
  inputs:
    containerRegistry: $(containerRegistry)
    repository: $(imageRepository)
    command: build
    Dockerfile: $(dockerfilePath)
    tags: |
      $(tag)
      latest

- task: Docker@2
  displayName: Push image
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/trunk'))
  inputs:
    containerRegistry: $(containerRegistry)
    repository: $(imageRepository)
    command: push
    tags: |
      $(tag)
      latest
```

## Multi-stage with image reuse

Build once, deploy the same image across environments using the build ID as the stable tag:

```yaml
stages:
- stage: Build
  jobs:
  - job: BuildImage
    steps:
    - task: Docker@2
      displayName: Build and push
      inputs:
        containerRegistry: 'ACR-ServiceConnection'
        repository: 'my-app'
        command: buildAndPush
        Dockerfile: '**/Dockerfile'
        tags: $(Build.BuildId)

- stage: DeployDev
  dependsOn: Build
  jobs:
  - deployment: Deploy
    environment: 'dev'
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureWebAppContainer@1
            displayName: Deploy container to App Service
            inputs:
              azureSubscription: 'Azure-ServiceConnection-Dev'
              appName: 'my-app-dev'
              containers: 'myacr.azurecr.io/my-app:$(Build.BuildId)'
```

## Notes

- The `containerRegistry` value is the **service connection name** in Azure DevOps, not the ACR login server URL.
- Tag with `$(Build.BuildId)` (stable, numeric) rather than `$(Build.SourceVersion)` (40-char SHA) for readability in ACR.
- The `latest` tag is convenient locally but makes rollback harder — always also push the numbered tag.
- For build-arg secrets (e.g., private NuGet feed credentials), use `--build-arg` via a `Bash` step rather than embedding in the Dockerfile.
