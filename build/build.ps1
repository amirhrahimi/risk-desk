<#
.SYNOPSIS
    Compiles every RiskDesk entry file and fails on any error or warning.

.DESCRIPTION
    Compiles each .mq4 under src/Experts and src/Scripts with the MT4 MetaEditor
    and each .mq5 with the MT5 MetaEditor (paths from build/paths.local.ps1),
    using MetaEditor's /compile and /log switches. On macOS and Linux
    (PowerShell 7) MetaEditor runs under Wine (build/host.ps1, ADR-032). MetaEditor's exit code is
    meaningless, so the result is read from the .log file it writes next to the
    source (UTF-16 or UTF-8; decoded here). Prints one line per file and a summary.
    Exit code 0 only when every file compiled with 0 errors and 0 warnings.

    The EA (src/Experts/RiskDesk.mq4/.mq5) is then copied into the root of
    MQLx\Experts of every terminal of that platform in $Terminals, so the
    Navigator shows it without a sub-folder. Scripts and includes reach the
    terminals through the junctions (macOS / Linux: symbolic links) of
    install-junctions.ps1.

    -Debug builds with RD_TEST_HOOKS: MetaEditor has no command-line define, so
    the script un-comments '//#define RD_TEST_HOOKS' in
    src/Include/RiskDesk/Build.mqh for the duration of the build and restores
    the file afterwards. A release build refuses to run while the define is active.

    Before compiling, check-version.ps1 verifies that RD_VERSION and
    RD_VERSION_PROP in Build.mqh name the same version.

.PARAMETER Target
    mt4, mt5 or all (default).

.PARAMETER Debug
    Debug build with test hooks (08-testing section 2). Release by default.

.PARAMETER TimeoutSec
    Maximum time for one compile. Default 180.

.PARAMETER PathsFile
    Alternative paths file (default build/paths.local.ps1).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/build.ps1
    powershell -ExecutionPolicy Bypass -File build/build.ps1 -Target mt5
    powershell -ExecutionPolicy Bypass -File build/build.ps1 -Debug
    pwsh build/build.ps1                      (macOS / Linux)
#>
param(
    [ValidateSet('mt4', 'mt5', 'all')]
    [string]$Target = 'all',
    [switch]$Debug,
    [int]$TimeoutSec = 180,
    [string]$PathsFile = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'host.ps1')

$RepoRoot  = Split-Path -Parent $PSScriptRoot
if (-not $PathsFile) { $PathsFile = Join-Path $PSScriptRoot 'paths.local.ps1' }
$BuildMqh  = Get-RdFullPath (Join-Path $RepoRoot 'src/Include/RiskDesk/Build.mqh')
$ExpertsDir = Get-RdFullPath (Join-Path $RepoRoot 'src/Experts')
$SrcDirs   = @($ExpertsDir, (Get-RdFullPath (Join-Path $RepoRoot 'src/Scripts')))

function Write-Status([string]$status, [string]$text) {
    $color = 'Gray'
    if ($status -eq 'PASS') { $color = 'Green' }
    elseif ($status -eq 'FAIL') { $color = 'Red' }
    elseif ($status -eq 'WARN') { $color = 'Yellow' }
    Write-Host ('{0,-5} ' -f $status) -ForegroundColor $color -NoNewline
    Write-Host $text
}

