# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The EA and the scripts are unchanged; this concerns developing Risk Desk.

### Added
- Risk Desk can be developed on macOS and Linux. The build scripts in `build/` run with PowerShell 7 (`pwsh`) and start MetaEditor and the terminals under Wine: MetaQuotes' MetaTrader 5 app on macOS, `mt5linux.sh` or the distribution's Wine on Linux. `install-junctions.ps1` creates symbolic links there (ADR-032). See CONTRIBUTING.md.
- `build/test-build-scripts.ps1` checks the build scripts without MetaTrader, and the `scripts` workflow runs it on Linux, macOS and Windows.
- `build.ps1 -PathsFile` and `package-release.ps1 -OutDir`.

### Fixed
- `package-release.ps1` run with Windows PowerShell 5.1 wrote zip entries with backslashes (`MQL5\Experts\RiskDesk.ex5`), which unpack into wrongly named files on macOS and Linux. Entry names now always use `/`. Released zips were not affected: CI packs them with PowerShell 7.
- The runners (`run-tests.ps1`, `run-script.ps1`, `run-uitest.ps1`) also find a terminal whose data folder is its install folder (portable mode), where there is no `origin.txt`.

## [1.8.1] - 2026-11-14

The trading logic is the same as in 1.8.0.

### Changed
- The EA's properties dialog (Common tab in MT5, About tab in MT4) describes Risk Desk in more detail: how the lot is sized from the risk % and the stop-loss line, the order and trade-management buttons, the status message after every click, and that it never trades on its own.

## [1.8.0] - 2026-11-14

First stable release. Changes since 1.8.0-rc.1; the trading logic is otherwise as in 1.7.0 and 1.8.0-rc.1. Tested on demo accounts only; not yet tested on live accounts. See the README for known limitations.

### Fixed
- After an unclear result (a timeout or no reply) the check for "did the request execute?" could take a trade of the seconds before for it: a second click with the same symbol, side and volume, then a lost reply, made the panel report success and name the old ticket although nothing had been opened (MT5: "executed but the position was not found"). The gateway now records the trades that exist before the first send and ignores them (BC-14, ADR-031). Found by the new safety tests on IC Markets EU MT4 and MT5.

### Added
- Debug builds only: fault injection in the gateway and a `safety` suite for `build/run-uitest.ps1` that runs the three safety paths against real demo servers: closing a position whose SL cannot be attached (T-29, rule R7), the lost-reply cases without a blind resend (T-35, rule R9) and the MT5 filling-policy fallback after a real rejection (BC-06). They pass on IC Markets EU and Dukascopy, MT4 and MT5 (ADR-031, `docs/design/08-testing.md` §3j). Release builds contain none of it.

### Changed
- The name in messages, dialogs and tooltips reads "Risk Desk" (status bar, confirmation dialogs, line and overlay tooltips, refusals). Code identifiers, file names, log names and the order comment stay `RiskDesk`.

## [1.8.0-rc.1] - 2026-11-13

Release candidate for 1.8.0, the first stable release, published as a pre-release for testing. The trading code is the same as in 1.7.0. Tested on demo accounts only; not yet tested on live accounts. The hardening work planned before 1.8.0 (tests that force the untested safety paths, the full demo test matrix, a review of the trade gateway) is still open; see the ROADMAP and the README's known limitations.

### Added
- `build/check-version.ps1`: `build.ps1` and the CI build fail when `RD_VERSION` and `RD_VERSION_PROP` in `Build.mqh` name different versions.

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
- Open-source project files: `LICENSE` (MIT), `NOTICE.md` (attribution to Map Manager by Mohammad Ali Poursamadi and team), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `ROADMAP.md`, user documentation in `docs/`, issue and pull-request templates, `.gitattributes`, `.editorconfig`.
- GitHub workflows: every pull request and push compiles MT4 and MT5 (0 errors, 0 warnings) and attaches the package to the run; a push to `main` publishes the release of a new version or else replaces the *Development build* pre-release; builds that are not a release report their commit in the version (`1.7.0+dev.abc1234`); Markdown link check.
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

[Unreleased]: https://github.com/amirhrahimi/risk-desk/compare/v1.8.1...HEAD
[1.8.1]: https://github.com/amirhrahimi/risk-desk/compare/v1.8.0...v1.8.1
[1.8.0]: https://github.com/amirhrahimi/risk-desk/compare/v1.8.0-rc.1...v1.8.0
[1.8.0-rc.1]: https://github.com/amirhrahimi/risk-desk/compare/v1.7.0...v1.8.0-rc.1
[1.7.0]: https://github.com/amirhrahimi/risk-desk/releases/tag/v1.7.0
