// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestValidators.mqh             |
//| Purpose : tests of Domain/Validators.mqh: V-12, V-13, V-14, V-21 |
//|           and the validator edge cases (market side, stops and   |
//|           freeze levels, pending geometry, volume limit).        |
//|           Quote used throughout: Bid 1.10000 / Ask 1.10010.      |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_VALIDATORS_MQH
#define RD_TESTS_VALIDATORS_MQH

#include "..\..\..\Include\RiskDesk\Domain\Validators.mqh"
#include "TestRunner.mqh"
#include "TestFixtures.mqh"

//+------------------------------------------------------------------+
void TestV12(CTestRunner &t)
  {
   t.Begin("V-12 Market side");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   ESide side = SIDE_SELL;
   SResult r;
   bool ok = CValidators::PreviewSide(1.09900, q, s, side, r);
   ASSERT_TRUE("SL 1.09900 -> a side", ok);
   ASSERT_EQ_INT("SL 1.09900 -> BUY", side, SIDE_BUY);
   ok = CValidators::PreviewSide(1.10100, q, s, side, r);
   ASSERT_TRUE("SL 1.10100 -> a side", ok);
   ASSERT_EQ_INT("SL 1.10100 -> SELL", side, SIDE_SELL);
   ok = CValidators::PreviewSide(1.10005, q, s, side, r);
   ASSERT_FALSE("SL 1.10005 -> none", ok);
   ASSERT_CONTAINS("SL 1.10005 reason", r.message, "SL inside spread");
   ASSERT_FALSE("SL at Bid -> none", CValidators::PreviewSide(1.10000, q, s, side, r));
   ASSERT_FALSE("SL at Ask -> none", CValidators::PreviewSide(1.10010, q, s, side, r));
  }

//+------------------------------------------------------------------+
void CheckClass(CTestRunner &t, const string name, const double entry, const double sl, const SQuote &q,
                const SSymbolSpec &s, const ESide wantSide, const EOrderKind wantKind, const string wantText)
  {
   ESide side = SIDE_BUY;
   EOrderKind kind = KIND_MARKET;
   SResult r;
   bool ok = CValidators::ClassifyPending(entry, sl, 0.0, q, s, side, kind, r);
   ASSERT_TRUE(name + ": valid", ok);
   ASSERT_EQ_INT(name + ": side", side, wantSide);
   ASSERT_EQ_INT(name + ": kind", kind, wantKind);
   ASSERT_EQ_STR(name + ": Pending Info text", r.message, wantText);
  }

void TestV13(CTestRunner &t)
  {
   t.Begin("V-13 Pending classification");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   CheckClass(t, "E 1.10200 SL 1.10000", 1.10200, 1.10000, q, s, SIDE_BUY, KIND_STOP, "Buy Stop");
   CheckClass(t, "E 1.09800 SL 1.09600", 1.09800, 1.09600, q, s, SIDE_BUY, KIND_LIMIT, "Buy Limit");
   CheckClass(t, "E 1.09800 SL 1.10000", 1.09800, 1.10000, q, s, SIDE_SELL, KIND_STOP, "Sell Stop");
   CheckClass(t, "E 1.10200 SL 1.10400", 1.10200, 1.10400, q, s, SIDE_SELL, KIND_LIMIT, "Sell Limit");
   CheckClass(t, "long entry inside spread", 1.10005, 1.09900, q, s, SIDE_BUY, KIND_LIMIT, "Buy Limit");
   CheckClass(t, "short entry inside spread", 1.10005, 1.10100, q, s, SIDE_SELL, KIND_LIMIT, "Sell Limit");
  }

//+------------------------------------------------------------------+
void TestV14(CTestRunner &t)
  {
   t.Begin("V-14 Pending too close");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 10;
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   ESide side = SIDE_SELL;
   EOrderKind kind = KIND_MARKET;
   SResult r;
   bool ok = CValidators::ClassifyPending(1.10005, 1.09900, 0.0, q, s, side, kind, r);
   ASSERT_TRUE("classified", ok);
   ASSERT_EQ_INT("Buy Limit: side", side, SIDE_BUY);
   ASSERT_EQ_INT("Buy Limit: kind", kind, KIND_LIMIT);
   ok = CValidators::PendingStops(side, kind, 1.10005, 1.09900, 0.0, q, s, r);
   ASSERT_FALSE("refused", ok);
   ASSERT_CONTAINS("names Ask and the type", r.message, "Entry too close to Ask for a Buy Limit");
   ASSERT_CONTAINS("needed distance", r.message, "needs >= 10 pts (0.00010)");
   ASSERT_CONTAINS("where to move it", r.message, "1.10000 or lower");
  }

