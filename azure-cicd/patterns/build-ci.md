# Pattern: CI — Build & Test (Azure DevOps)

Restore, build, run unit tests, and upload a `.trx` artifact. Covers multi-target .NET projects.

## YAML

```yaml
trigger:
  branches:
    include: [trunk, main]
  paths:
    exclude: [docs/**, '*.md']

pr:
  branches:
    include: [trunk, main]

pool:
  vmImage: 'windows-latest'

variables:
  buildConfiguration: 'Release'
  dotnetVersion: '9.0.x'

steps:
- task: UseDotNet@2
  displayName: Use .NET $(dotnetVersion)
  inputs:
    version: $(dotnetVersion)

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
    arguments: '--no-restore --configuration $(buildConfiguration)'

- task: DotNetCoreCLI@2
  displayName: Run unit tests
  inputs:
    command: test
    projects: 'src/**/*.UnitTests.csproj'
    arguments: '--no-build --configuration $(buildConfiguration)'
    publishTestResults: true

- task: DotNetCoreCLI@2
  displayName: Publish
  inputs:
    command: publish
    publishWebProjects: false
    projects: 'src/MyApp/*.csproj'
    arguments: '--no-build --configuration $(buildConfiguration) --output $(Build.ArtifactStagingDirectory)'

- task: PublishBuildArtifacts@1
  displayName: Publish artifact
  inputs:
    PathtoPublish: $(Build.ArtifactStagingDirectory)
    ArtifactName: drop
```

## Notes

- `publishTestResults: true` on the test step uploads `.trx` results to the pipeline UI automatically.
- For multi-target projects, pin `--framework` to a single TFM for CI speed; run the full matrix in a separate matrix job if needed.
- Exclude `docs/**` and markdown from the path trigger to avoid spurious runs on documentation edits.
