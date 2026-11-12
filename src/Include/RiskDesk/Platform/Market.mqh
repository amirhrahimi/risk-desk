//+------------------------------------------------------------------+
//| RiskDesk - Platform/Market.mqh                                   |
//| Layer   : Platform                                               |
//| Purpose : fresh quotes (02-architecture section 9).              |
//| Status  : P0 provides Quote(), used by BrokerProbe. Anything     |
//|           else the panel needs is added in phase P2.             |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_MARKET_MQH
#define RD_PLATFORM_MARKET_MQH

#include "..\Domain\Types.mqh"

class CMarket
  {
public:
   // Last bid/ask/time of 'symbol'. False when the terminal has no
   // valid quote yet (symbol just added, market closed since start-up).
   static bool       Quote(const string symbol, SQuote &q);
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

#endif // RD_PLATFORM_MARKET_MQH
