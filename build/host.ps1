<#
.SYNOPSIS
    Host helpers shared by the build scripts: Windows, or macOS / Linux with Wine.
    Dot-sourced by build.ps1, install-junctions.ps1, run-tests.ps1,
    run-script.ps1, run-uitest.ps1 and profile-guard.ps1.

.DESCRIPTION
    On Windows, MetaEditor and the terminals run natively and these helpers do
    what the scripts always did. On macOS and Linux (PowerShell 7) they run
    under Wine (ADR-032):

      - A Windows program is started as  <wine> <program.exe> <arguments>,
        with WINEPREFIX set to the prefix that holds the program (the folder
        above drive_c) and WINEDEBUG=-all unless WINEDEBUG is already set.
      - A path handed to a Windows program is converted: inside the prefix's
        drive_c it becomes C:\..., any other path Z:\... (Wine maps Z: to /).
      - A path written by a Windows program (origin.txt) is converted back.
      - A terminal is found by its process name (ps) and closed with Wine's
        taskkill, which sends WM_CLOSE like CloseMainWindow on Windows.

    Wine is looked up in this order: the $Wine4 / $Wine5 setting of
    build/paths.local.ps1 (or a terminal's own Wine entry), the Wine inside
    /Applications/MetaTrader 4.app or MetaTrader 5.app (macOS), then wine and
    wine64 on the PATH.

    Every helper keeps to the subset of PowerShell that Windows PowerShell 5.1
    and PowerShell 7 share.
#>

$RdOnWindows = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
$RdOnMac = (-not $RdOnWindows) -and (Test-Path -LiteralPath '/System/Library/CoreServices')

# Folder for temporary files ($env:TEMP exists on Windows only).
function Get-RdTempDir {
    return [IO.Path]::GetTempPath()
}

# A leading ~ in a path from paths.local.ps1 means the home folder.
function Expand-RdHome([string]$path) {
    if ($null -eq $path) { return $null }
    if ($path -eq '~') { return $HOME }
    if ($path.StartsWith('~/') -or $path.StartsWith('~\')) { return (Join-Path $HOME $path.Substring(2)) }
    return $path
}

# Full path with the host's separators (forward slashes are accepted on Windows too).
function Get-RdFullPath([string]$path) {
    return [IO.Path]::GetFullPath((Expand-RdHome $path))
}

# The file $name in $dir, or $null. On macOS / Linux the name is also matched
# without regard to case (Wine creates MetaEditor64.exe, the docs say metaeditor64.exe).
function Find-RdFile([string]$dir, [string]$name) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $null }
    $exact = Join-Path $dir $name
    if (Test-Path -LiteralPath $exact -PathType Leaf) { return $exact }
    if ($RdOnWindows) { return $null }
    $hit = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $name }) | Select-Object -First 1
    if ($hit) { return $hit.FullName }
    return $null
}

# $relative below $base (forward or back slashes). On macOS / Linux each part that
# exists is matched without regard to case, as Wine does for the terminal: a Wine
# install may have Config where Windows has config. Missing parts keep the given
# spelling. Windows: Join-Path.
function Join-RdPath([string]$base, [string]$relative) {
    if ($RdOnWindows) { return (Join-Path $base $relative) }
    $path = $base
    foreach ($part in @($relative -split '[\\/]' | Where-Object { $_ -ne '' })) {
        $next = Join-Path $path $part
        if (-not (Test-Path -LiteralPath $next) -and (Test-Path -LiteralPath $path -PathType Container)) {
            $hit = @(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $part }) | Select-Object -First 1
            if ($hit) { $next = Join-Path $path $hit.Name }
        }
        $path = $next
    }
    return $path
}

# A program path from paths.local.ps1 with ~ expanded and, on macOS / Linux, the
# file name's case taken from the disk. Returns the path unchanged when the file is missing.
function Resolve-RdFile([string]$path) {
    if (-not $path) { return $path }
    $p = Expand-RdHome $path
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    $hit = Find-RdFile (Split-Path -Parent $p) (Split-Path -Leaf $p)
    if ($hit) { return $hit }
    return $p
}

# Wine setting for a terminal of paths.local.ps1: its own Wine entry, else $wine4 / $wine5.
function Get-RdWineSetting($terminal, [string]$platform, [string]$wine4, [string]$wine5) {
    if ($terminal -is [Collections.IDictionary] -and $terminal.Contains('Wine') -and $terminal['Wine']) { return [string]$terminal['Wine'] }
    if ($platform -eq 'mt4') { return $wine4 }
    return $wine5
}

