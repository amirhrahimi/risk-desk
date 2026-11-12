# 04 — Risk Engine

All functions here live in `Domain/` (pure) except `LossPerLot`, `MarginFor` and the cross-rate lookup, which live in `Platform/Money.mqh`. Every formula has test vectors (V-xx) that the `RiskDeskTests` script must implement.

## 1. Inputs

| Symbol | Meaning | Source |
|---|---|---|
| `base` | Risk base in account currency | `InpRiskBase`: Balance (default, as Orig §01) / Equity / min(Balance, Equity) |
| `pct` | Risk % from the panel | 0 < pct ≤ `InpMaxRiskPerTradePct` (10) |
| `entry` | Market buy: Ask · market sell: Bid · pending: Entry line | Quote / lines |
| `sl`, `tp` | Line prices, normalized (BC-03) | Lines |
| `lossPerLot` | Money lost per 1.0 lot from entry to SL, account currency, > 0 | BC-05 |
| `comm` | `InpCommissionPerLot`, round turn, account currency | Input |
| spec | `volMin`, `volStep`, `volMax`, `tickSize`, `digits` | SymbolSpec |

## 2. Core formulas

```
riskMoney     = base × pct / 100
lossPerLotAll = lossPerLot + comm
rawLots       = riskMoney / lossPerLotAll
lots          = FloorVolume(rawLots)                  (BC-04; null if rawLots < volMin)
lots          = min(lots, volMax)                     (warn when capped)
actualRisk    = lots × lossPerLotAll
actualPct     = actualRisk / base × 100
reward        = lots × profitPerLot(entry → tp) − lots × comm   (only when TP exists)
rr            = |tp − entry| / |entry − sl|
```

Notes
- Why the spread does not need a separate term: a buy is opened at Ask and its SL is hit when **Bid** reaches SL, so the loss distance is exactly `Ask − SL`. A sell is opened at Bid and stopped when **Ask** reaches SL, so the distance is `SL − Bid`. Using `entry = Ask/Bid` already includes the spread at entry.
- The lot is computed **after** normalizing prices (BC-03) so the displayed risk is the risk of what is actually sent.
- Use `FloorVolume`, never `MathRound` or `NormalizeDouble(lots, 2)`.

## 3. FloorVolume and price helpers

```
VolumeDigits(step): smallest d in 0..8 with |step×10^d − round(step×10^d)| < 1e-8
FloorVolume(raw):   if raw < volMin − 1e-12 → NONE
                    k = floor((raw − volMin) / volStep + 1e-8)
                    return NormalizeDouble(volMin + k × volStep, VolumeDigits(volStep))
NormalizePrice(p):  NormalizeDouble(round(p / tickSize) × tickSize, digits)
RoundPriceUp(p):    NormalizeDouble(ceil (p / tickSize − 1e-8) × tickSize, digits)
RoundPriceDown(p):  NormalizeDouble(floor(p / tickSize + 1e-8) × tickSize, digits)
PriceEq(a,b):       |a − b| < tickSize / 2
```
The `+1e-8` is essential: in IEEE doubles `0.57 / 0.01 = 56.99999999999999`, and a plain `floor` would turn a valid 0.57 lot into 0.56.

## 4. Below-minimum and above-maximum

| Case | Default behaviour | Setting |
|---|---|---|
| `rawLots < volMin` | Refuse: "Min lot 1 would risk €60.00 (1.20 %) – above your 1.00 %. Widen risk or tighten SL." | `InpAllowMinLotOverRisk=true` → send `volMin` if its risk % ≤ `InpMaxRiskPerTradePct`; amber status shows the real risk |
| `lots > volMax` | Send `volMax`, amber: "Capped at max lot 50 (risk 0.62 %)" | – |
| MT5 `SYMBOL_VOLUME_LIMIT` exceeded | Refuse with the remaining allowance | – |

## 5. Risk budget (F-16)

```
openRisk = Σ over tool positions p:  max(0, lossToSl(p))
         + Σ over tool pending orders o (if InpIncludePendingInTotalRisk): lossToSl(o)
lossToSl(p)  = LossPerLot(p.symbol, p.side, p.open, p.sl) × p.volume + comm × p.volume
               (≤ 0 when the SL is at or beyond break-even → counts as 0)
lossToSl(o)  = LossPerLot(o.symbol, o.side, o.price, o.sl) × o.volume + comm × o.volume
allowed  ⇔  pctNew ≤ InpMaxRiskPerTradePct  AND  (openRisk + actualRisk) / base × 100 ≤ InpMaxTotalRiskPct
```
- Tool position with `sl == 0` → open risk is unknown → refuse new trades: "Position #123 (XAUUSD) has no SL – total risk cannot be computed".
- Netting (BC-10): a same-direction add replaces the SL of the whole position, so the check uses the **post-trade** position: `(oldVol + lots)` at the new SL, minus the old position's contribution.
- Equality at the cap is allowed (`≤`).
- Moving a placed pending order (OP-16): the lot stays fixed and `pctNew` is the order's risk at the new entry/SL. For a tool order the old contribution is replaced, not added (`openRisk − oldRisk(o) + newRisk(o)`). Other orders (manual, other EAs) are checked against `InpMaxRiskPerTradePct` only. A move that does not raise the order's risk is allowed without the caps (P5, D29; `CRiskBudget::CheckMove`).
- Platform computes `lossToSl` per item (it needs `LossPerLot`), Domain sums and decides.

