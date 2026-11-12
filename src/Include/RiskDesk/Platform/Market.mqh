//+------------------------------------------------------------------+
//| RiskDesk - Platform/Market.mqh                                   |
//| Layer   : Platform                                               |
//| Purpose : fresh quotes (02-architecture section 9) and the       |
//|           BC-17 stale-quote check.                               |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_MARKET_MQH
#define RD_PLATFORM_MARKET_MQH

#include "..\Domain\Types.mqh"
#include "Compat.mqh"

class CMarket
  {
public:
   // Last bid/ask/time of 'symbol'. False when the terminal has no
   // valid quote yet (symbol just added, market closed since start-up).
   static bool       Quote(const string symbol, SQuote &q);
   // BC-17: seconds since the quote's tick, on the server clock.
   static int        AgeSeconds(const SQuote &q);
   // BC-17: older than staleSec (> 0) -> "No quotes for N min - market may
   // be closed" (amber hint; trading is not blocked, the server decides).
   static bool       IsStale(const SQuote &q, const int staleSec);
  };

//+------------------------------------------------------------------+
bool CMarket::Quote(const string symbol, SQuote &q)
  {
   q.Reset();
#ifdef __MQL4__
   if(symbol == _Symbol && !RefreshRates())
     {
      // No new tick since the last call; SymbolInfoTick still returns the latest one.
     }
#endif
   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;
   q.bid = tick.bid;
   q.ask = tick.ask;
   q.time = tick.time;
   return MathIsValidNumber(q.bid) && MathIsValidNumber(q.ask) && q.bid > 0.0 && q.ask > 0.0;
  }

int CMarket::AgeSeconds(const SQuote &q)
  {
   if(q.time <= 0)
      return -1;
   long age = (long)(RdServerTime() - q.time);
   return (age < 0) ? 0 : (int)age;
  }

bool CMarket::IsStale(const SQuote &q, const int staleSec)
  {
   if(staleSec <= 0)
      return false;
   int age = AgeSeconds(q);
   return age < 0 || age > staleSec;
  }

#endif // RD_PLATFORM_MARKET_MQH
