//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestPlanner.mqh                |
//| Purpose : tests of Domain/Planner.mqh: V-19, V-20, V-23, the     |
//|           market/pending plan flows, Risk Free modes and skips,  |
//|           and moves of placed pending orders (OP-16).            |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_PLANNER_MQH
#define RD_TESTS_PLANNER_MQH

#include "..\..\..\Include\RiskDesk\Domain\Planner.mqh"
#include "TestRunner.mqh"
#include "TestFixtures.mqh"

// Buy 0.50 lot EURUSD opened at 1.10000, SL 1.09800, tick worth 1.00.
void TfRiskFreeBuy(SRiskFreeInput &in)
  {
   in.Reset();
   in.side = SIDE_BUY;
   in.open = 1.10000;
   in.sl = 1.09800;
   in.volume = 0.5;
   in.tickValue = 1.0;
  }

//+------------------------------------------------------------------+
void TestV19(CTestRunner &t)
  {
   t.Begin("V-19 Risk Free buy");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 30;
   SPlanSettings cfg;
   cfg.Defaults();
   SRiskFreeInput in;
   TfRiskFreeBuy(in);
   SQuote q;
   TfQuote(q, 1.10050, 1.10062);
   SRiskFreeResult rf;
   SResult r;
   bool ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_TRUE("bid 1.10050 applied", ok);
   ASSERT_NEAR("target = open + spread", rf.target, 1.10012, 1e-12);
   TfQuote(q, 1.10035, 1.10047);
   ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_FALSE("bid 1.10035 skipped", ok);
   ASSERT_EQ_INT("skip is amber", r.sev, SEV_WARN);
   ASSERT_CONTAINS("needed price", r.message, "not enough profit (needs Bid >= 1.10043)");
  }

//+------------------------------------------------------------------+
void TestV20(CTestRunner &t)
  {
   t.Begin("V-20 Risk Free never loosens");
   SSymbolSpec s;
   TfFx(s);
   SPlanSettings cfg;
   cfg.Defaults();
   SRiskFreeInput in;
   TfRiskFreeBuy(in);
   in.sl = 1.10020;
   SQuote q;
   TfQuote(q, 1.10100, 1.10112);
   SRiskFreeResult rf;
   SResult r;
   ASSERT_FALSE("skipped", CPlanner::RiskFree(in, q, s, cfg, rf, r));
   ASSERT_NEAR("target 1.10012", rf.target, 1.10012, 1e-12);
   ASSERT_CONTAINS("already protected", r.message, "already protected");
   in.sl = 1.10012;
   ASSERT_FALSE("SL already at the target: skipped", CPlanner::RiskFree(in, q, s, cfg, rf, r));
  }

//+------------------------------------------------------------------+
void TestV23(CTestRunner &t)
  {
   t.Begin("V-23 Risk Free spread + commission");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 30;
   SPlanSettings cfg;
   cfg.Defaults();
   cfg.commissionPerLot = 7.0;
   SRiskFreeInput in;
   TfRiskFreeBuy(in);
   SQuote q;
   TfQuote(q, 1.10060, 1.10072);
   SRiskFreeResult rf;
   SResult r;
   bool ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_TRUE("bid 1.10060 applied", ok);
   ASSERT_NEAR("commDist 0.00007", rf.costDistance, 0.00007, 1e-12);
   ASSERT_NEAR("target 1.10019", rf.target, 1.10019, 1e-12);
   TfQuote(q, 1.10045, 1.10057);
   ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_FALSE("bid 1.10045 skipped", ok);
   ASSERT_CONTAINS("needed price", r.message, "needs Bid >= 1.10050");
  }

//+------------------------------------------------------------------+
void TestRiskFreeSell(CTestRunner &t)
  {
   t.Begin("Risk Free sell");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 30;
   SPlanSettings cfg;
   cfg.Defaults();
   SRiskFreeInput in;
   TfRiskFreeBuy(in);
   in.side = SIDE_SELL;
   in.sl = 1.10200;
   SQuote q;
   TfQuote(q, 1.09938, 1.09950);
   SRiskFreeResult rf;
   SResult r;
   bool ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_TRUE("ask 1.09950 applied", ok);
   ASSERT_NEAR("target = open - spread", rf.target, 1.09988, 1e-12);
   TfQuote(q, 1.09948, 1.09960);
   ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_FALSE("ask 1.09960 skipped", ok);
   ASSERT_CONTAINS("needed price", r.message, "needs Ask <= 1.09957");
   in.sl = 1.09980;
   TfQuote(q, 1.09900, 1.09912);
   ASSERT_FALSE("sell SL already below the target", CPlanner::RiskFree(in, q, s, cfg, rf, r));
   ASSERT_CONTAINS("sell already protected", r.message, "already protected");
  }

