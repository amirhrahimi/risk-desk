// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/SymbolSpec.mqh                               |
//| Layer   : Platform                                               |
//| Purpose : read every broker property of a symbol into            |
//|           SSymbolSpec at runtime (rule R3) and sanity-check it   |
//|           (BC-02). Callers re-read it on init, every 60 s and    |
//|           before every trade request; it is never cached across  |
//|           symbols or accounts.                                   |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_SYMBOLSPEC_MQH
#define RD_PLATFORM_SYMBOLSPEC_MQH

#include "..\Domain\Types.mqh"
#include "Compat.mqh"

class CSymbolSpec
  {
public:
   // Fills 's' with everything the broker reports, then applies the
   // BC-02 checks. Returns false when the symbol is unknown or a check
   // fails ('r' says which property); 's' is still filled as far as
   // possible so the caller can log it. A tick size of 0 is replaced
   // by the point and reported as a warning (r.sev == SEV_WARN).
   static bool       Read(const string symbol, SSymbolSpec &s, SResult &r);
   static bool       Exists(const string symbol);
   static string     Describe(const SSymbolSpec &s, const string accountCcy);
  };

//+------------------------------------------------------------------+
bool CSymbolSpec::Exists(const string symbol)
  {
   long digits = 0;
   return symbol != "" && SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits);
  }

//+------------------------------------------------------------------+
bool CSymbolSpec::Read(const string symbol, SSymbolSpec &s, SResult &r)
  {
   s.Reset();
   r.Reset();
   s.name = symbol;

   long digits = 0;
   if(symbol == "" || !SymbolInfoInteger(symbol, SYMBOL_DIGITS, digits))
      return RdFail(r, "Symbol " + symbol + " is not available on this server");

   s.digits       = (int)digits;
   s.point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
   s.tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   s.tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   s.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   s.volMin       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   s.volMax       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   s.volStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   s.stopsLevel   = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   s.freezeLevel  = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   s.tradeMode    = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   s.execMode     = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
   s.calcMode     = RdSymbolCalcMode(symbol);
   s.baseCcy      = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   s.profitCcy    = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   s.marginCcy    = SymbolInfoString(symbol, SYMBOL_CURRENCY_MARGIN);

#ifdef __MQL5__
   s.tickValueProfit = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   s.tickValueLoss   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   s.volLimit        = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);
   s.fillingFlags    = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   s.expirationFlags = (int)SymbolInfoInteger(symbol, SYMBOL_EXPIRATION_MODE);
   s.orderModeFlags  = (int)SymbolInfoInteger(symbol, SYMBOL_ORDER_MODE);
#else
   // BC-05: MT4 values a price move with MODE_TICKVALUE only.
   s.tickValueProfit = s.tickValue;
   s.tickValueLoss   = s.tickValue;
   s.volLimit        = 0.0;
   s.fillingFlags    = 0;
   s.expirationFlags = 0;
   s.orderModeFlags  = 0;
#endif

   //--- BC-02 sanity checks
   if(!MathIsValidNumber(s.point) || s.point <= 0.0)
      return RdFail(r, "Broker reports invalid point for " + symbol + " (" + RdNum(s.point, 10) + ")");
   if(!MathIsValidNumber(s.contractSize) || s.contractSize <= 0.0)
      return RdFail(r, "Broker reports invalid contract size for " + symbol + " (" + RdNum(s.contractSize) + ")");
   if(!MathIsValidNumber(s.volStep) || s.volStep <= 0.0)
      return RdFail(r, "Broker reports invalid volume step for " + symbol + " (" + RdNum(s.volStep) + ")");
   if(!MathIsValidNumber(s.volMin) || s.volMin <= 0.0)
      return RdFail(r, "Broker reports invalid minimum volume for " + symbol + " (" + RdNum(s.volMin) + ")");
   if(!MathIsValidNumber(s.volMax) || s.volMax < s.volMin - 1e-8)
      return RdFail(r, "Broker reports invalid maximum volume for " + symbol + " (" + RdNum(s.volMax) +
                    " below minimum " + RdNum(s.volMin) + ")");

   if(!MathIsValidNumber(s.tickSize) || s.tickSize <= 0.0)
     {
      s.tickSize = s.point;
      s.tickSizeFromPoint = true;
      return RdWarn(r, "Broker reports tick size 0 for " + symbol + "; using point " + RdNum(s.point, 10));
     }
   return RdOk(r, "Symbol spec OK");
  }

//+------------------------------------------------------------------+
//| One line for the Experts tab.                                    |
//+------------------------------------------------------------------+
string CSymbolSpec::Describe(const SSymbolSpec &s, const string accountCcy)
  {
   string text = s.name + ": digits " + IntegerToString(s.digits) +
                 ", point " + RdNum(s.point, 10) +
                 ", tick size " + RdNum(s.tickSize, 10) + (s.tickSizeFromPoint ? " (from point)" : "") +
                 ", tick value " + RdNum(s.tickValue) + " " + accountCcy +
                 " (profit " + RdNum(s.tickValueProfit) + ", loss " + RdNum(s.tickValueLoss) + ")" +
                 ", contract " + RdNum(s.contractSize) +
                 ", volume min " + RdNum(s.volMin) + " / step " + RdNum(s.volStep) +
                 " / max " + RdNum(s.volMax) + " / limit " + RdNum(s.volLimit) +
                 ", stops level " + IntegerToString(s.stopsLevel) + " pts" +
                 ", freeze level " + IntegerToString(s.freezeLevel) + " pts" +
                 ", trade " + RdSymbolTradeModeText(s.tradeMode) +
                 ", exec " + RdExecModeText(s.execMode) +
                 ", calc " + RdCalcModeText(s.calcMode) +
                 ", currencies " + s.baseCcy + "/" + s.profitCcy + " margin " + s.marginCcy +
                 ", filling " + RdFillingFlagsText(s.fillingFlags) +
                 ", expiration " + RdExpirationFlagsText(s.expirationFlags) +
                 ", orders " + RdOrderModeFlagsText(s.orderModeFlags);
   return text;
  }

#endif // RD_PLATFORM_SYMBOLSPEC_MQH
