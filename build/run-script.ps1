<#
.SYNOPSIS
    Runs one RiskDesk script (BrokerProbe, GatewaySmoke, ...) on one account of
    an MT4 or MT5 terminal and waits for its report file.

.DESCRIPTION
    Starts the terminal of build/paths.local.ps1 for -Platform with a startup
    configuration that logs into -Login on -Server, opens a chart of -Symbol
    and runs Scripts\RiskDesk\<Script> with the given inputs (a .set file in
    the terminal's Presets folder). The password is NOT passed: the terminal
    uses the one it has saved for that login (tick "Save password" when you
    open or log into the account). Algo trading is switched on for the run.

      MT5: terminal64.exe /config:<ini> ([Common], [Experts], [StartUp],
           ShutdownTerminal=1: the terminal closes when the script ends).
      MT4: terminal.exe <ini> (flat key=value file). MT4 has no shutdown
           switch for scripts: the runner waits for the fresh report and then
           closes the terminal window.

    The report is the newest file in MQLx\Files\RiskDesk matching -Report
    (wildcards) written after the start. Its path is printed; exit code 0 when
    a fresh report appeared.

    Needs build.ps1 and install-junctions.ps1 run first and the terminal NOT
    running (a running instance ignores the startup configuration).

    GatewaySmoke sends real orders: the script itself refuses non-demo
    accounts (rule R13). Pass InpConfirm=false to run it unattended.

.EXAMPLE
    powershell -File build/run-script.ps1 -Platform mt5 -Login A6 -Server MetaQuotes-Demo `
        -Script BrokerProbe -Symbol EURUSD -Report 'probe_*_A6_*.txt'
    powershell -File build/run-script.ps1 -Platform mt4 -Login A1 -Server IG-DEMO `
        -Script GatewaySmoke -Symbol EURUSD -Inputs 'InpConfirm=false' -Report 'smoke_*_A1_*.txt'
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('mt4', 'mt5')][string]$Platform,
    [Parameter(Mandatory = $true)][string]$Login,
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Script,
    [Parameter(Mandatory = $true)][string]$Symbol,
    [Parameter(Mandatory = $true)][string]$Report,
    [string]$Inputs = '',            # 'Key=Value;Key=Value' (enums as numbers, bools as true/false)
    [string]$Period = 'H1',
    [int]$TimeoutSec = 300
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$PathsFile = Join-Path $PSScriptRoot 'paths.local.ps1'
if (-not (Test-Path -LiteralPath $PathsFile)) { Write-Host 'FAIL  build/paths.local.ps1 not found'; exit 1 }
$Terminals = @()
. $PathsFile
$t = @(@($Terminals) | Where-Object { ([string]$_.Platform).ToLowerInvariant() -eq $Platform }) | Select-Object -First 1
if (-not $t) { Write-Host "FAIL  no $Platform terminal in build/paths.local.ps1"; exit 1 }

$data = [string]$t.DataPath
$mql = 'MQL5'; $exeName = 'terminal64.exe'; $ext = '.ex5'
if ($Platform -eq 'mt4') { $mql = 'MQL4'; $exeName = 'terminal.exe'; $ext = '.ex4' }
$install = (Get-Content -LiteralPath (Join-Path $data 'origin.txt') -TotalCount 1).Trim()
$exe = Join-Path $install $exeName
if (-not (Test-Path -LiteralPath (Join-Path $data "$mql\Scripts\RiskDesk\$Script$ext"))) {
    Write-Host "FAIL  $mql\Scripts\RiskDesk\$Script$ext missing: run build.ps1 and install-junctions.ps1"; exit 1
}
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -and ($_.Path -ieq $exe) } catch { $false } })
if ($running.Count -gt 0) { Write-Host "FAIL  $exe is running; close it first"; exit 1 }

#--- script inputs: a .set file in the Presets folder
$setName = ''
$setFiles = @()
if ($Inputs -ne '') {
    $setName = "RiskDesk-run-$PID.set"
    $setLines = @($Inputs -split ';' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
    $setText = ($setLines -join "`r`n") + "`r`n"
    $dirs = @(Join-Path $data "$mql\Presets")
    if ($Platform -eq 'mt4') { $dirs += (Join-Path $data 'presets') }
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        $f = Join-Path $d $setName
        if ($Platform -eq 'mt5') { [IO.File]::WriteAllText($f, $setText, [Text.Encoding]::Unicode) }
        else { [IO.File]::WriteAllText($f, $setText, [Text.Encoding]::ASCII) }
        $setFiles += $f
    }
}

#--- startup configuration (no password: the terminal's saved one is used)
$ini = Join-Path $env:TEMP "RiskDesk-run-script-$PID.ini"
if ($Platform -eq 'mt5') {
    $lines = @('[Common]', "Login=$Login", "Server=$Server",
               '[Experts]', 'AllowLiveTrading=1', 'AllowDllImport=0', 'Enabled=1',
               '[StartUp]', "Script=RiskDesk\$Script", "Symbol=$Symbol", "Period=$Period", 'ShutdownTerminal=1')
    if ($setName -ne '') { $lines += "ScriptParameters=$setName" }
    $arguments = @("/config:`"$ini`"")
} else {
    $lines = @("Login=$Login", "Server=$Server", 'ExpertsEnable=true', 'ExpertsTrades=true', 'ExpertsDllImport=false',
               "Script=RiskDesk\$Script", "Symbol=$Symbol", "Period=$Period")
    if ($setName -ne '') { $lines += "ScriptParameters=$setName" }
    $arguments = @("`"$ini`"")
}
[IO.File]::WriteAllText($ini, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

$filesDir = Join-Path $data "$mql\Files\RiskDesk"
function Get-FreshReport([datetime]$since) {
    if (-not (Test-Path -LiteralPath $filesDir)) { return $null }
    return Get-ChildItem -LiteralPath $filesDir -Filter $Report -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $since } | Sort-Object LastWriteTime | Select-Object -Last 1
}

# the chart profile is put back as it was after the run (MT4 adds a chart per start, build/profile-guard.ps1)
. (Join-Path $PSScriptRoot 'profile-guard.ps1')
$profileSnap = Save-ChartProfile $data $Platform
Write-Host "RUN   $Platform $Login@$Server  $Script on $Symbol $Period  inputs: $(if ($Inputs) { $Inputs } else { 'defaults' })"
$started = (Get-Date).AddSeconds(-1)
$found = $null
$proc = $null
try {
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $lastSize = -1
    while ((Get-Date) -lt $deadline) {
        $found = Get-FreshReport $started
        if ($found) {
            # wait until the file stops growing (the report is written in one go at the end)
            if ($found.Length -eq $lastSize) { break }
            $lastSize = $found.Length
        }
        if ($proc.HasExited) { $found = Get-FreshReport $started; break }
        Start-Sleep -Milliseconds 1500
    }
    if (-not $proc.WaitForExit(15000)) {
        $null = $proc.CloseMainWindow()
        if (-not $proc.WaitForExit(30000)) {
            Write-Host "WARN  terminal (pid $($proc.Id)) did not close; stopping it"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
} finally {
    if ($proc -and -not $proc.HasExited) { $null = $proc.WaitForExit(30000) }
    Restore-ChartProfile $profileSnap
    Remove-Item -LiteralPath $ini -Force -ErrorAction SilentlyContinue
    foreach ($f in $setFiles) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

if (-not $found) {
    Write-Host "FAIL  no fresh $Report within $TimeoutSec s. Check the login (saved password?), the symbol name, and $mql\Logs in $data"
    exit 1
}
Write-Host "OK    report: $($found.FullName)"
exit 0
