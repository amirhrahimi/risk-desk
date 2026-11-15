# Contributing to Risk Desk

Thank you for helping. Contributions of every size are welcome: a broker test report, a bug report with a log line, a documentation fix, or code.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) first. Risk Desk sends real orders, so the bar for changes to trading behaviour is high: **open an issue and discuss a change to order handling, lot sizing, risk checks or defaults before writing the code.**

## Ways to help

- **Broker test reports:** run Risk Desk with your broker on a demo account and open a [broker test report](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml). See [docs/broker-compatibility.md](docs/broker-compatibility.md#add-your-broker).
- **Bug reports:** use the [bug report](https://github.com/amirhrahimi/risk-desk/issues/new?template=bug_report.yml) template. The status-bar text and the Experts-tab lines are the most useful information.
- **Documentation:** corrections and clarifications are always welcome. Edit `README.md` or the file in `docs/`, not the [wiki](https://github.com/amirhrahimi/risk-desk/wiki): the wiki is generated from them when a change is merged, and edits made there are overwritten ([ADR-035](docs/design/adr/ADR-035-wiki-generated-from-the-docs.md)).
- **Code:** pick an issue, or propose one first. [ROADMAP.md](ROADMAP.md) lists planned work.

## Development setup

You need Git, PowerShell and at least one MetaTrader 4 and one MetaTrader 5 terminal (each with MetaEditor) logged in to **demo** accounts. Windows, macOS and Linux are supported:

| | PowerShell | MetaTrader |
|---|---|---|
| Windows | Windows PowerShell 5.1 (built in) or PowerShell 7 | the normal terminals |
| macOS | [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`) | under Wine: MetaQuotes' [MetaTrader 5 app for macOS](https://www.metatrader5.com/en/terminal/help/start_advanced/install_mac) |
| Linux | [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`) | under Wine: MetaQuotes' [`mt5linux.sh`](https://www.metatrader5.com/en/terminal/help/start_advanced/install_linux), or a current [WineHQ](https://gitlab.winehq.org/wine/wine/-/wikis/Download) Wine |

On macOS and Linux the build scripts start MetaEditor and the terminals through Wine ([ADR-032](docs/design/adr/ADR-032-development-on-macos-and-linux.md)). Clone the repository to a path **without spaces**, and run each command below as `pwsh build/<script>.ps1 ...` instead of `powershell -ExecutionPolicy Bypass -File build/<script>.ps1 ...`.

On Debian or Ubuntu, `bash build/install-metatrader-wine.sh --install-wine --paths-file build/paths.local.ps1` sets up what CI uses: WineHQ's Wine 11.21, MT4 and MT5 in the prefix `~/.wine-riskdesk`, and a paths file with the MetaEditor paths. Start each terminal once and log in to a demo account, then add its install folder to `$Terminals` in that file (`--help` lists the options).

Before the first build, start the terminal and MetaEditor once by hand, and again after installing or updating Wine. Wine's own first-run prompts (installing Mono or Gecko) would otherwise block the unattended start. If either program says **"A debugger has been found running in your system"**, MetaTrader refuses that Wine version, and MetaEditor would wait behind the message until the build's timeout. On Linux, WineHQ's Wine 11.21 worked with the prefix set to Windows 11 (`WINEPREFIX=~/.mt5 winecfg -v win11`). Ubuntu 24.04's own Wine 9.0 and WineHQ's Wine 10.0 did not.

1. Fork and clone the repository.
2. Copy `build/paths.example.ps1` to `build/paths.local.ps1` (git-ignored) and fill in the MetaEditor paths and your terminals' data folders. On Windows: **File → Open Data Folder** in each terminal. On macOS and Linux: the folder inside the Wine prefix that contains `MQL4`/`MQL5`; the template shows where MetaQuotes' installers put it, and `$Wine4`/`$Wine5` if the scripts don't find Wine on their own.
3. Link the sources into the terminals (`Include/RiskDesk` and `Scripts/RiskDesk`: directory junctions on Windows, symbolic links on macOS and Linux):
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

After changing a script in `build/`, run `build/test-build-scripts.ps1`. It checks the scripts without MetaTrader and changes nothing outside a temporary folder. CI runs it on Linux, macOS and Windows.

On macOS and Linux, two things work differently. The runners refuse to start while a terminal of the same kind (`terminal.exe` or `terminal64.exe`) is running under Wine in any prefix, because they close their own terminal with Wine's `taskkill` by program name. And the window captures that the self-test asks `run-uitest.ps1` for (the One-Click Trading panel) are Windows-only, so the runner skips them with a NOTE.

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

- **Every pull request and push** compiles the eight targets with MetaEditor 4 and 5 (0 errors, 0 warnings) and attaches the package to the workflow run, so reviewers can download and try it on a demo account. Two builds run in parallel, both with `build/build.ps1`: one on a Windows runner, whose package is the one attached and released, and one on a Linux runner with MetaEditor under Wine (`build/install-metatrader-wine.sh`; [ADR-033](docs/design/adr/ADR-033-ci-builds-on-linux-under-wine.md), [ADR-034](docs/design/adr/ADR-034-release-builds-on-windows-second-build-on-linux.md)). A failed Linux build marks the run as failed but does not hold back a release.
- **A new version:** maintainers bump `RD_VERSION` and `RD_VERSION_PROP` in `src/Include/RiskDesk/Build.mqh` and move the `[Unreleased]` notes in `CHANGELOG.md` to a `## [x.y.z]` section, in one pull request (`build.ps1` and CI fail when the two version values don't match, for example `1.8.0` with `"1.70"`). When it is merged, the workflow creates release `vx.y.z` with `RiskDesk-x.y.z.zip`, its `.sha256.txt` and the CHANGELOG section as notes. Following [SemVer](https://semver.org/), a version with a pre-release part such as `1.8.0-rc.1` is published as a pre-release (`RD_VERSION_PROP` stays `"1.80"`: MetaTrader's `#property version` has no room for a suffix).
- **Any other push to `main`** replaces the *Development build* pre-release (tag `dev`) with a build of that commit. It is untested.
- Builds that are not a release carry their commit in the version they report (SemVer build metadata, set on the runner only): `1.7.0+dev.abc1234` for a development build, `1.7.0+pr.12.abc1234` for pull request 12. A bug report then shows exactly which build was used.

`build/package-release.ps1` makes the same package locally, for example to check it before a release.

## Licence

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE) of this project.
