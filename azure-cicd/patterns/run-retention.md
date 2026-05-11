# Pattern: Run Retention Leases (Azure DevOps)

Controls how long pipeline runs are retained using the Azure DevOps retention lease REST API.
The `retention` root-level key is **not** a valid Azure DevOps YAML property — leases are the only YAML-level mechanism.

## Recommended retention values

| Scenario | `daysValid` |
|---|---|
| Failed run | project default — no lease created |
| Successful PR run | 3 |
| Successful branch run | 10 |
| Run that published a NuGet package | 365 |

There is no enforced API minimum for `daysValid`. The `ArgumentOutOfRangeException: DaysValid` error means the field was missing or zero — caused by passing `retainUntil` (not a valid field) instead of `daysValid`.

## YAML — lease step

```yaml
- pwsh: |
    $uri = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)$($env:SYSTEM_TEAMPROJECTID)/_apis/build/retention/leases?api-version=7.1"
    $body = ConvertTo-Json -Compress -InputObject @(
      @{
        ownerId         = "Pipeline:$($env:SYSTEM_DEFINITIONID)"
        definitionId    = [int]$env:SYSTEM_DEFINITIONID
        runId           = [int]$env:BUILD_BUILDID
        daysValid       = <DAYS>
        protectPipeline = $false
      }
    )
    Invoke-RestMethod -Method Post -Uri $uri `
      -Headers @{ Authorization = "Bearer $($env:SYSTEM_ACCESSTOKEN)" } `
      -ContentType 'application/json' -Body $body
  displayName: Retain run for <DAYS> days
  env:
    SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

The field is `daysValid` (int) — **not** `retainUntil`.

## Retention strategy: tiered by outcome

Multiple leases on the same run are additive — the run is kept until the last lease expires. Use a distinct `ownerId` suffix per lease so they don't overwrite each other.

```
Failed run          → project default (no lease created)
Successful PR run   → lease, daysValid = 3
Successful CI run   → lease, daysValid = 10
Published NuGet run → lease, ownerId suffix ":published", daysValid = 365
```

## Prerequisites

The pipeline job must have access to the OAuth token. Enable it per-step via `env: SYSTEM_ACCESSTOKEN: $(System.AccessToken)` (shown above), or enable **Allow scripts to access the OAuth token** in the pipeline settings UI. The build service account must have the **Edit build pipeline** permission on the project.
