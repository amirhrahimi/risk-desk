# CLAUDE.md — RiskDesk

> Read this file completely at the start of every session. It is the contract between you (Claude Code) and the project owner.

## 1. What we are building

RiskDesk is a chart-panel Expert Advisor for **MetaTrader 4 and MetaTrader 5** that:

- sizes a position from a **risk %** and a **stop-loss line** dragged on the chart,
- opens market and pending orders with one click,
- manages open trades (Risk Free / break-even, Half Close, Chart Close, Full Close, Delete Pending),
- and behaves **identically on every broker**. Target brokers: **IC Markets EU, Dukascopy, IG** (MT4 and MT5 where offered).

It is a clean-room reimplementation of the *behaviour* described in a freeware tool's user guide (summarised in `docs/01-product-requirements.md`). We have no access to that tool's code and must not try to get it.

It is a manual-trading tool. It never opens, modifies or closes anything unless the user clicks a button or drops a dragged line of a placed pending order (ADR-014).

## 2. Read order (source of truth = `docs/`)

| # | File | Use it for |
|---|---|---|
| 1 | `docs/01-product-requirements.md` | Feature IDs (F-xx) and acceptance criteria |
| 2 | `docs/02-architecture.md` | Layers, folders, compile model, event flow, state |
| 3 | `docs/03-broker-compatibility.md` | Rules BC-xx. **Mandatory before writing any trade code** |
| 4 | `docs/04-risk-engine.md` | Formulas, rounding, test vectors (V-xx) |
| 5 | `docs/05-ui-spec.md` | Panel, lines, labels, interaction |
| 6 | `docs/06-trade-operations.md` | Algorithm for every button (OP-xx) |
| 7 | `docs/07-settings.md` | Every input parameter and its default |
| 8 | `docs/08-testing.md` | Unit tests, BrokerProbe, demo test matrix (T-xx) |
| 9 | `docs/09-roadmap-and-prompts.md` | Phases and their Definition of Done |
| 10 | `docs/10-decisions.md` | Index of the ADRs (one file each in `docs/adr/`): why things are the way they are |
| 11 | `docs/11-open-questions.md` | Open questions, the owner's answers as decisions (Q-xx), assumed details (D-xx) |
| - | `broker-profiles/SUMMARY.md` | Account and test-symbol properties of every demo account, generated from the BrokerProbe/GatewaySmoke reports beside it |

This table is a map, not a reading list: read only what the task names (§8).

When docs conflict, precedence is: 03 > 04 > 06 > 01 > the rest. Report every conflict you find.

## 3. Non-negotiable rules

- **R1 Clean room.** Never decompile, disassemble or inspect the original `.ex4/.ex5`, never search for its source, never reuse its name, logo, texts or images.
- **R2 One source tree, two targets.** Platform-specific code lives only in `src/Include/RiskDesk/Platform/`. `#ifdef __MQL5__` / `__MQL4__` is allowed only in: `Platform/*`, `App/Inputs.mqh`, the two EA entry files, the two script entry files. Everything else compiles unchanged under MQL4 and MQL5.
- **R3 No hard-coded broker properties.** Digits, point, tick size, tick value, contract size, volume min/max/step, stops/freeze level, filling policy, expiration mode, symbol names, account currency: read at runtime through `SymbolSpec` / `AccountSpec`.
- **R4 Normalization.** Prices are normalized to **tick size** (not only `Digits`). Volumes are normalized **down** to the volume step. See BC-03, BC-04.
- **R5 Never exceed requested risk.** Lot size rounds down. If the minimum lot would exceed the risk, refuse with an explanation (unless the setting explicitly allows it).
- **R6 Single trade gateway.** All trading goes through `CTradeGateway`. No `OrderSend`, `OrderClose`, `OrderModify`, `OrderDelete` anywhere else. Do not use the MT5 Standard Library (`Trade\*`, `Controls\*`).
- **R7 Never leave a RiskDesk position without its stop-loss.** If attaching the SL fails after retries, close the position (`InpCloseIfStopFails=true`) and report loudly.
- **R8 No silent failures.** Every click ends with a status message on the panel (green = done, amber = partial/skipped, red = refused/failed, with the reason) **and** a log line. Silent failure is the main defect of the tool we are replacing.
- **R9 No blind resend.** After an ambiguous result (timeout, connection lost, no reply) never resend before checking whether the first request was executed (BC-14).
- **R10 Self-contained.** No DLLs, no WebRequest, no external libraries. File I/O only under `MQL4/Files/RiskDesk/` or `MQL5/Files/RiskDesk/`.
- **R11 Clean builds.** After every change both targets compile with **0 errors and 0 warnings**. `#property strict` in every MQL4 entry file.
- **R12 Docs are not edited silently.** If the implementation reveals a gap, add it to `docs/11-open-questions.md` or write a new ADR (`docs/adr/ADR-NNN-<slug>.md` plus a row at the end of `docs/10-decisions.md`), and mention it in your summary.
- **R13 Demo-only test trading.** Test scripts that place orders must abort unless `AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO`.

## 4. Repository layout

