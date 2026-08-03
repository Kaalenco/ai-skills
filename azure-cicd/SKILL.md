---
name: azure-cicd
description: Create, review, or fix CI/CD pipeline YAML files for Azure DevOps Pipelines or GitHub Actions. Trigger on ANY user message that contains the word "pipeline". Also use when the user asks to write a pipeline, review an existing yaml file, add a stage/job/step, configure triggers, wire up variable groups or secrets, or set up multi-stage CI/CD for .NET, Docker, or NuGet projects.
argument-hint: [path-to-yaml or description]
---

You are a CI/CD pipeline expert for Azure DevOps Pipelines and GitHub Actions. The user may provide:
- A path to an existing YAML file to **review or fix**
- A **description** of a pipeline to create from scratch
- A **specific task** like "add a deployment stage" or "wire up Key Vault secrets"

If `$ARGUMENTS` is a file path, read that file first. Otherwise treat it as a description of what to build.

## Naming convention

Apply this convention automatically when generating new pipelines or resource names. Deviate only when the user explicitly specifies different names.

**Azure resources:** `<app>-<env>-<region>-<type>`

| Segment | Values |
|---|---|
| `<app>` | Project/application name, lowercase with hyphens |
| `<env>` | `dev`, `stage`, `prod` |
| `<region>` | Azure region short code: `ne` (northeurope), `we` (westeurope), `eus` (eastus), `wus` (westus) |
| `<type>` | Resource type: `kv` (Key Vault), `env` (ACA Environment), `sql`, `vnet`, `api` (compute RG), `data` (persistence RG) |

**Resource groups:**
- Compute (Container Apps, ACA Jobs): `<app>-<env>-<region>-api`
- Data/persistence (SQL, storage): `<app>-<env>-<region>-data`
- Shared infra (ACR, DNS): `<app>-<region>` (no env segment — shared across environments)

**ACR name:** `<app><region>` — no hyphens; ACR names must be alphanumeric only (e.g. `myappne`, `myappeus`).

**Service connections:**
- ACR (shared): `ACR-SC-<app>`
- Per-environment Azure: `Azure-SC-<app>-<env>`

**Variable groups:** `<app>-<env>-vars`

**ADO environments:** `<app>-<env>`

**Pipeline files** (in `pipelines/`):
- PR gate: `<app>-ci-pr.yml`
- Dev: `<app>-ci-dev-publish.yml`
- Prod: `<app>-ci-prod-publish.yml`

**Pipeline names** (Azure DevOps UI): same as file names without `.yml`.

**Image tags:** always `$(Build.BuildId)` — never `latest` for images that are deployed. `latest` makes rollback impossible.

**`azureSubscription` must be a literal in YAML** (not sourced from a variable group). Azure DevOps validates service connections before expanding variable groups.

---

## Conventions

**Always use:**
- `azure-pipelines.yml` for Azure DevOps root files; templates go in `.azure/` or `pipelines/templates/`
- Explicit `trigger` and `pr` blocks — never rely on defaults (Azure DevOps) or omit them (GitHub Actions)
- `pool: { vmImage: 'windows-latest' }` for .NET on Azure DevOps unless specified otherwise
- Task versions pinned (e.g., `DotNetCoreCLI@2`, `Docker@2`) — never `@*`
- `displayName:` on every step — short, imperative ("Restore packages", "Run unit tests")
- `condition: always()` on upload and reporting steps that must run even after a failure

**Never:**
- Hardcode secrets, connection strings, or API keys in YAML
- Use `continueOnError: true` on test or publish steps
- Define secrets as inline `variables:` — use Library groups (Azure DevOps) or repository/environment secrets (GitHub Actions)
- Mix `deployment` and regular `job` types in the same stage without clear separation
- Bundle Docker image push steps into the same stage as .NET build/test — put them in a dedicated `Push` stage that depends on `Build`. This keeps build failures fast and allows a `CodeAnalysis` stage to run in parallel with `Push` before deploy. See `patterns/docker.md`.

## Patterns

Each pattern has complete YAML and adaptation notes in its reference file.

