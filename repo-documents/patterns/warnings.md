# src/WARNINGS.md pattern

## Purpose

Documents every warning suppressed via `<NoWarn>` (MSBuild/csproj) or `#pragma warning disable` in the project. The goal is to make suppressions auditable: anyone reviewing the project can see *why* each warning is suppressed and *when* the suppression is safe to remove.

## Structure

```markdown
# Suppressed Warnings

This document explains each warning suppressed via `<NoWarn>` in
`<ProjectName>/<ProjectName>.csproj`.

<One or two sentences about why suppressions exist in this type of project — e.g.
"Because this library contains only interfaces, abstract base types, and simple model
classes, several analyser rules that apply to concrete implementations are intentionally silenced.">

| Warning | Analyser | Name | Reason for suppression | Severity | Safe to ignore when |
|---------|----------|------|------------------------|----------|---------------------|
| `CA1002` | Roslyn / CA | Do not expose generic lists | … | Designer choice | … |
| `CS1591` | C# compiler | Missing XML comment | … | Low | … |
```

## Column definitions

| Column | What to write |
|--------|--------------|
| **Warning** | The warning code, e.g. `CA1002`, `CS1591`, `IDE0060`, `S125` |
| **Analyser** | `Roslyn / CA`, `C# compiler`, `Roslyn / IDE`, `Roslynator`, `SonarAnalyzer`, `Mapperly`, etc. |
| **Name** | The official analyser rule name (short form) |
| **Reason for suppression** | One sentence explaining *why* this project suppresses it — tied to the project's design or constraints, not just a restatement of the rule. |
| **Severity** | One of: `Designer choice`, `Low`, `Medium`, `High`. Use `Designer choice` for intentional API decisions; use severity words for warnings that carry correctness or security risk. |
| **Safe to ignore when** | One or two sentences describing the conditions under which the suppression remains safe. This is the most important column — it lets a future reviewer decide whether the suppression still applies. Include a "do not suppress" counterexample if relevant. |

## Severity guide

| Rating | Meaning |
|--------|---------|
| Designer choice | Pure style or API-shape decision; no correctness risk. |
| Low | Minor risk; safe in the described context, should be reviewed at major bumps. |
| Medium | Real risk in some scenarios; the suppression is conditional on the described circumstances. |
| High | Significant risk; suppression requires explicit sign-off and a very specific justification. |

## Maintenance rules

- Keep the table sorted by warning code (CA → CS → IDE → RCS → RMG → S).
- When a suppression is removed from the `.csproj`, remove its row from this table.
- When a new suppression is added to the `.csproj`, add its row to this table in the same PR.
- If a suppression was temporary (e.g. for active development), note that in the "Safe to ignore when" column and create a tracking item to remove it.

## Gathering entries

To generate the initial table or audit existing entries:

1. Read the `.csproj` file and extract all `<NoWarn>` values (may be semicolon-separated on one element, or spread across multiple `<NoWarn>` elements and `<ItemGroup>` conditionals).
2. Also grep for `#pragma warning disable` in `*.cs` files — these belong in the table too, noting the file(s) where they appear.
3. For each code, look up the official rule name and analyser. Roslyn CA/IDE rules are documented at `learn.microsoft.com/dotnet/fundamentals/code-analysis/quality-rules`; SonarAnalyzer rules at `rules.sonarsource.com/csharp`; Roslynator at `josefpihrt.github.io/docs/roslynator`.
4. Fill in "Reason for suppression" and "Safe to ignore when" based on the project's actual design, not just the rule description.
