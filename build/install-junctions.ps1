<#
.SYNOPSIS
    Links the repository's source folders into every terminal data folder.

.DESCRIPTION
    For each terminal listed in $Terminals in build/paths.local.ps1, creates
    two directory junctions inside its MQL4 or MQL5 folder:

        MQLx\Scripts\RiskDesk  ->  <repo>\src\Scripts\RiskDesk
        MQLx\Include\RiskDesk  ->  <repo>\src\Include\RiskDesk

    On macOS and Linux (PowerShell 7, terminals under Wine) they are symbolic
    links; Wine shows them to MetaTrader as ordinary folders (ADR-032).

    The EA is not linked: it sits in the root of MQLx\Experts (no sub-folder in
    the Navigator), and build.ps1 copies the compiled RiskDesk.ex4/.ex5 there.
    The former MQLx\Experts\RiskDesk junction to this repository is removed.

    One build (build.ps1) then serves every terminal. Idempotent: links that
    already point to the repo are left alone, links pointing elsewhere are
    re-pointed. A real folder that already exists with files in it is never
    touched: the script reports it and you move it away yourself.
    Junctions and symbolic links need no administrator rights.

.PARAMETER Uninstall
    Removes the junctions that point to this repository (only those).

.PARAMETER DryRun
    Prints what would be done without changing anything.

.PARAMETER PathsFile
    Alternative paths file (default build/paths.local.ps1).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/install-junctions.ps1
    powershell -ExecutionPolicy Bypass -File build/install-junctions.ps1 -DryRun
    powershell -ExecutionPolicy Bypass -File build/install-junctions.ps1 -Uninstall
    pwsh build/install-junctions.ps1          (macOS / Linux)
#>
param(
    [switch]$Uninstall,
    [switch]$DryRun,
    [string]$PathsFile = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'host.ps1')

$RepoRoot = Get-RdFullPath (Split-Path -Parent $PSScriptRoot)
if (-not $PathsFile) { $PathsFile = Join-Path $PSScriptRoot 'paths.local.ps1' }

$Links = @(
    @{ Sub = 'Scripts/RiskDesk'; Source = 'src/Scripts/RiskDesk' }
    @{ Sub = 'Include/RiskDesk'; Source = 'src/Include/RiskDesk' }
)
$LinkKind = 'junction'
if (-not $RdOnWindows) { $LinkKind = 'symbolic link' }

function Write-Action([string]$action, [string]$text) {
    $color = 'Gray'
    if ($action -in @('created', 'relinked', 'removed')) { $color = 'Green' }
    elseif ($action -in @('ok', 'absent')) { $color = 'DarkGray' }
    elseif ($action -in @('SKIPPED', 'ERROR')) { $color = 'Red' }
    elseif ($action -eq 'would') { $color = 'Yellow' }
    Write-Host ('  {0,-9} ' -f $action) -ForegroundColor $color -NoNewline
    Write-Host $text
}

