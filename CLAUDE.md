# CLAUDE.md — Risk Desk

> Read this file completely at the start of every session. It is the contract between you (Claude Code) and the project owner. Human contributors: see `CONTRIBUTING.md`; the rules below apply to you as well.

## 1. What we are building

Risk Desk (identifier `RiskDesk` in code, file names and object prefixes) is a chart-panel Expert Advisor for **MetaTrader 4 and MetaTrader 5** that:

- sizes a position from a **risk %** and a **stop-loss line** dragged on the chart,
- opens market and pending orders with one click,
- manages open trades (Risk Free / break-even, Half Close, Chart Close, Full Close, Delete Pending),
- and behaves **identically on every broker**. Target brokers: **IC Markets EU, Dukascopy, IG** (MT4 and MT5 where offered).

It is a clean-room reimplementation of the *behaviour* described in the public user guide of Map Manager by Mohammad Ali Poursamadi and team (summarised in `docs/design/01-product-requirements.md`; credits and what was taken from it in `NOTICE.md`). We have no access to that tool's code and must not try to get it.

It is a manual-trading tool. It never opens, modifies or closes anything unless the user clicks a button or drops a dragged line of a placed pending order (ADR-014).

The project is public and MIT-licensed (`LICENSE`, ADR-029). 1.7.0 was the first pre-release and 1.8.0-rc.1 the release candidate; 1.8.0 is the first stable release. The test work left over from it is in `ROADMAP.md`.

## 2. Read order (source of truth = `docs/design/`)

| # | File | Use it for |
|---|---|---|
| 1 | `docs/design/01-product-requirements.md` | Feature IDs (F-xx) and acceptance criteria |
| 2 | `docs/design/02-architecture.md` | Layers, folders, compile model, event flow, state |
| 3 | `docs/design/03-broker-compatibility.md` | Rules BC-xx. **Mandatory before writing any trade code** |
| 4 | `docs/design/04-risk-engine.md` | Formulas, rounding, test vectors (V-xx) |
| 5 | `docs/design/05-ui-spec.md` | Panel, lines, labels, interaction |
| 6 | `docs/design/06-trade-operations.md` | Algorithm for every button (OP-xx) |
| 7 | `docs/design/07-settings.md` | Every input parameter and its default |
| 8 | `docs/design/08-testing.md` | Unit tests, BrokerProbe, demo test matrix (T-xx) |
| 9 | `ROADMAP.md` | Planned work: the test work left over from 1.8.0, broker coverage, backlog |
| 10 | `docs/design/10-decisions.md` | Index of the ADRs (one file each in `docs/design/adr/`): why things are the way they are |
| 11 | `docs/design/11-open-questions.md` | Open questions, the owner's answers as decisions (Q-xx), assumed details (D-xx) |
| - | `broker-profiles/SUMMARY.md` | Account and test-symbol properties of every demo account, generated from the BrokerProbe/GatewaySmoke reports beside it |
| - | `README.md`, `docs/*.md` | User documentation, written from the design docs. Update it when behaviour, inputs or defaults change |

This table is a map, not a reading list: read only what the task names (§8).

When docs conflict, precedence is: 03 > 04 > 06 > 01 > the rest. Report every conflict you find.

## 3. Non-negotiable rules

