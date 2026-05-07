<#
.SYNOPSIS
    Scaffolds unit test stubs for untested C# source files.

.DESCRIPTION
    Runs find-untested.ps1 -ListOnly to discover what needs attention, then:
      create entries: writes a minimal test stub with the correct With*/Using* prefix.
      rename entries: renames the existing *Tests.cs file and updates the class declaration.

    Prefix heuristic:
      - public static class → Using<ClassName>
      - anything else       → With<ClassName>

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

    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceDir = [IO.Path]::GetFullPath($SourceDir)
$testDir   = [IO.Path]::GetFullPath($TestDir)

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

function Get-Prefix ([string]$SourceFile) {
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
            $prefix      = Get-Prefix $sourceFile
            $namespace   = Get-TestNamespace $relative $rootNs
            $hasFactory  = Test-HasFactoryMethods $sourceFile $baseName
            $stub        = New-Stub $prefix $baseName $namespace $hasFactory

            $outName = "$prefix$baseName.cs"
            $outFile = if ($subFolder) {
                Join-Path $testDir $subFolder $outName
            } else {
                Join-Path $testDir $outName
            }

            if ($WhatIf) {
                $tag = if ($hasFactory) { ' [factory candidate]' } else { '' }
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
            $prefix  = Get-Prefix $sourceFile
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
