# Broker compatibility

Brokers differ in more than spreads: volume grids, tick sizes, how tick values are reported, which MT5 filling policies they accept, stop and freeze levels, expiration modes, netting or hedging, and whether a partial close keeps the ticket. Risk Desk reads all of these from the terminal at run time and has no broker-specific settings. The rules it follows are specified in [design/03-broker-compatibility.md](design/03-broker-compatibility.md) (BC-01 to BC-18).

## How Risk Desk was tested

| Level | Tool | What it does |
|---|---|---|
| Properties | `BrokerProbe` script | Reports the account's properties and those of the test symbols (20–33 symbols per account here), and cross-checks the reported tick value against contract size × rate and, on MT5, `OrderCalcProfit`. MT5: validates market and pending requests with `OrderCheck`. **Sends no order.** |
| Trade gateway | `GatewaySmoke` script (source only, **demo accounts only**) | With real demo orders of the minimum volume: open buy with SL/TP, verify, modify SL, partial close, close, open/close a sell, place/modify/delete a buy limit. Writes a PASS/FAIL table. |
| Panel | Self-test suites (debug build, demo only) | Clicks the panel's buttons on a real chart with real demo orders and checks every result and status message: Buy/Sell, pending orders and overlay drags, Risk Free, Half Close over the volume grids, Chart Close, Full Close. |
| Logic | `RiskDeskTests` script | 842 checks of the risk math, rounding, validation and planning, on MT4 and MT5. |

## Results

All tests ran on **demo** accounts, 2026-11-12 and 2026-11-13. No live account has been tested. Reports: [broker-profiles/](../broker-profiles/SUMMARY.md) (redacted: the account number is replaced by the label A1–A6).

| # | Broker | Account | Platform | BrokerProbe | GatewaySmoke | Panel suites | Result |
|---|---|---|---|---|---|---|---|
| A1 | IG | demo, USD, 1:200, hedging | MT4 build 1492 | 27 symbols | EURUSD, XAUUSD, US30: 12/12 each | trade, pending, manage, Half Close | passed |
| A2 | IC Markets EU | demo, USD, 1:30, hedging | MT4 build 1492 | 33 symbols | EURUSD 9/9 (+1 skipped by setting), XAUUSD, US30: 12/12 | trade, pending, manage, Half Close | passed |
| A3 | IC Markets EU | demo, EUR, 1:30, hedging | MT5 build 6311 | 28 symbols | EURUSD 9/9 (+1 skipped by setting), XAUUSD, US30: 12/12 | trade, pending, manage, Half Close | passed |
| A4 | Dukascopy | demo, EUR, 1:100, hedging | MT4 build 1492 | 30 symbols | EURUSD, XAUUSD, USA30.IDX, AUS.IDX: 12/12 each | trade, pending, manage, Half Close | passed |
| A5 | Dukascopy | demo, EUR, 1:100, hedging | MT5 build 6311 | 20 symbols | EURUSD, XAUUSD, USA30.IDX, AUS.IDX: 12/12 each | trade, pending, manage, Half Close | passed |
| A6 | MetaQuotes-Demo | demo, EUR, 1:100, **netting** | MT5 build 6311 | 28 symbols | EURUSD, XAUUSD: 12/12 each | trade, pending, manage, Half Close (majors) | passed |
| – | IG | – | MT5 | – | – | – | untested |
| – | any | live account | MT4 / MT5 | – | – | – | untested |
| – | any | cent account | MT4 / MT5 | – | – | – | untested (cent display tested in forced mode only) |

"Passed" means every executed step gave the expected result. The observations below are broker behaviour that Risk Desk handles, not failures.

## What was observed, per account

- **A1 IG MT4:** FX pairs are reported as CFDs with all currencies in USD. Stops level: 40 points EURUSD, 200 XAUUSD, 150 US30. A partial close keeps the original ticket, and the closed part appears in the history as a new order with magic 0; Risk Desk reads the P/L from there. XAUUSD at the US open: every Buy/Sell was requoted four times with the default `InpSlippagePoints` = 20 (0.20 USD, below the gold spread); with 60, every order filled. Risk Desk then shows a red "Requote (4 attempts)" and opens nothing.
- **A2 IC Markets EU MT4:** US30 and USTEC trade in whole lots (min 1, step 1). A partial close gives the rest a new ticket, which the status bar names. Stops and freeze level 0.
- **A3 IC Markets EU MT5:** only IOC filling is accepted (FOK and RETURN are refused with retcode 10030); Risk Desk picks IOC from the symbol's flags. US30 minimum 0.1 lot. US30 market orders filled up to 4 index points from the price sent, so an automatic R/R take-profit can be up to that far from "R/R from the fill"; SL and lot size are not affected.
- **A4 Dukascopy MT4:** index CFDs report the tick value in the index currency rather than EUR (USA30.IDX 11 %, AUS.IDX 62 % above contract × rate). Risk Desk warns and uses the larger loss, so lot sizes there are up to 38 % smaller than the risk would allow; this is deliberate. AUS.IDX trades whole contracts. A single request occasionally took 7–11 s to be answered. After a successful delete, the terminal listed the deleted order for a moment; Risk Desk waits until it is gone.
- **A5 Dukascopy MT5:** IOC filling only. Closes are answered "done" without a deal ticket or price; Risk Desk finds the deal through the position history.
- **A6 MetaQuotes-Demo MT5 (netting):** FOK filling only. The reported tick values of stock CFDs and gold are wrong (10.9 % and 88.9 % off); on MT5 Risk Desk values the move with `OrderCalcProfit`, which was correct. US30 and US500 are disabled for trading on this server. A same-direction order merged with the position after confirmation; an opposite order was refused by default and reduced the position with `InpNettingAllowOpposite`.
- **Stop-loss fills:** on FX and gold, SL hits booked 100–101 % of the displayed risk. On index CFDs, SL hits on MT5 (A3 US30, A5 USA30.IDX) filled up to 7.5 % beyond it, because of slippage at the stop.

## Not yet verified on any server

These paths are implemented but no demo server produced the situation that triggers them. Tests that force them are planned ([ROADMAP.md](../ROADMAP.md)):

- closing a position whose SL could not be attached (`InpCloseIfStopFails`, rule R7);
- an ambiguous result (timeout, lost connection), which must be checked before any resend (rule R9);
- the MT5 filling-policy fallback after a real rejection (every server reported its filling flags correctly).

## Add your broker

Reports from other brokers, platforms and account types are welcome:

1. On a **demo** account, run **BrokerProbe** on a chart of EURUSD ([installation.md](installation.md#run-brokerprobe-optional-recommended-for-a-new-broker)).
2. Optionally, if you can compile from source: run **GatewaySmoke** on a demo account. It refuses to run on a live account, uses the minimum volume and closes or deletes everything it opened.
3. Try the quick-start steps from the [README](../README.md#quick-start-on-a-demo-account) with a few symbols.
4. **Redact** the reports (account number and data path): `build/redact-report.ps1 -Path <report> -Label C1`.
5. Open a [broker test report](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml) and attach the redacted reports.
