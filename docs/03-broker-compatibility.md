# 03 — Broker Compatibility

This is the document that makes RiskDesk work where the original does not. Every rule has an ID (BC-xx). Trade code must implement all of them; tests in `08-testing.md` reference them.

## 1. Why a risk panel works at one broker and fails at another

The owner's original tool works at IG and fails at IC Markets EU and Dukascopy. Without its source we cannot be certain which of the causes below apply, but these are the usual ones, ordered by likelihood for these brokers:

| # | Cause | Typical symptom | Where it bites | Our rule |
|---|---|---|---|---|
| H1 | MT5 filling policy hard-coded (FOK or IOC) | `Unsupported filling mode` (retcode 10030, often shown as error 4756) | MT5 servers that only accept one policy; frequently reported with IC Markets MT5 | BC-06 |
| H2 | Volume assumed to be min 0.01 / step 0.01 / 2 decimals | `Invalid volume`, or lot computed as 0 → nothing happens | Dukascopy: many CFDs trade in whole contracts (indices min 1 / step 1, ETH min 1 / step 0.1, LTC min 10, XAG min 0.5) | BC-04 |
| H3 | Tick value / currency conversion wrong or zero | Wrong lot size, or 0 lots → nothing happens | EUR (or CHF/GBP/PLN…) accounts trading USD-quoted instruments; CFDs whose tick value is reported oddly | BC-05, BC-12 |
| H4 | Margin under EU leverage caps or per-instrument exposure caps | `Not enough money`, `Volume limit` | ESMA retail caps at IC Markets EU and Dukascopy Europe (e.g. 30:1 major FX, 2:1 crypto); Dukascopy per-instrument max net exposure (e.g. 1 lot BTC/USD) | BC-09 |
| H5 | Prices rounded to `Digits` but not to tick size | `Invalid price` / `Invalid stops` | Index and metal CFDs whose tick size ≠ point (0.25, 0.5, 0.1 …) | BC-03 |
| H6 | Stops/freeze level ignored | `Invalid stops` (130 / 10016), `Modification denied` (145 / 10029) | Any broker with non-zero stops level | BC-07 |
| H7 | Pending expiration not accepted | `Invalid expiration` (10022 / 147) | MT5 symbols where GTC is not in `SYMBOL_EXPIRATION_MODE` | BC-08 |
| H8 | Netting account assumptions | Second trade nets the first, half close fails | MT5 netting accounts | BC-10 |
| H9 | SL/TP rejected on a market-execution order | `Invalid stops` on open, trade without SL | Some MT4 market-execution (ECN) servers | BC-11 |
| H10 | Symbol names with suffixes/slashes break conversion lookups | Lot = 0 for crosses | `EURUSD.a`, `EURUSDm`, `EUR/USD`-style names | BC-01 |
| H11 | Deliberate restriction in the original (e.g. tied to listed brokers) | Silent no-op | Unknown; its site says it was tested only with brokers it lists | Not applicable to RiskDesk |

### How the owner can confirm today with the original tool
Open the Toolbox (Ctrl+T) → **Experts** and **Journal** tabs, click Buy on IC Markets / Dukascopy, and read the last lines. `unsupported filling mode`, `invalid volume`, `not enough money`, `invalid stops`, `invalid expiration`, or **no line at all** (lot computed as zero, or a deliberate block) each point to a row above. Paste those lines into `broker-profiles/original-tool-errors.md`; they become regression cases.

## 2. Rules

### BC-01 Symbol identity
- Trade only the chart symbol (`_Symbol`) or symbols taken from the terminal's own position/order lists. Never construct trading symbol names.
- For currency-conversion lookups (MT4 fallback, BC-05), find the pair by **properties**, not names: scan `SymbolsTotal(false)` for a symbol whose `SYMBOL_CURRENCY_BASE` / `SYMBOL_CURRENCY_PROFIT` match the two currencies and whose trade mode is not disabled; prefer one already in Market Watch; `SymbolSelect(name, true)` it before reading prices. Cache the result per currency pair.

### BC-02 Read specs at runtime, sanity-check them
- Read `SSymbolSpec` on init, refresh every 60 s and before every trade request.
- Sanity: `point > 0`, `contractSize > 0`, `volStep > 0`, `volMin > 0`, `volMax ≥ volMin`. If `tickSize == 0` use `point` and log a warning. If any check fails: disable trading buttons for this symbol and show "Broker reports invalid <property> for <symbol>".
- Never cache specs across symbols or accounts.

