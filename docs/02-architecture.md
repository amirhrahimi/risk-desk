# 02 — Architecture

## 1. Quality goals (in priority order)

1. **Risk correctness**: the money lost at SL never exceeds what the user asked for.
2. **Broker portability**: same behaviour on any MT4/MT5 server; no hard-coded broker assumptions.
3. **Observability**: every refusal or failure is visible and explained (status bar + log).
4. **Single codebase**: one source tree compiles to `.ex4` and `.ex5`.
5. **Testability**: all money/price/volume math is pure and unit-tested.
6. **Responsiveness**: the panel never blocks the terminal longer than one trade request.

## 2. Context

```
 ┌───────────┐  clicks / drags   ┌──────────────────────────┐   MQL API    ┌───────────────┐   network  ┌────────────┐
 │  Trader   │ ───────────────▶  │ RiskDesk EA (one chart)  │ ───────────▶ │ MT4 / MT5     │ ─────────▶ │ Broker     │
 │           │ ◀───────────────  │ panel + lines + logic    │ ◀─────────── │ terminal      │ ◀───────── │ trade srv  │
 └───────────┘  status, labels   └──────────────────────────┘   events      └───────────────┘            └────────────┘
                                           │ files
                                           ▼
                                 MQLx/Files/RiskDesk/ (state, logs, screenshots, probe reports)
```

One EA instance per chart. Instances do not talk to each other; account-wide data (open risk, positions) is always read fresh from the terminal.

## 3. Layers and dependency rule

```
  Entry files (RiskDesk.mq4 / RiskDesk.mq5)      OnInit/OnDeinit/OnTick/OnTimer/OnChartEvent → CApp
        │
        ▼
  App      CApp (composition root) · CController (event → command) · Commands · CState · CSettings · Inputs
   │  │
   │  └──────────────▶ UI        CPanel · widgets · CLines · CPendingOverlay · CStatusBar · CTheme · CLayout
   │                    Services  CLogger · CPersistence · CScreenshot · CChartHousekeeping · CCandleTime
   ▼
  Domain   (pure)     Types · PriceMath · RiskMath · Validators · Planner · RiskBudget
   ▲
   │ uses Domain types only
  Platform (only place with #ifdef)  Compat · SymbolSpec · AccountSpec · Market · Money · TradeGateway · History
```

Rules:
- Domain depends on nothing (not even Platform). It receives plain structs and returns plain structs.
- Platform depends only on Domain types. It is the only layer that calls trade/symbol/account functions.
- UI never calls Platform for trading; it renders state and raises events.
- App orchestrates: reads specs/quotes through Platform, asks Domain to plan/validate, asks Platform to execute, tells UI what to show.

## 4. Compile model (one tree, two targets)

- `src/Experts/RiskDesk/RiskDesk.mq4` and `.mq5` are ~30-line shells: `#property` lines, includes, and the five event handlers forwarding to a global `CApp g_app`.
- `Platform/Compat.mqh` normalises the language differences:
  - `#ifdef __MQL5__ ... #else ... #endif` blocks that provide common helpers (`RdBid()`, `RdAsk()`, `RdIsTester()`, `RdTerminalDpi()`, ...).
  - Own enums for side and order kind so Domain never touches `OP_*` or `ORDER_TYPE_*`.
- `Platform/TradeGateway.mqh` includes either `TradeGatewayMT5.mqh` or `TradeGatewayMT4.mqh`. Both define the **same class name `CTradeGateway` with the same public methods** (compile-time selection, no virtual dispatch). Same pattern for `History.mqh` and the platform-specific parts of `Money.mqh`.
- `App/Inputs.mqh` is the only other `#ifdef` place: MQL5 uses `input group "Risk"`; MQL4 has no input groups, so it uses `sinput string InpSep_Risk = "──── Risk ────";` separators.
- MQL4 entry files carry `#property strict`.

## 5. Module responsibilities

