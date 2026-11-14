<#
.SYNOPSIS
    Builds the GitHub wiki from the user documentation and, with -Publish,
    replaces the wiki's pages with it (ADR-035).

.DESCRIPTION
    The wiki is a copy of README.md, docs/*.md (not docs/design/) and
    ROADMAP.md, for reading on GitHub with a sidebar. The repository stays the
    source: never edit the wiki, every page there is replaced on the next run.

    Each source file becomes one page ($Pages below; README.md is Home). The
    script
      - drops the file's leading '# ' heading (the wiki shows the page name as
        its title); Home keeps it;
      - rewrites relative links: a link to a file that is a page goes to that
        page's wiki URL (anchor kept), a link to any other file or folder of the
        repository goes to it on GitHub (blob/tree on -Branch); links inside
        code blocks are left alone;
      - adds a last line naming the source file;
      - writes _Sidebar.md and _Footer.md.

    It stops (exit 1) when a link points at a file that does not exist or when
    a docs/*.md file has no page in $Pages.

    Without -Publish the pages are only written to -OutDir. With -Publish the
    wiki repository is cloned, all its pages are replaced by the new ones
    (pages without a source are removed), and the change is committed and
    pushed; nothing is pushed when nothing changed. Run by
    .github/workflows/wiki.yml on every push to main that changes a source.

    GitHub creates the wiki repository only when its first page is saved in the
    browser. Once per repository: open https://github.com/<owner>/<repo>/wiki,
    click "Create the first page" and save it; -Publish then replaces it.

.PARAMETER Repo
    owner/name on GitHub. Default: $env:GITHUB_REPOSITORY (CI), else the URL of
    the 'origin' remote.

.PARAMETER Branch
    Branch that links to repository files point at. Default: main.

.PARAMETER OutDir
    Folder for the generated pages. It must be missing or empty. Default: a
    folder in the temporary directory, emptied on every run.

.PARAMETER Publish
    Clone the wiki, replace its pages, commit and push. Uses $env:GITHUB_TOKEN
    when it is set (CI), else git's own credentials. Refuses while a source file
    has uncommitted changes (the wiki would show text that is not in the
    repository), unless -AllowUncommitted is given.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build/publish-wiki.ps1
    powershell -ExecutionPolicy Bypass -File build/publish-wiki.ps1 -Publish
    pwsh build/publish-wiki.ps1 -Publish      (macOS / Linux)
#>
param(
    [string]$Repo = '',
    [string]$Branch = 'main',
    [string]$OutDir = '',
    [switch]$Publish,
    [switch]$AllowUncommitted
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'host.ps1')

$RepoRoot = Get-RdFullPath (Split-Path -Parent $PSScriptRoot)

# One page per source file, in sidebar order. Group '' = not listed in a sidebar group.
$Pages = @(
    @{ Source = 'README.md';                    Name = 'Home';                 Label = 'Home';                    Group = '' }
    @{ Source = 'docs/installation.md';         Name = 'Installation';         Label = 'Installation';            Group = 'Using Risk Desk' }
    @{ Source = 'docs/user-guide.md';           Name = 'User-Guide';           Label = 'User guide';              Group = 'Using Risk Desk' }
    @{ Source = 'docs/configuration.md';        Name = 'Configuration';        Label = 'Configuration';           Group = 'Using Risk Desk' }
    @{ Source = 'docs/broker-compatibility.md'; Name = 'Broker-Compatibility'; Label = 'Broker compatibility';    Group = 'Using Risk Desk' }
    @{ Source = 'docs/backtesting.md';          Name = 'Backtesting';          Label = 'Backtesting';             Group = 'Using Risk Desk' }
    @{ Source = 'docs/troubleshooting.md';      Name = 'Troubleshooting';      Label = 'Troubleshooting and FAQ'; Group = 'Using Risk Desk' }
    @{ Source = 'docs/glossary.md';             Name = 'Glossary';             Label = 'Glossary';                Group = 'Using Risk Desk' }
    @{ Source = 'docs/architecture.md';         Name = 'Architecture';         Label = 'Architecture';            Group = 'Project' }
    @{ Source = 'ROADMAP.md';                   Name = 'Roadmap';              Label = 'Roadmap';                 Group = 'Project' }
)

# Further sidebar links of the 'Project' group, written as in a file at the repository root.
$ProjectLinks = @(
    '[Changelog](CHANGELOG.md)'
    '[Releases](https://github.com/{repo}/releases)'
    '[Contributing](CONTRIBUTING.md)'
    '[Support](SUPPORT.md)'
    '[Security policy](SECURITY.md)'
    '[Credits](NOTICE.md)'
    '[Licence (MIT)](LICENSE)'
)

function Write-Result([bool]$ok, [string]$text) {
    if ($ok) { Write-Host 'PASS  ' -ForegroundColor Green -NoNewline }
    else { Write-Host 'FAIL  ' -ForegroundColor Red -NoNewline }
    Write-Host $text
}

function Stop-Wiki([string]$text) {
    Write-Result $false $text
    exit 1
}

# Runs git; returns exit code and output. Native stderr must not stop the script
# (Windows PowerShell 5.1 turns it into errors under ErrorActionPreference Stop).
function Invoke-Git([string[]]$arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& git @arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $old }
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($out -join "`n") }
}

function Write-Utf8([string]$path, [string]$text) {
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

#--- repository on GitHub
if ($Repo -eq '' -and $env:GITHUB_REPOSITORY) { $Repo = $env:GITHUB_REPOSITORY }
if ($Repo -eq '') {
    $r = Invoke-Git @('-C', $RepoRoot, 'remote', 'get-url', 'origin')
    if ($r.Code -eq 0 -and $r.Out -match 'github\.com[:/]([^/\s]+/[^/\s]+?)(\.git)?/?$') { $Repo = $Matches[1] }
}
if ($Repo -notmatch '^[^/\s]+/[^/\s]+$') { Stop-Wiki 'GitHub repository unknown: pass -Repo owner/name.' }
$RepoUrl = "https://github.com/$Repo"
$WikiUrl = "$RepoUrl/wiki"

#--- every docs/*.md has a page
$sources = @($Pages | ForEach-Object { $_.Source })
foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'docs') -Filter '*.md' -File)) {
    if ($sources -notcontains "docs/$($f.Name)") { Stop-Wiki "docs/$($f.Name) has no wiki page: add it to `$Pages in build/publish-wiki.ps1." }
}

#--- link rewriting
$script:LinkErrors = @()

# 'docs' + '../README.md' -> 'README.md'; $null when the path leaves the repository.
function Resolve-RepoPath([string]$dir, [string]$path) {
    $parts = New-Object Collections.Generic.List[string]
    foreach ($p in (($dir + '/' + $path) -split '/')) {
        if ($p -eq '' -or $p -eq '.') { continue }
        if ($p -eq '..') { if ($parts.Count -eq 0) { return $null }; $parts.RemoveAt($parts.Count - 1); continue }
        $parts.Add([Uri]::UnescapeDataString($p))
    }
    return ($parts -join '/')
}

function Convert-Link([string]$target, [string]$dir, [string]$source) {
    if ($target -match '^(#|[A-Za-z][A-Za-z0-9+.-]*:)') { return $target }   # anchor in the page, https:, mailto:
    $path = $target; $anchor = ''
    $i = $target.IndexOf('#')
    if ($i -ge 0) { $path = $target.Substring(0, $i); $anchor = $target.Substring($i) }
    $rel = Resolve-RepoPath $dir $path
    if ($null -eq $rel) { $script:LinkErrors += "${source}: $target leaves the repository"; return $target }
    $full = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $full)) { $script:LinkErrors += "${source}: $target not found"; return $target }
    foreach ($p in $Pages) { if ($p.Source -eq $rel) { return "$WikiUrl/$($p.Name)$anchor" } }
    if ($rel -eq '') { return "$RepoUrl$anchor" }
    $kind = 'blob'
    if (Test-Path -LiteralPath $full -PathType Container) { $kind = 'tree' }
    return "$RepoUrl/$kind/$Branch/$rel$anchor"
}

# Rewrites the links of a Markdown text written in folder $dir (relative to the repository).
function Convert-Markdown([string]$text, [string]$dir, [string]$source) {
    $lines = $text.Replace("`r`n", "`n") -split "`n"
    $fence = ''
    for ($n = 0; $n -lt $lines.Count; $n++) {
        $line = $lines[$n]
        if ($line -match '^ {0,3}(```+|~~~+)') {
            $mark = $Matches[1].Substring(0, 3)
            if ($fence -eq '') { $fence = $mark } elseif ($fence -eq $mark) { $fence = '' }
            continue
        }
        if ($fence -ne '') { continue }
        $lines[$n] = [regex]::Replace($line, '(?<=\]\()[^)\s]+(?=(\s+"[^"]*")?\))', {
            param($m) Convert-Link $m.Value $dir $source
        })
    }
    return ($lines -join "`n")
}

#--- pages
if ($OutDir -eq '') {
    $OutDir = Join-Path (Get-RdTempDir) 'RiskDesk-wiki'
    if (Test-Path -LiteralPath $OutDir) { Remove-Item -LiteralPath $OutDir -Recurse -Force }
} elseif ((Test-Path -LiteralPath $OutDir) -and @(Get-ChildItem -LiteralPath $OutDir -Force).Count -gt 0) {
    Stop-Wiki "-OutDir $OutDir is not empty."
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

foreach ($p in $Pages) {
    $text = [IO.File]::ReadAllText((Join-Path $RepoRoot $p.Source), [Text.Encoding]::UTF8)
    $text = $text.Replace("`r`n", "`n")
    if ($p.Name -ne 'Home') { $text = $text -replace '^\s*# [^\n]*\n+', '' }
    $dir = ''
    $slash = $p.Source.LastIndexOf('/')
    if ($slash -ge 0) { $dir = $p.Source.Substring(0, $slash) }
    $text = Convert-Markdown $text $dir $p.Source
    $text = $text.TrimEnd() + "`n`n---`n`n<sub>Source: [$($p.Source)]($RepoUrl/blob/$Branch/$($p.Source)). Edit that file, not this page.</sub>`n"
    Write-Utf8 (Join-Path $OutDir "$($p.Name).md") $text
}

$sidebar = New-Object Text.StringBuilder
[void]$sidebar.Append("**[Risk Desk](README.md)**`n")
foreach ($group in @('Using Risk Desk', 'Project')) {
    [void]$sidebar.Append("`n**$group**`n`n")
    foreach ($p in @($Pages | Where-Object { $_.Group -eq $group })) { [void]$sidebar.Append("- [$($p.Label)]($($p.Source))`n") }
    if ($group -eq 'Project') { foreach ($l in $ProjectLinks) { [void]$sidebar.Append("- $($l.Replace('{repo}', $Repo))`n") } }
}
Write-Utf8 (Join-Path $OutDir '_Sidebar.md') (Convert-Markdown $sidebar.ToString() '' '_Sidebar')

$footer = "This wiki is generated from the documentation in the [repository]($RepoUrl) by ``build/publish-wiki.ps1``. " +
    "Changes made here are overwritten: to correct a page, edit its source file and open a pull request ([CONTRIBUTING.md](CONTRIBUTING.md)).`n"
Write-Utf8 (Join-Path $OutDir '_Footer.md') (Convert-Markdown $footer '' '_Footer')

if ($script:LinkErrors.Count -gt 0) {
    foreach ($e in $script:LinkErrors) { Write-Host "        $e" }
    Stop-Wiki "$($script:LinkErrors.Count) link(s) point at nothing."
}
$count = @(Get-ChildItem -LiteralPath $OutDir -Filter '*.md' -File).Count
Write-Result $true "$count wiki files for $Repo in $OutDir"
if (-not $Publish) { exit 0 }

#--- publish
$dirty = Invoke-Git (@('-C', $RepoRoot, 'status', '--porcelain', '--') + $sources)
if ($dirty.Code -eq 0 -and $dirty.Out.Trim() -ne '' -and -not $AllowUncommitted) {
    Write-Host $dirty.Out
    Stop-Wiki 'Source files have uncommitted changes: commit them first, or pass -AllowUncommitted.'
}
$commit = Invoke-Git @('-C', $RepoRoot, 'rev-parse', '--short', 'HEAD')

# CI: the token goes in an HTTP header through git's environment, never on a command line or in a URL.
$tokenVars = @('GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0')
if ($env:GITHUB_TOKEN) {
    $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$($env:GITHUB_TOKEN)"))
    $env:GIT_CONFIG_COUNT = '1'
    $env:GIT_CONFIG_KEY_0 = 'http.https://github.com/.extraheader'
    $env:GIT_CONFIG_VALUE_0 = "AUTHORIZATION: basic $basic"
}
$clone = Join-Path (Get-RdTempDir) "RiskDesk-wiki-clone-$PID"
try {
    $r = Invoke-Git @('clone', '--quiet', '--depth', '1', "$RepoUrl.wiki.git", $clone)
    if ($r.Code -ne 0) {
        Write-Host $r.Out
        if ($r.Out -match 'not found') {
            Stop-Wiki "The wiki of $Repo has no pages yet. Open $WikiUrl, click 'Create the first page', save it, and run again."
        }
        Stop-Wiki "git clone of $RepoUrl.wiki.git failed."
    }
    Get-ChildItem -LiteralPath $clone -Force | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
    Copy-Item -Path (Join-Path $OutDir '*') -Destination $clone
    $r = Invoke-Git @('-C', $clone, 'add', '--all')
    if ($r.Code -ne 0) { Write-Host $r.Out; Stop-Wiki 'git add failed.' }
    $r = Invoke-Git @('-C', $clone, 'status', '--porcelain')
    if ($r.Out.Trim() -eq '') { Write-Result $true "wiki of $Repo is up to date"; exit 0 }
    $changed = @($r.Out -split "`n" | Where-Object { $_.Trim() -ne '' }).Count
    $r = Invoke-Git @('-C', $clone, 'commit', '--quiet', '-m', "Update from $Repo@$($commit.Out.Trim())")
    if ($r.Code -ne 0) { Write-Host $r.Out; Stop-Wiki 'git commit failed (is user.name / user.email set?).' }
    $r = Invoke-Git @('-C', $clone, 'push', '--quiet', 'origin', 'HEAD')
    if ($r.Code -ne 0) { Write-Host $r.Out; Stop-Wiki "git push to $RepoUrl.wiki.git failed." }
    Write-Result $true "wiki of $Repo updated: $changed file(s) changed, $WikiUrl"
} finally {
    foreach ($v in $tokenVars) { Remove-Item -LiteralPath "Env:$v" -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $clone) { Remove-Item -LiteralPath $clone -Recurse -Force -ErrorAction SilentlyContinue }
}
exit 0
