# 05 — UI Specification

The UI is built only from standard chart objects (`OBJ_RECTANGLE_LABEL`, `OBJ_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`, `OBJ_HLINE`, `OBJ_TEXT`) so it is identical on MT4 and MT5 (ADR-007). The layout follows the original's workflow (same buttons, same order) with our own name, title and styling.

## 1. Panel layout (scale 1.0, 96 DPI)

```
               ✥                      RD_P_HANDLE   (drag to move)
 ┌────────────────────────────┐
 │ RiskDesk               [–] │      RD_P_TITLE, RD_P_HIDE (collapse)
 │ Risk %  [ 1.00           ] │      RD_E_RISK   editable
 │ Lots    [ 0.50           ] │      RD_E_LOTS   read-only, red when below min lot
 │ [        Add Line        ] │      RD_B_ADDLINE
 │ [       Delete Line      ] │      RD_B_DELLINE
 │ [      Buy 1.10012       ] │      RD_B_BUY    green, live Ask
 │ [      Sell 1.10000      ] │      RD_B_SELL   red, live Bid
 │ [      Add Pend Line     ] │      RD_B_ADDPEND
 │ [       Set Pending      ] │      RD_B_SETPEND
 │        Pending Info        │      label
 │ [ Buy Stop · 0.35 lot    ] │      RD_E_PINFO  read-only
 │ [       Del Pending      ] │      RD_B_DELPEND
 │ [        Risk Free       ] │      RD_B_RISKFREE
 │ [       Half Close       ] │      RD_B_HALF
 │ [       Chart Close      ] │      RD_B_CHARTCLOSE
 │ [       Full Close       ] │      RD_B_FULLCLOSE
 │ Spread: 7 pts              │      RD_L_SPREAD
 │ ✔ Buy 0.50 EURUSD #123456  │      RD_L_STATUS1..3  (status bar, up to 3 lines)
 │ risk $100.00 (1.00 %)      │
 └────────────────────────────┘
               📷                     RD_B_SHOT  (manual screenshot)
```

### Geometry (before scaling)
| Item | Value |
|---|---|
| Panel width | 160 px |
| Outer padding | 8 px |
| Label column (Risk %, Lots) | 48 px |
| Field height / button height | 22 px / 24 px |
| Vertical gap | 5 px |
| Title font | font from `InpFontPreset`, semibold variant where one exists (e.g. "Segoe UI Semibold"), body size + 3 |
| Body font | font from `InpFontPreset` (default Segoe UI), `InpFontSize` (default 8) |
| Status font | body font, size − 1 |
| Panel border / button border | 1 px, `InpColorSystemBorder` / `InpColorButtonBorder` (`OBJPROP_BORDER_COLOR`) |

Layout computes every rectangle from a running y-cursor; nothing is positioned with hand-typed absolute coordinates.

### Two columns (ADR-023, [NEW] `InpPanelColumns`)
For short charts (small window, low resolution, high Windows scaling) the panel can be shown in two columns, so it can stay larger than one tall column could:

```
                         ✥
 ┌──────────────────────────────────────────────────────┐
 │ RiskDesk                                         [–] │
 │ Risk %  [ 1.00           ]        Pending Info       │
 │ Lots    [ 0.50           ]  [ Buy Stop · 0.35 lot  ] │
 │ [        Add Line        ]  [      Del Pending     ] │
 │ [       Delete Line      ]  [       Risk Free      ] │
 │ [      Buy 1.10012       ]  [      Half Close      ] │
 │ [      Sell 1.10000      ]  [      Chart Close     ] │
 │ [      Add Pend Line     ]  [      Full Close      ] │
 │ [       Set Pending      ]                           │
 │ Spread: 7 pts                                        │
 │ ✔ Buy 0.50 EURUSD #123456 · risk $100.00 (1.00 %)    │
 └──────────────────────────────────────────────────────┘
                         📷
```
- Width 2 × 160 − 8 = 312 px before scaling: two columns of 144 px, 8 px apart. The title row and the status area span both columns (fewer status lines wrap); the handle and the camera stay centred.
- The right column uses the left column's rows, so the rows stay level at every scale. Set Pending's neighbour is empty.
- `InpPanelColumns`: `Auto` (default), `One`, `Two`. Auto with auto-fit on: one column, unless one column would have to shrink below **85 %** of `InpScale` to fit the chart; then two columns if they reach a larger scale (or, both at 0.40, one column is cut off and two columns fit the width). Auto with auto-fit off: two columns when one column is taller than the chart and two columns fit its width. Decided again on every chart resize, together with the scale.
- A hidden panel keeps its width, so the show/hide button does not move.

