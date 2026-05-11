---
name: repo-documents
description: Create and maintain the four standard repository documents — README.md, CHANGELOG.md, src/WARNINGS.md, and src/DEVELOPER-GUIDE.md. Use when asked to write, update, or audit any of these files.
argument-hint: [readme|changelog|warnings|developer-guide|check] [optional description or version]
allowed-tools: Read Glob Grep Write Edit Bash
---

# Repository Documents

This skill manages four standard documents that every project in this workspace should maintain.

| Document | Location | Purpose |
|----------|----------|---------|
| `README.md` | repo root | Project overview, functional areas, links to other docs |
| `CHANGELOG.md` | repo root | Full version history, breaking changes highlighted |
| `src/WARNINGS.md` | `src/` | Suppressed analyser warnings with severity and guidance |
| `src/DEVELOPER-GUIDE.md` | `src/` | Build, test, CI/CD, and maintenance instructions |

## Step 1 — Determine mode from `$ARGUMENTS`

| Argument | Mode |
|----------|------|
| *(empty)* or `check` | Audit — scan the repo, report what exists vs what is missing, offer to create anything that is absent |
| `readme` | Create or update `README.md` |
| `changelog` | Add a new entry to `CHANGELOG.md`, or create the file if absent |
| `warnings` | Add or update an entry in `src/WARNINGS.md`, or create the file if absent |
| `developer-guide` | Create or update `src/DEVELOPER-GUIDE.md` |
| `all` | Create any missing documents; update all existing ones |

If the argument is ambiguous or the user's request describes a task, infer the most likely mode. If still unclear, ask.

## Step 2 — Audit mode

When mode is `check` or `all`:

1. Glob for `README.md`, `CHANGELOG.md`, `src/WARNINGS.md`, and `src/DEVELOPER-GUIDE.md`.
2. For each file found, read it and briefly note whether it follows the conventions in the relevant pattern file.
3. Report in a table:

   | Document | Status | Notes |
   |----------|--------|-------|
   | README.md | ✓ Found | … |
   | CHANGELOG.md | ✗ Missing | — |
   | src/WARNINGS.md | ⚠ Found — outdated format | … |
   | src/DEVELOPER-GUIDE.md | ✓ Found | … |

4. Offer to create or fix each issue. In `all` mode, proceed without waiting for confirmation.

## Step 3 — Create or update

Read the relevant pattern file from `patterns/` before writing any file content.

| Mode | Pattern file |
|------|-------------|
| `readme` | `patterns/readme.md` |
| `changelog` | `patterns/changelog.md` |
| `warnings` | `patterns/warnings.md` |
| `developer-guide` | `patterns/developer-guide.md` |

**For existing files:** Read the file first. Apply targeted edits — do not rewrite sections that are already correct.

**For `developer-guide` mode:** also detect the CI/CD system before writing — see `patterns/developer-guide.md` for the detection logic and the matching CI/CD pattern files:

| CI/CD system | Pattern file |
|-------------|--------------|
| Azure DevOps Pipelines (`pipelines/*.yml`) | `patterns/cicd-azure-pipelines.md` |
| GitHub Actions (`.github/workflows/*.yml`) | `patterns/cicd-github-actions.md` |

**For new files:** Use the pattern as a template. Fill in project-specific information by reading:
- The `.csproj` or `package.json` for name, version, and target frameworks.
- `src/*.sln` or `src/` directory layout for solution structure.
- `pipelines/` or `.github/workflows/` for CI/CD details (detect which is present).
- `Directory.Build.props` or `.editorconfig` for build settings and suppressions.
- `adr.config.json` and `docs/adr/` if ADRs are in use.

## Step 4 — After writing

Tell the user what was written and what still needs manual input (e.g. version number, badge URLs, CI/CD secret names). Do not run builds or tests.

## Conventions that apply to all documents

- No trailing whitespace; end each file with a single newline.
- Headings use sentence case (`## Functional areas`, not `## Functional Areas`).
- Code blocks always specify a language tag (`bash`, `xml`, `csharp`, etc.).
- Tables use `|---|` separator rows aligned to the widest cell in each column.
- Do not use emojis in document headings or table cells unless already present in the file.
- Links to other docs in the repo use relative paths, not absolute URLs.
