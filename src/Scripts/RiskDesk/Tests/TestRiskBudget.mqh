//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestRiskBudget.mqh             |
//| Purpose : tests of Domain/RiskBudget.mqh: V-15, V-16, V-17, V-24 |
//|           and budget edge cases. Base 10,000 USD, caps 10 %.     |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_RISKBUDGET_MQH
#define RD_TESTS_RISKBUDGET_MQH

#include "..\..\..\Include\RiskDesk\Domain\RiskBudget.mqh"
#include "TestRunner.mqh"
#include "TestFixtures.mqh"

//+------------------------------------------------------------------+
void TestV15(CTestRunner &t)
  {
   t.Begin("V-15 Risk budget");
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SPosition pos[];
   SOrder ord[];
   TfAddPosition(pos, 1, "EURUSD", SIDE_BUY, 0.5, 1.10000, 1.09400, cfg.magic, 300.0);
   TfAddPosition(pos, 2, "XAUUSD", SIDE_SELL, 0.1, 4000.00, 4045.00, cfg.magic, 450.0);
   TfAddPosition(pos, 3, "USDJPY", SIDE_BUY, 0.2, 150.000, 150.100, cfg.magic, -20.0);
   SBudgetResult bud;
   SResult r;
   bool ok = CRiskBudget::OpenRisk(pos, ord, cfg, bud, r);
   ASSERT_TRUE("open risk known", ok);
   ASSERT_NEAR("open 750 (break-even counts 0)", bud.openRisk, 750.0, 1e-9);
   ASSERT_EQ_INT("3 positions counted", bud.positions, 3);
   double open = bud.openRisk;
   ok = CRiskBudget::Check(acc, cfg, open, 0.0, 200.0, 200.0, bud, r);
   ASSERT_TRUE("new 200 allowed", ok);
   ASSERT_NEAR("open 7.5 %", bud.openPct, 7.5, 1e-9);
   ASSERT_NEAR("total 9.5 %", bud.totalPct, 9.5, 1e-9);
   ok = CRiskBudget::Check(acc, cfg, open, 0.0, 300.0, 300.0, bud, r);
   ASSERT_FALSE("new 300 refused", ok);
   ASSERT_NEAR("total 10.5 %", bud.totalPct, 10.5, 1e-9);
   ASSERT_CONTAINS("message with the numbers (T-11)", r.message, "open 7.50 % + 3.00 % > 10 % cap");
  }

//+------------------------------------------------------------------+
void TestV16(CTestRunner &t)
  {
   t.Begin("V-16 Risk budget equality");
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SBudgetResult bud;
   SResult r;
   bool ok = CRiskBudget::Check(acc, cfg, 800.0, 0.0, 200.0, 200.0, bud, r);
   ASSERT_TRUE("exactly 10 % allowed", ok);
   ASSERT_NEAR("total 10 %", bud.totalPct, 10.0, 1e-9);
   ok = CRiskBudget::Check(acc, cfg, 800.0, 0.0, 200.01, 200.01, bud, r);
   ASSERT_FALSE("one cent above refused", ok);
  }

//+------------------------------------------------------------------+
void TestV17(CTestRunner &t)
  {
   t.Begin("V-17 No-SL tool position");
   SPlanSettings cfg;
   cfg.Defaults();
   SPosition pos[];
   SOrder ord[];
   TfAddPosition(pos, 123, "XAUUSD", SIDE_BUY, 0.1, 4000.00, 0.0, cfg.magic, 0.0);
   SBudgetResult bud;
   SResult r;
   ASSERT_FALSE("refused", CRiskBudget::OpenRisk(pos, ord, cfg, bud, r));
   ASSERT_CONTAINS("ticket and symbol", r.message, "Position #123 (XAUUSD) has no SL");
   ASSERT_CONTAINS("consequence", r.message, "total risk cannot be computed");
  }

//+------------------------------------------------------------------+
void TestV24(CTestRunner &t)
  {
   t.Begin("V-24 Moving a pending order");
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SPosition pos[];
   SOrder ord[];
   TfAddPosition(pos, 10, "EURUSD", SIDE_BUY, 0.5, 1.10000, 1.09000, cfg.magic, 500.0);
   TfAddOrder(ord, 11, "EURUSD", SIDE_BUY, KIND_STOP, 1.10500, 1.10200, cfg.magic, 300.0);
   SBudgetResult bud;
   SResult r;
   bool ok = CRiskBudget::OpenRisk(pos, ord, cfg, bud, r);
   ASSERT_TRUE("open risk known", ok);
   ASSERT_NEAR("open 800 incl. the order's 300", bud.openRisk, 800.0, 1e-9);
   ASSERT_EQ_INT("1 order counted", bud.orders, 1);
   ok = CRiskBudget::Check(acc, cfg, 800.0, 300.0, 450.0, 450.0, bud, r);
   ASSERT_TRUE("new risk 450 allowed", ok);
   ASSERT_NEAR("950 = 9.5 % (old 300 replaced)", bud.totalPct, 9.5, 1e-9);
   ok = CRiskBudget::Check(acc, cfg, 800.0, 300.0, 600.0, 600.0, bud, r);
   ASSERT_FALSE("new risk 600 refused", ok);
   ASSERT_NEAR("1,100 = 11.0 %", bud.totalPct, 11.0, 1e-9);
   ASSERT_CONTAINS("replacement shown", r.message, "open 8.00 % - 3.00 % + 6.00 % > 10 % cap");
   ASSERT_CONTAINS("total money", r.message, "$1,100.00");
  }

