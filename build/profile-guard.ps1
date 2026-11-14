<#
.SYNOPSIS
    Keeps a terminal's chart profile as the owner left it during an unattended run.
    Dot-sourced by run-tests.ps1, run-script.ps1 and run-uitest.ps1.

.DESCRIPTION
    A terminal saves its open charts into the active profile when it closes. MT4
    treats the chart of a startup configuration as a temporary chart (start.tpl:
    temp_chart=1) that takes a chart-file number without removing the file that
    had it, so every unattended start left one more copy of the owner's chart
    (P4: 74 charts; P5: XAUUSD M1 twice more after two runs). The runners
    therefore copy the profile's files before the terminal starts and put them
    back after it has closed: the owner's charts, their order and their EAs stay
    exactly as they were. MT5 does not show the problem; it is guarded the same
    way for safety.

    Save-ChartProfile  -> snapshot object (call before Start-Process)
    Restore-ChartProfile $snap  (call after the terminal process has exited)
#>

if (-not (Get-Command -Name Get-RdTempDir -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'host.ps1') }

function Get-ChartProfileDir([string]$data, [string]$platform) {
    if ($platform -eq 'mt4') {
        $last = Join-RdPath $data 'profiles/lastprofile.ini'
        $name = 'default'
        if (Test-Path -LiteralPath $last) {
            $n = ([string](Get-Content -LiteralPath $last -TotalCount 1)).Trim()
            if ($n -ne '') { $name = $n }
        }
        return (Join-RdPath $data "profiles/$name")
    }
    $name = 'Default'
    $common = Join-RdPath $data 'config/common.ini'
    if (Test-Path -LiteralPath $common) {
        $m = Select-String -LiteralPath $common -Encoding Unicode -Pattern '^ProfileLast=(.+)$' | Select-Object -First 1
        if ($m) { $name = $m.Matches[0].Groups[1].Value.Trim() }
    }
    return (Join-RdPath $data "MQL5/Profiles/Charts/$name")
}

function Save-ChartProfile([string]$data, [string]$platform) {
    $dir = Get-ChartProfileDir $data $platform
    $snap = [pscustomobject]@{ Dir = $dir; Backup = $null; Files = 0 }
    if (-not (Test-Path -LiteralPath $dir)) { return $snap }
    $bak = Join-Path (Get-RdTempDir) ("RiskDesk-profile-" + $platform + "-" + $PID + "-" + (Get-Date -Format 'HHmmss'))
    New-Item -ItemType Directory -Path $bak -Force | Out-Null
    $files = @(Get-ChildItem -LiteralPath $dir -File)
    foreach ($f in $files) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $bak $f.Name) -Force }
    $snap.Backup = $bak
    $snap.Files = $files.Count
    return $snap
}

function Restore-ChartProfile($snap) {
    if (-not $snap -or -not $snap.Backup -or -not (Test-Path -LiteralPath $snap.Backup)) { return }
    $dir = $snap.Dir
    $now = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)
    $saved = @(Get-ChildItem -LiteralPath $snap.Backup -File)
    $added = @($now | Where-Object { $n = $_.Name; -not ($saved | Where-Object { $_.Name -ieq $n }) })
    foreach ($f in $now) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    foreach ($f in $saved) { Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $dir $f.Name) -Force }
    Remove-Item -LiteralPath $snap.Backup -Recurse -Force -ErrorAction SilentlyContinue
    $charts = @($added | Where-Object { $_.Extension -ieq '.chr' })
    if ($charts.Count -gt 0) {
        Write-Host ("NOTE  chart profile restored: the terminal had added " + $charts.Count + " chart file(s) (" +
                    (($charts | ForEach-Object { $_.Name }) -join ', ') + ") to $dir")
    }
}
