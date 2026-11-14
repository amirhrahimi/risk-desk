<#
.SYNOPSIS
    Checks that RD_VERSION and RD_VERSION_PROP in Build.mqh name the same version.

.DESCRIPTION
    RD_VERSION is the SemVer version (1.8.0, 1.8.0-rc.1). RD_VERSION_PROP is the
    same version in the 'x.yz' form that '#property version' accepts without
    warning 68: major.minor patch, so 1.8.0 = "1.80" and 1.8.0-rc.1 = "1.80"
    (ADR-029). Build metadata added by CI (+dev.<commit>) is ignored.

    Fails (exit 1) when RD_VERSION is not a SemVer version, when minor or patch
    is above 9 (the x.yz form has one digit for each), or when RD_VERSION_PROP
    does not match. Run by build.ps1 and by the CI workflow (.github/workflows/build.yml).

.PARAMETER Path
    The Build.mqh to check. Default: src/Include/RiskDesk/Build.mqh.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/check-version.ps1
    pwsh build/check-version.ps1              (macOS / Linux)
#>
param(
    [string]$Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/Include/RiskDesk/Build.mqh')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Stop-Check([string]$text) {
    Write-Host 'FAIL  ' -ForegroundColor Red -NoNewline
    Write-Host $text
    exit 1
}

$text = [IO.File]::ReadAllText($Path)
if ($text -notmatch '(?m)^#define\s+RD_VERSION\s+"([^"]*)"') { Stop-Check "RD_VERSION not found in $Path" }
$version = $Matches[1]
if ($text -notmatch '(?m)^#define\s+RD_VERSION_PROP\s+"([^"]*)"') { Stop-Check "RD_VERSION_PROP not found in $Path" }
$prop = $Matches[1]

$semver = '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if ($version -notmatch $semver) {
    Stop-Check "RD_VERSION ""$version"" is not a SemVer version (MAJOR.MINOR.PATCH, optionally -prerelease)."
}
$major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]
if ($minor -gt 9 -or $patch -gt 9) {
    Stop-Check "RD_VERSION $version does not fit RD_VERSION_PROP's 'x.yz' form (one digit each for minor and patch). Choose a new mapping first and record it in an ADR (see ADR-029)."
}
$expected = '{0}.{1}{2}' -f $major, $minor, $patch
if ($prop -ne $expected) {
    Stop-Check "RD_VERSION_PROP is ""$prop"" but RD_VERSION $version needs ""$expected"". Bump both together in Build.mqh."
}

Write-Host 'PASS  ' -ForegroundColor Green -NoNewline
Write-Host "version $version, #property version $prop"
exit 0
