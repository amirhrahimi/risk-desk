//+------------------------------------------------------------------+
//| RiskDesk - Platform/Compat.mqh                                   |
//| Layer   : Platform (one of the few places allowed to use         |
//|           #ifdef __MQL5__, rule R2)                              |
//| Purpose : language and terminal shims shared by MT4 and MT5:     |
//|           platform name, tester/DPI helpers, account margin      |
//|           mode, and text decoders for broker properties (used by |
//|           logs and BrokerProbe).                                 |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_COMPAT_MQH
#define RD_PLATFORM_COMPAT_MQH

#include "..\Domain\Types.mqh"

#ifdef __MQL5__
   #define RD_PLATFORM  "MT5"
   #define RD_MQL_DIR   "MQL5"
#else
   #define RD_PLATFORM  "MT4"
   #define RD_MQL_DIR   "MQL4"
#endif

// MT5 draws chart-object text in Unicode. MT4 draws it in the ANSI code
// page: characters outside Windows-1252 show as "?" (seen in P3 on the
// move handle), so glyphs must come from a symbol font there (ADR-021).
#ifdef __MQL5__
   #define RD_OBJ_TEXT_UNICODE  true
#else
   #define RD_OBJ_TEXT_UNICODE  false
#endif

// OBJPROP_TIMEFRAMES values that show / hide a chart object on every
// timeframe. MQL4 has no OBJ_NO_PERIODS; its documented value is EMPTY.
#ifdef __MQL5__
   #define RD_OBJ_ALL_PERIODS  OBJ_ALL_PERIODS
   #define RD_OBJ_NO_PERIODS   OBJ_NO_PERIODS
#else
   #define RD_OBJ_ALL_PERIODS  OBJ_ALL_PERIODS
   #define RD_OBJ_NO_PERIODS   EMPTY
#endif

//====================================================================
// Terminal / program
//====================================================================
bool RdIsTester()
  {
   return MQLInfoInteger(MQL_TESTER) != 0;
  }

bool RdIsVisualTester()
  {
   return MQLInfoInteger(MQL_VISUAL_MODE) != 0;
  }

int RdTerminalBuild()
  {
   return TerminalInfoInteger(TERMINAL_BUILD);
  }

int RdTerminalDpi()
  {
   int dpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   return dpi > 0 ? dpi : 96;
  }

double RdDpiScale()
  {
   return RdTerminalDpi() / 96.0;
  }

string RdDeinitReasonText(const int reason)
  {
   switch(reason)
     {
      case REASON_PROGRAM:
         return "stopped by the program";
      case REASON_REMOVE:
         return "removed from the chart";
      case REASON_RECOMPILE:
         return "recompiled";
      case REASON_CHARTCHANGE:
         return "chart symbol or timeframe changed";
      case REASON_CHARTCLOSE:
         return "chart closed";
      case REASON_PARAMETERS:
         return "inputs changed";
      case REASON_ACCOUNT:
         return "account changed";
      case REASON_TEMPLATE:
         return "template applied";
      case REASON_INITFAILED:
         return "initialisation failed";
      case REASON_CLOSE:
         return "terminal closed";
     }
   return "reason " + IntegerToString(reason);
  }

//====================================================================
// Account
//====================================================================
bool RdIsDemoAccount()
  {
   return AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO;
  }

// MT5 ENUM_ACCOUNT_MARGIN_MODE value; -1 on MT4 (no netting there).
int RdAccountMarginMode()
  {
#ifdef __MQL5__
   return (int)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
#else
   return -1;
#endif
  }

// BC-10: only RETAIL_HEDGING is hedging; RETAIL_NETTING and EXCHANGE are netting.
bool RdIsHedgingMarginMode(const int marginMode)
  {
#ifdef __MQL5__
   return marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
#else
   return true;
#endif
  }

string RdMarginModeText(const int marginMode)
  {
#ifdef __MQL5__
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return "hedging";
   if(marginMode == ACCOUNT_MARGIN_MODE_RETAIL_NETTING)
      return "netting";
   if(marginMode == ACCOUNT_MARGIN_MODE_EXCHANGE)
      return "exchange (treated as netting)";
   return "unknown (" + IntegerToString(marginMode) + ")";
#else
   return "hedging (MT4: every trade is its own ticket)";
#endif
  }

