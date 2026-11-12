# 11 — Open Questions and Assumptions

How this file works:
- **Open** questions say how to find the answer (usually a short test with the original tool on a demo account) and which **assumption** Claude Code implements until then, configurable where possible. The owner writes the answer in the `Answer` column.
- Once a question is answered, Claude Code rewrites the answer as a **decision** precise enough to implement, updates the docs named in the row, moves the row to *Answered* and adds a line to the log in `history/implementation-log.md`.
- Details Claude Code had to assume while turning an answer into a decision are listed under *Assumed details*. They need no reply unless they are wrong.

## Open

New questions found during implementation are added here (R12).

| ID | Question | Assumption until answered | Answer |
|---|---|---|---|
| – | (none open) | | |

## Answered

| ID | Topic | Decision | Docs updated |
|---|---|---|---|
| Q1 | Risk Free target | Buy: SL = open + current spread + commission distance. Sell: SL = open − current spread − commission distance. The commission distance is the price move whose money value for the position's volume equals `InpCommissionPerLot` × volume (round turn, the same number used for sizing). Swap is ignored. New mode `RF_SPREAD_COMMISSION`, the default; with no commission (e.g. IG) it equals `RF_SPREAD`. | 01 F-11, 04 §9 + V-23, 07 |
| Q2 | Scope of the chart buttons | Risk Free, Half Close, Chart Close and Del Pending act on every position/order of the chart symbol, including manual trades and other EAs' trades (`SCOPE_ALL_ON_SYMBOL`). Full Close closes every position on every symbol (`SCOPE_ALL_ACCOUNT`). | – (already so) |
| Q3 | Full Close and pending orders | Full Close closes positions only; pending orders stay (`InpFullCloseAlsoPending=false`). | – |
| Q4 | Candle time | One countdown to the close of the current candle of the chart timeframe, right of the current candle at the Bid price, size `InpCandleTimeFontSize`: `<-- mm:ss` under one hour, `<-- hh:mm:ss` from one hour, `<-- Nd hh:mm:ss` from 24 h, in gold, red near the close (threshold: Q20). It restarts with the next candle and shows a red `<-- 00:00` while the market is closed. Driven by the estimated server time, so it keeps running between ticks. | 01 F-21, 05 §6, 07, 08 T-33 |
| Q5 | Lines after a trade | Removed after a successful Buy, Sell or Set Pending (`InpKeepLinesAfterTrade=false`). | – |
| Q6 | Risk base | Account balance (`RISKBASE_BALANCE`). | – |
| Q7 | Product name | "RiskDesk"; chart object prefix `RD_`. | – |
| Q8 | Confirmation dialogs | Full Close only. | – |
| Q9 | Lots field | Read-only; no manual lot override. | – |
| Q10 | Account details per broker | Read from the BrokerProbe reports in `broker-profiles/` (phase P0). Commission per lot is entered per terminal in `InpCommissionPerLot`. | – |
| Q11 | Half Close on a position that cannot be halved | Skip it and report it (`INDIV_SKIP`). | – |
| Q12 | Trade history | The original's input "Closed Trade History Objects" (keep or remove MetaTrader's closed-trade arrows) replaces our history-overlay idea; a RiskDesk-drawn history overlay stays in the backlog. The owner uses "Remove". | – |
| Q13 | UI language | English only. | – |
| Q14 | Test symbols | EURUSD, USDJPY, EURGBP, XAUUSD, US30, Nasdaq 100, BTCUSD. Each broker's exact symbol names come from its BrokerProbe report and are never hard-coded (R3). | 08 §4 |
| Q15 | TP modes | Three modes from "Trade with TP Line" and "Manual TP Line" (table below). Our first spec had both labels inverted because they were cut off in the first screenshots; the owner's full screenshots and demo test corrected them. Nothing is drawn for the TP in Auto R/R mode. One deliberate improvement: the manual TP line keeps its R/R distance when the SL moves, until the user drags it (D1). | 01 F-04/F-07/F-17, 04 §8, 05 §5, 06, 07, 08 T-08, ADR-013 |
| Q16 | "Closed Trade History Objects" options | Exactly two: "Keep closed trade objects" and "Remove closed trade objects" (owner's screenshot of the dropdown). | 01 F-20, 07 |
| Q17 | Auto fit panel | Shrinks the panel to fit the chart window; never grows above "Shape Size Scale". | – |
| Q18 | Placed pending orders | The original draws placed pending orders itself in the three "Pending Overlay" colours, and dragging those lines changes the order (test below). RiskDesk does the same: dropping an overlay line modifies the order (OP-16) after checking order type, side, stops levels and risk caps; moving the entry line moves the whole order (D4); a refused move snaps the line back. RiskDesk's labels also show the money at SL and TP [NEW]. | CLAUDE.md §1, 01 F-19/F-22, 02, 04 §5 + V-24, 05 §5–6, 06 OP-16/G-08, 07, 08 T-39, 09 P2/P5, ADR-014 |
| Q19 | Inputs beyond the known list | None. The original's list starts at "Trade with TP Line" and ends at "Color Button Border". Magic number, slippage, risk caps and every other input without an "Orig label" in 07-settings are RiskDesk additions. | 07 |
| Q20 | Candle countdown red threshold | Red when the time left is at most 10 % of the candle's length (owner: "when 10 % and less of the candle time remains"), and always at `00:00` (closed market). The length is the chart period (MN1: the current month), so at 10 %: M1 the last 6 s, M5 30 s, H1 6 min, H4 24 min, D1 2 h 24 min. Input `InpCandleTimeWarnPct` = 10 (0–100, 0 = red only at `00:00`) replaces the assumed `InpCandleTimeWarnSec` = 60. The earlier screenshot red at `00:52` fits a candle of at least 520 s (M10 or longer). | 01 F-21, 05 §6, 07, 08 T-33 |
| Q21 | Dukascopy MT4 index tick values | Keep BC-05 as written: when the MT4 tick value and contract size × conversion rate differ by more than 5 %, value the trade with the larger loss and show the amber "Tick value mismatch" note. On Dukascopy MT4 index CFDs (tick value reported in the index currency) lots are therefore 11–38 % smaller than the risk % allows; no automatic correction. MT5 is not affected (OrderCalcProfit). | – (03 §3 already says so) |
| Q22 | Requotes with a small slippage (IG MT4 gold) | Kept as is (option a). `InpSlippagePoints` stays one value (20) for every symbol and broker; no broker- or symbol-specific settings or defaults, no spread-based deviation. A requote that outlasts the retries ends red, "Buy failed: Requote (4 attempts)", and nothing opens; the owner finds that fine. | 03 §3, 07 |

**Q15: TP modes** (owner's demo test, 2026-11-12)

| Trade with TP Line | Manual TP Line | TP mode | Add Line / Add Pend Line | TP of the order |
|---|---|---|---|---|
| false | ignored | No TP | No TP line | None |
| true | false | Auto R/R | No TP line | entry ± R/R × \|entry − SL\|, computed when the order is sent |
| true | true | Manual TP line | Green TP line placed at the R/R distance; the user can drag it | The TP line's price |

**Q18: test result** (owner, 2026-11-12, with the overlay colours set to Yellow / Blue / Magenta)
- Add Pend Line: white dash-dot entry line, red SL line labelled `-$23.38`, green TP line labelled `+$26.60`. The overlay colours are not used for these planning lines.
- Set Pending: yellow dash-dot entry line captioned with the order type, lot and price, blue dashed "SL" line, magenta dashed "TP" line. So the original draws placed orders itself.
- With "Show trade levels" switched off the lines stay, and dragging them changes the pending order's SL/TP.

## Assumed details

IDs start with D so they don't clash with the test accounts A1–A7 in 08-testing.

| ID | Detail | Status | Decision |
|---|---|---|---|
| D1 (Q15) | Does the manual TP line follow the SL when the SL is dragged? | Changed on purpose | The original does not. RiskDesk does by default until the TP line itself is dragged ([NEW] `InpTpFollowsSl=true`; false = the original's behaviour). The owner suggested it. |
| D2 (Q15) | Is anything drawn for the TP in Auto R/R mode? | Confirmed | Nothing. The TP line exists only when "Trade with TP Line" and "Manual TP Line" are both on. The dotted preview RiskDesk had added was removed. |
| D3 (Q4) | Countdown format with one hour or more left | Confirmed | `<-- hh:mm:ss`, and `<-- Nd hh:mm:ss` from 24 h (owner's screenshots). |
| D4 (Q18) | Can the entry line of a placed order be dragged? | Confirmed | Yes, and it moves the whole order: SL and TP shift by the same distance. A move that would change the order type (e.g. a Buy Stop dragged below Ask) is refused. |
| D5 (Q18) | Dragging the SL farther raises the order's risk, because MetaTrader cannot change the lot of a placed order. | Confirmed | Allowed up to the caps (`InpMaxRiskPerTradePct`, total open risk); amber note when above the panel's Risk %; refused and snapped back above a cap. |
| D6 (Q4) | When does the countdown turn red? | Replaced by Q20 | "Only at `00:00`" was confirmed, but a later screenshot shows red at `00:52` with the market open, so the rule includes a threshold. |
| D7 (F-16) | A RiskDesk pending order whose SL was removed (e.g. in MetaTrader) | Assumed (P1) | Blocks new trades like a RiskDesk position without SL, while pending orders count towards total risk (`InpIncludePendingInTotalRisk=true`): "Pending order #77 (EURUSD) has no SL - total risk cannot be computed". |
| D8 (F-02) | Risk % with more than 2 decimals | Assumed (P1) | Rounded to the 2 decimals the field shows before it is checked, so the risk used is the risk displayed: `0.333` → 0.33, `10.001` → 10.00 (accepted), `0.001` → 0 (rejected). A trailing `%` and a leading `+` are accepted. |
| D9 (BC-07) | Freeze level 0 | Assumed (P1) | Never blocks a modify, close or delete. Read literally, "not allowed while Bid − SL ≤ F" with F = 0 would block closing a position whose SL price has just been touched, which would stop the user from closing it by hand. |
| D10 (04 §9) | `RF_COMMISSION` when commission + swap is a net credit | Assumed (P1) | The booked costs are passed as a positive cost; a net credit counts as 0, so this mode never sets the SL on the losing side of the open price. |
| D11 (OP-09) | Several Risk Free skip reasons at once | Assumed (P1) | The first one in this order is reported: not in profit, already protected, not enough profit (with the price needed), frozen. |
| D12 (R7, BC-10) | Netting account: the SL cannot be attached to a position that a new order merged into | Assumed (P2) | Close the volume this order added, not the whole position (the rest was the user's); if the remaining position then has no SL, say so in red: "the remaining 0.30 lot has NO SL - set it now". |
| D13 (BC-11) | MT5 symbol whose `SYMBOL_ORDER_MODE` lacks market/limit/stop orders or TP | Assumed (P2) | Refuse with "Broker does not accept <type> orders on <symbol>" / "Broker does not accept TP on <symbol> - trade without a TP line". Sending without the TP would silently change the trade. |
| D14 (09 P2) | GatewaySmoke volume | Assumed (P2) | 2 × min lot when its risk at SL is within `InpMaxRiskPct` (1 % of balance), else the min lot and the partial-close step is skipped. With exactly the min lot a partial close is never possible. |
| D15 (F-01) | The owner edits X Start / Y Start after a position was saved | Assumed (P3) | The edited inputs win: `ui.ini` remembers the X/Y Start it was saved with, and when they differ the panel goes to the new X/Y Start (otherwise the inputs would silently do nothing after the first drag). |
| D16 (07) | "Start with the panel hidden" | Assumed (P3) | true: hidden at every start (attach or terminal start), whatever was saved; false: the saved hidden flag (shown on the very first start). |
| D17 (02 §8) | `ui.ini` is one file for every chart and account | Assumed (P3) | As specified: with RiskDesk on several charts, the panel position/hidden state saved last applies to all after a restart. A chart writes `ui.ini` only when its own panel was moved or hidden, so closing the terminal does not overwrite another chart's newer position. |
| D18 (05 §4) | Spread in pips | Assumed (P3) | 1 pip = 10 points on 3- and 5-digit symbols, else 1 point (`InpSpreadUnit=SPREAD_PIPS`); shown with one decimal on 3/5-digit symbols. |
| D19 (BC-15) | Which buttons a restricted symbol trade mode disables | Assumed (P3) | Disabled: every button except Add Line, Delete Line, Add Pend Line, Full Close (acts on all symbols) and the camera. Close-only: Buy, Sell, Set Pending. Long-only: Sell. Short-only: Buy. Disabled buttons are grey with the reason as tooltip; a click answers red with the same reason. |
| D20 (05 §3) | RiskDesk changes a chart setting | Assumed (P3) | "Chart on foreground" is switched off while RiskDesk runs (otherwise candles cover the panel and, from P4, the SL/TP lines), also when the user switches it on again, and the user's original value is restored when RiskDesk is removed from the chart. Found by the owner on a saved MT4 chart. |
| D21 (05 §5) | Distance of the default lines | Assumed (P4) | At least the stops level + 2 ticks, even when 15 % of the visible range is less, so Add Line never draws a line that Buy would refuse as "too close". A clamp into view that would cross the price is not applied. |
| D22 (F-06 AC5) | Risk in the status after a fill | Assumed (P4) | The risk of the position as filled: at the fill price and the SL on the server, not the preview's (they differ by the slippage). |
| D23 (BC-10) | `InpNettingAllowOpposite=true`: what an opposite order does | Assumed (P4) | Lots ≤ the position: the position is reduced (or closed) by that volume and keeps its own SL/TP. Lots > the position: the position is closed, then the rest is opened on the new side with the lines' SL/TP (two requests, the confirmation says so). The lots are still sized from the SL line. |
| D24 (F-03 AC3) | What Lots shows below the minimum lot | Assumed (P4) | The computed lot and the minimum in red, e.g. `0.83 < 1`; the tooltip and the SL label give the risk of the minimum lot. |
| D25 (F-06 AC6, T-25) | Click cooldown with slow servers | Assumed (P4) | Counted from the click and again from the end of the command: a second click made while an order was being sent is ignored. |
| D26 (OP-14) | Time in screenshot names | Assumed (P4) | The computer's local time (the time the user sees), not server time. |
| D27 (BC-10, OP-07) | Netting account: Set Pending while the symbol has an open position | Assumed (P5) | BC-10 applies to pending orders too, for the moment they fill. Same direction: the order merges with the position and its SL/TP replace the position's, so the caps are checked for the merged position (averaged open at the order's entry, the order's SL) and a confirmation is always asked. Opposite direction: refused ("when it fills, a Sell Limit would reduce or reverse the open buy 0.30 lot position"), unless `InpNettingAllowOpposite`; then a confirmation. |
| D28 (OP-16) | Dragging a line of a placed order that has no SL (e.g. placed by hand) | Assumed (P5) | Not moved: "not moved: it has no SL, so its risk cannot be checked - set an SL in MetaTrader first". The order is still drawn. |
| D29 (OP-16, 04 §5) | A move that does not raise the order's risk | Assumed (P5) | Always allowed, without the caps. An order above a cap (e.g. after the balance fell, or a manual order) can be tightened, and moving the entry line (SL and TP move by the same distance) needs no budget check. A move that raises the risk is checked as 04 §5 says. |
| D30 (OP-08, OP-14) | Del Pending: an order that is gone between listing and deleting; screenshot ticket | Assumed (P5) | It is counted as "already gone (filled or deleted elsewhere)" and the status turns amber, so a fill is not missed. The screenshot name carries the deleted order's ticket when one order was deleted, else 0. |
| D31 (F-22) | Overlay labels and which orders are drawn | Assumed (P5) | Each label in the colour of its overlay line (as the original's captions, Q18), in the planning labels' font and size and placed like them (05 §5, ADR-024). MT5 stop-limit orders are not drawn (RiskDesk does not modify them) but Del Pending deletes them (06 OP-08). |
| D32 (F-31, OP-07) | Margin of a pending order | Assumed (P5) | Checked at the entry price as for a market order ("as OP-03"), with `InpReduceToMargin`, although most servers reserve the margin only when the order fills. |
