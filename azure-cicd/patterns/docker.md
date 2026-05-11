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

## Gotcha: private NuGet feeds in Docker integration tests

When a `dotnet restore` runs inside a Docker build (e.g., in an integration-test Dockerfile) and the project references a private Azure Artifacts feed, the restore will silently fall back to nuget.org and fail with `NU1102` — because the Dockerfile doesn't have the project's `nuget.config` or any feed credentials.

**Two symptoms that confirm this is the problem:**
- Error says `Found N version(s) in nuget.org` rather than in your private feed.
- The package version exists in your feed but not on nuget.org.

**Fix — three files:**

**1. Dockerfile** — add the BuildKit syntax directive, copy `nuget.config`, and write/delete credentials inside one `RUN --mount=type=secret` step so they are never committed to a layer:

```dockerfile
# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:10.0
WORKDIR /src

COPY MyApp.sln .
COPY nuget.config .                          # <-- required; defines the private feed URL
COPY MyApp/MyApp.csproj MyApp/
COPY MyApp.Tests/MyApp.Tests.csproj MyApp.Tests/

# Credentials written from secret, deleted in the same layer — never baked in.
RUN --mount=type=secret,id=azure_token \
    mkdir -p /root/.nuget/NuGet && \
    printf '<configuration><packageSourceCredentials><my-feed><add key="Username" value="AzureDevOps" /><add key="ClearTextPassword" value="%s" /></my-feed></packageSourceCredentials></configuration>' \
      "$(cat /run/secrets/azure_token)" \
      > /root/.nuget/NuGet/NuGet.Config && \
    dotnet restore MyApp.Tests/MyApp.Tests.csproj && \
    rm /root/.nuget/NuGet/NuGet.Config

COPY . .
CMD ["dotnet", "test", "MyApp.Tests/MyApp.Tests.csproj", "--no-restore"]
```

Replace `my-feed` with the `key` name used in `nuget.config`'s `<packageSources>` block.

**2. docker-compose.yml** — expose the secret from the environment and pass it to the build:

```yaml
services:
  integration-tests:
    build:
      context: .
      dockerfile: Dockerfile.integration
      secrets:
        - azure_token
    # ... rest of service config

secrets:
  azure_token:
    environment: SYSTEM_ACCESSTOKEN   # read from the shell environment
```

**3. Pipeline** — map `System.AccessToken` to `SYSTEM_ACCESSTOKEN` on the `docker compose` step (Azure DevOps does not expose it automatically):

```yaml
- script: |
    docker compose -f src/docker-compose.integration.yml up \
      --build --exit-code-from integration-tests --abort-on-container-exit
  displayName: Run integration tests
  env:
    SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

**Why BuildKit secret over `--build-arg`:**
`ARG` values are recorded in `docker history` and baked into the image metadata; `--mount=type=secret` is never stored anywhere in the image. For ephemeral CI images that are never pushed, `ARG` is an acceptable pragmatic trade-off, but the secret mount approach is preferred.

**Required feed permission:** the pipeline's Build Service account (e.g., `<Project> Build Service (<org>)`) must have **Contributor** role on the Artifacts feed. Set this in Artifacts → `<feed>` → Feed settings → Permissions.
