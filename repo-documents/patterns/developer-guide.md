# src/DEVELOPER-GUIDE.md pattern

## Purpose

Gives a developer who has just cloned the repo everything they need to build, test, and maintain the project. Covers local workflow and CI/CD. Architecture and API design belong in the README or ADRs, not here.

## Structure

```markdown
# <Project Name> — Developer Guide

This document explains how to build, test, and maintain the project locally and in CI.

## Solution structure

<directory tree — top-level folders and key files only, no mermaid>

## Building

<bash code blocks — restore, build debug, build release>
<one-line note on side effects, e.g. "Release builds produce a .nupkg via GeneratePackageOnBuild">

## Running tests

### Unit tests

<bash code block>

### Single test by name

<bash code block>

<note on where test results are written>

## CI/CD

<content from the detected CI/CD pattern — see below>

## Regular maintenance

### <Runtime/SDK> targets

<when and how to add/drop target framework versions, including pipeline impact>

### Package version

<where the version is set, how to bump it before a release>

### Dependencies

<how to handle security advisories or dependency updates>
```

## Detecting the CI/CD system

Before writing the CI/CD section, glob for pipeline files:

| Files found | CI/CD system | Pattern file |
|-------------|-------------|--------------|
| `pipelines/*.yml` | Azure DevOps Pipelines | `patterns/cicd-azure-pipelines.md` |
| `.github/workflows/*.yml` | GitHub Actions | `patterns/cicd-github-actions.md` |
| Both present | Both — write a subsection for each | Read both pattern files |
| Neither found | Note that no CI/CD is configured yet | — |

Read the detected pipeline/workflow YAML files, then read the matching pattern file, then write the CI/CD section.

## Rules

- Use `bash` as the language tag for all shell commands. Use `powershell` only if the command is PowerShell-specific.
- Every command block must be copy-paste runnable. No `<placeholder>` values inside code blocks.
- Always include `--filter "TestCategory!=Integration"` in the unit test command. This is a convention across all N2.xxx libraries: integration tests are tagged `[TestCategory("Integration")]` and may require external infrastructure (database, service, etc.), so they are excluded from the default run. Include the filter even when no integration tests exist yet — it keeps the command consistent with the rest of the ecosystem.
- Integration tests section: only include if integration tests exist (glob `**/*.IntegrationTests.csproj` or grep for `[TestCategory("Integration")]`). When they do exist, note any prerequisites (e.g. a running SQL Server, a local API service) in this section so developers know what to set up before running them.
- Do not describe architecture or explain why interfaces exist — that belongs in the README.

## Information to gather before writing

- Build and test commands: read `CLAUDE.md` first — it often documents the canonical commands.
- Solution/project structure: glob `src/**/*.csproj` and `src/**/*.sln`.
- Target frameworks: read the main `.csproj` for `<TargetFrameworks>`.
- Package version location: read the `.csproj` for `<PackageVersion>` or `package.json` for `"version"`.
- CI/CD: detect as described above, then read the relevant YAML files.