//+------------------------------------------------------------------+
void CheckParse(CTestRunner &t, const string text, const bool wantOk, const double wantPct)
  {
   double pct = -1.0;
   SResult r;
   bool ok = CValidators::ParseRiskPct(text, 10.0, pct, r);
   string name = "\"" + text + "\"";
   if(wantOk)
     {
      ASSERT_TRUE(name + " accepted", ok);
      ASSERT_NEAR(name + " value", pct, wantPct, 1e-12);
     }
   else
     {
      ASSERT_FALSE(name + " rejected", ok);
      ASSERT_TRUE(name + " has a reason", r.message != "");
     }
  }

void TestV21(CTestRunner &t)
  {
   t.Begin("V-21 Risk input parsing");
   CheckParse(t, "1,5", true, 1.5);
   CheckParse(t, "0", false, 0.0);
   CheckParse(t, "12", false, 0.0);
   CheckParse(t, "abc", false, 0.0);
   CheckParse(t, " 0.25 ", true, 0.25);
   double pct = 0.0;
   SResult r;
   CValidators::ParseRiskPct("12", 10.0, pct, r);
   ASSERT_CONTAINS("\"12\" names the max", r.message, "cannot be above 10 % per trade");
   CValidators::ParseRiskPct("0", 10.0, pct, r);
   ASSERT_CONTAINS("\"0\" reason", r.message, "must be above 0");
  }

void TestRiskInputEdges(CTestRunner &t)
  {
   t.Begin("Risk input edge cases (F-02)");
   CheckParse(t, "10", true, 10.0);
   CheckParse(t, "1.5%", true, 1.5);
   CheckParse(t, "2 %", true, 2.0);
   CheckParse(t, "+2", true, 2.0);
   CheckParse(t, ".5", true, 0.5);
   CheckParse(t, "5.", true, 5.0);
   CheckParse(t, "0,75", true, 0.75);
   CheckParse(t, "0.333", true, 0.33);
   CheckParse(t, "10.001", true, 10.0);
   CheckParse(t, "0.001", false, 0.0);
   CheckParse(t, "10.01", false, 0.0);
   CheckParse(t, "", false, 0.0);
   CheckParse(t, "   ", false, 0.0);
   CheckParse(t, "1.2.3", false, 0.0);
   CheckParse(t, "1,5,0", false, 0.0);
   CheckParse(t, "-1", false, 0.0);
   CheckParse(t, "1e2", false, 0.0);
   CheckParse(t, ".", false, 0.0);
   CheckParse(t, "1 5", false, 0.0);
  }

//+------------------------------------------------------------------+
void TestMarketSide(CTestRunner &t)
  {
   t.Begin("Market side validation (04 section 6, F-06)");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SResult r;
   ASSERT_FALSE("buy, SL above Bid", CValidators::MarketSide(SIDE_BUY, 1.10100, 0.0, q, s, r));
   ASSERT_CONTAINS("buy, SL above Bid message (T-07)", r.message, "SL above Bid for a buy");
   ASSERT_FALSE("buy, SL at Bid", CValidators::MarketSide(SIDE_BUY, 1.10000, 0.0, q, s, r));
   ASSERT_CONTAINS("buy, SL at Bid message", r.message, "SL at Bid for a buy");
   ASSERT_FALSE("buy, TP below Bid", CValidators::MarketSide(SIDE_BUY, 1.09900, 1.09950, q, s, r));
   ASSERT_CONTAINS("buy, TP below Bid message", r.message, "TP below Bid for a buy");
   ASSERT_TRUE("buy, SL and TP valid", CValidators::MarketSide(SIDE_BUY, 1.09900, 1.10200, q, s, r));
   ASSERT_TRUE("buy, no TP", CValidators::MarketSide(SIDE_BUY, 1.09900, 0.0, q, s, r));
   ASSERT_TRUE("buy, TP inside spread but above Bid", CValidators::MarketSide(SIDE_BUY, 1.09900, 1.10005, q, s, r));
   ASSERT_FALSE("sell, SL inside spread", CValidators::MarketSide(SIDE_SELL, 1.10005, 0.0, q, s, r));
   ASSERT_CONTAINS("sell, SL below Ask message", r.message, "SL below Ask for a sell");
   ASSERT_FALSE("sell, TP above Ask", CValidators::MarketSide(SIDE_SELL, 1.10100, 1.10050, q, s, r));
   ASSERT_CONTAINS("sell, TP above Ask message", r.message, "TP above Ask for a sell");
   ASSERT_TRUE("sell, SL and TP valid", CValidators::MarketSide(SIDE_SELL, 1.10100, 1.09900, q, s, r));
   ASSERT_FALSE("no SL", CValidators::MarketSide(SIDE_BUY, 0.0, 0.0, q, s, r));
   ASSERT_CONTAINS("no SL message", r.message, "No SL line");
  }

