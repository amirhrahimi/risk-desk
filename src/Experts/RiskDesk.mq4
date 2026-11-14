// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk.mq4 - Expert Advisor entry file (MT4)                   |
//| Forwards the five event handlers to CApp (02-architecture 4).    |
//| Version, copyright and link come from Include/RiskDesk/Build.mqh |
//| (ADR-015, ADR-029); the version is also logged on init.          |
//+------------------------------------------------------------------+
#property strict

#include "..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property link        RD_LINK
#property version     RD_VERSION_PROP
// The description lines together (line feeds included) must stay within 511 characters,
// or MetaEditor raises warning 47 "description is too long". Keep RiskDesk.mq5 identical.
#property description "Risk Desk: risk-based position sizing and trade management panel for MetaTrader 4 and 5."
#property description "Set a risk % and drag the stop-loss line: the lot is sized from your broker's symbol data,"
#property description "rounded down, and refused if even the minimum lot would risk more than you set."
#property description "One-click market and pending orders, plus Risk Free, Half Close, Chart Close and Full Close."
#property description "Every click ends with a status message saying what happened and why."
#property description "A manual trading tool: it never trades on its own. Test it on a demo account first."

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