### Scaling
- `scale = InpScale` (0.40–1.60); with `InpAutoFitPanel` (F-34): `scale = min(InpScale, fitScale)` where `fitScale` is the largest scale at which the full panel (handle to camera button) fits inside `CHART_HEIGHT_IN_PIXELS` and `CHART_WIDTH_IN_PIXELS` minus 10 px margins, in the columns chosen above. Recompute on init and on `CHARTEVENT_CHART_CHANGE` (debounced 300 ms).
- `pxScale = scale × TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96`. Multiply every pixel distance/size by `pxScale`.
- Font point sizes are multiplied by `scale` only (the terminal already applies DPI to fonts); minimum 6 pt.
- Verify with T-24 at 100 %, 150 %, 200 % Windows scaling and T-37 (small chart window); adjust if text overflows (use `TextSetFont` + `TextGetSize` to measure).
- Rows are never shorter than one line of their text, and the caption column never narrower than "Risk %": below about scale 0.7 the fonts stay at 6 pt while the geometry keeps shrinking, so those rows grow and push the rows below them down; auto-fit uses the resulting height (ADR-021).
- Button texts and the read-only fields (Lots, Pending Info) get a smaller font, down to 6 pt, rather than a cut text (ADR-023). The status bar never starts a line with a unit (`%`, `pts`, `pips`, `lot`, `lots`).

## 2. Default theme (all overridable in 07-settings)

Defaults mirror the owner's current configuration of the original (07-settings "Colors").

| Element | Input | Default |
|---|---|---|
| Background | `InpColorBg` | `clrBlack` |
| Panel border / button border | `InpColorSystemBorder` / `InpColorButtonBorder` | `C'136,136,136'` |
| Text (buttons, fields) | `InpColorText` | `clrWhite` |
| Title accent (second word) | – | `C'150,120,255'` |
| Add Line / Add Pend Line | `InpColorAddLine` / `InpColorAddPendLine` | `C'44,64,97'` |
| Delete Line / Del Pending | `InpColorDeleteLine` / `InpColorDelPending` | `C'62,0,106'` |
| Buy / Sell | `InpColorBuy` / `InpColorSell` | `C'39,130,73'` / `C'192,55,42'` |
| Set Pending (black text) | `InpColorSetPending` | `C'211,162,31'` |
| "Pending Info" caption | `InpColorPendingInfo` | `clrGold` |
| Risk Free | `InpColorRiskFree` | `C'116,116,116'` |
| Half / Chart / Full Close | `InpColorHalfClose` / `InpColorChartClose` / `InpColorFullClose` | `C'0,94,94'` |
| Spread text | `InpColorSpread` | `clrWhite` |
| Fields background / border | – | `clrBlack` / `C'200,200,200'` |
| Status ok / warn / error | – | `C'76,175,80'` / `C'255,179,0'` / `C'239,83,80'` |

Button states: **normal**; **dim** (40 % towards background, F-33 invalid side); **disabled** (grey, tooltip says why, e.g. "Symbol is close-only"); **working** (dark grey, text "…") while the command runs.

Every button has an `OBJPROP_TOOLTIP` that says exactly what it affects, e.g. "Close 50 % of every position on EURUSD".

## 3. Panel behaviour

