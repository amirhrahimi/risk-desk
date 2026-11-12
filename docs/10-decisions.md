# 10 — Architecture Decision Records

Format: Context → Decision → Consequences. Add new ADRs at the end; never rewrite accepted ones (supersede them instead).

## ADR-001 One shared codebase with compile-time platform selection
- **Context:** MQL4 (build 600+) and MQL5 share most of the language (classes, structs, chart objects) but differ in trading, account and history APIs. Two separate code bases drift apart.
- **Decision:** One source tree. Platform-specific code only in `Platform/`, selected with `#ifdef __MQL5__`. Same class names and public methods in both implementations (no virtual interfaces needed).
- **Consequences:** Every feature is written once. Platform files carry the burden of parity; reviewers check both implementations together.

## ADR-002 No MT5 Standard Library (CTrade, Controls)
- **Context:** `CTrade` hides filling-policy handling and retcodes; `Controls/` dialogs differ between MT4 and MT5 and are heavy.
- **Decision:** Own `CTradeGateway` with raw `MqlTradeRequest`/`OrderSend`; own lightweight widgets over chart objects.
- **Consequences:** Full control over BC-06/BC-11/BC-14 and identical UI on both platforms; more code to write and test (GatewaySmoke covers it).

## ADR-003 Money value: OrderCalcProfit on MT5, tick value + cross-check on MT4
- **Context:** Wrong tick values are a common cause of wrong lot sizes on CFDs and non-USD accounts.
- **Decision:** MT5 uses `OrderCalcProfit` (terminal does conversion). MT4 uses tick value, cross-checked against contract size × conversion rate; on mismatch take the more conservative value and warn.
- **Consequences:** Correct lots on cross-currency accounts; occasional conservative under-sizing on MT4 with an explicit warning.

## ADR-004 Lots always rounded down; refuse below min lot by default
- **Context:** Rounding up or sending the min lot silently can exceed the user's risk.
- **Decision:** `FloorVolume` with epsilon; below min → refuse with numbers; opt-in `InpAllowMinLotOverRisk`.
- **Consequences:** Risk is never exceeded silently; some small-risk trades on whole-contract CFDs are refused with a clear reason.

## ADR-005 Filling-policy and expiration fallback ladders
- **Context:** Servers differ in accepted filling policies and expiration types; flags are sometimes misleading.
- **Decision:** Derive candidates from symbol flags, try them in order, fall back only on the specific retcode, cache what worked per symbol and action; provide an override input for diagnostics.
- **Consequences:** Works on unknown brokers without configuration; an extra round trip on the first order of a symbol at worst.

## ADR-006 A RiskDesk position never stays without SL
- **Context:** Some servers reject SL/TP on market-execution orders; modify-after can fail.
- **Decision:** Verify SL after every open; fix with retries; close the position if it cannot be protected (`InpCloseIfStopFails=true`).
- **Consequences:** Rare forced closes with a loud message, instead of unprotected exposure.

## ADR-007 UI from standard chart objects, not CCanvas
- **Context:** Canvas gives prettier graphics but needs bitmap resources, manual hit-testing and more CPU, and behaves differently across platforms.
- **Decision:** `OBJ_RECTANGLE_LABEL`, `OBJ_BUTTON`, `OBJ_EDIT`, `OBJ_LABEL`, `OBJ_HLINE`, `OBJ_TEXT`.
- **Consequences:** Native click/edit handling, identical on MT4/MT5, simple DPI scaling; limited styling (no rounded corners/gradients).

## ADR-008 Tool trades by magic number; chart operations act on all trades of the symbol by default
- **Context:** The original's risk cap applies to its own trades only, but its Chart/Half/Risk-Free buttons act on "all trades on the chart".
- **Decision:** Magic number identifies tool trades for the risk budget. Chart-scope and account-scope operations default to all trades (parity) and can be limited to tool trades by setting.
- **Consequences:** Same behaviour as the original out of the box; users mixing other EAs can restrict scope.

