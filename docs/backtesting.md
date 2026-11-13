# Backtesting and the Strategy Tester

Risk Desk is a **manual** trading tool: it has no entry or exit rules, so there is nothing to backtest or optimize. Its results depend entirely on where you put the lines and when you click. Any "backtest" of Risk Desk is therefore a test of your own decisions, not of the software.

## What happens in the Strategy Tester

Risk Desk detects the Strategy Tester and adapts (see [design/02-architecture.md §10](design/02-architecture.md#10-strategy-tester-behaviour)):

- MetaTrader does not deliver chart click events to Expert Advisors in the tester, even in visual mode. Risk Desk therefore polls its buttons on every tick. This works in the **MT4** visual tester. In the **MT5** visual tester, button clicks may not register.
- Confirmation dialogs are answered **Yes** automatically.
- Nothing is written to files: no log file, no saved panel state.
- Screenshots are taken only in visual mode.
- Optimization makes no sense: none of the inputs is a strategy parameter.

The visual tester has not been part of the project's test matrix; it is an optional convenience. If you use it, please report what you see ([SUPPORT.md](../SUPPORT.md)).

## Practising the workflow

To practise with Risk Desk on historical data:

1. MT4: open the Strategy Tester, choose **RiskDesk**, tick **Visual mode**, and use "Every tick" modelling.
2. Start the test, pause it or slow it down, and use the panel as on a live chart.
3. Keep in mind the tester's limits: modelled spreads and fills, no requotes, no partial fills, and symbol properties as of today.

## Pitfalls

- **The tester is not your broker.** Risk Desk exists because brokers differ in filling policies, volume grids, stop levels and tick values. The tester reproduces few of these. A clean tester run says nothing about how a broker will treat the orders; a demo account with that broker does.
- **Slippage and gaps** at the stop-loss are not modelled realistically, so the loss at a stop can look smaller than it will be in the market.
- **Commission** is included in the lot size only if you set `InpCommissionPerLot`.
