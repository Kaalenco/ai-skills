# Pattern: Docker Build & Push (Azure DevOps)

Build a Docker image and push it to Azure Container Registry via a service connection.

## YAML

```yaml
variables:
  imageRepository: '<app>-api'         # follows naming convention
  containerRegistry: 'ACR-SC-<app>'    # service connection name — literal, never from variable group
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
    tags: $(tag)

- task: Docker@2
  displayName: Push image
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/trunk'))
  inputs:
    containerRegistry: $(containerRegistry)
    repository: $(imageRepository)
    command: push
    tags: $(tag)
```

## Multi-stage with image reuse

Separate the .NET build/test from the Docker push into distinct stages. This keeps build failures fast and allows a `CodeAnalysis` (or other) stage to run in parallel with `Push` before deploy.

```yaml
stages:
- stage: Build
  displayName: Build & Test
  jobs:
  - job: BuildAndTest
    pool:
      vmImage: ubuntu-latest
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
      displayName: Run unit tests
      inputs:
        command: test
        projects: 'src/**/*.UnitTests.csproj'
        arguments: '--no-build --configuration Release'
        publishTestResults: true

- stage: Push
  displayName: Push images
  dependsOn: Build
  jobs:
  - job: PushImages
    pool:
      vmImage: ubuntu-latest
    steps:
    - task: AzureCLI@2
      displayName: Log in to ACR
      inputs:
        azureSubscription: ACR-SC-<app>    # literal — never from a variable group
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: az acr login --name <app><region>.azurecr.io

    - script: |
        DOCKER_BUILDKIT=1 docker build \
          --secret id=azure_token,env=SYSTEM_ACCESSTOKEN \
          --file src/MyApp/Dockerfile \
          --tag <app><region>.azurecr.io/<app>-api:$(Build.BuildId) \
          src
        docker push <app><region>.azurecr.io/<app>-api:$(Build.BuildId)
      displayName: Build and push image
      env:
        SYSTEM_ACCESSTOKEN: $(System.AccessToken)

- stage: DeployDev
  displayName: Deploy to Dev
  dependsOn: Push    # or [Push, CodeAnalysis] if a parallel analysis stage exists
  variables:
  - group: <app>-dev-vars
  jobs:
  - deployment: Deploy
    environment: <app>-dev
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureWebAppContainer@1
            displayName: Deploy container to App Service
            inputs:
              azureSubscription: Azure-SC-<app>-dev    # literal — never from a variable group
              appName: $(appName)
              containers: '<app><region>.azurecr.io/<app>-api:$(Build.BuildId)'
```

### Parallel Push + CodeAnalysis

When the pipeline also has a `CodeAnalysis` stage (coverage, complexity), both it and `Push` can depend on `Build` and run in parallel. `DeployDev` then waits for both:

```
Build  ──►  Push          ──►  DeployDev
       ──►  CodeAnalysis  ──►
```

```yaml
- stage: Push
  dependsOn: Build
  ...

- stage: CodeAnalysis
  dependsOn: Build
  ...

- stage: DeployDev
  dependsOn:
  - Push
  - CodeAnalysis
  ...
```

## Notes

- The `containerRegistry` value is the **service connection name** in Azure DevOps, not the ACR login server URL. Follows the convention `ACR-SC-<app>` — must be a literal in YAML.
- Tag with `$(Build.BuildId)` (stable, numeric) rather than `$(Build.SourceVersion)` (40-char SHA) for readability in ACR.
- Do not push a `latest` tag for deployed images — it makes rollback impossible. Use the build ID tag only.

## Gotcha: wrong runtime base image (`runtime` vs `aspnet`)

`mcr.microsoft.com/dotnet/runtime` only ships `Microsoft.NETCore.App`. Any project that references a `Microsoft.AspNetCore.*` package — including `Microsoft.AspNetCore.Identity.EntityFrameworkCore`, `Microsoft.AspNetCore.Diagnostics.EntityFrameworkCore`, or any other ASP.NET Core library — pulls in the `Microsoft.AspNetCore.App` shared framework. At container start you'll see:

```
Framework: 'Microsoft.AspNetCore.App', version 'X.Y.Z' (x64)
No frameworks were found.
```

This happens even for console apps and migration runners that are not web services.

**Rule:**
- Use `mcr.microsoft.com/dotnet/aspnet:<version>` whenever the project references any `Microsoft.AspNetCore.*` package.
- Use `mcr.microsoft.com/dotnet/runtime:<version>` only for projects with zero ASP.NET Core dependencies (pure console/worker with only `Microsoft.Extensions.*`).
- Use `mcr.microsoft.com/dotnet/runtime-deps:<version>` for self-contained single-file publishes only.

When in doubt, use `aspnet` — it is a superset of `runtime` and the size difference is small (~30 MB).

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