int RdAccountCurrencyDigits()
  {
#ifdef __MQL5__
   return (int)AccountInfoInteger(ACCOUNT_CURRENCY_DIGITS);
#else
   return 2;
#endif
  }

string RdAccountTradeModeText(const long mode)
  {
   if(mode == ACCOUNT_TRADE_MODE_DEMO)
      return "demo";
   if(mode == ACCOUNT_TRADE_MODE_CONTEST)
      return "contest";
   if(mode == ACCOUNT_TRADE_MODE_REAL)
      return "real";
   return "unknown (" + IntegerToString(mode) + ")";
  }

string RdStopoutModeText(const long mode)
  {
   if(mode == ACCOUNT_STOPOUT_MODE_PERCENT)
      return "percent";
   if(mode == ACCOUNT_STOPOUT_MODE_MONEY)
      return "money";
   return "unknown (" + IntegerToString(mode) + ")";
  }

//====================================================================
// Symbol properties
//====================================================================

// MT5: SYMBOL_TRADE_CALC_MODE. MT4: MODE_PROFITCALCMODE (0 forex, 1 CFD, 2 futures).
int RdSymbolCalcMode(const string symbol)
  {
#ifdef __MQL5__
   return (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_CALC_MODE);
#else
   return (int)MarketInfo(symbol, MODE_PROFITCALCMODE);
#endif
  }

bool RdIsForexCalcMode(const int calcMode)
  {
#ifdef __MQL5__
   return calcMode == SYMBOL_CALC_MODE_FOREX || calcMode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE;
#else
   return calcMode == 0;
#endif
  }

string RdCalcModeText(const int calcMode)
  {
#ifdef __MQL5__
   string s = EnumToString((ENUM_SYMBOL_CALC_MODE)calcMode);
   StringReplace(s, "SYMBOL_CALC_MODE_", "");
   StringToLower(s);
   return s + " (" + IntegerToString(calcMode) + ")";
#else
   switch(calcMode)
     {
      case 0:
         return "forex (0)";
      case 1:
         return "cfd (1)";
      case 2:
         return "futures (2)";
     }
   return "unknown (" + IntegerToString(calcMode) + ")";
#endif
  }

// Same numbering on both platforms (ENUM_SYMBOL_TRADE_MODE).
string RdSymbolTradeModeText(const int mode)
  {
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
      return "disabled (0)";
   if(mode == SYMBOL_TRADE_MODE_LONGONLY)
      return "long only (1)";
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY)
      return "short only (2)";
   if(mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return "close only (3)";
   if(mode == SYMBOL_TRADE_MODE_FULL)
      return "full (4)";
   return "unknown (" + IntegerToString(mode) + ")";
  }

