// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/Money.mqh                                    |
//| Layer   : Platform                                               |
//| Purpose : money <-> price conversions in account currency.       |
//|           Building blocks (P0, measured by BrokerProbe):         |
//|             - Rate(): BC-01 conversion lookup by symbol          |
//|               properties (never by name), route cached per pair  |
//|             - LossByCalcProfit / LossByTickValue / LossByContract|
//|               (the three BC-05 valuations, raw, for 1.0 lot)     |
//|             - MarginRaw (BC-09 terminal margin figure)           |
//|           Decisions (P2):                                        |
//|             - LossPerLot / ProfitPerLot (BC-05): MT5             |
//|               OrderCalcProfit, fallback tick value; MT4 tick     |
//|               value cross-checked against contract x rate, the   |
//|               conservative one used on a > 5 % mismatch; one     |
//|               retry after selecting the conversion pair.         |
//|               WITHOUT commission: CRiskMath adds                 |
//|               InpCommissionPerLot (ADR-018/ADR-019).             |
//|             - MarginFor, MaxLotsByMargin (BC-09)                 |
//|             - FillLossToSl: lossToSl of listed positions and     |
//|               orders for RiskBudget (G-06, 04 section 5)         |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_MONEY_MQH
#define RD_PLATFORM_MONEY_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\PriceMath.mqh"
#include "..\Domain\Format.mqh"
#include "..\Services\Logger.mqh"
#include "Compat.mqh"
#include "SymbolSpec.mqh"

#define RD_MONEY_MISMATCH_PCT  5.0    // BC-05 MT4 cross-check threshold

// A cached conversion route: from -> to via one or two symbols.
struct SConvRoute
  {
   string            from;
   string            to;
   bool              found;
   string            sym1;
   bool              inv1;      // true: rate = 1 / mid(sym1)
   string            sym2;      // "" for a direct pair
   bool              inv2;
  };

class CMoney
  {
private:
   SConvRoute        m_routes[];
   string            m_added[];   // symbols this instance put into Market Watch

   int               FindRoute(const string from, const string to) const;
   bool              FindPair(const string base, const string quote, const bool forexOnly, string &symbol) const;
   void              BuildRoute(const string from, const string to, SConvRoute &route) const;
   void              BuildRouteTier(const string from, const string to, const bool forexOnly, SConvRoute &route) const;
   bool              LegRate(const string symbol, const bool inverted, double &rate);
   string            RouteDesc(const SConvRoute &route) const;

   string            m_mismatchWarned[];   // BC-05: mismatch logged once per symbol
   bool              FirstMismatch(const string symbol);
   bool              MoveValue(const SSymbolSpec &s, const string accountCcy, const ESide side, const double from,
                               const double to, const bool isLoss, double &value, SResult &r);
   bool              TryValue(const SSymbolSpec &s, const string accountCcy, const ESide side, const double from,
                              const double to, const bool isLoss, double &value, SResult &r);
   double            SignedLoss(const SSymbolSpec &s, const string accountCcy, const ESide side, const double open,
                                const double sl, const double volume, const double commissionPerLot);

public:
   // Rate to convert an amount in 'from' into 'to' (mid prices).
   bool              Rate(const string from, const string to, double &rate, string &via, SResult &r);
   int               RouteCount() const { return ArraySize(m_routes); }
   string            RouteText(const int index);
   int               AddedCount() const { return ArraySize(m_added); }
   string            Added(const int index) const { return m_added[index]; }

   // Positive loss in account currency for 1.0 lot moving from entry to sl.
   bool              LossByCalcProfit(const SSymbolSpec &s, const ESide side, const double entry, const double sl,
                                      double &loss, SResult &r) const;
   bool              LossByTickValue(const SSymbolSpec &s, const double entry, const double sl,
                                     double &loss, SResult &r) const;
   bool              LossByContract(const SSymbolSpec &s, const double entry, const double sl, const string accountCcy,
                                    double &loss, string &via, SResult &r);
   bool              MarginRaw(const SSymbolSpec &s, const ESide side, const double volume, const double price,
                               double &margin, SResult &r) const;

   //--- BC-05 decisions. Positive amounts in account currency for 1.0 lot,
   //--- without commission. r.sev == SEV_WARN: valued, but see r.message
   //--- (MT4 tick value mismatch). false: refuse, r.message says why.
   bool              LossPerLot(const SSymbolSpec &s, const string accountCcy, const ESide side, const double entry,
                                const double sl, double &loss, SResult &r);
   bool              ProfitPerLot(const SSymbolSpec &s, const string accountCcy, const ESide side, const double entry,
                                  const double tp, double &profit, SResult &r);
   //--- BC-09
   bool              MarginFor(const SSymbolSpec &s, const ESide side, const double lots, const double price,
                               double &margin, SResult &r) const;
   bool              MaxLotsByMargin(const SSymbolSpec &s, const ESide side, const double price, const double freeMargin,
                                     const double bufferPct, double &maxLots, SResult &r) const;
   //--- G-06/G-07: lossToSl = value(open -> SL) x volume + commission x volume;
   //--- <= 0 when the SL is at or beyond break-even; NaN when it cannot be
   //--- valued (RiskBudget then refuses with the ticket). 0 without SL.
   //--- Returns the number of items that could not be valued.
   int               FillLossToSl(SPosition &positions[], const string accountCcy, const double commissionPerLot);
   int               FillLossToSl(SOrder &orders[], const string accountCcy, const double commissionPerLot);
  };

