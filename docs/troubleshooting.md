# Troubleshooting and FAQ

Risk Desk explains every refusal in its status bar and in the terminal's **Experts** tab (Toolbox, Ctrl+T). Start there: the message usually names the cause. If it does not help, see [SUPPORT.md](../SUPPORT.md) for how to report it.

## Status messages

| Message (or start of it) | Cause | What to do |
|---|---|---|
| "Algo/AutoTrading is off in the terminal toolbar" | The toolbar button is off | Switch on **AutoTrading** (MT4) / **Algo Trading** (MT5) |
| "Allow algo/live trading is unticked in RiskDesk's properties" | The EA may not trade | Right-click the chart → Expert Advisors → Properties → Common → tick *Allow live trading* / *Allow Algo Trading* |
| "Trading not allowed on this account (investor password?)" | Logged in with the investor (read-only) password | Log in with the trading password |
| "Broker disabled EA trading on this account" | The broker does not allow Expert Advisors | Ask the broker; Risk Desk cannot trade there |
| "No connection to trade server" | Terminal offline | Check the connection icon at the bottom right |
| "No quotes for … - market may be closed" | No recent tick | Normal outside trading hours; the server decides whether an order is accepted |
| "Min lot … would risk …" | Even the minimum lot risks more than your Risk % | Move the SL closer, raise Risk %, or allow it with `InpAllowMinLotOverRisk` |
| "Capped at max lot …" | The computed lot is above the broker's maximum | The order is sent with the maximum lot; the real risk is shown |
| Risk-cap refusal naming the open risk, the new risk and the cap | Per-trade or total open-risk cap reached | Close or protect trades, lower Risk %, or change `InpMaxTotalRiskPct` |
| "… has no SL - total risk cannot be computed" | A Risk Desk position without a stop-loss blocks new trades | Give that position an SL |
| Margin refusal with required and available margin | Not enough free margin (minus `InpMarginBufferPct`) | Smaller risk, or `InpReduceToMargin` |
| Refusal naming a minimum distance in points and a price | The SL, TP or pending entry is inside the broker's stops level | Move the line to the price shown |
| "Requote (4 attempts)" | Fast market; the price moved more than `InpSlippagePoints` four times | Try again, or raise `InpSlippagePoints` for that session |
| "Filling policy rejected …" (MT5) | The server refused the filling policy | Leave `InpFillingOverride` on Auto; if it still fails, report it with a BrokerProbe report |
| "Cannot value a price move on … (no conversion rate)" | No exchange rate to convert the symbol's currency into the account currency | Add the conversion pair to Market Watch; report the broker if it persists |
| "Tick value mismatch" | The broker's tick value and Risk Desk's cross-check differ by more than 5 % (MT4) | Risk Desk uses the larger loss, so the lot is smaller. Compare with BrokerProbe |
| "SL could not be attached - position closed" | The broker refused the stop-loss after retries (`InpCloseIfStopFails`) | Check the stops level and the symbol's rules; report it |
| "Lines already on chart" | Add Line / Add Pend Line while lines exist | Drag the existing lines, or Delete Line first |

## FAQ

**Nothing happens when I click a button.** That should not happen: every click ends with a status message. Check that the panel belongs to a running EA (smiley/hat icon at the top right of the chart, and an "initialized" line in the Experts tab). If the EA is running and there is still no message, please report it: this is a bug.

**Why is the lot smaller than I expected?** Usually one of: rounding down to the volume step (never up), commission (`InpCommissionPerLot`), the conservative tick-value rule on some CFDs (see "Tick value mismatch"), the maximum lot, or `InpReduceToMargin`. The SL label shows the risk of the lot that will actually be sent.

**Can the loss be larger than my Risk %?** Yes. Risk % is the planned loss at the SL price. A stop can fill worse (slippage, gaps, weekend opens), and swaps are not included. On index CFDs, demo SL hits filled up to 7.5 % beyond the displayed risk.

**Does Risk Desk close or move my manual trades?** Only when you click a management button. By default *Risk Free*, *Half Close*, *Chart Close* and *Del Pending* act on all trades of the chart symbol, and *Full Close* on the whole account. Limit them with `InpScopeChartOps` / `InpScopeFullClose`.

**Will it open trades by itself?** No. It acts only on your clicks, and when you drop a dragged line of a pending order it placed.

**Can I run it on several charts?** Yes. Each chart has its own panel; the open-risk cap and Full Close work across the account.

**Do I need One-Click Trading?** No.

**Does it work on netting accounts (MT5)?** Yes. An order in the same direction as an existing position asks for confirmation (the position's SL is replaced); an opposite order is refused unless `InpNettingAllowOpposite` is on.

**My broker's symbol names have a suffix (EURUSD.a, EURUSDm).** That is fine: Risk Desk reads the properties of whatever symbol the chart shows.

**Where are the logs?** In the Experts tab, and in `MQL4/Files/RiskDesk/Logs/` or `MQL5/Files/RiskDesk/Logs/` (one file per day, kept `InpLogKeepDays` days).

**How do I reset the panel position?** Change `InpPanelX` / `InpPanelY` and delete `Files/RiskDesk/ui.ini`, or simply drag the panel by its handle. A panel outside the chart is moved back into view automatically.

**Is it the same as Map Manager?** No. It is an independent reimplementation of a similar workflow, with its own code ([NOTICE.md](../NOTICE.md)).
