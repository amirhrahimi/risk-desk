# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- CI: the MT5 compile check and the Markdown link check were verified on GitHub Actions and now run on every pull request and push to `main` that touches the sources or the docs. MT4 is still checked locally with `build/build.ps1`.

## [1.7.0] - 2026-11-13

First public pre-release. Tested on demo accounts only (IG MT4, IC Markets EU MT4 and MT5, Dukascopy MT4 and MT5, MetaQuotes-Demo MT5 netting); not yet tested on live accounts. See the README for known limitations.

### Added
- Chart panel for MetaTrader 4 and 5: Risk %, live lot size, Add Line, Delete Line, Buy and Sell with live prices, Add Pend Line, Pending Info, Set Pending, Del Pending, Risk Free, Half Close, Chart Close, Full Close, spread, status bar, camera button.
- Risk-based lot sizing from the broker's own symbol properties: lot rounded down to the volume step, refusal (or opt-in minimum lot) when the minimum lot would exceed the risk, commission-aware sizing, per-trade and total open-risk caps, margin pre-check with a buffer.
- Take-profit modes: none, automatic at R/R, manual TP line (optionally following the SL).
- Pending-order overlay: placed pending orders drawn on the chart and modified by dragging their lines.
- Broker compatibility layer: prices normalized to tick size, volume grids, MT5 filling-policy and expiration fallbacks, tick-value cross-check and `OrderCalcProfit` valuation, MT5 netting accounts, cent accounts, retries with no blind resend, SL/TP verification and close-if-SL-fails.
- Confirmations (optional; Full Close on by default), click cooldown, dimmed invalid side, open-risk readout.
- Extras: candle countdown, removal of MetaTrader's closed-trade objects, automatic screenshots, panel scaling and two-column layout, persistence across timeframe changes and restarts, daily log files with retention.
- BrokerProbe script (account and symbol report, no trading), GatewaySmoke script (demo-only gateway test), RiskDeskTests unit tests (842 checks), debug-build panel self-test suites.
- Open-source project files: `LICENSE` (MIT), `NOTICE.md` (attribution to Map Manager by Mohammad Ali Poursamadi and team), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `ROADMAP.md`, user documentation in `docs/`, issue and pull-request templates, `.gitattributes`, `.editorconfig`, draft GitHub workflows (untested).
- `build/package-release.ps1` (release zip with checksums) and `build/redact-report.ps1` (removes the login and data path from reports).
- SPDX licence header in every source file; `#property version` and `#property link` in every entry file.

### Changed
- The EA sits directly under *Expert Advisors* in the Navigator, without a `RiskDesk` sub-folder.
- Version numbering continues from the internal 0.7.0 as 1.7.0; 1.8.0 will be the first stable release.
- Specifications moved to `docs/design/`; broker reports are published with the account number replaced by an account label.

### Removed
- Development-only documents (AI prompt pack, implementation diary, notes about the original tool's behaviour).

## Development history before 1.7.0

Internal versions, not published. The BrokerProbe and GatewaySmoke reports in `broker-profiles/` carry these version numbers; the decisions are recorded in [docs/design/adr/](docs/design/adr/).

| Version | Date | Phase |
|---|---|---|
| 0.7.0 | 2026-11-13 | P7: candle time, closed-trade objects, cent display, log retention |
| 0.6.0 | 2026-11-12 | P6: Risk Free, Half Close, Chart Close, Full Close |
| 0.5.0 | 2026-11-12 | P5: pending orders and overlay |
| 0.4.0 | 2026-11-12 | P4: market orders with risk sizing |
| 0.3.0 | 2026-11-12 | P3: panel |
| 0.2.0 | 2026-11-12 | P2: platform layer, trade gateway, GatewaySmoke |
| 0.1.0 | 2026-11-12 | P1: domain layer and unit tests |
| 0.0.1 | 2026-11-12 | P0: build tooling and BrokerProbe |

[Unreleased]: https://github.com/amirhrahimi/risk-desk/compare/v1.7.0...HEAD
[1.7.0]: https://github.com/amirhrahimi/risk-desk/releases/tag/v1.7.0