## 6. Market side validation (F-06)

```
Buy  valid ⇔ sl < bid  AND (no TP or tp > bid)  AND BC-07 distances
Sell valid ⇔ sl > ask  AND (no TP or tp < ask)  AND BC-07 distances
Preview side (Lots field, F-03): sl < bid → BUY · sl > ask → SELL · otherwise none ("SL inside spread")
```

## 7. Pending classification (F-08)

```
if PriceEq(entry, sl)                          → Invalid: "Entry and SL are equal"
long  = sl < entry ; short = sl > entry
long:  entry > ask → BUY_STOP ;  entry < ask → BUY_LIMIT ;  PriceEq(entry, ask) → Invalid "Entry at market – use Buy"
short: entry < bid → SELL_STOP;  entry > bid → SELL_LIMIT;  PriceEq(entry, bid) → Invalid "Entry at market – use Sell"
TP (if present): long requires tp > entry; short requires tp < entry, else Invalid "TP on wrong side"
then BC-07 distance rules for the chosen type
```
Lots for pending: `entry` = Entry line; `LossPerLot(side, entry, sl)`.

## 8. Take profit by R:R (F-17)

Applies in Auto R/R mode (F-17: "Trade with TP Line" = true, "Manual TP Line" = false) and to the starting position of the TP line in Manual TP line mode. Manual TP line mode: TP = TP line. No TP mode: TP = 0.

```
d  = |entry − sl|
tp = entry + InpTpRR × d   (buy)      tp = entry − InpTpRR × d   (sell)
tp = NormalizePrice(tp)
```
For market orders `entry` is the price used at send time (Ask/Bid), recomputed on every retry.

## 9. Risk Free target (F-11)

```
commDist   = price distance whose money value for p.volume equals InpCommissionPerLot × p.volume
             (round turn, via ProfitPerLot); 0 when InpCommissionPerLot = 0
baseOffset = InpRiskFreeMode:
   SPREAD_COMMISSION → (ask − bid) + commDist   [default; Orig §11 "taking the spread into account" + owner's Q1 answer]
   SPREAD            → ask − bid (current)
   COMMISSION        → price distance whose money value for p.volume equals commission + swap booked on the position (via ProfitPerLot)
   EXACT             → 0
offset = baseOffset + InpRiskFreeExtraPoints × point
buy : target = RoundPriceUp  (open + offset)
      apply if target ≤ bid − S − tickSize  AND (sl == 0 OR target > sl + tickSize/2)
sell: target = RoundPriceDown(open − offset)
      apply if target ≥ ask + S + tickSize  AND (sl == 0 OR target < sl − tickSize/2)
also: BC-07 freeze checks; keep the existing TP unchanged
```
Skip reasons: "not enough profit (needs Bid ≥ 1.10043)", "already protected", "frozen".

## 10. Partial close volume (F-12)

```
closeVol = FloorVolume(vol × InpPartialClosePct / 100)          (NONE → indivisible)
remain   = vol − closeVol
indivisible ⇔ closeVol is NONE  OR  (remain > 0 AND remain < volMin − 1e-8)
indivisible → InpPartialIndivisible: SKIP (default, report) | CLOSE_ALL
```

## 11. Display formatting

- Money: account currency, 2 decimals (0 for JPY/HUF-like currencies with `ACCOUNT_CURRENCY_DIGITS` when available), thousands separators.
- Percent: 2 decimals. Lots: `VolumeDigits(volStep)` decimals. Points: integer.
- Cent mode: append major-unit value (BC-12).

## 12. Test vectors (implement all in `RiskDeskTests`)

Unless stated: `volMin 0.01, volStep 0.01, volMax 100`, commission 0, base = balance.

