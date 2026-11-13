//+------------------------------------------------------------------+
//| RiskDesk - Domain/TimeMath.mqh                                   |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : - the candle countdown (F-21, 05 section 6, Q4, Q20):  |
//|             when the chart's current candle closes, the text     |
//|             "<-- mm:ss" / "<-- hh:mm:ss" / "<-- Nd hh:mm:ss" and |
//|             when it turns red;                                   |
//|           - the day of a daily log file (F-32) and whether it is |
//|             older than the files kept (InpLogKeepDays).          |
//|           Times are server times for the countdown, local times  |
//|           for the log files; TimeToStruct / StructToTime only    |
//|           convert, they read no terminal state.                  |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_TIMEMATH_MQH
#define RD_DOMAIN_TIMEMATH_MQH

#include "Types.mqh"

#define RD_DAY_SEC   86400

// The countdown of the chart's current candle (F-21).
struct SCandleClock
  {
   datetime          open;      // open of the candle counted down
   datetime          close;     // its close (the next candle's open)
   long              length;    // seconds (MN1: this calendar month)
   long              left;      // seconds to the close, never negative
   bool              closed;    // the time ran out and the market is closed: "<-- 00:00"
   bool              warn;      // red: left <= warnPct % of the length, or 00:00 (Q20)
   string            text;      // "<-- 02:33:29"

   void              Reset()
     {
      open = 0;
      close = 0;
      length = 0;
      left = 0;
      closed = false;
      warn = false;
      text = "";
     }
  };

bool RdIsLeapYear(const int year)
  {
   return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  }

int RdDaysInMonth(const int year, const int mon)
  {
   switch(mon)
     {
      case 2:
         return RdIsLeapYear(year) ? 29 : 28;
      case 4:
      case 6:
      case 9:
      case 11:
         return 30;
      default:
         return 31;
     }
  }

// 't' moved by 'months' calendar months (the day clamped to the month's end).
datetime RdAddMonths(const datetime t, const int months)
  {
   MqlDateTime d;
   TimeToStruct(t, d);
   int m = (d.mon - 1) + months;
   int years = (m >= 0) ? m / 12 : -((11 - m) / 12);
   d.year += years;
   d.mon = m - years * 12 + 1;
   int dim = RdDaysInMonth(d.year, d.mon);
   if(d.day > dim)
      d.day = dim;
   return StructToTime(d);
  }

// Close of the candle opened at 'open' on a chart period of 'periodSec'
// seconds; monthly = MN1 (calendar months, not PeriodSeconds' 30 days).
datetime RdCandleClose(const datetime open, const int periodSec, const bool monthly)
  {
   if(monthly)
      return RdAddMonths(open, 1);
   return (datetime)((long)open + periodSec);
  }

//+------------------------------------------------------------------+
//| "<-- mm:ss" under one hour, "<-- hh:mm:ss" from one hour,        |
//| "<-- Nd hh:mm:ss" from 24 h (Q4, D3). Negative counts as 0.      |
//| pointRight: the text stands left of the candle (no room right of |
//| it, D39), the arrow still points at it: "mm:ss -->".             |
//+------------------------------------------------------------------+
string RdCountdownText(const long secondsLeft, const bool pointRight = false)
  {
   long s = (secondsLeft > 0) ? secondsLeft : 0;
   int days = (int)(s / RD_DAY_SEC);
   s -= (long)days * RD_DAY_SEC;
   int h = (int)(s / 3600);
   s -= (long)h * 3600;
   int m = (int)(s / 60);
   int sec = (int)(s - (long)m * 60);
   string t;
   if(days > 0)
      t = StringFormat("%dd %02d:%02d:%02d", days, h, m, sec);
   else
      if(h > 0)
         t = StringFormat("%02d:%02d:%02d", h, m, sec);
      else
         t = StringFormat("%02d:%02d", m, sec);
   return pointRight ? t + " -->" : "<-- " + t;
  }