//+------------------------------------------------------------------+
void TestMarketStops(CTestRunner &t)
  {
   t.Begin("Market stops level (BC-07)");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 30;
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SResult r;
   ASSERT_TRUE("buy SL exactly 30 pts below Bid", CValidators::MarketSide(SIDE_BUY, 1.09970, 0.0, q, s, r));
   ASSERT_FALSE("buy SL 29 pts below Bid", CValidators::MarketSide(SIDE_BUY, 1.09971, 0.0, q, s, r));
   ASSERT_CONTAINS("buy SL message", r.message, "SL too close to Bid: needs >= 30 pts (0.00030)");
   ASSERT_CONTAINS("buy SL limit price", r.message, "1.09970 or lower");
   ASSERT_FALSE("buy TP 29 pts above Bid", CValidators::MarketSide(SIDE_BUY, 1.09900, 1.10029, q, s, r));
   ASSERT_CONTAINS("buy TP message", r.message, "TP too close to Bid");
   ASSERT_CONTAINS("buy TP limit price", r.message, "1.10030 or higher");
   ASSERT_TRUE("buy TP exactly 30 pts", CValidators::MarketSide(SIDE_BUY, 1.09900, 1.10030, q, s, r));
   ASSERT_TRUE("sell SL exactly 30 pts above Ask", CValidators::MarketSide(SIDE_SELL, 1.10040, 0.0, q, s, r));
   ASSERT_FALSE("sell SL 29 pts above Ask", CValidators::MarketSide(SIDE_SELL, 1.10039, 0.0, q, s, r));
   ASSERT_CONTAINS("sell SL limit price", r.message, "1.10040 or higher");
   ASSERT_FALSE("sell TP 29 pts below Ask", CValidators::MarketSide(SIDE_SELL, 1.10100, 1.09981, q, s, r));
   ASSERT_CONTAINS("sell TP message", r.message, "TP too close to Ask");
   ASSERT_CONTAINS("sell TP limit price", r.message, "1.09980 or lower");
  }

