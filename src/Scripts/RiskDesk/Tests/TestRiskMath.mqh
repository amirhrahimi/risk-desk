//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestRiskMath.mqh               |
//| Purpose : tests of Domain/RiskMath.mqh: V-01..V-07, V-09, V-11,  |
//|           V-18 and sizing edge cases.                            |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_RISKMATH_MQH
#define RD_TESTS_RISKMATH_MQH

#include "..\..\..\Include\RiskDesk\Domain\RiskMath.mqh"
#include "TestRunner.mqh"
#include "TestFixtures.mqh"

//+------------------------------------------------------------------+
void TestV01(CTestRunner &t)
  {
   t.Begin("V-01 FX, USD account");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   ASSERT_NEAR("ticks", RdTicksBetween(s, 1.10000, 1.09800), 200.0, 1e-9);
   double loss = CRiskMath::LossPerLotByTicks(s, 1.10000, 1.09800);
   ASSERT_NEAR("lossPerLot", loss, 200.0, 1e-9);
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, loss, s, acc, cfg, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("raw", lot.rawLots, 0.5, 1e-9);
   ASSERT_NEAR("lots", lot.lots, 0.50, 1e-12);
   ASSERT_NEAR("risk", lot.actualRisk, 100.0, 1e-9);
   ASSERT_NEAR("risk %", lot.actualPct, 1.0, 1e-9);
   ASSERT_EQ_INT("no warning", r.sev, SEV_OK);
  }

//+------------------------------------------------------------------+
void TestV02(CTestRunner &t)
  {
   t.Begin("V-02 Commission");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   cfg.commissionPerLot = 7.0;
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, CRiskMath::LossPerLotByTicks(s, 1.10000, 1.09800), s, acc, cfg, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("lossPerLotAll", lot.lossPerLotAll, 207.0, 1e-9);
   ASSERT_NEAR("raw", lot.rawLots, 0.48309, 1e-5);
   ASSERT_NEAR("lots", lot.lots, 0.48, 1e-12);
   ASSERT_NEAR("risk", lot.actualRisk, 99.36, 1e-9);
  }

//+------------------------------------------------------------------+
void TestV03(CTestRunner &t)
  {
   t.Begin("V-03 Tick value not round");
   SSymbolSpec s;
   TfSpec(s, "USDJPY", 3, 0.001, 0.001, 0.66667, 0.01, 0.01, 100.0);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   ASSERT_NEAR("ticks", RdTicksBetween(s, 150.000, 149.500), 500.0, 1e-9);
   double loss = CRiskMath::LossPerLotByTicks(s, 150.000, 149.500);
   ASSERT_NEAR("lossPerLot", loss, 333.335, 1e-9);
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, loss, s, acc, cfg, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("raw", lot.rawLots, 0.2999985, 1e-7);
   ASSERT_NEAR("lots", lot.lots, 0.29, 1e-12);
   ASSERT_NEAR("risk", lot.actualRisk, 96.67, 0.005);
  }

