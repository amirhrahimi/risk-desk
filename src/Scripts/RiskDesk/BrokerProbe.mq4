// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| BrokerProbe.mq4 - diagnostic script entry file (MT4)             |
//| Writes MQL4\Files\RiskDesk\probe_<company>_MT4_<login>_<date>.txt|
//| (F-27, 08-testing section 3). NOTHING IS TRADED.                 |
//|                                                                  |
//| The shared report body is BrokerProbeCore.mqh; this file adds    |
//| the MT4-only parts through the three ProbePlatform* hooks.       |
//+------------------------------------------------------------------+
#property strict

#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property link        RD_LINK
#property version     RD_VERSION_PROP
#property description "RiskDesk BrokerProbe: writes a broker, account and symbol report to MQL4\\Files\\RiskDesk."
#property description "Nothing is traded."
#property script_show_inputs

#include "BrokerProbeCore.mqh"

void OnStart()
  {
   ProbeRun();
  }

//+------------------------------------------------------------------+
void ProbePlatformAccount(CProbeWriter &w)
  {
   w.Kv("free_margin_mode", IntegerToString((int)AccountFreeMarginMode()) +
        "  (0 floating P/L ignored, 1 profit and loss counted, 2 profit only, 3 loss only)");
   w.Kv("stopout_mode", AccountStopoutMode() == 0 ? "percent" : "money");
   w.Kv("stopout_level", IntegerToString(AccountStopoutLevel()));
  }

//+------------------------------------------------------------------+
//| Raw MarketInfo values, to compare with the SymbolInfo* values    |
//| above (some MT4 servers disagree between the two).               |
//+------------------------------------------------------------------+
void ProbePlatformSymbol(CProbeWriter &w, const SSymbolSpec &s, const SAccountSpec &a)
  {
   string n = s.name;
   w.Group("mt4 marketinfo");
   w.Kv2("MODE_LOTSIZE", RdNum(MarketInfo(n, MODE_LOTSIZE)));
   w.Kv2("MODE_TICKVALUE", ProbeMoney(MarketInfo(n, MODE_TICKVALUE), a.currency));
   w.Kv2("MODE_TICKSIZE", RdNum(MarketInfo(n, MODE_TICKSIZE), 10));
   w.Kv2("MODE_MINLOT", RdNum(MarketInfo(n, MODE_MINLOT)));
   w.Kv2("MODE_LOTSTEP", RdNum(MarketInfo(n, MODE_LOTSTEP)));
   w.Kv2("MODE_MAXLOT", RdNum(MarketInfo(n, MODE_MAXLOT)));
   w.Kv2("MODE_STOPLEVEL", RdNum(MarketInfo(n, MODE_STOPLEVEL)));
   w.Kv2("MODE_FREEZELEVEL", RdNum(MarketInfo(n, MODE_FREEZELEVEL)));
   w.Kv2("MODE_MARGINREQUIRED", ProbeMoney(MarketInfo(n, MODE_MARGINREQUIRED), a.currency) + "  (free margin for 1 lot)");
   w.Kv2("MODE_MARGININIT", RdNum(MarketInfo(n, MODE_MARGININIT)));
   w.Kv2("MODE_MARGINMAINTENANCE", RdNum(MarketInfo(n, MODE_MARGINMAINTENANCE)));
   w.Kv2("MODE_MARGINHEDGED", RdNum(MarketInfo(n, MODE_MARGINHEDGED)));
   w.Kv2("MODE_PROFITCALCMODE", RdNum(MarketInfo(n, MODE_PROFITCALCMODE)) + "  (0 forex, 1 CFD, 2 futures)");
   w.Kv2("MODE_MARGINCALCMODE", RdNum(MarketInfo(n, MODE_MARGINCALCMODE)) + "  (0 forex, 1 CFD, 2 futures, 3 CFD on index)");
   w.Kv2("MODE_SWAPTYPE", RdNum(MarketInfo(n, MODE_SWAPTYPE)) + "  (0 points, 1 base ccy, 2 interest, 3 margin ccy)");
   w.Kv2("MODE_TRADEALLOWED", RdNum(MarketInfo(n, MODE_TRADEALLOWED)));
   w.Kv2("raw_tick_value_profit", RdNum(SymbolInfoDouble(n, SYMBOL_TRADE_TICK_VALUE_PROFIT)) + "  (not used on MT4)");
   w.Kv2("raw_tick_value_loss", RdNum(SymbolInfoDouble(n, SYMBOL_TRADE_TICK_VALUE_LOSS)) + "  (not used on MT4)");
   w.Kv2("raw_volume_limit", RdNum(SymbolInfoDouble(n, SYMBOL_VOLUME_LIMIT)) + "  (not used on MT4)");
   w.Kv2("raw_filling_flags", IntegerToString(SymbolInfoInteger(n, SYMBOL_FILLING_MODE)) + "  (not used on MT4)");
   w.Kv2("raw_expiration_flags", IntegerToString(SymbolInfoInteger(n, SYMBOL_EXPIRATION_MODE)) + "  (not used on MT4)");
  }

//+------------------------------------------------------------------+
//| MT4 has no OrderCheck. AccountFreeMarginCheck is the only        |
//| request validation available without sending an order.          |
//+------------------------------------------------------------------+
void ProbePlatformChecks(CProbeWriter &w, const SSymbolSpec &s, const SQuote &q, const bool hasQuote, const SAccountSpec &a)
  {
   w.Group("checks");
   w.Kv2("order_check", "n/a (MT4 has no OrderCheck; the server's answer is only known when an order is sent: GatewaySmoke, phase P2)");
   if(!hasQuote)
     {
      w.Kv2("free_margin_check", "skipped (no quote or invalid symbol spec)");
      return;
     }
   ResetLastError();
   double after = AccountFreeMarginCheck(s.name, OP_BUY, s.volMin);
   int error = GetLastError();
   string text = ProbeMoney(after, a.currency) + "  (free margin left after a " + RdNum(s.volMin) + " lot buy at " +
                 DoubleToString(q.ask, s.digits) + ")";
   if(error != 0)
      text += "  error " + IntegerToString(error);
   if(after <= 0.0 || error == ERR_NOT_ENOUGH_MONEY)
      text += "  INSUFFICIENT MARGIN";
   w.Kv2("free_margin_after_min_lot_buy", text);
  }