//+------------------------------------------------------------------+
void TestPendingClassEdges(CTestRunner &t)
  {
   t.Begin("Pending classification edge cases (04 section 7)");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   ESide side = SIDE_BUY;
   EOrderKind kind = KIND_MARKET;
   SResult r;
   ASSERT_FALSE("entry = SL", CValidators::ClassifyPending(1.10200, 1.10200, 0.0, q, s, side, kind, r));
   ASSERT_CONTAINS("entry = SL message", r.message, "Entry and SL are equal");
   ASSERT_FALSE("long entry at Ask", CValidators::ClassifyPending(1.10010, 1.09900, 0.0, q, s, side, kind, r));
   ASSERT_CONTAINS("long entry at Ask message", r.message, "Entry at market - use Buy");
   ASSERT_FALSE("short entry at Bid", CValidators::ClassifyPending(1.10000, 1.10100, 0.0, q, s, side, kind, r));
   ASSERT_CONTAINS("short entry at Bid message", r.message, "Entry at market - use Sell");
   bool ok = CValidators::ClassifyPending(1.10200, 1.10000, 1.10100, q, s, side, kind, r);
   ASSERT_FALSE("Buy Stop with TP below the entry", ok);
   ASSERT_CONTAINS("long TP message", r.message, "TP on wrong side");
   ASSERT_EQ_INT("type still known: side", side, SIDE_BUY);
   ASSERT_EQ_INT("type still known: kind", kind, KIND_STOP);
   ASSERT_FALSE("Sell Limit with TP above the entry", CValidators::ClassifyPending(1.10200, 1.10400, 1.10300, q, s, side, kind, r));
   ASSERT_CONTAINS("short TP message", r.message, "must be below the entry for a Sell Limit");
   ASSERT_TRUE("Sell Stop with TP below", CValidators::ClassifyPending(1.09800, 1.10000, 1.09600, q, s, side, kind, r));
   ASSERT_FALSE("no entry", CValidators::ClassifyPending(0.0, 1.10000, 0.0, q, s, side, kind, r));
   ASSERT_CONTAINS("no entry message", r.message, "No entry line");
   ASSERT_FALSE("no SL", CValidators::ClassifyPending(1.10200, 0.0, 0.0, q, s, side, kind, r));
   ASSERT_CONTAINS("no SL message", r.message, "No SL line");
  }

//+------------------------------------------------------------------+
void TestPendingStops(CTestRunner &t)
  {
   t.Begin("Pending stops level per type (BC-07)");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 10;
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SResult r;
   ASSERT_TRUE("Buy Limit: all distances exactly 10 pts",
               CValidators::PendingStops(SIDE_BUY, KIND_LIMIT, 1.10000, 1.09990, 1.10010, q, s, r));
   ASSERT_FALSE("Buy Limit: SL 5 pts", CValidators::PendingStops(SIDE_BUY, KIND_LIMIT, 1.10000, 1.09995, 0.0, q, s, r));
   ASSERT_CONTAINS("Buy Limit: SL message", r.message, "SL too close to the entry for a Buy Limit");
   ASSERT_CONTAINS("Buy Limit: SL limit", r.message, "1.09990 or lower");
   ASSERT_FALSE("Buy Limit: TP 5 pts", CValidators::PendingStops(SIDE_BUY, KIND_LIMIT, 1.10000, 1.09900, 1.10005, q, s, r));
   ASSERT_CONTAINS("Buy Limit: TP limit", r.message, "1.10010 or higher");
   ASSERT_FALSE("Sell Limit: 5 pts above Bid", CValidators::PendingStops(SIDE_SELL, KIND_LIMIT, 1.10005, 1.10100, 0.0, q, s, r));
   ASSERT_CONTAINS("Sell Limit: message", r.message, "Entry too close to Bid for a Sell Limit");
   ASSERT_CONTAINS("Sell Limit: limit", r.message, "1.10010 or higher");
   ASSERT_TRUE("Sell Limit: 10 pts above Bid", CValidators::PendingStops(SIDE_SELL, KIND_LIMIT, 1.10010, 1.10100, 0.0, q, s, r));
   ASSERT_FALSE("Buy Stop: 5 pts above Ask", CValidators::PendingStops(SIDE_BUY, KIND_STOP, 1.10015, 1.09900, 0.0, q, s, r));
   ASSERT_CONTAINS("Buy Stop: limit", r.message, "1.10020 or higher");
   ASSERT_TRUE("Buy Stop: 10 pts above Ask", CValidators::PendingStops(SIDE_BUY, KIND_STOP, 1.10020, 1.09900, 0.0, q, s, r));
   ASSERT_FALSE("Sell Stop: 5 pts below Bid", CValidators::PendingStops(SIDE_SELL, KIND_STOP, 1.09995, 1.10100, 0.0, q, s, r));
   ASSERT_CONTAINS("Sell Stop: limit", r.message, "1.09990 or lower");
   ASSERT_TRUE("Sell Stop: 10 pts below Bid", CValidators::PendingStops(SIDE_SELL, KIND_STOP, 1.09990, 1.10100, 0.0, q, s, r));
   ASSERT_FALSE("Sell Stop: SL 5 pts", CValidators::PendingStops(SIDE_SELL, KIND_STOP, 1.09990, 1.09995, 0.0, q, s, r));
   ASSERT_CONTAINS("Sell Stop: SL limit", r.message, "1.10000 or higher");
   ASSERT_FALSE("market kind refused", CValidators::PendingStops(SIDE_BUY, KIND_MARKET, 1.10200, 1.09900, 0.0, q, s, r));
  }

