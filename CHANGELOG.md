# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog; versions: SemVer.

## [Unreleased]
### Changed
- Q20 answered: the candle countdown turns red when 10 % or less of the candle time is left, and at `00:00`. The input `InpCandleTimeWarnPct` (10, range 0–100, 0 = only at `00:00`) replaces `InpCandleTimeWarnSec` (60). The countdown itself comes in P7 (01 F-21, 05 §6, 07, 08 T-33).
- Q22 answered: requotes stay as they are. There is one `InpSlippagePoints` for every symbol and broker, with no broker-specific settings, and a requote that outlasts the retries ends red with nothing opened (03 §3, 07).
- Less context per Claude Code session (no change to the EA or scripts):
  - `build/run-uitest.ps1` prints a short result (header, INFO, FAIL lines with their screenshot, SUMMARY) instead of the whole report; `-Full` prints the report. The report is now read as UTF-8, so `·` no longer shows as `Â·`.
  - `build/run-script.ps1` prints the last run's FAIL/SKIP rows and `[summary]`.
  - `docs/10-decisions.md` is now an index; each ADR moved unchanged into `docs/adr/ADR-NNN-<slug>.md`.
  - The implementation log moved from `docs/11-open-questions.md` to `docs/history/implementation-log.md`.
  - CLAUDE.md §8 "Context budget".

### Added
- `build/summarize-profiles.ps1` and the generated `broker-profiles/SUMMARY.md`: account and test-symbol properties, probe items to check, and the latest GatewaySmoke result for every demo account (14 KB instead of 590 KB of raw reports).

