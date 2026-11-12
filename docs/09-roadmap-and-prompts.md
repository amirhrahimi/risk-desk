# 09 — Roadmap and Prompts

Eight phases after a bootstrap. Each phase is one Claude Code session (or a few), ends with both targets compiling cleanly, and has a copy-paste prompt. Do them in order: each phase relies on the previous one.

```
P0 Bootstrap + BrokerProbe ─▶ P1 Domain + unit tests ─▶ P2 Platform + GatewaySmoke ─▶ P3 UI shell
   ─▶ P4 Market orders ─▶ P5 Pending orders ─▶ P6 Trade management ─▶ P7 Extras ─▶ P8 Hardening & release
```

Why this order: the probe (P0) and the gateway smoke test (P2) tell us how each broker behaves **before** any UI exists, so broker problems surface early and in isolation. The UI is built last on top of tested math and a tested gateway.

---

## P0 — Bootstrap and diagnostics
**Goal:** repository skeleton that compiles on both platforms, build tooling, and the BrokerProbe.
**Deliverables:** folder tree per CLAUDE.md §4 with stub files; `.gitignore`; `CHANGELOG.md`; `build/paths.example.ps1`, `build/build.ps1`, `build/install-junctions.ps1`; `Platform/Compat.mqh`, `Platform/SymbolSpec.mqh`, `Platform/AccountSpec.mqh`; `Domain/Types.mqh`; `Services/Logger.mqh`; EA shells that only log version/account/symbol info; `BrokerProbe.mq4/.mq5` complete (08 §3).
**Done when:** build.ps1 reports 0/0 for all four entry files on both platforms; the owner has run the probe on A1–A5 and committed the reports.
**Owner actions:** fill `build/paths.local.ps1`; run `install-junctions.ps1`; run BrokerProbe on each account; copy reports to `broker-profiles/`; record the original tool's errors in `broker-profiles/original-tool-errors.md`.

```text
Read CLAUDE.md, then docs/02-architecture.md, docs/03-broker-compatibility.md and docs/08-testing.md §3.
Implement phase P0 from docs/09-roadmap-and-prompts.md:
1. Create the repository layout exactly as in CLAUDE.md §4 with compiling stubs.
2. Write build/build.ps1: compiles every .mq4 (with the MT4 MetaEditor) and every .mq5 (with the MT5 MetaEditor) under src/Experts and src/Scripts, using MetaEditor's /compile and /log switches, decodes the .log (it may be UTF-16), prints a one-line result per file and exits 1 on any error or warning. Paths come from build/paths.local.ps1 (create paths.example.ps1 as a template with comments). Support -Target mt4|mt5|all and -Debug (adds RD_TEST_HOOKS).
3. Write build/install-junctions.ps1: for every terminal data folder listed in paths.local.ps1, create directory junctions MQLx\Experts\RiskDesk, MQLx\Scripts\RiskDesk, MQLx\Include\RiskDesk pointing to the repo's src folders; idempotent; prints what it did.
4. Implement Platform/Compat.mqh, Platform/SymbolSpec.mqh, Platform/AccountSpec.mqh (BC-02 sanity checks), Domain/Types.mqh, Services/Logger.mqh.
5. Implement BrokerProbe.mq4/.mq5 per docs/08-testing.md §3, including the MT5 OrderCheck filling/expiration checks (no orders are executed).
6. EA shells: on init, log version, platform, account (currency, leverage, margin mode) and the chart symbol's spec, nothing else.
Compile both platforms until clean. Then give me: the exact steps to fill paths.local.ps1 and run the junction script, how to run BrokerProbe, and where the report files will be.
```

## P1 — Domain and unit tests
**Goal:** all money/price/volume logic, pure and tested.
**Deliverables:** `Domain/PriceMath.mqh`, `RiskMath.mqh`, `Validators.mqh`, `Planner.mqh`, `RiskBudget.mqh`; `RiskDeskTests.mq4/.mq5` covering V-01…V-24 plus validator edge cases.
**Done when:** tests compile on both platforms and the owner reports "N passed, 0 failed" on MT4 and MT5.

```text
Read CLAUDE.md, docs/04-risk-engine.md (all of it), docs/03-broker-compatibility.md BC-03/BC-04/BC-07, docs/02-architecture.md §6.
Implement phase P1: the pure Domain layer (PriceMath, RiskMath, Validators, Planner, RiskBudget) with no terminal calls, and the RiskDeskTests scripts for MT4 and MT5 that implement every test vector V-01..V-24 from docs/04-risk-engine.md §12 plus extra edge cases you consider necessary.
Rules: FloorVolume must use the +1e-8 epsilon; never round lots up; all functions return bool + SResult with plain-English messages.
Compile both targets clean. Tell me how to run the tests and what output to paste back.
```

