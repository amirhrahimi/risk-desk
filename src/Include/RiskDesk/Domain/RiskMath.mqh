// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Domain/RiskMath.mqh                                   |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : the money math of 04-risk-engine:                      |
//|           - RiskBase, RiskMoney                    (section 1-2) |
//|           - LotsFromRisk: floor to the grid, min/max lot rules   |
//|                                                (sections 2, 4)   |
//|           - TpFromRR, RewardRatio                  (section 8)   |
//|           - CostDistance: price distance worth an amount, used   |
//|             for the Risk Free commission offset    (section 9)   |
//|           - PartialClose volume                    (section 10)  |
//|           - CloseChunk: a full close above the max volume (D35)  |
//|           - LossPerLotByTicks: the tick-value valuation (BC-05)  |
//|             as a pure formula. Platform/Money decides which      |
//|             valuation the EA uses; the tests use this one.       |
//| Lots are always rounded DOWN (rule R5, ADR-004).                 |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_RISKMATH_MQH
#define RD_DOMAIN_RISKMATH_MQH

#include "Types.mqh"
#include "PriceMath.mqh"
#include "Format.mqh"

// Result of LotsFromRisk. Money is in account currency.
struct SLotResult
  {
   double            base;            // risk base used (balance/equity)
   double            requestedPct;
   double            riskMoney;       // base x pct / 100
   double            lossPerLot;      // valuation of entry -> SL for 1.0 lot, without commission
   double            lossPerLotAll;   // + commission per lot
   double            rawLots;         // riskMoney / lossPerLotAll
   double            lots;            // volume to send; 0 when refused
   double            actualRisk;      // lots x lossPerLotAll
   double            actualPct;       // actualRisk / base x 100
   double            minLotRisk;      // risk of volMin
   double            minLotPct;
   bool              belowMin;        // rawLots < volMin
   bool              usedMinLot;      // volMin sent although above the risk (InpAllowMinLotOverRisk)
   bool              capped;          // limited to volMax

   void              Reset()
     {
      base = 0.0;
      requestedPct = 0.0;
      riskMoney = 0.0;
      lossPerLot = 0.0;
      lossPerLotAll = 0.0;
      rawLots = 0.0;
      lots = 0.0;
      actualRisk = 0.0;
      actualPct = 0.0;
      minLotRisk = 0.0;
      minLotPct = 0.0;
      belowMin = false;
      usedMinLot = false;
      capped = false;
     }
  };

// Result of PartialClose (F-12).
struct SPartialClose
  {
   double            volume;          // position volume
   double            closeVolume;     // volume to close; 0 when skipped
   double            remainVolume;
   bool              indivisible;
   bool              closeAll;        // INDIV_CLOSE_ALL applied to an indivisible position

   void              Reset()
     {
      volume = 0.0;
      closeVolume = 0.0;
      remainVolume = 0.0;
      indivisible = false;
      closeAll = false;
     }
  };

class CRiskMath
  {
public:
   static double     RiskBase(const ERiskBase mode, const double balance, const double equity);
   static double     RiskMoney(const double base, const double pct);
   static double     LossPerLotByTicks(const SSymbolSpec &s, const double entry, const double sl);
   static double     PositionRisk(const double lossPerLot, const double commissionPerLot, const double volume);
   static bool       LotsFromRisk(const double pct, const double lossPerLot, const SSymbolSpec &s,
                                  const SAccountSpec &acc, const SPlanSettings &cfg, SLotResult &lot, SResult &r);
   static bool       TpFromRR(const ESide side, const double entry, const double sl, const double rr,
                              const SSymbolSpec &s, double &tp, SResult &r);
   static double     RewardRatio(const double entry, const double sl, const double tp);
   static bool       CostDistance(const double money, const double moneyPerTick, const SSymbolSpec &s,
                                  double &dist);
   static bool       PartialClose(const double volume, const SSymbolSpec &s, const SPlanSettings &cfg,
                                  SPartialClose &pc, SResult &r);
   static bool       CloseChunk(const double remaining, const SSymbolSpec &s, double &chunk);
  };