```
/
├─ CLAUDE.md  README.md  CHANGELOG.md  .gitignore
├─ docs/                       specifications (see rule R12)
│  ├─ adr/                     one file per ADR, indexed by 10-decisions.md
│  └─ history/                 implementation-log.md: history only, not needed to implement
├─ broker-profiles/            SUMMARY.md (generated) + BrokerProbe/GatewaySmoke reports from the owner's terminals
├─ build/
│  ├─ build.ps1                compiles every target, prints a summary, exit 1 on any error/warning
│  ├─ install-junctions.ps1    links src/ into each terminal data folder
│  ├─ run-tests.ps1            RiskDeskTests headless on each terminal
│  ├─ run-script.ps1           BrokerProbe / GatewaySmoke on one demo account
│  ├─ run-uitest.ps1           debug panel/trade/pending self-test on one demo account
│  ├─ profile-guard.ps1        chart-profile snapshot/restore used by the runners
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
- Compile everything: `powershell -ExecutionPolicy Bypass -File build/build.ps1` (or `-Target mt4` / `-Target mt5`).
- Underlying commands (build.ps1 wraps them):
  - MT5: `"<MT5 dir>\metaeditor64.exe" /compile:"<repo>\src\Experts\RiskDesk.mq5" /log`
  - MT4: `"<MT4 dir>\metaeditor.exe" /compile:"<repo>\src\Experts\RiskDesk.mq4" /log`
  - build.ps1 then copies the compiled EA to `MQLx\Experts\RiskDesk.ex4/.ex5` of every terminal in `paths.local.ps1`; a compile done by hand does not.
  - The `.log` file is written next to the source file. **Do not trust MetaEditor's exit code.** Parse the log (it may be UTF-16 encoded) for the final `N errors, M warnings` result.
  - `.ex4/.ex5/.log` are build artefacts and are git-ignored.
- You cannot click inside MetaTrader. For runtime verification give the owner a short numbered list of test IDs (T-xx from `docs/08-testing.md`) and ask for the relevant Experts-tab log lines and status-bar texts.

## 6. Coding standards (MQL4/MQL5 common subset)

- Naming: classes `CName`, structs `SName`, enums `ENameType` with values `NAME_VALUE`, members `m_name`, globals `g_name`, inputs `InpName`, constants/macros `RD_NAME`.
- One class per file where reasonable; header comment stating purpose and owning layer; keep files under ~600 lines.
- `Domain/` has **no terminal calls at all** (no `SymbolInfo*`, `Account*`, `Object*`, `Print`, `TimeCurrent`). Pure functions over structs, so it is unit-testable.
- No global mutable state outside `App/State.mqh`.
- Functions that can fail return `bool` and fill an `SResult &out` whose `message` is plain English suitable for the status bar.
- Never compare doubles with `==`. Use the helpers in `Domain/PriceMath.mqh` (`PriceEq`, `PriceLt`, ... with half-tick tolerance; volume helpers with 1e-8 tolerance).
- Chart objects: every name starts with `RD_`. Panel objects: `OBJPROP_HIDDEN=true`, `OBJPROP_SELECTABLE=false`, high `OBJPROP_ZORDER`. Trade lines are selectable and not hidden.
- Logging via `Services/Logger.mqh` macros. Every trade request and result is logged with symbol, side, volume, price, SL, TP, filling/time policy, retcode/error number and its text.
- Keep `CHANGELOG.md` (Keep a Changelog style) and bump `#property version` at the end of each phase.

## 7. How to work in a session

1. Restate the phase goal and list the files you will create or touch.
2. Implement in small steps; run `build.ps1` after each step and fix warnings immediately.
3. Add or extend unit tests for any `Domain/` change (`RiskDeskTests` scripts).
4. End every session with: summary, files changed, compile result for both targets, the manual test list (T-xx) the owner should run, and open questions.
5. Commit only when the owner asks; use messages like `phase-4: market orders with risk sizing`.

## 8. Context budget

A session runs out of context long before it runs out of work: the docs are ~240 KB, the source ~940 KB, the raw probe reports ~590 KB. Read in proportion to the task.

- **Docs: only the sections the task names.** Prompts name sections (`docs/03 BC-07`, `docs/06 OP-05..OP-08`, `docs/05 §5`). Grep for the heading (`^### BC-07`, `^### OP-05`, `^## 5\.`; rows such as V-xx or T-xx with `^\| T-13 \|`) and Read only that range with `offset`/`limit`. Read a whole doc only when the prompt says "all of it" or "entirely".
- **Broker data: `broker-profiles/SUMMARY.md`.** For a property or symbol it lacks, Grep the raw probe for `^\[symbol NAME\]` and read that section (about 60 lines). Never read a whole `probe_*.txt` (~90 KB each), even where an older prompt says "every file in broker-profiles/". After adding a probe or smoke report, run `build/summarize-profiles.ps1`.
- **Decisions:** the index `docs/10-decisions.md`, then only the ADR files the task names or changes. In `docs/11-open-questions.md`, Grep for the Q-xx/D-xx IDs you need. `docs/history/implementation-log.md` and the released sections of `CHANGELOG.md` are history: don't read them to implement anything. To add a CHANGELOG entry, Read only its first ~20 lines (the `[Unreleased]` section).
- **Source:** Grep for the class or function first and Read the matching range; many files are 20–37 KB. Don't open `App/UiSelfTest*.mqh` unless the task changes a self-test suite.
- **Test output is short by design.** `run-uitest.ps1` prints the header, INFO lines, each FAIL with its screenshot and the SUMMARY (`-Full` prints the whole report). `run-script.ps1` prints the last run's FAIL/SKIP rows and `[summary]`. `run-tests.ps1` prints PASS or the FAIL lines. Open a full report or a screenshot only to investigate a failure.
- **Builds:** `build.ps1` prints the issues it found. Open a MetaEditor `.log` only if that is not enough.