//+------------------------------------------------------------------+
void TestRiskFreeModes(CTestRunner &t)
  {
   t.Begin("Risk Free modes and extra points (04 section 9)");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 30;
   SPlanSettings cfg;
   cfg.Defaults();
   SRiskFreeInput in;
   TfRiskFreeBuy(in);
   SQuote q;
   TfQuote(q, 1.10100, 1.10112);
   SRiskFreeResult rf;
   SResult r;
   cfg.riskFreeMode = RF_EXACT;
   CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_NEAR("EXACT: open price", rf.target, 1.10000, 1e-12);
   cfg.riskFreeMode = RF_SPREAD;
   cfg.commissionPerLot = 7.0;
   CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_NEAR("SPREAD: commission ignored", rf.target, 1.10012, 1e-12);
   cfg.riskFreeMode = RF_COMMISSION;
   in.bookedCost = 3.5;
   CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_NEAR("COMMISSION: booked 3.50 on 0.50 lot = 7 ticks", rf.target, 1.10007, 1e-12);
   cfg.riskFreeMode = RF_SPREAD_COMMISSION;
   cfg.commissionPerLot = 0.0;
   cfg.riskFreeExtraPoints = 5;
   bool ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_TRUE("extra points applied", ok);
   ASSERT_NEAR("SPREAD_COMMISSION + 5 pts", rf.target, 1.10017, 1e-12);
   cfg.riskFreeExtraPoints = 0;
   cfg.commissionPerLot = 7.0;
   in.tickValue = 0.0;
   ok = CPlanner::RiskFree(in, q, s, cfg, rf, r);
   ASSERT_FALSE("commission without tick value refused", ok);
   ASSERT_EQ_INT("refusal is red", r.sev, SEV_ERROR);
   ASSERT_CONTAINS("refusal message", r.message, "Cannot value the commission on EURUSD");
  }

//+------------------------------------------------------------------+
void TestRiskFreeSkips(CTestRunner &t)
  {
   t.Begin("Risk Free skips: not in profit, frozen");
   SSymbolSpec s;
   TfFx(s);
   s.stopsLevel = 30;
   SPlanSettings cfg;
   cfg.Defaults();
   SRiskFreeInput in;
   TfRiskFreeBuy(in);
   SQuote q;
   TfQuote(q, 1.09990, 1.10002);
   SRiskFreeResult rf;
   SResult r;
   ASSERT_FALSE("buy below open", CPlanner::RiskFree(in, q, s, cfg, rf, r));
   ASSERT_EQ_STR("not in profit", r.message, "not in profit");
   in.side = SIDE_SELL;
   in.sl = 1.10200;
   ASSERT_FALSE("sell with Ask above open", CPlanner::RiskFree(in, q, s, cfg, rf, r));
   ASSERT_EQ_STR("sell not in profit", r.message, "not in profit");
   TfRiskFreeBuy(in);
   in.tp = 1.10105;
   s.freezeLevel = 10;
   TfQuote(q, 1.10100, 1.10112);
   ASSERT_FALSE("TP inside the freeze level", CPlanner::RiskFree(in, q, s, cfg, rf, r));
   ASSERT_CONTAINS("frozen reason", r.message, "frozen: TP is within the freeze level (10 pts) of Bid");
  }

