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

## Common assertions (MSTest v4)

```csharp
Assert.AreEqual(expected, actual);
Assert.AreNotEqual(unexpected, actual);
Assert.IsTrue(condition);
Assert.IsFalse(condition);
Assert.IsNull(obj);
Assert.IsNotNull(obj);
Assert.IsInstanceOfType<TExpected>(obj);
Assert.IsNotEmpty(collection);                          // prefer over Assert.IsTrue(x.Length > 0)
Assert.HasCount(expectedCount, collection);             // prefer over Assert.AreEqual(n, x.Length)
Assert.IsGreaterThan(lowerBound, actual);               // prefer over Assert.IsTrue(actual > n)
Assert.IsLessThan(upperBound, actual);                  // prefer over Assert.IsTrue(actual < n)
CollectionAssert.AreEqual(expected, actual);
Assert.Throws<ArgumentException>(() => sut.Method(badArg));
```

## Disposable dependencies

When the class under test takes a disposable dependency (e.g. `HttpClient`), implement `IDisposable` on the test class. Declare the dependency as `readonly` with an inline initializer — **not** assigned in `[TestInitialize]`.

```csharp
[TestClass]
public sealed class With{ClassName} : IDisposable
{
    private readonly {DisposableDep} _dep = new {DisposableDep}();
    private {ClassName} _sut = null!;
    private bool _disposedValue;

    [TestInitialize]
    public void Setup()
    {
        _sut = new {ClassName}(_dep);
    }

    [TestCleanup]
    public void Cleanup()
    {
        _dep.Dispose();
    }

    // ... test methods ...

    private void Dispose(bool disposing)
    {
        if (!_disposedValue)
        {
            if (disposing)
                _dep?.Dispose();
            _disposedValue = true;
        }
    }

    public void Dispose()
    {
        Dispose(disposing: true);
        GC.SuppressFinalize(this);
    }
}
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
