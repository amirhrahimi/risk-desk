<#
.SYNOPSIS
    Checks the build scripts themselves, without MetaTrader, on Windows,
    macOS or Linux (ADR-032).

.DESCRIPTION
    Run by .github/workflows/scripts.yml with PowerShell 7 on Linux, macOS
    and Windows and with Windows PowerShell 5.1, and locally after changing a
    script in build/. Everything happens in a temporary folder:
    build/paths.local.ps1, dist/ and the terminals are not touched.

      1. every build/*.ps1 parses;
      2. check-version.ps1 passes;
      3. summarize-profiles.ps1 reproduces broker-profiles/SUMMARY.md;
      4. the path helpers of host.ps1 (Wine paths on macOS / Linux, the
         terminal found with and without origin.txt, names in any case);
      5. install-junctions.ps1 links a made-up terminal data folder to src/,
         leaves the links alone when run again and removes only the links;
      6. build.ps1 finds the sources and stops with "MetaEditor not found"
         when no MetaEditor is configured;
      7. package-release.ps1 -SkipBuild lays out the zip with '/' in every
         entry name. Needs the compiled .ex4/.ex5 in src/; with -FakeBinaries
         (CI) placeholders are written there for the check and removed again.

    Exit code 0 when every check passes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/test-build-scripts.ps1
    pwsh build/test-build-scripts.ps1
#>
param(
    [switch]$FakeBinaries
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'host.ps1')

$RepoRoot = Get-RdFullPath (Split-Path -Parent $PSScriptRoot)
$Shell = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$Temp = Join-Path (Get-RdTempDir) "RiskDesk-buildtest-$PID"
$script:Failed = 0
$script:Passed = 0

function Write-Check([bool]$ok, [string]$text) {
    if ($ok) { $script:Passed++; Write-Host 'PASS  ' -ForegroundColor Green -NoNewline }
    else { $script:Failed++; Write-Host 'FAIL  ' -ForegroundColor Red -NoNewline }
    Write-Host $text
}

# Runs a build script in a new process of this PowerShell; returns exit code and output.
function Invoke-BuildScript([string]$name, [string[]]$arguments) {
    $argv = @('-NoProfile')
    if ($RdOnWindows) { $argv += @('-ExecutionPolicy', 'Bypass') }
    $argv += @('-File', (Join-Path $PSScriptRoot $name)) + $arguments
    $out = & $Shell @argv 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}

function Show-Output([string]$text) {
    foreach ($l in ($text -split "`r?`n")) { if ($l.Trim() -ne '') { Write-Host "        $l" } }
}

$psName = 'PowerShell ' + $PSVersionTable.PSVersion.ToString()
$os = 'Windows'
if ($RdOnMac) { $os = 'macOS' } elseif (-not $RdOnWindows) { $os = 'Linux' }
Write-Host "RiskDesk build-script checks - $psName on $os"
New-Item -ItemType Directory -Force -Path $Temp | Out-Null
$fakes = @()
try {
    #--- 1. parse
    $bad = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File)) {
        $tokens = $null; $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
        foreach ($e in @($errors)) { $bad += "$($f.Name):$($e.Extent.StartLineNumber) $($e.Message)" }
    }
    Write-Check ($bad.Count -eq 0) "every build/*.ps1 parses"
    foreach ($b in $bad) { Write-Host "        $b" }

    #--- 2. version
    $r = Invoke-BuildScript 'check-version.ps1' @()
    Write-Check ($r.Code -eq 0) 'check-version.ps1'
    if ($r.Code -ne 0) { Show-Output $r.Out }

    #--- 3. SUMMARY.md
    $profiles = Join-Path $Temp 'profiles'
    New-Item -ItemType Directory -Force -Path $profiles | Out-Null
    Copy-Item -Path (Join-Path $RepoRoot 'broker-profiles/*.txt') -Destination $profiles
    $r = Invoke-BuildScript 'summarize-profiles.ps1' @('-ProfilesDir', $profiles)
    $made = [IO.File]::ReadAllText((Join-Path $profiles 'SUMMARY.md')).Replace("`r`n", "`n")
    $kept = [IO.File]::ReadAllText((Join-Path $RepoRoot 'broker-profiles/SUMMARY.md')).Replace("`r`n", "`n")
    Write-Check ($r.Code -eq 0 -and $made -eq $kept) 'summarize-profiles.ps1 reproduces broker-profiles/SUMMARY.md'
    if ($made -ne $kept) { Write-Host '        differs: run build/summarize-profiles.ps1 and commit SUMMARY.md, or fix the script' }

    #--- 4. host.ps1
    $install = Join-Path $Temp 'pfx/drive_c/Program Files/MetaTrader 5'
    $data = Join-Path $Temp 'pfx/drive_c/users/dev/AppData/Roaming/MetaQuotes/Terminal/ABC'
    New-Item -ItemType Directory -Force -Path $install, (Join-Path $data 'Config') | Out-Null
    Set-Content -LiteralPath (Join-Path $install 'terminal64.exe') -Value 'placeholder'
    Set-Content -LiteralPath (Join-Path $install 'MetaEditor64.exe') -Value 'placeholder'
    Set-Content -LiteralPath (Join-Path $data 'Config/common.ini') -Value 'placeholder'
    $prefix = Get-RdFullPath (Join-Path $Temp 'pfx')
    $installWin = ConvertTo-RdWinPath $install $prefix
    Set-Content -LiteralPath (Join-Path $data 'origin.txt') -Value $installWin
    $exe = Find-RdTerminalExe $data 'terminal64.exe'
    Write-Check ($null -ne $exe -and (Get-RdFullPath $exe) -eq (Get-RdFullPath (Join-Path $install 'terminal64.exe'))) 'host.ps1: terminal found through origin.txt'
    $exe = Find-RdTerminalExe $install 'terminal64.exe'
    Write-Check ($null -ne $exe) 'host.ps1: terminal found in a data folder without origin.txt (portable, macOS app, Linux installer)'
    if ($RdOnWindows) {
        Write-Check ((Format-RdPathArg '/compile:' 'C:\a b\x.mq5') -eq '/compile:"C:\a b\x.mq5"') 'host.ps1: Windows arguments keep their quotes'
        Write-Check ((Join-RdPath $data 'config/common.ini') -eq (Join-Path $data 'config/common.ini')) 'host.ps1: Join-RdPath is Join-Path on Windows'
    } else {
        Write-Check ((Get-RdWinePrefix (Join-Path $install 'terminal64.exe')) -eq $prefix) 'host.ps1: Wine prefix from a program path'
        Write-Check ($installWin -eq 'C:\Program Files\MetaTrader 5') "host.ps1: path in drive_c -> C:\ ($installWin)"
        $z = ConvertTo-RdWinPath '/tmp/rd x/a.ini' $prefix
        Write-Check ($z -eq 'Z:\tmp\rd x\a.ini') "host.ps1: path outside the prefix -> Z:\ ($z)"
        $back = ConvertFrom-RdWinPath 'C:\Program Files\MetaTrader 5' $prefix
        Write-Check ((Get-RdFullPath $back) -eq (Get-RdFullPath $install)) 'host.ps1: C:\ back to the prefix'
        Write-Check ((ConvertFrom-RdWinPath 'Z:\tmp\a.ini' $prefix) -eq '/tmp/a.ini') 'host.ps1: Z:\ back to /'
        Write-Check ((Format-RdPathArg '/config:' 'Z:\tmp\a.ini') -eq '/config:Z:\tmp\a.ini') 'host.ps1: Wine arguments without quotes'
        Write-Check (Test-Path -LiteralPath (Join-RdPath $data 'config/common.ini')) 'host.ps1: Join-RdPath finds Config/common.ini as config/common.ini'
        Write-Check ($null -ne (Find-RdFile $install 'metaeditor64.exe')) 'host.ps1: metaeditor64.exe finds MetaEditor64.exe'
        Write-Check ((Expand-RdHome '~/x') -eq (Join-Path $HOME 'x')) 'host.ps1: ~ is the home folder'
    }

    #--- 5. install-junctions on a made-up terminal
    $term = Join-Path $Temp 'terminal'
    New-Item -ItemType Directory -Force -Path (Join-Path $term 'MQL5') | Out-Null
    $paths = Join-Path $Temp 'paths.test.ps1'
    Set-Content -LiteralPath $paths -Value @(
        '$MetaEditor4 = $null', '$MetaEditor5 = $null',
        ('$Terminals = @(@{ Name = ''test''; Platform = ''mt5''; DataPath = ''' + $term + ''' })'))
    $r = Invoke-BuildScript 'install-junctions.ps1' @('-PathsFile', $paths)
    $linked = (Test-Path -LiteralPath (Join-Path $term 'MQL5/Include/RiskDesk/Build.mqh')) -and
              (Test-Path -LiteralPath (Join-Path $term 'MQL5/Scripts/RiskDesk/BrokerProbe.mq5'))
    Write-Check ($r.Code -eq 0 -and $linked) 'install-junctions.ps1 links Include/RiskDesk and Scripts/RiskDesk'
    if (-not ($r.Code -eq 0 -and $linked)) { Show-Output $r.Out }
    $r = Invoke-BuildScript 'install-junctions.ps1' @('-PathsFile', $paths)
    Write-Check ($r.Code -eq 0 -and ([regex]::Matches($r.Out, 'already linked')).Count -eq 2) 'install-junctions.ps1 run again: both links kept'
    $r = Invoke-BuildScript 'install-junctions.ps1' @('-PathsFile', $paths, '-Uninstall')
    $gone = -not (Get-Item -LiteralPath (Join-Path $term 'MQL5/Include/RiskDesk') -Force -ErrorAction SilentlyContinue)
    $kept = Test-Path -LiteralPath (Join-Path $RepoRoot 'src/Include/RiskDesk/Build.mqh')
    Write-Check ($r.Code -eq 0 -and $gone -and $kept) 'install-junctions.ps1 -Uninstall removes the links and keeps the sources'

    #--- 6. build.ps1 without MetaEditor
    $r = Invoke-BuildScript 'build.ps1' @('-Target', 'mt5', '-PathsFile', $paths)
    Write-Check ($r.Code -eq 1 -and $r.Out -match 'MetaEditor not found' -and $r.Out -match '4 files not compiled') 'build.ps1 finds the 4 .mq5 files and stops: MetaEditor not found'
    if (-not ($r.Out -match 'MetaEditor not found')) { Show-Output $r.Out }

    #--- 7. package-release
    $bins = @('src/Experts/RiskDesk.ex4', 'src/Scripts/RiskDesk/BrokerProbe.ex4', 'src/Experts/RiskDesk.ex5', 'src/Scripts/RiskDesk/BrokerProbe.ex5')
    $missing = @($bins | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RepoRoot $_)) })
    if ($missing.Count -gt 0 -and $FakeBinaries) {
        foreach ($m in $missing) { Set-Content -LiteralPath (Join-Path $RepoRoot $m) -Value 'placeholder'; $fakes += (Join-Path $RepoRoot $m) }
        $missing = @()
    }
    if ($missing.Count -gt 0) {
        Write-Host "SKIP  package-release.ps1: $($missing.Count) compiled file(s) missing in src/ (build first, or -FakeBinaries)"
    } else {
        $dist = Join-Path $Temp 'dist'
        $r = Invoke-BuildScript 'package-release.ps1' @('-SkipBuild', '-OutDir', $dist)
        $zip = @(Get-ChildItem -LiteralPath $dist -Filter '*.zip' -File -ErrorAction SilentlyContinue) | Select-Object -First 1
        $names = @()
        if ($zip) {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [IO.Compression.ZipFile]::OpenRead($zip.FullName)
            try { $names = @($archive.Entries | ForEach-Object { $_.FullName }) } finally { $archive.Dispose() }
        }
        $expected = @('MQL4/Experts/RiskDesk.ex4', 'MQL5/Scripts/RiskDesk/BrokerProbe.ex5', 'LICENSE', 'docs/installation.md')
        $absent = @($expected | Where-Object { $names -notcontains $_ })
        $slashes = @($names | Where-Object { $_.Contains('\') })
        Write-Check ($r.Code -eq 0 -and $names.Count -gt 0 -and $absent.Count -eq 0 -and $slashes.Count -eq 0) "package-release.ps1: $($names.Count) zip entries, '/' only"
        if ($r.Code -ne 0) { Show-Output $r.Out }
        foreach ($a in $absent) { Write-Host "        missing entry $a" }
        foreach ($s in $slashes) { Write-Host "        backslash in entry $s" }
    }
} finally {
    foreach ($f in $fakes) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    # Links first, on their own: Remove-Item -Recurse of Windows PowerShell 5.1 can follow a
    # junction and delete what it points to (here: src/ of this repository).
    $linksLeft = 0
    foreach ($sub in @('terminal/MQL5/Include/RiskDesk', 'terminal/MQL5/Scripts/RiskDesk')) {
        $l = Join-Path $Temp $sub
        $item = Get-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            try { if ($RdOnWindows) { [IO.Directory]::Delete($l, $false) } else { [IO.File]::Delete($l) } } catch { }
            if (Get-Item -LiteralPath $l -Force -ErrorAction SilentlyContinue) { $linksLeft++ }
        }
    }
    if ($linksLeft -eq 0) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
    else { Write-Host "WARN  $linksLeft link(s) left in $Temp; remove that folder's links by hand before deleting it" }
}

Write-Host ''
if ($script:Failed -eq 0) {
    Write-Host 'PASS  ' -ForegroundColor Green -NoNewline
    Write-Host "$($script:Passed) checks passed ($psName on $os)"
    exit 0
}
Write-Host 'FAIL  ' -ForegroundColor Red -NoNewline
Write-Host "$($script:Failed) of $($script:Passed + $script:Failed) checks failed ($psName on $os)"
exit 1
