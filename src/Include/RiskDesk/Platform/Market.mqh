// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/Market.mqh                                   |
//| Layer   : Platform                                               |
//| Purpose : fresh quotes (02-architecture section 9), the BC-17    |
//|           stale-quote check, trade sessions, and CServerClock:   |
//|           the server time that keeps running between ticks for   |
//|           the candle countdown (F-21, 05 section 6).             |
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
   // The symbol's trading sessions (Market Watch > Specification): is 'when'
   // (server time) inside one? known = false when the terminal lists none.
   // Information only (BC-17: the server decides whether an order trades).
   static bool       InSession(const string symbol, const datetime when, bool &known);
  };

//+------------------------------------------------------------------+
//| F-21 / 05 section 6: the server time, also between ticks.        |
//| MT5: TimeTradeServer() (the terminal's estimate). MT4 has only   |
//| TimeCurrent(), the whole second of the last tick: the clock runs |
//| on GetTickCount() milliseconds from an anchor in server time.    |
//| Every tick is a lower bound (the server time is at least that    |
//| second): a tick later than the clock moves the anchor up to it,  |
//| so the clock converges onto the server time from below and never |
//| runs ahead by a rounding second. A tick 2 s or more behind the   |
//| clock (the clock was anchored on an old tick) re-anchors it.     |
//| No tick at all (weekend): it runs on from the last tick.         |
//| One instance per user (state in members, not global).            |
//+------------------------------------------------------------------+
class CServerClock
  {
private:
   long              m_anchorMs;      // server time in ms at m_anchorAt
   uint              m_anchorAt;      // GetTickCount() then
   bool              m_known;
   datetime          m_lastTick;

public:
                     CServerClock() { Reset(); }
   void              Reset() { m_anchorMs = 0; m_anchorAt = 0; m_known = false; m_lastTick = 0; }
   datetime          Now();
  };

datetime CServerClock::Now()
  {
#ifdef __MQL5__
   return TimeTradeServer();
#else
   datetime server = TimeCurrent();
   if(server <= 0)
      return TimeLocal();
   uint at = GetTickCount();
   long low = (long)server * 1000;
   if(!m_known)
     {
      m_anchorMs = low;
      m_anchorAt = at;
      m_known = true;
      m_lastTick = server;
      return server;
     }
   long estimate = m_anchorMs + (long)(uint)(at - m_anchorAt);
   if(server != m_lastTick)
     {
      m_lastTick = server;
      if(low > estimate || low < estimate - 2000)
        {
         m_anchorMs = low;
         m_anchorAt = at;
         estimate = low;
        }
     }
   return (datetime)(estimate / 1000);
#endif
  }

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

bool CMarket::InSession(const string symbol, const datetime when, bool &known)
  {
   known = false;
   MqlDateTime dt;
   TimeToStruct(when, dt);
   ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)dt.day_of_week;
   long now = dt.hour * 3600 + dt.min * 60 + dt.sec;
   datetime from = 0;
   datetime to = 0;
   for(uint i = 0; i < 16 && SymbolInfoSessionTrade(symbol, day, i, from, to); i++)
     {
      known = true;
      long a = (long)from % 86400;
      long b = (long)to - ((long)from - a);   // "24:00" comes back as the next day's 00:00
      if(now >= a && now < b)
         return true;
     }
   return false;
  }

#endif // RD_PLATFORM_MARKET_MQH
