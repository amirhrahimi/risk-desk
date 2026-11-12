//+------------------------------------------------------------------+
//| RiskDeskTests.mq5 - unit test script entry file (MT5)            |
//| Includes ONLY Domain/* (08-testing section 2): results must be   |
//| identical on every account.                                      |
//| Status : stub. The V-01..V-24 vectors arrive in phase P1.        |
//+------------------------------------------------------------------+
#include "..\..\Include\RiskDesk\Build.mqh"

#property copyright   RD_COPYRIGHT
#property description "RiskDesk unit tests (Domain layer). Phase P0 stub: no tests yet."

#include "..\..\Include\RiskDesk\Domain\Types.mqh"
#include "..\..\Include\RiskDesk\Domain\PriceMath.mqh"
#include "..\..\Include\RiskDesk\Domain\RiskMath.mqh"
#include "..\..\Include\RiskDesk\Domain\Validators.mqh"
#include "..\..\Include\RiskDesk\Domain\Planner.mqh"
#include "..\..\Include\RiskDesk\Domain\RiskBudget.mqh"

void OnStart()
  {
   Print("RiskDeskTests ", RD_VERSION, ": 0 passed, 0 failed (the test vectors arrive in phase P1)");
  }