# Comparable form of a path: full, no trailing separator; lower case on Windows only.
function Get-NormalizedPath([string]$path) {
    $p = $path
    if ($p.StartsWith('\??\')) { $p = $p.Substring(4) }
    $p = ([IO.Path]::GetFullPath($p)).TrimEnd('\', '/')
    if ($RdOnWindows) { $p = $p.ToLowerInvariant() }
    return $p
}

# Target of a junction/symlink, or $null for a normal folder.
function Get-LinkTarget([string]$path) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
    $target = @($item.Target) | Select-Object -First 1
    if (-not $target) { return '' }
    $target = [string]$target
    # a relative symbolic link is relative to the folder that holds it
    if (-not $RdOnWindows -and -not [IO.Path]::IsPathRooted($target)) { $target = Join-Path (Split-Path -Parent $item.FullName) $target }
    return $target
}

# Removes the junction / symbolic link itself, never the folder it points to.
function Remove-Junction([string]$path) {
    if ($RdOnWindows) { [IO.Directory]::Delete($path, $false) }
    else { [IO.File]::Delete($path) }   # unlink: removes the link only
}

function New-DirLink([string]$path, [string]$target) {
    if ($RdOnWindows) { New-Item -ItemType Junction -Path $path -Value $target | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path $path -Value $target | Out-Null }
}

if (-not (Test-Path -LiteralPath $PathsFile)) {
    Write-Host "Paths file not found: $PathsFile" -ForegroundColor Red
    Write-Host 'Copy build/paths.example.ps1 to build/paths.local.ps1 and fill in $Terminals.'
    exit 1
}
$MetaEditor4 = $null
$MetaEditor5 = $null
$Terminals = @()
. $PathsFile
$Terminals = @($Terminals)
if ($Terminals.Count -eq 0) {
    Write-Host "No terminals listed in $PathsFile (`$Terminals is empty)." -ForegroundColor Red
    exit 1
}

foreach ($l in $Links) {
    $src = Join-Path $RepoRoot $l.Source
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "Repository folder missing: $src" -ForegroundColor Red
        exit 1
    }
}

$mode = 'install'
if ($Uninstall) { $mode = 'uninstall' }
if ($DryRun) { $mode += ' (dry run, nothing is changed)' }
Write-Host "RiskDesk links ($LinkKind) - $mode"
Write-Host "Repository: $RepoRoot"
$problems = 0

foreach ($t in $Terminals) {
    $name = [string]$t.Name
    $platform = ([string]$t.Platform).ToLowerInvariant()
    $data = Expand-RdHome ([string]$t.DataPath)
    Write-Host ''
    Write-Host "$name  [$platform]  $data"

    $mql = $null
    if ($platform -eq 'mt4') { $mql = 'MQL4' } elseif ($platform -eq 'mt5') { $mql = 'MQL5' }
    if (-not $mql) {
        Write-Action 'ERROR' "Platform must be 'mt4' or 'mt5' (got '$platform')"
        $problems++
        continue
    }
    $mqlDir = Join-RdPath $data $mql
    if (-not (Test-Path -LiteralPath $mqlDir)) {
        Write-Action 'ERROR' "$mqlDir not found. DataPath must be the folder that contains $mql (File > Open Data Folder)."
        $problems++
        continue
    }

    # Former EA folder junction (the EA now sits in the Experts root, copied by build.ps1).
    $old = Join-RdPath $mqlDir 'Experts/RiskDesk'
    if (Test-Path -LiteralPath $old) {
        $current = Get-LinkTarget $old
        if ($current -and (Get-NormalizedPath $current).StartsWith((Get-NormalizedPath $RepoRoot) + [IO.Path]::DirectorySeparatorChar)) {
            if ($DryRun) { Write-Action 'would' "remove obsolete $LinkKind $mql/Experts/RiskDesk" }
            else { Remove-Junction $old; Write-Action 'removed' "$mql/Experts/RiskDesk (obsolete: the EA is now $mql/Experts/RiskDesk.ex$($mql.Substring(3)), copied by build.ps1)" }
        }
    }

    foreach ($l in $Links) {
        $link = Join-RdPath $mqlDir $l.Sub
        $target = Join-Path $RepoRoot $l.Source
        $shown = "$mql/$($l.Sub)"
        # a link whose target is gone counts as existing (Test-Path follows the link)
        $exists = (Test-Path -LiteralPath $link) -or ($null -ne (Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue))

        if ($Uninstall) {
            if (-not $exists) { Write-Action 'absent' $shown; continue }
            $current = Get-LinkTarget $link
            if ($null -eq $current) { Write-Action 'SKIPPED' "$shown is a real folder, not a RiskDesk $LinkKind"; $problems++; continue }
            if ((Get-NormalizedPath $current) -ne (Get-NormalizedPath $target)) {
                Write-Action 'SKIPPED' "$shown points to $current, not to this repository"
                continue
            }
            if ($DryRun) { Write-Action 'would' "remove $shown"; continue }
            Remove-Junction $link
            Write-Action 'removed' $shown
            continue
        }

        if ($exists) {
            $current = Get-LinkTarget $link
            if ($null -eq $current) {
                $content = @(Get-ChildItem -LiteralPath $link -Force)
                if ($content.Count -gt 0) {
                    Write-Action 'SKIPPED' "$shown is a real folder with $($content.Count) item(s). Move it out of the way, then run this script again."
                    $problems++
                    continue
                }
                if ($DryRun) { Write-Action 'would' "replace empty folder $shown with a $LinkKind to $target"; continue }
                Remove-Item -LiteralPath $link -Force
            }
            elseif ((Get-NormalizedPath $current) -eq (Get-NormalizedPath $target)) {
                Write-Action 'ok' "$shown -> $target (already linked)"
                continue
            }
            else {
                if ($DryRun) { Write-Action 'would' "re-point $shown from $current to $target"; continue }
                Remove-Junction $link
                New-DirLink $link $target
                Write-Action 'relinked' "$shown -> $target (was $current)"
                continue
            }
        }

        $parent = Split-Path -Parent $link
        if ($DryRun) { Write-Action 'would' "link $shown -> $target"; continue }
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
        New-DirLink $link $target
        Write-Action 'created' "$shown -> $target"
    }
}

Write-Host ''
if ($problems -gt 0) {
    Write-Host "$problems problem(s); see the lines marked ERROR or SKIPPED." -ForegroundColor Red
    exit 1
}
if (-not $Uninstall -and -not $DryRun) {
    Write-Host 'Done. In each terminal: Navigator > right-click > Refresh (or restart the terminal).' -ForegroundColor Green
}
exit 0