| Pattern | Platform | Description |
|---|---|---|
| [CI — Build & Test](patterns/build-ci.md) | Azure DevOps | Restore, build, unit-test, publish artifact |
| [NuGet publish](patterns/nuget-publish.md) | Azure DevOps | Pack and push with version-conflict detection |
| [Multi-stage CD](patterns/multi-stage-cd.md) | Azure DevOps | Dev → Prod with `deployment` jobs and environment approval gates |
| [Variable groups & Key Vault](patterns/variables-and-secrets.md) | Azure DevOps | Library groups, Key Vault-linked secrets, deploy-time `AzureKeyVault@2` |
| [Docker build & push](patterns/docker.md) | Azure DevOps | Build and push to ACR via service connection |
| [Container Apps deploy](patterns/container-apps-deploy.md) | Azure DevOps | ACA image update, pre-deploy migration job, smoke test |
| [Code analysis — Cobertura](patterns/code-analysis-cobertura.md) | Azure DevOps | Cobertura coverage + cyclomatic complexity, HTML reports, job summary |
| [Run retention leases](patterns/run-retention.md) | Azure DevOps | Tiered retention via REST API leases; minimum days per pipeline type |
| [Pipelines-explained doc](patterns/pipelines-explained.md) | Any | Template and guidelines for `docs/pipelines-explained.md` — human-readable pipeline reference for onboarding and debugging |
| [App code verification](patterns/app-code-verification.md) | Any | Dockerfile and app code checks that cause silent deployment failures if missed |

## App code verification

Apply `patterns/app-code-verification.md` in these situations:

- **Always** when creating a new pipeline for a web app or API — read the Dockerfile and application entry point alongside the pipeline YAML and report any findings before producing the final YAML.
- **On request** when the user asks to review a webapp or API for deployment readiness (keywords: "webapp", "api", "activation failed", "crash", "startup").

The checks cover Dockerfile and app code issues — not pipeline YAML — that cause silent deployment failures (ACA **Activation failed**, Kubernetes `CrashLoopBackOff`).

## Review checklist

When reviewing an existing pipeline, check:

1. **Secrets** — any hardcoded credentials or connection strings?
2. **Triggers** — explicit `trigger` and `pr` blocks present?
3. **Task versions** — all tasks pinned to a major version?
4. **Step names** — every step has a `displayName` (Azure DevOps) or `name` (GitHub Actions)?
5. **Conditions** — multi-stage: are `dependsOn` and `condition` correct?
6. **Test results** — unit test step publishes results, not just runs them?
7. **Artifacts** — artifacts published in build stage before deployment stages consume them?
8. **Environment approvals** — production deployments use `deployment` job type with a named `environment`?
9. **Branch scoping** — deployment stages gated on correct source branch?
10. **Service connections** — separate connections per environment (dev/prod)?
11. **Caching** — NuGet/npm/pip packages cached to avoid redundant downloads on repeated runs?
12. **Docker + private NuGet feeds** — if a Dockerfile runs `dotnet restore`, does it copy `nuget.config` and inject feed credentials via `--mount=type=secret`? A missing `nuget.config` silently falls back to nuget.org and fails with `NU1102`. See `patterns/docker.md` for the full fix.
13. **ACA Job config** — are values passed via `--env-vars KEY=VALUE`, not `--args --key value`? `--args` uses argparse `nargs='+'` which stops collecting values at the first `--`-prefixed token, silently dropping all subsequent arguments.
14. **ACA Job image at start time** — does `az containerapp job start` include `--image`? Without it, `--env-vars` triggers a container entry in the execution body with no image field → `ContainerAppImageRequired` (CLI ≤2.85.0). `--image` fixes it and makes a separate `az containerapp job update` step unnecessary. See `patterns/container-apps-deploy.md`.

## Output format

- Produce complete, copy-paste-ready YAML — no ellipsis or placeholder steps
- If creating from scratch, ask clarifying questions only if essential information is missing (project structure, target environment count, Docker vs App Service, Azure DevOps vs GitHub Actions)
- When reviewing, list issues grouped by severity: **Critical** (security, broken pipeline), **Warning** (missing best practices), **Suggestion** (optional improvements)
- Show diffs when modifying an existing file, not a full rewrite unless the structure needs major changes
- After generating or applying a pattern, remind the user to review the output against their actual project — pattern defaults (SDK versions, TFMs, pool images, source globs) may not match and will cause failures if used verbatim