### BC-03 Prices normalized to tick size
- `NormalizePrice(p) = NormalizeDouble(MathRound(p / tickSize) * tickSize, digits)`.
- Directional variants `RoundPriceUp/Down` for cases where the direction matters (Risk Free target, BC-07 distances).
- **Order of operations:** normalize Entry/SL/TP first, then compute lots from the normalized prices. The risk shown is always the risk of the prices actually sent.

### BC-04 Volumes normalized to the broker's grid
- `FloorVolume(raw) = volMin + MathFloor((raw − volMin) / volStep + 1e-8) × volStep`, rounded to `VolumeDigits(volStep)` decimals (digits derived from the step: 1 → 0, 0.1 → 1, 0.01 → 2, 0.001 → 3).
- `raw < volMin` → not tradable at this risk (see 04-risk-engine §4).
- `> volMax` → cap at `volMax` and warn.
- MT5: if `SYMBOL_VOLUME_LIMIT > 0`, current same-direction volume on the symbol + new volume must not exceed it.
- Never assume 0.01. Examples from Dukascopy's published MT4/MT5 specs: index CFDs min 1 / step 1; ETH/USD min 1 / step 0.1; LTC/USD min 10 / step 1; XAG/USD min 0.5 / step 0.01.

### BC-05 Money value of a price move (loss per lot)
Implemented in `Platform/Money.mqh` → `LossPerLot(sym, side, entry, sl, out loss)` returning a **positive** amount in **account currency** for 1.0 lot.
- **MT5 primary:** `OrderCalcProfit(side==BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, 1.0, entry, sl, profit)`; `loss = -profit`. Handles cross-currency conversion and all calc modes (forex, CFD, futures, exchange).
- **MT5 fallback:** `ticks × SYMBOL_TRADE_TICK_VALUE_LOSS` (or `SYMBOL_TRADE_TICK_VALUE` if 0), `ticks = |entry − sl| / tickSize`.
- **MT4 primary:** `ticks × MODE_TICKVALUE` (via `SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE)`).
- **MT4 cross-check:** `expected = tickSize × contractSize × Rate(profitCcy → accountCcy)` (Rate via BC-01 lookup, mid price). If `|tickValue − expected| / expected > 5 %`, log a warning once per symbol, show "Tick value mismatch" in the status bar, and use the **larger** of the two (smaller lot = conservative). If `expected` cannot be computed, use tickValue.
- If the result is ≤ 0, NaN, or unavailable: retry once after `SymbolSelect` of the conversion pair; if still invalid → refuse: "Cannot value a price move on <symbol> (no conversion rate)".
- Add `InpCommissionPerLot` (round turn, account currency) to the loss per lot.

### BC-06 MT5 filling policy (market orders and closes)
- Read `SYMBOL_FILLING_MODE` (bit flags). Test it with `SYMBOL_FILLING_FOK` (1) and `SYMBOL_FILLING_IOC` (2). **Never** test it with `ORDER_FILLING_FOK/IOC/RETURN`: those are enum values (0/1/2), not flags; mixing them up is a classic cause of 10030.
- Candidate ladder for market deals (open and close): the policies allowed by the flags first (FOK, then IOC), then the remaining ones as a last resort (some servers report flags that do not match what they accept), RETURN always last; under Market execution RETURN is generally not accepted for market deals.
- Candidate ladder for pending orders: RETURN, then FOK, then IOC.
- Every candidate is tried at most once per request.
- Optionally pre-screen candidates with `OrderCheck` (no execution) and skip those it rejects with `TRADE_RETCODE_INVALID_FILL`.
- On `TRADE_RETCODE_INVALID_FILL` from `OrderSend`, retry immediately with the next candidate (nothing was executed). Any other retcode is handled by BC-13/BC-14, not by the ladder.
- Cache the policy that succeeded per (symbol, action) for the session. `InpFillingOverride` (Auto/FOK/IOC/RETURN) forces one policy for diagnostics.
- MT4: not applicable.

### BC-07 Stops level and freeze level
Let `S = stopsLevel × point`, `F = freezeLevel × point`, prices normalized. Requirements before sending (MT4 and MT5 servers apply the same logic; buys close at Bid, sells close at Ask):

