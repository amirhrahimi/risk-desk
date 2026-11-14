# 08 — Testing

## 1. Levels

| Level | What | Who runs it | When |
|---|---|---|---|
| L1 Build | Both targets: 0 errors, 0 warnings (`build/build.ps1`) | Claude Code | Every change |
| L2 Unit | `RiskDeskTests.mq4/.mq5` scripts: all V-xx vectors + validators | Owner drags the script on any chart (Claude prepares) | Every Domain change |
| L3 Probe | `BrokerProbe.mq4/.mq5` on every account; reports committed to `broker-profiles/` | Owner | Phase 0, then whenever a broker misbehaves |
| L3b Gateway smoke | `GatewaySmoke.mq4/.mq5` (demo only): open → verify SL → modify → partial close → close; pending place → modify price/SL/TP → delete; PASS/FAIL table | Owner | Phase 2, and after any gateway change |
| L4 Demo integration | T-xx cases below on the account matrix | Owner, with Claude's checklist | End of phases 4–8 |
| L5 Visual tester | Optional smoke in the MT4 visual tester (button polling, 02 §10) | Owner | Optional |

Claude Code cannot click inside MetaTrader. At the end of each phase it outputs the exact T-xx list to run and what to paste back (status-bar text + Experts-tab lines).

## 2. Unit tests (L2)

- `src/Scripts/RiskDesk/RiskDeskTests.mq5` and `.mq4` include **only** `Domain/*` (plus a tiny assert helper). No terminal state is read, so results are identical on every account.
- Helpers: `ASSERT_NEAR(name, actual, expected, eps)`, `ASSERT_TRUE(name, cond)`, `ASSERT_EQ_STR(...)`.
- Each V-xx from `04-risk-engine.md` §12 is one named test; add one test per bug fixed later.
- Output: one line per failure, then `RiskDeskTests: 58 passed, 0 failed` via `Print` and `Alert`. Also written to `Files/RiskDesk/tests_<platform>.txt`.
- Optional (MT5): a headless run via `terminal64.exe /config:<ini>` is possible but not required; do not spend more than one session on automating it.
- Done in P1: `build/run-tests.ps1 [-Target mt4|mt5|all] [-Symbol EURUSD]` starts each terminal of `paths.local.ps1` (which must not be running) with a startup configuration that runs `RiskDesk\RiskDeskTests` on one chart, waits for `tests_<platform>.txt`, prints the summary and failures and exits 1 on any failure. MT5 closes itself (`ShutdownTerminal=1`); MT4 has no such switch for scripts, so the runner closes its window. The terminal logs into its last account; the script never trades. Needs `build.ps1` and `install-junctions.ps1` first.

### Test hooks (debug builds only)
Compile-time `#define RD_TEST_HOOKS` (off in release) compiles the self-test (`InpTestUiSelfTest`) and, for T-29/T-35 and the filling fallback, the gateway's **fault injection** (ADR-031): `EGwFault` in `Platform/TradeGatewayBase.mqh`, armed by the safety suite (§3j) and not by inputs (the hidden inputs `InpTestFailSlAttach`, `InpTestForceAmbiguous` and `InpTestForceFill` that this section used to describe were never built). A fault changes what is sent or what the terminal is told, never what the gateway does with the answer. Release builds must not contain any of it (`build.ps1` compiles release by default).

## 3. BrokerProbe (L3, F-27)

Script, both platforms. Inputs: `InpExtraSymbols` (comma list, e.g. `XAUUSD,US30,DE40,BTCUSD`), `InpIncludeMarketWatch=true`, `InpFindTestSymbols=true` (finds and probes candidates for the §4 instruments; section `[test symbols]`), `InpMaxSymbols=150` (ADR-017).

Writes `Files/RiskDesk/probe_<company>_<platform>_<login>_<yyyymmdd>.txt` (company/server sanitized). Plain `key: value` text, one block per section, so it diffs well in git.

```
[terminal]  build, platform (MT4/MT5), dpi, connected, trade_allowed, community, data_path
[account]   login, server, company, currency, currency_digits, leverage, trade_mode(demo/real),
            margin_mode (MT5: hedging/netting/exchange), limit_orders, trade_allowed, trade_expert,
            balance, equity, margin_so_mode, stopout levels
[symbol EURUSD]
            path, description, base/profit/margin currency, digits, point, tick_size,
            tick_value, tick_value_profit, tick_value_loss (MT5), contract_size,
            volume_min/max/step/limit, stops_level, freeze_level,
            trade_mode, exec_mode, calc_mode, filling_flags (decoded: FOK|IOC),
            expiration_flags (decoded: GTC|DAY|SPECIFIED|SPECIFIED_DAY), order_mode_flags (decoded),
            spread_now, spread_float, swap_long/short, session times today,
            bid/ask/time of last tick
  calc:     loss_100ticks_buy: OrderCalcProfit=…, tickvalue_formula=…, expected_from_contract=…, mismatch_pct=…
            margin_min_lot_buy=…, margin_1lot_buy=…
  checks (MT5 only, OrderCheck — nothing is executed):
            market_buy_min_lot fill=FOK → retcode/comment ; fill=IOC → … ; fill=RETURN → …
            buy_limit_min_lot  fill=RETURN time=GTC → … ; time=DAY → …
[conversion] rate lookups used: EURUSD for USD→EUR, …
```

Owner workflow: run once on each account (chart of any symbol), copy the files from `MQLx/Files/RiskDesk/` into `broker-profiles/`, commit. Claude Code reads them before implementing or debugging broker-specific behaviour.

## 3b. GatewaySmoke (L3b, phase P2)

