<#
.SYNOPSIS
    Runs the RiskDeskTests unit-test script headless in each terminal and
    reports the result (docs/08-testing.md section 2, optional headless run).

.DESCRIPTION
    For every terminal in $Terminals of build/paths.local.ps1 (filtered by
    -Target), starts the terminal with a startup configuration that opens one
    chart (-Symbol, H1) and runs Scripts\RiskDesk\RiskDeskTests on it. The
    script only does arithmetic: it never trades. The terminal logs into the
    account it used last.

      MT5: terminal64.exe /config:<ini> with [StartUp] ... ShutdownTerminal=1;
           the terminal closes itself when the script ends.
      MT4: terminal.exe <ini> (flat key=value startup file); MT4 has no
           shutdown switch for scripts, so this runner waits for the fresh
           report and then closes the terminal window normally.

    Reads MQLx\Files\RiskDesk\tests_<MT4|MT5>.txt, prints the summary and any
    FAIL lines. Exit code 0 only when every terminal reported 0 failed.

    Needs: build.ps1 run first, the junctions from install-junctions.ps1, and
    the terminal NOT already running (a running instance would ignore the
    startup configuration).

    On macOS and Linux (PowerShell 7) the terminal runs under Wine; MT4's
    window is closed with Wine's taskkill (build/host.ps1, ADR-032).

.PARAMETER Target
    mt4, mt5 or all (default).

.PARAMETER Symbol
    Chart symbol for the script; must exist on the terminal's server. Default EURUSD.

.PARAMETER TimeoutSec
    Maximum wait for the report per terminal. Default 120.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/run-tests.ps1
    powershell -ExecutionPolicy Bypass -File build/run-tests.ps1 -Target mt4 -Symbol EURUSD.a
    pwsh build/run-tests.ps1 -Target mt5      (macOS / Linux)
