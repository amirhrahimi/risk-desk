# User guide

This page explains the panel, the lines and every button. Test each one on a **demo** account first. Input names in `code` are explained in [configuration.md](configuration.md).

## The panel

```
          ✥                 drag handle: move the panel
 ┌───────────────────────┐
 │ RiskDesk          [–] │  [–] hides / shows the panel
 │ Risk %  [ 1.00      ] │  type your risk; Enter or click elsewhere
 │ Lots    [ 0.50      ] │  lot size Risk Desk will send (read-only)
 │ [     Add Line      ] │
 │ [    Delete Line    ] │
 │ [   Buy 1.10012     ] │  live Ask
 │ [   Sell 1.10000    ] │  live Bid
 │ [   Add Pend Line   ] │
 │ [    Set Pending    ] │
 │     Pending Info      │
 │ [ Buy Stop · 0.35   ] │  order type the lines imply
 │ [    Del Pending    ] │
 │ [     Risk Free     ] │
 │ [    Half Close     ] │
 │ [    Chart Close    ] │
 │ [    Full Close     ] │
 │ Spread: 7 pts         │
 │ ✔ Buy 0.50 EURUSD …   │  status bar: result of the last action
 └───────────────────────┘
          📷                camera: save a screenshot now
```

On a short chart the panel shrinks to fit or switches to two columns (`InpAutoFitPanel`, `InpPanelColumns`). The position, the hidden state and your Risk % are remembered across timeframe changes and restarts.

## Risk % and Lots

- **Risk %** is the share of your balance (`InpRiskBase`) you are prepared to lose if the stop-loss is hit. Values above `InpMaxRiskPerTradePct` (10 %) are refused. Both `.` and `,` are accepted as the decimal separator.
- **Lots** shows the volume Risk Desk would send now: risk money ÷ (loss per lot from entry to SL + commission per lot), rounded **down** to the broker's volume step. It updates while you drag a line and while the price moves. `—` means there is no valid line yet. A red value means the minimum lot would risk more than your Risk % (see `InpAllowMinLotOverRisk`).
- The **SL label** on the chart shows the same numbers: `SL  −€123.45 (1.00 %) · 0.42 lot · 200 pts`.

## Market orders

| Button | What it does |
|---|---|
| **Add Line** | Draws the red **SL line** (and the green **TP line**, if `InpManualTpLine` is on) at a distance from the price. Drag the SL line to your stop. It replaces pending-order lines. If market lines are already there, nothing moves and the status says so. |
| **Delete Line** | Removes Risk Desk's planning lines. Placed orders are not touched. |
| **Buy** | Opens a buy at the Ask with the computed lot, the SL from the line and the TP from the TP mode. It needs the SL **below** the Bid (and a TP above it). |
| **Sell** | Opens a sell at the Bid. It needs the SL **above** the Ask (and a TP below it). |

The side your SL makes impossible is dimmed (`InpDimInvalidSide`); clicking it explains why. After a successful order, the lines are removed (unless `InpKeepLinesAfterTrade`), the status shows the ticket, lots and risk, and a screenshot is saved (`InpAutoScreenshot`).

Before sending, Risk Desk checks the terminal and account permissions, the broker's minimum stop distance, the margin, the per-trade cap and the total open-risk cap. If a check fails, nothing is sent and the status bar says why.

