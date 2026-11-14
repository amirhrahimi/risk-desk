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
    (wildcards) written after the start. Its path is printed with a short
    result (the last run's FAIL/SKIP rows and its [summary] section); exit
    code 0 when a fresh report appeared.

    Needs build.ps1 and install-junctions.ps1 run first and the terminal NOT
    running (a running instance ignores the startup configuration).

    GatewaySmoke sends real orders: the script itself refuses non-demo
    accounts (rule R13). Pass InpConfirm=false to run it unattended.

    On macOS and Linux (PowerShell 7) the terminal runs under Wine; MT4's
    window is closed with Wine's taskkill (build/host.ps1, ADR-032).

.EXAMPLE
    powershell -File build/run-script.ps1 -Platform mt5 -Login <login> -Server MetaQuotes-Demo `
        -Script BrokerProbe -Symbol EURUSD -Report 'probe_*_<login>_*.txt'
    powershell -File build/run-script.ps1 -Platform mt4 -Login <login> -Server IG-DEMO `
        -Script GatewaySmoke -Symbol EURUSD -Inputs 'InpConfirm=false' -Report 'smoke_*_<login>_*.txt'
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

. (Join-Path $PSScriptRoot 'host.ps1')

$PathsFile = Join-Path $PSScriptRoot 'paths.local.ps1'
if (-not (Test-Path -LiteralPath $PathsFile)) { Write-Host 'FAIL  build/paths.local.ps1 not found'; exit 1 }
$Wine4 = $null
$Wine5 = $null
$Terminals = @()
. $PathsFile
$t = @(@($Terminals) | Where-Object { ([string]$_.Platform).ToLowerInvariant() -eq $Platform }) | Select-Object -First 1
if (-not $t) { Write-Host "FAIL  no $Platform terminal in build/paths.local.ps1"; exit 1 }

$data = Expand-RdHome ([string]$t.DataPath)
$mql = 'MQL5'; $exeName = 'terminal64.exe'; $ext = '.ex5'
if ($Platform -eq 'mt4') { $mql = 'MQL4'; $exeName = 'terminal.exe'; $ext = '.ex4' }
$exe = Find-RdTerminalExe $data $exeName
if (-not $exe) { Write-Host "FAIL  $exeName not found through $data (no origin.txt naming its install folder, and not in the folder itself): is DataPath right?"; exit 1 }
$wine = $null
if (-not $RdOnWindows) {
    $wine = Find-RdWine $Platform (Get-RdWineSetting $t $Platform $Wine4 $Wine5)
    if (-not $wine) { Write-Host "FAIL  $(Get-RdWineHint $Platform)"; exit 1 }
}
if (-not (Test-Path -LiteralPath (Join-RdPath $data "$mql/Scripts/RiskDesk/$Script$ext"))) {
    Write-Host "FAIL  $mql/Scripts/RiskDesk/$Script$ext missing: run build.ps1 and install-junctions.ps1"; exit 1
}
if (@(Get-RdProgramProcesses $exe).Count -gt 0) { Write-Host "FAIL  $exe is running; close it first"; exit 1 }

#--- script inputs: a .set file in the Presets folder
$setName = ''
$setFiles = @()
if ($Inputs -ne '') {
    $setName = "RiskDesk-run-$PID.set"
    $setLines = @($Inputs -split ';' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
    $setText = ($setLines -join "`r`n") + "`r`n"
    $dirs = @(Join-RdPath $data "$mql/Presets")
    if ($Platform -eq 'mt4') { $dirs += (Join-RdPath $data 'presets') }
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        $f = Join-Path $d $setName
        if ($Platform -eq 'mt5') { [IO.File]::WriteAllText($f, $setText, [Text.Encoding]::Unicode) }
        else { [IO.File]::WriteAllText($f, $setText, [Text.Encoding]::ASCII) }
        $setFiles += $f
    }
}

#--- startup configuration (no password: the terminal's saved one is used)
$ini = Join-Path (Get-RdTempDir) "RiskDesk-run-script-$PID.ini"
$iniArg = ConvertTo-RdWinPath $ini (Get-RdWinePrefix $exe)
if ($Platform -eq 'mt5') {
    $lines = @('[Common]', "Login=$Login", "Server=$Server",
               '[Experts]', 'AllowLiveTrading=1', 'AllowDllImport=0', 'Enabled=1',
               '[StartUp]', "Script=RiskDesk\$Script", "Symbol=$Symbol", "Period=$Period", 'ShutdownTerminal=1')
    if ($setName -ne '') { $lines += "ScriptParameters=$setName" }
    $arguments = @((Format-RdPathArg '/config:' $iniArg))
} else {
    $lines = @("Login=$Login", "Server=$Server", 'ExpertsEnable=true', 'ExpertsTrades=true', 'ExpertsDllImport=false',
               "Script=RiskDesk\$Script", "Symbol=$Symbol", "Period=$Period")
    if ($setName -ne '') { $lines += "ScriptParameters=$setName" }
    $arguments = @((Format-RdPathArg '' $iniArg))
}
[IO.File]::WriteAllText($ini, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

$filesDir = Join-RdPath $data "$mql/Files/RiskDesk"
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
    $proc = Start-RdProgram $exe $arguments $wine
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $lastSize = -1
    while ((Get-Date) -lt $deadline) {
        $found = Get-FreshReport $started
        if ($found) {
            # wait until the file stops growing (the report is written in one go at the end)
            if ($found.Length -eq $lastSize) { break }
            $lastSize = $found.Length
        }
        if (-not (Test-RdProgramRunning $proc $exe)) { $found = Get-FreshReport $started; break }
        Start-Sleep -Milliseconds 1500
    }
    if (-not (Wait-RdProgramExit $proc $exe 15000)) {
        Close-RdProgram $proc $exe $wine
        if (-not (Wait-RdProgramExit $proc $exe 30000)) {
            Write-Host "WARN  terminal (pid $($proc.Id)) did not close; stopping it"
            Stop-RdProgram $proc $exe $wine
        }
    }
} finally {
    if ($proc) { $null = Wait-RdProgramExit $proc $exe 30000 }
    Restore-ChartProfile $profileSnap
    Remove-Item -LiteralPath $ini -Force -ErrorAction SilentlyContinue
    foreach ($f in $setFiles) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

if (-not $found) {
    Write-Host "FAIL  no fresh $Report within $TimeoutSec s. Check the login (saved password?), the symbol name, and $mql/Logs in $data"
    exit 1
}
Write-Host "OK    report: $($found.FullName)"
# short result, so the report need not be read: the last run in the file (GatewaySmoke appends one
# block per run, each starting with '# RiskDesk '), its FAIL/SKIP rows and its [summary] section
$lines = @([IO.File]::ReadAllLines($found.FullName, [Text.Encoding]::UTF8))
$start = 0
for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^# RiskDesk ') { $start = $i } }
$inSummary = $false; $shown = 0
for ($i = $start; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    if ($i -eq $start -and $line -match '^# RiskDesk ') { Write-Host "      $line"; continue }
    if ($line -match '^\[(.+)\]\s*$') { $inSummary = ($Matches[1] -eq 'summary'); if ($inSummary) { Write-Host '      [summary]' }; continue }
    if ($inSummary -or $line -match '^\s+\S+\s+.+?\s+(FAIL|SKIP)\s+\d+') {
        if ($line.Trim() -eq '') { continue }
        if ($found.Name -like 'probe_*' -and $line -match '^\s+- ') { continue }   # the items: merged in SUMMARY.md
        if ($shown -ge 30) { Write-Host '      ... (more in the report)'; break }
        Write-Host "      $line"; $shown++
    }
}
if ($found.Name -like 'probe_*') { Write-Host '      copy it into broker-profiles/ and run build/summarize-profiles.ps1: SUMMARY.md lists the items to check' }
exit 0