#>
param(
    [ValidateSet('mt4', 'mt5', 'all')]
    [string]$Target = 'all',
    [string]$Symbol = 'EURUSD',
    [int]$TimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PathsFile = Join-Path $PSScriptRoot 'paths.local.ps1'

. (Join-Path $PSScriptRoot 'host.ps1')
. (Join-Path $PSScriptRoot 'profile-guard.ps1')

function Write-Status([string]$status, [string]$text) {
    $color = 'Gray'
    if ($status -eq 'PASS') { $color = 'Green' }
    elseif ($status -eq 'FAIL') { $color = 'Red' }
    elseif ($status -eq 'WARN') { $color = 'Yellow' }
    Write-Host ('{0,-5} ' -f $status) -ForegroundColor $color -NoNewline
    Write-Host $text
}

# Runs the tests in one terminal; returns $true when the report says 0 failed.
function Invoke-TerminalTests($t) {
    $name = [string]$t.Name
    $platform = ([string]$t.Platform).ToLowerInvariant()
    $data = Expand-RdHome ([string]$t.DataPath)
    $mql = 'MQL5'; $exeName = 'terminal64.exe'; $ext = '.ex5'; $tag = 'MT5'
    if ($platform -eq 'mt4') { $mql = 'MQL4'; $exeName = 'terminal.exe'; $ext = '.ex4'; $tag = 'MT4' }

    $exe = Find-RdTerminalExe $data $exeName
    if (-not $exe) { Write-Status 'FAIL' "$name  $exeName not found through $data (no origin.txt naming its install folder, and not in the folder itself): is DataPath right?"; return $false }
    $wine = $null
    if (-not $RdOnWindows) {
        $wine = Find-RdWine $platform (Get-RdWineSetting $t $platform $Wine4 $Wine5)
        if (-not $wine) { Write-Status 'FAIL' "$name  $(Get-RdWineHint $platform)"; return $false }
    }
    $script = Join-RdPath $data "$mql/Scripts/RiskDesk/RiskDeskTests$ext"
    if (-not (Test-Path -LiteralPath $script)) {
        Write-Status 'FAIL' "$name  $mql/Scripts/RiskDesk/RiskDeskTests$ext missing: run build.ps1 and install-junctions.ps1 first"
        return $false
    }
    if (@(Get-RdProgramProcesses $exe).Count -gt 0) {
        Write-Status 'FAIL' "$name  the terminal is running; close it first (a running instance ignores the startup configuration)"
        return $false
    }

    $report = Join-RdPath $data "$mql/Files/RiskDesk/tests_$tag.txt"
    $ini = Join-Path (Get-RdTempDir) "RiskDesk-run-tests-$tag-$PID.ini"
    $iniArg = ConvertTo-RdWinPath $ini (Get-RdWinePrefix $exe)
    if ($platform -eq 'mt5') {
        $lines = @('[StartUp]', 'Script=RiskDesk\RiskDeskTests', "Symbol=$Symbol", 'Period=H1', 'ShutdownTerminal=1')
        $arguments = @((Format-RdPathArg '/config:' $iniArg))
    } else {
        $lines = @('Script=RiskDesk\RiskDeskTests', "Symbol=$Symbol", 'Period=H1')
        $arguments = @((Format-RdPathArg '' $iniArg))
    }
    [IO.File]::WriteAllText($ini, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

    $started = Get-Date
    # the chart profile is put back as it was after the run (MT4 adds a chart per start, build/profile-guard.ps1)
    $profileSnap = Save-ChartProfile $data $platform
    $proc = $null
    try {
        $proc = Start-RdProgram $exe $arguments $wine
        $fresh = $false
        $deadline = $started.AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            if ((Test-Path -LiteralPath $report) -and (Get-Item -LiteralPath $report).LastWriteTime -ge $started.AddSeconds(-1)) {
                $fresh = $true
                break
            }
            if (-not (Test-RdProgramRunning $proc $exe)) { break }
            Start-Sleep -Milliseconds 500
        }
        # MT5 closes itself; MT4 (or a slow MT5) is asked to close its window.
        if (-not (Wait-RdProgramExit $proc $exe 15000)) {
            Close-RdProgram $proc $exe $wine
            if (-not (Wait-RdProgramExit $proc $exe 20000)) {
                Write-Status 'WARN' "$name  terminal (pid $($proc.Id)) did not close; close it by hand"
            }
        }
    } finally {
        if ($proc) { $null = Wait-RdProgramExit $proc $exe 30000 }
        Restore-ChartProfile $profileSnap
        Remove-Item -LiteralPath $ini -Force -ErrorAction SilentlyContinue
    }

    if (-not $fresh -and (Test-Path -LiteralPath $report) -and (Get-Item -LiteralPath $report).LastWriteTime -ge $started.AddSeconds(-1)) {
        $fresh = $true
    }
    if (-not $fresh) {
        Write-Status 'FAIL' "$name  no fresh report within $TimeoutSec s. Does symbol '$Symbol' exist on this server? See $mql/Logs in $data"
        return $false
    }

    $text = Get-Content -LiteralPath $report -Raw
    $summary = ($text -split "`r?`n") | Where-Object { $_ -match '^RiskDeskTests: \d+ passed, \d+ failed' } | Select-Object -Last 1
    if (-not $summary) { Write-Status 'FAIL' "$name  report has no summary line: $report"; return $false }
    $m = [regex]::Match($summary, '(\d+) passed, (\d+) failed')
    $failed = [int]$m.Groups[2].Value
    if ($failed -eq 0) {
        Write-Status 'PASS' "$name  $summary"
        return $true
    }
    Write-Status 'FAIL' "$name  $summary"
    ($text -split "`r?`n") | Where-Object { $_ -match '^(FAIL |\s+- )' } | ForEach-Object { Write-Host "        $_" }
    Write-Host "        full report: $report"
    return $false
}

#--- configuration -------------------------------------------------------------
if (-not (Test-Path -LiteralPath $PathsFile)) {
    Write-Status 'FAIL' 'build/paths.local.ps1 not found (copy build/paths.example.ps1 and fill it in).'
    exit 1
}
$Wine4 = $null
$Wine5 = $null
$Terminals = @()
. $PathsFile
$selected = @(@($Terminals) | Where-Object { $Target -eq 'all' -or ([string]$_.Platform).ToLowerInvariant() -eq $Target })
if ($selected.Count -eq 0) {
    Write-Status 'FAIL' "no $Target terminal listed in build/paths.local.ps1"
    exit 1
}

Write-Host "RiskDesk unit tests - headless, target $Target, chart $Symbol H1"
$failures = 0
foreach ($t in $selected) {
    if (-not (Invoke-TerminalTests $t)) { $failures++ }
}
Write-Host ''
if ($failures -eq 0) {
    Write-Status 'PASS' "$($selected.Count) of $($selected.Count) terminal(s): 0 failed"
    exit 0
}
Write-Status 'FAIL' "$failures of $($selected.Count) terminal(s) failed or gave no result"
exit 1
