//+------------------------------------------------------------------+
//| GatewaySmoke.mq4 - gateway smoke test script entry file (MT4)    |
//| Places and removes real orders on a DEMO account only (rule R13).|
//| Status : stub. The test sequence arrives in phase P2; this stub  |
//|          sends nothing.                                          |
//+------------------------------------------------------------------+
#property strict

#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property description "RiskDesk gateway smoke test (demo accounts only). Phase P0 stub: sends nothing."

#include "..\..\Include\RiskDesk\Platform\TradeGateway.mqh"

void OnStart()
  {
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
     {
      Alert("GatewaySmoke runs on demo accounts only (rule R13). Aborted, nothing was sent.");
      return;
     }
   Print("GatewaySmoke ", RD_VERSION, ": not implemented yet (phase P2). Nothing was sent.");
  }
