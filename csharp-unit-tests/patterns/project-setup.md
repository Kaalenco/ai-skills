# Pattern: Unit Test Project Setup

## Naming convention

| Main project | Test project |
|---|---|
| `MyApp.csproj` | `MyApp.UnitTests.csproj` |
| `MyApp.Services.csproj` | `MyApp.Services.UnitTests.csproj` |

Place the test project in a sibling folder next to the main project (e.g., `src/MyApp.UnitTests/`).

## .csproj template

Replace `{MainProjectRootNamespace}`, `{MainProjectFolder}`, and `{MainProject}` with the actual values.

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFrameworks>net8.0;net10.0</TargetFrameworks>
    <LangVersion>12.0</LangVersion>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
    <!-- RootNamespace must match the main library — UnitTests is NOT part of the namespace -->
    <RootNamespace>{MainProjectRootNamespace}</RootNamespace>
    <NoWarn>CA1515;CS1591;CA1707</NoWarn>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.3.0" />
    <PackageReference Include="MSTest.TestAdapter" Version="4.1.0" />
    <PackageReference Include="MSTest.TestFramework" Version="4.1.0" />
    <PackageReference Include="coverlet.collector" Version="8.0.1">
      <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
      <PrivateAssets>all</PrivateAssets>
    </PackageReference>
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\{MainProjectFolder}\{MainProject}.csproj" />
  </ItemGroup>

</Project>
```

## Target framework selection

Match `<TargetFrameworks>` to the concrete runtimes the main library supports:
- Library targets `netstandard2.0;netstandard2.1;net8.0;net10.0` → use `net8.0;net10.0` (test only the concrete runtimes).
- Library targets a single framework → use the same framework.

## Check existing package versions

Before writing package versions, Glob `**/*.UnitTests.csproj` in the solution to find existing test projects and match their package versions. Do not use versions older than those already in use.

## Adding to the solution

After creating the `.csproj`, add it to the solution:
```powershell
dotnet sln src add src/{MainProject}.UnitTests/{MainProject}.UnitTests.csproj
```
