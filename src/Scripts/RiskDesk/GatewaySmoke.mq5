// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| GatewaySmoke.mq5 - gateway smoke test script entry file (MT5)    |
//| Places, modifies, closes and deletes REAL orders on the chart    |
//| symbol of a DEMO account only (rule R13), with the smallest      |
//| volume and every trade cleaned up at the end. Shared body:       |
//| GatewaySmokeCore.mqh. Report: MQL5\Files\RiskDesk\smoke_*.txt.   |
//+------------------------------------------------------------------+
#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property link        RD_LINK
#property version     RD_VERSION_PROP
#property description "RiskDesk gateway smoke test: real orders on DEMO accounts only, minimum volume,"
#property description "everything closed/deleted at the end. Writes MQL5\\Files\\RiskDesk\\smoke_*.txt."
#property script_show_inputs

#include "GatewaySmokeCore.mqh"

void OnStart()
  {
   // Started from a startup configuration, the script can run before the
   // login completes: wait for the account before the R13 decision.
   int waited = 0;
   CAccountSpec::WaitReady(15000, waited);
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
     {
      Alert("GatewaySmoke runs on demo accounts only (rule R13). Aborted, nothing was sent.");
      return;
     }
   SmokeRun();
  }