| Operation | Condition |
|---|---|
| Market Buy SL / TP | `Bid − SL ≥ S`, `TP − Bid ≥ S` |
| Market Sell SL / TP | `SL − Ask ≥ S`, `Ask − TP ≥ S` |
| Buy Limit | `Ask − Entry ≥ S`; `Entry − SL ≥ S`; `TP − Entry ≥ S` |
| Sell Limit | `Entry − Bid ≥ S`; `SL − Entry ≥ S`; `Entry − TP ≥ S` |
| Buy Stop | `Entry − Ask ≥ S`; `Entry − SL ≥ S`; `TP − Entry ≥ S` |
| Sell Stop | `Bid − Entry ≥ S`; `SL − Entry ≥ S`; `Entry − TP ≥ S` |
| Modify / close a buy position | not allowed while `Bid − SL ≤ F` or `TP − Bid ≤ F` (for levels that are set) |
| Modify / close a sell position | not allowed while `SL − Ask ≤ F` or `Ask − TP ≤ F` |
| Modify / delete a pending order | not allowed while the entry is within `F` of the activation price |

- When a condition fails, refuse before sending and say what is needed: "SL too close: needs ≥ 30 pts (1.10020) from Bid".
- `stopsLevel == 0` can mean "no minimum" or a floating minimum. Apply the checks with 0 and rely on the server; if the server answers `INVALID_STOPS`, show the distance used and suggest moving the line further.

### BC-08 Pending order expiration
- `InpPendingExpiryHours = 0` means "no expiry" (GTC); `> 0` means the user wants the order to expire after N hours.
- MT5: read `SYMBOL_EXPIRATION_MODE` flags.
  - User wants no expiry: `ORDER_TIME_GTC` if `SYMBOL_EXPIRATION_GTC` is set → else `ORDER_TIME_DAY` if `SYMBOL_EXPIRATION_DAY` → else `ORDER_TIME_SPECIFIED` with `expiration = TimeCurrent() + 168 h`.
  - User wants N hours: `ORDER_TIME_SPECIFIED` (if `SYMBOL_EXPIRATION_SPECIFIED`) with `TimeCurrent() + N h` → else `ORDER_TIME_SPECIFIED_DAY` → else GTC with an amber warning that expiry is not supported.
  - On `TRADE_RETCODE_INVALID_EXPIRATION`, try the next rung. Report in the status bar whenever the policy differs from what the user asked for.
- MT4: `expiration = 0` for no expiry, else `TimeCurrent() + N h`. If the server returns 147 (expiration denied), retry with 0 and warn.

### BC-09 Margin, leverage and exposure caps
- Pre-check margin: MT5 `OrderCalcMargin`; MT4 `AccountFreeMarginCheck(sym, cmd, lots)` (≤ 0 or error 134 = insufficient) or `MarketInfo(sym, MODE_MARGINREQUIRED) × lots`.
- Keep `InpMarginBufferPct` (default 5 %) of free margin unused.
- If insufficient: refuse with "Needs €2,340 margin, €1,120 free · max ≈ 0.23 lots at current leverage". Optional `InpReduceToMargin=true` sends the max affordable lot instead (amber status).
- EU retail accounts are capped by ESMA (30:1 major FX; 20:1 non-major FX, gold, major indices; 10:1 other commodities and non-major indices; 5:1 shares; 2:1 crypto). Tight stops on high-risk % hit these caps quickly.
- Some brokers cap total exposure per instrument (Dukascopy publishes a "max net exposure in lots" per instrument). MT5 may expose it as `SYMBOL_VOLUME_LIMIT`; otherwise only the server reply tells. Map `LIMIT_VOLUME` / generic rejections to a message that mentions this possibility.
- Check `ACCOUNT_LIMIT_ORDERS` (when > 0) before placing new orders.

### BC-10 Netting vs hedging (MT5)
- `hedging = (ACCOUNT_MARGIN_MODE == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)`. Treat both `..._RETAIL_NETTING` and `..._EXCHANGE` as netting.
- Netting has at most one position per symbol:
  - A new order in the **same** direction adds volume; the position's SL/TP are replaced by the new request's SL/TP. Show an amber confirm: "Netting account: this will merge with the existing 0.30 lot position and replace its SL/TP".
  - An order in the **opposite** direction reduces/reverses. Refuse by default with an explanation; allow only with `InpNettingAllowOpposite=true` and a confirm.
  - Half Close = opposite deal of the computed volume (no `position` ticket needed). Chart Close = opposite deal of the full volume.
  - Risk Free uses the position's average open price.
  - Open risk = loss from the netted position's open price to its SL.
