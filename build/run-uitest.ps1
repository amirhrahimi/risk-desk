<#
.SYNOPSIS
    Runs the RiskDesk panel self-test (debug build) on one account of an MT4 or
    MT5 terminal and collects its report and screenshots.

.DESCRIPTION
    The self-test (src/Include/RiskDesk/App/UiSelfTest.mqh, ADR-021) exists only
    in a DEBUG build: run 'build.ps1 -Debug' first, and 'build.ps1' afterwards to
    put the release build back.

    The runner
      1. writes the one-time request file MQLx\Files\RiskDesk\uitest.request
         (without it the self-test input is ignored, so a chart left in a
         profile never re-runs the test),
      2. starts the terminal with a startup configuration that logs into
         -Login on -Server (saved password; none is passed or stored), opens a
         chart of -Symbol and attaches Experts\RiskDesk\RiskDesk with
         InpTestUiSelfTest=true (a .set file in the Presets folder),
      3. waits for MQLx\Files\RiskDesk\uitest\<PLATFORM>_<login>_report.txt; the
         EA removes itself and closes the terminal when it is done,
      4. copies the report and the screenshots to -OutDir and prints the report.
    Exit code 0 when the report says "0 failed".

    The self-test never trades; it keeps ui.ini / acct_*.ini in the sandbox
    MQLx\Files\RiskDesk\uitest\store (the owner's saved state is not touched).
    T-21 needs two runs on the same terminal: the second checks, after the real
    restart, what the first saved.
    The terminal must NOT be running (a running instance ignores the
    startup configuration).

.EXAMPLE
    powershell -File build/build.ps1 -Debug -Target mt5
    powershell -File build/run-uitest.ps1 -Platform mt5 -Login A3 -Server ICMarketsEU-Demo -Symbol EURUSD
    powershell -File build/build.ps1
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('mt4', 'mt5')][string]$Platform,
    [Parameter(Mandatory = $true)][string]$Login,
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$Symbol,
    [string]$Inputs = '',            # extra EA inputs 'Key=Value;Key=Value'
    [string]$Period = 'H1',
    [string]$OutDir = (Join-Path $env:TEMP 'RiskDesk-uitest'),
    [int]$TimeoutSec = 240
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
$mql = 'MQL5'; $exeName = 'terminal64.exe'; $ext = '.ex5'; $tag = 'MT5'
if ($Platform -eq 'mt4') { $mql = 'MQL4'; $exeName = 'terminal.exe'; $ext = '.ex4'; $tag = 'MT4' }
$install = (Get-Content -LiteralPath (Join-Path $data 'origin.txt') -TotalCount 1).Trim()
$exe = Join-Path $install $exeName
if (-not (Test-Path -LiteralPath (Join-Path $data "$mql\Experts\RiskDesk\RiskDesk$ext"))) {
    Write-Host "FAIL  $mql\Experts\RiskDesk\RiskDesk$ext missing: run build.ps1 -Debug and install-junctions.ps1"; exit 1
}
$buildMqh = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Include\RiskDesk\Build.mqh'
if (-not (Select-String -LiteralPath $buildMqh -Pattern '^\s*#define\s+RD_TEST_HOOKS' -Quiet)) {
    Write-Host 'NOTE  Build.mqh is in release mode now; the installed build must be a debug build (build.ps1 -Debug) or the test will not start'
}
$running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -and ($_.Path -ieq $exe) } catch { $false } })
if ($running.Count -gt 0) { Write-Host "FAIL  $exe is running; close it first"; exit 1 }

$filesDir = Join-Path $data "$mql\Files\RiskDesk"
$testDir = Join-Path $filesDir 'uitest'
if (-not (Test-Path -LiteralPath $filesDir)) { New-Item -ItemType Directory -Path $filesDir -Force | Out-Null }
$request = Join-Path $filesDir 'uitest.request'
[IO.File]::WriteAllText($request, "requested by build/run-uitest.ps1 $(Get-Date -Format s)`r`n", [Text.Encoding]::ASCII)

#--- EA inputs: a .set file in the Presets folder
$setName = "RiskDesk-uitest-$PID.set"
$setLines = @('InpTestUiSelfTest=true') + @($Inputs -split ';' | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Trim() })
$setText = ($setLines -join "`r`n") + "`r`n"
$setFiles = @()
$dirs = @(Join-Path $data "$mql\Presets")
if ($Platform -eq 'mt4') { $dirs += (Join-Path $data 'presets') }
foreach ($d in $dirs) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    $f = Join-Path $d $setName
    if ($Platform -eq 'mt5') { [IO.File]::WriteAllText($f, $setText, [Text.Encoding]::Unicode) }
    else { [IO.File]::WriteAllText($f, $setText, [Text.Encoding]::ASCII) }
    $setFiles += $f
}