| Behaviour | Spec |
|---|---|
| Move | Mouse-down on the handle (hit test with `CHARTEVENT_MOUSE_MOVE` x/y and left-button bit in `sparam`) starts a drag; disable `CHART_MOUSE_SCROLL` while dragging; move all panel objects by the delta; on release re-enable scroll and save position (debounced). |
| Clamp | On init and on `CHARTEVENT_CHART_CHANGE`: keep `x ∈ [0, chartWidth − panelWidth]`, `y ∈ [0, chartHeight − panelHeight]` (`CHART_WIDTH_IN_PIXELS`, `CHART_HEIGHT_IN_PIXELS`; panel height = handle to camera, or to the title row when hidden), so the whole panel stays in view (T-37). The saved position is the user's; only the shown one is clamped, so the panel moves back when the window grows. Changed from `chartHeight − 40` in P3 (ADR-021). While MetaTrader's One-Click Trading panel is shown (`CHART_SHOW_ONE_CLICK`), the panel also keeps out of the top-left 215 × 90 px (× DPI / 96) that it covers: below it if the panel fits there, else to its right. |
| Hide | `[–]` collapses to title + handle; `[+]` restores. Lines stay on the chart. Persisted. |
| Z-order | Panel objects `OBJPROP_BACK=false`, `OBJPROP_ZORDER` high (buttons above background), `OBJPROP_HIDDEN=true`, not selectable. "Chart on foreground" (`CHART_FOREGROUND`) would still draw the candles above them: RiskDesk switches it off while it runs and restores the user's value when it is removed (ADR-021, D20). |
| Redraw | Widgets keep their last rendered text/colour and only call `ObjectSet*` when something changed; one `ChartRedraw()` per refresh cycle at most. |

## 4. Fields

| Field | Behaviour |
|---|---|
| Risk % | On `CHARTEVENT_OBJECT_ENDEDIT`: parse (accept `,`), validate `0 < x ≤ InpMaxRiskPerTradePct`, display with 2 decimals, persist per account. Invalid → revert, red status. |
| Lots | Read-only. Market mode: preview for the side implied by SL (04 §6). Pending mode: lots for the classified order. `—` when not computable. Red text + status hint when below min lot. |
| Pending Info | Read-only. `Buy Stop · 0.35 lot` or `Invalid: TP on wrong side`. Empty when not in pending mode. |
| Spread | `Spread: 7 pts` (or pips with `InpSpreadUnit`). Amber when > `InpSpreadWarnPts` (0 = off). |
| Status bar | Up to 3 wrapped lines; colour by severity; full text also in the tooltip and the log. Holds `InpStatusHoldSec` (8 s) then shows the idle readout: `Open risk 3.20 % / 10 %` (amber above 75 % of cap) or the highest-priority warning (trading disabled, stale quotes, tick value mismatch). |

## 5. Trade lines

| Line | Name | Colour input (default) | Style | Selectable |
|---|---|---|---|---|
| SL (market and pending mode) | `RD_LN_SL` | `InpColorSL` (`clrRed`) | solid, `InpLineWidth` (2) | yes |
| TP (market and pending mode) | `RD_LN_TP` | `InpColorTP` (`clrLimeGreen`) | solid, `InpLineWidth` | yes |
| Entry (pending mode) | `RD_LN_EN` | `InpColorEntry` (`clrWhite`) | dash-dot, width 1 (as the original) | yes |
| Pending order overlay (F-22) | `RD_PO_<ticket>_EN/SL/TP` | `InpColorPendOverlayEntry/SL/TP` (LimeGreen / Red / Red) | entry dash-dot, SL/TP dash, width 1 | yes: dropping it modifies the order (OP-16) |

MetaTrader draws dash/dot styles only at width 1; width > 1 is always solid.

