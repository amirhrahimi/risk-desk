# Installation

Risk Desk runs in the MetaTrader 4 or MetaTrader 5 desktop terminal on Windows. You can install a compiled release (no compiler needed) or compile it from source in MetaEditor.

## Where the files go

Every terminal has a *data folder*. In the terminal choose **File → Open Data Folder**; it contains `MQL4` (MetaTrader 4) or `MQL5` (MetaTrader 5).

| File | MetaTrader 4 | MetaTrader 5 | Needed? |
|---|---|---|---|
| Expert Advisor | `MQL4/Experts/RiskDesk.ex4` | `MQL5/Experts/RiskDesk.ex5` | yes |
| BrokerProbe script | `MQL4/Scripts/RiskDesk/BrokerProbe.ex4` | `MQL5/Scripts/RiskDesk/BrokerProbe.ex5` | optional (diagnostics) |
| Settings, logs, screenshots, reports | `MQL4/Files/RiskDesk/` | `MQL5/Files/RiskDesk/` | created by Risk Desk |

## Option A: install a release

1. Download `RiskDesk-<version>.zip` from the [Releases page](https://github.com/amirhrahimi/risk-desk/releases). Optionally check it against `RiskDesk-<version>.sha256.txt` (PowerShell: `Get-FileHash RiskDesk-<version>.zip`).
2. Unzip it. It contains an `MQL4` and an `MQL5` folder in the layout above.
3. Close the terminal, or keep it open and refresh the Navigator later.
4. Copy the `MQL4` folder (for MetaTrader 4) or the `MQL5` folder (for MetaTrader 5) into the data folder, merging it with the folder that is already there.
5. In the terminal: **Navigator → Expert Advisors → right-click → Refresh** (or restart the terminal). *RiskDesk* appears under Expert Advisors.

## Option B: compile from source

1. Download or clone this repository.
2. Copy into the data folder (MT4 shown; for MT5 use `MQL5` and the `.mq5` files):

   | From the repository | To the data folder |
   |---|---|
   | `src/Experts/RiskDesk.mq4` | `MQL4/Experts/RiskDesk.mq4` |
   | `src/Include/RiskDesk/` (whole folder) | `MQL4/Include/RiskDesk/` |
   | `src/Scripts/RiskDesk/` (whole folder, optional) | `MQL4/Scripts/RiskDesk/` |

3. Open MetaEditor (**F4** in the terminal), open `Experts/RiskDesk.mq4`, and press **F7** (Compile). The *Errors* tab must end with `0 errors, 0 warnings`.
4. Optionally compile `Scripts/RiskDesk/BrokerProbe.mq4` the same way.
5. Refresh the Navigator in the terminal.

The includes are relative (`..\Include\RiskDesk\...`), so this layout compiles without changes. Developers who work on several terminals can use the build scripts in `build/` instead ([CONTRIBUTING.md](../CONTRIBUTING.md)).

## Allow algo trading

Risk Desk sends orders only when you click, but MetaTrader treats it as an Expert Advisor, so algo trading must be allowed:

1. Toolbar: **AutoTrading** (MT4) / **Algo Trading** (MT5) must be on (green).
2. When attaching the EA, on the **Common** tab: tick **Allow live trading** (MT4) / **Allow Algo Trading** (MT5).
3. DLL imports and WebRequest are **not** needed. MetaTrader's One-Click Trading is not needed either.

If one of these is off, the status bar says which one ([troubleshooting.md](troubleshooting.md)).

## Attach to a chart

Drag **RiskDesk** from the Navigator onto a chart, check the inputs ([configuration.md](configuration.md)) and press OK. The panel appears at the top left, and the status bar shows `RiskDesk <version> ready`. You can run Risk Desk on several charts at once; the open-risk cap and Full Close work across all of them.

Start on a **demo** account: see the quick start in the [README](../README.md#quick-start-on-a-demo-account) and the [user guide](user-guide.md).

## Run BrokerProbe (optional, recommended for a new broker)

BrokerProbe writes a report of the account's and symbols' trading properties. **It sends no orders.** On MT5 it validates requests with `OrderCheck` only.

1. Drag **Scripts → RiskDesk → BrokerProbe** onto any chart of the account you want to check, and press OK.
2. When it finishes, an alert names the report: `MQL4/Files/RiskDesk/probe_<company>_MT4_<login>_<date>.txt` (or `MQL5/...`).
3. The report contains your **account number** and the path of your data folder, which includes your Windows user name. Before you share it, remove both: run `build/redact-report.ps1` from this repository, or replace them by hand.

## Update

Replace the files as in Option A or B, then refresh the Navigator. To be sure the new version runs, re-attach Risk Desk to its charts or restart the terminal; the Experts tab logs the version when it starts (`RiskDesk <version> starting`). Your settings and the panel position in `Files/RiskDesk/` are kept.

## Uninstall

1. Remove Risk Desk from every chart (**right-click → Expert Advisors → Remove**). This deletes all its chart objects (names starting with `RD_`).
2. Delete `Experts/RiskDesk.ex4|.ex5` (and `.mq4|.mq5` if you compiled it), `Include/RiskDesk/` and `Scripts/RiskDesk/`.
3. Optionally delete `Files/RiskDesk/` (settings, logs, screenshots, reports).

Open trades are not touched by removing the EA.
