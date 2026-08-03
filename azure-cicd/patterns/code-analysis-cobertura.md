# Pattern: Code Analysis — Cobertura Coverage + Cyclomatic Complexity (Azure DevOps)

Runs as a separate job after the main build. Collects Cobertura coverage via coverlet, publishes it
to the built-in Azure DevOps coverage tab, measures cyclomatic complexity with lizard, and writes a
markdown table to the pipeline summary. Reports are also uploaded as a build artifact.

The `az-code-analysis-summary.py` script (see [`scripts/az-code-analysis-summary.py`](../scripts/az-code-analysis-summary.py))
reads the Cobertura XML and lizard's CSV output and writes the combined summary table.

## Job YAML (Azure DevOps)

Drop this as a job inside a stage that already has a `Build` job, or use it standalone with its
own restore/build steps as shown here.

```yaml
- job: CodeAnalysis
  displayName: Code Analysis
  dependsOn: Build
  pool:
    vmImage: 'ubuntu-latest'
  variables:
    COVERAGE_DIR: '$(Agent.TempDirectory)'

  steps:
  - task: UseDotNet@2
    displayName: Use .NET 8.0
    inputs:
      version: 8.0.x

  - task: UseDotNet@2
    displayName: Use .NET 10.0
    inputs:
      version: 10.0.x

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
      arguments: '--no-restore'

  - task: DotNetCoreCLI@2
    displayName: Run unit tests with coverage
    inputs:
      command: test
      projects: 'src/**/*.UnitTests.csproj'
      arguments: >-
        --no-build
        --framework net8.0
        --verbosity normal
        --filter "TestCategory!=Integration"
        --collect:"XPlat Code Coverage"
    env:
      Logging__LogLevel__Default: Error

  - script: dotnet tool install --global dotnet-reportgenerator-globaltool
    displayName: Install ReportGenerator

  - script: |
      reportgenerator \
        -reports:"$(COVERAGE_DIR)/**/coverage.cobertura.xml" \
        -targetdir:reports/coverage \
        -reporttypes:"HtmlInline_AzurePipelines;Cobertura"
    displayName: Generate HTML coverage report

  - task: PublishCodeCoverageResults@2
    displayName: Publish coverage to pipeline
    condition: always()
    inputs:
      summaryFileLocation: reports/coverage/Cobertura.xml
      reportDirectory: reports/coverage

  - bash: pip install lizard
    displayName: Install lizard

  - bash: |
      mkdir -p reports/complexity
      lizard src/ \
        -x "*.UnitTests" \
        -x "*Generated.cs" \
        -x "*/Migrations/*" \
        -C 10 --html > reports/complexity/index.html
    displayName: Generate complexity report

  - bash: |
      SUMMARY_FILE="$(Agent.TempDirectory)/code-analysis-summary.md"
      PIPELINE_SUMMARY_FILE="$SUMMARY_FILE" python3 scripts/az-code-analysis-summary.py \
        --source src/ \
        --exclude "*.UnitTests" \
        --exclude "*Generated.cs" \
        --exclude "*/Migrations/*" \
        --coverage-dir $COVERAGE_DIR
      echo "##vso[task.uploadsummary]$SUMMARY_FILE"
    displayName: Write pipeline summary
    condition: always()

  - task: PublishBuildArtifacts@1
    displayName: Upload analysis reports
    condition: always()
    inputs:
      PathtoPublish: reports/
      ArtifactName: code-analysis
```

## Notes

- ReportGenerator converts the Cobertura XML to `HtmlInline_AzurePipelines` format, which Azure DevOps renders as a full interactive report directly in the **Coverage** tab — no download required. The `reportDirectory` input on `PublishCodeCoverageResults@2` is what enables this inline view.
- `COVERAGE_DIR` is set to `$(Agent.TempDirectory)` because `DotNetCoreCLI@2` always injects `--results-directory $(Agent.TempDirectory)` automatically for test runs. Do **not** add a second `--results-directory` in the `arguments` field — it causes `Option '--results-directory' expects a single argument but 2 were provided`.
- The `az-code-analysis-summary.py` script uses `sys.executable -m lizard` (not a bare `lizard` call) so it works regardless of whether the lizard executable is on `PATH`. The `lizard` bash steps still call it directly because `pip install lizard` on Ubuntu CI puts it on PATH.
- The summary script writes to `PIPELINE_SUMMARY_FILE`. The `##vso[task.uploadsummary]` command in the same step attaches that file to the pipeline summary tab.
- Variables defined in the `variables:` block are available as environment variables by the same name in `bash` steps (`$SOURCE_DIR`, `$COVERAGE_DIR`, etc.).
- `$(Agent.TempDirectory)` is a predefined Azure DevOps variable that resolves to an agent-local temp path and is cleaned up after the job.

## Adapting to a new project

- The test glob `src/**/*.UnitTests.csproj` and source root `src/` work for any repo following the `src/MyApp` / `src/MyApp.UnitTests` layout. If source lives elsewhere, adjust both the lizard command and `--source`.
- The default exclude patterns strip test projects (`*.UnitTests`), auto-generated files (`*Generated.cs`), and migration files (`*/Migrations/*`) from lizard. Pass additional `--exclude` flags for any other paths to omit; each flag takes one glob pattern.
- Change `-C 10` to adjust the CCN threshold; mirror it in `CCN_THRESHOLD` at the top of `az-code-analysis-summary.py`.
- The `--framework net8.0` flag pins coverage collection to one TFM. Change to match the lowest common target in the project.
- Remove `dependsOn: Build` if this runs as a standalone pipeline rather than after a `Build` job.

## Script reference

See [`scripts/az-code-analysis-summary.py`](../scripts/az-code-analysis-summary.py) for the full source.

**CLI options:**

| Flag | Default | Description |
|---|---|---|
| `--source` | `src` | Source root passed to lizard |
| `--exclude` | _(none)_ | Lizard `-x` pattern; repeatable — pass once per pattern to exclude paths from complexity analysis |
| `--coverage-dir` | `src/TestResults/Coverage` | Root directory containing `coverage.cobertura.xml` files (all are aggregated) |

**Output sections:**

- Test Coverage table (line rate + branch rate from Cobertura XML)
- Code Complexity table (total NLOC, function count, avg CCN, avg NLOC, count above threshold)
- Per-function breakdown of functions exceeding the CCN threshold, sorted descending

**Dependencies:** `lizard` (on PATH), `xml.etree.ElementTree` (stdlib), `csv` (stdlib).

