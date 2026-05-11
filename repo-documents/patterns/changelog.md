# CHANGELOG.md pattern

## Structure

```markdown
# Changelog

## <X.Y.Z> — <YYYY-MM-DD>

<one-line summary for patch/minor releases with no API surface changes>

### <Domain area> (optional, for larger releases)

- <change description>
- **Breaking:** <description> — `OldApi` now returns `X` instead of `Y`.

[… repeat for each version, newest first …]
```

## Entry heading format

```
## 1.7.1 — 2026-05-10
```

- Version and date separated by ` — ` (em dash with spaces).
- Date in ISO 8601 (`YYYY-MM-DD`).
- No "v" prefix on the version number.

## Entry body rules

**Patch releases** (Z bump): one-line prose summary is enough — `Optimizations and other minor refactoring; no API surface changes.`

**Minor releases** (Y bump): use `###` subsections per domain area if there are three or more distinct areas. Fewer than three: flat bullet list under the version heading.

**Major releases** (X bump): always use `###` subsections. Add a short prose introduction before the bullets.

**Breaking changes:** prefix the bullet with `**Breaking:**` and state the old and new signatures inline. Example:
```
- **Breaking:** `INotifyChangeListener.OnItemModified` now returns `bool` instead of `void`.
```

**Removed APIs:** prefix with `**Removed:**`.

**Deprecated APIs:** prefix with `**Deprecated:**`.

## Adding a new entry

1. Read the current `CHANGELOG.md`.
2. Read the version from the `.csproj` (`<PackageVersion>`) or `package.json`.
3. Ask the user for the date if it is not today or if it should be a release date in the future.
4. Insert the new entry **immediately after `# Changelog`** (before the previous newest entry).
5. Do NOT renumber or reformat existing entries.

## Information to gather before writing an entry

- New version number (from project file — do not guess).
- What changed: read the git log since the last tag (`git log <last-tag>..HEAD --oneline`) and ask the user to confirm or add items.
- Whether any public API surfaces changed (interface signatures, method return types, added/removed members).
- Whether any changes are breaking (require callers to update their code).

## What NOT to include

- Internal refactoring that has no effect on consumers.
- Test-only changes.
- CI/CD changes (unless they affect how the package is consumed, e.g. a new required secret).
- Dependency bumps with no API effect (unless a security advisory is being addressed — in that case note the CVE).
