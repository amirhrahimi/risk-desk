# Support

Risk Desk is maintained in spare time and supported through this repository's [issues](https://github.com/amirhrahimi/risk-desk/issues). There is no private support channel, and no paid support.

## Before you ask

1. Read the status-bar message and the **Experts** tab (Toolbox, Ctrl+T); they usually name the cause.
2. Check [docs/troubleshooting.md](docs/troubleshooting.md), the [user guide](docs/user-guide.md) and [docs/configuration.md](docs/configuration.md).
3. Search the [existing issues](https://github.com/amirhrahimi/risk-desk/issues?q=is%3Aissue).

## Where to ask

| You want to … | Use |
|---|---|
| report a bug or an unexpected result | [Bug report](https://github.com/amirhrahimi/risk-desk/issues/new?template=bug_report.yml) |
| report how Risk Desk works with your broker | [Broker test report](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml) |
| suggest a feature | [Feature request](https://github.com/amirhrahimi/risk-desk/issues/new?template=feature_request.yml) |
| ask a question | a [blank issue](https://github.com/amirhrahimi/risk-desk/issues/new) with "Question:" in the title |
| report a security problem | [SECURITY.md](SECURITY.md) |

Please do not contact the authors of Map Manager about Risk Desk; it is an independent project ([NOTICE.md](NOTICE.md)).

## What to include

- Risk Desk version (Experts tab: `RiskDesk <version> starting`), MT4 or MT5, terminal build (**Help → About**).
- Broker, account type (demo or live, hedging or netting, account currency, cent or standard), symbol and timeframe.
- The inputs you changed from their defaults.
- What you did, what you expected, and what happened: the **status-bar text** and the **Experts-tab lines** around the click, copied as text (right-click → Copy).
- For broker-related problems: a BrokerProbe report of that account.

## Redact before posting

Logs, screenshots and BrokerProbe/GatewaySmoke reports can contain your **account number**, balance and your Windows user name (in file paths). Remove them before posting:

- reports: `build/redact-report.ps1 -Path <report> -Label C1` replaces the login and the data path;
- logs and screenshots: replace the account number by hand, and crop screenshots to the chart;
- never post passwords, statements or broker e-mails.