//+------------------------------------------------------------------+
//| InpRiskBase: balance (default), equity or the lower of the two.  |
//+------------------------------------------------------------------+
double CRiskMath::RiskBase(const ERiskBase mode, const double balance, const double equity)
  {
   if(mode == RISKBASE_EQUITY)
      return equity;
   if(mode == RISKBASE_MIN_BAL_EQ)
      return MathMin(balance, equity);
   return balance;
  }

double CRiskMath::RiskMoney(const double base, const double pct)
  {
   return base * pct / 100.0;
  }

//+------------------------------------------------------------------+
//| BC-05 tick-value formula: ticks x loss tick value (MT5) or tick  |
//| value (MT4) for 1.0 lot. 0 when the spec cannot value the move.  |
//+------------------------------------------------------------------+
double CRiskMath::LossPerLotByTicks(const SSymbolSpec &s, const double entry, const double sl)
  {
   double tickValue = (s.tickValueLoss > 0.0) ? s.tickValueLoss : s.tickValue;
   if(!MathIsValidNumber(tickValue) || tickValue <= 0.0)
      return 0.0;
   return RdTicksBetween(s, entry, sl) * tickValue;
  }

//+------------------------------------------------------------------+
//| Money lost at the SL by 'volume' lots, commission included       |
//| (04 section 5, lossToSl).                                        |
//+------------------------------------------------------------------+
double CRiskMath::PositionRisk(const double lossPerLot, const double commissionPerLot, const double volume)
  {
   return (lossPerLot + commissionPerLot) * volume;
  }

//+------------------------------------------------------------------+
//| 04 sections 2 and 4. 'lossPerLot' is the platform's valuation of |
//| entry -> SL for 1.0 lot (> 0, without commission).               |
//| true  : lot.lots is the volume to send; r.sev is SEV_WARN when   |
//|         it was capped at volMax or is the min lot above the risk.|
//| false : refused, r.message says why with the numbers.            |
//+------------------------------------------------------------------+
bool CRiskMath::LotsFromRisk(const double pct, const double lossPerLot, const SSymbolSpec &s,
                             const SAccountSpec &acc, const SPlanSettings &cfg, SLotResult &lot, SResult &r)
  {
   lot.Reset();
   r.Reset();
   lot.base = RiskBase(cfg.riskBase, acc.balance, acc.equity);
   lot.requestedPct = pct;
   lot.lossPerLot = lossPerLot;

   if(!MathIsValidNumber(lot.base) || lot.base <= 0.0)
      return RdFail(r, "Risk base is " + RdMoney(acc, lot.base) + " - nothing can be risked");
   if(!MathIsValidNumber(pct) || pct <= 0.0)
      return RdFail(r, "Risk % must be above 0");
   if(!MathIsValidNumber(lossPerLot) || lossPerLot <= 0.0)
      return RdFail(r, "Cannot value a price move on " + s.name + " (loss per lot " + RdNum(lossPerLot) + ")");
   if(!(s.volStep > 0.0) || !(s.volMin > 0.0))
      return RdFail(r, "Broker reports an invalid volume grid for " + s.name);

   double commission = MathMax(0.0, cfg.commissionPerLot);
   lot.riskMoney = RiskMoney(lot.base, pct);
   lot.lossPerLotAll = lossPerLot + commission;
   lot.rawLots = lot.riskMoney / lot.lossPerLotAll;
   lot.minLotRisk = s.volMin * lot.lossPerLotAll;
   lot.minLotPct = lot.minLotRisk / lot.base * 100.0;

   double lots = 0.0;
   string warning = "";
   if(!RdFloorVolume(s, lot.rawLots, lots))
     {
      lot.belowMin = true;
      string minText = "Min lot " + RdFormatLots(s, s.volMin) + " would risk " + RdMoney(acc, lot.minLotRisk) +
                       " (" + RdFormatPct(lot.minLotPct) + ")";
      if(!cfg.allowMinLotOverRisk)
         return RdFail(r, minText + " - above your " + RdFormatPct(pct) + ". Widen risk or tighten SL.");
      if(lot.minLotPct > cfg.maxRiskPerTradePct + RD_PCT_EPS)
         return RdFail(r, minText + " - above the " + RdFormatCapPct(cfg.maxRiskPerTradePct) + " per-trade cap");
      lots = s.volMin;
      lot.usedMinLot = true;
      warning = "Min lot " + RdFormatLots(s, s.volMin) + " risks " + RdMoney(acc, lot.minLotRisk) +
                " (" + RdFormatPct(lot.minLotPct) + ") - above your " + RdFormatPct(pct) + " (allowed by settings)";
     }

   if(RdVolGt(lots, s.volMax))
     {
      double maxLots = 0.0;
      if(!RdFloorVolume(s, s.volMax, maxLots))
         return RdFail(r, "Broker reports max lot " + RdNum(s.volMax) + " below min lot " + RdNum(s.volMin) +
                       " for " + s.name);
      lots = maxLots;
      lot.capped = true;
     }

   lot.lots = lots;
   lot.actualRisk = lots * lot.lossPerLotAll;
   lot.actualPct = lot.actualRisk / lot.base * 100.0;

   if(lot.capped)
      return RdWarn(r, "Capped at max lot " + RdFormatLots(s, lots) + " (risk " + RdFormatPct(lot.actualPct) + ")");
   if(lot.usedMinLot)
      return RdWarn(r, warning);
   return RdOk(r, RdFormatLots(s, lots) + " lot, risk " + RdMoney(acc, lot.actualRisk) +
               " (" + RdFormatPct(lot.actualPct) + ")");
  }

