# Risk Desk

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform: MT4 | MT5](https://img.shields.io/badge/platform-MetaTrader%204%20%7C%205-informational.svg)](#mt4-and-mt5)
[![Release](https://img.shields.io/github/v/release/amirhrahimi/risk-desk?include_prereleases&sort=semver)](https://github.com/amirhrahimi/risk-desk/releases)

Risk Desk is a chart panel (Expert Advisor) for MetaTrader 4 and MetaTrader 5 that turns *"where is my stop?"* and *"how much do I want to risk?"* into a correctly sized order, then manages that trade with a few buttons. You set a risk percentage and drag a stop-loss line on the chart; Risk Desk computes the lot size from the broker's own symbol properties, opens market or pending orders with one click, and offers break-even, partial close and close-all buttons. Every click ends with a message saying what happened and why.

**What it does not do:** it does not trade on its own. It has no signals, no strategy and no automatic entries or exits. It acts only when you click a button, or when you drag a line of a pending order it has placed. It does not trail stops, and it cannot prevent slippage or gaps.

> [!WARNING]
> **Risk disclaimer.** Trading foreign exchange, CFDs and other leveraged products carries a high risk of losing money, and you can lose more than you expect. Risk Desk is provided "as is", without warranty of any kind (see [LICENSE](LICENSE)); you use it entirely at your own risk. It is not financial advice. A bug in this software, a broker's behaviour or a market gap can cause losses. The "risk %" is the planned loss at the stop-loss price: a stop can fill worse than its price (slippage, gaps, weekends), and commissions and swaps are only included where you configure them. **Always test on a demo account with your broker before using a live account**, and check every lot size and stop-loss yourself.

**Status:** 1.7.0 is a **pre-release**. It has been tested on demo accounts only (six accounts, four broker companies, both platforms; see [Broker compatibility](#broker-compatibility)). It has not been tested on live accounts. A few safety paths still lack a test against a real server; see [Known limitations](#known-limitations). 1.8.0 will be the first stable release ([ROADMAP.md](ROADMAP.md)).

## Contents

[Features](#features) · [MT4 and MT5](#mt4-and-mt5) · [Requirements](#requirements) · [Installation](#installation) · [Quick start on a demo account](#quick-start-on-a-demo-account) · [Key inputs](#key-inputs) · [Broker compatibility](#broker-compatibility) · [How it differs from the original](#how-it-differs-from-the-original) · [Backtesting](#backtesting) · [Known limitations](#known-limitations) · [Help](#help) · [Contributing](#contributing) · [Credits](#credits) · [Licence](#licence)

## Features

- **Risk-based lot size.** Lots = (risk % of balance) ÷ (money lost per lot between entry and stop-loss, plus commission). The lot is always rounded **down** to the broker's volume step. If even the minimum lot would risk more than you asked, the order is refused with an explanation, unless you allow it.
- **Lines on the chart.** A red stop-loss line (and an optional green take-profit line) that you drag. A label on the SL line shows the money at risk, the %, the lot and the distance in points.
- **Market orders:** Buy and Sell, with the live price on the button. The button for the side your stop-loss makes invalid is dimmed.
- **Pending orders:** an entry line plus SL/TP lines. *Pending Info* shows the order type the lines imply (Buy/Sell Stop or Limit). Placed pending orders are drawn on the chart and can be modified by dragging their lines.
- **Take-profit modes:** no TP, automatic TP at a reward/risk ratio, or a manual TP line.
- **Trade management:** *Risk Free* (moves the SL to break-even plus spread and commission), *Half Close* (closes a share of each position, rounded to the volume grid), *Chart Close*, *Full Close*, *Del Pending*.
- **Safety checks before every order:** terminal and account permissions, stops and freeze levels, margin (with a buffer), a per-trade risk cap and a total open-risk cap, double-click protection, optional confirmation dialogs.
- **Broker compatibility layer:** prices normalized to the tick size, volumes to the broker's grid, automatic MT5 filling policy and expiration fallbacks, currency conversion for any account currency, netting and hedging accounts, cent accounts, a retry policy that never resends an order blindly after an unclear result.
- **Status bar and log:** green (done), amber (partial or skipped) and red (refused or failed, with the reason) for every action, mirrored to the Experts tab and an optional daily log file.
- **Extras:** spread display, a candle countdown, removal of MetaTrader's closed-trade arrows (optional), automatic screenshots after trade actions, panel scaling and an automatic two-column layout on short charts, and settings that survive timeframe changes and restarts.
- **Diagnostics:** the *BrokerProbe* script writes a report of your broker's account and symbol properties without trading.

Each button is described in the [user guide](docs/user-guide.md).

## MT4 and MT5

Both platforms are built from one source tree and offer the same features. The differences are those the platforms impose:

| Topic | MT4 | MT5 |
|---|---|---|
| Features | all | all |
| Filling policy | not applicable | chosen from the symbol's flags, with a fallback ladder (input `InpFillingOverride` to force one) |
| Netting accounts | not applicable (every trade is its own ticket) | supported: same-direction adds need confirmation, opposite orders are refused unless `InpNettingAllowOpposite` |
| Partial close | the broker decides whether the rest keeps the ticket or gets a new one; both are handled | the position keeps its ticket |
| Pending expiry | `expiration` time | expiration mode from the symbol's flags (GTC, day, specified) |
| Stop-limit orders | not offered | not supported by Risk Desk |
| Strategy Tester | buttons polled in the visual tester | button clicks may not register in the visual tester ([docs/backtesting.md](docs/backtesting.md)) |

## Requirements

- MetaTrader 4 or MetaTrader 5 desktop terminal on Windows. Tested with MT4 build 1492 and MT5 builds 6311 and 6316; older builds are untested.
- Algo trading enabled: the **AutoTrading** / **Algo Trading** toolbar button, and *Allow live trading* (MT4) / *Allow Algo Trading* (MT5) in the EA's properties. MetaTrader's One-Click Trading is not needed.
- An account on which the broker allows Expert Advisors: hedging or netting (MT5), any account currency. Cent accounts are supported, but the cent display has only been tested in forced mode, not on a real cent account.
- Any symbol and timeframe: symbol properties are read from the broker at run time. Tested symbols are listed under [Broker compatibility](#broker-compatibility).
- No DLLs, no internet access by the EA. Files are written only under `MQL4/Files/RiskDesk/` or `MQL5/Files/RiskDesk/` (settings, logs, screenshots).

## Installation

**From a release (no compiling):** download `RiskDesk-<version>.zip` from [Releases](https://github.com/amirhrahimi/risk-desk/releases). In the terminal choose **File → Open Data Folder**, then copy the zip's `MQL4` folder (MetaTrader 4) or `MQL5` folder (MetaTrader 5) into that data folder, merging with the folder that is already there. Restart the terminal or right-click **Navigator → Refresh**. *RiskDesk* appears under **Expert Advisors**.

**From source:** copy `src/Experts/RiskDesk.mq4` (or `.mq5`) to `MQL4/Experts/` (or `MQL5/Experts/`), and `src/Include/RiskDesk/` to `MQL4/Include/RiskDesk/` (or `MQL5/Include/RiskDesk/`). Then open the `.mq4`/`.mq5` in MetaEditor and press **F7**.

Step by step, with the optional scripts: [docs/installation.md](docs/installation.md).

## Quick start on a demo account

1. Open a **demo** account with your broker and a chart of a liquid symbol (for example EURUSD).
2. Drag **RiskDesk** from the Navigator onto the chart, tick *Allow live trading* / *Allow Algo Trading*, and press OK. The status bar at the bottom of the panel shows `RiskDesk 1.7.0 ready`.
3. Type a small value in **Risk %**, for example `0.5`.
4. Click **Add Line**. A red SL line appears; drag it below the price for a buy (above the price for a sell).
5. Read **Lots** and the label on the SL line: the money you would lose at that stop, the %, the lot size and the distance.
6. Click **Buy** (or **Sell**). The status bar shows the ticket, the lots and the risk. Compare it with the trade in the terminal's **Trade** tab.
7. Try **Risk Free**, **Half Close** and **Chart Close** on that demo position, and read the status bar after each click.
8. Repeat with your other symbols (gold, an index) and note the lot sizes and messages. On a new broker, run **BrokerProbe** once (see [docs/installation.md](docs/installation.md)).

> [!IMPORTANT]
> By default *Risk Free*, *Half Close*, *Chart Close* and *Del Pending* act on **every** trade of the chart's symbol, including trades opened by hand or by other EAs, and *Full Close* closes **every position on the account**. Only *Full Close* asks for confirmation by default. If you run other EAs, set `InpScopeChartOps` and `InpScopeFullClose` to the "RiskDesk trades only" options and consider enabling the confirmations.

## Key inputs

The inputs that change what is traded. All inputs, with types, defaults and allowed ranges: [docs/configuration.md](docs/configuration.md).

| Input | Type | Default | Meaning | Allowed range |
|---|---|---|---|---|
| `InpDefaultRiskPct` | double | 1.0 | Risk % shown on first start (the panel then remembers your last value per account) | 0.01 – `InpMaxRiskPerTradePct` |
| `InpMaxRiskPerTradePct` | double | 10.0 | Highest Risk % the panel accepts | 0.01 – 100 |
| `InpMaxTotalRiskPct` | double | 10.0 | New trades are refused when Risk Desk's open risk would exceed this | 0.01 – 100 |
| `InpRiskBase` | enum | Balance | What the % refers to: balance, equity or the lower of the two | – |
| `InpCommissionPerLot` | double | 0.0 | Round-turn commission per lot in account currency, added to the loss per lot | 0 – 1,000,000 |
| `InpAllowMinLotOverRisk` | bool | false | Send the minimum lot even when it risks more than Risk % (still within the per-trade cap) | – |
| `InpMarginBufferPct` | double | 5.0 | Share of free margin kept unused | 0 – 90 |
| `InpTradeWithTpLine` / `InpManualTpLine` / `InpTpRR` | bool / bool / double | true / false / 1.0 | TP mode: no TP, automatic TP at R/R (default), or a manual TP line | R/R 0.01 – 50 |
| `InpSlippagePoints` | int | 20 | Maximum deviation for market orders, in points, for every symbol | 0 – 100,000 |
| `InpCloseIfStopFails` | bool | true | Close a position whose stop-loss cannot be attached | – |
| `InpScopeChartOps` | enum | all trades on the symbol | Scope of Risk Free, Half Close, Chart Close, Del Pending | – |
| `InpScopeFullClose` | enum | all trades on the account | Scope of Full Close | – |
| `InpConfirmTrades` / `InpConfirmHalfClose` / `InpConfirmChartClose` / `InpConfirmFullClose` | bool | false / false / false / true | Confirmation dialogs | – |
| `InpMagic` | int | 772211 | Magic number that marks Risk Desk's trades | – |

## Broker compatibility

Verified on demo accounts with Risk Desk's own diagnostics: *BrokerProbe* (account and symbol properties), *GatewaySmoke* (open, modify, partial close, close, and place/modify/delete pending orders, with real demo orders), and the panel self-test suites (Buy/Sell, pending orders, Risk Free, Half Close, Chart Close, Full Close, clicked on a real chart). Details, per-symbol properties and raw reports: [docs/broker-compatibility.md](docs/broker-compatibility.md) and [broker-profiles/](broker-profiles/SUMMARY.md).

| Broker | Account | Platform | Tested | Result | Notes |
|---|---|---|---|---|---|
| IG | demo, USD, 1:200, hedging | MT4 (build 1492) | 2026-11-12/13 | passed | EURUSD, XAUUSD, US30. Stops level 40/200/150 points. Partial close keeps the ticket. Gold was requoted at the US open with the default 20-point slippage. |
| IC Markets EU | demo, USD, 1:30, hedging | MT4 (build 1492) | 2026-11-12/13 | passed | EURUSD, XAUUSD, US30 (whole lots). Partial close gives the rest a new ticket. |
| IC Markets EU | demo, EUR, 1:30, hedging | MT5 (build 6311) | 2026-11-12/13 | passed | EURUSD, XAUUSD, US30. The server accepts only IOC filling; chosen automatically. |
| Dukascopy | demo, EUR, 1:100, hedging | MT4 (build 1492) | 2026-11-12/13 | passed | EURUSD, XAUUSD, USA30.IDX, AUS.IDX (whole contracts). Index tick values are reported in the index currency, so lot sizes are deliberately conservative (up to 38 % below the risk). |
| Dukascopy | demo, EUR, 1:100, hedging | MT5 (build 6311) | 2026-11-12/13 | passed | Same symbols. IOC filling only; closes are confirmed through the position history. |
| MetaQuotes-Demo | demo, EUR, 1:100, **netting** | MT5 (build 6311) | 2026-11-12/13 | passed | EURUSD, XAUUSD, majors. US30/US500 are disabled for trading on this server. |
| IG | – | MT5 | – | untested | community reports welcome |
| any broker | live or cent account | MT4 / MT5 | – | untested | community reports welcome |

Have you tested Risk Desk with another broker? Please open a [broker test report](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml).

## How it differs from the original

Risk Desk reimplements the workflow of **Map Manager** by Mohammad Ali Poursamadi and team ([poursamadi.com](https://poursamadi.com/en/)). The original's website says that it *"has been tested only on demo and live accounts of the broker introduced in the 'Trusted broker' section"*. Risk Desk was built to behave the same on every broker, and has been tested on the demo accounts of several brokers on both platforms (table above). It also adds the status bar, risk caps, margin and commission checks, confirmations, MT5 netting support, the pending-order overlay with drag-to-modify, and the BrokerProbe diagnostics. More features are planned ([ROADMAP.md](ROADMAP.md)). Risk Desk is independent and not endorsed by the original's authors; what was taken from the original is listed in [NOTICE.md](NOTICE.md).

## Backtesting

Risk Desk is a manual tool, so there is no strategy to backtest or optimize. In the Strategy Tester it can be used in visual mode to practise the workflow, with limitations (confirmations are answered "Yes", nothing is saved to files, MT5 may ignore clicks). See [docs/backtesting.md](docs/backtesting.md).

## Known limitations

- **Pre-release.** Three safety paths have not yet been triggered on a real server: closing a position whose stop-loss could not be attached (`InpCloseIfStopFails`), handling an unclear result such as a timeout (no blind resend), and the MT5 filling-policy fallback after a real rejection. They are covered by design and code review only. Tests for them are planned for 1.8.0.
- A stop-loss can fill beyond its price. On index CFDs, demo SL hits filled up to 7.5 % beyond the displayed risk on MT5.
- One slippage value is used for every symbol. On fast markets (for example gold at the US open on IG MT4) market orders can be requoted until the retries run out; the status bar then says so and nothing is opened.
- Screenshots, log lines and BrokerProbe reports contain your account number. Remove it before sharing them ([SUPPORT.md](SUPPORT.md)).

## Help

- [User guide](docs/user-guide.md) · [Configuration](docs/configuration.md) · [Troubleshooting and FAQ](docs/troubleshooting.md) · [Glossary](docs/glossary.md) · [Architecture](docs/architecture.md)
- Questions and problems: [SUPPORT.md](SUPPORT.md). Security issues: [SECURITY.md](SECURITY.md).

## Contributing

Bug reports, broker test reports and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). Planned work is in [ROADMAP.md](ROADMAP.md), and changes are listed in [CHANGELOG.md](CHANGELOG.md).

## Credits

Thanks to **Mohammad Ali Poursamadi and his team** for Map Manager, whose workflow inspired this project ([NOTICE.md](NOTICE.md)), and to everyone who reports how Risk Desk behaves with their broker.

## Licence

Copyright (c) 2026 Amir Rahimi. Released under the [MIT License](LICENSE). MetaTrader is a trademark of MetaQuotes Ltd; this project is not affiliated with MetaQuotes or with any broker named here.