- MT4 accounts behave like hedging (every trade is its own ticket).

### BC-11 Attaching SL/TP
- `InpStopsMode = Auto | WithOrder | ModifyAfter`.
- **Auto:** send with SL/TP. If the server answers invalid stops (MT4 130, MT5 `TRADE_RETCODE_INVALID_STOPS`) **and** our BC-07 check passed (so the server probably refuses stops on market-execution orders), resend without SL/TP and immediately modify the position to add them. Remember per symbol that this server needs ModifyAfter.
- **Verify** after every open: select the position and compare SL/TP to the request (± half tick). Missing or wrong → modify with retries. Still failing → close the position if `InpCloseIfStopFails` (default true), red status "SL could not be attached – position closed".
- MT5: if `SYMBOL_ORDER_MODE` lacks the SL flag (`SYMBOL_ORDER_SL`), refuse trading: "Broker does not accept SL on this symbol".

### BC-12 Account currency, cent accounts, display
- All money math stays in account currency. Display symbol map: USD `$`, EUR `€`, GBP `£`, JPY `¥`; others show the ISO code after the amount.
- Cent detection (`InpCentMode=Auto`): currency in {`USC`, `EUC`, `GBC`, `USc`, `EUc`} or containing `cent` (case-insensitive). With cent mode, labels show `−1,000.00 USC ($10.00)` using `InpCentDivisor` (100). Lot math is unchanged.

### BC-13 Retries
- Max `InpMaxRetries` (3) per request, delay `InpRetryDelayMs` (300 ms) doubling each time.
- Before each retry: refresh the quote (MT4 `RefreshRates()`), recompute market price, keep the same lot (do not resize on retry).
- Retry only codes marked **retry** in §5. **fix** codes trigger their specific fallback once. **fatal** codes stop immediately with their message.
- Market orders use `InpSlippagePoints` as deviation (MT4 `slippage` argument, MT5 `request.deviation`).

### BC-14 Ambiguous results (no blind resend)
- MT4 128 (trade timeout), MT5 `TRADE_RETCODE_TIMEOUT` / `TRADE_RETCODE_CONNECTION`, or `OrderSend` returning false without a usable retcode: the request may or may not have executed.
- Wait 1 s, then scan positions/orders for one with our magic, same symbol, side/type, volume, and open time ≥ request time − 5 s. Found → treat as success and continue (verify SL/TP). Not found → retry once. Log both branches.

### BC-15 Trade permissions (checked before every command, with specific messages)
| Check | Message |
|---|---|
| `TERMINAL_CONNECTED` | "No connection to trade server" |
| `TERMINAL_TRADE_ALLOWED` | "Algo/AutoTrading is off in the terminal toolbar" |
| `MQL_TRADE_ALLOWED` | "Allow algo/live trading is unticked in RiskDesk's properties" |
| `ACCOUNT_TRADE_ALLOWED` | "Trading not allowed on this account (investor password?)" |
| `ACCOUNT_TRADE_EXPERT` | "Broker disabled EA trading on this account" |
| `SYMBOL_TRADE_MODE` disabled / close-only / long-only / short-only | Specific message; disable the affected buttons |

RiskDesk does **not** require MetaTrader's One-Click Trading (the original did).

### BC-16 Identification of tool trades
- Identify by magic number (`InpMagic`). Comments are informational only: brokers may truncate or replace them.
- MT4 partial close creates a new ticket for the remainder that keeps the magic; always re-list positions after a partial close.

### BC-17 Market closed and stale quotes
- If the last tick is older than `InpStaleQuoteSec` (300 s), show an amber hint "No quotes for 5 min – market may be closed". Do not block; the server decides.
- Map market-closed codes to "Market closed for <symbol>".

### BC-18 Order prices
- Always send the current Ask (buy) / Bid (sell), normalized, even under Market execution where the server ignores it.
- MT5 `request.type_filling`, `type_time`, `deviation`, `magic`, `comment` are always set explicitly.

## 3. Per-broker notes (verify every line with BrokerProbe)

