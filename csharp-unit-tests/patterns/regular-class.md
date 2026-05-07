# Pattern: With<ClassName> — Instance Method Tests

Use for regular (non-static) classes where you test instance methods and properties.

## File placement

Mirror the main project's folder structure inside the test project.

| Main project file | Test file |
|---|---|
| `src/MyApp/UserService.cs` | `src/MyApp.UnitTests/WithUserService.cs` |
| `src/MyApp/Commands/CommandRouter.cs` | `src/MyApp.UnitTests/Commands/WithCommandRouter.cs` |

## Template

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

// Add using directives for the class under test

namespace {RootNamespace};  // or {RootNamespace}.{SubFolder}

[TestClass]
public sealed class With{ClassName}
{
    // -------------------------------------------------------------------------
    // {GroupName}
    // -------------------------------------------------------------------------

    [TestMethod]
    public void {Subject}_{Condition}_{Expected}()
    {
        // Arrange
        var sut = new {ClassName}(/* args */);

        // Act
        var result = sut.{Method}();

        // Assert
        Assert.AreEqual(expected, result);
    }
}
```

## Key rules

- Class is `sealed`.
- Prefer local arrange in each test method over shared `[TestInitialize]` state. Use `[TestInitialize]` only when all tests genuinely share the same setup.
- Group related test methods with divider comments when the class covers multiple methods.
- Exception assertions: `Assert.Throws<TException>(() => ...)` (MSTest 3+).

## Common assertions

```csharp
Assert.AreEqual(expected, actual);
Assert.AreNotEqual(unexpected, actual);
Assert.IsTrue(condition);
Assert.IsFalse(condition);
Assert.IsNull(obj);
Assert.IsNotNull(obj);
Assert.IsInstanceOfType<TExpected>(obj);
CollectionAssert.AreEqual(expected, actual);
Assert.Throws<ArgumentException>(() => sut.Method(badArg));
```

## Example

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace N2.Core;

[TestClass]
public sealed class WithRequestResult
{
    // -------------------------------------------------------------------------
    // MessageOrDefault
    // -------------------------------------------------------------------------

    [TestMethod]
    public void MessageOrDefault_EmptyMessage_ReturnsDefault()
    {
        RequestResult result = new(RequestResult.OkCode, string.Empty);
        string message = result.MessageOrDefault("Default message");
        Assert.AreEqual("Default message", message);
    }

    [TestMethod]
    public void MessageOrDefault_NonEmptyMessage_ReturnsMessage()
    {
        RequestResult result = new(RequestResult.OkCode, "Custom");
        string message = result.MessageOrDefault("Default message");
        Assert.AreEqual("Custom", message);
    }

    // -------------------------------------------------------------------------
    // WithHandle
    // -------------------------------------------------------------------------

    [TestMethod]
    public void WithHandle_ReturnsNewInstanceWithUpdatedHandle()
    {
        Guid handle = Guid.NewGuid();
        RequestResult original = new(RequestResult.OkCode, "msg");
        RequestResult updated = RequestResultExtensions.WithHandle(original, handle);
        Assert.AreEqual(handle, updated.Handle);
        Assert.AreEqual(original.Status, updated.Status);
    }
}
```