//+------------------------------------------------------------------+
void TestMarketPlanAutoRR(CTestRunner &t)
  {
   t.Begin("Market plan with Auto R/R and sizing");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   cfg.tpRR = 2.0;
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SLines lines;
   TfLines(lines, LINES_MARKET, 0.0, 1.09800, 0.0);
   STradePlan plan;
   SResult r;
   bool ok = CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r);
   ASSERT_TRUE("buy planned", ok);
   ASSERT_NEAR("entry = Ask", plan.entry, 1.10010, 1e-12);
   ASSERT_NEAR("SL", plan.sl, 1.09800, 1e-12);
   ASSERT_NEAR("TP = Ask + 2 x 210 pts", plan.tp, 1.10430, 1e-12);
   ASSERT_NEAR("R/R", plan.rr, 2.0, 1e-9);
   double loss = CRiskMath::LossPerLotByTicks(s, plan.entry, plan.sl);
   double gain = CRiskMath::LossPerLotByTicks(s, plan.entry, plan.tp);
   SLotResult lot;
   ok = CPlanner::Size(plan, s, acc, cfg, 1.0, loss, gain, 0.0, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("lots floor(100 / 210)", plan.lots, 0.47, 1e-12);
   ASSERT_NEAR("money risk", plan.riskMoney, 98.70, 1e-9);
   ASSERT_NEAR("risk %", plan.riskPct, 0.987, 1e-9);
   ASSERT_NEAR("reward", plan.rewardMoney, 197.40, 1e-9);
   ok = CPlanner::Market(SIDE_SELL, lines, q, s, cfg, plan, r);
   ASSERT_FALSE("sell with SL below price refused", ok);
   ASSERT_CONTAINS("sell refusal", r.message, "SL below Ask for a sell");
   TfLines(lines, LINES_MARKET, 0.0, 1.10100, 0.0);
   ok = CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r);
   ASSERT_FALSE("buy with SL above price refused before any TP", ok);
   ASSERT_CONTAINS("buy refusal (T-07)", r.message, "SL above Bid for a buy");
   cfg.tpRR = 1.0;
   ok = CPlanner::Market(SIDE_SELL, lines, q, s, cfg, plan, r);
   ASSERT_TRUE("sell planned", ok);
   ASSERT_NEAR("sell entry = Bid", plan.entry, 1.10000, 1e-12);
   ASSERT_NEAR("sell TP = Bid - 100 pts", plan.tp, 1.09900, 1e-12);
  }

//+------------------------------------------------------------------+
void TestMarketPlanTpModes(CTestRunner &t)
  {
   t.Begin("Market plan TP modes (F-17) and Lots preview (F-03)");
   SSymbolSpec s;
   TfFx(s);
   SPlanSettings cfg;
   cfg.Defaults();
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SLines lines;
   TfLines(lines, LINES_MARKET, 0.0, 1.09800, 1.10300);
   STradePlan plan;
   SResult r;
   cfg.tpMode = TPMODE_NONE;
   CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r);
   ASSERT_NEAR("No TP: tp 0 even with a line", plan.tp, 0.0, 1e-12);
   ASSERT_NEAR("No TP: R/R 0", plan.rr, 0.0, 1e-12);
   cfg.tpMode = TPMODE_MANUAL_LINE;
   CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r);
   ASSERT_NEAR("Manual: the line's price", plan.tp, 1.10300, 1e-12);
   lines.hasTp = false;
   CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r);
   ASSERT_NEAR("Manual with the TP line deleted: no TP", plan.tp, 0.0, 1e-12);
   TfLines(lines, LINES_MARKET, 0.0, 1.09800, 1.09950);
   ASSERT_FALSE("Manual TP below Bid refused", CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r));
   ASSERT_CONTAINS("Manual TP refusal", r.message, "TP below Bid for a buy");
   cfg.tpMode = TPMODE_AUTO_RR;
   TfLines(lines, LINES_MARKET, 0.0, 1.10100, 0.0);
   bool ok = CPlanner::MarketPreview(lines, q, s, cfg, plan, r);
   ASSERT_TRUE("preview SL above Ask", ok);
   ASSERT_EQ_INT("preview side SELL", plan.side, SIDE_SELL);
   ASSERT_NEAR("preview entry = Bid", plan.entry, 1.10000, 1e-12);
   TfLines(lines, LINES_MARKET, 0.0, 1.09900, 0.0);
   ok = CPlanner::MarketPreview(lines, q, s, cfg, plan, r);
   ASSERT_EQ_INT("preview side BUY", plan.side, SIDE_BUY);
   ASSERT_NEAR("preview entry = Ask", plan.entry, 1.10010, 1e-12);
   TfLines(lines, LINES_MARKET, 0.0, 1.10005, 0.0);
   ASSERT_FALSE("preview SL inside spread", CPlanner::MarketPreview(lines, q, s, cfg, plan, r));
   ASSERT_CONTAINS("preview reason", r.message, "SL inside spread");
   TfLines(lines, LINES_MARKET, 0.0, 1.098004, 0.0);
   CPlanner::Market(SIDE_BUY, lines, q, s, cfg, plan, r);
   ASSERT_NEAR("line price normalized to the tick", plan.sl, 1.09800, 1e-12);
  }