- **R1 Clean room.** Never decompile, disassemble or inspect the original `.ex4/.ex5`, never search for its source, never reuse its logo, images or documentation text. Its name appears only in the attribution (`NOTICE.md`, the README credits, the source-file headers). The button and input names already taken from it are listed in `NOTICE.md`; do not add more of its wording. Never imply that its author endorses this project.
- **R2 One source tree, two targets.** Platform-specific code lives only in `src/Include/RiskDesk/Platform/`. `#ifdef __MQL5__` / `__MQL4__` is allowed only in: `Platform/*`, `App/Inputs.mqh`, the two EA entry files, the two script entry files. Everything else compiles unchanged under MQL4 and MQL5.
- **R3 No hard-coded broker properties.** Digits, point, tick size, tick value, contract size, volume min/max/step, stops/freeze level, filling policy, expiration mode, symbol names, account currency: read at runtime through `SymbolSpec` / `AccountSpec`.
- **R4 Normalization.** Prices are normalized to **tick size** (not only `Digits`). Volumes are normalized **down** to the volume step. See BC-03, BC-04.
- **R5 Never exceed requested risk.** Lot size rounds down. If the minimum lot would exceed the risk, refuse with an explanation (unless the setting explicitly allows it).
- **R6 Single trade gateway.** All trading goes through `CTradeGateway`. No `OrderSend`, `OrderClose`, `OrderModify`, `OrderDelete` anywhere else. Do not use the MT5 Standard Library (`Trade\*`, `Controls\*`).
- **R7 Never leave a RiskDesk position without its stop-loss.** If attaching the SL fails after retries, close the position (`InpCloseIfStopFails=true`) and report loudly.
- **R8 No silent failures.** Every click ends with a status message on the panel (green = done, amber = partial/skipped, red = refused/failed, with the reason) **and** a log line. A silent failure is the defect this tool exists to avoid.
- **R9 No blind resend.** After an ambiguous result (timeout, connection lost, no reply) never resend before checking whether the first request was executed (BC-14).
- **R10 Self-contained.** No DLLs, no WebRequest, no external libraries. File I/O only under `MQL4/Files/RiskDesk/` or `MQL5/Files/RiskDesk/`.
- **R11 Clean builds.** After every change both targets compile with **0 errors and 0 warnings**. `#property strict` in every MQL4 entry file.
- **R12 Docs are not edited silently.** If the implementation reveals a gap, add it to `docs/design/11-open-questions.md` or write a new ADR (`docs/design/adr/ADR-NNN-<slug>.md` plus a row at the end of `docs/design/10-decisions.md`), and mention it in your summary.
- **R13 Demo-only test trading.** Test scripts that place orders must abort unless `AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO`.
- **R14 No account data in the repository.** Never commit logins, passwords, investor passwords, account statements, local paths or screenshots that show account data. BrokerProbe/GatewaySmoke reports are committed only after `build/redact-report.ps1` (login → account label, `data_path` blanked). Never commit `.ex4/.ex5`; release binaries go to GitHub Releases.

## 4. Repository layout

```
/
├─ CLAUDE.md  README.md  CHANGELOG.md  ROADMAP.md  LICENSE  NOTICE.md
├─ CONTRIBUTING.md  CODE_OF_CONDUCT.md  SECURITY.md  SUPPORT.md
├─ .github/                    issue templates, PR template, workflows (MT4+MT5 build and releases, docs link check)
├─ docs/                       user documentation (installation, user guide, configuration, ...)
│  └─ design/                  specifications 01-08, 10, 11 (see rule R12)
│     └─ adr/                  one file per ADR, indexed by 10-decisions.md
├─ broker-profiles/            SUMMARY.md (generated) + redacted BrokerProbe/GatewaySmoke reports
├─ build/
│  ├─ build.ps1                compiles every target, prints a summary, exit 1 on any error/warning
│  ├─ host.ps1                 Windows vs macOS/Linux+Wine helpers dot-sourced by the scripts (ADR-032)
│  ├─ install-metatrader-wine.sh  Linux: Wine + MT4/MT5 in one prefix, used by CI (ADR-033)
│  ├─ test-build-scripts.ps1   checks the build scripts without MetaTrader (CI: scripts.yml)
│  ├─ check-version.ps1        RD_VERSION and RD_VERSION_PROP must match (run by build.ps1 and CI)
│  ├─ package-release.ps1      release build + zip for GitHub Releases (dist/, git-ignored)
│  ├─ install-junctions.ps1    links src/ into each terminal data folder (junctions; symlinks on macOS/Linux)
│  ├─ run-tests.ps1            RiskDeskTests headless on each terminal
│  ├─ run-script.ps1           BrokerProbe / GatewaySmoke on one demo account
│  ├─ run-uitest.ps1           debug panel/trade/pending self-test on one demo account
│  ├─ profile-guard.ps1        chart-profile snapshot/restore used by the runners
│  ├─ redact-report.ps1        removes the login and the data path from a report
│  ├─ summarize-profiles.ps1   regenerates broker-profiles/SUMMARY.md
│  ├─ paths.example.ps1        template (committed)
│  └─ paths.local.ps1          real paths (git-ignored)
└─ src/
   ├─ Experts/RiskDesk.mq4      (no sub-folder: the EA sits in the Experts root, ADR-028)
   ├─ Experts/RiskDesk.mq5
   ├─ Scripts/RiskDesk/BrokerProbe.mq4   BrokerProbe.mq5
   ├─ Scripts/RiskDesk/RiskDeskTests.mq4 RiskDeskTests.mq5
   ├─ Scripts/RiskDesk/GatewaySmoke.mq4  GatewaySmoke.mq5   (demo-only, rule R13)
   └─ Include/RiskDesk/
      ├─ Build.mqh  product name, version, copyright, link, test-hooks switch
      ├─ Platform/  Compat.mqh  SymbolSpec.mqh  AccountSpec.mqh  Market.mqh  Money.mqh
      │             TradeGateway.mqh  TradeGatewayMT4.mqh  TradeGatewayMT5.mqh  History.mqh
      ├─ Domain/    Types.mqh  PriceMath.mqh  RiskMath.mqh  Validators.mqh  Planner.mqh  RiskBudget.mqh
      ├─ App/       Inputs.mqh  Settings.mqh  State.mqh  App.mqh  Controller.mqh  Commands.mqh
      ├─ UI/        Theme.mqh  Layout.mqh  Widgets.mqh  Panel.mqh  Lines.mqh  PendingOverlay.mqh  StatusBar.mqh
      └─ Services/  Logger.mqh  Persistence.mqh  Screenshot.mqh  ChartHousekeeping.mqh  CandleTime.mqh
```

