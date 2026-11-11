# 06 — Trade Operations

One section per button (OP-xx) plus the gateway primitives (G-xx) they share. Algorithms are written platform-neutral; MT4/MT5 specifics are called out.

## 0. Common command skeleton

Every command in `App/Commands.mqh` follows this shape:

```
1. Guard        if State.busy or within InpClickCooldownMs of the last click on this button → ignore (no status)
                reset the button's OBJPROP_STATE; State.busy = true; button → "working"
2. Pre-flight   PF checks (below) needed by this command
3. Plan         read specs/quote/lines → Domain planner/validators → STradePlan or refusal
4. Confirm      if this command's confirm setting is on → MessageBox(YES/NO); NO → amber "Cancelled"
5. Execute      gateway calls (G-xx)
6. Report       status bar (ok / warn / error) + log line(s) + screenshot (if success and enabled)
7. Cleanup      State.busy = false; refresh panel
```

### Pre-flight checks (PF)
| ID | Check | Used by |
|---|---|---|
| PF-1 | BC-15 permission chain (connection, algo trading, EA permission, account, symbol trade mode) | every trading command |
| PF-2 | Fresh `SSymbolSpec` passes BC-02 sanity | every trading command |
| PF-3 | Fresh quote available | OP-03/04/07/09 |
| PF-4 | Risk % valid | OP-03/04/07 |
| PF-5 | Required lines exist for the mode | OP-03/04/07 |

## 1. Line commands

### OP-01 Add Line (F-04)
1. If mode is PENDING → delete pending lines (status note).
2. If mode is MARKET and lines exist → amber "Lines already on chart"; stop.
3. Create SL, plus the TP line in Manual TP line mode (F-17), at default placement (05 §5). Mode = MARKET.
4. Refresh preview (Lots, labels, button dimming).

### OP-02 Delete Line (F-05)
Delete `RD_LN_*` and `RD_LT_*`; mode = NONE; Lots `—`; Pending Info empty. Status "Lines removed".

### OP-05 Add Pend Line (F-07)
Same as OP-01 for PENDING mode with Entry/SL/TP and pending styles.

### OP-06 Pending Info (F-08) — continuous
On every refresh in PENDING mode: classify (04 §7), compute lots, write `RD_E_PINFO`, update labels. No trading.

### OP-15 Lots preview (F-03) — continuous
On every refresh: MARKET mode → preview side from SL (04 §6), entry = Ask/Bid, compute lots (04 §2–4). PENDING → from OP-06. Cache the last inputs (prices, risk %, specs version) and skip recomputation when unchanged.

## 2. Opening trades

### OP-03 Buy / OP-04 Sell (F-06, F-16, F-17, F-31)
```
PF-1..PF-5
lines  = Lines.Read() normalized
quote  = Market.Quote()
side   = BUY | SELL (button)
entry  = ask | bid
validate side vs SL/TP (04 §6) and BC-07 distances         → refuse with the specific reason
tp     = TP mode: NONE → 0 · AUTO_RR → TpFromRR(side, entry, sl) · MANUAL_LINE → lines.tp
loss   = Money.LossPerLot(side, entry, sl) + comm            → refuse if unavailable (BC-05)
lots   = RiskMath.LotsFromRisk(...)                          → refuse below min (04 §4)
budget = RiskBudget.Check(open risk + this)                  → refuse with numbers
netting? (BC-10) same-direction → confirm merge; opposite → refuse unless allowed
margin = Money.MarginFor(side, lots, entry)                  → refuse or reduce (BC-09)
[confirm if InpConfirmTrades]
res    = G-01 OpenMarket(side, lots, sl, tp)
ok     → status "Buy 0.50 EURUSD @1.10012 · risk $100.00 (1.00 %) · #123456"
         delete lines unless InpKeepLinesAfterTrade; screenshot "buy"/"sell"
fail   → status red with message from gateway
```
Entry/TP are recomputed from a fresh quote inside G-01 on each retry; lots stay fixed.