//+------------------------------------------------------------------+
void TestPendingPlan(CTestRunner &t)
  {
   t.Begin("Pending plan (OP-06/07)");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SLines lines;
   TfLines(lines, LINES_PENDING, 1.10200, 1.10000, 0.0);
   STradePlan plan;
   SResult r;
   bool ok = CPlanner::Pending(lines, q, s, cfg, plan, r);
   ASSERT_TRUE("Buy Stop planned", ok);
   ASSERT_EQ_STR("Pending Info", r.message, "Buy Stop");
   ASSERT_EQ_INT("side", plan.side, SIDE_BUY);
   ASSERT_EQ_INT("kind", plan.kind, KIND_STOP);
   ASSERT_NEAR("Auto R/R 1 from the entry", plan.tp, 1.10400, 1e-12);
   SLotResult lot;
   ok = CPlanner::Size(plan, s, acc, cfg, 1.0, 200.0, 200.0, 0.0, lot, r);
   ASSERT_TRUE("sized", ok);
   ASSERT_NEAR("lots", plan.lots, 0.50, 1e-12);
   ASSERT_NEAR("reward", plan.rewardMoney, 100.0, 1e-9);
   cfg.tpMode = TPMODE_MANUAL_LINE;
   TfLines(lines, LINES_PENDING, 1.10200, 1.10000, 1.10500);
   CPlanner::Pending(lines, q, s, cfg, plan, r);
   ASSERT_NEAR("Manual TP line", plan.tp, 1.10500, 1e-12);
   TfLines(lines, LINES_PENDING, 1.10200, 1.10000, 1.10100);
   ok = CPlanner::Pending(lines, q, s, cfg, plan, r);
   ASSERT_FALSE("Manual TP below the entry refused", ok);
   ASSERT_EQ_INT("type kept for Pending Info", plan.kind, KIND_STOP);
   ASSERT_CONTAINS("TP refusal", r.message, "TP on wrong side");
   cfg.tpMode = TPMODE_NONE;
   s.stopsLevel = 10;
   TfLines(lines, LINES_PENDING, 1.10005, 1.09900, 0.0);
   ok = CPlanner::Pending(lines, q, s, cfg, plan, r);
   ASSERT_FALSE("entry inside the stops level refused", ok);
   ASSERT_EQ_INT("classified as Buy Limit: side", plan.side, SIDE_BUY);
   ASSERT_EQ_INT("classified as Buy Limit: kind", plan.kind, KIND_LIMIT);
   ASSERT_CONTAINS("stops refusal", r.message, "Entry too close to Ask for a Buy Limit");
   TfLines(lines, LINES_PENDING, 0.0, 1.09900, 0.0);
   ASSERT_FALSE("no entry line", CPlanner::Pending(lines, q, s, cfg, plan, r));
  }

