//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestSuite.mqh                  |
//| Purpose : runs every Domain unit test (08-testing section 2).    |
//|           Shared by RiskDeskTests.mq4 and .mq5, which include    |
//|           ONLY Domain/* through these files: no terminal state   |
//|           is read, so results are identical on every account.    |
//|                                                                  |
//| Test vectors (04-risk-engine section 12):                        |
//|   PriceMath  V-08 V-10 V-22                                      |
//|   RiskMath   V-01..V-07 V-09 V-11 V-18                           |
//|   Validators V-12 V-13 V-14 V-21                                 |
//|   RiskBudget V-15 V-16 V-17 V-24                                 |
//|   Planner    V-19 V-20 V-23                                      |
//| plus edge cases per module. Add one test per Domain bug fixed.   |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_SUITE_MQH
#define RD_TESTS_SUITE_MQH

#include "TestRunner.mqh"
#include "TestFixtures.mqh"
#include "TestPriceMath.mqh"
#include "TestRiskMath.mqh"
#include "TestValidators.mqh"
#include "TestRiskBudget.mqh"
#include "TestPlanner.mqh"

// Returns the number of failed checks.
int RunRiskDeskTests(const string platform, const string mqlDir)
  {
   CTestRunner t;
   t.Start(platform, mqlDir);
   RunPriceMathTests(t);
   RunRiskMathTests(t);
   RunValidatorTests(t);
   RunRiskBudgetTests(t);
   RunPlannerTests(t);
   t.Finish();
   return t.Failed();
  }

#endif // RD_TESTS_SUITE_MQH