//+------------------------------------------------------------------+
//| 04 section 8: tp = entry +/- rr x |entry - sl|, on the tick grid.|
//+------------------------------------------------------------------+
bool CRiskMath::TpFromRR(const ESide side, const double entry, const double sl, const double rr,
                         const SSymbolSpec &s, double &tp, SResult &r)
  {
   tp = 0.0;
   r.Reset();
   if(!MathIsValidNumber(rr) || rr <= 0.0)
      return RdFail(r, "R/R must be above 0 (is " + RdNum(rr) + ")");
   if(!(entry > 0.0) || !(sl > 0.0))
      return RdFail(r, "TP from R/R needs an entry and an SL");
   double d = MathAbs(entry - sl);
   double raw = (side == SIDE_BUY) ? entry + rr * d : entry - rr * d;
   double price = RdNormalizePrice(s, raw);
   if(!(price > 0.0))
      return RdFail(r, "TP at R/R " + RdNum(rr) + " would be at or below zero (" + RdFormatPrice(s, raw) + ")");
   tp = price;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| |tp - entry| / |entry - sl|; 0 without TP or SL distance.        |
//+------------------------------------------------------------------+
double CRiskMath::RewardRatio(const double entry, const double sl, const double tp)
  {
   double risk = MathAbs(entry - sl);
   if(!(tp > 0.0) || !(risk > 0.0))
      return 0.0;
   return MathAbs(tp - entry) / risk;
  }

//+------------------------------------------------------------------+
//| Price distance whose money value is 'money', given the money of  |
//| a one-tick move for the same volume (04 section 9 commDist).     |
//| 0 for money <= 0. False when a cost must be converted but the    |
//| tick value is unknown.                                           |
//+------------------------------------------------------------------+
bool CRiskMath::CostDistance(const double money, const double moneyPerTick, const SSymbolSpec &s, double &dist)
  {
   dist = 0.0;
   if(!MathIsValidNumber(money) || money <= 0.0)
      return true;
   if(!MathIsValidNumber(moneyPerTick) || moneyPerTick <= 0.0)
      return false;
   dist = money / moneyPerTick * RdTick(s);
   return true;
  }

//+------------------------------------------------------------------+
//| 04 section 10 (Q23): the split nearest to the percentage, a tie  |
//| keeping the larger part (3 lots at 50 % -> close 1, keep 2; 0.25 |
//| -> close 0.12, keep 0.13). hi = the largest close that leaves at |
//| least the minimum lot; the grid volume nearest to vol x pct;     |
//| above hi: hi when it is as near as closing everything or nearer, |
//| else indivisible (as when nothing is nearest or no split leaves a|
//| minimum lot). true: close                                        |
//| pc.closeVolume. false: skipped, r.sev == SEV_WARN with the reason|
//| (or SEV_ERROR on bad input).                                     |
//+------------------------------------------------------------------+
bool CRiskMath::PartialClose(const double volume, const SSymbolSpec &s, const SPlanSettings &cfg,
                             SPartialClose &pc, SResult &r)
  {
   pc.Reset();
   r.Reset();
   pc.volume = volume;
   if(!MathIsValidNumber(volume) || volume <= 0.0)
      return RdFail(r, "Position volume is " + RdNum(volume));

   double raw = volume * cfg.partialClosePct / 100.0;
   double hi = 0.0;
   double closeVol = 0.0;
   bool divisible = RdFloorVolume(s, volume - s.volMin, hi) && RdNearestVolume(s, raw, closeVol);
   if(divisible && RdVolGt(closeVol, hi))
     {
      if(raw - hi <= volume - raw + RD_VOL_EPS)
         closeVol = hi;          // the nearest split that leaves a minimum lot (a tie keeps more)
      else
         divisible = false;      // closing everything is nearer
     }
   double remain = 0.0;
   if(divisible)
     {
      remain = NormalizeDouble(volume - closeVol, RdLotDigits(s));
      if(!RdVolGt(remain, 0.0) || RdVolLt(remain, s.volMin))
         divisible = false;
     }

   if(!divisible)
     {
      pc.indivisible = true;
      string why = RdFormatLots(s, volume) + " lot cannot be split at " + RdFormatCapPct(cfg.partialClosePct) +
                   " (min " + RdFormatLots(s, s.volMin) + ", step " + RdFormatLots(s, s.volStep) + ")";
      if(cfg.partialIndivisible == INDIV_CLOSE_ALL)
        {
         pc.closeAll = true;
         pc.closeVolume = volume;
         pc.remainVolume = 0.0;
         return RdWarn(r, why + " - closing all of it");
        }
      return RdSkip(r, why);
     }

   pc.closeVolume = closeVol;
   pc.remainVolume = remain;
   return RdOk(r, "close " + RdFormatLots(s, closeVol) + ", keep " + RdFormatLots(s, remain));
  }

//+------------------------------------------------------------------+
//| Closing a whole position whose volume is above the broker's      |
//| maximum per request (a netting position can grow past it, BC-04, |
//| D35): the volume of the next close request. All of 'remaining'   |
//| when it fits; else the maximum on the grid, or less when that    |
//| would leave a rest below the minimum lot. False when no valid    |
//| request exists (volume <= 0, invalid grid).                      |
//+------------------------------------------------------------------+
bool CRiskMath::CloseChunk(const double remaining, const SSymbolSpec &s, double &chunk)
  {
   chunk = 0.0;
   if(!MathIsValidNumber(remaining) || remaining <= 0.0)
      return false;
   if(!(s.volMax > 0.0) || !RdVolGt(remaining, s.volMax))
     {
      chunk = remaining;
      return true;
     }
   double c = 0.0;
   if(!RdFloorVolume(s, s.volMax, c))
      return false;
   if(RdVolLt(remaining - c, s.volMin) && !RdFloorVolume(s, remaining - s.volMin, c))
      return false;
   chunk = c;
   return RdVolGt(chunk, 0.0);
  }

#endif // RD_DOMAIN_RISKMATH_MQH
