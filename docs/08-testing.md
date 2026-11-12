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
Compile-time `#define RD_TEST_HOOKS` (off in release) exposes hidden inputs used by T-29/T-35:
`InpTestFailSlAttach` (pretend SL attach failed), `InpTestForceAmbiguous` (pretend the first send timed out after executing), `InpTestForceFill` (start the ladder with a wrong policy). Release builds must not contain them (`build.ps1` compiles release by default).

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

## 4. Account and symbol matrix (L4)

| Account | Platform | Notes |
|---|---|---|
| A1 IG demo | MT4 | baseline (original works here) |
| A2 IC Markets EU demo | MT4 | |
| A3 IC Markets EU demo | MT5 | filling policy (H1) |
| A4 Dukascopy demo | MT4 | volume grid (H2) |
| A5 Dukascopy demo | MT5 | |
| A6 MetaQuotes-Demo **netting** | MT5 | open a demo with "hedging" unticked, for T-30 |
| A7 any cent demo (optional) | MT4/MT5 | T-31 |

Symbols per account (owner's list, Q14; use the broker's names from the probe): EURUSD, USDJPY, EURGBP (cross), XAUUSD, US30, Nasdaq 100, BTCUSD, and on Dukascopy one whole-contract CFD (min lot ≥ 1).

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
| T-24 | Hi-DPI | Windows scale 150 % and 200 % | No clipped text; panel proportions kept |
| T-25 | Double click | Double-click Buy fast | Exactly one position |
| T-26 | Permissions | Toolbar Algo/AutoTrading off; EA "allow trading" off | Specific red message for each; nothing sent |
| T-27 | Market closed | Weekend, click Buy on FX | "Market closed" message (or stale-quote hint) |
| T-28 | Risk accuracy | EUR account, XAUUSD, small SL; let SL hit (or close at SL price) | Realized loss within ±5 % of displayed risk (+commission, slippage) |
| T-29 | SL safety | Debug build, `InpTestFailSlAttach=true` | Position closed, red "SL could not be attached – position closed" |
| T-30 | Netting (A6) | Buy, Buy again, Sell, Half Close, Risk Free | Merge confirm; opposite refused by default; half close reduces; RF on averaged price |
| T-31 | Cent (A7) | Buy with 1 % | Lots correct; labels show USC and $ |
| T-32 | Multi-chart | RiskDesk on 2 charts, trades on both | Open risk counts both; Full Close from one closes all |
| T-33 | Chart extras | Close a few trades with `CTO_REMOVE`, then `CTO_KEEP`; toggle Candle Time; place 2 pending orders with overlay on, move one with MetaTrader's own trade level, delete one | Closed-trade arrows removed/kept (user drawings untouched); countdown correct at M1 (`mm:ss`), H4 (`hh:mm:ss`), W1 (`Nd hh:mm:ss`), gold, red in the last `InpCandleTimeWarnSec` seconds and at `00:00` when the market is closed, keeps running between ticks; overlay follows orders exactly; no lag |
| T-34 | Screenshot naming | Several actions + camera button | Files named per F-19 |
| T-35 | Ambiguous result | Debug build, `InpTestForceAmbiguous=true` | Log shows check-before-resend; exactly one position |
| T-36 | Original-tool regressions | Repeat every scenario recorded in `broker-profiles/original-tool-errors.md` | All succeed or fail with a clear reason |
| T-37 | Auto-fit panel | `InpScale=1.6`, `InpAutoFitPanel=true`; shrink the chart window step by step, then enlarge | Panel always fully visible, never larger than scale 1.6, text readable; with auto-fit off it keeps its size |
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
- [ ] Release zip: `RiskDesk.ex4`, `RiskDesk.ex5`, `BrokerProbe.ex4/.ex5`, short user guide (PDF/MD).
