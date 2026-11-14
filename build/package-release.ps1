<#
.SYNOPSIS
    Builds the release targets and packs the zip that is attached to a
    GitHub release.

.DESCRIPTION
    1. Runs build.ps1 in release mode (no test hooks) and stops on any error
       or warning.
    2. Copies the compiled files into the folder layout of a MetaTrader data
       folder, so a user can copy MQL4 / MQL5 over the terminal's own:
         MQL4/Experts/RiskDesk.ex4
         MQL4/Scripts/RiskDesk/BrokerProbe.ex4
         MQL5/Experts/RiskDesk.ex5
         MQL5/Scripts/RiskDesk/BrokerProbe.ex5
       plus README.md, LICENSE, NOTICE.md, CHANGELOG.md and the user docs.
       (Release checklist: docs/design/08-testing.md section 7. GatewaySmoke,
       which places demo orders, and the unit tests stay source-only.)
    3. Writes dist/RiskDesk-<version>.zip and dist/RiskDesk-<version>.sha256.txt.
       dist/ is git-ignored: binaries are never committed (CLAUDE.md R14).
       The zip's entry names use '/' whichever PowerShell packs it
       (Compress-Archive of Windows PowerShell 5.1 wrote '\', which unpacks
       into wrongly named files on macOS and Linux).

.PARAMETER SkipBuild
    Pack the binaries that are already in src/ (CI builds them first).

.PARAMETER OutDir
    Folder for the zip and the checksum file. Default dist/.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/package-release.ps1
    pwsh build/package-release.ps1            (macOS / Linux)
#>
param(
    [switch]$SkipBuild,
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BuildMqh = Join-Path $RepoRoot 'src/Include/RiskDesk/Build.mqh'

$buildText = [IO.File]::ReadAllText($BuildMqh)
if ($buildText -match '(?m)^[ \t]*#define[ \t]+RD_TEST_HOOKS') {
    throw 'Build.mqh has RD_TEST_HOOKS active: a release package must be a release build.'
}
if ($buildText -notmatch '(?m)^#define\s+RD_VERSION\s+"([^"]+)"') { throw 'RD_VERSION not found in Build.mqh' }
$version = $Matches[1]

if (-not $SkipBuild) {
    # build.ps1 in a new process of the same PowerShell (powershell.exe, or pwsh on macOS / Linux)
    $shell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'build.ps1')
    if ($LASTEXITCODE -ne 0) { throw "build.ps1 failed (exit $LASTEXITCODE): nothing packed." }
}

$files = [ordered]@{
    'MQL4/Experts/RiskDesk.ex4'             = 'src/Experts/RiskDesk.ex4'
    'MQL4/Scripts/RiskDesk/BrokerProbe.ex4' = 'src/Scripts/RiskDesk/BrokerProbe.ex4'
    'MQL5/Experts/RiskDesk.ex5'             = 'src/Experts/RiskDesk.ex5'
    'MQL5/Scripts/RiskDesk/BrokerProbe.ex5' = 'src/Scripts/RiskDesk/BrokerProbe.ex5'
    'README.md'                             = 'README.md'
    'LICENSE'                               = 'LICENSE'
    'NOTICE.md'                             = 'NOTICE.md'
    'CHANGELOG.md'                          = 'CHANGELOG.md'
}
# every user document (docs/*.md; the design docs stay in the repository)
foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'docs') -Filter '*.md' -File | Sort-Object Name)) {
    $files["docs/$($d.Name)"] = "docs/$($d.Name)"
}

$dist  = Join-Path $RepoRoot 'dist'
if ($OutDir -ne '') { $dist = $OutDir }
if (-not (Test-Path -LiteralPath $dist)) { New-Item -ItemType Directory -Force -Path $dist | Out-Null }
$dist  = (Get-Item -LiteralPath $dist).FullName
$name  = "RiskDesk-$version"
$stage = Join-Path $dist $name
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null

foreach ($k in $files.Keys) {
    $src = Join-Path $RepoRoot $files[$k]
    if (-not (Test-Path -LiteralPath $src)) { throw "Missing $($files[$k]) - build first or check the docs." }
    $dst = Join-Path $stage $k
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    Copy-Item -LiteralPath $src -Destination $dst
}

$zip = Join-Path $dist "$name.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
# entry names exactly as listed in $files ('/' on every host)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zip, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($k in $files.Keys) {
        $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $stage $k), $k, [IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $archive.Dispose()
}

$stage = (Get-Item -LiteralPath $stage).FullName.TrimEnd('\', '/')
$sums = foreach ($f in @(Get-ChildItem -LiteralPath $stage -Recurse -File | Sort-Object FullName)) {
    $rel = $f.FullName.Substring($stage.Length + 1) -replace '\\', '/'
    "$((Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower())  $rel"
}
$sums += "$((Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLower())  $name.zip"
[IO.File]::WriteAllText((Join-Path $dist "$name.sha256.txt"), (($sums -join "`n") + "`n"), (New-Object Text.UTF8Encoding $false))

Write-Host "OK    $zip ($([math]::Round((Get-Item -LiteralPath $zip).Length / 1KB)) KB)"
Write-Host "OK    $(Join-Path $dist "$name.sha256.txt")"
