---
description: Create unit test projects and test files for C# class libraries. Use when asked to write tests, add a unit test project, check test coverage, or generate MSTest stubs for a specific C# class.
allowed-tools: Read Glob Grep Write Edit Bash
---

# C# Unit Test Generator

Read the target class file first to understand its structure, then follow these steps.

## Step 1 — Locate or create the test project

Glob for `**/*.UnitTests.csproj` in the solution. If no test project exists for the target library, create one by reading and following `patterns/project-setup.md`.

Naming rule:
- `MyApp.csproj` → `MyApp.UnitTests.csproj`
- `MyApp.Services.csproj` → `MyApp.Services.UnitTests.csproj`

Place the test project in a sibling folder next to the main project.

## Step 2 — Choose the test class prefix

Inspect the target class to determine the correct prefix:

| Target | Prefix | Pattern file |
|--------|--------|-------------|
| Regular class (instance methods) | `With<ClassName>` | `patterns/regular-class.md` |
| Static class or static method group | `Using<ClassName>` | `patterns/static-class.md` |
| Factory methods (static creators returning instances) | `Creating<ClassName>` | `patterns/factory-class.md` |

A class may have both instance and factory methods. In that case, create separate test files:
`With<ClassName>.cs` for instance tests, `Creating<ClassName>.cs` for factory tests.

Read the relevant pattern file before generating test code.

## Step 2b — DTO detection: JSON serialization tests

Before generating test methods, check whether the class is a DTO:

| Signal | Example |
|--------|---------|
| Name ends in `Model` (case-insensitive) | `UserModel`, `CreateOrderModel` |
| Name ends in `Dto` (case-insensitive) | `TokenDto`, `UserDto` |
| Implements `ICommandRequest` | `class CreateUserRequest : ICommandRequest` |
| Implements `ICommandResponse` | `class CreateUserResponse : ICommandResponse` |

If any signal matches, read `patterns/dto-class.md` and generate serialization tests instead of a generic placeholder.

**DateTime rule:** always use `DateTimeKind.Utc` in test data. `System.Text.Json` appends `Z` for Utc and round-trips `Kind` correctly. `DateTimeKind.Local` serializes without `Z` and deserializes as `Unspecified`, silently losing timezone intent. Assert both the value **and** `.Kind` for every `DateTime` property.

## Step 3 — Namespace convention

`UnitTests` must NOT appear in the namespace — only in the project/assembly name.

Derive the test namespace from the main library's root namespace:

| Main library root namespace | Test file location | Test namespace |
|---|---|---|
| `MyApp` | root of test project | `MyApp` |
| `MyApp` | `Commands/` sub-folder | `MyApp.Commands` |
| `MyApp.Services` | root of test project | `MyApp.Services` |

Set `<RootNamespace>` explicitly in the test `.csproj` to the main library's root namespace.

To find the main library's root namespace, read its `.csproj`; if no `<RootNamespace>` is set, the default is the assembly name (the project file name without extension).

## Step 4 — Test method naming

Use descriptive PascalCase. Two accepted styles — be consistent within a single test class:

**Style A — Subject_Condition_Expected** (preferred when the precondition matters):
```csharp
public void Constructor_NullValue_TreatedAsEmpty()
public void ToTokenString_SecretTooShort_Throws()
```

**Style B — ActionExpectedOutcome** (preferred for simple state assertions):
```csharp
public void OkReturnsSingletonWithCode200()
public void MessageOrDefaultShouldReturnDefaultMessageWhenEmpty()
```

Never append `Test` to method names. Never use `[DataTestMethod]` unless explicitly requested.

## Step 5 — Class sealing

- `With*` test classes: always `sealed`.
- `Using*` and `Creating*` test classes: `sealed` preferred.

## Step 6 — Grouping

When a test class covers multiple methods or scenarios, use comment dividers to group them:

```csharp
// -------------------------------------------------------------------------
// Constructor
// -------------------------------------------------------------------------

[TestMethod]
public void Constructor_...
```

## Batch workflow — processing the untested-file list

When the user asks to add or fix tests across a project rather than for a single class, run
`scripts/find-untested.ps1` with `-ListOnly` to get a machine-readable plan, then work
through each line.

### 1 — Generate the plan

```powershell
$plan = & "$PSScriptRoot/scripts/find-untested.ps1" `
    -SourceDir .\src\MyApp `
    -TestDir   .\src\MyApp.UnitTests `
    -ListOnly
```

Each line is one of:
- `create:<relative-source-path>` — no test file exists; create one.
- `rename:<relative-source-path>` — a `*Tests.cs` file exists but violates the naming convention; rename the file and the class inside it.

### 2 — Scaffold stubs with new-tests.ps1

`scripts/new-tests.ps1` runs `find-untested.ps1 -ListOnly` internally and processes every line:

```powershell
# Preview first
.\skills\csharp-unit-tests\scripts\new-tests.ps1 `
    -SourceDir .\src\MyApp `
    -TestDir   .\src\MyApp.UnitTests `
    -WhatIf

# Write for real
.\skills\csharp-unit-tests\scripts\new-tests.ps1 `
    -SourceDir .\src\MyApp `
    -TestDir   .\src\MyApp.UnitTests
```

What it does per line:
- **create** — detects static vs regular class, writes a `With*` or `Using*` stub, flags factory candidates in a comment.
- **rename** — renames the `*Tests.cs` file to `With*` or `Using*` and updates the class declaration inside it.

### 3 — Fill in the stubs

After the script runs, all new test files contain a single `Placeholder()` method marked `// TODO`. For each file:

1. Read the source class to understand its public surface.
2. Replace `Placeholder()` with real test methods following Steps 4–6 above.
3. If the stub comment flags a factory candidate, decide whether a separate `Creating*` file is warranted.

### 4 — Confirm with the user before writing

When driving a batch interactively, run with `-WhatIf` first and show the user the plan. Write only after confirmation.
