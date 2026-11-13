# Roadmap

This page lists **plans, not commitments**. Order and scope can change; nothing here has a date. Suggestions are welcome as [feature requests](https://github.com/amirhrahimi/risk-desk/issues/new?template=feature_request.yml).

## 1.8.0: first stable release

The hardening work that turns the 1.7.0 pre-release into a release line:

- **Force the untested safety paths in debug builds** and run them on demo accounts: closing a position whose stop-loss cannot be attached (T-29, rule R7) and an ambiguous result without blind resend (T-35, rule R9). Add a test for the MT5 filling-policy fallback after a real rejection.
- **Run the full demo test matrix** (T-01 to T-28 on the IG, IC Markets EU and Dukascopy accounts, T-30 on a netting account, T-31 on a cent account if available) and fix what it finds, with a regression test for every fix in the risk logic ([docs/design/08-testing.md](docs/design/08-testing.md)).
- **Review the trade gateway** against the compatibility checklist ([docs/design/03-broker-compatibility.md §6](docs/design/03-broker-compatibility.md#6-compatibility-checklist-definition-of-done-for-every-trade-feature)).
- Refresh the BrokerProbe and GatewaySmoke reports with the release build.
- Show the product name as "Risk Desk" in the panel title, dialogs and messages (code identifiers, file names and log file names stay `RiskDesk`).
- An MT4 compile check in CI, if a reliable way to install MetaEditor 4 on a runner is found. The MT5 compile check and the docs link check already run on every pull request.

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