### OP-07 Set Pending (F-09)
```
PF-1..PF-5 (PENDING mode)
classify (04 §7) → kind + side, or refuse with the classification message
validate BC-07 for that kind
tp    = TP mode: NONE → 0 · AUTO_RR → TpFromRR(side, entry, sl) · MANUAL_LINE → lines.tp
loss/lots/budget/margin as OP-03 (entry = Entry line)
ACCOUNT_LIMIT_ORDERS check (BC-09)
res   = G-02 PlacePending(kind, side, lots, entry, sl, tp)
ok    → "Buy Stop 0.35 EURUSD @1.10250 placed · risk $100.00 (1.00 %) · #123457"; delete lines unless keep; screenshot "pending"
```

## 3. Managing trades

Scope helpers:
- `ChartScope()` = positions/orders with `symbol == _Symbol` and, when `InpScopeChartOps = TOOL_ONLY`, `magic == InpMagic`. Default `ALL_ON_SYMBOL` (matches the original).
- `AccountScope()` = all positions, or tool-only when `InpScopeFullClose = TOOL_ONLY`. Default `ALL`.

Always **collect tickets first**, then act on the list; re-select each ticket before acting (it may have closed meanwhile → count as "already closed").

### OP-08 Del Pending (F-10)
```
orders = G-07 ListPending(ChartScope())                 limit + stop (MT5: also stop-limit)
none   → amber "No pending orders on EURUSD"
for each: G-05 DeletePending(ticket)                     BC-07 freeze check first
status "Deleted 3 of 3 pending orders" (amber if any failed, failures listed in tooltip/log)
screenshot "delpending" if ≥ 1 deleted
```

### OP-09 Risk Free (F-11)
```
positions = G-06 ListPositions(ChartScope())
for each p:
   if p.profit ≤ 0 (price-wise: buy bid ≤ open, sell ask ≥ open) → skip "not in profit"
   target = 04 §9
   if not applicable → skip with reason (not enough profit / already protected / frozen)
   G-03 ModifyPositionSLTP(p.ticket, target, p.tp)
status "Risk-free: 2 moved · 1 not enough profit · 1 already protected"
screenshot "riskfree" if ≥ 1 moved
```
"In profit" is judged by price versus open price (not by `profit` money, which includes swap/commission), so the result is independent of broker accounting.

### OP-10 Half Close (F-12)
```
positions = G-06 ListPositions(ChartScope())
for each p: closeVol = 04 §10
   indivisible → SKIP (report) or CLOSE_ALL per InpPartialIndivisible
   G-04 ClosePosition(p.ticket, closeVol)
[confirm if InpConfirmHalfClose]
status "Half-closed 2 positions (0.25 + 0.10 lot) · 1 skipped (0.01 lot indivisible)"
screenshot "half"
```
MT4: the remainder gets a new ticket; do not reuse the old one. MT5 netting: one position, opposite deal of `closeVol` (BC-10).

### OP-11 Chart Close (F-13)
```
positions = G-06 ListPositions(ChartScope());  none → amber "No positions on EURUSD"
[confirm if InpConfirmChartClose]
for each: G-04 ClosePosition(ticket, full volume)
status "Closed 3 of 3 positions on EURUSD · P/L −$12.40"   (sum of realized profit from results/history)
screenshot "chartclose"
```

### OP-12 Full Close (F-14)
```
positions = G-06 ListPositions(AccountScope())
[confirm if InpConfirmFullClose (default true): "Close 9 positions on 4 symbols?"]
for each (grouped by symbol): G-04 ClosePosition(ticket, full volume); status progress "Closing 4/9…" (redraw)
if InpFullCloseAlsoPending: delete pending in AccountScope as well
status summary; failures listed (symbol, ticket, reason)
screenshot "fullclose"
```