//+------------------------------------------------------------------+
void TestPendingGeometry(CTestRunner &t)
  {
   t.Begin("Pending order type stays valid (OP-16)");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SResult r;
   ASSERT_FALSE("Buy Stop below Ask", CValidators::PendingGeometry(SIDE_BUY, KIND_STOP, 1.10005, 1.09900, 0.0, q, s, r));
   ASSERT_CONTAINS("Buy Stop message", r.message, "A Buy Stop must stay above Ask (1.10010)");
   ASSERT_FALSE("Buy Limit above Ask", CValidators::PendingGeometry(SIDE_BUY, KIND_LIMIT, 1.10020, 1.09900, 0.0, q, s, r));
   ASSERT_CONTAINS("Buy Limit message", r.message, "must stay below Ask");
   ASSERT_FALSE("Sell Stop above Bid", CValidators::PendingGeometry(SIDE_SELL, KIND_STOP, 1.10005, 1.10100, 0.0, q, s, r));
   ASSERT_CONTAINS("Sell Stop message", r.message, "must stay below Bid");
   ASSERT_FALSE("Sell Limit below Bid", CValidators::PendingGeometry(SIDE_SELL, KIND_LIMIT, 1.09990, 1.10100, 0.0, q, s, r));
   ASSERT_CONTAINS("Sell Limit message", r.message, "must stay above Bid");
   ASSERT_FALSE("Buy Stop SL above entry", CValidators::PendingGeometry(SIDE_BUY, KIND_STOP, 1.10200, 1.10300, 0.0, q, s, r));
   ASSERT_CONTAINS("buy SL message", r.message, "SL must be below the entry for a Buy Stop");
   ASSERT_FALSE("Sell Limit SL below entry", CValidators::PendingGeometry(SIDE_SELL, KIND_LIMIT, 1.10200, 1.10100, 0.0, q, s, r));
   ASSERT_CONTAINS("sell SL message", r.message, "SL must be above the entry for a Sell Limit");
   ASSERT_TRUE("order without SL/TP", CValidators::PendingGeometry(SIDE_BUY, KIND_STOP, 1.10200, 0.0, 0.0, q, s, r));
  }

