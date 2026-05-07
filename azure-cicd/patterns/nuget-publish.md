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
