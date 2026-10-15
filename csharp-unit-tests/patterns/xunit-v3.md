# Pattern: xUnit v3 translation

The other pattern files show MSTest syntax. When the target test project uses xUnit v3
(see Step 0 in SKILL.md), keep everything else from those patterns -- class naming
(`With*`, `Using*`, `Creating*`, `Validating*`, `For*UnitTests`), namespaces, grouping
dividers, method naming, sealing, one statement per line -- and translate only the
framework-specific parts using the tables below.

## Attributes and structure

| MSTest | xUnit v3 |
|---|---|
| `using Microsoft.VisualStudio.TestTools.UnitTesting;` | `using Xunit;` |
| `[TestClass]` on the class | nothing -- remove it |
| `[TestMethod]` | `[Fact]` |
| `[TestMethod]` + `[DataRow(...)]` | `[Theory]` + `[InlineData(...)]` |
| `[TestInitialize]` | constructor |
| `[TestCleanup]` | `IDisposable.Dispose()` (or `IAsyncDisposable`) |
| `[ClassInitialize]` / shared expensive setup | `IClassFixture<TFixture>` |
| `[AssemblyInitialize]` / cross-class setup | `ICollectionFixture<TFixture>` + `[Collection("...")]` |
| `[TestCategory("X")]` | `[Trait("Category", "X")]` |
| `[Ignore]` | `[Fact(Skip = "reason")]` |
| `Assert.Inconclusive("...")` | `Assert.Skip("...")` |

xUnit creates a new instance of the test class for every test, so constructor setup is
per-test, the same as `[TestInitialize]`.

## Assertions

Note the argument order is the same as MSTest: expected first, actual second.

| MSTest | xUnit v3 |
|---|---|
| `Assert.AreEqual(expected, actual)` | `Assert.Equal(expected, actual)` |
| `Assert.AreNotEqual(a, b)` | `Assert.NotEqual(a, b)` |
| `Assert.AreSame(a, b)` | `Assert.Same(a, b)` |
| `Assert.IsTrue(x)` / `Assert.IsFalse(x)` | `Assert.True(x)` / `Assert.False(x)` |
| `Assert.IsNull(x)` / `Assert.IsNotNull(x)` | `Assert.Null(x)` / `Assert.NotNull(x)` |
| `Assert.IsInstanceOfType<T>(x)` | `Assert.IsAssignableFrom<T>(x)` (or `Assert.IsType<T>(x)` for exact type) |
| `Assert.IsNotEmpty(c)` / `Assert.IsEmpty(c)` | `Assert.NotEmpty(c)` / `Assert.Empty(c)` |
| `Assert.HasCount(1, c)` | `Assert.Single(c)` |
| `Assert.HasCount(n, c)` | `Assert.Equal(n, c.Count)` |
| `Assert.IsGreaterThan(low, x)` / `Assert.IsLessThan(high, x)` | `Assert.True(x > low)` -- or `Assert.InRange(x, low, high)` when both bounds apply |
| `CollectionAssert.AreEqual(e, a)` | `Assert.Equal(e, a)` (sequence equality) |
| `Assert.Throws<T>(() => ...)` | `Assert.Throws<T>(() => ...)` -- exact type; use `Assert.ThrowsAny<T>` to accept derived types |
| `await Assert.ThrowsAsync<T>(...)` | `await Assert.ThrowsAsync<T>(...)` |
| `Assert.Fail("...")` | `Assert.Fail("...")` |

`Assert.Null(x)` and `Assert.NotNull(x)` participate in nullable flow analysis, so no `!` is
needed after `Assert.NotNull(result)`.

## Cancellation tokens

xUnit v3 provides `TestContext.Current.CancellationToken`. Pass it explicitly to every async
call that accepts a token (analyzer xUnit1051 warns otherwise):

```csharp
var result = await sut.CreateOrder(request, TestContext.Current.CancellationToken);
```

## Async setup and teardown

Implement `IAsyncLifetime` (v3 signatures use `ValueTask`):

```csharp
public sealed class WithOrderRepository : IAsyncLifetime
{
    public ValueTask InitializeAsync() { ... }

    public ValueTask DisposeAsync() { ... }
}
```

The interface method names keep their `Async` suffix because they are defined by xUnit.

## Disposable dependencies

Unlike MSTest, no `[TestCleanup]` is involved: implement `IDisposable` on the sealed test
class and dispose the dependency in `Dispose()`. The full `Dispose(bool)` pattern is not
needed for a sealed class.

```csharp
public sealed class With{ClassName} : IDisposable
{
    private readonly {DisposableDep} _dep = new();
    private readonly {ClassName} _sut;

    public With{ClassName}()
    {
        _sut = new {ClassName}(_dep);
    }

    public void Dispose()
    {
        _dep.Dispose();
    }
}
```

## Example (regular class)

```csharp
using Xunit;

namespace N2.Core;

public sealed class WithRequestResult
{
    // -------------------------------------------------------------------------
    // MessageOrDefault
    // -------------------------------------------------------------------------

    [Fact]
    public void MessageOrDefault_EmptyMessage_ReturnsDefault()
    {
        RequestResult result = new(RequestResult.OkCode, string.Empty);
        string message = result.MessageOrDefault("Default message");
        Assert.Equal("Default message", message);
    }

    [Theory]
    [InlineData("Custom")]
    [InlineData("Another")]
    public void MessageOrDefault_NonEmptyMessage_ReturnsMessage(string text)
    {
        RequestResult result = new(RequestResult.OkCode, text);
        string message = result.MessageOrDefault("Default message");
        Assert.Equal(text, message);
    }
}
```

## Filtering

`[Trait]` works on both classes and methods. The MSTest gotcha about `[TestCategory]` only
being matched at class level does not apply.