### Platform
| Module | Responsibility | Key API (indicative) |
|---|---|---|
| Compat | Language shims, common enums | `RdBid(sym)`, `RdAsk(sym)`, `RdIsTester()`, `RdIsVisualTester()`, `RdDpiScale()` |
| SymbolSpec | Read all symbol properties into `SSymbolSpec`, with sanity checks | `bool Read(string sym, SSymbolSpec &s, SResult &r)` |
| AccountSpec | Read account/terminal properties into `SAccountSpec` | `bool Read(SAccountSpec &a, SResult &r)`, `bool CanTrade(SResult &why)` |
| Market | Fresh quotes | `bool Quote(string sym, SQuote &q)` |
| Money | Money↔price conversions in account currency | `bool LossPerLot(sym, side, entry, sl, double &loss, SResult &r)`, `bool ProfitPerLot(...)`, `bool MarginFor(sym, side, lots, price, double &m)`, `double MaxLotsByMargin(...)` |
| TradeGateway | Execute requests with filling/expiration/retry/verification logic (BC rules) | `OpenMarket`, `PlacePending`, `ModifyPositionSLTP`, `ModifyPending(ticket, price, sl, tp)`, `ClosePosition(ticket, volume)`, `DeletePending`, `ListPositions(filter, SPosition &arr[])`, `ListPending(filter, SOrder &arr[])` |
| History | Closed trades (realized P/L for close summaries; future history overlay) | `bool ClosedTrades(sym, from, SClosedTrade &arr[])` |

### Domain
| Module | Responsibility |
|---|---|
| Types | `ESide`, `EOrderKind`, `ELineMode`, `SSymbolSpec`, `SAccountSpec`, `SQuote`, `SLines`, `STradePlan`, `SPosition`, `SOrder`, `SResult` |
| PriceMath | `NormalizePrice`, `RoundPriceUp/Down`, `PriceEq/Lt/Gt` (half-tick tolerance), `PointsBetween`, `VolumeDigits`, `FloorVolume`, `IsValidVolume` |
| RiskMath | `LotsFromRisk(riskMoney, lossPerLot, commissionPerLot, spec, SLotResult &)`, `RiskMoney(base, pct)`, `TpFromRR(side, entry, sl, rr, spec)` |
| Validators | Market side validation, stops-level/freeze-level checks, pending classification, risk-input parsing |
| Planner | Build an `STradePlan` (side, kind, entry, sl, tp, lots, money risk, warnings) from lines + quote + specs + settings; no I/O |
| RiskBudget | Sum open risk from `SPosition[]`/`SOrder[]` (with their precomputed loss-to-SL), check caps |

### App
| Module | Responsibility |
|---|---|
| Inputs | All `input` declarations (see 07-settings) |
| Settings | Validated, immutable snapshot of inputs + derived values; validation errors surfaced on init |
| State | Mutable UI/session state: line mode, busy flag, last click time, risk %, panel position, hidden flag, last status |
| Controller | Maps chart events and timer ticks to commands; owns the busy/re-entrancy guard and click cooldown |
| Commands | One function/class per button (`CmdAddLine`, `CmdBuy`, ... `CmdFullClose`); each: pre-checks → plan → execute → status → screenshot → log |
| App | Composition root: creates everything in `OnInit`, wires dependencies, owns timer |

### UI
| Module | Responsibility |
|---|---|
| Theme | Colours, fonts, sizes (from Settings) |
| Layout | Scaled geometry (scale × DPI/96, scale reduced by auto-fit F-34); computes every widget rectangle from a y-cursor |
| Widgets | Thin wrappers over chart objects: `CRdButton`, `CRdEdit`, `CRdLabel`, `CRdRect`. Create/update only when a property changed (dirty flags) |
| Panel | Builds the panel (05-ui-spec §2), drag, hide, clamp-to-view, exposes `Render(SPanelModel&)` |
| Lines | Create/adopt/delete SL/TP/Entry lines and their text labels; read prices |
| StatusBar | Message with severity colour, auto-fades to the idle readout after `InpStatusHoldSec` |
| PendingOverlay | Draws placed pending orders of the chart symbol with overlay colours and labels (F-22); rebuilds only when the order list changes; passes a dropped overlay line to the Controller (OP-16) and snaps it back when the move is refused |

