# Pattern: Pipelines-Explained Documentation

Every project with CI/CD should have a `docs/pipelines-explained.md` that describes what the pipelines do in plain language. YAML answers *how*; this file answers *why* and *what*, which is what you need when a pipeline fails at 11pm.

Maintain it as a first-class artifact alongside the YAML — update it in the same commit as any pipeline change.

---

## Why this file exists

- **Onboarding:** a new team member can understand the full deploy flow without reading YAML
- **Debugging:** when a pipeline fails, you can read the step description to understand its intent before diving into logs
- **Change review:** reviewers can check the prose against the YAML to spot intent/implementation mismatches
- **AI assistance:** providing this file as context gives an LLM enough understanding to diagnose failures and suggest fixes without having to reverse-engineer the YAML

---

## Template

````markdown
# CI/CD Pipelines

<one-paragraph summary of how many pipelines exist and what they collectively do>

---

## Branch strategy

| Branch | Pipeline |
|--------|----------|
| PR targeting `<main-branch>` | PR pipeline — build and tests only, no push |
| `<dev-branch>` | Dev pipeline — build, test, push, deploy to Dev |
| `<main-branch>` | Prod pipeline — build, push, deploy to Prod (approval gate) |

<describe the merge direction, e.g. "Changes flow from trunk → main">

Both pipelines ignore changes under `docs/` and `*.md` files.

---

## Resource naming convention

<describe the naming pattern, e.g. `<app>-<env>-<region>-<type>`>

| Resource | Dev | Prod |
|---|---|---|
| Resource group | ... | ... |
| Key Vault | ... | ... |
| Container App | ... | ... |
| ACR | ... | ... |

---

## Shared templates

<for each template, describe its parameters and steps in plain language>

### `templates/<name>.yml`

Produces the `<StageName>` stage.

| Parameter | Default | Description |
|---|---|---|
| `param` | `default` | What it controls |

Steps:

1. **Step name** — what it does and why (include non-obvious details: what cache key is used, why a flag is set, what happens if this step is skipped)
2. ...

---

## <Pipeline name> (`<ado-pipeline-name>`)

**Trigger:** <branch>

### Stages

```
Build  ──►  Push  ──►  Deploy
```

### <Stage name> stage

<What this stage does. For each non-trivial step, explain its purpose and any gotchas.>

**Step N — <Step name>**

<Explain what the step does, what it produces, what can go wrong. Include variable names that matter for debugging.>

---

## Required variable groups

### `<group-name>`

| Variable | Secret | Description |
|---|---|---|
| `varName` | No | What it is, where to find its value |
| `secretName` | Yes | What it is, which Key Vault holds it |
````

---

## What to document per step

Not every step needs explanation — only document steps where the intent is not obvious from the `displayName`. Focus on:

- **Why a flag was added** — e.g. `--container-name` is required because the ARM API rejects the request otherwise; `--replica-retry-limit 0` because migrations are not idempotent
- **Timing dependencies** — e.g. a `sleep 30` exists because Log Analytics has a 30–90 second ingestion delay
- **Variable sources** — where a variable comes from (Key Vault? variable group? a preceding step via `task.setvariable`?)
- **Failure modes** — what a failed step typically indicates (permissions problem, wrong resource name, transient Azure issue)
- **Non-obvious sequences** — why two steps must run in a specific order

Leave out steps that are self-explanatory from their name and task type (e.g. "Restore packages" via `DotNetCoreCLI@2` with `command: restore`).

---

## Maintenance discipline

- Update `pipelines-explained.md` in the same commit as the YAML change — never let them drift
- When a pipeline stage is added, removed, or significantly changed, update the stage diagram
- When a gotcha is discovered (a flag that must be present, a timing issue, a known CLI bug), document it in the relevant step description and in the file's **Gotchas** section
- When a step is removed, remove its documentation — stale docs are worse than no docs

### Optional: Gotchas section

Add a `## Gotchas` section at the end for issues that affected the pipeline and were non-obvious to diagnose. Format each entry as: symptom → root cause → fix applied. This turns a debugging incident into reusable knowledge.

Example:

```markdown
## Gotchas

**`ContainerAppImageRequired` on migration job update**
Symptom: `az containerapp job update --image` fails with `(ContainerAppImageRequired) Container with name '...' must have an 'Image' property specified`.
Root cause: Azure CLI ≤2.85.0 sends a PATCH where the container object is present but the `image` field is missing — a CLI bug.
Fix: replaced with `az rest PATCH` using the template read from `az containerapp job show` and image patched via `jq`.
```