## [0.5.0] - 2026-11-12 - Phase P5: Pending orders
### Added
- Set Pending (OP-07, F-09, `App/CommandsPending.mqh`): the order type from the Entry/SL lines (04 §7), stops-level refusals naming the distance and the price to move to (BC-07), TP by mode (F-17), BC-05 valuation, lots from Entry − SL, MT5 volume limit, per-trade and total risk caps, margin at the entry price, `InpConfirmTrades`, G-02 with the BC-06 pending filling ladder, the BC-08 expiration ladder and SL verification (R7). Status `Buy Stop 0.02 EURUSD @1.11351 placed · risk €4.99 (0.10 %) · #2085419900` (+ `· expires … server time`); lines removed; screenshot `pending`. Netting accounts (BC-10, D27): an order in the position's direction is checked as the merged position and confirmed; an opposite one is refused unless `InpNettingAllowOpposite`.
- Del Pending (OP-08, F-10): every pending order in chart scope (`InpScopeChartOps`; MT5 stop-limit orders included), tickets collected first, "Deleted 3 of 3 pending orders on EURUSD", amber with the reasons when some could not be deleted or were filled meanwhile; screenshot `delpending`.
- Pending order overlay (F-22, `UI/PendingOverlay.mqh`, `App/ControllerOverlay.mqh`): every placed order in chart scope drawn as `RD_PO_<ticket>_EN/SL/TP` (entry dash-dot, SL/TP dashed, overlay colours) with labels `Buy Stop 0.02 @ 1.11351`, `SL −€4.99 (0.10 %)`, `TP +€4.96 (R 1.00)`; follows changes made anywhere (MetaTrader's trade levels, other tools), goes with the order, redraws a deleted line, `InpShowPendingOverlay` switches it.
- Moving a placed order by dropping its overlay line (OP-16, ADR-014): entry moves the whole order, SL/TP only their level; order type, stops and freeze levels checked; the risk with the lot unchanged against the caps (old risk replaced for RiskDesk orders; a move that does not raise the risk is always allowed, D29); amber "risk now x % (panel y %)"; refused moves snap back; G-08 keeps the order's expiry; screenshot `modify`.
- Domain: `CRiskBudget::CheckMove` / `MoveNeedsOpenRisk` with unit tests (632 checks). `SOrder.expiration`, filled by both gateways.
- Debug pending self-test (`build/run-uitest.ps1 -Suite pending`, 08 §3f, `App/UiSelfTestPending*.mqh`): real pending orders far from the price on demo accounts only, covering T-13, T-14, T-15, T-23, T-39, F-22, the pending part of T-08, the Set Pending refusals and the netting confirmation.
- `build/profile-guard.ps1`: the runners copy the terminal's chart profile before a run and restore it afterwards.
- ADR-025; assumed details D27–D32; 08 §3f.

### Fixed
- G-05 (both platforms): Dukascopy MT4 kept listing a deleted order for a moment, so the overlay still drew it and a second Del Pending answered red "Ticket not found". The gateway now waits until the terminal drops the ticket, and a delete that fails for a ticket that is then gone counts as already deleted (amber).
- Every unattended MT4 start (unit tests, scripts, self-tests) left one more copy of the owner's chart in the terminal's profile: MT4 keeps the startup chart as a temporary chart that takes a chart-file number without removing the old file (also the cause of the 74 charts seen in P4). The runners now put the profile back after each run; the two copies made by today's P5 runs were removed (backed up).

### Changed
- The panel self-test clicks Set Pending only after removing the pending lines and Del Pending only when no order is in its scope, so it still never trades.
- 04 §5, 05 §6, 06 OP-07/OP-08/OP-16: the P5 details (ADR-025); 03 §3: what the P5 runs showed.

### Verified
- Both targets 0 errors / 0 warnings (release and debug). Unit tests 632 passed, 0 failed on MT4 and MT5 (0.5.0).
- Pending self-test with real demo orders (08 §3f), 2026-11-12, 0 failed in every run: A1 IG MT4 (EURUSD, XAUUSD, US30: 38 checks each, incl. the T-14 stops-level refusals at 40 / 200 / 150 pts), A2 IC Markets EU MT4 (EURUSD, XAUUSD, US30: 37), A3 IC Markets EU MT5 (EURUSD, XAUUSD, US30: 37), A4 Dukascopy MT4 (EURUSD, XAUUSD, USA30.IDX, AUS.IDX: 37, after the G-05 fix), A5 Dukascopy MT5 (same four: 37), A6 MetaQuotes netting (EURUSD, XAUUSD: 39, incl. the netting checks). The G-05 change was re-run on A3, A4 and A5, and GatewaySmoke passed 12 of 12 on A4 and A5 (reports in `broker-profiles/`).
- Panel self-test 66 passed, 0 failed on A1 and A3 (Set Pending / Del Pending clicks that send nothing); trade-basic 20 passed, 0 failed on A3 EURUSD (P4 regression).

## [0.4.0] - 2026-11-12 - Phase P4: Market orders
### Added
- Planning lines (`UI/Lines.mqh`, 05 §5): SL line (+ TP line in Manual TP line mode) for market orders, Entry + SL (+ TP) for pending orders; created selected, adopted after a timeframe change or restart, snapped to the tick grid when dropped; labels right of the current candle (F-18): `SL  -$5.74 (0.06 %) · 0.02 lot · 287 pts`, `TP  +$11.48 (R 2.00) · 574 pts`, `ENTRY  Buy Stop  1.11288`, amber when invalid or below the minimum lot. A line deleted by hand drops to a consistent mode with an amber note. The panel stays drawn above the lines.
- Add Line (OP-01), Delete Line (OP-02), Add Pend Line (OP-05) with the default placement of 05 §5 (at least the stops level away; clamped into view without crossing the price); the manual TP line follows SL/Entry drops at the R/R distance until the user drags it (`InpTpFollowsSl`).
- Live preview (OP-15, OP-06): Lots for the side the SL implies, `—` when invalid, red `0.003 < 0.01` below the minimum lot; Pending Info `Buy Stop · 0.01 lot` or `Invalid: …`; Buy or Sell dimmed when the lines make that side invalid (F-33), the tooltip says why.
- Buy / Sell (OP-03/04, `App/CommandsTrade.mqh`): permissions, spec, quote, Risk %, lines, side and stops-level validation, BC-05 valuation, commission (F-30), MT5 volume limit, lots rounded down, per-trade and total risk caps with the numbers (F-16, a RiskDesk position without SL blocks new trades), margin pre-check with needed / free / max lots and optional reduce-to-margin (F-31), netting (BC-10: same-direction add confirmed and checked as the merged position; opposite refused unless `InpNettingAllowOpposite`, then close + open), `InpConfirmTrades`, G-01. Status with the risk at the fill price and the ticket; lines removed (unless kept); screenshot.
- Screenshots (`Services/Screenshot.mqh`, F-19 / OP-14): after Buy/Sell and from the camera button, `Files/RiskDesk/Screenshots/<login>_<symbol>_<TF>_<yyyy-mm-dd_HH-MM-SS>_<action>_<ticket>.png`.
- Input `InpDefaultOffsetPct` (15 %, 05 §5; was missing from 07).
- `Platform/Market.mqh`: `InSession` (trading sessions of the terminal). `Platform/History.mqh`: `grossProfit` of a closed trade.
- Domain: `CPlanner::MarketLines`, `PendingLines`, `FollowTp` with unit tests (611 checks).
- Debug trade self-test (`App/UiSelfTestTrade*.mqh`, `build/run-uitest.ps1 -Suite trade | trade-basic [-Permissions off]`, 08 §3e): real orders on demo accounts only (R13), own magic, every test position closed again; covers T-03…T-09, T-11, T-12, T-25…T-28, F-16 AC3, F-28 (confirm trades), F-33 and the netting confirmations.
- ADR-022; assumed details D21–D26; 08 §3e.
- Two-column panel (ADR-023, owner's T-24 feedback): input `InpPanelColumns` = Auto (default) / One / Two. Auto shows two columns (Risk %…Set Pending on the left; Pending Info, Del Pending…Full Close on the same rows on the right; title and status across both) when one column would have to shrink below 85 % of Shape Size Scale to fit the chart. A1's 429 px chart: two columns at scale 0.92 instead of one at 0.59.
- Line labels keep clear of the panel (ADR-024, owner): a label the panel would cover is drawn left of the panel (right of it when there is no room on the left).

### Fixed
- MT4: dimmed buttons were drawn almost white: MQL4 evaluates `(c & 0xFF) - (d & 0xFF)` unsigned, so the colour blend wrapped around (`CTheme::Blend`).
- A second click made while a slow order was being sent (synchronous requests) could pass the click cooldown; the cooldown now also counts from the end of the command (T-25).
- Status bar: the line wrap was cached by font size only; a font preset change kept the old wrap (text wider than the panel).
- Lots and Pending Info cut their text when the field was narrow ("Buy Stop · 0.27" without "lot"); they now get a smaller font like the buttons. The status wrap no longer starts a line with a unit ("% / 10 %").
- 11: the assumed-details table broke after D20 (a blank line before D21).

### Changed
- 09: Add Pend Line and Pending Info (display) moved from P5 to P4 (T-03 needs them); 05 §5 placement and label anchoring refined; 07 lists `InpDefaultOffsetPct`.
- `build/run-uitest.ps1`: `-Suite panel | trade | trade-basic`, `-Permissions on | off`; trade reports are named after the symbol. It warns when a run makes the terminal's profile grow (MT4 had collected one chart per start), and a window capture shows the test chart (brought to the front first).

### Verified
- Both targets 0 errors / 0 warnings (release and debug). Unit tests 611 passed, 0 failed on MT4 and MT5.
- Trade self-test with real demo orders through the panel's buttons (08 §3e), 2026-11-12: A1 IG MT4 (EURUSD, XAUUSD, US30), A2 IC Markets EU MT4 (EURUSD, XAUUSD, US30), A3 IC Markets EU MT5 (EURUSD, XAUUSD, US30, SA40), A4 Dukascopy MT4 (EURUSD, XAUUSD, USA30.IDX, AUS.IDX), A5 Dukascopy MT5 (same four), A6 MetaQuotes netting (EURUSD, XAUUSD): every run 0 failed in its final form (full suite 32–35 checks, basic 18–19), including T-26 (Algo Trading off, A1 and A3) and T-27 (SA40 outside its session, A3). IG gold needed `InpSlippagePoints` 60 (Q22). Panel self-test 66 passed, 0 failed on A1 and A3 (with the two-column checks).

## [0.3.0] - 2026-11-12 - Phase P3: UI shell
### Added
- The panel (05-ui-spec, ADR-021): title with accent, hide/show toggle, Risk % and Lots fields, the eleven trading buttons, Pending Info, spread, a 3-line status bar and the camera button, built only from standard chart objects. Drag by the move handle (chart scrolling off while dragging), clamp so the whole panel stays in view, DPI scaling (scale × DPI / 96, fonts × scale with a 6 pt floor), auto-fit to the chart size (F-34, debounced 300 ms, grows back up to Shape Size Scale), six font presets, all colour inputs, tooltips that say what each button affects, live Ask/Bid on Buy/Sell, spread in points or pips with an optional amber threshold.
- Status bar (F-25): severity colours, word wrap measured in the status font, full text as tooltip and in the log; after `InpStatusHoldSec` the idle readout: permission warnings (BC-15), the symbol's trade mode, missing/stale quotes (BC-17), MT4 tick-value mismatch (BC-05), else "Open risk x % / cap" (F-29) from fresh position and order lists.
- Risk % field (F-02, T-02): `.` or `,`, 2 decimals, `0 < x ≤ max`; refusals restore the value in use and say why in red; saved per account in `Files/RiskDesk/acct_<login>.ini`.
- Persistence (F-23): `Files/RiskDesk/ui.ini` (panel position and hidden state, written 1 s after a change and on exit, only by the chart that changed it), Risk % per account; a timeframe change keeps everything in memory; a symbol change removes the old symbol's planning lines (chart object `RD_S_CHART`).
- `App/Inputs.mqh`: every input of 07-settings with the original's labels; `App/Settings.mqh` validates and clamps them (bounds in ADR-021), derives the TP mode and fills the Domain and gateway settings.
- `App/Controller.mqh`: busy guard and per-button click cooldown (F-06 AC6), Strategy Tester polling of buttons and the Risk % field, panel self-repair, one redraw per refresh. Every trading button answers amber "not implemented yet (coming in phase Pn)" with a log line (R8); buttons the symbol's trade mode forbids are grey with the reason (BC-15).
- Debug-only panel self-test (`RD_TEST_HOOKS`, `App/UiSelfTest*.mqh`) and `build/run-uitest.ps1` (08 §3d): drives the real event handlers on a terminal and covers T-01, T-02, T-20, T-21 (across a real restart), T-25, T-37, text fit at every scale and font, with screenshots; never trades and never touches the owner's saved state.
- `Platform/Compat.mqh`: `RD_OBJ_TEXT_UNICODE`, `RD_OBJ_ALL_PERIODS` / `RD_OBJ_NO_PERIODS`; `CAccountSpec::Login()`.
- ADR-021; assumed details D15–D20; 08 §3d.

### Fixed
- Candles drawn over the panel on charts with "Chart on foreground": RiskDesk switches it off while it runs and restores it when removed (D20).
- MetaTrader's One-Click Trading panel covered the panel's top, including the move handle: the panel keeps out of that corner while it is shown.

### Changed
- 05 §3: the clamp keeps the whole panel in view (`y ≤ chartHeight − panelHeight`), not only its top 40 px; 05 §1: rows never shorter than their text line.
- 02 §8/§11: the chart's last symbol is kept in the chart object `RD_S_CHART` instead of `chart_<ChartID>.ini`; object table completed.

### Verified
- Both targets 0 errors / 0 warnings (release and debug). Unit tests 581 passed, 0 failed on MT4 and MT5. Panel self-test 60 passed, 0 failed on A1 (IG MT4) and A3 (IC Markets EU MT5), 120 DPI, including a real window capture with One-Click Trading shown.

## [0.2.0] - 2026-11-12 - Phase P2: Platform layer and GatewaySmoke
### Added
- `Platform/TradeGateway*.mqh`: `CTradeGateway` for MT4 and MT5 with one public API (ADR-001, ADR-019): `OpenMarket` (G-01), `PlacePending` (G-02), `ModifyPositionSLTP` (G-03), `ClosePosition` (G-04, partial and full; MT4 remainder ticket, MT5 netting without `position`), `DeletePending` (G-05), `ListPositions` / `ListPending` (G-06/G-07, scope filter), `ModifyPending` (G-08), `SelectPosition` / `SelectPending`, `Configure(SGatewaySettings)`.
  - BC-06 MT5 filling ladder from the `SYMBOL_FILLING_*` flags with last-resort policies, retried only on `INVALID_FILL`, cached per symbol; `InpFillingOverride`.
  - BC-08 expiration ladder (MT5 flags, `TimeTradeServer()`; MT4 error 147 → resend without expiry), amber note when the policy differs from the request.
  - BC-07 stops and freeze checks before every request, with the distance needed; after an `INVALID_STOPS` answer the distances used.
  - BC-11 SL/TP attach: Auto falls back to modify-after when the server refuses stops that pass BC-07 (remembered per symbol); verification after every open and every pending placement; rule R7: SL that cannot be attached → position closed / order deleted, loud red message.
  - BC-13 retries with a fresh price (and Auto R/R TP) per attempt, doubling delays; BC-14 ambiguous answers checked in positions/orders/deal history before the single allowed resend (rule R9).
  - BC-09 order-count limit; BC-10 netting (opposite opens refused, closes never exceed the position); BC-15 permission and symbol trade-mode checks in every primitive; MT5 order-mode flags (market/limit/stop/SL/TP).
  - One log line per request and per answer with symbol, side, volume, price, SL, TP, filling/time policy, deviation, magic, attempt, retcode/error and its name (06 §6).
- `Platform/TradeErrors.mqh`: every MT5 retcode and MT4 error of 03 §5 mapped to a handling class and a status message; fatal answers get the numbers (volume grid, margin needed vs free, freeze level, distances).
- `Platform/Money.mqh`: `LossPerLot` / `ProfitPerLot` (BC-05: MT5 `OrderCalcProfit` with tick-value fallback; MT4 tick value cross-checked against contract × rate, conservative value and "Tick value mismatch" warning above 5 %; one retry after selecting the conversion pair), `MarginFor`, `MaxLotsByMargin` (BC-09), `FillLossToSl` for positions and orders (04 §5).
- `Platform/Market.mqh`: `AgeSeconds`, `IsStale` (BC-17). `Platform/History.mqh`: `ClosedTrades` (MT5 exit deals, MT4 history pool). `Platform/Compat.mqh`: `RdServerTime`, `RdSymbolAcceptsTp`, `RdSymbolAcceptsKind`.
- `GatewaySmoke.mq4/.mq5` with `GatewaySmokeCore.mqh` (demo only, R13): S00 preflight, M01–M07 market buy/sell with verify, modify, partial close, close, P01–P03 buy limit place/modify/delete, cleanup; PASS/FAIL/SKIP table to the Experts tab and `Files/RiskDesk/smoke_<company>_<platform>_<login>_<yyyymmdd>.txt` (08 §3b).
- ADR-019; assumed details D12–D14; 08 §3b GatewaySmoke.
- `build/run-script.ps1`: runs BrokerProbe or GatewaySmoke unattended on one saved account (login/server, inputs via a preset, waits for the report; no password handled) (08 §3c, ADR-020).
- `CAccountSpec::WaitReady`: BrokerProbe and GatewaySmoke wait for the account data after a login; GatewaySmoke decides R13 after it.
- First broker data: BrokerProbe reports for A1–A6 and GatewaySmoke reports (19 runs, 228 steps, 0 failures, plus targeted T-22, T-23 and ModifyAfter runs) in `broker-profiles/`; observations in 03 §3; Q21 answered (keep the conservative rule).

### Fixed
- BC-01 conversion lookup chose an index CFD as the USD→EUR pair on IC Markets EU MT5; forex symbols are now searched first.
- MT4 partial close on servers that keep the original ticket (IG) is recognised at once instead of after a 1 s search and a warning.
- MT5 close on servers that answer without a deal ticket (Dukascopy) now reports the close price and realized P/L.

### Changed
- 03 BC-05: commission is added once, by `CRiskMath::LotsFromRisk`, not by `LossPerLot` (they disagreed; ADR-019).
- 09 P2: GatewaySmoke opens 2 × min lot when the risk guard allows, so the partial close can be tested.

## [0.1.0] - 2026-11-12 - Phase P1: Domain and unit tests
### Added
- `Domain/PriceMath.mqh`: tick-size normalization and directional rounding (BC-03), half-tick price comparisons, BC-07 distance helpers, points/ticks, `RdVolumeDigits`, `RdFloorVolume` (never rounds up, +1e-8 epsilon; BC-04), volume validity and comparisons.
- `Domain/Format.mqh` (new, ADR-018): money in the account currency with thousands separators and BC-12 signs, percent, lots with the step's decimals, prices, order names.
- `Domain/RiskMath.mqh`: risk base and money, `LotsFromRisk` (min-lot refusal with numbers, `InpAllowMinLotOverRisk`, max-lot cap; 04 §2–4), `TpFromRR`, reward ratio, commission/cost distance, partial-close volume (04 §10), tick-value valuation formula.
- `Domain/Validators.mqh`: Risk % parsing (F-02), market side and Lots-preview side (04 §6), pending classification and order-type geometry (04 §7), stops level for market and pending orders and freeze level for positions and pending orders (BC-07), MT5 volume limit (BC-04), quote check. Every refusal names what is needed ("needs >= 30 pts (0.00030), move it to 1.09970 or lower").
- `Domain/Planner.mqh`: market / Lots-preview / pending plans with the three TP modes (F-17), sizing step after the platform valuation, Risk Free target with all four modes and skip reasons (04 §9, F-11), moves of placed pending orders (OP-16).
- `Domain/RiskBudget.mqh`: open risk of tool positions and pending orders, per-trade and total caps with old-contribution replacement for netting adds and moved orders (04 §5, F-16), open-risk readout (F-29).
- `Domain/Types.mqh`: `SPlanSettings` (the settings the Domain reads), `ELineRole`, `RdSkip`, `RdTpModeFrom`.
- `RiskDeskTests.mq4/.mq5` with `Scripts/RiskDesk/Tests/` (runner, fixtures, one file per module): all vectors V-01…V-24 plus edge cases and sweeps, 58 tests / 581 checks; failures and summary to the Experts tab and an Alert, report in `Files/RiskDesk/tests_<platform>.txt`.
- `build/run-tests.ps1`: headless run of RiskDeskTests in every MT4/MT5 terminal of `paths.local.ps1` (08 §2); first results 581 passed, 0 failed on MT4 and MT5.
- ADR-018 (Domain API shape); assumed details D7–D11.

### Changed
- `docs/09` P1 now names V-01…V-24 (04 §12 defines 24 vectors; the roadmap said V-22).

## [0.0.1] - 2026-11-12 - Phase P0: bootstrap and diagnostics
### Added
- Specification pack: CLAUDE.md, README, docs 01–11, broker-profiles placeholder.
- Repository layout of CLAUDE.md §4 with compiling stubs for every module of the later phases.
- `build/build.ps1`: compiles every `.mq4` (MT4 MetaEditor) and `.mq5` (MT5 MetaEditor) under `src/Experts` and `src/Scripts`, reads the result from MetaEditor's UTF-16 log (the exit code is meaningless), one line per file, exit 1 on any error, warning, missing output or missing MetaEditor; `-Target mt4|mt5|all`, `-Debug` (RD_TEST_HOOKS).
- `build/install-junctions.ps1`: links `src/Experts|Scripts|Include/RiskDesk` into every terminal data folder of `paths.local.ps1`; idempotent, re-points stale links, never touches real folders with content; `-DryRun`, `-Uninstall`.
- `build/paths.example.ps1` (template for the git-ignored `paths.local.ps1`).
- `Include/RiskDesk/Build.mqh`: product name, `RD_VERSION`, release/debug switch (ADR-015).
- `Domain/Types.mqh`: core and input enums (07-settings), `SSymbolSpec`, `SAccountSpec`, `SQuote`, `SLines`, `STradePlan`, `SPosition`, `SOrder`, `SResult` and pure helpers.
- `Platform/Compat.mqh` (platform name, tester/DPI, margin mode, property decoders, MT5 retcode names), `SymbolSpec.mqh` (runtime read + BC-02 sanity checks), `AccountSpec.mqh` (BC-15 permission messages, BC-12 cent detection), `Market.mqh` (`Quote`), `Money.mqh` (BC-01 conversion lookup by properties, raw BC-05 valuations and margin; ADR-017).
- `Services/Logger.mqh`: Experts tab plus daily file `Files/RiskDesk/Logs/RiskDesk_<yyyymmdd>.log`; macros `RD_LOG_*` (ADR-016).
- EA shells `RiskDesk.mq4/.mq5`: on init log version, platform, terminal build, account (currency, leverage, margin mode, demo/real), trade permissions and the chart symbol's spec.
- `BrokerProbe.mq4/.mq5` (F-27, 08 §3): terminal, time, account, test-symbol discovery, per-symbol properties, BC-05 valuations (OrderCalcProfit / tick value / contract × rate with mismatch %), margin, MT5 OrderCheck filling and expiration matrix, MT4 MarketInfo dump and AccountFreeMarginCheck, conversion routes, summary of items to check. Nothing is executed.
- `RiskDeskTests` and `GatewaySmoke` stubs (GatewaySmoke refuses non-demo accounts, R13).
- `broker-profiles/original-tool-errors.md` template.
- ADR-015 (Build.mqh and versioning), ADR-016 (static logger configuration), ADR-017 (BrokerProbe structure).

### Changed
- Spec aligned with the original's settings dialog (v2.0.1): TP modes (F-17), closed trade objects (F-20), candle time (F-21), pending order overlay (F-22), auto-fit panel (F-34), original colour/font defaults; new questions Q15–Q19; ADR-012; tests T-37, T-38.
- Owner's answers to Q1–Q17 and Q19 folded into the spec: TP modes corrected (the "Manual TP Line" and "R/R" labels had been read inverted; ADR-013, T-08); Risk Free default `RF_SPREAD_COMMISSION` (04 §9, V-23); candle time format, colour and server-time source (F-21); Nasdaq 100 in the test matrix; `11-open-questions.md` reorganised (only Q18 open).
- Q18 answered: placed pending orders are drawn by RiskDesk in the overlay colours and can be dragged to modify the order (OP-16, G-08, ADR-014, T-39, V-24; CLAUDE.md §1). Manual TP line follows the SL until dragged (`InpTpFollowsSl`, [NEW]). Candle time formats `mm:ss` / `hh:mm:ss` / `Nd hh:mm:ss`, gold, red in the last `InpCandleTimeWarnSec` seconds and at 00:00 (`InpColorCandleTimeWarn`; threshold open as Q20). Pending entry planning line dash-dot.
- Owner's follow-ups: no TP preview in Auto R/R mode (`InpShowRRPreview` and `RD_LN_TPRR` removed); dragging a placed order's entry line moves its SL and TP by the same distance; assumed-detail IDs renamed D1–D6 (A1–A7 are test accounts).
- 08-testing §3: BrokerProbe inputs `InpFindTestSymbols`, `InpMaxSymbols` (ADR-017).
