// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDeskTests.mq4 - unit test script entry file (MT4)            |
//| Runs every Domain test (Tests/TestSuite.mqh). Includes ONLY      |
//| Domain/* (08-testing section 2): results must be identical on    |
//| every account. Output: one Experts line per failure, then        |
//| "RiskDeskTests: N passed, M failed" (also as an Alert), and the  |
//| full report in MQL4/Files/RiskDesk/tests_MT4.txt.                |
//+------------------------------------------------------------------+
#property strict

#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property link        RD_LINK
#property version     RD_VERSION_PROP
#property description "RiskDesk unit tests (Domain layer: vectors V-01..V-24 and edge cases)."

#include "Tests\TestSuite.mqh"

void OnStart()
  {
   RunRiskDeskTests("MT4", "MQL4");
  }