### OP-16 Move a pending order by dragging its overlay line (F-22)
Triggered by `CHARTEVENT_OBJECT_DRAG` on `RD_PO_<ticket>_EN/SL/TP` (sent when the line is dropped). A drop is a deliberate user action (ADR-014) and ends like every command with a status message and a log line; a refused move always puts the line back.
```
order  = re-select ticket                 gone → amber "Order #123457 no longer exists"; remove its overlay
busy   → snap back; amber "Busy – try again"
new    = entry line dropped → price = dropped price; sl and tp shift by the same distance (0 stays 0), as in the original
         SL or TP line dropped → only that level changes
         all normalized to tick size
validate  entry move keeps the order type valid (04 §7: a Buy Stop stays above Ask, a Buy Limit below, …)
          SL/TP on the correct side of the entry; BC-07 stops and freeze levels
risk   = LossPerLot(side, new.price, new.sl) × volume + comm × volume      (lot unchanged)
         above InpMaxRiskPerTradePct, or total cap with the old contribution replaced (04 §5) → refuse
         above the panel's Risk % → allowed, amber note "risk now 1.40 % (panel 1.00 %)"
res    = G-08 ModifyPending(ticket, new.price, new.sl, new.tp)
ok     → green "Buy Stop #123457 SL 3985.00 · risk $30.12 (0.30 %)"; labels updated; screenshot "modify"
refused / failed → line snaps back to the order's current value; red status with the reason
```

## 4. Other

### OP-13 Spread (F-15) — continuous
`spreadPts = round((ask − bid) / point)`; pips = pts / 10 for 3/5-digit FX symbols, else = pts.

### OP-14 Screenshot (F-19)
`ChartScreenShot(0, path, width, height, ALIGN_RIGHT)` with width/height from `InpShotWidth/Height` (0 → current chart size). Path `RiskDesk\Screenshots\<login>_<symbol>_<TF>_<yyyy-mm-dd_HH-MM-SS>_<action>_<ticket>.png` (symbol sanitized: `/ \ : * ? " < > |` → `_`). Taken after the chart has been redrawn with the new state. Manual camera button → action `manual`, ticket `0`.

## 5. Gateway primitives (Platform/TradeGateway*.mqh)

All primitives: log request and every attempt; apply BC-13 retries, BC-14 ambiguity handling; return `SResult` with final user message and ticket.

### G-01 OpenMarket(side, lots, sl, tp)
**MT5**
```
req.action=TRADE_ACTION_DEAL, symbol, volume=lots, type=BUY|SELL, price=fresh ask|bid (normalized),
req.sl, req.tp (or 0,0 if symbol is known to need ModifyAfter, BC-11), deviation=InpSlippagePoints,
magic=InpMagic, comment=InpComment, type_filling = first candidate (BC-06), type_time=ORDER_TIME_GTC
loop attempts:
   OrderSend(req, res)
   DONE/DONE_PARTIAL → position id = HistoryDealGetInteger(res.deal, DEAL_POSITION_ID)
                       (HistoryDealSelect / HistorySelect around now first); break
   INVALID_FILL      → next filling candidate, same attempt count
   INVALID_STOPS     → if our BC-07 check passed and SL/TP were attached → resend without SL/TP (BC-11)
   retry codes       → wait, refresh price (and TP in Auto R/R mode), retry
   ambiguous         → BC-14
   fatal             → return error
verify: PositionSelectByTicket(positionId) → SL/TP equal (± half tick)? else G-03 with retries
        still missing → if InpCloseIfStopFails: G-04 full close; return error "SL could not be attached – position closed"
```
**MT4**
```
wait trade context (≤ 5 s); RefreshRates()
ticket = OrderSend(sym, OP_BUY|OP_SELL, lots, ask|bid, InpSlippagePoints, sl, tp, comment, magic, 0, clrNONE)
errors per 03 §5 (130 → BC-11 fallback: send with 0/0 then OrderModify)
verify: OrderSelect(ticket, SELECT_BY_TICKET) → OrderStopLoss/OrderTakeProfit; fix or close as above
```