## ADR-009 Persistence in files under MQLx/Files/RiskDesk
- **Context:** Terminal global variables only store doubles and are easily wiped.
- **Decision:** Small `key=value` files (`ui.ini`, `acct_<login>.ini`); chart objects keep the lines.
- **Consequences:** Human-readable, portable state; must handle missing/corrupt files gracefully (fall back to defaults).

## ADR-010 Synchronous requests
- **Context:** `OrderSendAsync` (MT5) is faster but complicates verification, retries and status reporting; MT4 has no async API.
- **Decision:** Synchronous `OrderSend` only; one command at a time per chart (busy flag).
- **Consequences:** Simple, verifiable flows; Full Close on many positions takes a few seconds and shows progress.

## ADR-011 Diagnostics before features (BrokerProbe, GatewaySmoke)
- **Context:** The original fails silently on two of the owner's brokers; guessing the cause wastes time.
- **Decision:** Build the probe in P0 and the gateway smoke test in P2, before any UI.
- **Consequences:** Broker issues are found in isolation, with data committed to the repo for future debugging.

## ADR-012 Mirror the original's inputs and defaults where known
- **Context:** The owner shared the original's settings dialog (v2.0.1). Familiar names and colours make the switch painless, and the inputs reveal features the guide does not describe (closed-trade objects, pending overlay, auto-fit, manual TP line).
- **Decision:** Where the original has an equivalent input, RiskDesk uses the same label (as the input's display comment), the same meaning and the owner's current value as default. Our own extra inputs keep their names. Unknown semantics (Q15–Q18) get a configurable assumption, never a guess baked into code.
- **Consequences:** Side-by-side parity can be checked (T-38). Our earlier "history overlay" idea moved to the backlog.

## ADR-013 TP modes derived from the original's full input labels
- **Context:** The first spec read "Trade with TP Line = false" as "no TP line, TP from R/R". That reading came from screenshots in which the labels were cut off. The full labels say "Manual TP Line - It doesn't work if Trade with TP Line is False" and "R/R | Only Active When Trade with TP Line is True", and the owner's demo test (Q15, 2026-11-12) confirmed them.
- **Decision:** Three TP modes, derived once in `Settings` as `ETpMode`: **No TP** (Trade with TP Line = false: no TP line, no TP), **Auto R/R** (true / Manual false: no TP line, TP from R/R at send time), **Manual TP line** (both true: draggable TP line that starts at the R/R distance). Lines, labels and order paths read `ETpMode`; nothing else reads the two booleans.
- **Consequences:** With the owner's configuration (true / false / 1.0) trades open with a 1:1 TP and no TP line, as in the original. Updated: 01 F-04/F-07/F-17, 04 §8, 05 §5, 06 OP-01/03/07, 07, 08 T-08.

## ADR-014 Placed pending orders are drawn by RiskDesk and moved by dragging
- **Context:** The owner's test (Q18) showed that the original draws placed pending orders itself in the "Pending Overlay" colours and that dragging those lines changes the order. CLAUDE.md §1 said RiskDesk acts only on clicks, and the first spec kept the overlay display-only.
- **Decision:** Overlay lines are selectable `OBJ_HLINE`s. Dropping one is a deliberate user action, handled as command OP-16: validate the new price (order type, side, BC-07), check the risk caps with the lot unchanged (04 §5), send `G-08 ModifyPending` through `CTradeGateway`, report the result; a refused or failed move snaps the line back. Deleting an overlay object never deletes the order. CLAUDE.md §1 now names this as the only non-click action.
- **Consequences:** Parity with the original; one more gateway primitive (G-08) and GatewaySmoke step; test T-39. The backlog item "draggable pending overlay lines" is done in v1 (P5).

## ADR-015 Build configuration file and version numbering before 1.0.0
- **Context:** 08-testing §2 needs a debug build with `RD_TEST_HOOKS` and a release build without it, but MetaEditor has no command-line define switch. Separately, both compilers (MT4 and MT5 MetaEditor) emit warning 68 "version is incompatible with MQL5 Market, must be xxx.yyy" for every `#property version` whose major part is 0 (tested in P0: "0.1", "0.10", "0.001", "0.100" warn; "1.00", "1.001", "10.20" do not). SemVer 0.x before the 1.0.0 release (09 P8) therefore conflicts with rule R11 (0 warnings), and CLAUDE.md §6 asks to bump `#property version` every phase.
- **Decision:** A new file `src/Include/RiskDesk/Build.mqh` (not in the CLAUDE.md §4 layout) holds `RD_PRODUCT`, `RD_VERSION` (SemVer) and a commented `//#define RD_TEST_HOOKS`. Every entry file includes it first. `build.ps1 -Debug` un-comments that line for the duration of the build and restores the file byte for byte; a release build refuses to start while the define is active. `RD_VERSION` is the product version: logged on init, written into probe reports, bumped at the end of each phase together with CHANGELOG (P0 = 0.0.1, phase N = 0.N.0, P8 = 1.0.0). Entry files carry no `#property version` until 1.0.0; from then on it is set to the `xxx.yyy` form of the version (e.g. "1.00").
- **Consequences:** One place to bump the version. Until 1.0.0, CLAUDE.md §6 "bump `#property version`" is done by bumping `RD_VERSION`; the owner may want to reword §6. The terminal's About box shows no version before 1.0.0; the Experts log does.

## ADR-016 Logger configuration is static
- **Context:** Platform, Services, App and the scripts all log (rule R8), and BrokerProbe has no `CApp` to own a logger. Threading a logger instance through every static Platform helper adds noise. CLAUDE.md §6 allows no global mutable state outside `App/State.mqh`.
- **Decision:** `CLogger` keeps its configuration (level, file mirror on/off, tag) in static members set once by `Configure()` in `OnInit`/`OnStart`; code logs through `RD_LOG_ERROR/WARN/INFO/DEBUG`. This is the only static state outside `App/State.mqh`, and it holds configuration, never application state.
- **Consequences:** One configuration line per entry point. Each EA instance has its own copy (MQL programs share no memory). The daily file is opened, appended and closed per line so several charts can write it.

## ADR-017 BrokerProbe structure and early Platform building blocks
- **Context:** The probe report (08 §3) is the same on both platforms, but its MT5 part (OrderCheck, OrderCalcProfit, OrderCalcMargin) and its MT4 part (MarketInfo, AccountFreeMarginCheck) use APIs that do not exist on the other platform, and rule R2 limits `#ifdef`. The report also needs the BC-01 conversion lookup and the BC-05 valuations, which belong to `Platform/Money.mqh` (phase P2). Broker symbol names differ, so a probe limited to Market Watch may miss the test-matrix instruments (08 §4).
- **Decision:**
  - Shared body `src/Scripts/RiskDesk/BrokerProbeCore.mqh`, with the test-symbol discovery in `BrokerProbeDiscovery.mqh` to stay under ~600 lines (both not in the §4 layout), with no `#ifdef`. Each entry file defines three hooks, `ProbePlatformAccount`, `ProbePlatformSymbol`, `ProbePlatformChecks`, with its platform-only code. Each entry file compiles for one platform only, so neither needs `#ifdef`. (A bodiless prototype of the hooks would be read by the MT4 compiler as a DLL import, warning 46, so the contract is a comment.)
  - P0 implements the probe's building blocks where they belong, so the probe measures the code paths the EA will use: `CMarket::Quote`; `CMoney::Rate` (BC-01 lookup by currency properties, Market Watch first, two-leg routes through any currency, routes cached per pair including failed lookups) and the raw valuations `LossByCalcProfit`, `LossByTickValue`, `LossByContract`, `MarginRaw`. P2 adds `LossPerLot`/`MarginFor` (BC-05 decision logic, BC-09) on top.
  - Two extra inputs beyond 08 §3: `InpFindTestSymbols` (default true) lists up to three candidates per test instrument, found by currency properties or by keywords in name/description, and probes them; `InpMaxSymbols` (150) caps the report. Keywords are used for this discovery only; trading code never builds or matches symbol names (R3, BC-01).
  - Symbols the probe adds to Market Watch (for quotes) are removed again at the end.
- **Consequences:** One report format on both platforms; P2 extends `Money.mqh` instead of starting it. The probe changes Market Watch only while it runs.

## ADR-018 Domain API shape (phase P1)
- **Context:** 02 §5–6 give an indicative Domain API. Implementing it left open: function vs class style, where the settings come from, how to size a trade when the money value of the SL distance comes from Platform (BC-05) but depends on the side and entry the Domain chooses, where display formatting for Domain messages lives, and how the spec's typographic characters (€, ≥, –, ·) get into ASCII sources.
- **Decision:**
  - PriceMath and formatting are free functions with the `Rd` prefix, taking the spec first where a grid is involved (`RdNormalizePrice(s, p)`, `RdPriceEq(s, a, b)`, `RdFloorVolume(s, raw, lots)`). RiskMath, Validators, Planner and RiskBudget are classes with static methods (`CRiskMath::LotsFromRisk`, `CValidators::MarketSide`, `CPlanner::Market`, `CRiskBudget::Check`), the `Module.Function` style of 02 §7.2.
  - New file `Domain/Format.mqh` (not in the CLAUDE.md §4 layout): money with the account currency and thousands separators, percent, lots, prices, points, order names (04 §11, BC-12). Domain messages and, later, the UI use it.
  - `SPlanSettings` in `Types.mqh` carries every setting the Domain reads; `App/Settings` fills it from the inputs in P3. Domain never reads inputs. Also new in Types: `ELineRole` (OP-16), `RdSkip()` (result "nothing to do, amber"), `RdTpModeFrom()` (ADR-013).
  - Opening a trade is two Domain steps around the platform valuation: `CPlanner::Market / MarketPreview / Pending` (side, kind, normalized prices, 04 §6–8 and BC-07 validation) → Platform `LossPerLot / ProfitPerLot` for that side and entry → `CPlanner::Size` (lots, money, reward, MT5 volume limit). The risk budget is then `CRiskBudget::OpenRisk` + `Check(openRisk, removed, added, trade)`: one formula covers new trades (removed 0), netting adds (BC-10: removed = old position) and moved orders (04 §5, OP-16: removed = old order risk).
  - Unit tests live in `src/Scripts/RiskDesk/Tests/` (runner, fixtures, one file per Domain module, suite). The two entry files only call `RunRiskDeskTests(platform, mqlDir)`. "passed/failed" count checks; a test is one V-xx or one edge-case group.
  - Sources stay ASCII. Currency signs are built from code points (`ShortToString(0x20AC)`); Domain messages use ASCII punctuation (`-`, `>=`) where the spec's examples show `–`, `≥`, `−`, `·`. The UI may use those glyphs through code points later.
  - Small extensions of the 04 formulas, all on the safe side: `RdFloorVolume` rounds to the larger of the step's and the minimum's decimals and never returns k < 0; above `volMax` the lot is `volMax` floored to the grid; `RdTicksBetween` snaps to whole ticks only within 1e-6, so a distance is never rounded down.
- **Consequences:** P2–P6 call these APIs instead of re-deriving rules; every rule has a unit test before any UI exists. The refusal texts differ from the spec's examples only in punctuation, and V-06 shows `€60.00` (BC-12) where 04 §12 writes "60.00 EUR".

## ADR-019 Trade gateway structure and the decisions taken in phase P2
- **Context:** 06 §5 and 03 describe each primitive and BC rule, but implementing them left open: how MT4 and MT5 share the code that is identical, where broker answers become messages, how the gateway is configured, what a primitive returns, and a few points where the spec is ambiguous or contradicts another part of it. The gateway must work on any broker: no rule may depend on a broker name, a symbol name or a value observed at one broker.
- **Decision:**
  - Files (not in the CLAUDE.md §4 layout): `Platform/TradeGatewayBase.mqh` (platform-neutral, no `#ifdef`: `SGatewaySettings`, `STradeOutcome`, `STradeFilter`, the pre-send checks BC-02/04/09/11/15 and rule R7, BC-11 memory, BC-13 delays, log helpers) is the base class of `CTradeGateway` (no virtual methods, ADR-001). `Platform/TradeErrors.mqh` is the only place where an MT5 retcode or MT4 error becomes a handling class and a status message (03 §5). Each platform has three files to stay near ~600 lines: `TradeGatewayMTx.mqh` (declaration, G-01, G-02, SL verification), `TradeGatewayMTxSend.mqh` (send engine: ladders, retries, BC-14, logging), `TradeGatewayMTxManage.mqh` (G-03…G-08, lists). `Scripts/RiskDesk/GatewaySmokeCore.mqh` is the shared smoke-test body; it has no `#ifdef`, so it also proves that the two gateways have the same public API.
  - Configuration: `CTradeGateway::Configure(SGatewaySettings)` with the Execution inputs of 07; App/Settings fills it in P3. Every primitive returns `bool` + `SResult`; G-01/G-02/G-04 also fill `STradeOutcome` (ticket, deal, fill price/volume, policy used, sends, realized P/L of a close, MT4 remainder ticket, amber notes). Messages are the reason only ("Filling policy rejected (tried FOK, IOC) [Unsupported filling mode]"); the command adds "Buy refused:" etc.
  - Every primitive checks BC-15 permissions and reads the spec and quote itself (BC-02 "before every trade request"), so a direct caller such as GatewaySmoke gets the specific messages too.
  - **Rule R7 at the gateway:** `OpenMarket` and `PlacePending` refuse a request without SL. A placed pending order is verified like a position: an SL that cannot be attached deletes the order (`InpCloseIfStopFails`), since it would otherwise fill into a position without SL.
  - **Commission is not part of `CMoney::LossPerLot`.** 03 BC-05 says "add `InpCommissionPerLot` to the loss per lot"; `CRiskMath::LotsFromRisk` (P1, ADR-018) already adds it (`lossPerLotAll`), so adding it in Money too would count it twice. `LossPerLot`/`ProfitPerLot` value the price move only; 03 BC-05 now says where the commission is added.
  - `OpenMarket(..., tpRR)`: with `tpRR > 0` the TP is `entry ± tpRR × |entry − SL|`, recomputed from the fresh price of every attempt (06 OP-03 "Entry/TP are recomputed … on each retry").
  - BC-06: no OrderCheck pre-screen. The terminal's OrderCheck judges a filling policy by the same `SYMBOL_FILLING_MODE` flags the ladder starts from; on a server whose flags do not match what it accepts it would remove exactly the fallbacks the ladder exists for. The ladder is: the policy that worked last for this symbol, the policies the flags allow (FOK, IOC), the others (FOK, IOC), RETURN; pending: last success, RETURN, FOK, IOC. The cache is per symbol and per kind (deal or pending); opens and closes share it.
  - BC-08 (MT5): rungs allowed by `SYMBOL_EXPIRATION_MODE` in the order of 03, then the others as last resorts (same reasoning as BC-06). Expirations use `TimeTradeServer()` (`RdServerTime()`), not `TimeCurrent()`, which is the time of the last tick and can be hours old on a quiet symbol. MT4 has only `TimeCurrent()`.
  - BC-13: `InpMaxRetries` counts retries after the first send (3 → at most 4 sends for retry-class answers). Filling and expiration ladder steps do not count as retries. Delay `InpRetryDelayMs` doubling, ×4 for busy/too-many-requests, capped at 10 s.
  - BC-14 (MT5): the check looks in the deal history (works on netting, where positions merge) and, on hedging, in the positions; closes by "position gone or smaller by the volume"; modifies by comparing the values. After the one allowed resend a second unknown result is final: red "No answer from the server and the request was not found – check the Trade tab before trying again".
  - BC-10: the gateway refuses an opening deal opposite to a netting position (03 default). P4 adds the `InpNettingAllowOpposite` path. On netting, a failed SL attach closes the volume this request added (assumed detail D12).
  - BC-11 extended to the other MT5 `SYMBOL_ORDER_MODE` flags: market/limit/stop orders and TP are refused with a message when the symbol does not allow them (D13). MT5 stop-limit orders are listed for deletion (`includeStopLimit`, as `KIND_STOP`) but never modified.
  - MT4: `ACCOUNT_LIMIT_ORDERS` counts open positions too, so BC-09's order-count check also runs before market orders there.
  - GatewaySmoke opens **2 × min lot** when the risk guard allows it, not the min lot of 09 P2: with exactly the min lot a partial close is never possible (the rest would be below the minimum), so M04 would always be skipped. SL/TP distance = max(`InpDistancePct` of price, 2 × (stops + freeze level) + 3 × spread + 10 ticks); the run aborts before sending anything when the min lot would risk more than `InpMaxRiskPct` (1 %) of balance or the margin is short; own magic (772299), confirmation box, everything it opened is closed/deleted at the end and reported.
- **Consequences:** P4–P6 commands call one gateway API on both platforms and only compose status texts. The smoke reports in `broker-profiles/` show, per account, which filling and time policy each server accepted. Files outside the §4 layout are listed here; CLAUDE.md §4 is unchanged.

## ADR-020 Unattended diagnostic runs, and what the first real runs changed
- **Context:** P2 ends with BrokerProbe and GatewaySmoke on six demo accounts (A1–A6). They live in two terminals (one MT4, one MT5 installation, several saved accounts each), so they can be run without clicking: start the terminal with a startup configuration that logs into an account and runs a script. The first runs showed problems that only real servers reveal.
- **Decision:**
  - `build/run-script.ps1 -Platform -Login -Server -Script -Symbol -Report [-Inputs]`: writes a startup configuration (login and server, algo trading on, chart, script, a `.set` file for the inputs in the Presets folder), starts the terminal, waits for the fresh report in `Files/RiskDesk`, closes the terminal. The password is never passed or stored: the terminal uses the one it saved for that login. GatewaySmoke needs `-Inputs 'InpConfirm=false'` to run unattended; R13 stays in the script.
  - `CAccountSpec::WaitReady(timeoutMs)`: right after a login the account properties arrive a moment after the connection (MT5: balance 0 and trading "not allowed" in the first reads; MT4: the startup script runs before the login completes). BrokerProbe and GatewaySmoke wait up to 15 s for a connected account with a currency and either trading allowed or a balance. GatewaySmoke makes its R13 decision only after that wait: before, MT4 runs aborted with "demo accounts only" (safe, but nothing was tested).
  - BC-01: conversion routes use forex calculation-mode symbols first (direct, inverted, two legs) and other symbol kinds only when no forex route exists. IC Markets EU MT5 has an index CFD whose currencies match "USD→EUR" (rate 20003.5); it was chosen before the inverted EURUSD. MT5 sizing was not affected (OrderCalcProfit is primary), but the MT4 cross-check would have been.
  - BC-16: after an MT4 partial close the gateway first checks whether the original ticket is still open with the smaller volume (IG MT4 does this), then looks for a new ticket.
  - G-04 (MT5): when the server answers DONE without a deal ticket or price (Dukascopy MT5), the deal is found through the order in the position's history, so the close price and realized P/L are reported.
- **Consequences:** The owner can re-run the whole matrix after any gateway change with one command per account (08 §3c). The observations are recorded in 03 §3. Q21 (Dukascopy MT4 index tick values): the owner keeps the conservative rule.
