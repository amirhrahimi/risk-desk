# Roadmap

This page lists **plans, not commitments**. Order and scope can change; nothing here has a date. Suggestions are welcome as [feature requests](https://github.com/amirhrahimi/risk-desk/issues/new?template=feature_request.yml).

## Test work left over from 1.8.0

1.8.0 is the first stable release. Its hardening (see the [CHANGELOG](CHANGELOG.md)) is done: the three safety paths are tested on demo servers with injected faults (T-29, T-35, MT5 filling fallback; ADR-031), the trade gateway is reviewed against the compatibility checklist (one BC-14 defect found and fixed), and messages and dialogs say "Risk Desk". It was released before this test work, which is still open:

- **Finish the full demo test matrix on open markets** ([docs/design/08-testing.md](docs/design/08-testing.md)): T-01 to T-28 on EURUSD, XAUUSD and an index on the IG, IC Markets EU and Dukascopy accounts, and T-30 on a netting account. A weekend run covered the panel, trade, pending, manage, half and extras suites on BTCUSD (the only symbol open) on four accounts. T-31 needs a cent account (none available). Fix what it finds, with a regression test for every fix in the risk logic.
- **Refresh the BrokerProbe and GatewaySmoke reports with the release build**, on a weekday: on a closed market IG reports every symbol as trade-disabled.

## Development on macOS and Linux

The build scripts run on macOS and Linux with PowerShell 7 and MetaTrader under Wine ([ADR-032](docs/design/adr/ADR-032-development-on-macos-and-linux.md)). On Linux, linking, the MT5 build and the headless unit tests are verified. Still to check:

- MetaQuotes' MetaTrader 5 app on a Mac: the Wine the scripts find, `install-junctions.ps1`, `build.ps1` and `run-tests.ps1`.
- MT4 under Wine on Linux and macOS: links, compile, `run-tests.ps1`.
- `run-script.ps1` and `run-uitest.ps1` against a logged-in demo account under Wine.

## Broader broker coverage

- IG on MetaTrader 5, cent accounts, and more brokers and account types, through [broker test reports](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml) from the community.
- Confirm behaviour on live accounts, reported by users who choose to do so after testing on demo.

## Candidate features (1.x)

- Hotkeys for the main buttons.
- Manual lot override.
- Trade history overlay drawn by Risk Desk (entry/exit markers with P/L).
- Several take-profits / a scale-out plan.
- Trailing stop.
- MT5 stop-limit orders.
- Saved setting profiles.
- UI translations (for example Persian).
- "Close losers only" / "close winners only".
- Per-symbol default SL distance (for example ATR-based).

## Community requests

Open feature requests are tracked as [issues labelled *enhancement*](https://github.com/amirhrahimi/risk-desk/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement).
