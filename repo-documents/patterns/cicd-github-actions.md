# CI/CD — GitHub Actions pattern

Workflow definitions live in `.github/workflows/` at the repo root.
Use GitHub Actions terminology throughout: **workflow**, **job**, **step**, **runner**.
Never use Azure DevOps terms (pipeline, stage, agent pool).

## Section template

```markdown
## CI/CD

Workflows: `.github/workflows/` — runs on GitHub Actions.

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `dotnet.yml` | push + PR to `trunk` (src changes only) | Build, test, publish NuGet |
| `codeql.yml` | push + PR to `trunk`; weekly schedule | Security scanning |
| `maintenance.yml` | weekly schedule; manual | Delete old workflow runs |

### Required repository variables

Set under **Settings → Secrets and variables → Actions → Variables**:

| Variable | Description | Value |
|----------|-------------|-------|
| `CSPROJ_PATH` | Path to the publishable `.csproj` | `src/<Name>/<Name>.csproj` |
| `NUGET_PACKAGE_ID` | NuGet package ID (lowercase) | `<name>` |

### Required repository secrets

| Secret | Description |
|--------|-------------|
| `PACKAGE_N2` | NuGet API key for nuget.org |
```

## Rules

- Workflows and their `on:` triggers come from the YAML files — read each file, do not guess.
- List every repository variable (`${{ vars.* }}`) and secret (`${{ secrets.* }}`) referenced in any workflow file.
- Packages are published to nuget.org (or another registry if configured). Note `--skip-existing` behaviour where applicable.
- External workflows (e.g. CodeQL) are maintained by third parties — note that they should be periodically checked for updated versions.

## Information to extract from the YAML files

- `on:` block in each workflow → what events and branches trigger it.
- `jobs:` list → job names, `needs`, `if` conditions.
- `${{ vars.* }}` references → repository variables that must be set.
- `${{ secrets.* }}` references → repository secrets that must be set.
- `uses: actions/*` and `uses: github/*` → pinned action versions to track for updates.
- `.NET` setup steps (`actions/setup-dotnet`) → which SDK versions are used.
