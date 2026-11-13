<#
.SYNOPSIS
    Removes the account login and the local data path from a BrokerProbe or
    GatewaySmoke report before it is shared or committed.

.DESCRIPTION
    BrokerProbe and GatewaySmoke name their reports
    <probe|smoke>_<company>_<MT4|MT5>_<login>_<yyyymmdd>.txt and write the
    login and the terminal's data folder (which contains the Windows user
    name) into the report. This script writes a copy in which:
      - the login is replaced by -Label, in the file name and in the text
        (only where it stands as a whole number, so prices and tickets are
        not touched);
      - the value of every 'data_path:' line is replaced by '<redacted>'.
    Everything else (server, company, symbol properties, results, tickets)
    is kept: it is what makes the report useful.

    The redacted copy is written next to the original (or into -OutDir).
    The original is deleted only with -RemoveOriginal.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/redact-report.ps1 `
        -Path 'C:\...\MQL5\Files\RiskDesk\probe_ExampleBroker_MT5_12345678_20261112.txt' -Label C1 `
        -OutDir broker-profiles
#>
param(
    [Parameter(Mandatory = $true)][string[]]$Path,
    # Short neutral id that replaces the login, e.g. A1..A6 for the
    # maintainer's accounts or C1, C2 ... for community reports.
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z][A-Za-z0-9]{0,7}$')][string]$Label,
    [string]$OutDir = '',
    [switch]$RemoveOriginal
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

foreach ($p in $Path) {
    $file = Get-Item -LiteralPath $p
    if ($file.Name -notmatch '^(probe|smoke)_(.+)_(MT4|MT5)_(\d+)_(\d{8})\.txt$') {
        throw "Not a report name with a numeric login: $($file.Name)"
    }
    $login = $Matches[4]
    $newName = "$($Matches[1])_$($Matches[2])_$($Matches[3])_$($Label)_$($Matches[5]).txt"
    $dir = if ($OutDir -ne '') { (Resolve-Path -LiteralPath $OutDir).Path } else { $file.DirectoryName }
    $target = Join-Path $dir $newName

    $text = [IO.File]::ReadAllText($file.FullName)
    $count = ([regex]::Matches($text, "(?<!\d)$login(?!\d)")).Count
    $text = [regex]::Replace($text, "(?<!\d)$login(?!\d)", $Label)
    $text = [regex]::Replace($text, '(?m)^(\s*data_path:\s+)\S.*?(\r?)$', '${1}<redacted>${2}')

    [IO.File]::WriteAllText($target, $text, (New-Object Text.UTF8Encoding $false))
    Write-Host "OK    $newName  (login replaced $count time(s), data_path redacted)"
    if ($RemoveOriginal -and ($file.FullName -ne $target)) { Remove-Item -LiteralPath $file.FullName }
}