// Same numbering on both platforms (ENUM_SYMBOL_TRADE_EXECUTION).
string RdExecModeText(const int mode)
  {
   if(mode == SYMBOL_TRADE_EXECUTION_REQUEST)
      return "request (0)";
   if(mode == SYMBOL_TRADE_EXECUTION_INSTANT)
      return "instant (1)";
   if(mode == SYMBOL_TRADE_EXECUTION_MARKET)
      return "market (2)";
   if(mode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
      return "exchange (3)";
   return "unknown (" + IntegerToString(mode) + ")";
  }

// BC-06: the flags are SYMBOL_FILLING_* bits, never ORDER_FILLING_* enum values.
string RdFillingFlagsText(const int flags)
  {
#ifdef __MQL5__
   string s = "";
   if((flags & SYMBOL_FILLING_FOK) != 0)
      s = RdJoin(s, "FOK");
   if((flags & SYMBOL_FILLING_IOC) != 0)
      s = RdJoin(s, "IOC");
   int other = flags & ~(SYMBOL_FILLING_FOK | SYMBOL_FILLING_IOC);
   if(other != 0)
      s = RdJoin(s, StringFormat("other 0x%X", other));
   if(s == "")
      s = "none";
   return s + " (" + IntegerToString(flags) + ")";
#else
   return "n/a (MT4)";
#endif
  }

string RdExpirationFlagsText(const int flags)
  {
#ifdef __MQL5__
   string s = "";
   if((flags & SYMBOL_EXPIRATION_GTC) != 0)
      s = RdJoin(s, "GTC");
   if((flags & SYMBOL_EXPIRATION_DAY) != 0)
      s = RdJoin(s, "DAY");
   if((flags & SYMBOL_EXPIRATION_SPECIFIED) != 0)
      s = RdJoin(s, "SPECIFIED");
   if((flags & SYMBOL_EXPIRATION_SPECIFIED_DAY) != 0)
      s = RdJoin(s, "SPECIFIED_DAY");
   int other = flags & ~(SYMBOL_EXPIRATION_GTC | SYMBOL_EXPIRATION_DAY | SYMBOL_EXPIRATION_SPECIFIED | SYMBOL_EXPIRATION_SPECIFIED_DAY);
   if(other != 0)
      s = RdJoin(s, StringFormat("other 0x%X", other));
   if(s == "")
      s = "none";
   return s + " (" + IntegerToString(flags) + ")";
#else
   return "n/a (MT4)";
#endif
  }

string RdOrderModeFlagsText(const int flags)
  {
#ifdef __MQL5__
   string s = "";
   if((flags & SYMBOL_ORDER_MARKET) != 0)
      s = RdJoin(s, "MARKET");
   if((flags & SYMBOL_ORDER_LIMIT) != 0)
      s = RdJoin(s, "LIMIT");
   if((flags & SYMBOL_ORDER_STOP) != 0)
      s = RdJoin(s, "STOP");
   if((flags & SYMBOL_ORDER_STOP_LIMIT) != 0)
      s = RdJoin(s, "STOP_LIMIT");
   if((flags & SYMBOL_ORDER_SL) != 0)
      s = RdJoin(s, "SL");
   if((flags & SYMBOL_ORDER_TP) != 0)
      s = RdJoin(s, "TP");
   if((flags & SYMBOL_ORDER_CLOSEBY) != 0)
      s = RdJoin(s, "CLOSE_BY");
   int known = SYMBOL_ORDER_MARKET | SYMBOL_ORDER_LIMIT | SYMBOL_ORDER_STOP | SYMBOL_ORDER_STOP_LIMIT |
               SYMBOL_ORDER_SL | SYMBOL_ORDER_TP | SYMBOL_ORDER_CLOSEBY;
   int other = flags & ~known;
   if(other != 0)
      s = RdJoin(s, StringFormat("other 0x%X", other));
   if(s == "")
      s = "none";
   return s + " (" + IntegerToString(flags) + ")";
#else
   return "n/a (MT4)";
#endif
  }

// BC-11: MT5 symbols may refuse SL. MT4 has no such flag.
bool RdSymbolAcceptsSl(const SSymbolSpec &spec)
  {
#ifdef __MQL5__
   return (spec.orderModeFlags & SYMBOL_ORDER_SL) != 0;
#else
   return true;
#endif
  }

// MT5 SYMBOL_ORDER_MODE: TP allowed on this symbol. MT4: always.
bool RdSymbolAcceptsTp(const SSymbolSpec &spec)
  {
#ifdef __MQL5__
   return (spec.orderModeFlags & SYMBOL_ORDER_TP) != 0;
#else
   return true;
#endif
  }

// MT5 SYMBOL_ORDER_MODE: market / limit / stop orders allowed. MT4: always.
bool RdSymbolAcceptsKind(const SSymbolSpec &spec, const EOrderKind kind)
  {
#ifdef __MQL5__
   if(kind == KIND_LIMIT)
      return (spec.orderModeFlags & SYMBOL_ORDER_LIMIT) != 0;
   if(kind == KIND_STOP)
      return (spec.orderModeFlags & SYMBOL_ORDER_STOP) != 0;
   return (spec.orderModeFlags & SYMBOL_ORDER_MARKET) != 0;
#else
   return true;
#endif
  }

//====================================================================
// Time
//====================================================================

// Server time for request timestamps (BC-14) and expirations (BC-08).
// MT5: the terminal's estimate of the current server time, which keeps
// running between ticks. MT4: time of the last server tick (the only
// server clock MQL4 has).
datetime RdServerTime()
  {
#ifdef __MQL5__
   return TimeTradeServer();
#else
   return TimeCurrent();
#endif
  }

//====================================================================
// Chart: MetaTrader's own trade history display (F-20)
//====================================================================

// MT5 "Show trade history" (CHART_SHOW_TRADE_HISTORY): the deals the
// terminal draws itself, not as chart objects. False on MT4, which has no
// such property (it draws closed trades as "#ticket ..." objects).
bool RdChartTradeHistory(bool &on)
  {
   on = false;
#ifdef __MQL5__
   long value = 0;
   if(!ChartGetInteger(0, CHART_SHOW_TRADE_HISTORY, 0, value))
      return false;
   on = (value != 0);
   return true;
#else
   return false;
#endif
  }

bool RdSetChartTradeHistory(const bool on)
  {
#ifdef __MQL5__
   return ChartSetInteger(0, CHART_SHOW_TRADE_HISTORY, on);
#else
   return false;
#endif
  }

#ifdef __MQL5__
//====================================================================
// MT5 trade server return codes -> constant names (for logs/reports).
//====================================================================
string RdRetcodeText(const uint retcode)
  {
   switch((int)retcode)
     {
      case 0:
         return "OK";
      case TRADE_RETCODE_REQUOTE:
         return "REQUOTE";
      case TRADE_RETCODE_REJECT:
         return "REJECT";
      case TRADE_RETCODE_CANCEL:
         return "CANCEL";
      case TRADE_RETCODE_PLACED:
         return "PLACED";
      case TRADE_RETCODE_DONE:
         return "DONE";
      case TRADE_RETCODE_DONE_PARTIAL:
         return "DONE_PARTIAL";
      case TRADE_RETCODE_ERROR:
         return "ERROR";
      case TRADE_RETCODE_TIMEOUT:
         return "TIMEOUT";
      case TRADE_RETCODE_INVALID:
         return "INVALID";
      case TRADE_RETCODE_INVALID_VOLUME:
         return "INVALID_VOLUME";
      case TRADE_RETCODE_INVALID_PRICE:
         return "INVALID_PRICE";
      case TRADE_RETCODE_INVALID_STOPS:
         return "INVALID_STOPS";
      case TRADE_RETCODE_TRADE_DISABLED:
         return "TRADE_DISABLED";
      case TRADE_RETCODE_MARKET_CLOSED:
         return "MARKET_CLOSED";
      case TRADE_RETCODE_NO_MONEY:
         return "NO_MONEY";
      case TRADE_RETCODE_PRICE_CHANGED:
         return "PRICE_CHANGED";
      case TRADE_RETCODE_PRICE_OFF:
         return "PRICE_OFF";
      case TRADE_RETCODE_INVALID_EXPIRATION:
         return "INVALID_EXPIRATION";
      case TRADE_RETCODE_ORDER_CHANGED:
         return "ORDER_CHANGED";
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         return "TOO_MANY_REQUESTS";
      case TRADE_RETCODE_NO_CHANGES:
         return "NO_CHANGES";
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         return "SERVER_DISABLES_AT";
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
         return "CLIENT_DISABLES_AT";
      case TRADE_RETCODE_LOCKED:
         return "LOCKED";
      case TRADE_RETCODE_FROZEN:
         return "FROZEN";
      case TRADE_RETCODE_INVALID_FILL:
         return "INVALID_FILL";
      case TRADE_RETCODE_CONNECTION:
         return "CONNECTION";
      case TRADE_RETCODE_ONLY_REAL:
         return "ONLY_REAL";
      case TRADE_RETCODE_LIMIT_ORDERS:
         return "LIMIT_ORDERS";
      case TRADE_RETCODE_LIMIT_VOLUME:
         return "LIMIT_VOLUME";
      case TRADE_RETCODE_INVALID_ORDER:
         return "INVALID_ORDER";
      case TRADE_RETCODE_POSITION_CLOSED:
         return "POSITION_CLOSED";
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME:
         return "INVALID_CLOSE_VOLUME";
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
         return "CLOSE_ORDER_EXIST";
      case TRADE_RETCODE_LIMIT_POSITIONS:
         return "LIMIT_POSITIONS";
      case TRADE_RETCODE_REJECT_CANCEL:
         return "REJECT_CANCEL";
      case TRADE_RETCODE_LONG_ONLY:
         return "LONG_ONLY";
      case TRADE_RETCODE_SHORT_ONLY:
         return "SHORT_ONLY";
      case TRADE_RETCODE_CLOSE_ONLY:
         return "CLOSE_ONLY";
      case TRADE_RETCODE_FIFO_CLOSE:
         return "FIFO_CLOSE";
      case TRADE_RETCODE_HEDGE_PROHIBITED:
         return "HEDGE_PROHIBITED";
     }
   return "UNKNOWN";
  }
#endif // __MQL5__

#endif // RD_PLATFORM_COMPAT_MQH