### Services
Logger (Experts tab + optional daily file), Persistence (key=value files), Screenshot, ChartHousekeeping (closed-trade objects, F-20), CandleTime (F-21).

## 6. Core data structures (indicative, Domain/Types.mqh)

```cpp
enum ESide        { SIDE_BUY = 0, SIDE_SELL = 1 };
enum EOrderKind   { KIND_MARKET, KIND_LIMIT, KIND_STOP };
enum ELineMode    { LINES_NONE, LINES_MARKET, LINES_PENDING };
enum ESeverity    { SEV_OK, SEV_WARN, SEV_ERROR };

struct SSymbolSpec {
  string name; int digits; double point, tickSize, tickValue, tickValueLoss, contractSize;
  double volMin, volMax, volStep, volLimit;          // volLimit = 0 when unlimited / MT4
  int    stopsLevel, freezeLevel;                    // in points
  int    fillingFlags, expirationFlags, orderModeFlags; // MT5 flags, 0 on MT4
  int    tradeMode, execMode, calcMode;
  string baseCcy, profitCcy, marginCcy;
};
struct SAccountSpec {
  long login; string currency, server, company; double balance, equity, freeMargin; long leverage;
  bool hedging; bool isCent; bool isDemo; bool terminalTradeAllowed, eaTradeAllowed, accountTradeAllowed, accountExpertAllowed;
  int  limitOrders; int digitsCcy;
};
struct SQuote   { double bid, ask; datetime time; };
struct SLines   { ELineMode mode; double sl, tp, entry; bool hasTp; };
struct STradePlan {
  ESide side; EOrderKind kind; double entry, sl, tp, lots;
  double lossPerLot, riskMoney, riskPct, rewardMoney, rr; string warnings;
};
struct SPosition { ulong ticket; string symbol; ESide side; double volume, open, sl, tp, profit; long magic; double lossToSl; };
struct SOrder    { ulong ticket; string symbol; ESide side; EOrderKind kind; double volume, price, sl, tp; long magic; double lossToSl; };
struct SResult   { bool ok; ESeverity sev; int code; string message; ulong ticket; };
```
(`ulong` tickets work in MQL4 as well; cast to `int` only inside the MT4 gateway.)

## 7. Event flow

### 7.1 Handlers
| Handler | Does |
|---|---|
| `OnInit` | Read settings → validate → read specs → load persisted state → build panel → adopt existing lines → `EventSetMillisecondTimer(InpRefreshMs)` → enable `CHART_EVENT_MOUSE_MOVE` |
| `OnTimer` | Refresh quote/spread/button prices; recompute preview plan if inputs changed (lines, price, risk); update labels; candle time; status fade. Redraw only if something changed. |
| `OnTick` | Same light refresh as timer (keeps prices instant on fast markets). In the Strategy Tester also polls button states (§10). |
| `OnChartEvent` | `OBJECT_CLICK` → Controller; `OBJECT_ENDEDIT` (risk field); `OBJECT_DRAG` (planning lines → recompute; overlay lines `RD_PO_*` → OP-16); `MOUSE_MOVE` (panel drag); `CHART_CHANGE` (re-clamp panel, re-anchor labels) |
| `OnDeinit` | Save state. `REASON_CHARTCHANGE` / `REASON_PARAMETERS` / `REASON_RECOMPILE`: keep objects. `REASON_REMOVE`: delete all `RD_` objects. Always `EventKillTimer()`. |

Note: `REASON_CHARTCHANGE` does not say whether the symbol or the period changed. Persist the symbol in the hidden chart object `RD_S_CHART`; on the next `OnInit` compare it and delete lines if it differs (F-23 AC2, ADR-021).

