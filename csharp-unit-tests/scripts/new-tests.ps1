<#
.SYNOPSIS
    Scaffolds unit test stubs for untested C# source files.

.DESCRIPTION
    Runs find-untested.ps1 -ListOnly to discover what needs attention, then:
      create entries: writes a minimal test stub with the correct With*/Using* prefix.
      rename entries: renames the existing *Tests.cs file and updates the class declaration.

    Naming heuristics:
      - name ends in Exception        → For<ClassName>UnitTests  (avoids CA1711)
      - validator (see below)         → Validating<ClassName>
      - public static class           → Using<ClassName>
      - anything else                 → With<ClassName>

    Validator detection (name ends in Validator, implements IRuntimeValidator<...>,
    or declares a public Validate/TryValidate/IsValid method): takes priority over
    the static/regular check, generates a Validating<ClassName> stub.

    DTO detection (name ends in Model/Dto, or implements ICommandRequest/ICommandResponse):
    generates a JSON serialization stub instead of a generic placeholder.

    Factory method detection (Creating<ClassName>) requires human judgement — the
    script flags candidates in the stub comment but does not create a separate file.

    Use -WhatIf to preview all actions without writing or deleting anything.

.PARAMETER SourceDir
    Path to the main project source folder (contains .cs files and .csproj).

.PARAMETER TestDir
    Path to the unit test project folder.

.PARAMETER WhatIf
    Preview mode — show what would happen without writing any files.

.EXAMPLE
    .\new-tests.ps1 -SourceDir .\src\MyApp -TestDir .\src\MyApp.UnitTests
    .\new-tests.ps1 -SourceDir .\src\MyApp -TestDir .\src\MyApp.UnitTests -WhatIf
