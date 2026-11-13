# Contributing to Risk Desk

Thank you for helping. Contributions of every size are welcome: a broker test report, a bug report with a log line, a documentation fix, or code.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) first. Risk Desk sends real orders, so the bar for changes to trading behaviour is high: **open an issue and discuss a change to order handling, lot sizing, risk checks or defaults before writing the code.**

## Ways to help

- **Broker test reports:** run Risk Desk with your broker on a demo account and open a [broker test report](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml). See [docs/broker-compatibility.md](docs/broker-compatibility.md#add-your-broker).
- **Bug reports:** use the [bug report](https://github.com/amirhrahimi/risk-desk/issues/new?template=bug_report.yml) template. The status-bar text and the Experts-tab lines are the most useful information.
- **Documentation:** corrections and clarifications are always welcome.
- **Code:** pick an issue, or propose one first. [ROADMAP.md](ROADMAP.md) lists planned work.

## Development setup

You need Windows, Git, and at least one MetaTrader 4 and one MetaTrader 5 terminal (each with MetaEditor) logged in to **demo** accounts.

1. Fork and clone the repository.
2. Copy `build/paths.example.ps1` to `build/paths.local.ps1` (git-ignored) and fill in the MetaEditor paths and your terminals' data folders (**File → Open Data Folder**).
3. Link the sources into the terminals (directory junctions for `Include/RiskDesk` and `Scripts/RiskDesk`):
   ```
   powershell -ExecutionPolicy Bypass -File build/install-junctions.ps1
   ```
4. Build both platforms. The script compiles every target, copies the EA into each terminal's `Experts` folder and fails on any error **or warning**:
   ```
   powershell -ExecutionPolicy Bypass -File build/build.ps1            # or -Target mt4 / -Target mt5
   ```
5. Run the unit tests headless on each terminal:
   ```
   powershell -ExecutionPolicy Bypass -File build/run-tests.ps1        # -Symbol <name> if EURUSD does not exist on the account
   ```

Without the scripts you can compile in MetaEditor directly: open `src/Experts/RiskDesk.mq4` (or `.mq5`) and press **F7**. MetaEditor's exit code is not reliable; read the `N errors, M warnings` line of the log.

Optional, on demo accounts only:

- `build/run-script.ps1`: runs BrokerProbe or GatewaySmoke unattended on one saved account.
- `build/build.ps1 -Debug` then `build/run-uitest.ps1 -Suite <panel|trade|pending|manage|half|extras>`: the panel self-test suites, which click the real panel and place real **demo** orders. A debug build refuses to run as a release.

The layout, the build and the specifications are described in [docs/architecture.md](docs/architecture.md) and [docs/design/](docs/design/). [CLAUDE.md](CLAUDE.md) lists the project's non-negotiable rules (R1–R14); they apply to every contributor.

## Code style

- One source tree for both platforms. Platform-specific code (`#ifdef __MQL5__`) only in `src/Include/RiskDesk/Platform/`, `App/Inputs.mqh` and the entry files.
- `Domain/` makes no terminal calls; add or extend unit tests (`src/Scripts/RiskDesk/Tests/`) for every Domain change.
- All trading goes through `CTradeGateway`. No `OrderSend`/`OrderClose`/`OrderModify`/`OrderDelete` elsewhere, and no MT5 Standard Library.
- No hard-coded broker properties: read them through `SymbolSpec` / `AccountSpec`. Prices are normalized to the tick size, volumes rounded down to the step.
- Every action ends with a status message and a log line; no silent failure.
- Naming: `CName` classes, `SName` structs, `ENameType` enums, `m_` members, `Inp` inputs, `RD_` macros and chart objects. MetaEditor indentation (3 spaces, braces on their own line). Sources are ASCII.
- Every source file starts with the licence header:
  ```
  // Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
  // SPDX-License-Identifier: MIT
  // Copyright (c) 2026 Amir Rahimi
  // Workflow inspired by Map Manager by Mohammad Ali Poursamadi and team
  // (https://poursamadi.com/en/). No code of it is used; see NOTICE.md.
  ```
- A new or changed input needs its trailing label comment, a row in [docs/design/07-settings.md](docs/design/07-settings.md) and in [docs/configuration.md](docs/configuration.md). Changing a default is a behaviour change: discuss it first.
- Do not copy code, text or images from other EAs, including the tool that inspired this one ([NOTICE.md](NOTICE.md)).

## Branches and commits

- Branch from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat(pending): …`, `fix(gateway): …`, `docs: …`, `test(domain): …`, `chore(build): …`. Mark breaking changes with `!` and explain them in the body.
- Keep commits focused; one pull request per topic.

## Pull request checklist

- [ ] Both platforms compile with **0 errors and 0 warnings** (`build/build.ps1`).
- [ ] Unit tests pass on MT4 and MT5 (`build/run-tests.ps1`).
- [ ] Trading-related changes were tested on **demo** accounts (which brokers, which symbols, which T-xx tests from [docs/design/08-testing.md](docs/design/08-testing.md)), and the result is in the PR description.
- [ ] No change to order handling, lot sizing, risk checks or defaults without a linked, agreed issue.
- [ ] Docs updated (README, `docs/`, the design docs or a new ADR in `docs/design/adr/`), and `CHANGELOG.md` under `[Unreleased]`.
- [ ] **No account data and no binaries:** no logins, passwords, account statements, data-folder paths, screenshots showing account details, `.ex4`/`.ex5`, `.log`, `.set` files with personal values.

## Never commit

- Account numbers, passwords (trading or investor), statements, broker e-mails.
- `build/paths.local.ps1`, compiled `.ex4`/`.ex5`, MetaEditor `.log` files, terminal caches or tester files (they are git-ignored; keep it that way).
- Unredacted BrokerProbe or GatewaySmoke reports. Use `build/redact-report.ps1 -Path <report> -Label C1` first.

## Releases

Releases are built and published by GitHub Actions ([.github/workflows/build.yml](.github/workflows/build.yml)); binaries are never committed.

- **Every pull request and push** compiles the eight targets with MetaEditor 4 and 5 (0 errors, 0 warnings) and attaches the package to the workflow run, so reviewers can download and try it on a demo account.
- **A new version:** maintainers bump `RD_VERSION` and `RD_VERSION_PROP` in `src/Include/RiskDesk/Build.mqh` and move the `[Unreleased]` notes in `CHANGELOG.md` to a `## [x.y.z]` section, in one pull request. When it is merged, the workflow creates release `vx.y.z` with `RiskDesk-x.y.z.zip`, its `.sha256.txt` and the CHANGELOG section as notes. Following [SemVer](https://semver.org/), a version with a pre-release part such as `1.8.0-rc.1` is published as a pre-release (`RD_VERSION_PROP` stays `"1.80"`: MetaTrader's `#property version` has no room for a suffix).
- **Any other push to `main`** replaces the *Development build* pre-release (tag `dev`) with a build of that commit. It is untested.
- Builds that are not a release carry their commit in the version they report (SemVer build metadata, set on the runner only): `1.7.0+dev.abc1234` for a development build, `1.7.0+pr.12.abc1234` for pull request 12. A bug report then shows exactly which build was used.

`build/package-release.ps1` makes the same package locally, for example to check it before a release.

## Licence

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE) of this project.
