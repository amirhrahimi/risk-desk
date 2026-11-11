# 10 — Architecture Decision Records

Format: Context → Decision → Consequences. Add new ADRs at the end; never rewrite accepted ones (supersede them instead).

## ADR-001 One shared codebase with compile-time platform selection
- **Context:** MQL4 (build 600+) and MQL5 share most of the language (classes, structs, chart objects) but differ in trading, account and history APIs. Two separate code bases drift apart.
- **Decision:** One source tree. Platform-specific code only in `Platform/`, selected with `#ifdef __MQL5__`. Same class names and public methods in both implementations (no virtual interfaces needed).
- **Consequences:** Every feature is written once. Platform files carry the burden of parity; reviewers check both implementations together.

## ADR-002 No MT5 Standard Library (CTrade, Controls)
- **Context:** `CTrade` hides filling-policy handling and retcodes; `Controls/` dialogs differ between MT4 and MT5 and are heavy.
- **Decision:** Own `CTradeGateway` with raw `MqlTradeRequest`/`OrderSend`; own lightweight widgets over chart objects.
- **Consequences:** Full control over BC-06/BC-11/BC-14 and identical UI on both platforms; more code to write and test (GatewaySmoke covers it).

## ADR-003 Money value: OrderCalcProfit on MT5, tick value + cross-check on MT4
- **Context:** Wrong tick values are a common cause of wrong lot sizes on CFDs and non-USD accounts.
- **Decision:** MT5 uses `OrderCalcProfit` (terminal does conversion). MT4 uses tick value, cross-checked against contract size × conversion rate; on mismatch take the more conservative value and warn.
- **Consequences:** Correct lots on cross-currency accounts; occasional conservative under-sizing on MT4 with an explicit warning.

## ADR-004 Lots always rounded down; refuse below min lot by default
- **Context:** Rounding up or sending the min lot silently can exceed the user's risk.
- **Decision:** `FloorVolume` with epsilon; below min → refuse with numbers; opt-in `InpAllowMinLotOverRisk`.
- **Consequences:** Risk is never exceeded silently; some small-risk trades on whole-contract CFDs are refused with a clear reason.

## ADR-005 Filling-policy and expiration fallback ladders
- **Context:** Servers differ in accepted filling policies and expiration types; flags are sometimes misleading.
- **Decision:** Derive candidates from symbol flags, try them in order, fall back only on the specific retcode, cache what worked per symbol and action; provide an override input for diagnostics.
- **Consequences:** Works on unknown brokers without configuration; an extra round trip on the first order of a symbol at worst.

## ADR-006 A RiskDesk position never stays without SL
- **Context:** Some servers reject SL/TP on market-execution orders; modify-after can fail.
- **Decision:** Verify SL after every open; fix with retries; close the position if it cannot be protected (`InpCloseIfStopFails=true`).
- **Consequences:** Rare forced closes with a loud message, instead of unprotected exposure.

## ADR-007 UI from standard chart objects, not CCanvas
- **Context:** Canvas gives prettier graphics but needs bitmap resources, manual hit-testing and more CPU, and behaves differently across platforms.
- **Decision:** `OBJ_RECTANGLE_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`, `OBJ_LABEL`, `OBJ_HLINE`, `OBJ_TEXT`.
- **Consequences:** Native click/edit handling, identical on MT4/MT5, simple DPI scaling; limited styling (no rounded corners/gradients).

## ADR-008 Tool trades by magic number; chart operations act on all trades of the symbol by default
- **Context:** The original's risk cap applies to its own trades only, but its Chart/Half/Risk-Free buttons act on "all trades on the chart".
- **Decision:** Magic number identifies tool trades for the risk budget. Chart-scope and account-scope operations default to all trades (parity) and can be limited to tool trades by setting.
- **Consequences:** Same behaviour as the original out of the box; users mixing other EAs can restrict scope.

## ADR-009 Persistence in files under MQLx/Files/RiskDesk
- **Context:** Terminal global variables only store doubles and are easily wiped.
- **Decision:** Small `key=value` files (`ui.ini`, `acct_<login>.ini`); chart objects keep the lines.
- **Consequences:** Human-readable, portable state; must handle missing/corrupt files gracefully (fall back to defaults).

## ADR-010 Synchronous requests
- **Context:** `OrderSendAsync` (MT5) is faster but complicates verification, retries and status reporting; MT4 has no async API.
- **Decision:** Synchronous `OrderSend` only; one command at a time per chart (busy flag).
- **Consequences:** Simple, verifiable flows; Full Close on many positions takes a few seconds and shows progress.

## ADR-011 Diagnostics before features (BrokerProbe, GatewaySmoke)
- **Context:** The original fails silently on two of the owner's brokers; guessing the cause wastes time.
- **Decision:** Build the probe in P0 and the gateway smoke test in P2, before any UI.
- **Consequences:** Broker issues are found in isolation, with data committed to the repo for future debugging.

## ADR-012 Mirror the original's inputs and defaults where known
- **Context:** The owner shared the original's settings dialog (v2.0.1). Familiar names and colours make the switch painless, and the inputs reveal features the guide does not describe (closed-trade objects, pending overlay, auto-fit, manual TP line).
- **Decision:** Where the original has an equivalent input, RiskDesk uses the same label (as the input's display comment), the same meaning and the owner's current value as default. Our own extra inputs keep their names. Unknown semantics (Q15–Q18) get a configurable assumption, never a guess baked into code.
- **Consequences:** Side-by-side parity can be checked (T-38). Our earlier "history overlay" idea moved to the backlog.

## ADR-013 TP modes derived from the original's full input labels
- **Context:** The first spec read "Trade with TP Line = false" as "no TP line, TP from R/R". That reading came from screenshots in which the labels were cut off. The full labels say "Manual TP Line - It doesn't work if Trade with TP Line is False" and "R/R | Only Active When Trade with TP Line is True", and the owner's demo test (Q15, 2026-11-12) confirmed them.
- **Decision:** Three TP modes, derived once in `Settings` as `ETpMode`: **No TP** (Trade with TP Line = false: no TP line, no TP), **Auto R/R** (true / Manual false: no TP line, TP from R/R at send time), **Manual TP line** (both true: draggable TP line that starts at the R/R distance). Lines, labels and order paths read `ETpMode`; nothing else reads the two booleans.
- **Consequences:** With the owner's configuration (true / false / 1.0) trades open with a 1:1 TP and no TP line, as in the original. Updated: 01 F-04/F-07/F-17, 04 §8, 05 §5, 06 OP-01/03/07, 07, 08 T-08.

## ADR-014 Placed pending orders are drawn by RiskDesk and moved by dragging
- **Context:** The owner's test (Q18) showed that the original draws placed pending orders itself in the "Pending Overlay" colours and that dragging those lines changes the order. CLAUDE.md §1 said RiskDesk acts only on clicks, and the first spec kept the overlay display-only.
- **Decision:** Overlay lines are selectable `OBJ_HLINE`s. Dropping one is a deliberate user action, handled as command OP-16: validate the new price (order type, side, BC-07), check the risk caps with the lot unchanged (04 §5), send `G-08 ModifyPending` through `CTradeGateway`, report the result; a refused or failed move snaps the line back. Deleting an overlay object never deletes the order. CLAUDE.md §1 now names this as the only non-click action.
- **Consequences:** Parity with the original; one more gateway primitive (G-08) and GatewaySmoke step; test T-39. The backlog item "draggable pending overlay lines" is done in v1 (P5).
