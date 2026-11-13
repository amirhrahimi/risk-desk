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
   ASSERT_NEAR("0.03: close (0.015 is a tie: the larger part stays)", pc.closeVolume, 0.01, 1e-12);
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
//| Q23: the split nearest to the percentage, a tie keeping the      |
//| larger part, never leaving less than the minimum lot.            |
//+------------------------------------------------------------------+
void TestPartialCloseNearest(CTestRunner &t)
  {
   t.Begin("Partial close: nearest split, a tie keeps the larger part (Q23)");
   SSymbolSpec s;
   SPlanSettings cfg;
   cfg.Defaults();
   SPartialClose pc;
   SResult r;
   // the owner's path: Half Close again and again from 2.00 lot (min 0.01, step 0.01)
   TfFx(s);
   double path[] = {1.0, 0.5, 0.25, 0.13, 0.07, 0.04, 0.02, 0.01};
   double v = 2.0;
   for(int i = 0; i < ArraySize(path); i++)
     {
      string id = "halving " + DoubleToString(v, 2);
      bool ok = CRiskMath::PartialClose(v, s, cfg, pc, r);
      ASSERT_TRUE(id + " divisible", ok);
      ASSERT_NEAR(id + " -> keep " + DoubleToString(path[i], 2), pc.remainVolume, path[i], 1e-12);
      ASSERT_NEAR(id + ": close + keep = the position", pc.closeVolume + pc.remainVolume, v, 1e-9);
      v = pc.remainVolume;
     }
   ASSERT_FALSE("halving 0.01: the minimum lot cannot be split", CRiskMath::PartialClose(v, s, cfg, pc, r));
   ASSERT_TRUE("halving 0.01: indivisible", pc.indivisible);

   TfSpec(s, "US30", 2, 0.01, 0.01, 0.01, 1.0, 1.0, 250.0);   // whole lots
   double vols[] = {2.0, 3.0, 4.0, 5.0, 11.0};
   double want[] = {1.0, 1.0, 2.0, 2.0, 5.0};
   for(int i = 0; i < ArraySize(vols); i++)
     {
      bool ok = CRiskMath::PartialClose(vols[i], s, cfg, pc, r);
      string id = "whole lots, 50 % of " + DoubleToString(vols[i], 0);
      ASSERT_TRUE(id + " divisible", ok);
      ASSERT_NEAR(id + ": close", pc.closeVolume, want[i], 1e-12);
      ASSERT_NEAR(id + ": keep", pc.remainVolume, vols[i] - want[i], 1e-12);
     }
   ASSERT_FALSE("whole lots: 1 at 50 % cannot be split", CRiskMath::PartialClose(1.0, s, cfg, pc, r));
   cfg.partialClosePct = 30.0;
   CRiskMath::PartialClose(5.0, s, cfg, pc, r);
   ASSERT_NEAR("30 % of 5: 1.5 is a tie -> close 1, keep 4", pc.closeVolume, 1.0, 1e-12);
   CRiskMath::PartialClose(4.0, s, cfg, pc, r);
   ASSERT_NEAR("30 % of 4: 1.2 -> close 1", pc.closeVolume, 1.0, 1e-12);
   CRiskMath::PartialClose(10.0, s, cfg, pc, r);
   ASSERT_NEAR("30 % of 10: close 3", pc.closeVolume, 3.0, 1e-12);
   ASSERT_FALSE("30 % of 1: nothing is nearest", CRiskMath::PartialClose(1.0, s, cfg, pc, r));
   ASSERT_TRUE("30 % of 1: indivisible", pc.indivisible);
   cfg.partialClosePct = 70.0;
   CRiskMath::PartialClose(3.0, s, cfg, pc, r);
   ASSERT_NEAR("70 % of 3: 2.1 -> close 2, keep 1", pc.closeVolume, 2.0, 1e-12);
   CRiskMath::PartialClose(4.0, s, cfg, pc, r);
   ASSERT_NEAR("70 % of 4: 2.8 -> close 3 (nearest, not the floor), keep 1", pc.closeVolume, 3.0, 1e-12);
   cfg.partialClosePct = 99.0;
   ASSERT_FALSE("99 % of 2: closing all is nearest -> indivisible", CRiskMath::PartialClose(2.0, s, cfg, pc, r));
   bool ok = CRiskMath::PartialClose(200.0, s, cfg, pc, r);
   ASSERT_TRUE("99 % of 200 divisible", ok);
   ASSERT_NEAR("99 % of 200: close 198", pc.closeVolume, 198.0, 1e-12);
   // a minimum above the step (seen: min 1, step 0.01): never a rest below the minimum
   TfSpec(s, "AUSD", 4, 0.0001, 0.0001, 1.0, 1.0, 0.01, 100.0);
   cfg.partialClosePct = 50.0;
   ASSERT_FALSE("min 1 step 0.01: 1.50 at 50 % leaves < min", CRiskMath::PartialClose(1.5, s, cfg, pc, r));
   ok = CRiskMath::PartialClose(2.5, s, cfg, pc, r);
   ASSERT_TRUE("min 1 step 0.01: 2.50 at 50 %", ok);
   ASSERT_NEAR("min 1 step 0.01: 2.50 -> close 1.25", pc.closeVolume, 1.25, 1e-12);
   cfg.partialClosePct = 70.0;
   ok = CRiskMath::PartialClose(2.4, s, cfg, pc, r);
   ASSERT_TRUE("min 1 step 0.01: 2.40 at 70 %", ok);
   ASSERT_NEAR("min 1 step 0.01: 2.40 at 70 % -> close 1.40, keep the minimum", pc.closeVolume, 1.4, 1e-12);
   ASSERT_NEAR("min 1 step 0.01: keep 1.00", pc.remainVolume, 1.0, 1e-12);
   // the volume helper itself
   double lots = 0.0;
   ASSERT_TRUE("nearest 0.015 at step 0.01", RdNearestVolume(0.015, 0.01, 0.01, lots));
   ASSERT_NEAR("nearest 0.015 -> 0.01 (a tie rounds down)", lots, 0.01, 1e-12);
   RdNearestVolume(0.125, 0.01, 0.01, lots);
   ASSERT_NEAR("nearest 0.125 -> 0.12 (a tie rounds down)", lots, 0.12, 1e-12);
   RdNearestVolume(0.0151, 0.01, 0.01, lots);
   ASSERT_NEAR("nearest 0.0151 -> 0.02", lots, 0.02, 1e-12);
   RdNearestVolume(0.0149, 0.01, 0.01, lots);
   ASSERT_NEAR("nearest 0.0149 -> 0.01", lots, 0.01, 1e-12);
   ASSERT_FALSE("nearest 0.005 at min 0.01: a tie -> nothing", RdNearestVolume(0.005, 0.01, 0.01, lots));
   ASSERT_TRUE("nearest 0.006 at min 0.01 -> 0.01", RdNearestVolume(0.006, 0.01, 0.01, lots) && RdVolEq(lots, 0.01));
   ASSERT_FALSE("nearest 0.004 at min 0.01: nothing", RdNearestVolume(0.004, 0.01, 0.01, lots));
   ASSERT_FALSE("nearest of 0", RdNearestVolume(0.0, 0.01, 0.01, lots));
   ASSERT_FALSE("nearest on an invalid grid", RdNearestVolume(1.0, 0.01, 0.0, lots));
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
//| D35: a full close above the maximum volume per request is sent   |
//| in parts; no part leaves a rest below the minimum lot.           |
//+------------------------------------------------------------------+
void TestCloseChunk(CTestRunner &t)
  {
   t.Begin("Close chunks above the max volume (D35)");
   SSymbolSpec s;
   TfSpec(s, "IDX", 1, 0.1, 0.1, 1.0, 1.0, 0.1, 100.0);
   double c = 0.0;
   ASSERT_TRUE("50 fits", CRiskMath::CloseChunk(50.0, s, c));
   ASSERT_NEAR("50 in one request", c, 50.0, 1e-12);
   ASSERT_TRUE("exactly the max fits", CRiskMath::CloseChunk(100.0, s, c));
   ASSERT_NEAR("100 in one request", c, 100.0, 1e-12);
   ASSERT_TRUE("150", CRiskMath::CloseChunk(150.0, s, c));
   ASSERT_NEAR("150: first part 100 (rest 50)", c, 100.0, 1e-12);
   ASSERT_TRUE("100.5", CRiskMath::CloseChunk(100.5, s, c));
   ASSERT_NEAR("100.5: 99.5, so the rest is the min lot 1", c, 99.5, 1e-12);
   ASSERT_TRUE("100.9", CRiskMath::CloseChunk(100.9, s, c));
   ASSERT_NEAR("100.9: 99.9 (rest 1.0)", c, 99.9, 1e-12);
   ASSERT_TRUE("101", CRiskMath::CloseChunk(101.0, s, c));
   ASSERT_NEAR("101: 100 (rest = min lot)", c, 100.0, 1e-12);
   ASSERT_FALSE("0 volume", CRiskMath::CloseChunk(0.0, s, c));
   TfSpec(s, "FX", 5, 0.00001, 0.00001, 1.0, 0.01, 0.01, 50.0);
   ASSERT_TRUE("FX 120.37", CRiskMath::CloseChunk(120.37, s, c));
   ASSERT_NEAR("FX 120.37: 50", c, 50.0, 1e-12);
   ASSERT_TRUE("FX 50.01", CRiskMath::CloseChunk(50.01, s, c));
   ASSERT_NEAR("FX 50.01: 50 (rest = min lot 0.01)", c, 50.0, 1e-12);
   s.volMax = 0.0;
   ASSERT_TRUE("no max reported", CRiskMath::CloseChunk(500.0, s, c));
   ASSERT_NEAR("no max: whole volume", c, 500.0, 1e-12);
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
   TestPartialCloseNearest(t);
   TestCostAndTickValue(t);
   TestCloseChunk(t);
  }

#endif // RD_TESTS_RISKMATH_MQH