| ID | Case | Given | Expected |
|---|---|---|---|
| V-01 | FX, USD account | EURUSD, tickSize 0.00001, tickValue 1.00, balance 10,000, 1 %; buy entry 1.10000, SL 1.09800 | ticks 200, lossPerLot 200.00, raw 0.5, **lots 0.50**, risk 100.00 (1.00 %) |
| V-02 | Commission | V-01 + comm 7.00 | lossPerLotAll 207.00, raw 0.48309, **lots 0.48**, risk 99.36 |
| V-03 | Tick value not round | USDJPY, tickSize 0.001, tickValue 0.66667, balance 10,000, 1 %, SL distance 0.500 | ticks 500, lossPerLot 333.335, raw 0.2999985, **lots 0.29**, risk 96.67 |
| V-04 | EUR account, gold | tickSize 0.01, tickValue 0.925926 (=1.00 USD / 1.08), balance 5,000 EUR, 0.5 %; buy 4000.00, SL 3990.00 | ticks 1000, lossPerLot 925.93, raw 0.0270, **lots 0.02**, risk 18.52 EUR (0.37 %) |
| V-05 | Whole-contract CFD (Dukascopy-style) | volMin 1, volStep 1, tickSize 0.01, tickValue 0.01 EUR, balance 5,000 EUR, 1 %; SL distance 40.00 | lossPerLot 40.00, raw 1.25, **lots 1**, risk 40.00 (0.80 %) |
| V-06 | Below minimum | V-05 with SL distance 60.00 | raw 0.833 → **refused**, message mentions 60.00 EUR (1.20 %) |
| V-07 | Min not on 0.01 grid start | volMin 0.5, volStep 0.01; raw 0.537 / raw 0.42 | **0.53** / **refused** |
| V-08 | Float floor | FloorVolume(0.57, step 0.01, min 0.01) | **0.57** (not 0.56) |
| V-09 | Above max | raw 120, volMax 50 | **50**, warning |
| V-10 | Price normalization | tick 0.25 digits 2: 4501.13 · tick 0.5: 24000.74 · tick 0.001: 150.1234 | 4501.25 · 24000.50 · 150.123 |
| V-11 | RR TP | buy entry 1.10000 SL 1.09800 RR 2 · sell entry 1.10000 SL 1.10150 RR 1.5 | 1.10400 · 1.09775 |
| V-12 | Market side | bid 1.10000 ask 1.10010; SL 1.09900 · SL 1.10100 · SL 1.10005 | BUY · SELL · none |
| V-13 | Pending classification | bid 1.10000 ask 1.10010, S=0: (E 1.10200, SL 1.10000) · (1.09800, 1.09600) · (1.09800, 1.10000) · (1.10200, 1.10400) | Buy Stop · Buy Limit · Sell Stop · Sell Limit |
| V-14 | Pending too close | stopsLevel 10 pts, point 0.00001; bid 1.10000 ask 1.10010; entry 1.10005, SL 1.09900 (→ Buy Limit) | **refused**: needs Ask − Entry ≥ 0.00010 |
| V-15 | Risk budget | base 10,000, cap 10 %; open risks 300, 450, −20 (BE); new 200 · new 300 | open 750 (7.5 %); 9.5 % **allowed** · 10.5 % **refused** |
| V-16 | Risk budget equality | open 800, new 200, cap 10 % of 10,000 | **allowed** (exactly 10 %) |
| V-17 | No-SL tool position | one tool position with sl 0 | **refused** with ticket in message |
| V-18 | Partial close | vol 0.03 · 0.05 · 0.01 · 1 (min 1, step 1) at 50 % | close 0.01 keep 0.02 · close 0.02 keep 0.03 · indivisible · indivisible |
| V-19 | Risk Free buy | open 1.10000, spread 0.00012, S 30 pts; bid 1.10050 · bid 1.10035 | target 1.10012 **applied** · **skipped** (needs bid ≥ 1.10043) |
| V-20 | Risk Free never loosens | buy open 1.10000, current SL 1.10020, target 1.10012 | **skipped**: already protected |
| V-21 | Risk input parsing | "1,5" · "0" · "12" · "abc" · " 0.25 " | 1.5 · reject · reject (max 10) · reject · 0.25 |
| V-22 | Volume digits | step 1 · 0.1 · 0.01 · 0.001 · 0.5 | 0 · 1 · 2 · 3 · 1 |
| V-23 | Risk Free spread + commission | EURUSD tickSize 0.00001, tickValue 1.00; buy 0.50 lot, open 1.10000, spread 0.00012, comm 7.00/lot, S 30 pts; bid 1.10060 · bid 1.10045 | commDist 0.00007, target 1.10019 **applied** · **skipped** (needs bid ≥ 1.10050) |
| V-24 | Moving a pending order | base 10,000, cap 10 %; open risk 800 of which 300 is this tool order; new risk of this order 450 · 600 | 950 (9.5 %) **allowed** · 1,100 (11.0 %) **refused** (old 300 replaced, not added) |

(V-19 second case: target 1.10012 needs `bid − 0.00030 − 0.00001 ≥ 1.10012` → bid ≥ 1.10043.)
(V-23: commission 7.00 × 0.50 = 3.50 = 7 ticks at 0.50 per tick → 0.00007; target = 1.10000 + 0.00012 + 0.00007.)