### G-02 PlacePending(kind, side, lots, price, sl, tp)
**MT5:** `TRADE_ACTION_PENDING`, type BUY_LIMIT/SELL_LIMIT/BUY_STOP/SELL_STOP, price normalized, `type_time` per BC-08 ladder, `type_filling` per BC-06 pending ladder, magic, comment. Success = `PLACED`/`DONE` with `res.order` as ticket.
**MT4:** `OrderSend(sym, OP_BUYLIMIT..OP_SELLSTOP, lots, price, 0, sl, tp, comment, magic, expiration, clrNONE)`; expiration per BC-08.

### G-03 ModifyPositionSLTP(ticket, sl, tp)
**MT5:** `TRADE_ACTION_SLTP`, `position=ticket`, `symbol`, `sl`, `tp` (pass the current TP when only SL changes), `magic`. `NO_CHANGES` = success.
**MT4:** `OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrNONE)`; error 1 = success; skip the call when values are already equal.
Both: BC-07 stops and freeze checks first.

### G-04 ClosePosition(ticket, volume)
**MT5 hedging:** `TRADE_ACTION_DEAL`, `position=ticket`, opposite type, `volume`, price = fresh bid (closing a buy) / ask (closing a sell), filling ladder, deviation, magic.
**MT5 netting:** same without relying on `position` (an opposite deal of `volume` on the symbol); never exceed the position volume (that would reverse it).
**MT4:** `OrderClose(ticket, volume, bid|ask, InpSlippagePoints, clrNONE)`.
Both: `volume` floored to step; BC-07 freeze check; "already closed" → success.

### G-05 DeletePending(ticket)
**MT5:** `TRADE_ACTION_REMOVE`, `order=ticket`. **MT4:** `OrderDelete(ticket)`.

### G-08 ModifyPending(ticket, price, sl, tp)
**MT5:** `TRADE_ACTION_MODIFY`, `order=ticket`, `price`, `sl`, `tp`, and the order's current `type_time` and `expiration` unchanged (BC-08). `NO_CHANGES` = success.
**MT4:** `OrderModify(ticket, price, sl, tp, OrderExpiration(), clrNONE)`; error 1 = success.
Both: BC-07 stops and freeze checks first. The volume cannot be changed (MetaTrader does not allow it on a placed order).

### G-06 ListPositions(filter) → SPosition[]
**MT5:** `PositionsTotal()` → `PositionGetTicket(i)` → read `POSITION_SYMBOL, TYPE, VOLUME, PRICE_OPEN, SL, TP, PROFIT, MAGIC`.
**MT4:** `OrdersTotal()` → `OrderSelect(i, SELECT_BY_POS, MODE_TRADES)` → `OrderType() <= OP_SELL`.
Also fills `lossToSl` via Money.LossPerLot for RiskBudget.

### G-07 ListPending(filter) → SOrder[]
**MT5:** `OrdersTotal()` → `OrderGetTicket(i)` → types LIMIT/STOP (and STOP_LIMIT when listing for deletion).
**MT4:** same loop as G-06 with `OrderType() >= OP_BUYLIMIT`.

## 6. Logging format (every gateway attempt)

```
2026.11.09 10:43:21.512 [INFO ] [G-01] EURUSD BUY 0.50 @1.10012 sl=1.09800 tp=1.10436 dev=20 fill=FOK magic=772211 attempt=1
2026.11.09 10:43:21.689 [WARN ] [G-01] EURUSD retcode=10030 INVALID_FILL "Unsupported filling mode" → next fill=IOC
2026.11.09 10:43:21.811 [INFO ] [G-01] EURUSD retcode=10009 DONE deal=987654 position=123456 price=1.10013 vol=0.50
2026.11.09 10:43:21.830 [INFO ] [G-01] verify SL/TP ok (1.09800/1.10436)
```
