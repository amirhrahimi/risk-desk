//+------------------------------------------------------------------+
//| RiskDesk - Platform/Money.mqh                                    |
//| Layer   : Platform                                               |
//| Purpose : money <-> price conversions in account currency.       |
//| Status  : P0 provides the building blocks that BrokerProbe       |
//|           measures on every broker:                              |
//|             - Rate(): BC-01 conversion lookup by symbol          |
//|               properties (never by name), route cached per pair  |
//|             - LossByCalcProfit / LossByTickValue / LossByContract|
//|               (the three BC-05 valuations, raw, for 1.0 lot)     |
//|             - MarginRaw (BC-09 terminal margin figure)           |
//|           P2 adds LossPerLot() (BC-05 decision logic, retry,     |
//|           commission), MarginFor() and MaxLotsByMargin().        |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_MONEY_MQH
#define RD_PLATFORM_MONEY_MQH

#include "..\Domain\Types.mqh"

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
   bool              FindPair(const string base, const string quote, string &symbol) const;
   void              BuildRoute(const string from, const string to, SConvRoute &route) const;
   bool              LegRate(const string symbol, const bool inverted, double &rate);
   string            RouteDesc(const SConvRoute &route) const;

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
//+------------------------------------------------------------------+
bool CMoney::FindPair(const string base, const string quote, string &symbol) const
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
         symbol = name;
         return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Direct pair, inverted pair, or two legs through any currency X   |
//| for which from/X and X/to pairs exist (no currency is assumed).  |
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

   string s = "";
   if(FindPair(from, to, s))
     {
      route.found = true;
      route.sym1 = s;
      return;
     }
   if(FindPair(to, from, s))
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
         if(!FindPair(middle, to, s2))
           {
            if(!FindPair(to, middle, s2))
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

#endif // RD_PLATFORM_MONEY_MQH