| Broker | Platforms | Known specifics to handle |
|---|---|---|
| IG | MT4 (original works here); MT5 offered in some regions | Large CFD contract sizes on indices; spread-betting accounts (UK) quote per point; trust `OrderCalcProfit`/tick value and check the probe |
| IC Markets EU | MT4, MT5 | ESMA leverage caps (BC-09); Raw accounts charge commission → set `InpCommissionPerLot`; MT5 filling-mode rejections are a commonly reported EA failure (BC-06) |
| Dukascopy (Europe / Bank) | MT4, MT5 | Market execution; hedging allowed on MT4; max 1,000 orders; many CFDs with min lot ≥ 1 and step ≥ 0.1 (BC-04); per-instrument max net exposure (BC-09); EU leverage e.g. 20–30:1 FX, 2:1 crypto; account currencies include EUR/CHF/GBP/PLN (BC-05) |

## 4. BrokerProbe → what to look at
For each account the probe report (08-testing §3) must let a developer answer, per symbol: filling flags, expiration flags, execution mode, order-mode flags, tick size vs point, tick value vs computed expectation, volume min/step/max/limit, stops/freeze level, margin for 1 lot, and account margin mode/currency/leverage. Any surprise becomes a new line in §3 and, if needed, a new BC rule.

## 5. Error and retcode handling

Always use the symbolic constants in code; numbers are for reading logs.

### MT5 (`MqlTradeResult.retcode`)
| Code | Constant | Class | Status message (suffix with broker comment) |
|---|---|---|---|
| 10008 | `TRADE_RETCODE_PLACED` | success | "Pending placed" |
| 10009 | `TRADE_RETCODE_DONE` | success | "Done" |
| 10010 | `TRADE_RETCODE_DONE_PARTIAL` | success (amber) | "Partially filled x of y" |
| 10004 | `TRADE_RETCODE_REQUOTE` | retry | "Requote" |
| 10020 | `TRADE_RETCODE_PRICE_CHANGED` | retry | "Price changed" |
| 10021 | `TRADE_RETCODE_PRICE_OFF` | retry | "No quotes" |
| 10023 | `TRADE_RETCODE_ORDER_CHANGED` | retry | "Order state changed" |
| 10024 | `TRADE_RETCODE_TOO_MANY_REQUESTS` | retry (longer wait) | "Too many requests" |
| 10028 | `TRADE_RETCODE_LOCKED` | retry | "Order locked by dealer" |
| 10011 | `TRADE_RETCODE_ERROR` | retry once | "Server error" |
| 10012 | `TRADE_RETCODE_TIMEOUT` | ambiguous (BC-14) | "Timeout – checking…" |
| 10031 | `TRADE_RETCODE_CONNECTION` | ambiguous (BC-14) | "Connection lost – checking…" |
| 10030 | `TRADE_RETCODE_INVALID_FILL` | fix: BC-06 ladder | "Filling policy rejected" |
| 10022 | `TRADE_RETCODE_INVALID_EXPIRATION` | fix: BC-08 ladder | "Expiration rejected" |
| 10016 | `TRADE_RETCODE_INVALID_STOPS` | fix: BC-11 (market) else fatal | "SL/TP too close or not allowed" |
| 10015 | `TRADE_RETCODE_INVALID_PRICE` | retry once with fresh price | "Invalid price" |
| 10025 | `TRADE_RETCODE_NO_CHANGES` | success for modify | "Already set" |
| 10036 | `TRADE_RETCODE_POSITION_CLOSED` | success for close | "Already closed" |
| 10006 / 10007 | `REJECT` / `CANCEL` | fatal | "Rejected by broker" |
| 10013 | `TRADE_RETCODE_INVALID` | fatal (log full request) | "Invalid request (bug)" |
| 10014 | `TRADE_RETCODE_INVALID_VOLUME` | fatal | "Invalid volume (min/step/max = …)" |
| 10017 | `TRADE_RETCODE_TRADE_DISABLED` | fatal | "Trading disabled for symbol" |
| 10018 | `TRADE_RETCODE_MARKET_CLOSED` | fatal | "Market closed" |
| 10019 | `TRADE_RETCODE_NO_MONEY` | fatal | "Not enough margin" + BC-09 numbers |
| 10026 / 10027 | `SERVER_DISABLES_AT` / `CLIENT_DISABLES_AT` | fatal | "Algo trading disabled by server / terminal" |
| 10029 | `TRADE_RETCODE_FROZEN` | fatal | "Inside freeze level" |
| 10033 / 10040 | `LIMIT_ORDERS` / `LIMIT_POSITIONS` | fatal | "Order / position count limit reached" |
| 10034 | `TRADE_RETCODE_LIMIT_VOLUME` | fatal | "Volume limit for symbol reached (broker exposure cap)" |
| 10042 / 10043 / 10044 | `LONG_ONLY` / `SHORT_ONLY` / `CLOSE_ONLY` | fatal | "Symbol allows long only / short only / close only" |
| 10045 / 10046 | `FIFO_CLOSE` / `HEDGE_PROHIBITED` | fatal | "FIFO rule / hedging prohibited" |