# Wine prefix that holds $path (the folder above drive_c), else $env:WINEPREFIX, else ~/.wine.
function Get-RdWinePrefix([string]$path) {
    if ($RdOnWindows) { return $null }
    if ($path) {
        $full = Get-RdFullPath $path
        $i = $full.IndexOf('/drive_c/', [StringComparison]::OrdinalIgnoreCase)
        if ($i -gt 0) { return $full.Substring(0, $i) }
        if ($full.EndsWith('/drive_c', [StringComparison]::OrdinalIgnoreCase)) { return $full.Substring(0, $full.Length - 8) }
    }
    if ($env:WINEPREFIX) { return (Get-RdFullPath $env:WINEPREFIX) }
    return (Join-Path $HOME '.wine')
}

# Path as a Windows program sees it. Windows: the full path. Wine: C:\... inside
# the prefix's drive_c, Z:\... elsewhere.
function ConvertTo-RdWinPath([string]$path, [string]$prefix) {
    $full = Get-RdFullPath $path
    if ($RdOnWindows) { return $full }
    $drive = (Join-Path $prefix 'drive_c').TrimEnd('/')
    if ($full -eq $drive) { return 'C:\' }
    if ($full.StartsWith($drive + '/')) { return 'C:\' + $full.Substring($drive.Length + 1).Replace('/', '\') }
    return 'Z:' + $full.Replace('/', '\')
}

# Host path of a path written by a Windows program (for example origin.txt).
function ConvertFrom-RdWinPath([string]$path, [string]$prefix) {
    if ($RdOnWindows) { return $path }
    if ($path -match '^([A-Za-z]):[\\/]?(.*)$') {
        $letter = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2].Replace('\', '/').TrimEnd('/')
        if ($letter -eq 'c') { $root = Join-Path $prefix 'drive_c' }
        elseif ($letter -eq 'z') { $root = '/' }
        else { $root = Join-Path $prefix "dosdevices/${letter}:" }
        if ($rest -eq '') { return $root }
        return (Join-Path $root $rest)
    }
    return $path.Replace('\', '/')
}

# "/switch:" + path in the form the program receives intact. Windows: the path in
# quotes, as MetaQuotes documents it. Wine: no quotes; Wine quotes the argument
# itself when it has a space (avoid spaces in the repository path, ADR-032).
function Format-RdPathArg([string]$switch, [string]$winPath) {
    if ($RdOnWindows) { return "$switch`"$winPath`"" }
    return "$switch$winPath"
}

# Wine program for one platform ('mt4' / 'mt5'), or $null. $configured: the
# setting from paths.local.ps1 (a path, or a command name such as 'wine').
function Find-RdWine([string]$platform, [string]$configured) {
    if ($RdOnWindows) { return $null }
    $candidates = @()
    if ($configured) {
        $candidates += (Expand-RdHome $configured)
    } else {
        if ($RdOnMac) {
            $app = '/Applications/MetaTrader 5.app'; $bins = @('wine64', 'wine')
            if ($platform -eq 'mt4') { $app = '/Applications/MetaTrader 4.app'; $bins = @('wine', 'wine64') }
            foreach ($b in $bins) { $candidates += "$app/Contents/SharedSupport/wine/bin/$b" }
        }
        $candidates += @('wine', 'wine64')
    }
    foreach ($c in $candidates) {
        if ($c.Contains('/')) {
            if (Test-Path -LiteralPath $c -PathType Leaf) { return $c }
            continue
        }
        $cmd = Get-Command -Name $c -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    return $null
}

# Text for a missing Wine.
function Get-RdWineHint([string]$platform) {
    $var = '$Wine5'
    if ($platform -eq 'mt4') { $var = '$Wine4' }
    return "Wine not found: install it (Linux: your distribution's wine package or MetaQuotes' mt5linux.sh; macOS: the MetaTrader app) or set $var in build/paths.local.ps1"
}

# Starts a Windows program and returns its Process. $exe is a host path.
# Windows: Start-Process as before. Wine: <wine> <exe> <arguments> with WINEPREFIX.
function Start-RdProgram([string]$exe, [string[]]$arguments, [string]$wine, [switch]$Hidden) {
    if ($RdOnWindows) {
        $p = @{ FilePath = $exe; PassThru = $true }
        if ($arguments -and $arguments.Count -gt 0) { $p.ArgumentList = $arguments }
        if ($Hidden) { $p.WindowStyle = 'Hidden' }
        return (Start-Process @p)
    }
    # the program by its Windows path: given a host path, Wine would run it through start.exe
    $prefix = Get-RdWinePrefix $exe
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $wine
    $psi.UseShellExecute = $false
    # Wine's output goes to a pipe of this script, not to its console: the wineserver that Wine
    # starts inherits the output and outlives the program, and would keep the console's pipe
    # open (a CI step or "| tail" would then wait for it).
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.ArgumentList.Add((ConvertTo-RdWinPath $exe $prefix))
    foreach ($a in @($arguments)) { if ($null -ne $a) { $psi.ArgumentList.Add([string]$a) } }
    $psi.Environment['WINEPREFIX'] = $prefix
    if (-not $env:WINEDEBUG) { $psi.Environment['WINEDEBUG'] = '-all' }
    $p = [Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEndAsync()   # drained, so Wine never blocks on a full pipe
    $null = $p.StandardError.ReadToEndAsync()
    return $p
}

# Runs a Wine built-in program (taskkill, ...) in a prefix and waits for it.
function Invoke-RdWineTool([string]$wine, [string]$prefix, [string[]]$arguments, [int]$timeoutMs = 30000) {
    if ($RdOnWindows -or -not $wine) { return }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $wine
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($a in $arguments) { $psi.ArgumentList.Add($a) }
    $psi.Environment['WINEPREFIX'] = $prefix
    if (-not $env:WINEDEBUG) { $psi.Environment['WINEDEBUG'] = '-all' }
    $p = [Diagnostics.Process]::Start($psi)
    $null = $p.StandardOutput.ReadToEndAsync()
    $null = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutMs)) { try { $p.Kill() } catch { } }
}

# Running processes of a terminal program. Windows: by full path. Wine: by
# program name in the command line (terminal.exe, terminal64.exe), in any
# prefix - a terminal of the same kind in another prefix also counts.
function Get-RdProgramProcesses([string]$exe) {
    if ($RdOnWindows) {
        return @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            try { $_.Path -and ($_.Path -ieq $exe) } catch { $false }
        })
    }
    $name = [regex]::Escape([IO.Path]::GetFileName($exe))
    $pattern = '(?i)(^|[\\/\s"])' + $name + '("|\s|$)'
    $found = @()
    foreach ($line in @(& /bin/ps -A -o pid= -o args= 2>$null)) {
        $text = ([string]$line).Trim()
        if ($text -notmatch '^(\d+)\s+(.*)$') { continue }
        $id = [int]$Matches[1]; $cmd = $Matches[2]
        if ($id -eq $PID -or $cmd -match '(?i)taskkill') { continue }
        if ($cmd -match $pattern) { $found += [pscustomobject]@{ Id = $id; CommandLine = $cmd } }
    }
    return $found
}

# True while the started terminal runs. Under Wine the process that was started
# may be a launcher, so the program name is checked as well.
function Test-RdProgramRunning($proc, [string]$exe) {
    if ($proc -and -not $proc.HasExited) { return $true }
    if ($RdOnWindows) { return $false }
    return (@(Get-RdProgramProcesses $exe).Count -gt 0)
}

# Waits up to $timeoutMs for the terminal to end; $true when it has.
function Wait-RdProgramExit($proc, [string]$exe, [int]$timeoutMs) {
    if ($RdOnWindows) { return $proc.WaitForExit($timeoutMs) }
    $deadline = (Get-Date).AddMilliseconds($timeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-RdProgramRunning $proc $exe)) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (-not (Test-RdProgramRunning $proc $exe))
}

# Asks the terminal to close (WM_CLOSE), as the user closing its window would.
function Close-RdProgram($proc, [string]$exe, [string]$wine) {
    if ($RdOnWindows) { $null = $proc.CloseMainWindow(); return }
    Invoke-RdWineTool $wine (Get-RdWinePrefix $exe) @('taskkill', '/IM', [IO.Path]::GetFileName($exe))
}

# Ends the terminal without asking.
function Stop-RdProgram($proc, [string]$exe, [string]$wine) {
    if ($RdOnWindows) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue; return }
    Invoke-RdWineTool $wine (Get-RdWinePrefix $exe) @('taskkill', '/F', '/IM', [IO.Path]::GetFileName($exe))
    # also Wine's launcher, which runs under the program's name before the program itself starts
    foreach ($p in @(Get-RdProgramProcesses $exe)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
    $null = Wait-RdProgramExit $proc $exe 10000
}

# The terminal program of a data folder, or $null. The data folder's origin.txt
# names the install folder (Windows: AppData\Roaming\MetaQuotes\Terminal\<id>).
# Without it the data folder is the install folder: /portable on Windows, and
# MetaQuotes' macOS app and Linux installer, which keep the data in
# drive_c/Program Files/MetaTrader 5.
function Find-RdTerminalExe([string]$data, [string]$exeName) {
    $origin = Join-RdPath $data 'origin.txt'
    $install = $data
    if (Test-Path -LiteralPath $origin) {
        $written = ([string](Get-Content -LiteralPath $origin -TotalCount 1)).Trim()
        $install = ConvertFrom-RdWinPath $written (Get-RdWinePrefix $data)
    }
    return (Find-RdFile $install $exeName)
}
