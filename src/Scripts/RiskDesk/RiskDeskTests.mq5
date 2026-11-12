//+------------------------------------------------------------------+
//| RiskDeskTests.mq5 - unit test script entry file (MT5)            |
//| Runs every Domain test (Tests/TestSuite.mqh). Includes ONLY      |
//| Domain/* (08-testing section 2): results must be identical on    |
//| every account. Output: one Experts line per failure, then        |
//| "RiskDeskTests: N passed, M failed" (also as an Alert), and the  |
//| full report in MQL5/Files/RiskDesk/tests_MT5.txt.                |
//+------------------------------------------------------------------+
#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property description "RiskDesk unit tests (Domain layer: vectors V-01..V-24 and edge cases)."

#include "Tests\TestSuite.mqh"

void OnStart()
  {
   RunRiskDeskTests("MT5", "MQL5");
  }
