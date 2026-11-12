# RiskDesk - build paths TEMPLATE (committed).
#
# Copy this file to build/paths.local.ps1 (git-ignored) and replace the
# examples with the real paths of this PC. Both build.ps1 and
# install-junctions.ps1 read paths.local.ps1.

# --- MetaEditor ---------------------------------------------------------------
# The editor sits in the terminal's INSTALL folder (not the data folder):
#   MT4: metaeditor.exe      MT5: metaeditor64.exe
# Tip: in the terminal press F4 to open MetaEditor, then look up the running
# program's location in Task Manager (right-click > Open file location).
# One MetaEditor per platform is enough: build.ps1 compiles every .mq4 with
# $MetaEditor4 and every .mq5 with $MetaEditor5, and the junctions make the
# compiled files visible in every terminal.
$MetaEditor4 = 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe'
$MetaEditor5 = 'C:\Program Files\MetaTrader 5\metaeditor64.exe'

# --- Terminal data folders ----------------------------------------------------
# One entry per terminal you test with (accounts A1-A7 in docs/08-testing.md).
# DataPath: in the terminal, File > Open Data Folder, copy the folder path from
# the Explorer address bar. It is the folder that CONTAINS MQL4 or MQL5,
# usually C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<long hex id>.
# Platform: 'mt4' or 'mt5'.
$Terminals = @(
    @{ Name = 'A1 IG MT4';             Platform = 'mt4'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A2 IC Markets EU MT4';  Platform = 'mt4'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A3 IC Markets EU MT5';  Platform = 'mt5'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A4 Dukascopy MT4';      Platform = 'mt4'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
    @{ Name = 'A5 Dukascopy MT5';      Platform = 'mt5'; DataPath = 'C:\Users\<you>\AppData\Roaming\MetaQuotes\Terminal\<hex id>' }
)
