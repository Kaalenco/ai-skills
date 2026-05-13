<#
.SYNOPSIS
    Lists C# source files that have no corresponding unit test file.

.DESCRIPTION
    Scans the source project for .cs files and checks whether a matching
    With*, Using*, or Creating* test file exists in the test project.
    Reports files with no coverage and files whose test class is misnamed.

    Use -ListOnly to emit bare paths suitable for scripting or skill input.
    In that mode each line is prefixed with "create:" or "rename:" to indicate
    the required action, and no human-readable headers are written.

.PARAMETER SourceDir
    Path to the main project source folder (the folder containing .cs files).

.PARAMETER TestDir
    Path to the unit test project folder.

.PARAMETER ListOnly
    Emit machine-readable output: one "create:<path>" or "rename:<path>" line
    per file, no headers, no colour. Intended for skill/script consumption.

.EXAMPLE
    .\find-untested.ps1 -SourceDir .\src\MyApp -TestDir .\src\MyApp.UnitTests

.EXAMPLE
    .\find-untested.ps1 -SourceDir .\src\MyApp -TestDir .\src\MyApp.UnitTests -ListOnly
#>
param(
    [Parameter(Mandatory)]
    [string]$SourceDir,

    [Parameter(Mandatory)]
    [string]$TestDir,

    [switch]$ListOnly
)

$sourceDir = [IO.Path]::GetFullPath($SourceDir)
$testDir   = [IO.Path]::GetFullPath($TestDir)

$sourceFiles = Get-ChildItem -Path $sourceDir -Recurse -Filter '*.cs' |
    Where-Object { $_.FullName -notmatch '\\obj\\' -and $_.FullName -notmatch '\\bin\\' }

$testFileNames = Get-ChildItem -Path $testDir -Recurse -Filter '*.cs' |
    Where-Object { $_.FullName -notmatch '\\obj\\' -and $_.FullName -notmatch '\\bin\\' } |
    Select-Object -ExpandProperty BaseName

$missing    = [System.Collections.Generic.List[string]]::new()
$misnamed   = [System.Collections.Generic.List[string]]::new()

foreach ($file in $sourceFiles) {
    $baseName = $file.BaseName

    # Skip generated files and infrastructure files
    if ($baseName -match '\.(g|AssemblyInfo|GlobalUsings)$') { continue }
    if ($baseName -match '^(Program|Startup|AssemblyInfo)$') { continue }
    if ($file.FullName -match '\\Migrations\\') { continue }

    # Skip interfaces — they have no testable implementation
    if ($baseName -match '^I[A-Z]') { continue }

    # Exception classes use For*UnitTests naming to satisfy CA1711
    $isException = $baseName -match 'Exception$'
    $hasTest = if ($isException) {
                   $testFileNames -contains "For${baseName}UnitTests"
               } else {
                   ($testFileNames -contains "With$baseName") -or
                   ($testFileNames -contains "Using$baseName") -or
                   ($testFileNames -contains "Creating$baseName")
               }

    $relative = [IO.Path]::GetRelativePath($sourceDir, $file.FullName)

    if (-not $hasTest) {
        # Detect legacy *Tests naming — test exists but violates naming convention
        if ($testFileNames -contains "${baseName}Tests") {
            $misnamed.Add($relative)
        } else {
            $missing.Add($relative)
        }
    }
}

if ($ListOnly) {
    foreach ($item in $missing  | Sort-Object) { Write-Output "create:$item" }
    foreach ($item in $misnamed | Sort-Object) { Write-Output "rename:$item" }
    return
}

if ($misnamed.Count -gt 0) {
    Write-Host "Naming convention violations — rename to With*/Using*/Creating* ($($misnamed.Count)):" -ForegroundColor Cyan
    foreach ($item in $misnamed | Sort-Object) {
        Write-Host "  - $item"
    }
}

if ($missing.Count -eq 0 -and $misnamed.Count -eq 0) {
    Write-Host "All source files have a corresponding test file." -ForegroundColor Green
} elseif ($missing.Count -gt 0) {
    Write-Host "Source files with no test coverage ($($missing.Count)):" -ForegroundColor Yellow
    foreach ($item in $missing | Sort-Object) {
        Write-Host "  - $item"
    }
}