//+------------------------------------------------------------------+
void TestFreezeLevel(CTestRunner &t)
  {
   t.Begin("Freeze level (BC-07)");
   SSymbolSpec s;
   TfFx(s);
   s.freezeLevel = 5;
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SResult r;
   ASSERT_FALSE("buy SL 5 pts below Bid frozen", CValidators::PositionNotFrozen(SIDE_BUY, 1.09995, 0.0, q, s, r));
   ASSERT_CONTAINS("frozen message", r.message, "SL is within the freeze level (5 pts) of Bid");
   ASSERT_TRUE("buy SL 6 pts below Bid free", CValidators::PositionNotFrozen(SIDE_BUY, 1.09994, 0.0, q, s, r));
   ASSERT_FALSE("buy TP 5 pts above Bid frozen", CValidators::PositionNotFrozen(SIDE_BUY, 0.0, 1.10005, q, s, r));
   ASSERT_TRUE("buy TP 6 pts above Bid free", CValidators::PositionNotFrozen(SIDE_BUY, 0.0, 1.10006, q, s, r));
   ASSERT_TRUE("buy without SL/TP free", CValidators::PositionNotFrozen(SIDE_BUY, 0.0, 0.0, q, s, r));
   ASSERT_FALSE("sell SL 5 pts above Ask frozen", CValidators::PositionNotFrozen(SIDE_SELL, 1.10015, 0.0, q, s, r));
   ASSERT_TRUE("sell SL 6 pts above Ask free", CValidators::PositionNotFrozen(SIDE_SELL, 1.10016, 0.0, q, s, r));
   ASSERT_FALSE("sell TP 5 pts below Ask frozen", CValidators::PositionNotFrozen(SIDE_SELL, 0.0, 1.10005, q, s, r));
   ASSERT_TRUE("sell TP 6 pts below Ask free", CValidators::PositionNotFrozen(SIDE_SELL, 0.0, 1.10004, q, s, r));
   ASSERT_FALSE("Buy Limit 5 pts below Ask frozen", CValidators::PendingNotFrozen(SIDE_BUY, KIND_LIMIT, 1.10005, q, s, r));
   ASSERT_CONTAINS("pending frozen message", r.message, "Buy Limit entry is within the freeze level (5 pts) of Ask");
   ASSERT_TRUE("Buy Limit 6 pts below Ask free", CValidators::PendingNotFrozen(SIDE_BUY, KIND_LIMIT, 1.10004, q, s, r));
   ASSERT_FALSE("Buy Stop 5 pts above Ask frozen", CValidators::PendingNotFrozen(SIDE_BUY, KIND_STOP, 1.10015, q, s, r));
   ASSERT_TRUE("Buy Stop 6 pts above Ask free", CValidators::PendingNotFrozen(SIDE_BUY, KIND_STOP, 1.10016, q, s, r));
   ASSERT_FALSE("Sell Limit 5 pts above Bid frozen", CValidators::PendingNotFrozen(SIDE_SELL, KIND_LIMIT, 1.10005, q, s, r));
   ASSERT_FALSE("Sell Stop 5 pts below Bid frozen", CValidators::PendingNotFrozen(SIDE_SELL, KIND_STOP, 1.09995, q, s, r));
   ASSERT_TRUE("Sell Stop 6 pts below Bid free", CValidators::PendingNotFrozen(SIDE_SELL, KIND_STOP, 1.09994, q, s, r));
   s.freezeLevel = 0;
   ASSERT_TRUE("freeze level 0 never blocks", CValidators::PositionNotFrozen(SIDE_BUY, 1.10000, 1.10000, q, s, r));
   ASSERT_TRUE("freeze level 0 never blocks pending", CValidators::PendingNotFrozen(SIDE_BUY, KIND_LIMIT, 1.10010, q, s, r));
  }

//+------------------------------------------------------------------+
void TestVolumeLimitAndQuote(CTestRunner &t)
  {
   t.Begin("Volume limit (BC-04) and quote check");
   SSymbolSpec s;
   TfFx(s);
   s.volLimit = 2.0;
   SResult r;
   ASSERT_TRUE("1.50 + 0.50 = limit", CValidators::VolumeLimit(s, 1.5, 0.5, r));
   ASSERT_FALSE("1.50 + 0.51 > limit", CValidators::VolumeLimit(s, 1.5, 0.51, r));
   ASSERT_CONTAINS("remaining allowance", r.message, "at most 0.50 more");
   ASSERT_FALSE("limit already used", CValidators::VolumeLimit(s, 2.0, 0.01, r));
   ASSERT_CONTAINS("nothing left", r.message, "at most 0.00 more");
   s.volLimit = 0.0;
   ASSERT_TRUE("limit 0 = unlimited", CValidators::VolumeLimit(s, 100.0, 50.0, r));
   SQuote q;
   TfQuote(q, 0.0, 0.0);
   ASSERT_FALSE("no quote", CValidators::QuoteOk(q, s, r));
   ASSERT_CONTAINS("no quote message", r.message, "No quote for EURUSD");
   TfQuote(q, 1.10010, 1.10000);
   ASSERT_FALSE("Ask below Bid", CValidators::QuoteOk(q, s, r));
   TfQuote(q, 1.10000, 1.10010);
   ASSERT_TRUE("normal quote", CValidators::QuoteOk(q, s, r));
  }

//+------------------------------------------------------------------+
void RunValidatorTests(CTestRunner &t)
  {
   TestV12(t);
   TestV13(t);
   TestV14(t);
   TestV21(t);
   TestRiskInputEdges(t);
   TestMarketSide(t);
   TestMarketStops(t);
   TestPendingClassEdges(t);
   TestPendingStops(t);
   TestPendingGeometry(t);
   TestFreezeLevel(t);
   TestVolumeLimitAndQuote(t);
  }

#endif // RD_TESTS_VALIDATORS_MQH