## P2 — Platform layer and GatewaySmoke
**Goal:** a gateway that trades correctly on every account, proven before the UI exists.
**Deliverables:** `Platform/Market.mqh`, `Money.mqh` (BC-05 incl. MT4 cross-check), `TradeGateway.mqh` + `TradeGatewayMT4.mqh` + `TradeGatewayMT5.mqh` (G-01…G-08 with BC-06/07/08/09/10/11/13/14/16), `History.mqh` (stub ok); `Scripts/RiskDesk/GatewaySmoke.mq4/.mq5` (demo-only, R13): on the chart symbol, with the smallest volume (2 × min lot when the risk guard allows, so the partial close is divisible; ADR-019) and safe distances: open buy with SL/TP → verify → modify SL → partial close (if divisible) → close; place buy limit far from price → modify price/SL/TP → delete; prints a PASS/FAIL table.
**Done when:** GatewaySmoke passes on A1–A5 (and A6 netting for the netting path).

```text
Read CLAUDE.md, docs/03-broker-compatibility.md (entirely), docs/06-trade-operations.md §5–6, docs/02-architecture.md §9, and every file in broker-profiles/.
Implement phase P2: Platform/Market.mqh, Money.mqh, TradeGateway (MT4 and MT5 implementations with the same public API), and the GatewaySmoke scripts described in docs/09 P2. Implement every BC rule that applies to the gateway, including the filling and expiration ladders, stops/freeze checks, SL verification with close-on-failure, retries and the ambiguous-result check. Map every retcode/error to the messages in docs/03 §5.
Before coding, list any property in broker-profiles/ that contradicts the spec and propose how to handle it.
Compile clean, then give me a short run sheet for GatewaySmoke on each account (A1–A6) and what to paste back.
```

## P3 — UI shell
**Goal:** the panel, without trading.
**Deliverables:** `UI/Theme`, `Layout`, `Widgets`, `Panel`, `StatusBar`; `Services/Persistence`; `App/Inputs`, `Settings`, `State`, `Controller`, `App`; risk field with validation and persistence; spread; live prices on Buy/Sell; drag, hide, clamp, DPI scale, auto-fit (F-34); font presets; original colour inputs; button tooltips; tester button polling; every trading button currently shows amber "Not implemented yet".
**Done when:** T-01, T-02, T-20 (panel part), T-21, T-24, T-37 pass on one MT4 and one MT5 account.

```text
Read CLAUDE.md, docs/05-ui-spec.md, docs/07-settings.md, docs/02-architecture.md §5, §7, §8, §10, §11.
Implement phase P3: the complete panel UI and app skeleton without trading. Include all inputs from docs/07-settings.md (even ones used later), settings validation, persistence (ui.ini, acct_<login>.ini), drag/hide/clamp, DPI scaling, auto-fit to chart size (F-34), font presets, tooltips, status bar with idle readout, spread display, live prices on Buy/Sell, busy/cooldown guard in the Controller, and Strategy Tester button polling. Trading buttons show an amber "Not implemented yet" message.
Compile clean and give me the T-xx list to run (include T-37).
```

## P4 — Market orders
**Goal:** Add Line, Delete Line, Lots preview, Buy, Sell with full risk logic.
**Deliverables:** `UI/Lines.mqh` (market mode, labels, manual-deletion detection), commands OP-01/02/03/04/15, caps (F-16), commission (F-30), margin (F-31), open-risk readout (F-29), dim invalid side (F-33), `Services/Screenshot.mqh` (basic naming). Added in P4 (ADR-022): the pending-mode lines and display of OP-05 Add Pend Line and OP-06 Pending Info (T-03 needs Add Pend Line), and the camera button (OP-14, already promised by the P3 panel).
**Done when:** T-03…T-12, T-25…T-28 pass on A1–A5.

```text
Read CLAUDE.md, docs/01 (F-03..F-06, F-16..F-18, F-29..F-31, F-33), docs/04, docs/05 §5, docs/06 §0–2, docs/03 BC-09/BC-10/BC-11.
Implement phase P4: market-mode lines and labels, live Lots preview, Add Line / Delete Line / Buy / Sell commands with risk sizing, per-trade and total risk caps, commission, margin pre-check, netting confirmations, open-risk readout, invalid-side dimming and post-trade screenshots.
Every refusal must name the reason and the numbers. Compile clean and give me the T-xx list (T-03..T-12, T-25..T-28) with expected results for each account.
```

