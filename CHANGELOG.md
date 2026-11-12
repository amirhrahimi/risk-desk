# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog; versions: SemVer.

## [Unreleased]

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
