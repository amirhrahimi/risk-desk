# RiskDesk - build paths TEMPLATE (committed).
#
# Copy this file to build/paths.local.ps1 (git-ignored) and replace the
# examples with the real paths of this computer. build.ps1,
# install-junctions.ps1 and the run-*.ps1 runners read paths.local.ps1.
#
# Windows: Windows PowerShell 5.1 or PowerShell 7. macOS / Linux: PowerShell 7
# (pwsh), with MetaTrader running under Wine (ADR-032). Forward slashes work
# everywhere; a leading ~ means your home folder.

# --- MetaEditor ---------------------------------------------------------------
# The editor sits in the terminal's INSTALL folder (not the data folder):
#   MT4: metaeditor.exe      MT5: metaeditor64.exe (Wine installs: MetaEditor64.exe)
# Tip (Windows): in the terminal press F4 to open MetaEditor, then look up the
# running program's location in Task Manager (right-click > Open file location).
# One MetaEditor per platform is enough: build.ps1 compiles every .mq4 with
# $MetaEditor4 and every .mq5 with $MetaEditor5, and the junctions make the
# compiled files visible in every terminal.
$MetaEditor4 = 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe'
$MetaEditor5 = 'C:\Program Files\MetaTrader 5\metaeditor64.exe'

# macOS, MetaQuotes' MetaTrader 5 app (its Wine prefix):
#   $MetaEditor5 = '~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe'
# Linux, MetaQuotes' mt5linux.sh (prefix ~/.mt5):
#   $MetaEditor5 = '~/.mt5/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe'
# MT4 under Wine: the same pattern in the prefix you installed it into, e.g.
#   $MetaEditor4 = '~/.mt4/drive_c/Program Files (x86)/MetaTrader 4/metaeditor.exe'
# To find them:  find ~ -iname 'metaeditor*.exe' 2>/dev/null

# --- Wine (macOS / Linux only; ignored on Windows) ---------------------------
# Leave these $null to use, in this order: the Wine inside
# /Applications/MetaTrader 4.app or MetaTrader 5.app (macOS), then wine and
# wine64 on the PATH. Set them when that is not the Wine your terminals run
# with: a prefix should always be run by the Wine that created it. The prefix
# (WINEPREFIX) is taken from each path above: the folder that holds drive_c.
$Wine4 = $null
$Wine5 = $null
#   $Wine5 = '/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64'
#   $Wine5 = '/usr/bin/wine'

# --- Terminal data folders ----------------------------------------------------
# One entry per terminal you test with (accounts A1-A7 in docs/08-testing.md).
# DataPath: the folder that CONTAINS MQL4 or MQL5.
#   Windows: in the terminal, File > Open Data Folder, copy the folder path
#     from the Explorer address bar; usually
#     C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<long hex id>.
#   macOS / Linux: the host path inside the Wine prefix. MetaQuotes' macOS app
#     and Linux installer keep the data in the install folder itself, e.g.
#     ~/.mt5/drive_c/Program Files/MetaTrader 5. To find them:
#       find ~ -type d \( -name MQL4 -o -name MQL5 \) -path '*drive_c*' 2>/dev/null
# Platform: 'mt4' or 'mt5'.
# Wine (optional, macOS / Linux): this terminal's Wine, if not $Wine4 / $Wine5.
$Terminals = @(
    @{ Name = 'A1 IG MT4';             Platform = 'mt4'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A2 IC Markets EU MT4';  Platform = 'mt4'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A3 IC Markets EU MT5';  Platform = 'mt5'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A4 Dukascopy MT4';      Platform = 'mt4'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A5 Dukascopy MT5';      Platform = 'mt5'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    # macOS:  @{ Name = 'MT5 (Mac app)'; Platform = 'mt5'; DataPath = '~/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5' }
    # Linux:  @{ Name = 'MT5 (Wine)';    Platform = 'mt5'; DataPath = '~/.mt5/drive_c/Program Files/MetaTrader 5' }
)
