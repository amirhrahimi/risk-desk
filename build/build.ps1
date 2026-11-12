<#
.SYNOPSIS
    Compiles every RiskDesk entry file and fails on any error or warning.

.DESCRIPTION
    Compiles each .mq4 under src/Experts and src/Scripts with the MT4 MetaEditor
    and each .mq5 with the MT5 MetaEditor (paths from build/paths.local.ps1),
    using MetaEditor's /compile and /log switches. MetaEditor's exit code is
    meaningless, so the result is read from the .log file it writes next to the
    source (UTF-16 or UTF-8; decoded here). Prints one line per file and a summary.
    Exit code 0 only when every file compiled with 0 errors and 0 warnings.

    -Debug builds with RD_TEST_HOOKS: MetaEditor has no command-line define, so
    the script un-comments '//#define RD_TEST_HOOKS' in
    src/Include/RiskDesk/Build.mqh for the duration of the build and restores
    the file afterwards. A release build refuses to run while the define is active.

.PARAMETER Target
    mt4, mt5 or all (default).

.PARAMETER Debug
    Debug build with test hooks (08-testing section 2). Release by default.

.PARAMETER TimeoutSec
    Maximum time for one compile. Default 180.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/build.ps1
    powershell -ExecutionPolicy Bypass -File build/build.ps1 -Target mt5
    powershell -ExecutionPolicy Bypass -File build/build.ps1 -Debug
#>
param(
    [ValidateSet('mt4', 'mt5', 'all')]
    [string]$Target = 'all',
    [switch]$Debug,
    [int]$TimeoutSec = 180
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$RepoRoot  = Split-Path -Parent $PSScriptRoot
$PathsFile = Join-Path $PSScriptRoot 'paths.local.ps1'
$BuildMqh  = Join-Path $RepoRoot 'src\Include\RiskDesk\Build.mqh'
$SrcDirs   = @((Join-Path $RepoRoot 'src\Experts'), (Join-Path $RepoRoot 'src\Scripts'))

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
        return $path.Substring($RepoRoot.Length).TrimStart('\')
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

function Invoke-Compile([string]$platform, [string]$editor, [string]$file) {
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

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath $editor -ArgumentList @("/compile:`"$file`"", '/log') -PassThru -WindowStyle Hidden
    if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
        try { $proc.Kill() } catch { }
        $result.Note = "MetaEditor did not finish within $TimeoutSec s"
        return $result
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
    $result.Issues = @($text -split "`r?`n" | Where-Object { $_ -match ':\s*(error|warning)\s+\d+\s*:' } |
        ForEach-Object { $_.Replace($RepoRoot + '\', '').Trim() })

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

#--- configuration -------------------------------------------------------------
if (-not (Test-Path -LiteralPath $PathsFile)) {
    Write-Status 'FAIL' 'build/paths.local.ps1 not found. Copy build/paths.example.ps1 to build/paths.local.ps1 and fill in the MetaEditor paths.'
    exit 1
}
$MetaEditor4 = $null
$MetaEditor5 = $null
$Terminals = @()
. $PathsFile

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
        if ($platform -eq 'mt4') { $editor = $MetaEditor4; $ext = '.mq4'; $var = '$MetaEditor4' }

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

        foreach ($f in $files) {
            $r = Invoke-Compile $platform $editor $f.FullName
            $results.Add($r)
            if ($r.Errors -ge 0) {
                $summary = '{0} errors, {1} warnings' -f $r.Errors, $r.Warnings
            } else {
                $summary = 'no result'
            }
            if ($r.Ok) {
                Write-Status 'PASS' ('{0}  {1,-48} {2}  ({3})' -f $platform, $r.File, $summary, $r.Note)
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