//+------------------------------------------------------------------+
void TestToolTradesOnly(CTestRunner &t)
  {
   t.Begin("Open risk counts tool trades only (F-16 AC3)");
   SPlanSettings cfg;
   cfg.Defaults();
   SPosition pos[];
   SOrder ord[];
   TfAddPosition(pos, 1, "EURUSD", SIDE_BUY, 1.0, 1.10000, 0.0, 0, 999.0);         // manual, no SL
   TfAddPosition(pos, 2, "EURUSD", SIDE_BUY, 1.0, 1.10000, 1.09500, 1, 500.0);     // other EA
   TfAddPosition(pos, 3, "GBPUSD", SIDE_SELL, 0.2, 1.27000, 1.27500, cfg.magic, 200.0);
   TfAddOrder(ord, 4, "EURUSD", SIDE_BUY, KIND_LIMIT, 1.09000, 1.08900, cfg.magic, 100.0);
   TfAddOrder(ord, 5, "EURUSD", SIDE_SELL, KIND_STOP, 1.09000, 1.09500, 0, 400.0);  // manual pending
   SBudgetResult bud;
   SResult r;
   bool ok = CRiskBudget::OpenRisk(pos, ord, cfg, bud, r);
   ASSERT_TRUE("manual position without SL does not block", ok);
   ASSERT_NEAR("tool position + tool order", bud.openRisk, 300.0, 1e-9);
   ASSERT_EQ_INT("1 position", bud.positions, 1);
   ASSERT_EQ_INT("1 order", bud.orders, 1);
   cfg.includePendingInTotalRisk = false;
   ok = CRiskBudget::OpenRisk(pos, ord, cfg, bud, r);
   ASSERT_NEAR("pending excluded by setting", bud.openRisk, 200.0, 1e-9);
   ASSERT_EQ_INT("0 orders", bud.orders, 0);
  }

//+------------------------------------------------------------------+
void TestPendingWithoutSl(CTestRunner &t)
  {
   t.Begin("Tool pending order without SL (D7)");
   SPlanSettings cfg;
   cfg.Defaults();
   SPosition pos[];
   SOrder ord[];
   TfAddOrder(ord, 77, "EURUSD", SIDE_BUY, KIND_STOP, 1.10500, 0.0, cfg.magic, 0.0);
   SBudgetResult bud;
   SResult r;
   ASSERT_FALSE("blocks while pending counts", CRiskBudget::OpenRisk(pos, ord, cfg, bud, r));
   ASSERT_CONTAINS("message", r.message, "Pending order #77 (EURUSD) has no SL");
   cfg.includePendingInTotalRisk = false;
   ASSERT_TRUE("ignored when pending does not count", CRiskBudget::OpenRisk(pos, ord, cfg, bud, r));
  }

//+------------------------------------------------------------------+
void TestPerTradeCapAndBase(CTestRunner &t)
  {
   t.Begin("Per-trade cap and risk base");
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SBudgetResult bud;
   SResult r;
   ASSERT_FALSE("12 % refused", CRiskBudget::Check(acc, cfg, 0.0, 0.0, 1200.0, 1200.0, bud, r));
   ASSERT_CONTAINS("per-trade message", r.message, "Risk 12.00 % ($1,200.00) is above the 10 % per-trade cap");
   ASSERT_TRUE("10 % per trade allowed", CRiskBudget::CheckPerTrade(acc, cfg, 1000.0, bud, r));
   cfg.riskBase = RISKBASE_EQUITY;
   acc.equity = 8000.0;
   ASSERT_FALSE("equity base: 1,000 = 12.5 %", CRiskBudget::Check(acc, cfg, 0.0, 0.0, 1000.0, 1000.0, bud, r));
   ASSERT_NEAR("equity base used", bud.base, 8000.0, 1e-9);
   TfAccount(acc, "USD", 0.0);
   cfg.riskBase = RISKBASE_BALANCE;
   ASSERT_FALSE("balance 0 refused", CRiskBudget::Check(acc, cfg, 0.0, 0.0, 10.0, 10.0, bud, r));
   ASSERT_CONTAINS("balance 0 message", r.message, "Risk base is $0.00");
  }

//+------------------------------------------------------------------+
void TestReadout(CTestRunner &t)
  {
   t.Begin("Open-risk readout (F-29)");
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   ESeverity sev = SEV_ERROR;
   ASSERT_EQ_STR("3.20 %", CRiskBudget::Readout(acc, cfg, 320.0, sev), "Open risk 3.20 % / 10 %");
   ASSERT_EQ_INT("normal colour", sev, SEV_OK);
   CRiskBudget::Readout(acc, cfg, 750.0, sev);
   ASSERT_EQ_INT("exactly 75 % of the cap: normal", sev, SEV_OK);
   CRiskBudget::Readout(acc, cfg, 800.0, sev);
   ASSERT_EQ_INT("above 75 % of the cap: amber", sev, SEV_WARN);
  }

//+------------------------------------------------------------------+
void RunRiskBudgetTests(CTestRunner &t)
  {
   TestV15(t);
   TestV16(t);
   TestV17(t);
   TestV24(t);
   TestToolTradesOnly(t);
   TestPendingWithoutSl(t);
   TestPerTradeCapAndBase(t);
   TestReadout(t);
  }

#endif // RD_TESTS_RISKBUDGET_MQH