## P5 — Pending orders
**Deliverables:** pending order overlay with drag-to-modify (`UI/PendingOverlay.mqh`, F-22, OP-16), OP-07/08. (Pending mode in Lines, OP-05 Add Pend Line and OP-06 Pending Info were done in P4, ADR-022; P5 adds the order placement to them.)
**Done when:** T-13…T-15, T-23, T-39 pass on A1–A5.
**Done in P5 (ADR-025):** besides the deliverables, the debug pending self-test (08 §3f) that runs T-13…T-15, T-23, T-39, F-22 and the pending part of T-08 unattended; `build/profile-guard.ps1` so unattended runs leave the terminal's charts as they were. T-23 is checked with `InpPendingExpiryHours=24`: no account has a symbol without GTC.

```text
Read CLAUDE.md, docs/01 (F-07..F-10, F-22), docs/04 §7, docs/05 §5, docs/06 OP-05..OP-08, OP-16 and G-02/G-05/G-07/G-08, docs/03 BC-07/BC-08.
Implement phase P5: Add Pend Line, Pending Info (live classification), Set Pending and Del Pending, with the expiration ladder and stops-level refusals, plus the draggable pending order overlay (F-22, OP-16, docs/05 §6). Compile clean and give me T-13..T-15, T-23 and T-39 run instructions.
```

## P6 — Trade management
**Deliverables:** OP-09/10/11/12, scopes, confirmations (F-28), netting paths, progress messages.
**Done when:** T-16…T-19, T-30, T-32 pass.

```text
Read CLAUDE.md, docs/01 (F-11..F-14, F-28), docs/04 §9–10, docs/06 §3, docs/03 BC-07/BC-10/BC-16.
Implement phase P6: Risk Free, Half Close, Chart Close and Full Close with scopes, confirmations, netting behaviour, freeze-level checks and per-item summaries. Compile clean and give me T-16..T-19, T-30, T-32 instructions.
```

## P7 — Extras
**Deliverables:** closed trade objects keep/remove (F-20, `Services/ChartHousekeeping.mqh`), candle time (F-21, per the answer to Q4), cent display (F-24), final screenshot naming and camera button (F-19), log file rotation (F-32).
**Done when:** T-31, T-33, T-34 pass.

```text
Read CLAUDE.md, docs/01 (F-19..F-21, F-24, F-32), docs/05 §6, docs/11-open-questions.md (use the owner's answers).
Implement phase P7 extras. For F-20 on MT4, first ask me for a screenshot of the object list (Ctrl+B) on a chart with closed trades, and match only those object names. Keep each overlay fully optional and cheap when disabled. Compile clean and list T-31, T-33, T-34.
```

## P8 — Hardening and release
**Deliverables:** fixes from the full matrix; debug build with test hooks (T-29, T-35); short user guide `docs/USER-GUIDE.md`; release zip; version 1.0.0.

```text
Read CLAUDE.md and docs/08-testing.md §5 and §7. Here are the results of the full test matrix: <paste>.
Fix every failure, add a regression unit test where the bug was in Domain, implement the RD_TEST_HOOKS debug build for T-29 and T-35, write docs/USER-GUIDE.md (one page per button, in plain English), and produce the release zip described in §7. Then run a self-review of TradeGateway against the checklist in docs/03 §6 and report anything still open.
```

---

## 10. Tips for working with Claude Code on this project
- One phase per session; start a fresh session (`/clear`) between phases. Always begin with "Read CLAUDE.md…" as in the prompts.
- For P2, P4 and P6 ask for a plan first ("make a plan, don't code yet"), review it, then let it implement.
- Commit after every phase (`git add -A && git commit -m "phase-N: …"`), so you can roll back.
- Paste real log lines, not descriptions. Use the bug template in `08-testing.md` §6.
- Never test on a live account. All accounts in the matrix are demo.
- When a broker surprises you, run BrokerProbe again and commit the new report before asking for a fix.

## 11. Backlog (v1.x candidates)
Hotkeys; manual lot override; trade history overlay drawn by RiskDesk (entry/exit markers with P/L); multiple take-profits / scale-out plan; trailing stop; MT5 stop-limit orders; saved setting profiles; UI translations (e.g. Persian); "close losers only" / "close winners only"; per-symbol default SL distance (ATR-based).
