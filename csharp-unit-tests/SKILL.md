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

## Step 2 — Choose the test class name

Inspect the target class to determine the correct naming:

| Target | Test class name | File name | Pattern file |
|--------|----------------|-----------|-------------|
| Exception class (name ends in `Exception`) | `For<ClassName>UnitTests` | `For<ClassName>UnitTests.cs` | `patterns/regular-class.md` |
| Regular class (instance methods) | `With<ClassName>` | `With<ClassName>.cs` | `patterns/regular-class.md` |
| Static class or static method group | `Using<ClassName>` | `Using<ClassName>.cs` | `patterns/static-class.md` |
| Factory methods (static creators returning instances) | `Creating<ClassName>` | `Creating<ClassName>.cs` | `patterns/factory-class.md` |

**Exception classes** use `For<ClassName>UnitTests` to avoid the CA1711 analyser warning that forbids class names ending in `Exception`. This is the only case where `UnitTests` appears in a class name.

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

## Gotchas

### `[TestCategory]` is only matched at the class level by `dotnet test --filter`

When using `dotnet test --filter "TestCategory=X"` or `TestCategory!=X`, the expression only
matches categories applied to the **class** — not to individual test methods. Applying
`[TestCategory]` on a method has no effect on filtering.

```csharp
// Wrong — the filter "TestCategory!=LongRunning" will NOT exclude this method
[TestClass]
public class MyTests {
    [TestMethod]
    [TestCategory("LongRunning")]  // ignored by dotnet test --filter
    public async Task SlowTimingTest() { ... }
}

// Correct — extract slow tests into a dedicated class with the category on the class
[TestClass]
[TestCategory("LongRunning")]
public class LongRunningTests {
    [TestMethod]
    public async Task SlowTimingTest() { ... }
}
```

This applies to all filter expressions, including `TestCategory=Integration` and negations.
Always put `[TestCategory]` on the class when the intent is CI filtering.

### One statement per line — never concatenate on a single line

Every assertion and every statement must be on its own line. Do **not** place two statements on the same line — not even when they are logically related:

```csharp
// Wrong — two assertions crammed onto one line
Assert.AreEqual(10, info.PageSize);        Assert.AreEqual(0, info.TotalItems);

// Correct
Assert.AreEqual(10, info.PageSize);
Assert.AreEqual(0, info.TotalItems);
```

This applies to all generated test files. When writing file content via the Write tool, check each line before issuing the call — if any line contains more than one semicolon, split it.

### Avoid repeated assertions across test methods (exception classes)

When every constructor of a class produces the **same** value for a given property (e.g., all exception constructors set the same `ResponseStatus`), verify that value **once** — in the test for the default constructor or a dedicated "status" test. Do not repeat the assertion in every subsequent constructor test.

- **Wrong:** `StringCtorSetsPreconditionFailedAndPreservesMessage` — "PreconditionFailed" is already asserted in `DefaultCtorSetsPreconditionFailed`. The string-ctor test only needs to verify what is unique to it: that the message is preserved.
- **Right:** `StringCtorPreservesMessage` — focused on the ONE thing the string constructor adds.

The same generic name (`StringCtorPreservesMessage`, `StringInnerCtorChainsCorrectly`) is acceptable across multiple exception test classes; the test class name provides the exception-specific context.

**Only include a status in a constructor test name when that constructor sets a DIFFERENT status from the default constructor** (e.g., `ContractException` where default → `NotAccepted` but string ctor → `NotAcceptable`).

```csharp
// All three ConfigurationException ctors use PreconditionFailed.
// Test the status once — in the default-ctor test.
[TestMethod]
public void DefaultCtorSetsPreconditionFailed()
{
    ConfigurationException ex = new();
    Assert.AreEqual(ResponseStatus.PreconditionFailed, ex.ResponseStatus);
    Assert.IsFalse(string.IsNullOrEmpty(ex.Message));
}

[TestMethod]
public void StringCtorPreservesMessage()   // no status assertion — already covered above
{
    ConfigurationException ex = new("config missing");
    Assert.AreEqual("config missing", ex.Message);
}

[TestMethod]
public void StringInnerCtorChainsCorrectly()   // no status assertion — same reason
{
    InvalidOperationException inner = new("inner");
    ConfigurationException ex = new("outer", inner);
    Assert.AreEqual("outer", ex.Message);
    Assert.AreEqual(inner, ex.InnerException);
}
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

### 3 — Implement the actual tests (parallel)

Do not stop after scaffolding. Immediately proceed to implement real test bodies for every file that was just created or renamed. Process files in parallel: issue multiple Read + Edit tool calls in a single response whenever the files are independent of each other.

#### Per-file process

For each stub file:

1. **Read in parallel** — issue one `Read` call for the stub file and one `Read` call for its corresponding source file in the same response.
2. **Identify all public members** from the source: constructors, public methods, public properties with logic, operators, and static factory methods.
3. **Replace** the entire body of `Placeholder()` / `Assert.Inconclusive` with real test methods. Keep the file structure (namespace, class declaration, grouping comments) and only replace the method content.

#### What to test per class type

**Regular class (`With*`)**
- Each public constructor: valid args set expected state; invalid args throw.
- Each public method: happy path, boundary values, invalid-argument throws.
- Equality / comparison operators if defined.

**Static or extension class (`Using*`)**
- Each static method: happy path, null/empty inputs throw, boundary values.

**Factory class (`Creating*`)**
- Each factory method: returned instance has correct initial state.
- Singleton factories: same reference returned on repeated calls.
- Invalid args throw.

**DTO (`With*`, detected as DTO)**
- Fill in every public property in the round-trip test with explicit values.
- Assert each property individually after deserialization.
- For `DateTime` properties: assert both value and `Kind`; use `DateTimeKind.Utc`.
- If no `DateTime` properties exist, remove `Serialization_DateTimeProperties_KindIsPreserved`.

**Exception class (`For*UnitTests`)**
- Default constructor: `Message` is non-empty.
- `(string message)` constructor: `Message` equals the argument.
- `(string message, Exception inner)` constructor: both `Message` and `InnerException` set correctly.
- The type is assignable to its expected base (e.g. `Assert.IsInstanceOfType<Exception>(ex)`).

**Enum or constants class**
- Verify that each named value exists and has the expected underlying value.
- If the enum is used as a bitmask, verify flag combinations.

#### Parallelism guidance

- Read all source files for a batch in one parallel `Read` burst.
- Write all updated test files in one parallel `Edit` burst where content is independent.
- Break into smaller bursts (8–12 files) if the batch is very large to keep context manageable.
- If a file requires significant design decisions (e.g. a complex factory), handle it alone rather than in a burst.

After all files are written, run `find-untested.ps1` one final time to confirm full coverage.

### 4 — Confirm with the user before writing

When driving a batch interactively, run with `-WhatIf` first and show the user the plan. Write only after confirmation.
