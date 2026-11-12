//+------------------------------------------------------------------+
//| BrokerProbe.mq5 - diagnostic script entry file (MT5)             |
//| Writes MQL5\Files\RiskDesk\probe_<company>_MT5_<login>_<date>.txt|
//| (F-27, 08-testing section 3). NOTHING IS TRADED: the checks use  |
//| OrderCheck, which validates a request without sending it.        |
//|                                                                  |
//| The shared report body is BrokerProbeCore.mqh; this file adds    |
//| the MT5-only parts through the three ProbePlatform* hooks.       |
//+------------------------------------------------------------------+
#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property description "RiskDesk BrokerProbe: writes a broker, account and symbol report to MQL5\\Files\\RiskDesk."
#property description "Nothing is traded. Filling and expiration policies are tested with OrderCheck only."
#property script_show_inputs

#include "BrokerProbeCore.mqh"

void OnStart()
  {
   ProbeRun();
  }

//+------------------------------------------------------------------+
void ProbePlatformAccount(CProbeWriter &w)
  {
   w.Kv("fifo_close", RdBoolText(AccountInfoInteger(ACCOUNT_FIFO_CLOSE) != 0));
   w.Kv("server_time_estimate", ProbeTime(TimeTradeServer()));
  }

//+------------------------------------------------------------------+
void ProbePlatformSymbol(CProbeWriter &w, const SSymbolSpec &s, const SAccountSpec &a)
  {
   w.Group("mt5");
   w.Kv2("tick_value_profit", ProbeMoney(s.tickValueProfit, a.currency));
   w.Kv2("tick_value_loss", ProbeMoney(s.tickValueLoss, a.currency));
   w.Kv2("volume_limit", s.volLimit > 0.0 ? RdNum(s.volLimit) : "0 (no limit)");
   w.Kv2("margin_initial", RdNum(SymbolInfoDouble(s.name, SYMBOL_MARGIN_INITIAL)));
   w.Kv2("margin_maintenance", RdNum(SymbolInfoDouble(s.name, SYMBOL_MARGIN_MAINTENANCE)));
   w.Kv2("margin_hedged", RdNum(SymbolInfoDouble(s.name, SYMBOL_MARGIN_HEDGED)));
   double initial = 0.0;
   double maintenance = 0.0;
   if(SymbolInfoMarginRate(s.name, ORDER_TYPE_BUY, initial, maintenance))
      w.Kv2("margin_rate_buy", "initial " + RdNum(initial) + ", maintenance " + RdNum(maintenance));
   if(SymbolInfoMarginRate(s.name, ORDER_TYPE_SELL, initial, maintenance))
      w.Kv2("margin_rate_sell", "initial " + RdNum(initial) + ", maintenance " + RdNum(maintenance));
   w.Kv2("swap_mode", EnumToString((ENUM_SYMBOL_SWAP_MODE)SymbolInfoInteger(s.name, SYMBOL_SWAP_MODE)));
   w.Kv2("chart_mode", EnumToString((ENUM_SYMBOL_CHART_MODE)SymbolInfoInteger(s.name, SYMBOL_CHART_MODE)));
  }

//+------------------------------------------------------------------+
//| One OrderCheck call, written as one report line.                 |
//+------------------------------------------------------------------+
void ProbeOrderCheck(CProbeWriter &w, const string key, MqlTradeRequest &request)
  {
   MqlTradeCheckResult result;
   ZeroMemory(result);
   ResetLastError();
   bool ok = OrderCheck(request, result);
   int error = GetLastError();
   string text = "ok=" + RdBoolText(ok) + " retcode=" + IntegerToString(result.retcode) + " " + RdRetcodeText(result.retcode);
   if(result.comment != "")
      text += " \"" + result.comment + "\"";
   if(ok)
      text += " margin=" + RdNum(result.margin, 2);
   else
      if(error != 0)
         text += " last_error=" + IntegerToString(error);
   w.Kv2(key, text);
  }

void ProbeBaseRequest(MqlTradeRequest &request, const SSymbolSpec &s)
  {
   ZeroMemory(request);
   request.symbol     = s.name;
   request.volume     = s.volMin;
   request.magic      = 0;
   request.deviation  = 20;
   request.comment    = "RiskDesk probe";
   request.sl         = 0.0;
   request.tp         = 0.0;
   request.type_time  = ORDER_TIME_GTC;
   request.expiration = 0;
  }

