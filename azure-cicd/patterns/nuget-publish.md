# Pattern: NuGet Publish (Azure DevOps)

Pack and push a NuGet package. Separates pack from push; push is gated on a push to the main branch.

## YAML

```yaml
- task: DotNetCoreCLI@2
  displayName: Pack NuGet
  inputs:
    command: pack
    packagesToPack: 'src/**/*.csproj'
    versioningScheme: byEnvVar
    versionEnvVar: BUILD_BUILDNUMBER
    outputDir: '$(Build.ArtifactStagingDirectory)'

- task: NuGetAuthenticate@1
  displayName: Authenticate NuGet

- task: DotNetCoreCLI@2
  displayName: Push NuGet
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/trunk'))
  inputs:
    command: push
    packagesToPush: '$(Build.ArtifactStagingDirectory)/**/*.nupkg'
    nuGetFeedType: external
    publishFeedCredentials: 'NuGet-Feed-ServiceConnection'
```

## Notes

- `NuGetAuthenticate@1` is required before push even when using a service connection.
- The `condition` on the push step prevents publishing from PR builds.
- For nuget.org, the `publishFeedCredentials` service connection is of type **NuGet** and stores the API key.

### ⚠️ Pitfall: `publishVstsFeed` does not expand pipeline variables

The `DotNetCoreCLI@2` `publishVstsFeed` task input does not reliably expand `$(VARIABLE)` references. If the variable is not defined, the literal string (e.g., `$(MY_FEED)`) is URL-encoded and sent as the feed ID, producing `TF1600011: The feed with ID '$(MY_FEED)' doesn't exist`. Use `NuGetAuthenticate@1` + a script step to construct the URL from `env:` variables instead.

### ⚠️ Pitfall: `find -exec cmd \;` does not reliably fail the step

`find -exec dotnet nuget push {} \;` can exit 0 even when the push command fails. Use `set -euo pipefail` with an explicit loop instead — `set -e` exits the script immediately on any non-zero return code:

```yaml
- script: |
    set -euo pipefail
    while IFS= read -r -d '' pkg; do
      dotnet nuget push "$pkg" \
        --source "$FEED_URL" \
        --api-key AzureArtifacts \
        --skip-duplicate
    done < <(find "$(Build.ArtifactStagingDirectory)" -name "*.nupkg" -print0)
  displayName: Push NuGet package
  env:
    FEED_URL: $(AZURE_ARTIFACTS_FEED_URL)
```

### ⚠️ Pitfall: avoid variable groups for publish configuration — prefer pipeline artifacts and dynamic feed URL

Using a Library variable group to pass `CSPROJ_PATH` or the feed URL to the Publish stage causes a hard pipeline validation error before any stage runs:

> _The pipeline is not valid. Stage Publish: Variable group `my-group` could not be found._

The group must be manually created in **Pipelines → Library** and authorized for each pipeline — a friction point that is easy to forget and impossible to detect until the pipeline runs.

**Preferred pattern (no variable group needed):**

1. Upload the `.nupkg` as a pipeline artifact in the Build stage (reuse the package already on disk if `GeneratePackageOnBuild=true`).
2. In the Publish stage, set `checkout: none`, download the artifact, and construct the feed URL dynamically from predefined variables.

```yaml
# Build stage — after dotnet build
- task: CopyFiles@2
  displayName: Stage NuGet packages
  inputs:
    SourceFolder: src
    Contents: '**/*.nupkg'
    TargetFolder: '$(Build.ArtifactStagingDirectory)/packages'

- task: PublishPipelineArtifact@1
  displayName: Upload NuGet packages
  inputs:
    targetPath: '$(Build.ArtifactStagingDirectory)/packages'
    artifact: nuget-packages

# Publish stage — no restore/build/pack needed
- checkout: none

- task: DownloadPipelineArtifact@2
  displayName: Download NuGet packages
  inputs:
    artifact: nuget-packages
    targetPath: '$(Pipeline.Workspace)/packages'

- task: NuGetAuthenticate@1
  displayName: Authenticate to Azure Artifacts

- script: |
    set -euo pipefail
    ORG=$(echo "$COLLECTION_URI" | sed 's|https://dev.azure.com/||; s|/$||')
    PROJECT_ENCODED="${TEAM_PROJECT// /%20}"
    FEED_URL="https://pkgs.dev.azure.com/${ORG}/${PROJECT_ENCODED}/_packaging/${FEED_NAME}/nuget/v3/index.json"
    echo "Pushing to: $FEED_URL"
    while IFS= read -r -d '' pkg; do
      dotnet nuget push "$pkg" \
        --source "$FEED_URL" \
        --api-key AzureArtifacts \
        --skip-duplicate
    done < <(find "$(Pipeline.Workspace)/packages" -name "*.nupkg" -print0)
  displayName: Push NuGet package
  env:
    COLLECTION_URI: $(System.CollectionUri)
    TEAM_PROJECT: $(System.TeamProject)
    FEED_NAME: vault-packages   # or a top-level YAML variable
```

Declare `artifactsFeedName` as a top-level YAML variable (not in a group) so it is visible in the file and requires no Library setup.

### ⚠️ Pitfall: build service account needs Contributor on the feed

A 403 `lacks permission to complete this action. You need to have 'AddPackage'` means the pipeline's build service identity does not have the right feed permission. Fix in Azure DevOps UI:
> **Artifacts → [feed] → Feed settings → Permissions → Add users/groups**
> Add `[Project Name] Build Service ([Org Name])` with role **Contributor**.

### Version-conflict detection (skip if already published)

Use a script step to query the NuGet flat-container API before pushing:

```yaml
- bash: |
    VERSION=$(grep -oP '(?<=<PackageVersion>)[^<]+' "$CSPROJ_PATH")
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      https://api.nuget.org/v3-flatcontainer/$PACKAGE_ID/$VERSION/$PACKAGE_ID.$VERSION.nupkg)
    if [ "$STATUS" = "200" ]; then
      echo "##vso[task.setvariable variable=AlreadyPublished]true"
    fi
  displayName: Check version conflict

- task: DotNetCoreCLI@2
  displayName: Push NuGet
  condition: and(succeeded(), ne(variables['AlreadyPublished'], 'true'), eq(variables['Build.SourceBranch'], 'refs/heads/trunk'))
  inputs:
    command: push
    packagesToPush: '$(Build.ArtifactStagingDirectory)/**/*.nupkg'
    nuGetFeedType: external
    publishFeedCredentials: 'NuGet-Feed-ServiceConnection'
```