function Get-RelativePath([string]$path) {
    if ($path.StartsWith($RepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        return $path.Substring($RepoRoot.Length).TrimStart('\', '/')
    }
    return $path
}

# MetaEditor writes UTF-16 LE logs (sometimes UTF-8 or ANSI).
function Read-CompileLog([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    $zeros = 0
    $limit = [Math]::Min($bytes.Length, 400)
    for ($i = 1; $i -lt $limit; $i += 2) { if ($bytes[$i] -eq 0) { $zeros++ } }
    if ($limit -gt 0 -and $zeros -gt ($limit / 4)) {
        return [Text.Encoding]::Unicode.GetString($bytes)
    }
    return [Text.Encoding]::Default.GetString($bytes)
}

function Invoke-Compile([string]$platform, [string]$editor, [string]$wine, [string]$file) {
    $log = [IO.Path]::ChangeExtension($file, '.log')
    $outExt = '.ex5'
    if ($platform -eq 'mt4') { $outExt = '.ex4' }
    $out = [IO.Path]::ChangeExtension($file, $outExt)
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $before = [datetime]::MinValue
    if (Test-Path -LiteralPath $out) { $before = (Get-Item -LiteralPath $out).LastWriteTimeUtc }

    $result = [pscustomobject]@{
        Platform = $platform; File = (Get-RelativePath $file); Errors = -1; Warnings = -1
        Ok = $false; Note = ''; Issues = @()
    }

    # Windows: the path itself. Wine: Z:\<path> (C:\... inside the prefix); the log
    # then names the files in that form, which is cut from the issue lines below.
    $prefix = Get-RdWinePrefix $editor
    $winFile = ConvertTo-RdWinPath $file $prefix
    $winRoot = ConvertTo-RdWinPath $RepoRoot $prefix
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $proc = Start-RdProgram $editor @((Format-RdPathArg '/compile:' $winFile), '/log') $wine -Hidden
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        $result.Note = "MetaEditor did not finish within $TimeoutSec s"
        return $result
    }
    # Wine: in case the process started was only a launcher, wait until the log is complete
    if (-not $RdOnWindows) {
        $lastSize = -1
        while ($watch.Elapsed.TotalSeconds -lt $TimeoutSec) {
            if (Test-Path -LiteralPath $log) {
                $size = (Get-Item -LiteralPath $log).Length
                if ($size -gt 0 -and $size -eq $lastSize) { break }
                $lastSize = $size
            } elseif (@(Get-RdProgramProcesses $editor).Count -eq 0) {
                break
            }
            Start-Sleep -Milliseconds 500
        }
    }
    $watch.Stop()

    if (-not (Test-Path -LiteralPath $log)) {
        $result.Note = 'MetaEditor wrote no log file'
        return $result
    }
    $text = Read-CompileLog $log
    $found = [regex]::Matches($text, '(\d+)\s+errors?(?:\(s\))?\s*,\s*(\d+)\s+warnings?(?:\(s\))?', 'IgnoreCase')
    if ($found.Count -eq 0) {
        $result.Note = 'no "N errors, M warnings" line in the log'
        return $result
    }
    $last = $found[$found.Count - 1]
    $result.Errors = [int]$last.Groups[1].Value
    $result.Warnings = [int]$last.Groups[2].Value
    $rootPattern = '(?i)(' + [regex]::Escape($RepoRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar) + '|' +
                   [regex]::Escape($winRoot.TrimEnd('\') + '\') + ')'
    $result.Issues = @($text -split "`r?`n" | Where-Object { $_ -match ':\s*(error|warning)\s+\d+\s*:' } |
        ForEach-Object { ($_ -replace $rootPattern, '').Trim() })

    $after = [datetime]::MinValue
    if (Test-Path -LiteralPath $out) { $after = (Get-Item -LiteralPath $out).LastWriteTimeUtc }
    if ($result.Errors -eq 0 -and $after -le $before) {
        $result.Note = "no new $outExt was written"
        return $result
    }
    $result.Ok = ($result.Errors -eq 0 -and $result.Warnings -eq 0)
    $result.Note = '{0:N1} s' -f $watch.Elapsed.TotalSeconds
    return $result
}

# The EA sits in the root of MQLx\Experts (no RiskDesk sub-folder in the Navigator).
# A folder junction cannot do that and a file link cannot cross drives, so the
# compiled .ex4/.ex5 is copied there. Returns the number of failed copies.
function Install-Expert([string]$platform, [string]$source) {
    $outExt = '.ex5'; $mql = 'MQL5'
    if ($platform -eq 'mt4') { $outExt = '.ex4'; $mql = 'MQL4' }
    $built = [IO.Path]::ChangeExtension($source, $outExt)
    $name = [IO.Path]::GetFileName($built)
    $failed = 0
    foreach ($t in @($Terminals)) {
        if (([string]$t.Platform).ToLowerInvariant() -ne $platform) { continue }
        $dir = Join-RdPath (Expand-RdHome ([string]$t.DataPath)) "$mql/Experts"
        if (-not (Test-Path -LiteralPath $dir)) {
            Write-Status 'FAIL' "$platform  install $name - $dir not found"
            $failed++
            continue
        }
        try {
            Copy-Item -LiteralPath $built -Destination (Join-Path $dir $name) -Force
            Write-Status 'INFO' "$platform  installed $mql/Experts/$name  ($($t.Name))"
        } catch {
            Write-Status 'FAIL' "$platform  install $name into $dir - $($_.Exception.Message)"
            $failed++
        }
    }
    return $failed
}

#--- configuration -------------------------------------------------------------
if (-not (Test-Path -LiteralPath $PathsFile)) {
    Write-Status 'FAIL' 'build/paths.local.ps1 not found. Copy build/paths.example.ps1 to build/paths.local.ps1 and fill in the MetaEditor paths.'
    exit 1
}
$MetaEditor4 = $null
$MetaEditor5 = $null
$Wine4 = $null
$Wine5 = $null
$Terminals = @()
. $PathsFile
$MetaEditor4 = Resolve-RdFile $MetaEditor4
$MetaEditor5 = Resolve-RdFile $MetaEditor5

if (-not (Test-Path -LiteralPath $BuildMqh)) {
    Write-Status 'FAIL' "missing $(Get-RelativePath $BuildMqh)"
    exit 1
}
$originalBytes = [IO.File]::ReadAllBytes($BuildMqh)
$originalText = [Text.Encoding]::ASCII.GetString($originalBytes)
if ($originalText -match '(?m)^[ \t]*#define[ \t]+RD_TEST_HOOKS') {
    Write-Status 'FAIL' 'Build.mqh has RD_TEST_HOOKS active. Comment it out again (//#define RD_TEST_HOOKS); use -Debug for debug builds.'
    exit 1
}
& (Join-Path $PSScriptRoot 'check-version.ps1') -Path $BuildMqh
if ($LASTEXITCODE -ne 0) { exit 1 }

$platforms = @($Target)
if ($Target -eq 'all') { $platforms = @('mt4', 'mt5') }
$mode = 'release'
if ($Debug) { $mode = 'DEBUG (RD_TEST_HOOKS)' }

Write-Host "RiskDesk build - target $Target, $mode"
$results = New-Object System.Collections.Generic.List[object]
$failures = 0

try {
    if ($Debug) {
        $patched = [regex]::Replace($originalText, '(?m)^//[ \t]*#define[ \t]+RD_TEST_HOOKS', '#define RD_TEST_HOOKS')
        if ($patched -eq $originalText) {
            Write-Status 'FAIL' 'Build.mqh has no "//#define RD_TEST_HOOKS" line to enable.'
            exit 1
        }
        [IO.File]::WriteAllBytes($BuildMqh, [Text.Encoding]::ASCII.GetBytes($patched))
    }

    foreach ($platform in $platforms) {
        $editor = $MetaEditor5
        $ext = '.mq5'
        $var = '$MetaEditor5'
        $wineSetting = $Wine5
        if ($platform -eq 'mt4') { $editor = $MetaEditor4; $ext = '.mq4'; $var = '$MetaEditor4'; $wineSetting = $Wine4 }

        $files = @(Get-ChildItem -Path $SrcDirs -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -eq $ext } | Sort-Object FullName)
        if ($files.Count -eq 0) {
            Write-Status 'FAIL' "$platform  no $ext files under src/Experts or src/Scripts"
            $failures++
            continue
        }
        if (-not $editor -or -not (Test-Path -LiteralPath $editor)) {
            Write-Status 'FAIL' "$platform  MetaEditor not found: set $var in build/paths.local.ps1 ($($files.Count) files not compiled)"
            $failures++
            continue
        }
        $wine = $null
        if (-not $RdOnWindows) {
            $wine = Find-RdWine $platform $wineSetting
            if (-not $wine) {
                Write-Status 'FAIL' "$platform  $(Get-RdWineHint $platform) ($($files.Count) files not compiled)"
                $failures++
                continue
            }
            Write-Status 'INFO' "$platform  MetaEditor under Wine: $wine (prefix $(Get-RdWinePrefix $editor))"
            if ($RepoRoot.Contains(' ')) {
                Write-Status 'WARN' "$platform  the repository path contains a space; MetaEditor under Wine may not find the files. Clone it to a path without spaces."
            }
        }

        foreach ($f in $files) {
            $r = Invoke-Compile $platform $editor $wine $f.FullName
            $results.Add($r)
            if ($r.Errors -ge 0) {
                $summary = '{0} errors, {1} warnings' -f $r.Errors, $r.Warnings
            } else {
                $summary = 'no result'
            }
            if ($r.Ok) {
                Write-Status 'PASS' ('{0}  {1,-48} {2}  ({3})' -f $platform, $r.File, $summary, $r.Note)
                if ($f.DirectoryName -ieq $ExpertsDir) { $failures += Install-Expert $platform $f.FullName }
            } else {
                $failures++
                $note = ''
                if ($r.Note) { $note = "  - $($r.Note)" }
                Write-Status 'FAIL' ('{0}  {1,-48} {2}{3}' -f $platform, $r.File, $summary, $note)
                $shown = 0
                foreach ($issue in $r.Issues) {
                    if ($shown -ge 40) { Write-Host '        ...'; break }
                    Write-Host "        $issue"
                    $shown++
                }
            }
        }
    }
}
finally {
    if ($Debug) { [IO.File]::WriteAllBytes($BuildMqh, $originalBytes) }
}

$passed = @($results | Where-Object { $_.Ok }).Count
Write-Host ''
if ($failures -eq 0) {
    Write-Status 'PASS' ("{0} of {0} files: 0 errors, 0 warnings ({1})" -f $passed, $mode)
    exit 0
}
Write-Status 'FAIL' ("{0} file(s) or target(s) failed, {1} passed ({2})" -f $failures, $passed, $mode)
exit 1
