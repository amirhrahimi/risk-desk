// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestPriceMath.mqh              |
//| Purpose : tests of Domain/PriceMath.mqh and Domain/Format.mqh:   |
//|           V-08, V-10, V-22 and grid/format edge cases.           |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_PRICEMATH_MQH
#define RD_TESTS_PRICEMATH_MQH

#include "..\..\..\Include\RiskDesk\Domain\PriceMath.mqh"
#include "..\..\..\Include\RiskDesk\Domain\Format.mqh"
#include "TestRunner.mqh"
#include "TestFixtures.mqh"

//+------------------------------------------------------------------+
void TestV08(CTestRunner &t)
  {
   t.Begin("V-08 Float floor");
   double lots = 0.0;
   bool ok = RdFloorVolume(0.57, 0.01, 0.01, lots);
   ASSERT_TRUE("0.57 is tradable", ok);
   ASSERT_NEAR("FloorVolume(0.57) = 0.57, not 0.56", lots, 0.57, 1e-9);
  }

//+------------------------------------------------------------------+
void TestV10(CTestRunner &t)
  {
   t.Begin("V-10 Price normalization");
   SSymbolSpec s;
   TfSpec(s, "IDX025", 2, 0.01, 0.25, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("tick 0.25: 4501.13 -> 4501.25", RdNormalizePrice(s, 4501.13), 4501.25, 1e-9);
   TfSpec(s, "IDX05", 2, 0.01, 0.5, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("tick 0.5: 24000.74 -> 24000.50", RdNormalizePrice(s, 24000.74), 24000.50, 1e-9);
   TfSpec(s, "JPY", 3, 0.001, 0.001, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("tick 0.001: 150.1234 -> 150.123", RdNormalizePrice(s, 150.1234), 150.123, 1e-9);
  }

//+------------------------------------------------------------------+
void TestV22(CTestRunner &t)
  {
   t.Begin("V-22 Volume digits");
   ASSERT_EQ_INT("step 1", RdVolumeDigits(1.0), 0);
   ASSERT_EQ_INT("step 0.1", RdVolumeDigits(0.1), 1);
   ASSERT_EQ_INT("step 0.01", RdVolumeDigits(0.01), 2);
   ASSERT_EQ_INT("step 0.001", RdVolumeDigits(0.001), 3);
   ASSERT_EQ_INT("step 0.5", RdVolumeDigits(0.5), 1);
   ASSERT_EQ_INT("step 0.25", RdVolumeDigits(0.25), 2);
   ASSERT_EQ_INT("step 0 (invalid)", RdVolumeDigits(0.0), 0);
   ASSERT_EQ_INT("lot digits min 0.015 step 0.01", RdLotDigits(0.015, 0.01), 3);
  }

//+------------------------------------------------------------------+
void TestFloorVolumeGrids(CTestRunner &t)
  {
   t.Begin("FloorVolume on broker grids (BC-04)");
   double lots = 0.0;
   bool ok = RdFloorVolume(2.37, 1.0, 0.1, lots);
   ASSERT_TRUE("min 1 step 0.1: 2.37 tradable", ok);
   ASSERT_NEAR("min 1 step 0.1: 2.37 -> 2.3", lots, 2.3, 1e-9);
   ASSERT_FALSE("min 1 step 0.1: 0.99 refused", RdFloorVolume(0.99, 1.0, 0.1, lots));
   ok = RdFloorVolume(15.9, 10.0, 1.0, lots);
   ASSERT_NEAR("min 10 step 1: 15.9 -> 15", lots, 15.0, 1e-9);
   ASSERT_FALSE("min 10 step 1: 9.99 refused", RdFloorVolume(9.99, 10.0, 1.0, lots));
   ok = RdFloorVolume(0.5, 0.5, 0.01, lots);
   ASSERT_NEAR("min 0.5 step 0.01: 0.5 -> 0.5", lots, 0.5, 1e-9);
   ASSERT_FALSE("min 0.5 step 0.01: 0.4999 refused", RdFloorVolume(0.4999, 0.5, 0.01, lots));
   ok = RdFloorVolume(1234.5678, 0.01, 0.01, lots);
   ASSERT_NEAR("1234.5678 -> 1234.56", lots, 1234.56, 1e-9);
   ok = RdFloorVolume(0.0019999, 0.001, 0.001, lots);
   ASSERT_NEAR("step 0.001: 0.0019999 -> 0.001", lots, 0.001, 1e-12);
   ok = RdFloorVolume(0.01, 0.01, 0.01, lots);
   ASSERT_NEAR("exactly the min lot", lots, 0.01, 1e-12);
   ASSERT_FALSE("0.0099 below min refused", RdFloorVolume(0.0099, 0.01, 0.01, lots));
   ok = RdFloorVolume(0.4999, 0.01, 0.01, lots);
   ASSERT_NEAR("never rounds up: 0.4999 -> 0.49", lots, 0.49, 1e-9);
   ok = RdFloorVolume(0.1 + 0.2, 0.01, 0.01, lots);
   ASSERT_NEAR("0.1 + 0.2 (float noise above) -> 0.30", lots, 0.30, 1e-9);
   ok = RdFloorVolume(0.7 - 0.1, 0.01, 0.01, lots);
   ASSERT_NEAR("0.7 - 0.1 (float noise below) -> 0.60", lots, 0.60, 1e-9);
   ASSERT_FALSE("step 0 refused", RdFloorVolume(1.0, 0.01, 0.0, lots));
   SSymbolSpec s;
   TfSpec(s, "GRID", 2, 0.01, 0.01, 1.0, 0.5, 0.01, 100.0);
   ok = RdFloorVolume(s, 0.537, lots);
   ASSERT_NEAR("spec overload: min 0.5 step 0.01, 0.537 -> 0.53", lots, 0.53, 1e-9);
  }

//+------------------------------------------------------------------+
//| Sweeps: FloorVolume keeps every grid value, never rounds up and  |
//| never loses a full step.                                         |
//+------------------------------------------------------------------+
void TestFloorVolumeSweep(CTestRunner &t)
  {
   t.Begin("FloorVolume sweeps");
   double steps[] = {0.01, 0.1, 1.0, 0.001, 0.5};
   double mins[]  = {0.01, 1.0, 1.0, 0.001, 0.5};
   int kept = 0;
   int up = 0;
   int lost = 0;
   for(int g = 0; g < 5; g++)
     {
      int digits = RdLotDigits(mins[g], steps[g]);
      for(int k = 0; k < 3000; k++)
        {
         double v = NormalizeDouble(mins[g] + k * steps[g], digits);
         double lots = 0.0;
         if(!RdFloorVolume(v, mins[g], steps[g], lots) || !RdVolEq(lots, v))
            kept++;
         double raw = v + steps[g] * 0.37;
         if(RdFloorVolume(raw, mins[g], steps[g], lots))
           {
            if(lots > raw + 1e-9)
               up++;
            if(raw - lots >= steps[g] - 1e-9)
               lost++;
           }
        }
     }
   ASSERT_EQ_INT("grid values kept exactly", kept, 0);
   ASSERT_EQ_INT("results above raw (rounded up)", up, 0);
   ASSERT_EQ_INT("results a full step below raw", lost, 0);
  }

//+------------------------------------------------------------------+
void TestDirectionalRounding(CTestRunner &t)
  {
   t.Begin("Directional price rounding");
   SSymbolSpec s;
   TfFx(s);
   ASSERT_NEAR("up 1.100121 -> 1.10013", RdRoundPriceUp(s, 1.100121), 1.10013, 1e-12);
   ASSERT_NEAR("down 1.100121 -> 1.10012", RdRoundPriceDown(s, 1.100121), 1.10012, 1e-12);
   ASSERT_NEAR("up keeps a grid price", RdRoundPriceUp(s, 1.10012), 1.10012, 1e-12);
   ASSERT_NEAR("down keeps a grid price", RdRoundPriceDown(s, 1.10012), 1.10012, 1e-12);
   ASSERT_NEAR("up of a sum with float noise", RdRoundPriceUp(s, 1.10000 + 0.00012 + 0.00007), 1.10019, 1e-12);
   ASSERT_NEAR("down within the 1e-8 tick epsilon", RdRoundPriceDown(s, 1.10019 - 1e-14), 1.10019, 1e-12);
   ASSERT_NEAR("down beyond the epsilon", RdRoundPriceDown(s, 1.10019 - 1e-12), 1.10018, 1e-12);
   TfSpec(s, "IDX025", 2, 0.01, 0.25, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("tick 0.25: up 4501.13 -> 4501.25", RdRoundPriceUp(s, 4501.13), 4501.25, 1e-9);
   ASSERT_NEAR("tick 0.25: down 4501.13 -> 4501.00", RdRoundPriceDown(s, 4501.13), 4501.00, 1e-9);
   ASSERT_NEAR("tick 0.25: normalize half tick 4501.125 -> 4501.25", RdNormalizePrice(s, 4501.125), 4501.25, 1e-9);
   TfSpec(s, "NOTICK", 2, 0.01, 0.0, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("tick size 0 falls back to the point", RdTick(s), 0.01, 1e-12);
   ASSERT_NEAR("tick size 0: normalize 1.234 -> 1.23", RdNormalizePrice(s, 1.234), 1.23, 1e-12);
  }

//+------------------------------------------------------------------+
void TestPriceComparisons(CTestRunner &t)
  {
   t.Begin("Price comparisons (half-tick tolerance)");
   SSymbolSpec s;
   TfFx(s);
   ASSERT_TRUE("Eq within half a tick", RdPriceEq(s, 1.10000, 1.100004));
   ASSERT_FALSE("Eq one tick apart", RdPriceEq(s, 1.10000, 1.10001));
   ASSERT_TRUE("Lt one tick below", RdPriceLt(s, 1.10000, 1.10001));
   ASSERT_FALSE("Lt within half a tick", RdPriceLt(s, 1.10000, 1.100004));
   ASSERT_TRUE("Gt one tick above", RdPriceGt(s, 1.10001, 1.10000));
   ASSERT_FALSE("Gt equal", RdPriceGt(s, 1.10000, 1.10000));
   ASSERT_TRUE("Le equal-ish", RdPriceLe(s, 1.100004, 1.10000));
   ASSERT_TRUE("Ge equal-ish", RdPriceGe(s, 1.10000, 1.100004));
   ASSERT_FALSE("Ge one tick below", RdPriceGe(s, 1.09999, 1.10000));
   TfSpec(s, "CENTS", 2, 0.01, 0.01, 1.0, 0.01, 0.01, 100.0);
   ASSERT_TRUE("0.1 + 0.2 equals 0.3 on a 0.01 grid", RdPriceEq(s, 0.1 + 0.2, 0.3));
  }

//+------------------------------------------------------------------+
void TestDistances(CTestRunner &t)
  {
   t.Begin("Distances, points and ticks (BC-07)");
   SSymbolSpec s;
   TfFx(s);
   ASSERT_TRUE("AtLeast: equality allowed", RdDistAtLeast(s, 1.10000, 1.09970, 0.00030));
   ASSERT_FALSE("AtLeast: one tick short", RdDistAtLeast(s, 1.10000, 1.09971, 0.00030));
   ASSERT_TRUE("AtLeast: one tick more", RdDistAtLeast(s, 1.10000, 1.09969, 0.00030));
   ASSERT_TRUE("AtLeast: zero distance, equal prices", RdDistAtLeast(s, 1.10000, 1.10000, 0.0));
   ASSERT_FALSE("MoreThan: equal is not more", RdDistMoreThan(s, 1.10000, 1.09995, 0.00005));
   ASSERT_TRUE("MoreThan: one tick more", RdDistMoreThan(s, 1.10000, 1.09994, 0.00005));
   ASSERT_EQ_INT("points 1.10000 - 1.09800", RdPointsBetween(s, 1.10000, 1.09800), 200);
   ASSERT_NEAR("ticks 1.10000 - 1.09800", RdTicksBetween(s, 1.10000, 1.09800), 200.0, 1e-12);
   ASSERT_NEAR("off-grid distance is not snapped", RdTicksBetween(s, 1.100005, 1.10000), 0.5, 1e-6);
   TfSpec(s, "XAUUSD", 2, 0.01, 0.01, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("gold ticks 4000.00 - 3990.00", RdTicksBetween(s, 4000.00, 3990.00), 1000.0, 1e-12);
   TfSpec(s, "IDX025", 2, 0.01, 0.25, 1.0, 0.01, 0.01, 100.0);
   ASSERT_NEAR("tick 0.25: 1.25 = 5 ticks", RdTicksBetween(s, 4501.25, 4500.00), 5.0, 1e-12);
   ASSERT_EQ_INT("tick 0.25: 1.25 = 125 points", RdPointsBetween(s, 4501.25, 4500.00), 125);
  }

//+------------------------------------------------------------------+
void TestVolumeHelpers(CTestRunner &t)
  {
   t.Begin("Volume validity and comparisons");
   SSymbolSpec s;
   TfSpec(s, "GRID", 2, 0.01, 0.01, 1.0, 0.5, 0.01, 100.0);
   ASSERT_TRUE("0.5 valid", RdIsValidVolume(s, 0.5));
   ASSERT_TRUE("0.53 valid", RdIsValidVolume(s, 0.53));
   ASSERT_FALSE("0.535 off grid", RdIsValidVolume(s, 0.535));
   ASSERT_FALSE("0.49 below min", RdIsValidVolume(s, 0.49));
   ASSERT_TRUE("100 = max valid", RdIsValidVolume(s, 100.0));
   ASSERT_FALSE("100.01 above max", RdIsValidVolume(s, 100.01));
   ASSERT_TRUE("VolEq 0.1 + 0.2 = 0.3", RdVolEq(0.1 + 0.2, 0.3));
   ASSERT_TRUE("VolLt 0.29 < 0.3", RdVolLt(0.29, 0.3));
   ASSERT_FALSE("VolLt within 1e-8", RdVolLt(0.3, 0.30000000001));
   ASSERT_TRUE("VolGt 0.31 > 0.3", RdVolGt(0.31, 0.3));
  }

//+------------------------------------------------------------------+
void TestFormat(CTestRunner &t)
  {
   t.Begin("Display formatting (04 section 11, BC-12)");
   string euro = RdCurrencySymbol("EUR");
   ASSERT_EQ_INT("euro sign is U+20AC", StringGetCharacter(euro, 0), 0x20AC);
   ASSERT_EQ_STR("USD", RdFormatMoney(1234.5, "USD"), "$1,234.50");
   ASSERT_EQ_STR("EUR negative", RdFormatMoney(-60.0, "EUR"), "-" + euro + "60.00");
   ASSERT_EQ_STR("ISO code after the amount", RdFormatMoney(1234567.891, "CHF"), "1,234,567.89 CHF");
   ASSERT_EQ_STR("cent currency", RdFormatMoney(12.5, "USC"), "12.50 USC");
   ASSERT_EQ_STR("no sign when it rounds to zero", RdFormatMoney(-0.004, "USD"), "$0.00");
   ASSERT_EQ_STR("rounding carries into thousands", RdFormatMoney(999999.999, "USD"), "$1,000,000.00");
   ASSERT_EQ_STR("JPY with 0 decimals", RdFormatMoney(100.0, "JPY", 0), RdCurrencySymbol("JPY") + "100");
   ASSERT_EQ_STR("no currency", RdFormatMoney(1000.0, ""), "1,000.00");
   ASSERT_EQ_STR("thousands 123", RdGroupThousands("123"), "123");
   ASSERT_EQ_STR("thousands 1234", RdGroupThousands("1234"), "1,234");
   ASSERT_EQ_STR("thousands 123456", RdGroupThousands("123456"), "123,456");
   ASSERT_EQ_STR("percent", RdFormatPct(1.2), "1.20 %");
   ASSERT_EQ_STR("cap 10", RdFormatCapPct(10.0), "10 %");
   ASSERT_EQ_STR("cap 7.5", RdFormatCapPct(7.5), "7.5 %");
   SSymbolSpec s;
   TfFx(s);
   ASSERT_EQ_STR("lots step 0.01", RdFormatLots(s, 0.5), "0.50");
   ASSERT_EQ_STR("price 5 digits", RdFormatPrice(s, 1.1), "1.10000");
   TfSpec(s, "CFD", 2, 0.01, 0.01, 0.01, 1.0, 1.0, 100.0);
   ASSERT_EQ_STR("lots step 1", RdFormatLots(s, 1.0), "1");
   TfSpec(s, "ETH", 2, 0.01, 0.01, 0.01, 1.0, 0.1, 100.0);
   ASSERT_EQ_STR("lots step 0.1", RdFormatLots(s, 2.3), "2.3");
   ASSERT_EQ_STR("Buy Stop", RdOrderText(SIDE_BUY, KIND_STOP), "Buy Stop");
   ASSERT_EQ_STR("Sell Limit", RdOrderText(SIDE_SELL, KIND_LIMIT), "Sell Limit");
   ASSERT_EQ_STR("Buy", RdOrderText(SIDE_BUY, KIND_MARKET), "Buy");
   ASSERT_EQ_STR("ticket", RdTicketText(123456), "#123456");
   ASSERT_EQ_INT("TP mode: no TP line, manual ignored", RdTpModeFrom(false, true), TPMODE_NONE);
   ASSERT_EQ_INT("TP mode: auto R/R", RdTpModeFrom(true, false), TPMODE_AUTO_RR);
   ASSERT_EQ_INT("TP mode: manual line", RdTpModeFrom(true, true), TPMODE_MANUAL_LINE);
  }

//+------------------------------------------------------------------+
void RunPriceMathTests(CTestRunner &t)
  {
   TestV08(t);
   TestV10(t);
   TestV22(t);
   TestFloorVolumeGrids(t);
   TestFloorVolumeSweep(t);
   TestDirectionalRounding(t);
   TestPriceComparisons(t);
   TestDistances(t);
   TestVolumeHelpers(t);
   TestFormat(t);
  }

#endif // RD_TESTS_PRICEMATH_MQH