Script, both platforms, **demo accounts only** (rule R13; checked in the entry file and again in the core). Drag it onto a chart of the symbol to test; it trades that symbol only and needs Algo/AutoTrading on (MT4: also "Allow live trading" in the script's Common tab).

Inputs: `InpDistancePct` (0.30: SL/TP distance in % of price, raised to 2 × (stops + freeze level) + 3 × spread + 10 ticks), `InpMaxRiskPct` (1.0: abort before sending if a test position would risk more at SL), `InpTestPartialClose` (true: open 2 × min lot), `InpTestSell`, `InpTestPending`, `InpConfirm` (true: Yes/No box before anything is sent), `InpSmokeMagic` (772299, not the EA's magic), and the gateway inputs `InpSlippagePoints`, `InpMaxRetries`, `InpRetryDelayMs`, `InpFillingOverride` (T-22), `InpStopsMode`, `InpPendingExpiryHours` (T-23).

Steps: S00 preflight (demo, permissions, spec, quote, netting state, risk and margin guard) · M01 open buy with SL/TP · M02 verify SL/TP/volume/magic · M03 modify SL · M04 partial close (SKIP when indivisible) and check the rest (MT4: new ticket) · M05 close the rest · M06 open sell with SL/TP · M06v verify · M07 close · P01 place Buy Limit 2 distances below Ask · P02 move price/SL/TP down by half a distance · P03 delete · X01/X02 cleanup of anything still open. A netting account with an open position on the symbol is refused (the test would merge with it).

Output: one line per step in the Experts tab, an Alert with the summary, and a block appended to `Files/RiskDesk/smoke_<company>_<platform>_<login>_<yyyymmdd>.txt` ([run] account/symbol/settings, [results] table with ms per step, [summary]). Copy the file to `broker-profiles/`.

## 3c. Unattended runs (`build/run-script.ps1`)

Runs BrokerProbe or GatewaySmoke on one saved account without clicking (ADR-020). The terminal must not be running; it logs into `-Login` on `-Server` with the password it has saved, opens a chart of `-Symbol`, runs the script, and closes when the report appears in `MQLx/Files/RiskDesk`.

```
powershell -File build/run-script.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Script BrokerProbe -Symbol EURUSD -Report "probe_*_<login>_*.txt"
powershell -File build/run-script.ps1 -Platform mt4 -Login <login> -Server IG-DEMO -Script GatewaySmoke -Symbol US30 -Inputs "InpConfirm=false" -Report "smoke_*_<login>_*.txt"
```
Use the broker's own symbol names from its probe report (`[test symbols]`). Copy the reports into `broker-profiles/` afterwards.

## 3d. Panel self-test (`build/run-uitest.ps1`, debug build, phase P3)

Checks the panel on a real terminal without clicking (ADR-021). Only in a debug build: `build.ps1 -Debug` first, `build.ps1` afterwards to put the release build back.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Symbol EURUSD
powershell -File build/run-uitest.ps1 -Platform mt4 -Login <login> -Server IG-DEMO -Symbol EURUSD
powershell -File build/build.ps1
```
The runner writes the one-time request file `Files/RiskDesk/uitest.request`, starts the terminal with RiskDesk (`InpTestUiSelfTest=true`) on a temporary chart, waits for `Files/RiskDesk/uitest/<PLATFORM>_<login>_report.txt` and copies the report and the screenshots to `-OutDir` (default `%TEMP%\RiskDesk-uitest`). The EA removes itself and closes the terminal. It never trades and uses `Files/RiskDesk/uitest/store/` instead of `ui.ini` / `acct_*.ini`.

Covered: T-01 (objects, in view, ready status, prices, spread, fields, tooltips), T-02 (the five inputs), every button's status (R8; from P5 Set Pending is clicked only after the pending lines were removed, and Del Pending only when no order is in its scope; from P6 Risk Free, Half Close and Chart Close only when no position is in their scope, Full Close otherwise with its confirmation answered No; so the suite still never trades), T-25 cooldown, hide/show, drag, clamp, T-20 (timeframe and symbol change with a planning line), T-21 (two runs: the second checks, after the real restart, what the first saved), text fit at scales 0.40–1.60 and every font preset, one and two columns (widgets inside the panel, none overlapping, rows level; ADR-023), T-37 (this chart and the fit arithmetic for 52 chart sizes per layout, and the Auto columns rule), the key=value file layer, the chart look (Chart on foreground switched off again, panel kept clear of the One-Click Trading panel); screenshots of each state and glyph sheets of Wingdings/Webdings. `ChartScreenShot` does not draw terminal overlays, so for the One-Click check the self-test writes `uitest/capture.request` and the runner saves a capture of the real terminal window (`<PLATFORM>_<login>_window_<name>.png` in `-OutDir`). Not covered: Windows scaling (T-24) and real mouse/keyboard input.

## 3e. Trade self-test (`build/run-uitest.ps1 -Suite trade`, debug build, phase P4)

The same runner and debug build as §3d, with a second set of steps (`App/UiSelfTestTrade*.mqh`, ADR-022) that drives Add Line, Add Pend Line, Delete Line, line drops, the Risk % field, Buy and Sell through the EA's own event handlers and sends **real orders**:

- **Demo accounts only (rule R13):** checked before anything is sent; on a real account only the line steps run.
- Own magic number 772288 (not the EA's), so the owner's RiskDesk trades never count towards the test's open risk; every test position is closed again, also those of an aborted earlier run. Its own sandbox `Files/RiskDesk/uitest/store_trade/` (the panel suite's T-21 chain is not disturbed).
- Size: about 2.5 × the risk of the minimum lot at an SL 0.25 % of the price away (at least 2 × (stops + freeze level) + 3 × spread + 10 ticks), at most 1 % of the balance and half the free margin; otherwise the order steps are skipped with an INFO line.
- One run per symbol. Report and screenshots: `Files/RiskDesk/uitest/<PLATFORM>_<login>_trade_<symbol>_*`.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Symbol EURUSD -Suite trade -TimeoutSec 600
powershell -File build/run-uitest.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Symbol XAUUSD -Suite trade-basic -TimeoutSec 600
powershell -File build/run-uitest.ps1 -Platform mt4 -Login <login> -Server IG-DEMO -Symbol EURUSD -Suite trade-basic -Permissions off
powershell -File build/build.ps1
```

| Check | Covers |
|---|---|
| Add Line (selected, labelled, TP line only in Manual mode), again → "already on chart", Add Pend Line replaces it (Pending Info "Buy Stop · x lot", entry label, dash-dot), Add Line replaces those, Delete Line → no objects, Lots "—" | T-03, F-04, F-05, F-07, F-08 |
| SL dropped below Bid / above Ask / at Bid: Lots = the lots computed from the raw valuation, label, the other side dimmed (colour checked), both dimmed inside the spread; Risk % doubled; red `0.003 < 0.01` below the minimum lot | T-04, F-03, F-18, F-33 |
| SL above the price + Buy → red "SL above Bid for a buy", no position | T-07 |
| Risk 0.01 % with a far SL + Buy → red "Min lot … would risk …", no position; `InpConfirmTrades` answered No → amber "cancelled - nothing was sent" | T-09, F-28 |
| Buy and Sell: one position, volume = Lots shown, SL = line, TP = R/R from the fill (± slippage), green status with the risk and ticket, lines removed, screenshot named per OP-14 | T-05, T-06, F-06, F-19 |
| No TP / Auto R/R 2 / Manual TP line (starts at R/R 2, follows SL drops until dragged, order TP = line) | T-08 |
| Total cap set to 1.5 × the first trade's real risk: second trade refused "Total risk too high: open x % + y % > z % cap" | T-11, F-16 |
| A test position whose SL was removed blocks a new trade "Position #… has no SL" | F-16 AC3 |
| Margin buffer leaving half the margin needed → refused with needed / free / max lots; with `InpReduceToMargin` the affordable lot is sent (amber) | T-12, F-31 |
| Second Buy right after the first (lines kept): ignored, one position | T-25 |
| Buy with a tight SL and TP, left until the server closes it (≤ 90 s, else closed by the test): the broker's booked profit of the price move = RiskDesk's valuation of the same move within 5 % | T-28 |
| `-Permissions off` (the terminal starts with Algo/AutoTrading off): Buy refused with the BC-15 message, nothing sent, the idle readout shows it. The EA-level permission ("Allow algo/live trading" unticked in RiskDesk's properties) cannot be set through a startup configuration and stays a manual check | T-26 |
| Chart symbol outside its trading session (terminal session table): Buy → red "Market closed" from the server, no position | T-27 |
| Netting account only: second buy merges after the confirmation (volume summed, new SL); a sell is refused; with `InpNettingAllowOpposite` it reduces the position after its confirmation | BC-10 (T-30 part) |

`trade-basic` runs T-03, T-04, T-07, T-09, T-05, T-06, T-26/T-27 when they apply, and T-28: for the extra symbols of an account (gold, an index, a whole-contract CFD). A `-Permissions` run changes the terminal's saved Algo/AutoTrading setting; the next normal run switches it on again. Not covered: T-10 is the Risk % field (§3d, T-02); real mouse/keyboard input.

The runners (`run-tests.ps1`, `run-script.ps1`, `run-uitest.ps1`) copy the terminal's active chart profile before they start it and put it back after it closed: MT4 otherwise keeps one more copy of the owner's chart after every start with a startup configuration (ADR-025). A `NOTE  chart profile restored …` line says when the terminal had added a chart.

## 3f. Pending suite (`build/run-uitest.ps1 -Suite pending`, debug build, phase P5)

The same runner, debug build and safety rules as §3e (demo accounts only, magic 772288, test lot about 2.5 × the minimum lot's risk and at most 1 %, own sandbox), with REAL pending orders placed 3 SL distances (at least 0.75 % of the price) away from the market so they do not fill during the run. Every test order is deleted again, also those of an aborted earlier run. Report and screenshots: `Files/RiskDesk/uitest/<PLATFORM>_<login>_pending_<symbol>_*`.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Symbol EURUSD -Suite pending -TimeoutSec 600
powershell -File build/run-uitest.ps1 -Platform mt4 -Login <login> -Server IG-DEMO -Symbol EURUSD -Suite pending -TimeoutSec 600
powershell -File build/build.ps1
```

| Check | Covers |
|---|---|
| Lines for each of the four types (Buy Stop, Buy Limit, Sell Stop, Sell Limit): Pending Info `<type> · <lots> lot`, Lots = the lots computed from the raw valuation, entry label; Set Pending → exactly one order of that type at the Entry line with the SL line, TP by the inputs' mode, volume = Lots; green status with the risk and ticket; lines removed; screenshot `_pending_<ticket>` | T-13, F-08, F-09 |
| The order drawn by the overlay: `RD_PO_<ticket>_EN/SL/TP` at the order's values, entry dash-dot / SL and TP dashed, width 1, overlay colours, selectable and listed; labels `Buy Stop 0.02 @ 1.11351`, `SL −€4.99 (0.10 %)`, `TP +€4.96 (R 1.00)`; every order drawn; an SL changed outside the overlay is followed; a deleted overlay line comes back, the order stays; the overlay goes with a deleted order; `InpShowPendingOverlay` off → nothing drawn | F-22 |
| Overlay drops (OP-16): SL farther → modified, label and open-risk readout updated, amber "risk now x % (panel y %)"; TP dragged → only the TP; entry dragged up → SL and TP move by the same distance, risk unchanged; entry below Ask → refused and snapped back; SL so far that the risk passes the per-trade cap → refused with the numbers, snapped back; the same above the total cap (old risk replaced) → refused; an overlay line deleted with the Delete key → drawn again, order intact; screenshot `_modify_<ticket>` | T-39 |
| Test orders on the chart symbol and on a second Market Watch symbol (placed through the gateway); Del Pending → only the chart symbol's are deleted, "Deleted n of n pending orders on EURUSD", screenshot; a second click → amber "No pending orders on EURUSD". When someone else's orders are on the symbol, the check limits Del Pending to the test's own (tool scope) | T-15, F-10 |
| Entry half the stops level from Ask → red "Entry too close to Ask for a Buy Stop: needs >= 40 pts (0.00040), move it to …", nothing sent; SL half the stops level from the entry → refused likewise. On a symbol without a stops level only Pending Info "Invalid: Entry at market - use Buy" is checked (no click) | T-14, F-09 AC2, BC-07 |
| Set Pending with market lines / without lines → red PF-5 reason; Risk 0.01 % with a far SL → red "Min lot … would risk"; `InpConfirmTrades` answered No → amber "cancelled - nothing was sent" | F-09, T-09 (pending), F-28 |
| R/R 2: (a) No TP: no TP line, order without TP; (b) Auto R/R: no TP line, TP = entry + 2 × SL distance; (c) Manual TP line: starts at R/R 2, follows an SL drop, stays where it was dragged; order TP = line | T-08 (pending part) |
| `InpPendingExpiryHours=24`: order expiry ≈ server time + 24 h (MT5 `SPECIFIED`, MT4 expiration), the status says when; a server refusing expiry would leave it without one with an amber note; an overlay drop keeps the expiry (G-08) | T-23, BC-08 |
| Netting account only: with an open buy, a Buy Stop is placed after the merge confirmation; a Sell Limit is refused | BC-10 (D27) |

T-23 as written needs a symbol whose probe shows no GTC; none of the six accounts has one (2026-11-12 probes: GTC everywhere, XAUUSD.eu.custom on A3/A5 lacks only DAY), so the suite checks the expiry the user asks for instead. A ladder fallback after a real `INVALID_EXPIRATION` stays with the P8 test hooks.

## 3g. Manage suite (`build/run-uitest.ps1 -Suite manage`, debug build, phase P6)

The same runner, debug build and safety rules as §3e (demo accounts only, own sandbox), with REAL test positions opened through the gateway (minimum lot, 3 × for T-17; SL at the test distance, no TP) and the four management buttons clicked through the EA's event handlers (`App/UiSelfTestManage*.mqh`, ADR-026). "RiskDesk" test positions have magic 772288, a "manual" one 772289. When anyone else's positions are on the chart symbol, the chart buttons act on the test's own only (tool scope) and the manual part of T-18 is skipped; when anyone else's positions or orders are on the account, Full Close does the same. So no other trade is ever touched. Every test position and order is closed / deleted again, also those of an aborted earlier run. Report and screenshots: `Files/RiskDesk/uitest/<PLATFORM>_<login>_manage_<symbol>_*`.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Symbol EURUSD -Suite manage -TimeoutSec 900
powershell -File build/build.ps1
```

| Check | Covers |
|---|---|
| Two buys and two sells, Risk Free at once: status `Risk-free on EURUSD: n moved …` with n = the SLs that changed, every position listed with its reason, no SL loosened | T-16 (skips), F-11 AC2/AC4 |
| Waits (≤ 180 s) until both positions of one side would be moved with a margin, sets the second one's SL by hand a few ticks (or one spread) beyond break-even, so a spread that widens before the click does not move it again, Risk Free: 1 moved with SL = open ± (spread + commission distance) at the click, 1 already protected, the other side not in profit / not enough profit, amber, screenshot `_riskfree_<ticket>`; again: the moved one is already protected (or tightened if the spread widened), never loosened. When the market does not move enough in 180 s an INFO line says so | T-16, 04 §9 |
| 3 × min lot buy and (hedging) a min lot sell: `InpConfirmHalfClose` answered No → nothing changes, dialog names what is closed and what stays; Yes → the buy keeps the 04 §10 rest of 3 × min (2 × min, Q23) with its SL (a new MT4 ticket is named), the sell is skipped "cannot be split" (amber), screenshot `_half_<ticket>`. On a whole-contract CFD (min 1) this is T-17's "1 lot" case | T-17, F-12, F-28, BC-16 |
| RiskDesk buy + sell, a manual buy on the chart symbol, a RiskDesk buy on a second symbol: tool scope → the two RiskDesk ones closed, `Closed 2 of 2 Risk Desk positions on EURUSD · P/L x` with x = the history's P/L of those exits; all on the symbol, `InpConfirmChartClose` No → kept, Yes → the manual one closed; the other symbol untouched; nothing left → amber `Chart Close: no positions on EURUSD` | T-18, F-13, F-28 |
| RiskDesk positions on the chart symbol and up to two other symbols, a far Buy Limit: the open-risk readout = their risk at SL (+ the order) in % of the balance | T-32 (one chart; the readout is account-wide, so a second chart shows the same) |
| `InpConfirmFullClose` No → everything kept, dialog `Close 3 positions on 3 symbols? … Also delete 1 pending order.`; Yes with `InpFullCloseAlsoPending` → every position closed and the order deleted, `Closing 3/3...` shown on the way, `Closed 3 of 3 positions on 3 symbols · P/L x · deleted 1 of 1 pending order`; nothing left → amber `Full Close: no positions on this account …` | T-19, F-14, F-28 |
| Netting account only: two buys of 2 × min lot merge at the averaged open; Half Close leaves half on the same position and open price; Risk Free (after the same wait) sets SL = averaged open + spread, or skips with its reason; Chart Close closes it | T-30 (half close, Risk Free; the merge confirmation and the opposite refusal are §3e) |

The panel suite (§3d) clicks Risk Free, Half Close and Chart Close only when no position is in their scope, and Full Close only when nothing is in its scope or with its confirmation answered No, so it still never trades. Not covered: a freeze level (every account reports 0; the Domain tests cover it) and a position above the maximum volume per request (D35; unit-tested).

## 3h. Half Close suite (`build/run-uitest.ps1 -Suite half`, debug build)

Half Close (OP-10, F-12, 04 §10) over the volume grid of the chart symbol, so the index grids (min 1 / step 1, 0.1 / 0.1, 0.01 / 0.01) and the FX grid of every broker are covered: one run per symbol, indices and majors on every account. Same runner, debug build and safety rules as §3g (demo only, magic 772288, tool scope when anyone else's positions are on the symbol; on a netting account with someone else's position on the symbol it does not run). REAL test positions through the gateway, SL at 0.1 % of the price (at least 2 × stops level + 3 × spread + 10 ticks; they live a few seconds) and TP at twice it; a case runs only when its positions risk at most 2.5 % of the balance at the SL and need at most half the free margin (else an INFO line). Every test position is closed after each case. Symbols whose minimum lot is not one step are not run (the unit tests cover them). Report and screenshots: `Files/RiskDesk/uitest/<PLATFORM>_<login>_half_<symbol>_*`.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt4 -Login <login> -Server ICMarketsEU-Demo03 -Symbol US30 -Suite half -TimeoutSec 400
powershell -File build/build.ps1
```

Every click is checked against the split expected in whole grid steps (u = one step; 04 §10: the nearest to the percentage, a tie keeping the larger part, Q23): the rest's volume, side, open price, SL and TP, and its ticket (MT4: the new ticket, which the status must name, BC-16); the volume closed and the P/L in the account history, which the status P/L must equal; the status text, colour and progress. One INFO line per run lists the splits.

| Case | Positions, setting | Expected |
|---|---|---|
| H-1 even | buy 2u | 1u closed, 1u left, green |
| H-2 odd | sell 3u | 1u closed (1.5u is a tie: the larger part stays, Q23), 2u left, green |
| H-3 repeated | buy 4u, three clicks | 2u + 2u; then 1u + 1u on the rest (MT4: the new ticket); then the 1u is kept, amber `Half Close: nothing closed … cannot be split` |
| H-4 min lot, Close all | buy 1u, `INDIV_CLOSE_ALL` | closed whole, amber `… all 1u lot (cannot be split)` |
| H-5 30 % | buy 10u | 3u closed, 7u left |
| H-6 70 % | sell 3u | 2u closed (nearest to 2.1u), 1u left |
| H-7 several (hedging) | buy 2u, sell 3u, buy 1u | 1u + 1u closed in one click, `Half Close: closing 2/2...`, the 1u skipped, amber, P/L = the history's sum |
| H-8 several, Close all (hedging) | buy 3u, sell 1u, `INDIV_CLOSE_ALL` | 1u of the buy, all of the sell, amber |
| H-9 merged (netting) | buy 2u + buy 1u = one position of 3u | 1u closed by an opposite deal, the same position keeps 2u, its averaged open, SL and TP |
| H-10 halving to the minimum | buy 25u, six clicks | 25u → 13u → 7u → 4u → 2u → 1u kept (the rest named each time on MT4), then `cannot be split` (amber): the owner\'s path, at 0.01 steps 0.25 → 0.13 → 0.07 → 0.04 → 0.02 → 0.01 |

## 3i. Extras suite (`build/run-uitest.ps1 -Suite extras`, debug build, phase P7)

The P7 extras on a real chart (`App/UiSelfTestExtras.mqh`, ADR-027). Same runner, debug build and safety rules as §3e; one REAL test Buy (magic 772288, about 2.5 × the risk of the minimum lot, demo accounts only, closed again at once; on a netting account only when the symbol has no position). The timeframe steps run first (a timeframe change runs OnInit, which reloads the inputs). Report and screenshots: `Files/RiskDesk/uitest/<PLATFORM>_<login>_extras_<symbol>_*`.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt4 -Login <login> -Server ICMarketsEU-Demo03 -Symbol EURUSD -Suite extras
powershell -File build/build.ps1
```

| Check | Covers |
|---|---|
| `RD_CT` against a countdown computed in the test from bar 0's open + the period and the server clock (±2 s): text, `mm:ss` / `hh:mm:ss` / `Nd hh:mm:ss` form for that many seconds, gold or red at `InpCandleTimeWarnPct` (either within 2 s of the threshold), place (right of the candle `<-- …`, or left of it `… -->`, D39) at the Bid, hidden, not selectable, font size | T-33 candle time, F-21 AC1/AC2 |
| 2.5 s later the countdown went down by the time that passed (the INFO says whether a tick came meanwhile) | T-33 "keeps running between ticks" |
| Candle Time off → `RD_CT` removed (20 refreshes timed), on → drawn again | T-33 toggle, "cheap when disabled" |
| Chart shift on → right of the candle; off → left of it | D39 |
| The same check on M1, H4 and W1, then back to the runner's timeframe; on W1 also RiskDesk's own screenshot (a W1 chart with fewer bars than its width froze MT4 when a larger picture was asked for, ADR-027) | T-33 M1 / H4 / W1, T-34 |
| Camera: `<login>_<symbol>_<TF>_<yyyy-mm-dd_HH-MM-SS>_manual_0.png` exists, green `Screenshot saved: …`; a Buy: `…_buy_<ticket>.png` with the status ticket | T-34, F-19 |
| With the Buy's closed ticket: three objects named as MetaTrader names a closed trade's arrows and line, plus four that must stay (a text with the same `#ticket `, an arrow of a ticket that is no trade, a user trend line, `#<ticket>x`): Remove → the three deleted, the four kept, MT5 "Show trade history" off with the user's value in `RD_S_CTO`; Keep → new ones kept, the user's value back | T-33 closed-trade objects, F-20 AC1–AC3 |
| `InpCentMode=CENT_ON` with lines on the chart: the SL label shows `<cent unit> (<major>…)`, Lots unchanged | T-31 (display), F-24 |
| A daily log file of 2001 is deleted, a file of another name and today's file stay | F-32 retention (D41) |

Result 2026-11-13: 19 passed, 0 failed on A1–A6 (EURUSD). The suite's three objects carry the names MT4 gives a closed trade (Q24: `#<ticket> <open> -> <close>`, `#<ticket> sell 0.05 EURAUD at <open>`, `… close at <close>`); MetaTrader drawing them itself is not covered. Not covered either: a real cent account (A7, none in the matrix): T-31 on A7 stays a manual check.

## 3j. Safety suite (`build/run-uitest.ps1 -Suite safety`, debug build, ADR-031)

The three paths a healthy demo server never takes, driven through the real Buy button with a fault armed in the gateway (`EGwFault`, §2 test hooks; `App/UiSelfTestSafety.mqh`). Same runner, debug build and safety rules as §3e (demo only, R13; magic 772288; about 2.5 × the risk of the minimum lot; every test position closed again). The evidence is the position count, the status bar and the daily log file (`Files/RiskDesk/Logs`) read from where it ended before the click. **The market of the chart symbol must be open** (on a weekend use a crypto CFD): with it closed every case fails with `Market closed`, which says nothing about the paths. One run per account.

```
powershell -File build/build.ps1 -Debug
powershell -File build/run-uitest.ps1 -Platform mt5 -Login <login> -Server ICMarketsEU-Demo -Symbol EURUSD -Suite safety
powershell -File build/build.ps1
```

| Case | Fault | Passes when | Covers |
|---|---|---|---|
| T-29 SL fails, position closed | `GWFAULT_SL_ATTACH`: the open carries no SL/TP and every SL/TP modify is refused | no position left; red `Buy failed: SL could not be attached - position closed (…)`; log has the `has no valid SL` line and the close request (G-04) | T-29, rule R7, BC-11 |
| T-29 SL fails, kept open | same, `InpCloseIfStopFails` off | one position without SL; red `Position #… is open WITHOUT a valid SL - set it now (…)` | rule R7 (the opt-out is loud) |
| T-35 reply lost, executed | `GWFAULT_REPLY_LOST`: the open is sent and executes, the reply is dropped | one position; green status naming it; ONE request sent; log `the request WAS executed - not resending` | T-35, rule R9, BC-14 |
| T-35 request lost, resent once | `GWFAULT_SEND_LOST`: the open never reaches the server | one position; TWO requests (the first never sent); log `not executed - sending once more` | BC-14 |
| T-35 never answered | `GWFAULT_NEVER_ANSWERED` | no position; red `No answer from the server and the request was not found - check the Trade tab before trying again`; exactly two requests, no third | BC-14, rule R8 |
| T-35 earlier trade not adopted | a normal Buy, then at once `GWFAULT_NEVER_ANSWERED` | still one position; red `No answer …` that does not name the first ticket (before ADR-031 the status said done and named it) | BC-14 (ADR-031) |
| BC-06 fill rejected, next policy (MT5) | `GWFAULT_BAD_FILL`: the ladder starts with a policy the symbol's flags do not allow | the server really answers `retcode=10030`, the log shows `-> next fill=`, one position; INFO instead when the server accepts the policy anyway | T-22, BC-06 |
| BC-06 policy cached (MT5) | none | the next Buy sends one request with the policy that worked | BC-06 |

Result 2026-11-14 (BTCUSD, the only symbol open on a Saturday): A2 IC Markets EU MT4 6 passed; A3 IC Markets EU MT5 8 passed (10030 answered for FOK, IOC worked); A4 Dukascopy MT4 6 passed; A5 Dukascopy MT5 8 passed. A first run found the BC-14 defect of ADR-031 on A2 and A3 (case "earlier trade not adopted", and the earlier case's deal taken for the lost request on MT5); both pass after the fix. A1 IG MT4 (BTCUSD closed on weekends) and A6 MetaQuotes netting (BTC closed) wait for an open market.

## 4. Account and symbol matrix (L4)

| Account | Platform | Notes |
|---|---|---|
| A1 IG demo | MT4 | baseline |
| A2 IC Markets EU demo | MT4 | |
| A3 IC Markets EU demo | MT5 | filling policy (H1) |
| A4 Dukascopy demo | MT4 | volume grid (H2) |
| A5 Dukascopy demo | MT5 | |
| A6 MetaQuotes-Demo **netting** | MT5 | open a demo with "hedging" unticked, for T-30 |
| A7 any cent demo (optional) | MT4/MT5 | T-31 |

Symbols per account (owner's list, Q14; use the broker's names from the probe): EURUSD, USDJPY, EURGBP (cross), XAUUSD, US30, Nasdaq 100, BTCUSD, and on Dukascopy one whole-contract CFD (min lot ≥ 1).

Result 2026-11-14 (a Saturday: FX, gold and indices closed, so only BTCUSD could trade; build `1.8.0-rc.1` debug, MT5 build 6320, MT4 build 1492): every suite on A2 IC Markets EU MT4, A3 IC Markets EU MT5, A4 Dukascopy MT4 and A5 Dukascopy MT5.

| Suite | A2 MT4 | A3 MT5 | A4 MT4 | A5 MT5 |
|---|---|---|---|---|
| panel | 66 passed | 66 passed | 65 passed | 65 passed |
| trade | 34 passed | 34 passed (1) | 34 passed | 34 passed (1) |
| pending | 37 passed | 37 passed | 37 passed | 37 passed |
| manage | 13 passed | 13 passed | 11 passed (2) | 11 passed (2) |
| half | 16 passed | 9 passed (3) | 16 passed | 16 passed |
| extras | 19 passed | 19 passed (4) | 19 passed | 19 passed (4) |
| safety (§3j) | 6 passed | 8 passed | 6 passed | 8 passed |

1. T-12 "reduce to margin" failed on the first run on both MT5 accounts: the test left usable margin at exactly half of what 0.02 lot (2 × the minimum) needs, which is the margin of 0.01 lot, and BTCUSD ticked between the test's reading and the click, so 0.01 no longer fitted and the refusal was right. The test now leaves room for half the lots plus half a step; both accounts pass.
2. T-16 "moved": in 180 s the positions did not get far enough in profit, so that part is not checked (INFO).
3. H-5 and H-10 skipped: 0.10 and 0.25 lot would need more margin than A3 has free (INFO).
4. T-33 on W1 failed once on both MT5 accounts (label 10 to 58 px left of bar 0) and passed on the rerun. Probable cause: BTCUSD's W1 history was synced for the first time, so bar 0 moved after the label was placed; not reproduced, not proven.

Not run yet: A1 IG MT4 (BTCUSD is closed on weekends) and A6 MetaQuotes netting (BTC closed), the FX, gold and index symbols, so T-01 to T-28 are covered on a crypto CFD only, and T-30 (netting) and T-31 (cent) are open.

## 5. Test cases (L4)

Format: **ID — goal** · steps · expected. "Status" means the panel status bar; "log" the Experts tab.

| ID | Goal | Steps | Expected |
|---|---|---|---|
| T-01 | Install/init | Attach EA on each account | Panel visible at default position; log shows version, account, margin mode; no errors |
| T-02 | Risk input | Type `1,5`, `0`, `12`, `abc`, ` 0.25 ` | 1.50 / revert+red / revert+red / revert+red / 0.25 |
| T-03 | Lines lifecycle | Add Line → Add Pend Line → Add Line → Delete Line | Modes switch; status notes replacement; no leftover objects |
| T-04 | Lots preview | Drag SL below/above/inside spread; move risk % | Lots updates ≤ 250 ms; `—` when inside spread; red when < min |
| T-05 | Buy | Valid lines, Buy | Position with lots = expected (from probe values, ±0 steps), SL/TP exact, green status with risk, screenshot file exists |
| T-06 | Sell | Mirror of T-05 | Same |
| T-07 | Wrong side | SL above price, click Buy | Red "SL above Bid for a buy", **no** request in log |
| T-08 | TP modes | `InpTpRR=2`. (a) Trade with TP Line = false: Add Line, Buy. (b) true, Manual = false: Add Line, Buy and Sell. (c) true, Manual = true: Add Line, drag the TP line, Buy. Repeat (a)–(c) with Add Pend Line + Set Pending | (a) no TP line; order without TP. (b) no TP line; TP = entry ± 2 × SL distance (normalized). (c) green line starts at 2 × SL distance and follows SL drags until the TP line itself is dragged (`InpTpFollowsSl=true`); order TP = dragged line price |
| T-09 | Below min lot | Dukascopy whole-contract CFD, 0.1 % risk | Red message with min-lot risk; nothing sent |
| T-10 | Per-trade cap | Risk 12 | Rejected in field |
| T-11 | Total cap | Open 3 × 3 % trades, then 2 % | Refused with "open 9.00 % + 2.00 % > 10 %" |
| T-12 | Margin | BTCUSD on EU account, 5 % risk, very tight SL | Refused with required vs free margin and max lots |
| T-13 | Pending types | Arrange lines for each of the 4 types; Set Pending each | Pending Info text correct; order type/price/SL/TP/lots correct |
| T-14 | Pending too close | Entry inside stops level | Refused with required distance |
| T-15 | Del Pending | Pending orders on 2 symbols; click on chart A | Only chart A's pending deleted; count shown |
| T-16 | Risk Free | 3 positions: well in profit, barely in profit, already BE | 1 moved, 1 "not enough profit", 1 "already protected"; SL never loosened; moved SL = open ± (spread + commission distance), 04 §9 |
| T-17 | Half Close | Positions 0.03, 0.01, (Duka CFD) 1 | 0.01 closed / remainder 0.02; others skipped with reasons |
| T-18 | Chart Close | Manual + tool positions on chart symbol, plus another symbol | All on chart symbol closed (default scope); other symbol untouched |
| T-19 | Full Close | Positions on 3 symbols | Confirm dialog; all closed; summary |
| T-20 | TF / symbol change | Lines on chart; change TF; then change symbol | TF: identical panel/lines, no duplicates; symbol: lines removed, panel kept |
| T-21 | Restart | Move panel, hide, set risk 0.75; restart terminal | Position/hidden/risk restored |
| T-22 | Filling (MT5) | A3/A5 Buy with `FILLPOL_AUTO`; then force a wrong `InpFillingOverride` | Auto: success, log shows the policy used; forced wrong: red "[Unsupported filling mode]" |
| T-23 | Expiration (MT5) | Pending on a symbol whose probe shows no GTC (if any) | Placed with DAY/SPECIFIED; amber note |
| T-24 | Hi-DPI | Windows scale 150 % and 200 %; restart the terminal after changing it (RiskDesk's first log line must say `DPI 144` / `DPI 192`) | No clipped text; panel proportions kept; on a chart too short for one column at 85 % of Shape Size Scale the panel shows two columns (ADR-023) |
| T-25 | Double click | Double-click Buy fast | Exactly one position |
| T-26 | Permissions | Toolbar Algo/AutoTrading off; EA "allow trading" off | Specific red message for each; nothing sent |
| T-27 | Market closed | Weekend, click Buy on FX | "Market closed" message (or stale-quote hint) |
| T-28 | Risk accuracy | EUR account, XAUUSD, small SL; let SL hit (or close at SL price) | Realized loss within ±5 % of displayed risk (+commission, slippage) |
| T-29 | SL safety | Debug build, `-Suite safety` (§3j): the SL cannot be attached | Position closed, red "Buy failed: SL could not be attached - position closed (…)"; with `InpCloseIfStopFails` off the position stays and the red message says it has no SL |
| T-30 | Netting (A6) | Buy, Buy again, Sell, Half Close, Risk Free | Merge confirm; opposite refused by default; half close reduces; RF on averaged price |
| T-31 | Cent (A7) | Buy with 1 % | Lots correct; labels show USC and $ |
| T-32 | Multi-chart | RiskDesk on 2 charts, trades on both | Open risk counts both; Full Close from one closes all |
| T-33 | Chart extras | Close a few trades with `CTO_REMOVE`, then `CTO_KEEP`; toggle Candle Time; place 2 pending orders with overlay on, move one with MetaTrader's own trade level, delete one | Closed-trade arrows removed/kept (user drawings untouched); countdown correct at M1 (`mm:ss`), H4 (`hh:mm:ss`), W1 (`Nd hh:mm:ss`), gold, red in the last `InpCandleTimeWarnPct` (10) % of the candle (M5: from `00:30`, H1: from `06:00`) and at `00:00` when the market is closed, keeps running between ticks; overlay follows orders exactly; no lag |
| T-34 | Screenshot naming | Several actions + camera button | Files named per F-19 |
| T-35 | Ambiguous result | Debug build, `-Suite safety` (§3j): reply lost after executing, request not sent, never answered, an earlier trade of the seconds before | Log shows check-before-resend; exactly one position (or none and a red "No answer from the server …"); an earlier trade is never taken for the lost request |
| T-36 | Silent-failure regressions | On every account: Add Line, Buy with RiskDesk on EURUSD, XAUUSD and an index | Each click opens the trade or shows a red reason with a log line; never nothing (R8) |
| T-37 | Auto-fit panel | `InpScale=1.6`, `InpAutoFitPanel=true`; shrink the chart window step by step, then enlarge | Panel always fully visible, never larger than scale 1.6, text readable; with auto-fit off it keeps its size. `InpPanelColumns=Auto`: two columns once one column would fall below 85 % of 1.6, one column again when the window grows |
| T-39 | Drag a pending order | Buy Stop placed by RiskDesk: drag its SL farther (risk still under the caps), drag its TP, drag its entry up, drag its entry below Ask, drag the SL so the risk exceeds 10 %; select an overlay line and press Delete | SL/TP modified, labels and open risk updated, amber note when risk > panel %; entry up: SL and TP move by the same distance, risk unchanged; entry below Ask refused and snapped back; over-cap move refused with numbers and snapped back; deleted line redrawn, order intact |
| T-38 | Original settings parity | Set the same inputs as the original (07-settings ★ values) | Colours, font, sizes and TP behaviour match the original side by side |

## 6. Bug report template (owner → Claude Code)
```
Account: A3 (IC Markets EU MT5, hedging, EUR)   Build: RiskDesk 0.4.0
Symbol: XAUUSD   Action: Buy   Risk: 1.00 %   Lines: SL 3990.00 TP —
Status bar: "<exact text>"
Experts log (last 20 lines):
<paste>
Probe file: broker-profiles/probe_ICMarketsEU_MT5_12345678_20261109.txt
Expected: <what you expected>
```

## 7. Release checklist
- [ ] L1 clean on both targets (release build, no test hooks).
- [ ] L2 all pass on MT4 and MT5.
- [ ] Probe reports current for all accounts.
- [ ] T-01…T-28 pass on A1–A5; T-30 on A6; T-31 if available.
- [ ] CHANGELOG updated, version bumped, `README` user section updated.
- [ ] Release zip: `RiskDesk.ex4`, `RiskDesk.ex5`, `BrokerProbe.ex4/.ex5`, short user guide (PDF/MD). Built and published by `.github/workflows/build.yml` on the push to `main` that bumps the version (ADR-030); `build/package-release.ps1` makes the same zip locally.

## 8. Gateway review against 03 §6 (1.8.0)

Read through on 2026-11-14: `Platform/TradeGatewayBase.mqh`, `TradeGatewayMT5.mqh`, `TradeGatewayMT5Send.mqh`, `TradeGatewayMT5Manage.mqh` (G-03, G-04, G-08), `TradeGatewayMT4.mqh`, `TradeGatewayMT4Send.mqh`, `TradeErrors.mqh`, the margin check in `App/CommandsTrade.mqh`. Not re-read line by line: the remaining G-05/G-06/G-07 listing and delete code and `TradeGatewayMT4Manage.mqh` beyond G-03; they were exercised by the pending and manage suites.

| 03 §6 item | Result | Evidence |
|---|---|---|
| No literal 0.01, lot/price digits, 100000, currency or symbol suffix in trade code | pass | search of `Platform/TradeGateway*`, `TradeErrors`, `App/Commands*` and `Domain/` for those literals: no hit; every value comes from `SymbolSpec`/`AccountSpec` |
| Prices to tick size; volumes floored to step and checked against min/max/limit | pass | `RdNormalizePrice` in G-01/G-02/G-03/G-08; `CheckOpen` → `RdIsValidVolume`; `CloseVolume` floors and never exceeds the position (a netting reversal is impossible); `SYMBOL_VOLUME_LIMIT` in `CommandsTrade` |
| Filling and expiration ladders exercised (T-22, T-23) | pass | filling: the safety suite got the real `10030` and the next policy on A3 and A5 and the policy cached (§3j); expiration: T-23 in the pending suite |
| Stops/freeze checks with readable refusal messages | pass | `CValidators` before every send, the distances used in the message (`StopsDistances`), `INVALID_STOPS` detail with the stops level |
| Margin pre-check with numbers | pass | `CCommands::CheckMargin`: "needs X margin for N lot, Y free (Z % kept unused) - max about M lot"; `NO_MONEY` detail from the gateway |
| Netting path implemented or refused with a message | pass | G-01 refuses an opposite deal on a netting account; the same side merges with a note; G-04 floors to the position. T-30 on the netting account: manage suite (A6), needs an open market |
| SL verified after open; close-on-failure path tested | pass (was untested) | T-29 both ways in the safety suite on A2–A5 |
| Every result code produces a status message and a log line | pass | each send logs its request and answer (`LogRequest`/`LogResult`, MT4 `ok ticket=` / `error=`); `Failed()`/`Refuse()` log; a code with no entry in `TradeErrors` becomes fatal with its number in the message (`RETCODE_n`, `ERROR_n`) |

Findings:
1. **BC-14 could adopt an earlier trade** (fixed, ADR-031). After a lost reply the gateway looked for a trade with the same symbol, magic, side and volume opened within 5 s before the request; a trade of the seconds before (a second click) matched, so the panel said done and named the old ticket. Found by the safety suite's "earlier trade not adopted" case on A2 and A3; the gateway now ignores what existed before the first send.
2. **The documented test hooks did not exist** (`InpTestFailSlAttach`, `InpTestForceAmbiguous`, `InpTestForceFill` were described in §2 but never built). Replaced by the gateway fault injection of ADR-031.
3. Not a defect, a limit: a fault test shows what Risk Desk does with a lost reply, not how a broker's server behaves when it really times out; no demo server can be made to do that on demand.