//+------------------------------------------------------------------+
void TestSizeLimits(CTestRunner &t)
  {
   t.Begin("Size: volume limit, min lot, max lot");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec acc;
   TfAccount(acc, "USD", 10000.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SLines lines;
   TfLines(lines, LINES_PENDING, 1.10200, 1.10000, 0.0);
   STradePlan plan;
   SLotResult lot;
   SResult r;
   CPlanner::Pending(lines, q, s, cfg, plan, r);
   s.volLimit = 1.0;
   ASSERT_FALSE("0.80 + 0.50 > limit 1", CPlanner::Size(plan, s, acc, cfg, 1.0, 200.0, 0.0, 0.8, lot, r));
   ASSERT_CONTAINS("volume limit message", r.message, "Volume limit on EURUSD");
   ASSERT_NEAR("no lots on refusal", plan.lots, 0.0, 1e-12);
   s.volLimit = 0.0;
   ASSERT_FALSE("below min lot refused", CPlanner::Size(plan, s, acc, cfg, 0.01, 2000.0, 0.0, 0.0, lot, r));
   ASSERT_CONTAINS("min lot message", r.message, "Min lot 0.01 would risk");
   s.volMax = 0.3;
   bool ok = CPlanner::Size(plan, s, acc, cfg, 1.0, 200.0, 0.0, 0.0, lot, r);
   ASSERT_TRUE("capped is still sent", ok);
   ASSERT_NEAR("capped lots", plan.lots, 0.3, 1e-12);
   ASSERT_EQ_INT("capped is amber", r.sev, SEV_WARN);
   ASSERT_CONTAINS("warning kept on the plan", plan.warnings, "Capped at max lot 0.30");
  }

//+------------------------------------------------------------------+
void TfBuyStop(SOrder &o)
  {
   TfOrder(o, 555, "EURUSD", SIDE_BUY, KIND_STOP, 0.5, 1.10200, 1.10000, 1.10400, 772211, 100.0);
  }

void TestMovePendingEntry(CTestRunner &t)
  {
   t.Begin("Move a pending order: entry line (OP-16, D4)");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SOrder o;
   TfBuyStop(o);
   SOrder moved;
   SResult r;
   bool ok = CPlanner::MovePending(o, LINEROLE_ENTRY, 1.10300, q, s, moved, r);
   ASSERT_TRUE("entry up accepted", ok);
   ASSERT_NEAR("new entry", moved.price, 1.10300, 1e-12);
   ASSERT_NEAR("SL moved by the same distance", moved.sl, 1.10100, 1e-12);
   ASSERT_NEAR("TP moved by the same distance", moved.tp, 1.10500, 1e-12);
   ASSERT_NEAR("volume unchanged", moved.volume, 0.5, 1e-12);
   ASSERT_EQ_INT("same ticket", moved.ticket, 555);
   ok = CPlanner::MovePending(o, LINEROLE_ENTRY, 1.1030049, q, s, moved, r);
   ASSERT_NEAR("dropped price normalized", moved.price, 1.10300, 1e-12);
   ok = CPlanner::MovePending(o, LINEROLE_ENTRY, 1.10005, q, s, moved, r);
   ASSERT_FALSE("Buy Stop dragged below Ask refused", ok);
   ASSERT_CONTAINS("refusal", r.message, "A Buy Stop must stay above Ask");
   o.tp = 0.0;
   ok = CPlanner::MovePending(o, LINEROLE_ENTRY, 1.10300, q, s, moved, r);
   ASSERT_NEAR("no TP stays no TP", moved.tp, 0.0, 1e-12);
  }

void TestMovePendingLevels(CTestRunner &t)
  {
   t.Begin("Move a pending order: SL/TP lines, freeze (OP-16)");
   SSymbolSpec s;
   TfFx(s);
   SQuote q;
   TfQuote(q, 1.10000, 1.10010);
   SOrder o;
   TfBuyStop(o);
   SOrder moved;
   SResult r;
   bool ok = CPlanner::MovePending(o, LINEROLE_SL, 1.09900, q, s, moved, r);
   ASSERT_TRUE("SL farther accepted", ok);
   ASSERT_NEAR("only SL changed: SL", moved.sl, 1.09900, 1e-12);
   ASSERT_NEAR("only SL changed: entry", moved.price, 1.10200, 1e-12);
   ASSERT_NEAR("only SL changed: TP", moved.tp, 1.10400, 1e-12);
   ASSERT_FALSE("SL above the entry refused", CPlanner::MovePending(o, LINEROLE_SL, 1.10250, q, s, moved, r));
   ASSERT_CONTAINS("SL refusal", r.message, "SL must be below the entry for a Buy Stop");
   ASSERT_FALSE("TP below the entry refused", CPlanner::MovePending(o, LINEROLE_TP, 1.10150, q, s, moved, r));
   ASSERT_CONTAINS("TP refusal", r.message, "TP on wrong side");
   ok = CPlanner::MovePending(o, LINEROLE_TP, 1.10600, q, s, moved, r);
   ASSERT_NEAR("TP moved", moved.tp, 1.10600, 1e-12);
   s.stopsLevel = 10;
   ASSERT_FALSE("SL inside the stops level refused", CPlanner::MovePending(o, LINEROLE_SL, 1.10195, q, s, moved, r));
   ASSERT_CONTAINS("stops refusal", r.message, "SL too close to the entry");
   s.stopsLevel = 0;
   s.freezeLevel = 20;
   o.price = 1.10025;
   o.sl = 1.09900;
   o.tp = 0.0;
   ASSERT_FALSE("order inside the freeze level refused", CPlanner::MovePending(o, LINEROLE_SL, 1.09800, q, s, moved, r));
   ASSERT_CONTAINS("freeze refusal", r.message, "within the freeze level (20 pts) of Ask");
   o.kind = KIND_MARKET;
   ASSERT_FALSE("not a pending order", CPlanner::MovePending(o, LINEROLE_SL, 1.09800, q, s, moved, r));
  }

//+------------------------------------------------------------------+
void RunPlannerTests(CTestRunner &t)
  {
   TestV19(t);
   TestV20(t);
   TestV23(t);
   TestRiskFreeSell(t);
   TestRiskFreeModes(t);
   TestRiskFreeSkips(t);
   TestMarketPlanAutoRR(t);
   TestMarketPlanTpModes(t);
   TestPendingPlan(t);
   TestSizeLimits(t);
   TestMovePendingEntry(t);
   TestMovePendingLevels(t);
  }

#endif // RD_TESTS_PLANNER_MQH