**Take profit** depends on the TP mode: none, automatic at `InpTpRR` × the SL distance (default 1.0), or the green TP line ([configuration.md](configuration.md#take-profit)).

## Pending orders

| Button | What it does |
|---|---|
| **Add Pend Line** | Draws a white **entry line**, a red SL line (and a green TP line in manual TP mode). It replaces market lines. |
| **Pending Info** | Shows the order type the lines imply: entry above the Ask with the SL below it = *Buy Stop*; entry below the Ask with the SL below it = *Buy Limit*; and the mirror cases for *Sell Stop* and *Sell Limit*. An invalid layout shows the reason, e.g. "Entry at market – use Buy". |
| **Set Pending** | Places exactly the order shown in Pending Info. The lot is computed from the entry–SL distance. A pending order closer to the price than the broker's stops level is refused, with the distance and the price to move to. Expiry: `InpPendingExpiryHours` (0 = good till cancelled). |
| **Del Pending** | Deletes the pending orders on the chart's symbol: **all of them** by default, including orders placed by hand or by other EAs (`InpScopeChartOps`). |

**Placed pending orders** are drawn with their own lines (green entry, red SL and TP by default; `InpShowPendingOverlay`). Drag them to change the order:

- dragging the **entry** line moves the whole order (SL and TP move by the same distance);
- dragging the **SL** or **TP** line changes only that level;
- a move that is invalid or would exceed a risk cap is refused, and the line snaps back;
- deleting an overlay line never deletes the order; it is drawn again.

## Managing open trades

| Button | What it does | Scope (default) |
|---|---|---|
| **Risk Free** | Moves the SL of every position that is far enough in profit to its open price plus the spread and commission (`InpRiskFreeMode`, `InpRiskFreeExtraPoints`). Positions without enough profit are skipped with a reason. The SL is never moved against the trade, and the TP is kept. | all positions on the chart symbol |
| **Half Close** | Closes `InpPartialClosePct` (50 %) of each position, rounded to the broker's volume grid. A position that cannot be split (e.g. the minimum lot) is skipped and reported (`InpPartialIndivisible`). | all positions on the chart symbol |
| **Chart Close** | Closes every position on the chart symbol. Pending orders are not touched. | all positions on the chart symbol |
| **Full Close** | Closes every position on **every symbol** of the account, after a confirmation (`InpConfirmFullClose`). Shows progress and a summary. Pending orders are deleted too only with `InpFullCloseAlsoPending`. | all positions on the account |

To limit these buttons to Risk Desk's own trades, set `InpScopeChartOps` and `InpScopeFullClose` to the *RiskDesk trades* options. Confirmations for Buy/Sell/Set Pending, Half Close and Chart Close can be switched on (`InpConfirm…`).

## Status bar

Every click ends with a message:

- **green**: done, e.g. `Buy 0.50 EURUSD @1.10012 · risk $100.00 (1.00 %) · #123456`;
- **amber**: partly done or skipped, e.g. `Risk-free: 2 moved, 1 not enough profit`;
- **red**: refused or failed, with the reason and, where relevant, the broker's error text.

The same text goes to the terminal's **Experts** tab and, by default, to a daily log file in `Files/RiskDesk/Logs/`. When idle, the status bar shows the open risk of Risk Desk's trades (`Open risk 3.20 % / 10 %`, amber above 75 % of the cap) or the most important warning, such as "Algo/AutoTrading is off in the terminal toolbar".

**Open risk** counts only trades with Risk Desk's magic number (`InpMagic`), on all symbols. A position whose SL is at break-even or better counts as 0. A Risk Desk position **without** an SL blocks new trades, because the total risk can then not be known.

## Other features

- **Spread**: the current spread in points or pips (`InpSpreadUnit`), with an optional warning level.
- **Candle time**: a countdown to the close of the current candle, next to the price; red near the close and while the market is closed (`InpShowCandleTime`).
- **Closed-trade objects**: by default Risk Desk removes the arrows and lines MetaTrader draws for closed trades on the chart (`InpClosedTradeObjects`). Your own drawings are never touched.
- **Screenshots**: after each successful trade action, and with the camera button, a PNG is saved to `Files/RiskDesk/Screenshots/`. The file name contains your account number.
- **Cent accounts**: amounts are also shown in the major unit, e.g. `-1,000.00 USC (-$10.00)` (`InpCentMode`).

## Changing timeframe or symbol

- Changing the **timeframe** keeps the panel, the lines and the Risk %.
- Changing the **symbol** removes the planning lines, because their prices belong to the old symbol. The panel settings are kept.
- **Removing** Risk Desk from the chart deletes all its objects. Open trades and pending orders stay as they are.