### Default placement
`range = CHART_PRICE_MAX − CHART_PRICE_MIN` of the main window (fallback: 0.5 % of price if 0); `O = InpDefaultOffsetPct / 100 × range` (default 15 %), but at least the stops level + 2 ticks, so a default line is never "too close" (P4, ADR-022).
- **Add Line:** SL = Bid − O. TP line (Manual TP line mode only) = Ask + `InpTpRR` × (Ask − SL).
- **Add Pend Line:** Entry = Ask + O; SL = Entry − 1.5·O. TP line (Manual TP line mode only) = Entry + `InpTpRR` × (Entry − SL).
- Manual TP line with `InpTpFollowsSl=true` [NEW]: whenever the SL (or Entry) line is dropped, the TP line moves to entry ± `InpTpRR` × |entry − SL| (market mode: entry = current Ask/Bid for the side at that moment), until the user drags the TP line itself; after that it stays where it was dropped and its label shows the new R. Recomputed on drops only, never on ticks. `false` = the original's behaviour (never follows).
- No TP line in No TP and Auto R/R modes (F-17).
- Any line that would fall outside the visible range is clamped to 5 % inside the nearest edge, unless the clamp would put it on the wrong side of the price or inside the stops level; then it stays out of view on the correct side. No clamping while the price itself is out of view (chart scrolled back).
- Normalize to tick size (rounded away from the price). Lines are created **selected** so the user can drag at once. A dropped line snaps to the tick grid, so what the user sees is what is sent.
- Whether the user has dragged the TP line (it then stops following) is kept in the TP line's tooltip, so it survives a restart with the line (ADR-022).
- Chart objects are drawn in creation order: after RiskDesk creates a line or label, the panel's objects are created again so the panel stays on top (ADR-022).

### Line labels (F-18)
`OBJ_TEXT` named `RD_LT_*`, anchored `ANCHOR_LEFT_LOWER` at time = open time of the current bar + 3 × `PeriodSeconds()`, price = line price, when the chart has its right margin (`CHART_SHIFT`); without it, anchored `ANCHOR_RIGHT_LOWER` at the current bar so the text stays in view (P4). Where the panel (as shown, handle to camera) would cover a label, the label goes left of the panel, right-aligned on the last bar that keeps it 6 px (× DPI/96) clear; without room on the left it goes right of the panel when it ends before the price scale, else it stays (ADR-024, owner). Re-placed on every refresh, so it follows panel drags, scrolling and zoom. SL label: `InpColorSlLoss` (white), `InpSlLossFontSize` (10). TP/Entry labels: line colour, same size, font of the panel. Updated on drag, on timer and on new bar. MT4 shows `-` for the minus sign (ANSI, ADR-021).

| Label | Format |
|---|---|
| SL | `SL  −$100.00 (1.00 %) · 0.50 lot · 200 pts` |
| TP | `TP  +$200.00 (R 2.00) · 400 pts` |
| Entry | `ENTRY  Buy Stop  1.10250` |
| Invalid | `SL  (invalid: above Bid for a buy)` in amber |
| Below the minimum lot | `SL  min lot 1 risks €60.00 (1.20 %) · 200 pts` in amber; Lots field `0.83 < 1` in red (the computed lot, F-03 AC3) |

### Mode rules
- `LINES_NONE → Add Line → LINES_MARKET`; `→ Add Pend Line → LINES_PENDING`.
- Switching mode replaces the other mode's lines (status says so).
- Add Line/Add Pend Line in the same mode when lines exist: no change, status "Lines already on chart".
- Delete Line → `LINES_NONE`.
- Successful Buy/Sell/Set Pending → `LINES_NONE` unless `InpKeepLinesAfterTrade`.
- If the user deletes a line manually (object list / Delete key), detect it on the next refresh and drop to a consistent mode (e.g. TP deleted → market mode without TP; SL deleted → `LINES_NONE`).

## 6. Optional overlays

### Closed trade objects (F-20)
`InpClosedTradeObjects = CTO_REMOVE`: on init, on every trade event and every 5 s, remove the arrows/lines MetaTrader draws for closed trades on this chart (MT5: `ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, false)` plus deletion of leftover terminal trade objects; MT4: deletion of terminal-created closed-trade objects). Before writing the MT4 matcher, ask the owner for a screenshot of the object list (Ctrl+B) on a chart with closed trades, and match only those name patterns. `CTO_KEEP`: do nothing.

