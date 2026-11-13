// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk.mq5 - Expert Advisor entry file (MT5)                   |
//| Forwards the five event handlers to CApp (02-architecture 4).    |
//| Version, copyright and link come from Include/RiskDesk/Build.mqh |
//| (ADR-015, ADR-029); the version is also logged on init.          |
//+------------------------------------------------------------------+
#include "..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property link        RD_LINK
#property version     RD_VERSION_PROP
#property description "Risk Desk: risk-based position sizing and trade management panel for MetaTrader 4 and 5."
#property description "A manual trading tool: it acts only when you click. Test it on a demo account first."

#include "..\Include\RiskDesk\App\App.mqh"

CApp g_app;

int OnInit()
  {
   return g_app.Init();
  }

void OnDeinit(const int reason)
  {
   g_app.Deinit(reason);
  }

void OnTick()
  {
   g_app.Tick();
  }

void OnTimer()
  {
   g_app.Timer();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   g_app.ChartEvent(id, lparam, dparam, sparam);
  }