#--- startup configuration (no password: the terminal's saved one is used)
$ini = Join-Path $env:TEMP "RiskDesk-run-uitest-$PID.ini"
if ($Platform -eq 'mt5') {
    $lines = @('[Common]', "Login=$Login", "Server=$Server",
               '[Experts]', 'AllowLiveTrading=1', 'AllowDllImport=0', 'Enabled=1',
               '[StartUp]', 'Expert=RiskDesk\RiskDesk', "ExpertParameters=$setName", "Symbol=$Symbol", "Period=$Period")
    $arguments = @("/config:`"$ini`"")
} else {
    $lines = @("Login=$Login", "Server=$Server", 'ExpertsEnable=true', 'ExpertsTrades=true', 'ExpertsDllImport=false',
               'Expert=RiskDesk\RiskDesk', "ExpertParameters=$setName", "Symbol=$Symbol", "Period=$Period")
    $arguments = @("`"$ini`"")
}
[IO.File]::WriteAllText($ini, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::ASCII)

#--- window captures on request: ChartScreenShot does not draw terminal overlays such as
#--- the One-Click Trading panel, so the self-test asks for a capture of the real window
#--- (PrintWindow, also when the window is covered) by writing uitest\capture.request.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
public static class RdWindowCapture {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    public static bool Save(IntPtr hwnd, string path) {
        SetProcessDPIAware();
        RECT r;
        if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out r)) return false;
        int w = r.R - r.L, h = r.B - r.T;
        if (w <= 0 || h <= 0) return false;
        using (Bitmap bmp = new Bitmap(w, h)) {
            bool ok;
            using (Graphics g = Graphics.FromImage(bmp)) {
                IntPtr dc = g.GetHdc();
                ok = PrintWindow(hwnd, dc, 2);   // PW_RENDERFULLCONTENT
                g.ReleaseHdc(dc);
            }
            if (!ok) return false;
            bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
        return true;
    }
}
"@
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$captureRequest = Join-Path $testDir 'capture.request'
Remove-Item -LiteralPath $captureRequest -Force -ErrorAction SilentlyContinue

$reportName = "${tag}_${Login}_report.txt"
function Get-FreshReport([datetime]$since) {
    $p = Join-Path $testDir $reportName
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    $f = Get-Item -LiteralPath $p
    if ($f.LastWriteTime -ge $since) { return $f }
    return $null
}

Write-Host "RUN   $Platform $Login@$Server  RiskDesk panel self-test on $Symbol $Period  inputs: $($setLines -join ';')"
$started = (Get-Date).AddSeconds(-1)
$found = $null
try {
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $found = Get-FreshReport $started
        if ($found -or $proc.HasExited) { break }
        if (Test-Path -LiteralPath $captureRequest) {
            $name = ([string](Get-Content -LiteralPath $captureRequest -TotalCount 1)).Trim()
            $proc.Refresh()
            $png = Join-Path $OutDir "${tag}_${Login}_window_$name.png"
            if ([RdWindowCapture]::Save($proc.MainWindowHandle, $png)) { Write-Host "SHOT  window $png" }
            else { Write-Host "WARN  window capture '$name' failed" }
            Remove-Item -LiteralPath $captureRequest -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $proc.WaitForExit(30000)) {
        Write-Host "WARN  the terminal did not close itself; closing its window"
        $null = $proc.CloseMainWindow()
        if (-not $proc.WaitForExit(30000)) {
            Write-Host "WARN  terminal (pid $($proc.Id)) did not close; stopping it"
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $found) { $found = Get-FreshReport $started }
} finally {
    Remove-Item -LiteralPath $ini -Force -ErrorAction SilentlyContinue
    foreach ($f in $setFiles) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $request -Force -ErrorAction SilentlyContinue
}

if (-not $found) {
    Write-Host "FAIL  no fresh $reportName within $TimeoutSec s. Is a DEBUG build installed? Check the login and $mql\Logs in $data"
    exit 1
}
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$copied = 0
Get-ChildItem -LiteralPath $testDir -Filter "${tag}_${Login}_*" -File | Where-Object { $_.LastWriteTime -ge $started } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $OutDir -Force
    $copied++
}
Get-Content -LiteralPath $found.FullName | ForEach-Object { Write-Host $_ }
Write-Host "OK    $copied file(s) copied to $OutDir"
if (Select-String -LiteralPath $found.FullName -Pattern 'SUMMARY \d+ passed, 0 failed' -Quiet) { exit 0 }
exit 1