//+------------------------------------------------------------------+
int CMoney::FindRoute(const string from, const string to) const
  {
   int n = ArraySize(m_routes);
   for(int i = 0; i < n; i++)
      if(m_routes[i].from == from && m_routes[i].to == to)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| BC-01: a tradable symbol whose base/profit currencies match.     |
//| Market Watch symbols first, then every symbol of the server.     |
//| forexOnly: only forex calculation modes. Index/stock CFDs can    |
//| report currencies that make them look like a pair (IC Markets EU |
//| MT5 reported an index CFD as a USD->EUR pair, rate 20003.5).     |
//+------------------------------------------------------------------+
bool CMoney::FindPair(const string base, const string quote, const bool forexOnly, string &symbol) const
  {
   symbol = "";
   for(int pass = 0; pass < 2; pass++)
     {
      bool marketWatch = (pass == 0);
      int total = SymbolsTotal(marketWatch);
      for(int i = 0; i < total; i++)
        {
         string name = SymbolName(i, marketWatch);
         if(SymbolInfoString(name, SYMBOL_CURRENCY_BASE) != base)
            continue;
         if(SymbolInfoString(name, SYMBOL_CURRENCY_PROFIT) != quote)
            continue;
         if(SymbolInfoInteger(name, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
            continue;
         if(forexOnly && !RdIsForexCalcMode(RdSymbolCalcMode(name)))
            continue;
         symbol = name;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Direct pair, inverted pair, or two legs through any currency X   |
//| for which from/X and X/to pairs exist (no currency is assumed).  |
//| Tier 1 uses forex symbols only; tier 2 (any symbol kind) only    |
//| when no forex route exists.                                      |
//+------------------------------------------------------------------+
void CMoney::BuildRoute(const string from, const string to, SConvRoute &route) const
  {
   route.from = from;
   route.to = to;
   route.found = false;
   route.sym1 = "";
   route.inv1 = false;
   route.sym2 = "";
   route.inv2 = false;
   for(int tier = 0; tier < 2 && !route.found; tier++)
      BuildRouteTier(from, to, tier == 0, route);
  }

void CMoney::BuildRouteTier(const string from, const string to, const bool forexOnly, SConvRoute &route) const
  {
   string s = "";
   if(FindPair(from, to, forexOnly, s))
     {
      route.found = true;
      route.sym1 = s;
      return;
     }
   if(FindPair(to, from, forexOnly, s))
     {
      route.found = true;
      route.sym1 = s;
      route.inv1 = true;
      return;
     }

   for(int pass = 0; pass < 2; pass++)
     {
      bool marketWatch = (pass == 0);
      int total = SymbolsTotal(marketWatch);
      for(int i = 0; i < total; i++)
        {
         string name = SymbolName(i, marketWatch);
         if(SymbolInfoInteger(name, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
            continue;
         if(forexOnly && !RdIsForexCalcMode(RdSymbolCalcMode(name)))
            continue;
         string base = SymbolInfoString(name, SYMBOL_CURRENCY_BASE);
         string profit = SymbolInfoString(name, SYMBOL_CURRENCY_PROFIT);
         string middle = "";
         bool inv1 = false;
         if(base == from)
            middle = profit;
         else
            if(profit == from)
              {
               middle = base;
               inv1 = true;
              }
         if(middle == "" || middle == from || middle == to)
            continue;
         string s2 = "";
         bool inv2 = false;
         if(!FindPair(middle, to, forexOnly, s2))
           {
            if(!FindPair(to, middle, forexOnly, s2))
               continue;
            inv2 = true;
           }
         route.found = true;
         route.sym1 = name;
         route.inv1 = inv1;
         route.sym2 = s2;
         route.inv2 = inv2;
         return;
        }
     }
  }

//+------------------------------------------------------------------+
bool CMoney::LegRate(const string symbol, const bool inverted, double &rate)
  {
   rate = 0.0;
   if(SymbolInfoInteger(symbol, SYMBOL_SELECT) == 0)
     {
      if(SymbolSelect(symbol, true))
        {
         int n = ArraySize(m_added);
         ArrayResize(m_added, n + 1);
         m_added[n] = symbol;
        }
     }
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(!MathIsValidNumber(bid) || !MathIsValidNumber(ask) || bid <= 0.0 || ask <= 0.0)
      return false;
   double mid = (bid + ask) / 2.0;
   rate = inverted ? 1.0 / mid : mid;
   return true;
  }

//+------------------------------------------------------------------+
string CMoney::RouteDesc(const SConvRoute &route) const
  {
   if(!route.found)
      return "no route";
   string s = route.sym1 + (route.inv1 ? " (inverted)" : "");
   if(route.sym2 != "")
      s += " x " + route.sym2 + (route.inv2 ? " (inverted)" : "");
   return s;
  }

//+------------------------------------------------------------------+
bool CMoney::Rate(const string from, const string to, double &rate, string &via, SResult &r)
  {
   rate = 0.0;
   via = "";
   r.Reset();
   if(from == "" || to == "")
      return RdFail(r, "Cannot convert: currency unknown (" + from + " to " + to + ")");
   if(from == to)
     {
      rate = 1.0;
      via = "same currency";
      return RdOk(r, "");
     }

   int i = FindRoute(from, to);
   if(i < 0)
     {
      SConvRoute route;
      BuildRoute(from, to, route);
      i = ArraySize(m_routes);
      ArrayResize(m_routes, i + 1);
      m_routes[i] = route;      // failed lookups are cached too, so they are not rescanned
     }
   if(!m_routes[i].found)
      return RdFail(r, "No symbol on this server converts " + from + " to " + to);

   via = RouteDesc(m_routes[i]);
   double r1 = 0.0;
   double r2 = 1.0;
   if(!LegRate(m_routes[i].sym1, m_routes[i].inv1, r1))
      return RdFail(r, "No quote for " + m_routes[i].sym1 + " (needed to convert " + from + " to " + to + ")");
   if(m_routes[i].sym2 != "" && !LegRate(m_routes[i].sym2, m_routes[i].inv2, r2))
      return RdFail(r, "No quote for " + m_routes[i].sym2 + " (needed to convert " + from + " to " + to + ")");
   rate = r1 * r2;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| "USD>EUR via EURUSD (inverted) rate 0.86" with the current rate. |
//+------------------------------------------------------------------+
string CMoney::RouteText(const int index)
  {
   SConvRoute route = m_routes[index];
   string text = route.from + ">" + route.to + " via " + RouteDesc(route);
   if(route.found)
     {
      double rate = 0.0;
      string via = "";
      SResult r;
      if(Rate(route.from, route.to, rate, via, r))
         text += " rate " + RdNum(rate, 8);
      else
         text += " (" + r.message + ")";
     }
   return text;
  }

//+------------------------------------------------------------------+
//| BC-05 MT5 primary: the terminal's own valuation.                 |
//+------------------------------------------------------------------+
bool CMoney::LossByCalcProfit(const SSymbolSpec &s, const ESide side, const double entry, const double sl,
                              double &loss, SResult &r) const
  {
   loss = 0.0;
#ifdef __MQL5__
   double profit = 0.0;
   ENUM_ORDER_TYPE type = (side == SIDE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ResetLastError();
   if(!OrderCalcProfit(type, s.name, 1.0, entry, sl, profit))
      return RdFail(r, "OrderCalcProfit failed for " + s.name + " (error " + IntegerToString(GetLastError()) + ")");
   if(!MathIsValidNumber(profit))
      return RdFail(r, "OrderCalcProfit returned an invalid number for " + s.name);
   loss = -profit;
   return RdOk(r, "");
#else
   return RdFail(r, "OrderCalcProfit is not available on MT4");
#endif
  }

//+------------------------------------------------------------------+
//| BC-05 MT4 primary / MT5 fallback: ticks x tick value (loss).     |
//+------------------------------------------------------------------+
bool CMoney::LossByTickValue(const SSymbolSpec &s, const double entry, const double sl,
                             double &loss, SResult &r) const
  {
   loss = 0.0;
   if(s.tickSize <= 0.0)
      return RdFail(r, "Tick size unknown for " + s.name);
   double tickValue = (s.tickValueLoss > 0.0) ? s.tickValueLoss : s.tickValue;
   if(!MathIsValidNumber(tickValue) || tickValue <= 0.0)
      return RdFail(r, "Broker reports tick value " + RdNum(tickValue) + " for " + s.name);
   loss = MathAbs(entry - sl) / s.tickSize * tickValue;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-05 MT4 cross-check: distance x contract size x rate(profit -> |
//| account). Only meaningful for forex/CFD calculation modes.       |
//+------------------------------------------------------------------+
bool CMoney::LossByContract(const SSymbolSpec &s, const double entry, const double sl, const string accountCcy,
                            double &loss, string &via, SResult &r)
  {
   loss = 0.0;
   double rate = 0.0;
   if(!Rate(s.profitCcy, accountCcy, rate, via, r))
      return false;
   loss = MathAbs(entry - sl) * s.contractSize * rate;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| Margin the terminal reports for 'volume' lots at 'price'.        |
//+------------------------------------------------------------------+
bool CMoney::MarginRaw(const SSymbolSpec &s, const ESide side, const double volume, const double price,
                       double &margin, SResult &r) const
  {
   margin = 0.0;
#ifdef __MQL5__
   ENUM_ORDER_TYPE type = (side == SIDE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   ResetLastError();
   if(!OrderCalcMargin(type, s.name, volume, price, margin))
      return RdFail(r, "OrderCalcMargin failed for " + s.name + " (error " + IntegerToString(GetLastError()) + ")");
#else
   double perLot = MarketInfo(s.name, MODE_MARGINREQUIRED);
   if(!MathIsValidNumber(perLot) || perLot <= 0.0)
      return RdFail(r, "Broker reports margin " + RdNum(perLot) + " per lot for " + s.name);
   margin = perLot * volume;
#endif
   if(!MathIsValidNumber(margin))
      return RdFail(r, "Margin for " + s.name + " is not a number");
   return RdOk(r, "");
  }

//====================================================================
// BC-05 decisions (P2)
//====================================================================
bool CMoney::LossPerLot(const SSymbolSpec &s, const string accountCcy, const ESide side, const double entry,
                        const double sl, double &loss, SResult &r)
  {
   return MoveValue(s, accountCcy, side, entry, sl, true, loss, r);
  }

bool CMoney::ProfitPerLot(const SSymbolSpec &s, const string accountCcy, const ESide side, const double entry,
                          const double tp, double &profit, SResult &r)
  {
   return MoveValue(s, accountCcy, side, entry, tp, false, profit, r);
  }

//+------------------------------------------------------------------+
//| Value of a move from 'from' to 'to' for 1.0 lot, > 0. isLoss:    |
//| 'to' must be on the losing side (SL), else on the winning side   |
//| (TP). Invalid result -> one retry after selecting the conversion |
//| pair (BC-05), then refuse.                                       |
//+------------------------------------------------------------------+
bool CMoney::MoveValue(const SSymbolSpec &s, const string accountCcy, const ESide side, const double from,
                       const double to, const bool isLoss, double &value, SResult &r)
  {
   value = 0.0;
   r.Reset();
   string level = isLoss ? "SL" : "TP";
   if(!(from > 0.0) || !(to > 0.0))
      return RdFail(r, "Cannot value a price move on " + s.name + ": entry or " + level + " not set");
   if(RdPriceEq(s, from, to))
      return RdFail(r, level + " equals the entry on " + s.name);
   bool down = RdPriceLt(s, to, from);
   bool losing = (side == SIDE_BUY) ? down : !down;
   if(losing != isLoss)
      return RdFail(r, level + " is on the wrong side of the entry for a " + RdSideText(side));

   if(TryValue(s, accountCcy, side, from, to, isLoss, value, r))
      return true;
   //--- BC-05 retry: select the conversion pair, re-read the symbol
   double rate = 0.0;
   string via = "";
   SResult rr;
   Rate(s.profitCcy, accountCcy, rate, via, rr);
   SSymbolSpec fresh;
   SResult sr;
   if(CSymbolSpec::Read(s.name, fresh, sr) && TryValue(fresh, accountCcy, side, from, to, isLoss, value, r))
      return true;
   value = 0.0;
   return RdFail(r, "Cannot value a price move on " + s.name + " (no conversion rate" +
                 (rr.ok ? "" : ": " + rr.message) + ")");
  }

//+------------------------------------------------------------------+
//| One valuation attempt.                                           |
//|   MT5: OrderCalcProfit; fallback ticks x tick value (loss/profit)|
//|   MT4: ticks x MODE_TICKVALUE, cross-checked for forex and CFD   |
//|        calc modes against distance x contract x rate; > 5 %      |
//|        apart -> warn (once per symbol in the log, every time in  |
//|        r) and use the conservative value: the larger loss, the   |
//|        smaller profit.                                           |
//+------------------------------------------------------------------+
bool CMoney::TryValue(const SSymbolSpec &s, const string accountCcy, const ESide side, const double from,
                      const double to, const bool isLoss, double &value, SResult &r)
  {
   value = 0.0;
   r.Reset();
   double ticks = RdTicksBetween(s, from, to);
#ifdef __MQL5__
   double calc = 0.0;
   SResult cr;
   if(LossByCalcProfit(s, side, from, to, calc, cr))
     {
      double v = isLoss ? calc : -calc;
      if(MathIsValidNumber(v) && v > 0.0)
        {
         value = v;
         return RdOk(r, "");
        }
     }
   double tickValue = isLoss ? s.tickValueLoss : s.tickValueProfit;
   if(!(tickValue > 0.0))
      tickValue = s.tickValue;
   if(MathIsValidNumber(tickValue) && tickValue > 0.0 && ticks > 0.0)
     {
      value = ticks * tickValue;
      return RdOk(r, "");
     }
   return RdFail(r, "Cannot value a price move on " + s.name + " (OrderCalcProfit and tick value unavailable)");
#else
   double byTick = (MathIsValidNumber(s.tickValue) && s.tickValue > 0.0) ? ticks * s.tickValue : 0.0;
   double byContract = 0.0;
   bool checkable = (s.calcMode == 0 || s.calcMode == 1);   // MODE_PROFITCALCMODE forex / CFD
   if(checkable)
     {
      string via = "";
      SResult cr;
      if(!LossByContract(s, from, to, accountCcy, byContract, via, cr) || !MathIsValidNumber(byContract))
         byContract = 0.0;
     }
   if(byTick > 0.0 && byContract > 0.0)
     {
      double mismatch = MathAbs(byTick - byContract) / byContract * 100.0;
      if(mismatch <= RD_MONEY_MISMATCH_PCT)
        {
         value = byTick;
         return RdOk(r, "");
        }
      value = isLoss ? MathMax(byTick, byContract) : MathMin(byTick, byContract);
      string text = "Tick value mismatch on " + s.name + ": broker " + RdNum(byTick, 2) + " " + accountCcy +
                    ", contract x rate " + RdNum(byContract, 2) + " " + accountCcy + " (" + RdNum(mismatch, 1) +
                    " %) - using the more conservative";
      if(FirstMismatch(s.name))
         RD_LOG_WARN("BC-05 " + text + " (tick value " + RdNum(s.tickValue) + ", tick size " + RdNum(s.tickSize, 10) +
                     ", contract " + RdNum(s.contractSize) + ")");
      return RdWarn(r, text);
     }
   if(byTick > 0.0)
     {
      value = byTick;
      return RdOk(r, "");
     }
   if(byContract > 0.0)
     {
      value = byContract;
      if(FirstMismatch(s.name))
         RD_LOG_WARN("BC-05 broker reports tick value " + RdNum(s.tickValue) + " for " + s.name +
                     "; using contract size x conversion rate");
      return RdWarn(r, "Tick value missing on " + s.name + " - valued from contract size x rate");
     }
   return RdFail(r, "Cannot value a price move on " + s.name + " (tick value " + RdNum(s.tickValue) + ")");
#endif
  }

bool CMoney::FirstMismatch(const string symbol)
  {
   int n = ArraySize(m_mismatchWarned);
   for(int i = 0; i < n; i++)
      if(m_mismatchWarned[i] == symbol)
         return false;
   ArrayResize(m_mismatchWarned, n + 1);
   m_mismatchWarned[n] = symbol;
   return true;
  }

//+------------------------------------------------------------------+
//| BC-09: margin for 'lots' at 'price' (MT5 OrderCalcMargin, MT4    |
//| MODE_MARGINREQUIRED x lots).                                     |
//+------------------------------------------------------------------+
bool CMoney::MarginFor(const SSymbolSpec &s, const ESide side, const double lots, const double price,
                       double &margin, SResult &r) const
  {
   r.Reset();
   if(!MarginRaw(s, side, lots, price, margin, r))
      return false;
   if(margin < 0.0)
      return RdFail(r, "Broker reports a negative margin for " + s.name);
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-09: largest grid volume whose margin fits into free margin    |
//| minus the buffer (InpMarginBufferPct). 0 = not even the minimum. |
//+------------------------------------------------------------------+
bool CMoney::MaxLotsByMargin(const SSymbolSpec &s, const ESide side, const double price, const double freeMargin,
                             const double bufferPct, double &maxLots, SResult &r) const
  {
   maxLots = 0.0;
   r.Reset();
   double perLot = 0.0;
   if(!MarginRaw(s, side, 1.0, price, perLot, r))
      return false;
   double buffer = MathMax(0.0, MathMin(bufferPct, 100.0));
   double usable = MathMax(0.0, freeMargin) * (1.0 - buffer / 100.0);
   double raw = (perLot > 0.0) ? usable / perLot : s.volMax;
   if(!RdFloorVolume(s, MathMin(raw, s.volMax), maxLots))
      maxLots = 0.0;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| 04 section 5: value(open -> SL) x volume + commission x volume.  |
//| SL on the winning side -> minus the profit locked in.            |
//+------------------------------------------------------------------+
double CMoney::SignedLoss(const SSymbolSpec &s, const string accountCcy, const ESide side, const double open,
                          const double sl, const double volume, const double commissionPerLot)
  {
   double comm = MathMax(0.0, commissionPerLot) * volume;
   if(RdPriceEq(s, open, sl))
      return comm;
   bool down = RdPriceLt(s, sl, open);
   bool losing = (side == SIDE_BUY) ? down : !down;
   double v = 0.0;
   SResult r;
   bool ok = losing ? LossPerLot(s, accountCcy, side, open, sl, v, r) : ProfitPerLot(s, accountCcy, side, open, sl, v, r);
   if(!ok)
      return MathSqrt(-1.0);   // NaN: cannot be valued
   return (losing ? v : -v) * volume + comm;
  }

int CMoney::FillLossToSl(SPosition &positions[], const string accountCcy, const double commissionPerLot)
  {
   int failed = 0;
   SSymbolSpec s;
   bool specOk = false;
   string specOf = "";
   int n = ArraySize(positions);
   for(int i = 0; i < n; i++)
     {
      positions[i].lossToSl = 0.0;
      if(!(positions[i].sl > 0.0))
         continue;
      if(positions[i].symbol != specOf)
        {
         SResult sr;
         specOf = positions[i].symbol;
         specOk = CSymbolSpec::Read(specOf, s, sr);
        }
      positions[i].lossToSl = specOk ? SignedLoss(s, accountCcy, positions[i].side, positions[i].open, positions[i].sl,
                                                  positions[i].volume, commissionPerLot) : MathSqrt(-1.0);
      if(!MathIsValidNumber(positions[i].lossToSl))
         failed++;
     }
   return failed;
  }

int CMoney::FillLossToSl(SOrder &orders[], const string accountCcy, const double commissionPerLot)
  {
   int failed = 0;
   SSymbolSpec s;
   bool specOk = false;
   string specOf = "";
   int n = ArraySize(orders);
   for(int i = 0; i < n; i++)
     {
      orders[i].lossToSl = 0.0;
      if(!(orders[i].sl > 0.0))
         continue;
      if(orders[i].symbol != specOf)
        {
         SResult sr;
         specOf = orders[i].symbol;
         specOk = CSymbolSpec::Read(specOf, s, sr);
        }
      orders[i].lossToSl = specOk ? SignedLoss(s, accountCcy, orders[i].side, orders[i].price, orders[i].sl,
                                               orders[i].volume, commissionPerLot) : MathSqrt(-1.0);
      if(!MathIsValidNumber(orders[i].lossToSl))
         failed++;
     }
   return failed;
  }

#endif // RD_PLATFORM_MONEY_MQH