Includes are **relative** to the including file, using backslashes as in MetaQuotes' examples, e.g. in `src/Experts/RiskDesk.mq5`: `#include "..\Include\RiskDesk\App\App.mqh"`, in `src/Scripts/RiskDesk/BrokerProbe.mq5`: `#include "..\..\Include\RiskDesk\..."`. The same tree then compiles both from the repo and through the junctions inside each terminal's data folder. Scripts and includes reach the terminals through junctions; the EA is compiled in the repo and `build.ps1` copies `RiskDesk.ex4/.ex5` into the root of each terminal's `MQLx\Experts` (ADR-028).

## 5. Build and run

- Paths live in `build/paths.local.ps1` (MetaEditor executables and the data folder of every terminal). If it is missing, create it from `paths.example.ps1` and ask the owner to fill it.
- Compile everything: `powershell -ExecutionPolicy Bypass -File build/build.ps1` (or `-Target mt4` / `-Target mt5`). On macOS and Linux every script runs as `pwsh build/<script>.ps1` and starts MetaEditor and the terminals through Wine (ADR-032).
- Underlying commands (build.ps1 wraps them):
  - MT5: `"<MT5 dir>\metaeditor64.exe" /compile:"<repo>\src\Experts\RiskDesk.mq5" /log`
  - MT4: `"<MT4 dir>\metaeditor.exe" /compile:"<repo>\src\Experts\RiskDesk.mq4" /log`
  - Wine: `WINEPREFIX=<prefix> wine "<prefix>/drive_c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:Z:\<repo path with backslashes>\src\Experts\RiskDesk.mq5 /log`
  - build.ps1 then copies the compiled EA to `MQLx\Experts\RiskDesk.ex4/.ex5` of every terminal in `paths.local.ps1`; a compile done by hand does not.
  - The `.log` file is written next to the source file. **Do not trust MetaEditor's exit code.** Parse the log (it may be UTF-16 encoded) for the final `N errors, M warnings` result.
  - `.ex4/.ex5/.log` are build artefacts and are git-ignored.
- Release zip: `powershell -ExecutionPolicy Bypass -File build/package-release.ps1` (release build, then `dist/RiskDesk-<version>.zip`).
- CI (`.github/workflows/build.yml`) compiles the eight targets with MetaEditor 4 and 5 on every pull request and push, twice and in parallel, both times with `build.ps1`: on `windows-latest`, the build that is released, and on `ubuntu-24.04` under Wine (`build/install-metatrader-wine.sh`, pinned Wine version, ADR-033), which never holds back a release (ADR-034). Once the Windows build has passed, a push to `main` publishes release `v<RD_VERSION>` when that version has none yet (it needs a `## [x.y.z]` section in `CHANGELOG.md`; a SemVer pre-release version such as `1.8.0-rc.1` becomes a GitHub pre-release), otherwise it replaces the `dev` pre-release. Releasing = bump the version and the CHANGELOG in one commit and push it to `main`. Builds that are not a release report `<version>+dev.<commit>` or `<version>+pr.<n>.<commit>` (set on the runner only, ADR-030).
- You cannot click inside MetaTrader. For runtime verification give the owner a short numbered list of test IDs (T-xx from `docs/design/08-testing.md`) and ask for the relevant Experts-tab log lines and status-bar texts.

## 6. Coding standards (MQL4/MQL5 common subset)

