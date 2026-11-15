# Architecture

A short tour of how Risk Desk is built and how it decides what to send. The full specification is in [docs/design/](design/): architecture ([02](design/02-architecture.md)), broker rules ([03](design/03-broker-compatibility.md)), risk engine ([04](design/04-risk-engine.md)), trade operations ([06](design/06-trade-operations.md)) and the decision records ([10](design/10-decisions.md)).

## One source tree, two platforms

`src/` mirrors a MetaTrader data folder:

```
src/Experts/RiskDesk.mq4 | .mq5        entry files: five event handlers forwarded to CApp
src/Include/RiskDesk/
   Build.mqh                           product name, version, copyright, debug switch
   App/        CApp, CController (event -> command), commands per button, inputs, settings, state
   UI/         panel, widgets, trade lines, pending-order overlay, status bar, theme, layout
   Services/   logger, persistence, screenshots, closed-trade objects, candle time
   Domain/     pure logic: types, price math, risk math, validators, planner, risk budget, formatting
   Platform/   the only layer that calls MetaTrader's trade, symbol and account functions
src/Scripts/RiskDesk/                  BrokerProbe, GatewaySmoke, RiskDeskTests (unit tests)
```

The same files compile as MQL4 and as MQL5. Platform differences are confined to `Platform/` (and the input declarations): for example, `CTradeGateway` exists twice, once per platform, with the same public methods, and the compiler picks one. The MT5 Standard Library is not used, there are no DLLs, and there is no network access.

## Layers

```
 App ─────────▶ UI, Services
  │
  ▼
 Domain   (pure: no terminal calls; unit-tested)
  ▲
  │ Domain types only
 Platform (symbol/account specs, quotes, money conversion, trade gateway, history)
```

- **Domain** receives plain structs (symbol spec, account spec, quote, lines, settings) and returns a plan or a refusal. Because it never calls the terminal, the `RiskDeskTests` script can check it on both platforms (842 checks, including the specification's test vectors).
- **Platform** reads every broker property at run time and is the only place that sends orders.
- **App** wires it together: read specs and quotes, ask Domain to plan and validate, ask Platform to execute, tell the UI what to show.

## What happens when you click Buy

1. Check permissions: connection, algo trading in the terminal and in the EA, account and symbol trade mode.
2. Read a fresh quote and the symbol's properties.
3. Read the lines and normalize their prices to the symbol's **tick size**.
4. Validate the side: the SL must be below the Bid for a buy, and every price must respect the broker's stops level.
5. Compute the **loss per lot** from entry to SL in the account currency, plus commission. MT5 uses `OrderCalcProfit` (tick value as fallback); MT4 uses the tick value and cross-checks it against tick size × contract size × exchange rate: if they differ by more than 5 %, it warns and uses the larger loss. A move that cannot be valued is refused.
6. Compute the lot: `risk money ÷ loss per lot`, rounded **down** to the volume step. Refuse if it is below the minimum lot (unless allowed); cap at the maximum lot with a warning.
7. Check the risk budget (per-trade cap, total open-risk cap) and the margin (free margin minus the buffer).
8. Ask for confirmation, if enabled.
9. Send through `CTradeGateway`: MT5 filling policy from the symbol's flags with a fallback ladder; retries only for retryable answers, with a fresh price and the same lot; after an unclear answer (timeout, lost connection), check whether the order exists before doing anything else. Then verify the position's SL/TP and fix them, or close the position if the SL cannot be attached.
10. Show the result in the status bar, write the log line, remove the lines, take the screenshot.

Every step that fails stops the command and shows its reason. Pending orders, Risk Free, Half Close and the close buttons follow the same pattern ([design/06-trade-operations.md](design/06-trade-operations.md)).

## The risk formulas

```
riskMoney  = base × Risk% / 100                 base = balance (or equity, or the lower of both)
lossPerLot = money lost per 1 lot from entry to SL  +  commission per lot
lots       = floor_to_step(riskMoney / lossPerLot)  (never rounded up)
actualRisk = lots × lossPerLot                       shown on the SL label and in the status bar
TP (auto)  = entry ± R/R × |entry − SL|
```

The entry is the Ask for a buy and the Bid for a sell, so the spread at entry is already part of the SL distance. Details, edge cases and test vectors: [design/04-risk-engine.md](design/04-risk-engine.md).

## Identification and scope

Risk Desk marks its orders with a magic number (`InpMagic`). The total open-risk cap counts only those orders. The management buttons act on all trades of the chart symbol (or of the account, for Full Close) unless they are limited to Risk Desk's trades in the inputs.

## State

- Panel position and hidden state: `Files/RiskDesk/ui.ini` (shared by all charts).
- Risk % per account: `Files/RiskDesk/acct_<login>.ini`.
- Lines: the chart objects themselves. They are adopted again after a timeframe change, so they never duplicate or move.
- Logs: `Files/RiskDesk/Logs/RiskDesk_<yyyymmdd>.log`; screenshots: `Files/RiskDesk/Screenshots/`.

## Tests

| Level | What |
|---|---|
| Build | both platforms compile with 0 errors and 0 warnings (`build/build.ps1`) |
| Unit | `RiskDeskTests` on MT4 and MT5 (`build/run-tests.ps1`) |
| Broker | `BrokerProbe`, `GatewaySmoke` on demo accounts (`build/run-script.ps1`) |
| Panel | debug-build self-test suites that click the real panel on demo accounts (`build/run-uitest.ps1`) |

See [design/08-testing.md](design/08-testing.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