//+------------------------------------------------------------------+
void TestV04(CTestRunner &t)
  {
   t.Begin("V-04 EUR account, gold");
   SSymbolSpec s;
   TfSpec(s, "XAUUSD", 2, 0.01, 0.01, 0.925926, 0.01, 0.01, 100.0);
   SAccountSpec acc;
   TfAccount(acc, "EUR", 5000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   ASSERT_NEAR("ticks", RdTicksBetween(s, 4000.00, 3990.00), 1000.0, 1e-9);
   double loss = CRiskMath::LossPerLotByTicks(s, 4000.00, 3990.00);
   ASSERT_NEAR("lossPerLot", loss, 925.93, 0.005);
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(0.5, loss, s, acc, cfg, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("raw", lot.rawLots, 0.0270, 0.0001);
   ASSERT_NEAR("lots", lot.lots, 0.02, 1e-12);
   ASSERT_NEAR("risk EUR", lot.actualRisk, 18.52, 0.005);
   ASSERT_NEAR("risk %", lot.actualPct, 0.37, 0.005);
  }

//+------------------------------------------------------------------+
void TestV05(CTestRunner &t)
  {
   t.Begin("V-05 Whole-contract CFD");
   SSymbolSpec s;
   TfSpec(s, "DE40", 2, 0.01, 0.01, 0.01, 1.0, 1.0, 100.0);
   SAccountSpec acc;
   TfAccount(acc, "EUR", 5000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   double loss = CRiskMath::LossPerLotByTicks(s, 15000.00, 14960.00);
   ASSERT_NEAR("lossPerLot", loss, 40.0, 1e-9);
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, loss, s, acc, cfg, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("raw", lot.rawLots, 1.25, 1e-9);
   ASSERT_NEAR("lots", lot.lots, 1.0, 1e-12);
   ASSERT_NEAR("risk", lot.actualRisk, 40.0, 1e-9);
   ASSERT_NEAR("risk %", lot.actualPct, 0.80, 1e-9);
  }

//+------------------------------------------------------------------+
void TestV06(CTestRunner &t)
  {
   t.Begin("V-06 Below minimum");
   SSymbolSpec s;
   TfSpec(s, "DE40", 2, 0.01, 0.01, 0.01, 1.0, 1.0, 100.0);
   SAccountSpec acc;
   TfAccount(acc, "EUR", 5000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   double loss = CRiskMath::LossPerLotByTicks(s, 15000.00, 14940.00);
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, loss, s, acc, cfg, lot, r);
   ASSERT_FALSE("refused", ok);
   ASSERT_NEAR("raw", lot.rawLots, 0.8333, 0.0001);
   ASSERT_TRUE("below min flagged", lot.belowMin);
   ASSERT_NEAR("lots", lot.lots, 0.0, 1e-12);
   ASSERT_EQ_INT("red", r.sev, SEV_ERROR);
   ASSERT_CONTAINS("names the min lot", r.message, "Min lot 1 would risk");
   ASSERT_CONTAINS("money of the min lot", r.message, RdCurrencySymbol("EUR") + "60.00");
   ASSERT_CONTAINS("percent of the min lot", r.message, "(1.20 %)");
   ASSERT_CONTAINS("the user's risk", r.message, "above your 1.00 %");
  }

//+------------------------------------------------------------------+
void TestV07(CTestRunner &t)
  {
   t.Begin("V-07 Min not on the 0.01 grid start");
   double lots = 0.0;
   bool ok = RdFloorVolume(0.537, 0.5, 0.01, lots);
   ASSERT_TRUE("0.537 tradable", ok);
   ASSERT_NEAR("0.537 -> 0.53", lots, 0.53, 1e-12);
   ASSERT_FALSE("0.42 refused", RdFloorVolume(0.42, 0.5, 0.01, lots));
   SSymbolSpec s;
   TfSpec(s, "XAGUSD", 3, 0.001, 0.001, 1.0, 0.5, 0.01, 100.0);
   SAccountSpec acc;
   TfAccount(acc, "USD", 5370.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SLotResult lot;
   SResult r;
   ok = CRiskMath::LotsFromRisk(1.0, 100.0, s, acc, cfg, lot, r);
   ASSERT_TRUE("raw 0.537 sized", ok);
   ASSERT_NEAR("raw 0.537 -> 0.53 lots", lot.lots, 0.53, 1e-12);
   TfAccount(acc, "USD", 4200.0);
   ok = CRiskMath::LotsFromRisk(1.0, 100.0, s, acc, cfg, lot, r);
   ASSERT_FALSE("raw 0.42 refused", ok);
   ASSERT_CONTAINS("names min lot 0.50", r.message, "Min lot 0.50");
  }

//+------------------------------------------------------------------+
void TestV09(CTestRunner &t)
  {
   t.Begin("V-09 Above max");
   SSymbolSpec s;
   TfSpec(s, "EURUSD", 5, 0.00001, 0.00001, 1.0, 0.01, 0.01, 50.0);
   SAccountSpec acc;
   TfAccount(acc, "USD", 12000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, 1.0, s, acc, cfg, lot, r);
   ASSERT_TRUE("sent", ok);
   ASSERT_NEAR("raw", lot.rawLots, 120.0, 1e-9);
   ASSERT_NEAR("lots capped", lot.lots, 50.0, 1e-12);
   ASSERT_TRUE("capped flagged", lot.capped);
   ASSERT_EQ_INT("amber", r.sev, SEV_WARN);
   ASSERT_CONTAINS("warning", r.message, "Capped at max lot 50");
   ASSERT_NEAR("real risk", lot.actualRisk, 50.0, 1e-9);
  }

//+------------------------------------------------------------------+
void TestV11(CTestRunner &t)
  {
   t.Begin("V-11 RR TP");
   SSymbolSpec s;
   TfFx(s);
   double tp = 0.0;
   SResult r;
   bool ok = CRiskMath::TpFromRR(SIDE_BUY, 1.10000, 1.09800, 2.0, s, tp, r);
   ASSERT_TRUE("buy computed", ok);
   ASSERT_NEAR("buy RR 2", tp, 1.10400, 1e-12);
   ok = CRiskMath::TpFromRR(SIDE_SELL, 1.10000, 1.10150, 1.5, s, tp, r);
   ASSERT_TRUE("sell computed", ok);
   ASSERT_NEAR("sell RR 1.5", tp, 1.09775, 1e-12);
  }

//+------------------------------------------------------------------+
void TestV18(CTestRunner &t)
  {
   t.Begin("V-18 Partial close");
   SSymbolSpec s;
   TfFx(s);
   SPlanSettings cfg;
   cfg.Defaults();
   SPartialClose pc;
   SResult r;
   bool ok = CRiskMath::PartialClose(0.03, s, cfg, pc, r);
   ASSERT_TRUE("0.03 divisible", ok);
   ASSERT_NEAR("0.03: close", pc.closeVolume, 0.01, 1e-12);
   ASSERT_NEAR("0.03: keep", pc.remainVolume, 0.02, 1e-12);
   ok = CRiskMath::PartialClose(0.05, s, cfg, pc, r);
   ASSERT_TRUE("0.05 divisible", ok);
   ASSERT_NEAR("0.05: close", pc.closeVolume, 0.02, 1e-12);
   ASSERT_NEAR("0.05: keep", pc.remainVolume, 0.03, 1e-12);
   ok = CRiskMath::PartialClose(0.01, s, cfg, pc, r);
   ASSERT_FALSE("0.01 skipped", ok);
   ASSERT_TRUE("0.01 indivisible", pc.indivisible);
   ASSERT_EQ_INT("0.01 skip is amber", r.sev, SEV_WARN);
   ASSERT_CONTAINS("0.01 reason", r.message, "0.01 lot cannot be split at 50 %");
   TfSpec(s, "DE40", 2, 0.01, 0.01, 0.01, 1.0, 1.0, 100.0);
   ok = CRiskMath::PartialClose(1.0, s, cfg, pc, r);
   ASSERT_FALSE("1 (min 1, step 1) skipped", ok);
   ASSERT_TRUE("1 (min 1, step 1) indivisible", pc.indivisible);
  }

//+------------------------------------------------------------------+
void TestMinLotOverRisk(CTestRunner &t)
  {
   t.Begin("Min lot over risk when allowed (04 section 4)");
   SSymbolSpec s;
   TfSpec(s, "DE40", 2, 0.01, 0.01, 0.01, 1.0, 1.0, 100.0);
   SAccountSpec acc;
   TfAccount(acc, "EUR", 5000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   cfg.allowMinLotOverRisk = true;
   SLotResult lot;
   SResult r;
   bool ok = CRiskMath::LotsFromRisk(1.0, 60.0, s, acc, cfg, lot, r);
   ASSERT_TRUE("min lot sent", ok);
   ASSERT_NEAR("lots = min", lot.lots, 1.0, 1e-12);
   ASSERT_TRUE("flagged", lot.usedMinLot);
   ASSERT_EQ_INT("amber", r.sev, SEV_WARN);
   ASSERT_NEAR("real risk %", lot.actualPct, 1.20, 1e-9);
   ASSERT_CONTAINS("says why", r.message, "allowed by settings");
   ok = CRiskMath::LotsFromRisk(1.0, 600.0, s, acc, cfg, lot, r);
   ASSERT_FALSE("min lot above the 10 % cap refused", ok);
   ASSERT_CONTAINS("names the cap", r.message, "above the 10 % per-trade cap");
  }

//+------------------------------------------------------------------+
void TestSizingRefusals(CTestRunner &t)
  {
   t.Begin("Sizing refusals and risk base");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SLotResult lot;
   SResult r;
   ASSERT_FALSE("loss per lot 0", CRiskMath::LotsFromRisk(1.0, 0.0, s, acc, cfg, lot, r));
   ASSERT_CONTAINS("loss per lot 0 message", r.message, "Cannot value a price move on EURUSD");
   ASSERT_FALSE("negative loss per lot", CRiskMath::LotsFromRisk(1.0, -5.0, s, acc, cfg, lot, r));
   ASSERT_FALSE("risk 0 %", CRiskMath::LotsFromRisk(0.0, 200.0, s, acc, cfg, lot, r));
   TfAccount(acc, "USD", 0.0);
   ASSERT_FALSE("balance 0", CRiskMath::LotsFromRisk(1.0, 200.0, s, acc, cfg, lot, r));
   ASSERT_CONTAINS("balance 0 message", r.message, "Risk base is $0.00");
   ASSERT_NEAR("base balance", CRiskMath::RiskBase(RISKBASE_BALANCE, 10000.0, 9500.0), 10000.0, 1e-9);
   ASSERT_NEAR("base equity", CRiskMath::RiskBase(RISKBASE_EQUITY, 10000.0, 9500.0), 9500.0, 1e-9);
   ASSERT_NEAR("base lower (equity)", CRiskMath::RiskBase(RISKBASE_MIN_BAL_EQ, 10000.0, 9500.0), 9500.0, 1e-9);
   ASSERT_NEAR("base lower (balance)", CRiskMath::RiskBase(RISKBASE_MIN_BAL_EQ, 10000.0, 10500.0), 10000.0, 1e-9);
   ASSERT_NEAR("risk money", CRiskMath::RiskMoney(10000.0, 1.5), 150.0, 1e-9);
  }

//+------------------------------------------------------------------+
//| Rule R5 over many valuations and three grids.                    |
//+------------------------------------------------------------------+
void TestRiskNeverExceeded(CTestRunner &t)
  {
   t.Begin("Risk never exceeds the request (sweep, rule R5)");
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   cfg.commissionPerLot = 3.5;
   double mins[]  = {0.01, 1.0, 0.5};
   double steps[] = {0.01, 1.0, 0.01};
   int over = 0;
   int wrongRefusal = 0;
   int count = 0;
   for(int g = 0; g < 3; g++)
     {
      SSymbolSpec s;
      TfSpec(s, "SWEEP", 5, 0.00001, 0.00001, 1.0, mins[g], steps[g], 1000.0);
      for(int i = 0; i < 2000; i++)
        {
         double loss = 3.7 + i * 1.37;
         SLotResult lot;
         SResult r;
         if(CRiskMath::LotsFromRisk(0.75, loss, s, acc, cfg, lot, r))
           {
            count++;
            if(lot.actualRisk > lot.riskMoney + 1e-9)
               over++;
           }
         else
            if(!lot.belowMin)
               wrongRefusal++;
        }
     }
   ASSERT_TRUE("some trades sized", count > 0);
   ASSERT_EQ_INT("actual risk above requested", over, 0);
   ASSERT_EQ_INT("refusals other than below min", wrongRefusal, 0);
  }

//+------------------------------------------------------------------+
void TestTpEdgeCases(CTestRunner &t)
  {
   t.Begin("TP from R/R edge cases");
   SSymbolSpec s;
   TfFx(s);
   double tp = 0.0;
   SResult r;
   ASSERT_FALSE("R/R 0 refused", CRiskMath::TpFromRR(SIDE_BUY, 1.10000, 1.09800, 0.0, s, tp, r));
   ASSERT_FALSE("R/R negative refused", CRiskMath::TpFromRR(SIDE_BUY, 1.10000, 1.09800, -1.0, s, tp, r));
   ASSERT_FALSE("sell TP at zero refused", CRiskMath::TpFromRR(SIDE_SELL, 1.0, 2.0, 1.0, s, tp, r));
   ASSERT_NEAR("refused TP stays 0", tp, 0.0, 1e-12);
   TfSpec(s, "IDX025", 2, 0.01, 0.25, 1.0, 0.01, 0.01, 100.0);
   bool ok = CRiskMath::TpFromRR(SIDE_BUY, 4500.00, 4493.25, 1.3, s, tp, r);
   ASSERT_TRUE("index computed", ok);
   ASSERT_NEAR("tick 0.25: 4508.775 -> 4508.75", tp, 4508.75, 1e-9);
   ASSERT_NEAR("reward ratio 2", CRiskMath::RewardRatio(1.10000, 1.09800, 1.10400), 2.0, 1e-9);
   ASSERT_NEAR("reward ratio without TP", CRiskMath::RewardRatio(1.10000, 1.09800, 0.0), 0.0, 1e-12);
  }

//+------------------------------------------------------------------+
void TestPartialCloseEdgeCases(CTestRunner &t)
  {
   t.Begin("Partial close edge cases (04 section 10)");
   SSymbolSpec s;
   TfSpec(s, "GRID", 5, 0.00001, 0.00001, 1.0, 0.02, 0.01, 100.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SPartialClose pc;
   SResult r;
   cfg.partialClosePct = 70.0;
   ASSERT_FALSE("min 0.02: 0.03 at 70 % leaves 0.01 < min", CRiskMath::PartialClose(0.03, s, cfg, pc, r));
   cfg.partialClosePct = 50.0;
   bool ok = CRiskMath::PartialClose(0.05, s, cfg, pc, r);
   ASSERT_TRUE("min 0.02: 0.05 at 50 %", ok);
   ASSERT_NEAR("min 0.02: close 0.02", pc.closeVolume, 0.02, 1e-12);
   ASSERT_NEAR("min 0.02: keep 0.03", pc.remainVolume, 0.03, 1e-12);
   TfFx(s);
   ok = CRiskMath::PartialClose(0.57, s, cfg, pc, r);
   ASSERT_NEAR("0.57: close 0.28", pc.closeVolume, 0.28, 1e-12);
   ASSERT_NEAR("0.57: keep 0.29", pc.remainVolume, 0.29, 1e-12);
   cfg.partialClosePct = 99.0;
   ok = CRiskMath::PartialClose(1.0, s, cfg, pc, r);
   ASSERT_NEAR("99 % of 1.00: close 0.99", pc.closeVolume, 0.99, 1e-12);
   ASSERT_NEAR("99 % of 1.00: keep 0.01", pc.remainVolume, 0.01, 1e-12);
   cfg.partialClosePct = 50.0;
   cfg.partialIndivisible = INDIV_CLOSE_ALL;
   ok = CRiskMath::PartialClose(0.01, s, cfg, pc, r);
   ASSERT_TRUE("CLOSE_ALL: indivisible position closed", ok);
   ASSERT_TRUE("CLOSE_ALL flagged", pc.closeAll);
   ASSERT_NEAR("CLOSE_ALL: whole volume", pc.closeVolume, 0.01, 1e-12);
   ASSERT_EQ_INT("CLOSE_ALL is amber", r.sev, SEV_WARN);
  }

//+------------------------------------------------------------------+
void TestCostAndTickValue(CTestRunner &t)
  {
   t.Begin("Cost distance, position risk, loss tick value");
   SSymbolSpec s;
   TfFx(s);
   double dist = 0.0;
   bool ok = CRiskMath::CostDistance(3.5, 0.5, s, dist);
   ASSERT_TRUE("3.50 at 0.50 per tick", ok);
   ASSERT_NEAR("= 7 ticks", dist, 0.00007, 1e-12);
   ok = CRiskMath::CostDistance(0.0, 0.5, s, dist);
   ASSERT_TRUE("no cost", ok);
   ASSERT_NEAR("no cost = 0", dist, 0.0, 1e-15);
   ASSERT_FALSE("cost without tick value", CRiskMath::CostDistance(3.5, 0.0, s, dist));
   ASSERT_NEAR("position risk (200 + 7) x 0.5", CRiskMath::PositionRisk(200.0, 7.0, 0.5), 103.5, 1e-9);
   s.tickValueLoss = 1.1;
   ASSERT_NEAR("MT5 loss tick value preferred", CRiskMath::LossPerLotByTicks(s, 1.10000, 1.09800), 220.0, 1e-9);
   s.tickValueLoss = 0.0;
   ASSERT_NEAR("falls back to tick value", CRiskMath::LossPerLotByTicks(s, 1.10000, 1.09800), 200.0, 1e-9);
   s.tickValue = 0.0;
   ASSERT_NEAR("no tick value -> 0 (cannot value)", CRiskMath::LossPerLotByTicks(s, 1.10000, 1.09800), 0.0, 1e-12);
  }

//+------------------------------------------------------------------+
void RunRiskMathTests(CTestRunner &t)
  {
   TestV01(t);
   TestV02(t);
   TestV03(t);
   TestV04(t);
   TestV05(t);
   TestV06(t);
   TestV07(t);
   TestV09(t);
   TestV11(t);
   TestV18(t);
   TestMinLotOverRisk(t);
   TestSizingRefusals(t);
   TestRiskNeverExceeded(t);
   TestTpEdgeCases(t);
   TestPartialCloseEdgeCases(t);
   TestCostAndTickValue(t);
  }

#endif // RD_TESTS_RISKMATH_MQH
