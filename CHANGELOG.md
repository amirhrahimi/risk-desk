# Changelog

All notable changes to this project are documented here. Format: Keep a Changelog; versions: SemVer.

## [Unreleased]
### Added
- Specification pack: CLAUDE.md, README, docs 01–11, broker-profiles placeholder.

### Changed
- Spec aligned with the original's settings dialog (v2.0.1): TP modes (F-17), closed trade objects (F-20), candle time (F-21), pending order overlay (F-22), auto-fit panel (F-34), original colour/font defaults; new questions Q15–Q19; ADR-012; tests T-37, T-38.
- Owner's answers to Q1–Q17 and Q19 folded into the spec: TP modes corrected (the "Manual TP Line" and "R/R" labels had been read inverted; ADR-013, T-08); Risk Free default `RF_SPREAD_COMMISSION` (04 §9, V-23); candle time format, colour and server-time source (F-21); Nasdaq 100 in the test matrix; `11-open-questions.md` reorganised (only Q18 open).
- Q18 answered: placed pending orders are drawn by RiskDesk in the overlay colours and can be dragged to modify the order (OP-16, G-08, ADR-014, T-39, V-24; CLAUDE.md §1). Manual TP line follows the SL until dragged (`InpTpFollowsSl`, [NEW]). Candle time formats `mm:ss` / `hh:mm:ss` / `Nd hh:mm:ss`, gold, red in the last `InpCandleTimeWarnSec` seconds and at 00:00 (`InpColorCandleTimeWarn`; threshold open as Q20). Pending entry planning line dash-dot.
- Owner's follow-ups: no TP preview in Auto R/R mode (`InpShowRRPreview` and `RD_LN_TPRR` removed); dragging a placed order's entry line moves its SL and TP by the same distance; assumed-detail IDs renamed D1–D6 (A1–A7 are test accounts).
