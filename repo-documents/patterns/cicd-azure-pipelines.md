# CI/CD — Azure Pipelines pattern

Pipeline definitions live in `pipelines/` at the repo root.
Use Azure DevOps terminology throughout: **pipeline**, **stage**, **job**, **step**.
Never use GitHub Actions terms (workflow, action, runner).

## Section template

```markdown
## CI/CD pipeline

Pipeline: `pipelines/azure-pipelines.yml` — registered in Azure DevOps under <project>.

Triggers on push and PR to `trunk` when files under `src/<Name>.*/**` change.
Documentation-only commits do not trigger a run.

| # | Stage | Runs on |
|---|-------|---------|
| 1 | **Build and Test** | push + PR |
| 2 | **<Stage 2>** | push + PR (parallel) |
| 3 | **Publish** | push to `trunk` only, after Build passes |

### Pipeline variables

| Variable | Description | Value |
|----------|-------------|-------|
| `artifactsFeedName` | Azure Artifacts feed | `<feed-name>` |
| `buildConfiguration` | MSBuild configuration | `Release` |
```

## Rules

- Stages and their `dependsOn` / `condition` come from the YAML — read the file, do not guess.
- List every `variables:` entry from the YAML. Note pipeline-UI-only variables where relevant.
- Secrets are set under **Pipelines → Edit → Variables** (the lock icon). Do not invent a secrets table; instead note them inline where the stage that needs them is described.
- Packages are published to Azure Artifacts (`--skip-duplicate` means re-pushing an existing version is a no-op).

## Information to extract from the YAML

- `trigger:` and `pr:` blocks → what branches and paths trigger the pipeline.
- `stages:` list → stage names, `displayName`, `dependsOn`, `condition`.
- `variables:` block → variable names and default values.
- `UseDotNet@2` steps → which SDK versions are installed.
- Publish task or script → where packages go (feed name, URL construction).
