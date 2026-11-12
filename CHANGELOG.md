# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog; versions: SemVer.

## [Unreleased]

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