string ProbeFillingName(const ENUM_ORDER_TYPE_FILLING filling)
  {
   if(filling == ORDER_FILLING_FOK)
      return "FOK";
   if(filling == ORDER_FILLING_IOC)
      return "IOC";
   return "RETURN";
  }

string ProbeTimeName(const ENUM_ORDER_TYPE_TIME typeTime)
  {
   if(typeTime == ORDER_TIME_GTC)
      return "GTC";
   if(typeTime == ORDER_TIME_DAY)
      return "DAY";
   if(typeTime == ORDER_TIME_SPECIFIED)
      return "SPECIFIED";
   return "SPECIFIED_DAY";
  }

//+------------------------------------------------------------------+
//| BC-06 / BC-08 evidence: which filling and expiration policies    |
//| the terminal accepts for a market buy and a buy limit (min lot). |
//+------------------------------------------------------------------+
void ProbePlatformChecks(CProbeWriter &w, const SSymbolSpec &s, const SQuote &q, const bool hasQuote, const SAccountSpec &a)
  {
   w.Group("checks (OrderCheck only, nothing is executed)");
   if(!hasQuote)
     {
      w.Kv2("skipped", "no quote or invalid symbol spec");
      return;
     }
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
      w.Kv2("note", "Algo Trading is off in the toolbar: OrderCheck may answer 10027 CLIENT_DISABLES_AT to every check. Switch it on and run again.");

   //--- market buy, min lot, each filling policy
   ENUM_ORDER_TYPE_FILLING fillings[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC, ORDER_FILLING_RETURN};
   MqlTradeRequest request;
   for(int i = 0; i < ArraySize(fillings); i++)
     {
      ProbeBaseRequest(request, s);
      request.action       = TRADE_ACTION_DEAL;
      request.type         = ORDER_TYPE_BUY;
      request.price        = q.ask;
      request.type_filling = fillings[i];
      ProbeOrderCheck(w, "market_buy fill=" + ProbeFillingName(fillings[i]), request);
     }

   //--- buy limit far below the market (1 % or 3x the stops+freeze distance)
   double distance = MathMax(q.ask * 0.01, (s.stopsLevel + s.freezeLevel + 10) * s.point * 3.0);
   double price = NormalizeDouble(MathFloor((q.ask - distance) / s.tickSize + 1e-8) * s.tickSize, s.digits);
   if(price <= 0.0)
     {
      w.Kv2("buy_limit", "skipped (no valid price below the market)");
      return;
     }
   w.Kv2("buy_limit_price", DoubleToString(price, s.digits) + "  (ask " + DoubleToString(q.ask, s.digits) + ")");

   datetime expiry = TimeTradeServer() + 86400;
   ENUM_ORDER_TYPE_TIME times[] = {ORDER_TIME_GTC, ORDER_TIME_DAY, ORDER_TIME_SPECIFIED, ORDER_TIME_SPECIFIED_DAY};
   for(int i = 0; i < ArraySize(times); i++)
     {
      ProbeBaseRequest(request, s);
      request.action       = TRADE_ACTION_PENDING;
      request.type         = ORDER_TYPE_BUY_LIMIT;
      request.price        = price;
      request.type_filling = ORDER_FILLING_RETURN;
      request.type_time    = times[i];
      request.expiration   = (times[i] == ORDER_TIME_SPECIFIED || times[i] == ORDER_TIME_SPECIFIED_DAY) ? expiry : 0;
      ProbeOrderCheck(w, "buy_limit fill=RETURN time=" + ProbeTimeName(times[i]), request);
     }
   ENUM_ORDER_TYPE_FILLING pendingFillings[] = {ORDER_FILLING_FOK, ORDER_FILLING_IOC};
   for(int i = 0; i < ArraySize(pendingFillings); i++)
     {
      ProbeBaseRequest(request, s);
      request.action       = TRADE_ACTION_PENDING;
      request.type         = ORDER_TYPE_BUY_LIMIT;
      request.price        = price;
      request.type_filling = pendingFillings[i];
      ProbeOrderCheck(w, "buy_limit fill=" + ProbeFillingName(pendingFillings[i]) + " time=GTC", request);
     }
  }