//+------------------------------------------------------------------+
//| F-21 AC1/AC2. 'open' = open time of the chart's current bar      |
//| (bar 0), 'now' = the estimated server time.                      |
//| The bar's time ran out without a new bar (no tick yet):          |
//| - inSession: the candle running by the clock is counted down     |
//|   (its bar appears with its first tick), so a quiet M1 chart     |
//|   keeps counting between ticks;                                  |
//| - else the market is closed: "<-- 00:00", red.                   |
//| inSession is used only in that case (the caller may pass false   |
//| when now < RdCandleClose(open, ...)).                            |
//| warnPct: red when left <= warnPct % of the candle's length (Q20; |
//| 0 = red only at 00:00).                                          |
//+------------------------------------------------------------------+
bool RdCandleClock(const datetime open, const int periodSec, const bool monthly, const datetime now,
                   const bool inSession, const int warnPct, SCandleClock &c)
  {
   c.Reset();
   if(open <= 0 || periodSec <= 0 || now <= 0)
      return false;
   datetime start = open;
   datetime close = RdCandleClose(open, periodSec, monthly);
   if(now >= close && inSession)
     {
      if(monthly)
        {
         for(int i = 0; i < 1200 && now >= close; i++)
           {
            start = close;
            close = RdAddMonths(close, 1);
           }
        }
      else
        {
         long k = ((long)now - (long)close) / periodSec;   // whole candles that ran out besides bar 0's
         start = (datetime)((long)close + k * periodSec);
         close = (datetime)((long)start + periodSec);
        }
     }
   c.open = start;
   c.close = close;
   c.length = (long)close - (long)start;
   long left = (long)close - (long)now;
   c.left = (left > 0) ? left : 0;
   c.closed = (c.left == 0);
   int pct = warnPct;
   if(pct < 0)
      pct = 0;
   if(pct > 100)
      pct = 100;
   c.warn = c.closed || (pct > 0 && c.left * 100 <= (long)pct * c.length);
   c.text = RdCountdownText(c.left);
   return true;
  }

//====================================================================
// Daily log files (F-32)
//====================================================================

//+------------------------------------------------------------------+
//| "<prefix>_<yyyymmdd>.log" -> that day at 00:00. False for any    |
//| other name, so only RiskDesk's own daily files are ever pruned.  |
//+------------------------------------------------------------------+
bool RdLogFileDay(const string fileName, const string prefix, datetime &day)
  {
   day = 0;
   string head = prefix + "_";
   int hl = StringLen(head);
   if(StringLen(fileName) != hl + 12 || StringSubstr(fileName, 0, hl) != head || StringSubstr(fileName, hl + 8) != ".log")
      return false;
   for(int i = hl; i < hl + 8; i++)
     {
      ushort ch = StringGetCharacter(fileName, i);
      if(ch < '0' || ch > '9')
         return false;
     }
   MqlDateTime d;
   d.year = (int)StringToInteger(StringSubstr(fileName, hl, 4));
   d.mon = (int)StringToInteger(StringSubstr(fileName, hl + 4, 2));
   d.day = (int)StringToInteger(StringSubstr(fileName, hl + 6, 2));
   d.hour = 0;
   d.min = 0;
   d.sec = 0;
   d.day_of_week = 0;
   d.day_of_year = 0;
   if(d.year < 1971 || d.year > 3000 || d.mon < 1 || d.mon > 12 || d.day < 1 || d.day > RdDaysInMonth(d.year, d.mon))
      return false;
   day = StructToTime(d);
   return true;
  }

// keepDays > 0: the file of 'fileDay' is older than the last keepDays days
// up to 'today' (today counts as one). keepDays <= 0: every file is kept.
bool RdLogFileExpired(const datetime fileDay, const datetime today, const int keepDays)
  {
   if(keepDays <= 0)
      return false;
   long today0 = (long)today - (long)today % RD_DAY_SEC;
   return (long)fileDay <= today0 - (long)keepDays * RD_DAY_SEC;
  }

#endif // RD_DOMAIN_TIMEMATH_MQH
