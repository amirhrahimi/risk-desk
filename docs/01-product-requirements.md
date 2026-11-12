# 01 — Product Requirements (PRD)

Status: Draft v1.0 · Owner: project owner · Code name: **RiskDesk** (rename freely, see README)

## 1. Purpose

A discretionary trader wants one panel on the chart that turns "where is my stop?" + "how much do I risk?" into a correctly sized order, then manages that order with a few buttons. The freeware tool the owner uses today does this, but it fails silently at two of the owner's three brokers (works at IG, not at IC Markets EU or Dukascopy). RiskDesk reproduces the same workflow and adds the broker-compatibility and diagnostics layer the original lacks.

## 2. Users and context

- One user: a manual trader on Windows using several terminals: IG, IC Markets EU, Dukascopy; both MT4 and MT5.
- Instruments: FX majors and crosses, gold, indices, crypto CFDs. Account currency may be USD or EUR. Cent accounts possible.
- Trading style: draws SL (and optionally TP) on the chart, clicks Buy/Sell or places a pending order, later moves to break-even and scales out.

## 3. Sources

- Original user guide (Persian, 15 sections), translated below as "Orig §NN".
- Original website changelog v2.0.0 / v2.0.1, marked "Orig v2.0.x".
- Original input settings dialog (owner's screenshots of v2.0.1, 2026-11-09), marked "Orig input"; exact labels and defaults in `07-settings.md`.
- Requirements marked **[NEW]** are improvements we add on purpose.

## 4. Glossary

| Term | Meaning |
|---|---|
| Risk % | Percentage of the risk base lost if the SL is hit. Default 1.0, max 10. |
| Risk base | Account balance by default (Orig §01 says "total account balance"); configurable to equity. |
| SL line / TP line / Entry line | Horizontal chart lines created by the panel: red / green / white. |
| Market mode / Pending mode | Which line set is on the chart: SL(+TP) for market orders, Entry+SL(+TP) for pending orders. |
| TP mode | How the TP is set, derived from Orig inputs "Trade with TP Line" and "Manual TP Line" (F-17): **No TP**, **Auto R/R** (no TP line; TP = entry ± R/R × SL distance) or **Manual TP line** (green line the user drags). |
| Tool trade | A position or order opened by RiskDesk, identified by its magic number. |
| Chart scope | All positions/orders on the chart's symbol. |
| Open risk | Sum over tool positions (and tool pending orders) of the money lost if every SL is hit. |
| Status bar | Line at the bottom of the panel that reports the outcome of every action. **[NEW]** |

## 5. Feature list

| ID | Feature | Origin | Phase | Priority |
|---|---|---|---|---|
| F-01 | Panel: movable, hide/show, scale, font | Orig v2.0.0, v2.0.1 | 3 | Must |
| F-02 | Risk % input | Orig §01 | 3 | Must |
| F-03 | Lots live display | Orig §02 | 4 | Must |
| F-04 | Add Line (SL red, TP green) | Orig §03 | 4 | Must |
| F-05 | Delete Line | Orig §04 | 4 | Must |
| F-06 | Buy / Sell at market, risk-sized; live price on buttons | Orig §05–06 | 4 | Must |
| F-07 | Add Pend Line (Entry white, SL red, TP green) | Orig §07 | 5 | Must |
| F-08 | Pending Info (auto-detected order type) | Orig §09 | 5 | Must |
| F-09 | Set Pending | Orig §08 | 5 | Must |
| F-10 | Del Pending | Orig §10 | 5 | Must |
| F-11 | Risk Free (move SL to entry, spread-adjusted) | Orig §11 | 6 | Must |
| F-12 | Half Close | Orig §12 | 6 | Must |
| F-13 | Chart Close | Orig §13 | 6 | Must |
| F-14 | Full Close (all symbols) | Orig §14 | 6 | Must |
| F-15 | Spread display | Orig §15 | 3 | Must |
| F-16 | Risk caps: per trade ≤ 10 %, total open tool risk ≤ 10 % | Orig §01 | 4 | Must |
| F-17 | TP modes: No TP, Auto R/R, Manual TP line | Orig §03, §07, v2.0.0, Orig input | 4 | Must |
| F-18 | Money risk shown on the SL line label (own colour and font size) | Orig v2.0.0, Orig input | 4 | Must |
| F-19 | Screenshot after each trade action + manual camera button | Orig v2.0.0, v2.0.1, Orig input | 7 | Should |
| F-20 | Closed trade history objects: keep or remove | Orig v2.0.0, Orig input | 7 | Should |
| F-21 | Candle time: countdown to the close of the current candle | Orig v2.0.0, Orig input | 7 | Should |
| F-22 | Pending order overlay: placed pending orders drawn with own entry/SL/TP colours | Orig v2.0.0, Orig input | 5 | Should |
| F-23 | Persistence across timeframe change and restart | Orig v2.0.1 | 3 | Must |
| F-24 | Cent account support | Orig v2.0.1 | 7 | Should |
| F-25 | Status bar with outcome/reason for every action | [NEW] | 3 | Must |
| F-26 | Broker compatibility layer (all BC rules) | [NEW] | 1–6 | Must |
| F-27 | BrokerProbe diagnostic script | [NEW] | 0 | Must |
| F-28 | Confirmation dialogs for destructive actions | [NEW] | 6 | Should |
| F-29 | Open-risk readout ("Open risk 3.2 % / 10 %") | [NEW] | 4 | Should |
| F-30 | Commission-aware sizing | [NEW] | 4 | Should |
| F-31 | Margin pre-check before sending | [NEW] | 4 | Must |
| F-32 | Daily log file | [NEW] | 1 | Should |
| F-33 | Dim the side (Buy or Sell) that is invalid for the current SL | [NEW] | 4 | Could |
| F-34 | Auto-fit panel size to chart/monitor | Orig input | 3 | Should |

## 6. Detailed requirements

Acceptance criteria (AC) are testable statements. T-xx references point to `08-testing.md`.

### F-01 Panel
Orig: draggable via a move handle above the panel; "Hide" toggle; X/Y position inputs; v2.0.0 font and scale settings; v2.0.1 position persists and hidden state survives timeframe change.
- AC1 Panel appears at `InpPanelX/InpPanelY` on first run; afterwards at the last saved position.
- AC2 Dragging the handle moves the whole panel; chart scrolling is disabled while dragging and restored after.
- AC3 A hide/collapse control reduces the panel to the header; state persists (F-23).
- AC4 If the saved position is outside the visible chart (e.g. smaller window), the panel is clamped back into view. (Fixes the original's "panel not visible" support issue.)
- AC5 `InpScale` (0.40–1.60, Orig input "Shape Size Scale") and Windows DPI scale all pixel sizes; text never overflows its widget at 100–200 % DPI.
- AC6 Font chosen from a preset list (Orig input "Panel Font Preset", default Segoe UI) and size (default 8).

### F-02 Risk %
Orig §01: risk per trade; default 1 %; volume computed from risk and entry–SL distance; maximum input 10 %; tool refuses a trade if total risk of its open trades would exceed 10 %.
- AC1 Default from `InpDefaultRiskPct` (1.0); the last value used on the account is restored on restart.
- AC2 Accepts `.` or `,` as decimal separator.
- AC3 Values ≤ 0 or > `InpMaxRiskPerTradePct` (10) are rejected: field reverts, status bar explains.
- AC4 Changing the value immediately updates Lots and line labels.

### F-03 Lots (live)
Orig §02: live display of the volume about to be traded, from the risk % and the SL on the chart.
- AC1 Market mode: side inferred from the SL line (SL below Bid → buy, above Ask → sell); value updates at least every `InpRefreshMs` and on every line drag.
- AC2 Pending mode: computed from Entry–SL distance.
- AC3 Shows `—` when no lines or when lines are invalid; shown in red with tooltip/status when the computed lot is below the broker minimum.
- AC4 Read-only in v1 (manual override is out of scope, see §8).

### F-04 Add Line
Orig §03: draws a red SL line and a green TP line. Entry = market price at the moment Buy/Sell is clicked. Since v2.0.x whether a TP line is drawn depends on the TP mode (F-17); in the owner's configuration (Auto R/R) only the SL line is drawn.
- AC1 Creates the SL line, and the TP line in Manual TP line mode only, at default offsets around the current price (`05-ui-spec.md` §5) so they are visible without scrolling.
- AC2 Lines are selected and draggable immediately.
- AC4 If pending lines exist, they are replaced by market lines (status message says so). If market lines already exist, nothing moves; status says "Lines already on chart".

### F-05 Delete Line
Orig §04: removes the lines created by Add Line and by Add Pend Line.
- AC1 Removes all RiskDesk lines and their labels; Lots shows `—`.

### F-06 Buy / Sell
Orig §05–06: Buy opens a buy, Sell opens a sell at the current price; if lines are placed wrongly no trade is opened (e.g. SL above price → only Sell works).
- AC1 Buy requires SL below Bid (and TP above, if a TP line exists); Sell requires SL above Ask (and TP below).
- AC2 Volume = risk-based lot (04-risk-engine). Order has exactly the SL/TP from the lines (normalized) or the RR-computed TP.
- AC3 Wrong-side click → no request is sent; red status explains which line is wrong.
- AC4 Buttons show live prices ("Buy 1.10012" / "Sell 1.10000") when `InpShowPricesOnButtons=true`.
- AC5 After success: status green with ticket, lots, money risk and %; lines removed unless `InpKeepLinesAfterTrade=true`; screenshot if enabled.
- AC6 Double-click protection: a second click within `InpClickCooldownMs` is ignored.

### F-07 Add Pend Line
Orig §07: three lines: white = pending entry price, red = SL, green = TP (TP line only in Manual TP line mode, F-17).
- AC1 Creates Entry/SL/TP at default offsets; draggable; replaces market lines if present.
- AC2 Entry uses `InpColorEntry` (Orig "Pending Line Color"); SL/TP use the same colours as market mode ("Stop Line Color", "TP Line Color"); width `InpLineWidth`.

### F-08 Pending Info
Orig §09: shows the pending order type implied by the lines (e.g. white above price and red below white → "Buy Stop").
- AC1 Shows one of: Buy Stop, Buy Limit, Sell Stop, Sell Limit, or a short "Invalid: …" reason. Classification rules in `04-risk-engine.md` §7.
- AC2 Updates live as lines are dragged and as price moves.

### F-09 Set Pending
Orig §08: places the pending order from the three lines and the risk %.
- AC1 Places exactly the type shown in Pending Info, with lot from Entry–SL distance.
- AC2 Distance rules (stops level) enforced before sending; refusal explains the minimum distance in points and price.
- AC3 Expiration policy chosen per BC-08 (GTC when allowed).

### F-10 Del Pending
Orig §10: deletes all pending Limit and Stop orders.
- AC1 Deletes all pending orders on the chart symbol (scope per `InpScopeChartOps`, default: all orders on the symbol, matching the original).
- AC2 Status reports "Deleted n of m".

### F-11 Risk Free
Orig §11: for all trades on this chart that are currently in profit, move SL to entry "taking the spread into account", so the trade becomes risk-free.
- AC1 Only positions in profit enough for the new SL to be valid are modified; others are skipped with a reason.
- AC2 SL never moves against the trade (never loosens).
- AC3 Offset rule per `InpRiskFreeMode` (default: spread + commission, Q1). See OP-09 and 04 §9.
- AC4 Status: "Risk-free: 2 moved, 1 not enough profit, 1 already protected".

### F-12 Half Close
Orig §12: closes half of the volume of every open trade on the chart, in profit or loss.
- AC1 For each position: close `floor(volume × InpPartialClosePct%)` to the volume step; remaining volume must be ≥ min lot.
- AC2 Indivisible positions follow `InpPartialIndivisible` (default Skip) and are reported.

### F-13 Chart Close
Orig §13: closes every open trade on the chart in any state.
- AC1 Closes all positions on the chart symbol (scope setting). Pending orders are not touched.

### F-14 Full Close
Orig §14: closes all open trades on all symbols; the only button that affects all symbols.
- AC1 Closes all positions on the account (scope setting, default all). Confirmation dialog when `InpConfirmFullClose=true`.
- AC2 Progress shown ("Closing 4/9…"), final summary with failures listed.

### F-15 Spread
Orig §15: live spread of the current symbol.
- AC1 Shown in points (default) or pips (`InpSpreadUnit`), refreshed every `InpRefreshMs`.

### F-16 Risk caps
- AC1 New trade refused if its risk % > `InpMaxRiskPerTradePct`.
- AC2 New trade refused if open risk + new risk > `InpMaxTotalRiskPct` of the risk base. Message shows current open risk, new risk and the cap.
- AC3 Open risk counts only tool trades (as the original). Tool positions at break-even or better count as 0. A tool position without SL blocks new trades with a clear message.

### F-17 TP modes
Orig inputs: "Trade with TP Line" (true), "Manual TP Line - It doesn't work if Trade with TP Line is False" (false), "R/R | Only Active When Trade with TP Line is True" (1.0). Behaviour confirmed by the owner's demo test (Q15, ADR-013).

| `InpTradeWithTpLine` | `InpManualTpLine` | TP mode | Add Line / Add Pend Line | Order TP |
|---|---|---|---|---|
| false | ignored | No TP | no TP line | none |
| true | false | Auto R/R | no TP line | entry ± `InpTpRR` × \|entry − SL\| at send time |
| true | true | Manual TP line | green TP line placed at the R/R distance, draggable | TP line price |

- AC1 No TP: no TP line is drawn and orders are sent without TP.
- AC2 Auto R/R: TP = entry ± `InpTpRR` × |entry − SL|, sign by side, normalized to tick size (04 §8); for market orders recomputed from the send price on every retry.
- AC3 Manual TP line: the TP line starts at the R/R distance from the default entry/SL placement. With `InpTpFollowsSl=true` [NEW] it moves with the SL (and Entry) line to keep that R/R until the user drags the TP line itself; from then on it stays where it was dropped. With `false` it never follows, as in the original (D1 in 11). Order TP = line price; TP on the wrong side → refused (04 §6–7).
- AC4 The mode is derived once in `Settings` (`ETpMode`); every line, label and order path reads it from there.

### F-18 Money risk on the SL line
- AC1 SL label: `SL  −€123.45 (1.00 %) · 0.42 lot · 200 pts`. TP label (only where a TP line or preview is drawn): `TP  +€246.90 (R 2.00)`. Entry label (pending): `ENTRY Buy Stop 1.10250`.
- AC2 Currency symbol from account currency; cent accounts per F-24.
- AC3 SL label colour `InpColorSlLoss` (white) and size `InpSlLossFontSize` (10), as Orig inputs "SL Dollar Loss Color / Font Size".

### F-19 Screenshots
- AC1 After each successful trade action (open, pending placed or moved, risk-free, partial/close, delete), when `InpAutoScreenshot=true`, a PNG is saved as `Files/RiskDesk/Screenshots/<login>_<symbol>_<TF>_<yyyy-mm-dd_HH-MM-SS>_<action>_<ticket>.png`.
- AC2 Camera button below the panel saves a manual screenshot with action `manual`.

### F-20 Closed trade history objects
Orig input "Closed Trade History Objects": "Keep closed trade objects" / "Remove closed trade objects" (the only two options; owner uses Remove; Q16).
- AC1 `CTO_REMOVE`: the arrows/lines MetaTrader draws for closed trades are removed from the chart and kept removed while the EA runs. MT5: set the chart's "show trade history" property off (`CHART_SHOW_TRADE_HISTORY`) and delete any remaining terminal-created trade objects. MT4: delete terminal-created closed-trade objects (identify them by name pattern verified on the owner's chart via the object list, Ctrl+B; RiskDesk's own orders are sent with arrow colour `clrNONE` so they create none).
- AC2 `CTO_KEEP`: RiskDesk does not touch them.
- AC3 Never deletes objects that are not trade-history objects (user drawings, other indicators).

### F-21 Candle time
Orig inputs "Candle Time" (on/off) and "Candle Time Font Size" (10). No timeframe inputs exist, so it is a single countdown. Owner's screenshots (Q4): gold text `<-- 02:33:29` (H4) and `<-- 2d 22:32:16` (more than a day left) just right of the current candle at the price level; it counts down and restarts with the next candle; while the market is closed it shows `<-- 00:00` in red, and it was also red at `<-- 00:52` on a short timeframe (threshold: Q20).
- AC1 Shows the time left until the current candle of the chart timeframe closes: `<-- mm:ss` under one hour, `<-- hh:mm:ss` from one hour, `<-- Nd hh:mm:ss` from 24 h. Updated every second, also between ticks, from the estimated server time (05 §6); never negative.
- AC2 Position: right of the current candle at the Bid price; size `InpCandleTimeFontSize`; colour `InpColorCandleTime` (gold), switching to `InpColorCandleTimeWarn` (red) when fewer than `InpCandleTimeWarnSec` (60) seconds are left, which includes `00:00` on a closed market (Q20).

### F-22 Pending order overlay
Orig inputs "Pending Overlay Entry / SL / TP Line Color" (LimeGreen / Red / Red). Orig v2.0.0: "changed style of pending trades and selectable colours". Owner's test (Q18): after Set Pending the original draws the order itself in the overlay colours (entry dash-dot, SL/TP dashed, with captions for the order type and lot, "SL" and "TP"); the lines stay when MetaTrader's own trade levels are switched off, and dragging them changes the order.
- AC1 Every pending order in chart scope (`InpScopeChartOps`) is drawn with RiskDesk lines in the overlay colours: entry, SL, TP, with labels: entry `Buy Stop 0.14 @ 3991.15`, SL `SL −$23.38`, TP `TP +$26.60` [NEW: the original shows no money on placed orders].
- AC2 The lines can be dragged. Dropping one modifies the order (OP-16): moving the entry line moves the whole order (SL and TP shift by the same distance, as in the original); moving the SL or TP line changes only that level. Invalid or over-cap moves are refused with a red status and the line snaps back to the order's current value.
- AC3 The overlay follows the order within one refresh when it is added, modified (also through MetaTrader's own trade levels or another tool), filled or deleted, and disappears with the order. Deleting an overlay line (e.g. with the Delete key) never deletes the order; the line is redrawn.
- AC4 Toggle `InpShowPendingOverlay` (off: nothing is drawn, nothing can be dragged through RiskDesk).

### F-23 Persistence
- AC1 Timeframe change: panel position, hidden state, risk %, line mode and lines are preserved (no flicker, no duplicates).
- AC2 Symbol change: lines are removed (their prices belong to the old symbol); panel state is kept.
- AC3 Terminal restart: panel position, hidden state and risk % restored.

### F-24 Cent accounts
- AC1 Lot sizing works unchanged (all money values are in account currency).
- AC2 With cent mode (auto-detected or forced) labels show the major-unit value too, e.g. `−1,000 USC ($10.00)`.

### F-25 Status bar [NEW]
- AC1 Every command ends with one message: green success, amber partial/skipped, red refusal/failure. Messages are human-readable and include the broker's error text when relevant.
- AC2 When idle, shows open-risk readout (F-29) or the most important warning (e.g. "Algo trading disabled in terminal").

### F-26 Broker compatibility [NEW]
- AC1 All BC rules in `03-broker-compatibility.md` implemented and covered by T-xx tests on the owner's five accounts.

### F-27 BrokerProbe [NEW]
- AC1 A script that writes a complete properties report for the account and a list of symbols to `Files/RiskDesk/probe_<broker>_<platform>_<login>.txt` (format in `08-testing.md` §3).

### F-28 Confirmations [NEW]
- AC1 Full Close confirm by default; Chart Close / Half Close / trades confirm optional.

### F-29 Open-risk readout [NEW]
- AC1 "Open risk x.x % / 10 %" shown in the status bar when idle; amber above 75 % of the cap.

### F-30 Commission-aware sizing [NEW]
- AC1 `InpCommissionPerLot` (round turn, account currency) is added to the loss per lot.

### F-31 Margin pre-check [NEW]
- AC1 Before sending, required margin is checked against free margin minus `InpMarginBufferPct`. Refusal states required vs available and the maximum affordable lot.

### F-32 Log file [NEW]
- AC1 Logs mirror to `Files/RiskDesk/Logs/RiskDesk_<yyyymmdd>.log` when `InpLogToFile=true`.

### F-33 Dim invalid side [NEW]
- AC1 In market mode, the button for the side that the SL makes invalid is drawn greyed (still clickable; click explains why it is refused).

### F-34 Auto-fit panel
Orig input "Auto fit panel size to chart/monitor" (true).
- AC1 When on, the effective scale is reduced automatically so the whole panel fits inside the chart height (and width), on init and on every chart resize; it never grows above `InpScale`.
- AC2 DPI ("monitor") scaling is always applied (05 §1); auto-fit adds the chart-size constraint on top. See Q17.
- AC3 [NEW] (owner, T-24 feedback) With `InpPanelColumns=Auto`, a chart too short for one readable column shows the panel in two columns instead of shrinking it below 85 % of `InpScale`; `One` / `Two` force the layout (05 §1, ADR-023).

## 7. Non-functional requirements

| ID | Requirement |
|---|---|
| NFR-01 | Runs on current stable MT4 and MT5 builds on Windows (also under Wine/macOS if the terminal itself runs). No beta-only features. |
| NFR-02 | UI refresh period `InpRefreshMs` (default 250 ms); click-to-request < 100 ms excluding broker latency. |
| NFR-03 | Idle CPU per chart < 1 %; redraw only when a displayed value changed. |
| NFR-04 | No leaks: all `RD_` objects removed when the EA is removed; nothing left on other charts. |
| NFR-05 | Every trade request/result logged with enough detail to diagnose a broker rejection without a debugger. |
| NFR-06 | Correct on Hi-DPI (100–200 %). |
| NFR-07 | Several charts may run RiskDesk at once; account-wide features (open risk, Full Close) stay consistent. |
| NFR-08 | No network access, no DLLs. |
| NFR-09 | Identical behaviour MT4 vs MT5 except where the platform forces a difference (netting accounts, filling policies), documented in `02-architecture.md` §9. |

## 8. Out of scope (v1)

Automated entries/signals; multiple take-profits or order splitting; trailing stop; hotkeys; manual lot override; MT5 stop-limit orders; mobile terminals; reproducing the original's exact look, name or graphics. Candidates for v1.x are listed in `09-roadmap-and-prompts.md` §11.

## 9. Traceability (original guide → features)

| Orig § | Title | Feature |
|---|---|---|
| 01 | Risk | F-02, F-16 |
| 02 | Lots | F-03 |
| 03 | Add Line | F-04, F-17 |
| 04 | Delete Line | F-05 |
| 05/06 | Buy / Sell | F-06 |
| 07 | Add Pend Line | F-07, F-17 |
| 08 | Set Pending | F-09 |
| 09 | Pending Info | F-08 |
| 10 | Del Pending | F-10 |
| 11 | Risk Free | F-11 |
| 12 | Half Close | F-12 |
| 13 | Chart Close | F-13 |
| 14 | Full Close | F-14 |
| 15 | Spread | F-15 |
| v2.0.0 | TP settings, history objects, candle time, screenshots, font/scale, pending style, $ risk on line | F-17, F-20, F-21, F-19, F-01, F-22, F-18 |
| v2.0.1 | MT5 builds, size/width, fixed position and hidden state, cent accounts, screenshot naming | (not needed), F-01, F-23, F-24, F-19 |
| Orig input | Trade with TP Line, Manual TP Line, R/R, Closed Trade History Objects, Candle Time, SL Dollar Loss, Automatic Screenshot, Panel Font Preset, Font Size, Shape Size Scale, Auto fit panel, X/Y Start, all colours | F-17, F-20, F-21, F-18, F-19, F-01, F-34, F-22, 07-settings |