When `OrderSend` returns false, still read `result.retcode` and `result.comment`; `GetLastError()` is often 4756 (send failed) and is not informative by itself.

### MT4 (`GetLastError()` after `OrderSend/OrderModify/OrderClose/OrderDelete`)
| Code | Constant | Class | Message |
|---|---|---|---|
| 135 / 136 / 138 | `ERR_PRICE_CHANGED` / `ERR_OFF_QUOTES` / `ERR_REQUOTE` | retry (RefreshRates) | "Price changed / no quotes / requote" |
| 4 / 137 / 141 / 8 | `ERR_SERVER_BUSY` / `ERR_BROKER_BUSY` / `ERR_TOO_MANY_REQUESTS` / `ERR_TOO_FREQUENT_REQUESTS` | retry (longer wait) | "Server busy" |
| 146 | `ERR_TRADE_CONTEXT_BUSY` | retry (wait for context) | "Trade context busy" |
| 6 | `ERR_NO_CONNECTION` | retry after reconnect | "No connection" |
| 128 | `ERR_TRADE_TIMEOUT` | ambiguous (BC-14) | "Timeout – checking…" |
| 129 | `ERR_INVALID_PRICE` | retry once | "Invalid price" |
| 130 | `ERR_INVALID_STOPS` | fix: BC-11 else fatal | "SL/TP too close or not allowed" |
| 147 | `ERR_TRADE_EXPIRATION_DENIED` | fix: BC-08 | "Expiration not allowed" |
| 1 | `ERR_NO_RESULT` | success for modify | "Already set" |
| 131 | `ERR_INVALID_TRADE_VOLUME` | fatal | "Invalid volume (min/step/max = …)" |
| 132 | `ERR_MARKET_CLOSED` | fatal | "Market closed" |
| 133 | `ERR_TRADE_DISABLED` | fatal | "Trading disabled" |
| 134 | `ERR_NOT_ENOUGH_MONEY` | fatal | "Not enough margin" + numbers |
| 139 | `ERR_ORDER_LOCKED` | fatal | "Order locked" |
| 145 | `ERR_TRADE_MODIFY_DENIED` | fatal | "Too close to market (freeze level)" |
| 148 | `ERR_TRADE_TOO_MANY_ORDERS` | fatal | "Order count limit reached" |
| 149 / 150 | `ERR_TRADE_HEDGE_PROHIBITED` / `ERR_TRADE_PROHIBITED_BY_FIFO` | fatal | "Hedging prohibited / FIFO rule" |
| 4109 / 4110 / 4111 | `ERR_TRADE_NOT_ALLOWED` / `ERR_LONGS_NOT_ALLOWED` / `ERR_SHORTS_NOT_ALLOWED` | fatal | "Trading not allowed (check Algo/AutoTrading and EA properties) / longs not allowed / shorts not allowed" |
| 64 / 65 | `ERR_ACCOUNT_DISABLED` / `ERR_INVALID_ACCOUNT` | fatal | "Account cannot trade" |

## 6. Compatibility checklist (Definition of Done for every trade feature)
- [ ] No literal 0.01, 2 (lot digits), 5 (price digits), 100000 (contract), "USD", or symbol suffix in trade code.
- [ ] Prices normalized to tick size; volumes floored to step and checked against min/max/limit.
- [ ] Filling and expiration ladders exercised (T-22, T-23).
- [ ] Stops/freeze checks with readable refusal messages.
- [ ] Margin pre-check with numbers.
- [ ] Netting path implemented or explicitly refused with a message.
- [ ] SL verified after open; close-on-failure path tested.
- [ ] Every result code produces a status message and a log line.