#>
param(
    [Parameter(Mandatory)]
    [string]$SourceDir,

    [Parameter(Mandatory)]
    [string]$TestDir,

    # Auto: detect from the test project's .csproj; xUnit v3 when no test project exists yet.
    [ValidateSet('Auto', 'XUnit', 'MSTest')]
    [string]$Framework = 'Auto',

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDir = [IO.Path]::GetFullPath($SourceDir)
$testDir   = [IO.Path]::GetFullPath($TestDir)

if ($Framework -eq 'Auto') {
    $Framework = 'XUnit'
    $testCsproj = Get-ChildItem -Path $testDir -Filter '*.csproj' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($testCsproj) {
        $csprojContent = Get-Content $testCsproj.FullName -Raw
        if ($csprojContent -match 'Include="MSTest') { $Framework = 'MSTest' }
    }
}
Write-Host "Framework: $Framework" -ForegroundColor DarkGray

# Stubs are generated in MSTest syntax; convert them when targeting xUnit v3.
function ConvertTo-Framework ([string]$Stub) {
    if ($Framework -ne 'XUnit') { return $Stub }
    $Stub = $Stub -replace 'using Microsoft\.VisualStudio\.TestTools\.UnitTesting;', 'using Xunit;'
    $Stub = $Stub -replace '(?m)^\[TestClass\]\r?\n', ''
    $Stub = $Stub -replace '\[TestMethod\]', '[Fact]'
    $Stub = $Stub -replace 'Assert\.IsNotNull\(', 'Assert.NotNull('
    $Stub = $Stub -replace 'Assert\.AreEqual\(', 'Assert.Equal('
    $Stub = $Stub -replace 'Assert\.Inconclusive\(', 'Assert.Skip('
    return $Stub
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-RootNamespace ([string]$ProjectDir) {
    $csproj = Get-ChildItem -Path $ProjectDir -Filter '*.csproj' | Select-Object -First 1
    if (-not $csproj) {
        Write-Error "No .csproj found in $ProjectDir"
        return $null
    }
    [xml]$xml = Get-Content $csproj.FullName -Raw
    $ns = $xml.Project.PropertyGroup |
          ForEach-Object { $_.RootNamespace } |
          Where-Object   { $_ } |
          Select-Object  -First 1
    if ($ns) { return $ns.Trim() }
    # Default: assembly name = project file name without extension
    return [IO.Path]::GetFileNameWithoutExtension($csproj.Name)
}

function Get-Prefix ([string]$SourceFile, [string]$ClassName) {
    if ($ClassName -and (Test-IsValidator $SourceFile $ClassName)) { return 'Validating' }
    $content = Get-Content $SourceFile -Raw
    if ($content -match 'public\s+static\s+class\b') { return 'Using' }
    return 'With'
}

function Test-HasFactoryMethods ([string]$SourceFile, [string]$ClassName) {
    $content = Get-Content $SourceFile -Raw
    # Static method returning the class's own type — factory candidate
    return $content -match "public\s+static\s+$ClassName\b"
}

function Get-TestNamespace ([string]$RelativePath, [string]$Root) {
    $dir = [IO.Path]::GetDirectoryName($RelativePath)
    if ([string]::IsNullOrEmpty($dir)) { return $Root }
    $parts = $dir.Split([IO.Path]::DirectorySeparatorChar) | Where-Object { $_ }
    return "$Root.$($parts -join '.')"
}

function Test-IsException ([string]$ClassName) {
    return $ClassName -match 'Exception$'
}

function Test-IsValidator ([string]$SourceFile, [string]$ClassName) {
    if ($ClassName -match '(?i)Validator$') { return $true }
    $content = Get-Content $SourceFile -Raw
    if ($content -match 'class\s+\w+[^{]*:\s*[^{]*\bIRuntimeValidator\b') { return $true }
    if ($content -match 'public\s+\S+\s+(Validate|TryValidate|IsValid)\s*\(') { return $true }
    return $false
}

function New-ExceptionStub ([string]$ClassName, [string]$Namespace) {
    return @"
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace $Namespace;

[TestClass]
public sealed class For${ClassName}UnitTests
{
    [TestMethod]
    public void Placeholder()
    {
        // TODO
    }
}
"@
}

function Test-IsDto ([string]$SourceFile, [string]$ClassName) {
    if ($ClassName -match '(?i)(Model|Dto)$') { return $true }
    $content = Get-Content $SourceFile -Raw
    if ($content -match 'class\s+\w+[^{]*:\s*[^{]*\bICommandRequest\b') { return $true }
    if ($content -match 'class\s+\w+[^{]*:\s*[^{]*\bICommandResponse\b') { return $true }
    return $false
}

function New-Stub ([string]$Prefix, [string]$ClassName, [string]$Namespace, [bool]$HasFactories) {
    $factoryNote = if ($HasFactories) {
        "`n    // NOTE: $ClassName has static factory methods — consider a separate Creating$ClassName test class."
    } else { '' }

    return @"
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace $Namespace;
$factoryNote
[TestClass]
public sealed class $Prefix$ClassName
{
    [TestMethod]
    public void Placeholder()
    {
        // TODO
    }
}
"@
}

function New-DtoStub ([string]$ClassName, [string]$Namespace) {
    return @"
using System.Text.Json;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace $Namespace;

[TestClass]
public sealed class With$ClassName
{
    // -------------------------------------------------------------------------
    // JSON serialization
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Serialization_RoundTrip_PreservesAllProperties()
    {
        var dto = new $ClassName
        {
            // TODO: assign every public property with explicit, culture-neutral values.
            // DateTime: always use DateTimeKind.Utc — Local and Unspecified do not
            // survive a System.Text.Json round-trip with their Kind intact.
            //   e.g. CreatedAt = new DateTime(2024, 6, 15, 10, 30, 0, DateTimeKind.Utc)
        };

        var json   = JsonSerializer.Serialize(dto);
        var result = JsonSerializer.Deserialize<$ClassName>(json);

        Assert.IsNotNull(result);
        // TODO: assert each property by value.
        // For DateTime properties assert both value and Kind to catch locale drift:
        //   Assert.AreEqual(dto.CreatedAt, result.CreatedAt);
        //   Assert.AreEqual(DateTimeKind.Utc, result.CreatedAt.Kind);
    }

    [TestMethod]
    public void Serialization_DateTimeProperties_KindIsPreserved()
    {
        // System.Text.Json round-trips DateTimeKind.Utc correctly (appends 'Z').
        // DateTimeKind.Local becomes Unspecified on deserialize — use Utc in DTOs.
        var utcValue = new DateTime(2024, 6, 15, 10, 30, 0, DateTimeKind.Utc);
        var dto = new $ClassName
        {
            // TODO: set the DateTime property under test
            //   SomeDateProperty = utcValue
        };

        var json   = JsonSerializer.Serialize(dto);
        var result = JsonSerializer.Deserialize<$ClassName>(json);

        Assert.IsNotNull(result);
        // TODO: replace with actual DateTime property name
        //   Assert.AreEqual(utcValue, result.SomeDateProperty);
        //   Assert.AreEqual(DateTimeKind.Utc, result.SomeDateProperty.Kind);
        Assert.Inconclusive("Replace TODOs with the actual DateTime property name.");
    }

    [TestMethod]
    public void Deserialization_EmptyJson_ReturnsDefaultInstance()
    {
        var result = JsonSerializer.Deserialize<$ClassName>("{}");
        Assert.IsNotNull(result);
    }

    [TestMethod]
    public void Deserialization_UnknownProperties_AreIgnored()
    {
        var json   = "{\"__unknown\": 42}";
        var result = JsonSerializer.Deserialize<$ClassName>(json);
        Assert.IsNotNull(result);
    }
}
"@
}

function New-ValidatorStub ([string]$ClassName, [string]$Namespace) {
    return @"
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace $Namespace;

// TODO: confirm the validator's return shape and delete the other two examples below:
//   - Result object : ResponseStatus / ValidationResult Validate(T instance)
//   - Predicate      : bool IsValid(T instance)
//   - Throwing       : void Validate(T instance) — throws on invalid input
[TestClass]
public sealed class Validating$ClassName
{
    private readonly $ClassName _sut = new();

    // TODO: replace with a helper that builds a fully valid instance
    // private static SomeRequest ValidInstance() => new() { ... };

    // -------------------------------------------------------------------------
    // Validate
    // -------------------------------------------------------------------------

    [TestMethod]
    public void Validate_AllFieldsValid_ReturnsSuccess()
    {
        // TODO
    }

    [TestMethod]
    public void Validate_Placeholder_Fails()
    {
        // TODO: one test per validation rule — happy path + each distinct failure case
    }
}
"@
}

function Get-RelativeTestPath ([string]$AbsPath) {
    return [IO.Path]::GetRelativePath($testDir, $AbsPath)
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

$rootNs = Get-RootNamespace $sourceDir
if (-not $rootNs) { exit 1 }

$findScript = Join-Path $PSScriptRoot 'find-untested.ps1'
$plan = & $findScript -SourceDir $sourceDir -TestDir $testDir -ListOnly

if (-not $plan) {
    Write-Host "Nothing to do — all source files are covered." -ForegroundColor Green
    exit 0
}

$created = 0
$renamed = 0
$skipped = 0

foreach ($line in $plan) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    $action, $relative = $line -split ':', 2
    $baseName   = [IO.Path]::GetFileNameWithoutExtension($relative)
    $subFolder  = [IO.Path]::GetDirectoryName($relative)
    $sourceFile = Join-Path $sourceDir $relative

    switch ($action) {

        'create' {
            $isException = Test-IsException $baseName
            $isValidator = -not $isException -and (Test-IsValidator $sourceFile $baseName)
            $isDto       = -not $isException -and -not $isValidator -and (Test-IsDto $sourceFile $baseName)
            $prefix      = if ($isException -or $isDto) { 'With' }
                            elseif ($isValidator)        { 'Validating' }
                            else                          { Get-Prefix $sourceFile }
            $namespace   = Get-TestNamespace $relative $rootNs
            $hasFactory  = -not $isException -and -not $isValidator -and -not $isDto -and (Test-HasFactoryMethods $sourceFile $baseName)

            $outName = if ($isException) { "For${baseName}UnitTests.cs" } else { "$prefix$baseName.cs" }
            $stub    = if ($isException)    { New-ExceptionStub $baseName $namespace }
                       elseif ($isValidator) { New-ValidatorStub $baseName $namespace }
                       elseif ($isDto)      { New-DtoStub $baseName $namespace }
                       else             { New-Stub $prefix $baseName $namespace $hasFactory }
            $stub    = ConvertTo-Framework $stub

            $outFile = if ($subFolder) {
                Join-Path $testDir $subFolder $outName
            } else {
                Join-Path $testDir $outName
            }

            if ($WhatIf) {
                $tag = if ($isException)    { ' [exception]' }
                       elseif ($isValidator) { ' [validator]' }
                       elseif ($isDto)      { ' [dto]' }
                       elseif ($hasFactory) { ' [factory candidate]' }
                       else                 { '' }
                Write-Host "[create] $(Get-RelativeTestPath $outFile)$tag" -ForegroundColor Green
            } elseif (Test-Path $outFile) {
                Write-Host "[skip]   $(Get-RelativeTestPath $outFile) already exists" -ForegroundColor DarkGray
                $skipped++
            } else {
                $outDir = [IO.Path]::GetDirectoryName($outFile)
                if (-not (Test-Path $outDir)) {
                    New-Item -ItemType Directory -Path $outDir | Out-Null
                }
                Set-Content -Path $outFile -Value $stub -Encoding utf8NoBOM
                Write-Host "[create] $(Get-RelativeTestPath $outFile)" -ForegroundColor Green
                $created++
            }
        }

        'rename' {
            $prefix  = Get-Prefix $sourceFile $baseName
            $oldName = "${baseName}Tests.cs"
            $newName = "$prefix$baseName.cs"

            $oldFile = Get-ChildItem -Path $testDir -Recurse -Filter $oldName |
                       Where-Object { $_.FullName -notmatch '\\obj\\' } |
                       Select-Object -First 1

            if (-not $oldFile) {
                Write-Host "[warn]   $oldName not found in test project" -ForegroundColor Yellow
                continue
            }

            $newPath = Join-Path $oldFile.DirectoryName $newName

            if ($WhatIf) {
                Write-Host "[rename] $($oldFile.Name) → $newName" -ForegroundColor Cyan
            } elseif (Test-Path $newPath) {
                Write-Host "[skip]   $newName already exists — manual merge needed" -ForegroundColor Yellow
                $skipped++
            } else {
                $content = Get-Content $oldFile.FullName -Raw
                $content = $content -replace "(?<=\bclass\s+)${baseName}Tests\b", "$prefix$baseName"
                Set-Content -Path $newPath -Value $content -Encoding utf8NoBOM
                Remove-Item $oldFile.FullName
                Write-Host "[rename] $($oldFile.Name) → $newName" -ForegroundColor Cyan
                $renamed++
            }
        }

        default {
            Write-Host "[warn]   Unknown action '$action' on line: $line" -ForegroundColor Yellow
        }
    }
}

if ($WhatIf) {
    Write-Host ""
    Write-Host "WhatIf — no files were written." -ForegroundColor DarkGray
} else {
    Write-Host ""
    Write-Host "Done.  Created: $created  Renamed: $renamed  Skipped: $skipped" -ForegroundColor White
}
