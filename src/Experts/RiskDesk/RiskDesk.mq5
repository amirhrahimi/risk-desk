//+------------------------------------------------------------------+
//| RiskDesk.mq5 - Expert Advisor entry file (MT5)                   |
//| Forwards the five event handlers to CApp (02-architecture 4).    |
//| '#property version' is set from 1.0.0 on (ADR-015); the version  |
//| is RD_VERSION in Include/RiskDesk/Build.mqh and is logged on init.|
//+------------------------------------------------------------------+
#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property description "Risk-based trade panel for MetaTrader 4 and 5."
#property description "Phase P0 shell: logs version, account and symbol spec only."

#include "..\..\Include\RiskDesk\App\App.mqh"

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
