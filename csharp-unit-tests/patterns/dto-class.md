# Pattern: With<ClassName> — DTO JSON Serialization Tests

Use when the class is a Data Transfer Object, identified by:
- Name ending in `Model` or `Dto` (case-insensitive), or
- Implementing `ICommandRequest` or `ICommandResponse`

DTOs travel across serialization boundaries, so the primary concern is that they
survive a JSON round-trip intact and that missing properties deserialize to safe
defaults rather than throwing.

## File placement

Mirror the main project's folder structure.

| Main project file | Test file |
|---|---|
| `src/MyApp/Commands/CreateUserModel.cs` | `src/MyApp.UnitTests/Commands/WithCreateUserModel.cs` |
| `src/MyApp/Identity/UserProfileDto.cs` | `src/MyApp.UnitTests/Identity/WithUserProfileDto.cs` |

## Template

```csharp
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

// Add using directives for the DTO type

namespace {RootNamespace};  // or {RootNamespace}.{SubFolder}

[TestClass]
public sealed class With{ClassName}
{
    // -------------------------------------------------------------------------
    // JSON serialization
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Serialization_RoundTrip_PreservesAllProperties()
    {
        var dto = new {ClassName}
        {
            // Assign every public property with explicit, culture-neutral values.
            // DateTime: always use DateTimeKind.Utc — Local and Unspecified do not
            // survive a System.Text.Json round-trip with their Kind intact.
            //   e.g. CreatedAt = new DateTime(2024, 6, 15, 10, 30, 0, DateTimeKind.Utc)
        };

        var json   = JsonSerializer.Serialize(dto);
        var result = JsonSerializer.Deserialize<{ClassName}>(json);

        Assert.IsNotNull(result);
        // Assert every property by value.
        // For DateTime properties assert both value and Kind:
        //   Assert.AreEqual(dto.CreatedAt, result.CreatedAt);
        //   Assert.AreEqual(DateTimeKind.Utc, result.CreatedAt.Kind);
    }

    [TestMethod]
    public void Serialization_DateTimeProperties_KindIsPreserved()
    {
        // System.Text.Json appends 'Z' for Utc and round-trips Kind correctly.
        // DateTimeKind.Local serializes without 'Z' and deserializes as Unspecified,
        // silently losing timezone intent. DTOs must use Utc.
        var utcValue = new DateTime(2024, 6, 15, 10, 30, 0, DateTimeKind.Utc);
        var dto = new {ClassName} { {DateTimeProperty} = utcValue };

        var json   = JsonSerializer.Serialize(dto);
        var result = JsonSerializer.Deserialize<{ClassName}>(json);

        Assert.IsNotNull(result);
        Assert.AreEqual(utcValue, result.{DateTimeProperty});
        Assert.AreEqual(DateTimeKind.Utc, result.{DateTimeProperty}.Kind);
    }

    [TestMethod]
    public void Deserialization_EmptyJson_ReturnsDefaultInstance()
    {
        var result = JsonSerializer.Deserialize<{ClassName}>("{}");
        Assert.IsNotNull(result);
    }

    [TestMethod]
    public void Deserialization_UnknownProperties_AreIgnored()
    {
        var json   = """{"__unknown": 42}""";
        var result = JsonSerializer.Deserialize<{ClassName}>(json);
        Assert.IsNotNull(result);
    }
}
```

## Key rules

- Always use `System.Text.Json` (not Newtonsoft) unless the project explicitly uses Newtonsoft.
- Test with the same `JsonSerializerOptions` the application uses if non-default options are configured (e.g., camelCase, enum-as-string). Check the project's DI setup for a registered `JsonSerializerOptions`.
- **Every** public property must be asserted by value in the round-trip test — `IsNotNull` alone is insufficient.
- **DateTime properties**: assert both the value and `DateTimeKind`. Use `DateTimeKind.Utc` in test data — `Local` serializes without `Z` and deserializes as `Unspecified`, silently dropping timezone intent.
- **DateTimeOffset**: round-trips correctly regardless of offset; no special handling needed.
- If the DTO has no `DateTime` properties, remove `Serialization_DateTimeProperties_KindIsPreserved`.
- If the DTO has multiple `DateTime` properties, add one assertion per property in the Kind test rather than separate methods.
- Do not test private or internal setters — only the public serialization surface.
- If the DTO also has behaviour (e.g., `Normalize()`, `With*(...)` builders), add those tests after the serialization group using the regular-class pattern.

## Example

```csharp
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace N2.Core.Identity;

[TestClass]
public sealed class WithUserProfile
{
    // -------------------------------------------------------------------------
    // JSON serialization
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Serialization_RoundTrip_PreservesAllProperties()
    {
        var dto = new UserProfile
        {
            UserId    = Guid.Parse("11111111-0000-0000-0000-000000000000"),
            UserName  = "testuser",
            Email     = "test@example.com",
            CreatedAt = new DateTime(2024, 6, 15, 10, 30, 0, DateTimeKind.Utc),
        };

        var json   = JsonSerializer.Serialize(dto);
        var result = JsonSerializer.Deserialize<UserProfile>(json);

        Assert.IsNotNull(result);
        Assert.AreEqual(dto.UserId,    result.UserId);
        Assert.AreEqual(dto.UserName,  result.UserName);
        Assert.AreEqual(dto.Email,     result.Email);
        Assert.AreEqual(dto.CreatedAt, result.CreatedAt);
        Assert.AreEqual(DateTimeKind.Utc, result.CreatedAt.Kind);
    }

    [TestMethod]
    public void Serialization_DateTimeProperties_KindIsPreserved()
    {
        // DateTimeKind.Local serializes without 'Z' and deserializes as Unspecified.
        // DTOs must use Utc to preserve timezone intent across serialization.
        var utcValue = new DateTime(2024, 6, 15, 10, 30, 0, DateTimeKind.Utc);
        var dto = new UserProfile { CreatedAt = utcValue };

        var json   = JsonSerializer.Serialize(dto);
        var result = JsonSerializer.Deserialize<UserProfile>(json);

        Assert.IsNotNull(result);
        Assert.AreEqual(utcValue, result.CreatedAt);
        Assert.AreEqual(DateTimeKind.Utc, result.CreatedAt.Kind);
    }

    [TestMethod]
    public void Deserialization_EmptyJson_ReturnsDefaultInstance()
    {
        var result = JsonSerializer.Deserialize<UserProfile>("{}");
        Assert.IsNotNull(result);
    }

    [TestMethod]
    public void Deserialization_UnknownProperties_AreIgnored()
    {
        var json   = """{"__unknown": 42}""";
        var result = JsonSerializer.Deserialize<UserProfile>(json);
        Assert.IsNotNull(result);
    }
}
```
