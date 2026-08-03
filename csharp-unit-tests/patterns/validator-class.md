# Pattern: Validating<ClassName> — Validator Class Tests

Use when the class's primary purpose is validation, identified by:
- Implements `IRuntimeValidator<T>` (or an equivalent project-specific validator interface), or
- Class name ends in `Validator` (case-insensitive), or
- The primary public method is `Validate`, `TryValidate`, or `IsValid`.

Validators return one of three shapes — inspect the class to pick the matching style below:

| Shape | Signature example | Failure indicated by |
|---|---|---|
| Predicate | `bool IsValid(T instance)` | Returns `false` |
| Result object | `ResponseStatus Validate(T instance)` / `ValidationResult Validate(T instance)` | Returned status/result is not the success value |
| Throwing | `void Validate(T instance)` | Throws (e.g. `ValidationException`, `ArgumentException`) |

## File placement

Mirror the main project's folder structure.

| Main project file | Test file |
|---|---|
| `src/MyApp/Validation/UserRegistrationValidator.cs` | `src/MyApp.UnitTests/Validation/ValidatingUserRegistrationValidator.cs` |
| `src/MyApp/Commands/CreateOrderValidator.cs` | `src/MyApp.UnitTests/Commands/ValidatingCreateOrderValidator.cs` |

## Template — Result object shape (most common for `IRuntimeValidator<T>`)

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

// Add using directives for the class under test

namespace {RootNamespace};  // or {RootNamespace}.{SubFolder}

[TestClass]
public sealed class Validating{ClassName}
{
    // -------------------------------------------------------------------------
    // Validate
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Validate_AllFieldsValid_ReturnsSuccess()
    {
        var sut = new {ClassName}();
        var instance = /* build a fully valid instance */;

        var result = sut.Validate(instance);

        Assert.AreEqual(ResponseStatus.Ok, result);
    }

    [TestMethod]
    public void Validate_{FieldName}Missing_Returns{ExpectedStatus}()
    {
        var sut = new {ClassName}();
        var instance = /* build an instance with only this field invalid */;

        var result = sut.Validate(instance);

        Assert.AreEqual(ResponseStatus.{ExpectedStatus}, result);
    }
}
```

## Template — Predicate shape

```csharp
[TestClass]
public sealed class Validating{ClassName}
{
    [TestMethod]
    public void IsValid_AllFieldsValid_ReturnsTrue()
    {
        var sut = new {ClassName}();
        Assert.IsTrue(sut.IsValid(validInstance));
    }

    [TestMethod]
    public void IsValid_{Condition}_ReturnsFalse()
    {
        var sut = new {ClassName}();
        Assert.IsFalse(sut.IsValid(invalidInstance));
    }
}
```

## Template — Throwing shape

```csharp
[TestClass]
public sealed class Validating{ClassName}
{
    [TestMethod]
    public void Validate_AllFieldsValid_DoesNotThrow()
    {
        var sut = new {ClassName}();
        sut.Validate(validInstance);
    }

    [TestMethod]
    public void Validate_{Condition}_Throws{ExceptionType}()
    {
        var sut = new {ClassName}();
        Assert.Throws<{ExceptionType}>(() => sut.Validate(invalidInstance));
    }
}
```

## Key rules

- Class is `sealed`.
- One test method per distinct validation rule, covering both the pass case and each distinct fail case for that rule — do not collapse multiple unrelated failure conditions into one test.
- Group test methods by validated field or rule using comment dividers, same as other patterns.
- Always include one "all valid" happy-path test as the first test in the group.
- Cover boundary and edge inputs relevant to the rule: `null`, empty string, whitespace-only, min/max length or range, exactly-at-boundary values.
- Build each invalid instance with the minimum necessary deviation from a valid instance — only the field under test should be invalid, so the test isolates that rule. Reuse a private `CreateValid{ClassName}Instance()` helper (or `[TestInitialize]`) to avoid repeating a full valid object in every test.
- Test only the public validation surface (`Validate`/`IsValid`/`TryValidate`). Do not call private per-field helper methods directly, even if present.
- If the validator implements `IRuntimeValidator<T>`, test through the interface method — do not bypass it by calling a concrete-type-only overload.

## Example

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace N2.Core.Validation;

[TestClass]
public sealed class ValidatingUserRegistrationValidator
{
    private readonly UserRegistrationValidator _sut = new();

    private static UserRegistrationRequest ValidRequest() => new()
    {
        Email    = "user@example.com",
        Password = "Sup3rSecret!",
        UserName = "validuser",
    };

    // -------------------------------------------------------------------------
    // Validate
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Validate_AllFieldsValid_ReturnsOk()
    {
        var result = _sut.Validate(ValidRequest());
        Assert.AreEqual(ResponseStatus.Ok, result);
    }

    // -------------------------------------------------------------------------
    // Validate — Email
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Validate_EmailMissingAtSign_ReturnsBadRequest()
    {
        var request = ValidRequest();
        request.Email = "userexample.com";

        var result = _sut.Validate(request);

        Assert.AreEqual(ResponseStatus.BadRequest, result);
    }

    [TestMethod]
    public void Validate_EmailEmpty_ReturnsBadRequest()
    {
        var request = ValidRequest();
        request.Email = string.Empty;

        var result = _sut.Validate(request);

        Assert.AreEqual(ResponseStatus.BadRequest, result);
    }

    // -------------------------------------------------------------------------
    // Validate — Password
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Validate_PasswordShorterThanMinimum_ReturnsBadRequest()
    {
        var request = ValidRequest();
        request.Password = "short";

        var result = _sut.Validate(request);

        Assert.AreEqual(ResponseStatus.BadRequest, result);
    }
}
```