### Pending order overlay (F-22)
For each pending order in chart scope: `OBJ_HLINE` lines `RD_PO_<ticket>_EN/SL/TP` at entry (dash-dot), SL and TP (dash), width 1, overlay colours, selectable and not hidden like the planning lines. Labels `RD_PT_<ticket>_*` (`OBJ_TEXT`) are placed like the line labels in §5: entry `Buy Stop 0.14 @ 3991.15`, SL `SL −$23.38 (0.23 %)`, TP `TP +$26.60 (R 1.14)`. Dropping a line runs OP-16: the entry line moves the whole order (the SL and TP lines follow once the order is modified), the SL or TP line only its own level; a refused move snaps the line back. Rebuilt when the order list changes (compare a hash of tickets + prices each refresh), so moves made with MetaTrader's own trade levels are followed too. Removed with the order. A deleted overlay object is redrawn on the next refresh; deleting it never deletes the order.
P5 details (ADR-025): each label is drawn in its line's colour, in the font and size of the planning labels (D31). A line is moved only when its order's value changed or after a drop, never while the user is dragging it; a price typed in the line's properties dialog counts as a drop, other property changes do not. MT5 stop-limit orders are not drawn. The first refresh after `OnInit` removes objects of orders that went while RiskDesk was not running (or belong to the chart's previous symbol). The entry line's tooltip shows the order's expiry when it has one.

### Candle time (F-21, Q4)
`RD_CT` (an `OBJ_LABEL` placed in pixels since P7, see below), anchored left, placed right of the current candle at the Bid price (moves with price). Text: time left until the current candle closes, `<-- mm:ss` under one hour, `<-- hh:mm:ss` from one hour (`<-- 02:33:29`), `<-- Nd hh:mm:ss` from 24 h (`<-- 2d 22:32:16`). Colour `InpColorCandleTime` (gold); `InpColorCandleTimeWarn` (red) when the time left is at most `InpCandleTimeWarnPct` (10) % of the candle's length (the chart period; MN1: the current month), and always at `00:00` (Q20); size `InpCandleTimeFontSize`. Updated every second on the timer from the estimated server time, so it keeps running between ticks: MT5 `TimeTradeServer()`; MT4 `TimeLocal()` + the server offset measured when the last tick arrived (`Platform/Market.mqh`). Never negative: shows `<-- 00:00` once the candle's time has run out without a new candle (market closed).
P7 details (ADR-027): `RD_CT` is an `OBJ_LABEL` placed in pixels from bar 0 at the Bid (a few pixels right of the candle's half width) and moved every refresh and on every chart change, so the gap to the candle stays a few pixels at every zoom; it is hidden while bar 0 or the Bid is out of view. The time ran out but the symbol is inside its trade session (no tick in the new candle yet) → the candle that runs by the clock is counted down (D40); outside the session → `<-- 00:00` red. No room right of the candle (no chart shift) → left of it, right-anchored, with the arrow after the time, `02:33:29 -->` (D39). While Candle Time is on the timer runs at most 1 s apart (D42). `RD_CT` is hidden and not selectable. Cent accounts (F-24): money everywhere as `-1,000.00 USC (-$10.00)` (D38 for a forced cent mode). Closed-trade objects (F-20): only arrows and trend lines named `#<ticket> …` whose ticket is a closed trade of the chart symbol in the account history are deleted; MT5's "Show trade history" is given back when RiskDesk leaves the chart or the input becomes Keep.

## 7. Messages style guide
- Start with the verb or the outcome: "Buy 0.50 EURUSD opened", "Refused: SL above Bid for a buy".
- Include the numbers the user needs to fix it (distance, minimum, margin).
- Broker text in brackets at the end: `[Unsupported filling mode]`.
- No codes alone; codes go to the log.
