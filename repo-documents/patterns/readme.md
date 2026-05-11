# README.md pattern

## Structure (in order)

```markdown
# <project-name>

[badges — build status, NuGet version, etc.]

<one or two paragraphs: what the project is, why it exists, what problem it solves>

## Functional areas

### <Area name> (`<RootNamespace.Sub>`)

<Prose paragraph — NOT a bullet list — describing what this area contains and why.
Cover the domain concern, the key types (interfaces, models, base classes), and
how a consumer would use them. Do not just list class names.>

[… repeat for each namespace or module …]

## Project documentation

| Document | Description |
|----------|-------------|
| [src/DEVELOPER-GUIDE.md](src/DEVELOPER-GUIDE.md) | Developer guide — build commands, CI/CD pipeline, and maintenance notes. |
| [src/WARNINGS.md](src/WARNINGS.md) | Suppressed analyser warnings — lists every entry in `NoWarn` with severity rating and guidance. |
| [CHANGELOG.md](CHANGELOG.md) | Full version history. |

## Change log

See [CHANGELOG.md](CHANGELOG.md) for the full history. Current version: **<X.Y.Z>**.
```

## Rules

- The intro paragraphs come after badges and before any sections — no `## Introduction` heading.
- Every functional area gets its own `###` subsection. Do NOT flatten them into a single list.
- Prose, not bullets, in functional-area descriptions. The exception: if a sub-feature genuinely has discrete items (e.g. a list of supported backends), a bullet list inside the paragraph is fine.
- Badge URLs are project-specific; leave them as-is if the file already has them. When creating a new README from scratch, omit badges and note to the user that they need to add them.
- The "Project documentation" table must include all four standard documents. Omit `WARNINGS.md` if the project has no compiler suppressions.
- The "Change log" section carries just the current version — do not summarise entries here.
- Do not add sections beyond this structure unless the project type requires it (e.g., a CLI tool may add a "Usage" section with command examples).

## Information to gather before writing

- Project/package name (from `.csproj` `<AssemblyName>` or `<PackageId>`).
- Current version (from `<PackageVersion>` or `package.json`).
- Target frameworks or runtime (from `<TargetFrameworks>` or `engines` in `package.json`).
- Namespace structure (glob `src/**/*.cs` and group by namespace prefix, or read the solution layout).
- Purpose of each namespace (read the interface files — the names and method signatures reveal intent).
- Existing badges to preserve.
