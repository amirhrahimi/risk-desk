# 11 — Open Questions and Assumptions

How this file works:
- **Open** questions say how to find the answer (usually a short test with the original tool on a demo account) and which **assumption** Claude Code implements until then, configurable where possible. The owner writes the answer in the `Answer` column.
- Once a question is answered, Claude Code rewrites the answer as a **decision** precise enough to implement, updates the docs named in the row, moves the row to *Answered* and adds a line to the log at the end.
- Details Claude Code had to assume while turning an answer into a decision are listed under *Assumed details*. They need no reply unless they are wrong.

## Open

New questions found during implementation are added here (R12).

| ID | Question | Assumption until answered | Answer |
|---|---|---|---|
| Q20 | At how much time left does the candle countdown turn from gold to red? Your screenshots show red at `00:52` and `00:00`, gold at `02:33:29` and `2d 22:32:16`. Test: on an M5 chart while the market is open, note the colour at about `04:00`, `01:05` and `00:55`. Needed by phase P7 only. | Red when fewer than 60 seconds are left, and at `00:00` (`InpCandleTimeWarnSec=60`, configurable). | |

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

## Log of decisions taken during implementation
(Claude Code appends here: date, question, decision, reason.)

- 2026-11-09 · Original settings dialog received (owner screenshots, v2.0.1). Adopted: TP inputs "Trade with TP Line" / "Manual TP Line" / "R/R" (default 1.0); "Closed Trade History Objects" (replaces our history overlay); single candle-time countdown with font size; SL money-label colour and font size; font preset (Segoe UI, 8); Shape Size Scale 0.40–1.60; Auto fit panel; pending order overlay colours; all panel colours as defaults (07-settings ★).
- 2026-11-12 · Owner answered Q1–Q17 and Q19 and sent full-width settings screenshots plus chart screenshots. Q15: the "Manual TP Line" and "R/R" labels had been read inverted from cut-off screenshots; corrected to three TP modes (ADR-013). Q1: new Risk Free mode `RF_SPREAD_COMMISSION` (default, V-23). Q4: candle time `<-- mm:ss`, server-time driven. Q14: Nasdaq 100 replaces a duplicated XAUUSD.
- 2026-11-12 · Q18 answered by the owner's colour test: placed pending orders are drawn by RiskDesk in the overlay colours and can be dragged to modify the order (ADR-014, OP-16, G-08, T-39). D1 changed on purpose (`InpTpFollowsSl`). D3 confirmed; candle time gold while counting. Pending entry planning line drawn dash-dot like the original.
- 2026-11-12 · Owner confirmed D2 (no TP preview in Auto R/R mode; `InpShowRRPreview` removed), D4 (entry drag moves the whole order) and D5. D6 replaced by Q20 after a screenshot showed red at `00:52`; assumed threshold 60 s (`InpCandleTimeWarnSec`, `InpColorCandleTimeWarn`). Assumed-detail IDs renamed A→D.