- Every source file starts with the five-line licence comment (product, `SPDX-License-Identifier: MIT`, copyright, credit to the original; ADR-029), then the header box stating purpose and owning layer.
- Naming: classes `CName`, structs `SName`, enums `ENameType` with values `NAME_VALUE`, members `m_name`, globals `g_name`, inputs `InpName`, constants/macros `RD_NAME`.
- One class per file where reasonable; keep files under ~600 lines. Sources are ASCII (ADR-018).
- `Domain/` has **no terminal calls at all** (no `SymbolInfo*`, `Account*`, `Object*`, `Print`, `TimeCurrent`). Pure functions over structs, so it is unit-testable.
- No global mutable state outside `App/State.mqh`.
- Functions that can fail return `bool` and fill an `SResult &out` whose `message` is plain English suitable for the status bar.
- Never compare doubles with `==`. Use the helpers in `Domain/PriceMath.mqh` (`PriceEq`, `PriceLt`, ... with half-tick tolerance; volume helpers with 1e-8 tolerance).
- Chart objects: every name starts with `RD_`. Panel objects: `OBJPROP_HIDDEN=true`, `OBJPROP_SELECTABLE=false`, high `OBJPROP_ZORDER`. Trade lines are selectable and not hidden.
- Logging via `Services/Logger.mqh` macros. Every trade request and result is logged with symbol, side, volume, price, SL, TP, filling/time policy, retcode/error number and its text.
- Keep `CHANGELOG.md` (Keep a Changelog, SemVer). For a release bump `RD_VERSION` and `RD_VERSION_PROP` in `Build.mqh` together (ADR-029); `build/check-version.ps1` fails the build when they differ.
- Every new or changed input is documented in its trailing comment, in `docs/design/07-settings.md` and in `docs/configuration.md`.
- Build scripts (`build/*.ps1`) run on Windows PowerShell 5.1 and on PowerShell 7 under Windows, macOS and Linux (ADR-032): file paths joined with forward slashes (`Join-Path $data "$mql/Files"`), no `$env:TEMP` (use `Get-RdTempDir`), and programs started, found and closed only through the helpers in `build/host.ps1`. Paths inside a terminal's startup `.ini` (`Script=RiskDesk\RiskDeskTests`) stay Windows paths.

## 7. How to work in a session

1. Restate the goal and list the files you will create or touch.
2. Implement in small steps; run `build.ps1` after each step and fix warnings immediately.
3. Add or extend unit tests for any `Domain/` change (`RiskDeskTests` scripts).
4. End every session with: summary, files changed, compile result for both targets, the manual test list (T-xx) the owner should run, and open questions.
5. Commit only when the owner asks; use Conventional Commits (`feat(gateway): ...`, `fix(risk): ...`, `docs: ...`, `chore(build): ...`).

## 8. Context budget

A session runs out of context long before it runs out of work: the design docs are ~230 KB, the source ~950 KB, the raw probe reports ~530 KB. Read in proportion to the task.

- **Docs: only the sections the task names.** Prompts name sections (`docs/design/03 BC-07`, `06 OP-05..OP-08`, `05 §5`). Grep for the heading (`^### BC-07`, `^### OP-05`, `^## 5\.`; rows such as V-xx or T-xx with `^\| T-13 \|`) and Read only that range with `offset`/`limit`. Read a whole doc only when the prompt says "all of it" or "entirely".
- **Broker data: `broker-profiles/SUMMARY.md`.** For a property or symbol it lacks, Grep the raw probe for `^\[symbol NAME\]` and read that section (about 60 lines). Never read a whole `probe_*.txt` (~90 KB each), even where an older prompt says "every file in broker-profiles/". After adding a probe or smoke report, redact it (`build/redact-report.ps1`) and run `build/summarize-profiles.ps1`.
- **Decisions:** the index `docs/design/10-decisions.md`, then only the ADR files the task names or changes. In `docs/design/11-open-questions.md`, Grep for the Q-xx/D-xx IDs you need. The released sections of `CHANGELOG.md` are history: don't read them to implement anything. To add a CHANGELOG entry, Read only its first ~20 lines (the `[Unreleased]` section).
- **Source:** Grep for the class or function first and Read the matching range; many files are 20–37 KB. Don't open `App/UiSelfTest*.mqh` unless the task changes a self-test suite.
- **Test output is short by design.** `run-uitest.ps1` prints the header, INFO lines, each FAIL with its screenshot and the SUMMARY (`-Full` prints the whole report). `run-script.ps1` prints the last run's FAIL/SKIP rows and `[summary]`. `run-tests.ps1` prints PASS or the FAIL lines. Open a full report or a screenshot only to investigate a failure.
- **Builds:** `build.ps1` prints the issues it found. Open a MetaEditor `.log` only if that is not enough.