### 7.2 Sequence: user clicks Buy
```
Click "RD_BTN_BUY"
 → Controller: busy? cooldown? → reset button OBJPROP_STATE
 → CmdBuy
    1 AccountSpec.CanTrade()              terminal/EA/account/symbol trade permissions
    2 Market.Quote(); SymbolSpec.Read()   fresh every click (specs cached, refreshed every 60 s)
    3 Lines.Read() → SLines               normalized to tick size
    4 Validators.MarketSide(BUY, lines, quote, spec)       SL<Bid−stops, TP>Bid+stops
    5 Money.LossPerLot(BUY, ask, sl) (+commission)          BC-05
    6 RiskMath.LotsFromRisk → lots                          floor to step, min/max
    7 RiskBudget.Check(open risk + new)                     F-16
    8 Money.MarginFor → margin check                        F-31
    9 [confirm if enabled]
   10 TradeGateway.OpenMarket(plan)                         filling ladder, retries, SL verify (BC-06/11/13/14)
   11 StatusBar ✔ "Buy 0.50 EURUSD @1.10012 · risk $100.00 (1.00 %) · #123456"
   12 Lines.Delete() (unless keep) · Screenshot · Log
```
Each step that fails returns `SResult` with a message; the command stops and shows it. No step is skipped silently.

## 8. State and persistence

| Data | Where | Key | When written |
|---|---|---|---|
| Panel x, y, hidden, scale override | `Files/RiskDesk/ui.ini` | global | on change (debounced 1 s) and `OnDeinit` |
| Risk % | `Files/RiskDesk/acct_<login>.ini` | per account | on valid edit |
| Last symbol of the chart | hidden chart object `RD_S_CHART` (its text) | per chart | every `OnInit` (ADR-021: chart IDs are not stable across sessions, so a `chart_<ChartID>.ini` could belong to another chart) |
| Lines | the chart objects themselves | object names | MT keeps objects across timeframe change and saves them with the chart |

On `OnInit`, lines found on the chart by name are **adopted** (not recreated) so a timeframe change never duplicates or moves them. Use files, not terminal GlobalVariables: they hold strings, are human-readable and survive terminal reinstallation of the data folder backup.

## 9. MT4 ↔ MT5 mapping (inside Platform only)

| Concern | MT4 | MT5 |
|---|---|---|
| Quote | `RefreshRates()` + `SymbolInfoTick` | `SymbolInfoTick` |
| Market order | `OrderSend(sym, OP_BUY/OP_SELL, ...)` | `OrderSend` with `TRADE_ACTION_DEAL` |
| Pending | `OrderSend(OP_BUYLIMIT/…/OP_SELLSTOP, ..., expiration)` | `TRADE_ACTION_PENDING` + `type_time` |
| Modify position SL/TP | `OrderModify(ticket, open, sl, tp, 0)` | `TRADE_ACTION_SLTP` with `position=ticket` |
| Close / partial | `OrderClose(ticket, lots, price, slippage)` (partial creates a new ticket) | Hedging: `TRADE_ACTION_DEAL` opposite with `position=ticket`, partial volume allowed. Netting: opposite deal reduces the single position (BC-10) |
| Delete pending | `OrderDelete` | `TRADE_ACTION_REMOVE` |
| List positions | `OrdersTotal` + `OrderSelect(i, SELECT_BY_POS, MODE_TRADES)`, `OrderType() <= OP_SELL` | `PositionsTotal` + `PositionGetTicket(i)` |
| List pending | same loop, `OrderType() >= OP_BUYLIMIT` | `OrdersTotal` + `OrderGetTicket(i)` |
| History | `OrdersHistoryTotal` + `MODE_HISTORY` | `HistorySelect` + deals (`DEAL_ENTRY_IN/OUT`, `DEAL_POSITION_ID`) |
| Loss per lot | tick-value formula + cross-check (BC-05) | `OrderCalcProfit` (fallback: `SYMBOL_TRADE_TICK_VALUE_LOSS`) |
| Margin | `AccountFreeMarginCheck`, `MarketInfo(MODE_MARGINREQUIRED)` | `OrderCalcMargin` |
| Pre-check | none | `OrderCheck` |
| Filling policy | not applicable | `SYMBOL_FILLING_MODE` flags + ladder (BC-06) |
| Expiration | `expiration` arg (0 = GTC) | `SYMBOL_EXPIRATION_MODE` flags + ladder (BC-08) |
| Netting accounts | do not exist | `ACCOUNT_MARGIN_MODE` (BC-10) |
| Error source | `GetLastError()` | `MqlTradeResult.retcode` (+ `GetLastError()` when `OrderSend` returns false) |
| Input grouping | `sinput string` separators | `input group` |

