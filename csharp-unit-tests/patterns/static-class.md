# Pattern: Using<ClassName> — Static Class / Static Method Tests

Use when:
- The class under test is `static`.
- You are testing a group of static methods (extension methods, utility methods).
- You are testing static members of an otherwise non-static class.

## File placement

Mirror the main project's folder structure.

| Main project file | Test file |
|---|---|
| `src/MyApp/Utilities/StringUtils.cs` | `src/MyApp.UnitTests/Utilities/UsingStringUtils.cs` |
| `src/MyApp/Encryption/EncryptionHelper.cs` | `src/MyApp.UnitTests/Encryption/UsingEncryptionHelper.cs` |

## Template

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

// Add using directives for the class under test

namespace {RootNamespace};  // or {RootNamespace}.{SubFolder}

[TestClass]
public sealed class Using{ClassName}
{
    // -------------------------------------------------------------------------
    // {StaticMethodName}
    // -------------------------------------------------------------------------

    [TestMethod]
    public void {StaticMethodName}_{Condition}_{Expected}()
    {
        // Act
        var result = {ClassName}.{StaticMethod}(/* args */);

        // Assert
        Assert.AreEqual(expected, result);
    }

    [TestMethod]
    public void {StaticMethodName}_{InvalidCondition}_Throws()
    {
        Assert.Throws<{ExceptionType}>(() => {ClassName}.{StaticMethod}(invalidArg));
    }
}
```

## Key rules

- `sealed` preferred.
- No `[TestInitialize]` needed — static methods have no instance state.
- Group test methods by the static method being tested using comment dividers.
- For extension methods, call on the target type directly for readability:
  ```csharp
  // Preferred — reads naturally
  var token = "hello".ToAuthenticatedValue(expiry, secret);

  // Avoid — obscures intent
  var token = EncryptionUtilities.ToAuthenticatedValue("hello", expiry, secret);
  ```
- Shared read-only test data can be `private static readonly` fields.

## Example

```csharp
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace N2.Core.Encryption;

[TestClass]
public sealed class UsingAuthenticatedValue
{
    private static readonly byte[] Secret = Enumerable.Range(1, 32).Select(i => (byte)i).ToArray();
    private static readonly DateTime FutureExpiry = new(2099, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Constructor_NullValue_TreatedAsEmpty()
    {
        var av = new AuthenticatedValue(null!, FutureExpiry);
        Assert.AreEqual(0, av.Value.Length);
    }

    // -------------------------------------------------------------------------
    // ToTokenString
    // -------------------------------------------------------------------------

    [TestMethod]
    public void ToTokenString_NullSecret_Throws()
    {
        var av = new AuthenticatedValue([1], FutureExpiry);
        Assert.Throws<ArgumentException>(() => av.ToTokenString(null!));
    }

    [TestMethod]
    public void ToTokenString_SecretTooShort_Throws()
    {
        var av = new AuthenticatedValue([1], FutureExpiry);
        Assert.Throws<ArgumentException>(() => av.ToTokenString(new byte[31]));
    }
}
```
