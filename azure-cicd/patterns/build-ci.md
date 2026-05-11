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

### ⚠️ Pitfall: do not pass `--results-directory` when `publishTestResults: true`

`DotNetCoreCLI@2` automatically injects `--results-directory $(Agent.TempDirectory)` when `publishTestResults: true`. Adding a second `--results-directory` in the `arguments` field causes dotnet test to receive the flag twice, exit with code 1, and print its help text instead of running tests. The symptom looks like a misconfigured command rather than a duplicate-argument error, which makes it easy to miss.

When collecting coverage alongside `publishTestResults: true`, omit `--results-directory` entirely and point downstream steps at `$(Agent.TempDirectory)`:

```yaml
- task: DotNetCoreCLI@2
  displayName: Run unit tests
  inputs:
    command: test
    projects: 'src/**/*.UnitTests.csproj'
    arguments: '--no-build --configuration $(buildConfiguration) --collect:"XPlat Code Coverage"'
    publishTestResults: true

- task: PublishCodeCoverageResults@2
  displayName: Publish code coverage
  condition: always()
  inputs:
    summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'
```

### ⚠️ Pitfall: `feedsToUse: config` with an empty nuget.config silently drops nuget.org

When `feedsToUse: config` is set on the restore step, NuGet uses **only** the sources listed in the specified `nuget.config` — the global/machine-level sources (including nuget.org) are ignored. If the file exists but has no `<packageSources>` entries, restore fails with `NU1100: Unable to resolve` even for packages that exist on nuget.org.

Always declare every required source explicitly in the `nuget.config` used by the pipeline:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" protocolVersion="3" />
    <add key="vault-packages" value="https://pkgs.dev.azure.com/.../_packaging/vault-packages/nuget/v3/index.json" />
  </packageSources>
</configuration>
```

The symptom is `NU1100` errors for well-known public packages (e.g. `Microsoft.Extensions.*`) on specific TFMs — not `NU1301` (feed unreachable) or `NU1202` (incompatible framework).