## 10. Strategy Tester behaviour

`OnChartEvent` is not called for Expert Advisors in the Strategy Tester, even in visual mode. When `MQLInfoInteger(MQL_TESTER)` is true, the Controller polls each button's `OBJPROP_STATE` in `OnTick` and dispatches the same commands. This works reliably in the MT4 visual tester; in the MT5 visual tester button clicks may not register, so the tester is a convenience for MT4, not a test requirement. Real verification happens on demo accounts (08-testing).

## 11. Chart objects

| Object | Name | Type |
|---|---|---|
| Panel background | `RD_P_BG` | `OBJ_RECTANGLE_LABEL` |
| Move handle | `RD_P_HANDLE` | small `OBJ_BUTTON` with a glyph (MT4: Wingdings, ADR-021) |
| Title / hide toggle | `RD_P_TITLE` ("Risk"), `RD_P_TITLE2` ("Desk", accent), `RD_P_HIDE` | `OBJ_LABEL`, `OBJ_LABEL`, `OBJ_BUTTON` |
| Field captions | `RD_L_RISK`, `RD_L_LOTS`, `RD_L_PINFO` | `OBJ_LABEL` |
| Risk / Lots fields | `RD_E_RISK`, `RD_E_LOTS` | `OBJ_EDIT` (Lots read-only) |
| Buttons | `RD_B_ADDLINE`, `RD_B_DELLINE`, `RD_B_BUY`, `RD_B_SELL`, `RD_B_ADDPEND`, `RD_B_SETPEND`, `RD_B_DELPEND`, `RD_B_RISKFREE`, `RD_B_HALF`, `RD_B_CHARTCLOSE`, `RD_B_FULLCLOSE`, `RD_B_SHOT` | `OBJ_BUTTON` |
| Pending info | `RD_E_PINFO` | `OBJ_EDIT` read-only |
| Spread / status | `RD_L_SPREAD`, `RD_L_STATUS1..3` | `OBJ_LABEL` |
| Chart symbol memory | `RD_S_CHART` | `OBJ_LABEL`, hidden on every timeframe |
| Lines | `RD_LN_SL`, `RD_LN_TP`, `RD_LN_EN` | `OBJ_HLINE` |
| Line labels | `RD_LT_SL`, `RD_LT_TP`, `RD_LT_EN` | `OBJ_TEXT` |
| Pending order overlay | `RD_PO_<ticket>_EN/SL/TP` (lines), `RD_PT_<ticket>_EN/SL/TP` (labels) | `OBJ_HLINE` (selectable), `OBJ_TEXT` |
| Candle time | `RD_CT` | `OBJ_TEXT` |

All panel objects use `CORNER_LEFT_UPPER` with x/y computed by Layout; the panel moves by rewriting `OBJPROP_XDISTANCE/YDISTANCE` of every panel object.

## 12. Concurrency and re-entrancy

- A single `busy` flag in State. While busy, clicks are ignored (buttons drawn in a "working" colour), and the status shows progress.
- MT4: wait up to 5 s for `IsTradeContextBusy()` to clear before each request.
- Requests are synchronous (`OrderSend`, not `OrderSendAsync`), see ADR-010.
- Collect tickets first, then act; never modify while iterating the terminal's live list.

## 13. Error model

Every Platform/Domain function returns `bool` and fills `SResult`. `SResult.message` is final, user-facing English. Mapping of broker codes to messages lives in `03-broker-compatibility.md` §5 and is implemented once in the gateway.

## 14. Extension points (v1.x)

Hotkeys (Controller), multiple TPs (Planner + gateway loop), trailing stop (new command + timer hook), manual lot override (Planner input), translations (string table in UI).
