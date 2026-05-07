# Pattern: Creating<ClassName> — Factory Method Tests

Use when testing static methods whose primary purpose is constructing and returning a new instance.

Examples of factory methods: `RequestResult.Ok()`, `Token.For(userId)`, `UserProfile.Anonymous()`, `PagedResponse.Empty<T>()`.

## File placement

Mirror the main project's folder structure.

| Main project file | Test file |
|---|---|
| `src/MyApp/RequestResult.cs` | `src/MyApp.UnitTests/CreatingRequestResult.cs` |
| `src/MyApp/Commands/PagedResponse.cs` | `src/MyApp.UnitTests/Commands/CreatingPagedResponse.cs` |

## Template

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

// Add using directives for the class under test

namespace {RootNamespace};  // or {RootNamespace}.{SubFolder}

[TestClass]
public sealed class Creating{ClassName}
{
    // -------------------------------------------------------------------------
    // {FactoryMethodName}
    // -------------------------------------------------------------------------

    [TestMethod]
    public void {FactoryMethodName}_ReturnsInstanceWithExpectedState()
    {
        var result = {ClassName}.{FactoryMethodName}(/* args */);

        Assert.IsNotNull(result);
        Assert.AreEqual(expectedProp, result.Property);
    }

    [TestMethod]
    public void {FactoryMethodName}_{InvalidCondition}_Throws()
    {
        Assert.Throws<ArgumentException>(() => {ClassName}.{FactoryMethodName}(invalidArg));
    }
}
```

## Key rules

- Class is `sealed`.
- Group test methods by factory method using comment dividers.
- Each factory method gets at minimum: a happy-path test and an invalid-input test (when applicable).
- If a factory method returns a singleton, test for reference equality using `Assert.AreSame`.
- Verify that returned instances have the expected initial state — don't just assert `IsNotNull`.

## Example

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace N2.Core;

[TestClass]
public sealed class CreatingRequestResult
{
    // -------------------------------------------------------------------------
    // Ok
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Ok_ReturnsSingletonWithCode200()
    {
        RequestResult result = RequestResult.Ok();
        Assert.AreEqual(RequestResult.OkCode, result.Code);
        Assert.IsTrue(result.IsSuccessCode);
    }

    [TestMethod]
    public void Ok_WithMessage_CreatesInstanceWithCustomMessage()
    {
        RequestResult result = RequestResult.Ok("custom");
        Assert.AreEqual(RequestResult.OkCode, result.Code);
        Assert.AreEqual("custom", result.Message);
        Assert.IsTrue(result.IsSuccessCode);
    }

    // -------------------------------------------------------------------------
    // BadRequest
    // -------------------------------------------------------------------------

    [TestMethod]
    public void BadRequest_ReturnsSingletonWithCode406()
    {
        RequestResult result = RequestResult.BadRequest();
        Assert.AreEqual(RequestResult.BadRequestCode, result.Code);
        Assert.IsFalse(result.IsSuccessCode);
    }

    [TestMethod]
    public void BadRequest_WithMessage_CreatesInstanceWithMessage()
    {
        RequestResult result = RequestResult.BadRequest("invalid input");
        Assert.AreEqual(RequestResult.BadRequestCode, result.Code);
        Assert.AreEqual("invalid input", result.Message);
    }

    // -------------------------------------------------------------------------
    // NotFound
    // -------------------------------------------------------------------------

    [TestMethod]
    public void NotFound_ReturnsSingletonWithCode404()
    {
        RequestResult result = RequestResult.NotFound();
        Assert.AreEqual(RequestResult.NotFoundCode, result.Code);
        Assert.IsFalse(result.IsSuccessCode);
    }
}
```
