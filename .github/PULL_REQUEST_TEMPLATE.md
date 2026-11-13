## What and why

<!-- What does this change, and why? Link the issue: "Closes #123". -->

## Type

- [ ] Bug fix
- [ ] Feature
- [ ] Documentation
- [ ] Build / tooling
- [ ] Changes order handling, lot sizing, risk checks or a default value (**needs an agreed issue first**)

## Checks

- [ ] MT4 and MT5 both compile with **0 errors, 0 warnings** (`build/build.ps1`)
- [ ] Unit tests pass on MT4 and MT5 (`build/run-tests.ps1`), with new tests for any `Domain/` change
- [ ] Platform-specific code only in `Platform/`, `App/Inputs.mqh` or the entry files; no MT5 Standard Library; all trading through `CTradeGateway`
- [ ] Docs updated where needed (README, `docs/`, `docs/design/`, an ADR) and `CHANGELOG.md` under `[Unreleased]`
- [ ] **No secrets or binaries:** no account numbers, passwords, statements, data-folder paths, unredacted reports, `.ex4`/`.ex5`/`.log` files

## Demo test evidence

<!--
Risk Desk is a manual tool, so there is no backtest to show. For changes that affect trading, list what you ran on DEMO accounts:
- broker, platform, build, account type
- symbols
- test IDs from docs/design/08-testing.md (T-xx), self-test suites, GatewaySmoke results
- status-bar texts or redacted Experts-tab lines
-->
