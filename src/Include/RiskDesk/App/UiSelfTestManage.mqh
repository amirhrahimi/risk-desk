// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestManage.mqh                              |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : the manage suite of the self-test (phase P6,           |
//|           run-uitest.ps1 -Suite manage). Clicks Risk Free, Half  |
//|           Close, Chart Close and Full Close through the same     |
//|           event handlers a user triggers, on REAL test positions |
//|           opened through the gateway, and checks T-16, T-17,     |
//|           T-18, T-19, T-32 (one chart, positions on several      |
//|           symbols), on netting accounts T-30, the F-28           |
//|           confirmations and both scopes.                         |
//| Safety : as the trade suite (App/UiSelfTestTrade.mqh): rule R13  |
//|          (demo accounts only, checked by TradeStart before       |
//|          anything is sent); minimum-lot test positions (3 x for  |
//|          T-17), each within about 1 % of the balance; magic      |
//|          RD_UITEST_MAGIC for "RiskDesk" positions and            |
//|          RD_UITEST_MAGIC2 for a "manual" one; every test         |
//|          position and order closed / deleted again, also those of|
//|          an aborted earlier run. When anyone else's trades are on|
//|          the chart symbol (or the account), the chart buttons    |
//|          (Full Close) act on the test's own trades only (tool    |
//|          scope) and the "manual trade" part is not run, so no    |
//|          other trade is ever touched.                            |
//|          Part of CUiSelfTest; included at the end of             |
//|          App/UiSelfTest.mqh. This file: dispatch, helpers, T-16, |
//|          T-17; T-18, T-19, T-32, T-30: UiSelfTestManageClose.mqh.|
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTMANAGE_MQH
#define RD_APP_UISELFTESTMANAGE_MQH

//+------------------------------------------------------------------+
void CUiSelfTest::StepManage(const uint now)
  {
   bool trade = m_tradeOk && !m_marketClosed;
   bool hedge = m_gw.IsHedging();
   bool done = true;
   switch(m_step)
     {
      case 0:
        {
         SQuote q;
         if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
            return;   // wait for a first quote, at most 15 s
         TradeStart();
         if(m_tradeOk && m_marketClosed)
            Line("INFO " + _Symbol + " is outside its trading sessions - the manage steps are skipped");
         if(m_tradeOk && !m_marketClosed)
            MgStart();
         break;
        }
      case 1:
         if(trade && hedge)
            MgT16Open();
         break;
      case 2:
         if(trade && hedge)
            done = MgT16Wait(now);
         break;
      case 3:
         if(trade && hedge)
            MgT16Again();
         break;
      case 4:
         if(trade)
            MgT17();
         break;
      case 5:
         if(trade)
            MgT18();
         break;
      case 6:
         if(trade)
            MgT19Open();
         break;
      case 7:
         if(trade)
            MgT19Close();
         break;
      case 8:
         if(trade && !hedge)
            MgT30Open();
         break;
      case 9:
         if(trade && !hedge)
            done = MgT30Wait(now);
         break;
      default:
         if(m_tradeOk)
            MgCleanup("end of the test");
         TradeEnd();
         Finish();
         return;
     }
   if(done)
      m_step++;
  }

//====================================================================
// Helpers
//====================================================================

bool CUiSelfTest::MgIsTest(const long magic) const
  {
   return magic == RD_UITEST_MAGIC || magic == RD_UITEST_MAGIC2;
  }

// Positions (and pending orders) of anyone but the test on 'symbol' ("" = the whole account).
// A list that fails counts as someone else's, so the test stays in tool scope.
int CUiSelfTest::MgOthers(const string symbol, const bool orders)
  {
   STradeFilter f;
   f.Reset();
   f.symbol = symbol;
   f.includeStopLimit = true;
   SPosition pos[];
   SResult r;
   if(!m_gw.ListPositions(f, pos, r))
      return 1;
   int n = 0;
   for(int i = 0; i < ArraySize(pos); i++)
      if(!MgIsTest(pos[i].magic))
         n++;
   if(!orders)
      return n;
   SOrder ord[];
   if(!m_gw.ListPending(f, ord, r))
      return n + 1;
   for(int j = 0; j < ArraySize(ord); j++)
      if(!MgIsTest(ord[j].magic))
         n++;
   return n;
  }

// The scopes and Risk Free mode the checks expect: the defaults, limited to the
// test's own trades where someone else's are there.
void CUiSelfTest::MgScopes()
  {
   m_cfg.scopeChartOps = m_mgOthersSym ? SCOPE_TOOL_ON_SYMBOL : SCOPE_ALL_ON_SYMBOL;
   m_cfg.scopeFullClose = m_mgOthersAcc ? SCOPE_TOOL_ACCOUNT : SCOPE_ALL_ACCOUNT;
   m_cfg.riskFreeMode = RF_SPREAD_COMMISSION;
   m_cfg.partialIndivisible = INDIV_SKIP;
  }

//+------------------------------------------------------------------+
//| Setup after TradeStart: earlier runs cleaned up (both magics),   |
//| someone else's trades looked for, the other symbols chosen.      |
//+------------------------------------------------------------------+
void CUiSelfTest::MgStart()
  {
   MgCleanup("left by an earlier run");
   m_mgOthersSym = MgOthers(_Symbol, false) > 0;
   m_mgOthersAcc = MgOthers("", true) > 0;
   if(m_mgOthersSym)
      Line("INFO someone else's positions are on " + _Symbol + ": Risk Free / Half Close / Chart Close act on the test's " +
           "own positions only (tool scope), the 'manual trade' part of T-18 is not run");
   if(m_mgOthersAcc)
      Line("INFO someone else's positions or orders are on this account: Full Close acts on the test's own only (tool scope)");
   MgScopes();
   m_mgSym2 = MgPickSymbol("", "");
   m_mgSym3 = (m_mgSym2 != "") ? MgPickSymbol(m_mgSym2, "") : "";
   Line("setup (manage): magic " + IntegerToString(RD_UITEST_MAGIC) + " for RiskDesk trades, " +
        IntegerToString(RD_UITEST_MAGIC2) + " for a 'manual' one; other symbols: " +
        (m_mgSym2 != "" ? m_mgSym2 : "none") + ", " + (m_mgSym3 != "" ? m_mgSym3 : "none") + "; " +
        (m_gw.IsHedging() ? "hedging" : "netting") + " account");
  }

//+------------------------------------------------------------------+
//| Close every test position (both magics) and delete every test    |
//| order on the account.                                            |
//+------------------------------------------------------------------+
void CUiSelfTest::MgCleanup(const string why)
  {
   STradeFilter f;
   f.Reset();
   f.includeStopLimit = true;
   SPosition pos[];
   SOrder ord[];
   SResult r;
   int n = 0;
   int closed = 0;
   int deleted = 0;
   if(m_gw.ListPositions(f, pos, r))
      for(int i = 0; i < ArraySize(pos); i++)
        {
         if(!MgIsTest(pos[i].magic))
            continue;
         n++;
         STradeOutcome out;
         SResult cr;
         if(m_gw.ClosePosition(pos[i].ticket, 0.0, out, cr))
            closed++;
         else
            Line("WARN cleanup: " + RdTicketText(pos[i].ticket) + " not closed: " + cr.message);
        }
   if(m_gw.ListPending(f, ord, r))
      for(int j = 0; j < ArraySize(ord); j++)
        {
         if(!MgIsTest(ord[j].magic))
            continue;
         SResult dr;
         if(m_gw.DeletePending(ord[j].ticket, dr))
            deleted++;
        }
   if(n > 0 || deleted > 0)
      Line("cleanup (" + why + "): " + IntegerToString(closed) + " of " + IntegerToString(n) + " test position(s) closed" +
           (deleted > 0 ? ", " + IntegerToString(deleted) + " order(s) deleted" : ""));
   m_ctl.Refresh();
  }

// The test SL distance on any symbol, as TradeStart's: 0.25 % of the price, at least
// 2 x (stops + freeze) + 3 x spread + 10 ticks.
double CUiSelfTest::MgDist(const SSymbolSpec &s, const SQuote &q) const
  {
   double tick = RdTick(s);
   double d = MathMax(0.0025 * q.bid, 2.0 * (s.stopsLevel + s.freezeLevel) * s.point + 3.0 * (q.ask - q.bid) + 10.0 * tick);
   return MathCeil(d / tick - 1e-9) * tick;
  }

//+------------------------------------------------------------------+
//| A test position through the gateway (not the panel): 'lots' with |
//| an SL at the test distance, no TP, magic 'magic'. Returns the    |
//| position ticket (0 = not opened, said in an INFO line).          |
//+------------------------------------------------------------------+
ulong CUiSelfTest::MgOpen(const string sym, const ESide side, const double lots, const long magic, double &price)
  {
   price = 0.0;
   SSymbolSpec s;
   SResult sr;
   SQuote q;
   if(!CSymbolSpec::Read(sym, s, sr) || !CMarket::Quote(sym, q))
     {
      Line("INFO test " + RdSideText(side) + " on " + sym + " not opened: " + (sr.message != "" ? sr.message : "no quote"));
      return 0;
     }
   double d = MgDist(s, q);
   double sl = (side == SIDE_BUY) ? RdRoundPriceDown(s, q.bid - d) : RdRoundPriceUp(s, q.ask + d);
   SGatewaySettings gs;
   m_cfg.Gateway(gs);
   gs.magic = magic;
   m_gw.Configure(gs);
   STradeOutcome out;
   SResult r;
   bool ok = m_gw.OpenMarket(sym, side, lots, sl, 0.0, out, r);
   m_cfg.Gateway(gs);
   m_gw.Configure(gs);
   if(!ok)
     {
      Line("INFO test " + RdSideText(side) + " " + RdFormatLots(s, lots) + " " + sym + " (magic " + IntegerToString(magic) +
           ") not opened: " + r.message);
      return 0;
     }
   price = out.price;
   return out.ticket;
  }

//+------------------------------------------------------------------+
//| Another Market Watch symbol for T-18/T-19: tradeable now (full   |
//| trade mode, market orders with SL, a fresh quote, in session),   |
//| its minimum lot within 1 % of the balance at the test SL distance|
//| and a quarter of the free margin. "" = none.                     |
//+------------------------------------------------------------------+
string CUiSelfTest::MgPickSymbol(const string not1, const string not2)
  {
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   double base = Base();
   for(int i = 0; i < SymbolsTotal(true); i++)
     {
      string sym = SymbolName(i, true);
      if(sym == _Symbol || sym == not1 || sym == not2)
         continue;
      SSymbolSpec os;
      SResult sr;
      SQuote oq;
      if(!CSymbolSpec::Read(sym, os, sr) || os.tradeMode != SYMBOL_TRADE_MODE_FULL || !RdSymbolAcceptsKind(os, KIND_MARKET) ||
         !RdSymbolAcceptsSl(os) || !CMarket::Quote(sym, oq) || CMarket::IsStale(oq, 300))
         continue;
      bool known = false;
      if(!CMarket::InSession(sym, RdServerTime(), known) && known)
         continue;
      double sl = RdRoundPriceDown(os, oq.bid - MgDist(os, oq));
      double loss = 0.0;
      SResult lr;
      double need = 0.0;
      SResult mr;
      if(!(sl > 0.0) || !m_money.LossPerLot(os, acc.currency, SIDE_BUY, oq.ask, sl, loss, lr) ||
         os.volMin * (loss + MathMax(0.0, m_cfg.commissionPerLot)) > 0.01 * base ||
         !m_money.MarginFor(os, SIDE_BUY, os.volMin, oq.ask, need, mr) || need > 0.25 * acc.freeMargin)
         continue;
      return sym;
     }
   return "";
  }

// The T-16 positions: two buys, then two sells.
void CUiSelfTest::MgT16Tickets(ulong &t[])
  {
   ArrayResize(t, 0);
   for(int i = 0; i < ArraySize(m_mgBuy); i++)
     {
      ArrayResize(t, ArraySize(t) + 1);
      t[ArraySize(t) - 1] = m_mgBuy[i];
     }
   for(int j = 0; j < ArraySize(m_mgSell); j++)
     {
      ArrayResize(t, ArraySize(t) + 1);
      t[ArraySize(t) - 1] = m_mgSell[j];
     }
  }

// SL of each ticket now (0 when it has none or is gone).
void CUiSelfTest::MgSls(const ulong &t[], double &sl[])
  {
   int n = ArraySize(t);
   ArrayResize(sl, n);
   for(int i = 0; i < n; i++)
     {
      SPosition p;
      sl[i] = m_gw.SelectPosition(t[i], p) ? p.sl : 0.0;
     }
  }

// F-11 AC2: no SL moved against its position (buy: lower, sell: higher or removed).
bool CUiSelfTest::MgNotLoosened(const ulong &t[], const double &before[], string &why)
  {
   why = "";
   for(int i = 0; i < ArraySize(t); i++)
     {
      SPosition p;
      if(!(before[i] > 0.0) || !m_gw.SelectPosition(t[i], p))
         continue;
      bool worse = (p.side == SIDE_BUY) ? (!(p.sl > 0.0) || RdPriceLt(m_ts, p.sl, before[i])) :
                   (!(p.sl > 0.0) || RdPriceGt(m_ts, p.sl, before[i]));
      if(worse)
         why = RdJoin(why, RdTicketText(t[i]) + " " + RdFormatPrice(m_ts, before[i]) + " -> " + RdFormatPrice(m_ts, p.sl), ", ");
     }
   return why == "";
  }

// Money of a one-tick move for 1 lot from the raw valuation (BC-05), for the commission distance.
double CUiSelfTest::MgPerTick(const ESide side, const double open)
  {
   double tick = RdTick(m_ts);
   double far = (side == SIDE_BUY) ? open - 1000.0 * tick : open + 1000.0 * tick;
   if(!(far > 0.0))
      return 0.0;
   return ExpectedLoss(side, open, far) / 1000.0;
  }

//+------------------------------------------------------------------+
//| 04 section 9 target for RF_SPREAD_COMMISSION at this quote,      |
//| composed here: open +/- (spread + commission distance + extra).  |
//+------------------------------------------------------------------+
double CUiSelfTest::MgRfTarget(const SPosition &p, const SQuote &q)
  {
   double tick = RdTick(m_ts);
   double comm = 0.0;
   if(m_cfg.commissionPerLot > 0.0)
     {
      double perTick = MgPerTick(p.side, p.open);
      if(perTick > 0.0)
         comm = m_cfg.commissionPerLot / perTick * tick;
     }
   double off = (q.ask - q.bid) + comm + m_cfg.riskFreeExtraPoints * m_ts.point;
   return (p.side == SIDE_BUY) ? RdRoundPriceUp(m_ts, p.open + off) : RdRoundPriceDown(m_ts, p.open - off);
  }

// Risk Free would move this position even if the price first went 'margin' against it.
bool CUiSelfTest::MgRfReady(const SPosition &p, const SQuote &q, const double margin, SRiskFreeResult &rf)
  {
   SQuote q2 = q;
   double shift = (p.side == SIDE_BUY) ? -margin : margin;
   q2.bid = RdNormalizePrice(m_ts, q.bid + shift);
   q2.ask = RdNormalizePrice(m_ts, q.ask + shift);
   SRiskFreeInput in;
   in.Reset();
   in.side = p.side;
   in.open = p.open;
   in.sl = p.sl;
   in.tp = p.tp;
   in.volume = p.volume;
   in.tickValue = MgPerTick(p.side, p.open);
   SPlanSettings ps;
   m_cfg.Plan(ps);
   SResult r;
   return CPlanner::RiskFree(in, q2, m_ts, ps, rf, r);
  }

// The panel suite: how many trades a management button would act on now (-1 = cannot tell).
int CUiSelfTest::ManageScopeCount(const EPanelButton b)
  {
   STradeFilter f;
   f.Reset();
   if(b == PB_FULLCLOSE)
      f.toolOnly = (m_cfg.scopeFullClose == SCOPE_TOOL_ACCOUNT);
   else
     {
      f.symbol = _Symbol;
      f.toolOnly = (m_cfg.scopeChartOps == SCOPE_TOOL_ON_SYMBOL);
     }
   f.includeStopLimit = true;
   SPosition pos[];
   SOrder ord[];
   SResult r;
   if(!m_gw.ListPositions(f, pos, r))
      return -1;
   int n = ArraySize(pos);
   if(b == PB_FULLCLOSE && m_cfg.fullCloseAlsoPending)
     {
      if(!m_gw.ListPending(f, ord, r))
         return -1;
      n += ArraySize(ord);
     }
   return n;
  }

//====================================================================
// T-16 Risk Free (hedging accounts; netting: T-30)
//====================================================================

//+------------------------------------------------------------------+
//| Part 1: two buys and two sells of the minimum lot, Risk Free at  |
//| once. As a rule none is far enough in profit yet: each is listed |
//| with its reason, no SL moves against its position, and "n moved" |
//| is the number of SLs that changed.                               |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT16Open()
  {
   MgScopes();
   ArrayResize(m_mgBuy, 0);
   ArrayResize(m_mgSell, 0);
   m_mgMoved = 0;
   double price = 0.0;
   for(int i = 0; i < 2; i++)
     {
      ulong b = MgOpen(_Symbol, SIDE_BUY, m_ts.volMin, RD_UITEST_MAGIC, price);
      if(b > 0)
        {
         ArrayResize(m_mgBuy, ArraySize(m_mgBuy) + 1);
         m_mgBuy[ArraySize(m_mgBuy) - 1] = b;
        }
      ulong s = MgOpen(_Symbol, SIDE_SELL, m_ts.volMin, RD_UITEST_MAGIC, price);
      if(s > 0)
        {
         ArrayResize(m_mgSell, ArraySize(m_mgSell) + 1);
         m_mgSell[ArraySize(m_mgSell) - 1] = s;
        }
     }
   if(ArraySize(m_mgBuy) < 2 || ArraySize(m_mgSell) < 2)
     {
      Check(false, "T-16 setup", "test positions opened: " + IntegerToString(ArraySize(m_mgBuy)) + " buy(s), " +
            IntegerToString(ArraySize(m_mgSell)) + " sell(s) of 2 each");
      MgCleanup("after the T-16 setup");
      ArrayResize(m_mgBuy, 0);
      ArrayResize(m_mgSell, 0);
      return;
     }
   ulong all[];
   MgT16Tickets(all);
   double before[];
   MgSls(all, before);
   ClickButton(PB_RISKFREE);
   string st = m_status.Text();
   double after[];
   MgSls(all, after);
   int changed = 0;
   bool listed = true;
   for(int k = 0; k < ArraySize(all); k++)
     {
      if(!RdPriceEq(m_ts, after[k], before[k]))
         changed++;
      if(StringFind(st, RdTicketText(all[k])) < 0)
         listed = false;
     }
   string why = "";
   bool kept = MgNotLoosened(all, before, why);
   bool form = StringFind(st, "Risk-free on " + _Symbol + ": " + IntegerToString(changed) + " moved") == 0;
   Check(form && listed && kept && m_status.Severity() != SEV_ERROR, "T-16 at once",
         IntegerToString(changed) + " SL(s) changed, every position listed " + RdBoolText(listed) + ", none loosened " +
         RdBoolText(kept) + (why != "" ? " (" + why + ")" : "") + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   Shot("t16_at_once");
   m_mgWaitFrom = GetTickCount();
   Line("T-16: waiting up to " + IntegerToString(RD_UITEST_RF_S) + " s for the buys or the sells to be far enough in profit");
  }

//+------------------------------------------------------------------+
//| Part 2 (waits): once both positions of one side would be moved,  |
//| the second gets a break-even SL by hand ("already BE", a buffer  |
//| beyond the target), then                                         |
//| Risk Free: 1 moved (SL = open +/- (spread + commission distance) |
//| at the click), 1 already protected, the other side's two skipped |
//| with their reason; no SL loosened; screenshot "riskfree".        |
//+------------------------------------------------------------------+
bool CUiSelfTest::MgT16Wait(const uint now)
  {
   if(ArraySize(m_mgBuy) < 2 || ArraySize(m_mgSell) < 2)
      return true;
   if((uint)(now - m_mgWaitFrom) > (uint)RD_UITEST_RF_S * 1000)
     {
      Line("INFO T-16: in " + IntegerToString(RD_UITEST_RF_S) + " s neither the buys nor the sells got far enough in profit " +
           "(spread + stops level + a tick beyond the open price) - the 'moved' part is not checked in this run");
      return true;
     }
   SQuote q;
   if(!FreshQuote(q))
      return false;
   // Risk Free recomputes the target with the spread at the click (04 section 9): the hand-set
   // break-even SL lies 'buffer' beyond it, so a spread that widens a little meanwhile does not
   // make the click tighten it (A5, 2026-11-12: 1 -> 4 pts). Ready with twice that, so the SL is
   // still valid when it is set.
   double buffer = MathMax(5.0 * RdTick(m_ts), q.ask - q.bid);
   for(int side = 0; side < 2; side++)
     {
      ulong t1 = (side == 0) ? m_mgBuy[0] : m_mgSell[0];
      ulong t2 = (side == 0) ? m_mgBuy[1] : m_mgSell[1];
      SPosition p1, p2;
      if(!m_gw.SelectPosition(t1, p1) || !m_gw.SelectPosition(t2, p2))
         continue;
      SRiskFreeResult rf1, rf2;
      if(!MgRfReady(p1, q, 2.0 * buffer, rf1) || !MgRfReady(p2, q, 2.0 * buffer, rf2))
         continue;
      double be = (p2.side == SIDE_BUY) ? RdRoundPriceDown(m_ts, rf2.target + buffer) : RdRoundPriceUp(m_ts, rf2.target - buffer);
      SResult mr;
      if(!m_gw.ModifyPositionSLTP(t2, be, p2.tp, mr))
        {
         Line("INFO T-16: break-even SL on " + RdTicketText(t2) + " not set (" + mr.message + ") - waiting on");
         return false;
        }
      ulong all[];
      MgT16Tickets(all);
      double before[];
      MgSls(all, before);
      SQuote q0;
      FreshQuote(q0);
      ClickButton(PB_RISKFREE);
      SQuote q1;
      FreshQuote(q1);
      string st = m_status.Text();
      SPosition a1, a2;
      m_gw.SelectPosition(t1, a1);
      m_gw.SelectPosition(t2, a2);
      if(RdPriceEq(m_ts, a1.sl, p1.sl))
        {
         Line("INFO T-16: the price went back during the click ('" + st + "') - waiting on");
         return false;
        }
      double want0 = MgRfTarget(p1, q0);
      double want1 = MgRfTarget(p1, q1);
      bool slOk = RdPriceEq(m_ts, a1.sl, want0) || RdPriceEq(m_ts, a1.sl, want1);
      bool protOk = RdPriceEq(m_ts, a2.sl, be);
      string why = "";
      bool kept = MgNotLoosened(all, before, why);
      bool counts = StringFind(st, ": 1 moved") > 0 && StringFind(st, "1 already protected") > 0 &&
                    (StringFind(st, "not in profit") > 0 || StringFind(st, "not enough profit") > 0) &&
                    StringFind(st, RdTicketText(t1) + " SL ") >= 0 && m_status.Severity() == SEV_WARN;
      bool shot = !m_cfg.autoScreenshot || (m_state.lastShot != "" && FileIsExist(m_state.lastShot) &&
                  StringFind(m_state.lastShot, "_riskfree_" + IntegerToString((long)t1)) > 0);
      Check(slOk && protOk && kept && counts && shot, "T-16 risk free",
            RdSideText(p1.side) + " " + RdTicketText(t1) + " @" + RdFormatPrice(m_ts, p1.open) + ": SL " +
            RdFormatPrice(m_ts, p1.sl) + " -> " + RdFormatPrice(m_ts, a1.sl) + " (open " + (p1.side == SIDE_BUY ? "+" : "-") +
            " spread: " + RdFormatPrice(m_ts, want0) + " / " + RdFormatPrice(m_ts, want1) + " at spreads " +
            RdNum(q0.ask - q0.bid, m_ts.digits) + " / " + RdNum(q1.ask - q1.bid, m_ts.digits) + "), " + RdTicketText(t2) +
            " kept at its break-even SL " + RdFormatPrice(m_ts, be) + " " + RdBoolText(protOk) + ", none loosened " + RdBoolText(kept) + (why != "" ? " (" + why + ")" : "") +
            ", screenshot " + RdBoolText(shot) + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
      Shot("t16_riskfree");
      m_mgMoved = t1;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Part 3: Risk Free again: the moved position is now "already      |
//| protected" (or tightened further if the spread widened; never    |
//| loosened). Then every test position is closed.                   |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT16Again()
  {
   if(m_mgMoved > 0)
     {
      ulong all[];
      MgT16Tickets(all);
      double before[];
      MgSls(all, before);
      SPosition m0, m1;
      m_gw.SelectPosition(m_mgMoved, m0);
      ClickButton(PB_RISKFREE);
      string st = m_status.Text();
      m_gw.SelectPosition(m_mgMoved, m1);
      string why = "";
      bool kept = MgNotLoosened(all, before, why);
      bool same = RdPriceEq(m_ts, m1.sl, m0.sl);
      bool ok = kept && ((same && StringFind(st, RdTicketText(m_mgMoved) + " already at SL") >= 0) ||
                         (!same && StringFind(st, RdTicketText(m_mgMoved) + " SL ") >= 0));
      Check(ok, "T-16 again", RdTicketText(m_mgMoved) + " SL " + RdFormatPrice(m_ts, m0.sl) + " -> " +
            RdFormatPrice(m_ts, m1.sl) + ", none loosened " + RdBoolText(kept) + (why != "" ? " (" + why + ")" : "") +
            ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
     }
   MgCleanup("after T-16");
   ArrayResize(m_mgBuy, 0);
   ArrayResize(m_mgSell, 0);
  }

//====================================================================
// T-17 Half Close
//====================================================================

//+------------------------------------------------------------------+
//| A buy of 3 x the minimum lot and (hedging) a sell of the minimum |
//| lot. InpConfirmHalfClose answered No: nothing changes; Yes: the  |
//| buy keeps the 04 section 10 rest of 3 x min (2 x min, Q23; named |
//| when MT4 gives it a new ticket, BC-16; SL kept), the sell skipped|
//| as indivisible (amber, with the reason). 50 % = the input.       |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT17()
  {
   MgScopes();
   bool hedge = m_gw.IsHedging();
   double pct = m_cfg.partialClosePct;
   double big = 0.0;
   SPlanSettings plan;
   m_cfg.Plan(plan);
   SPartialClose pc;
   SResult pr;
   // the split itself is unit-tested (V-18, Q23); here: that the click does exactly that
   bool divisible = RdFloorVolume(m_ts, 3.0 * m_ts.volMin, big) && CRiskMath::PartialClose(big, m_ts, plan, pc, pr);
   double wantClose = pc.closeVolume;
   double wantRest = pc.remainVolume;
   if(!divisible)
     {
      Line("INFO T-17: " + RdFormatLots(m_ts, big) + " lot cannot be split at " + RdFormatCapPct(pct) + " on this grid - skipped");
      return;
     }
   double price = 0.0;
   ulong pb = MgOpen(_Symbol, SIDE_BUY, big, RD_UITEST_MAGIC, price);
   ulong ps = hedge ? MgOpen(_Symbol, SIDE_SELL, m_ts.volMin, RD_UITEST_MAGIC, price) : 0;
   SPosition b0;
   if(pb == 0 || (hedge && ps == 0) || !m_gw.SelectPosition(pb, b0))
     {
      Check(false, "T-17 setup", "test positions not opened (buy " + RdTicketText(pb) + ", sell " + RdTicketText(ps) + ")");
      MgCleanup("after the T-17 setup");
      return;
     }
   string closeText = RdFormatLots(m_ts, wantClose);

   //--- F-28: answered No
   m_cfg.confirmHalfClose = true;
   m_cmd.SetTestConfirm(RD_CONFIRM_NO);
   ClickButton(PB_HALF);
   string st = m_status.Text();
   string conf = m_cmd.LastConfirm();
   SPosition b1;
   bool still = m_gw.SelectPosition(pb, b1) && RdVolEq(b1.volume, big);
   Check(still && m_status.Severity() == SEV_WARN && StringFind(st, "Half Close cancelled - nothing was sent") == 0 &&
         StringFind(conf, "Close " + RdFormatCapPct(pct) + " of 1 position on " + _Symbol + " (" + closeText + " lot)?") == 0 &&
         (!hedge || StringFind(conf, "cannot be split") > 0), "F-28 Half Close answered No",
         "buy still " + RdFormatLots(m_ts, big) + " lot " + RdBoolText(still) + ", dialog '" + conf + "', status '" + st + "'");

   //--- answered Yes
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   ClickButton(PB_HALF);
   st = m_status.Text();
   SPosition arr[];
   int n = TestPositions(arr);
   double buyVol = 0.0;
   ulong rest = 0;
   double restSl = 0.0;
   bool sellKept = !hedge;
   for(int i = 0; i < n; i++)
     {
      if(arr[i].side == SIDE_BUY)
        {
         buyVol += arr[i].volume;
         rest = arr[i].ticket;
         restSl = arr[i].sl;
        }
      else
         if(arr[i].ticket == ps && RdVolEq(arr[i].volume, m_ts.volMin))
            sellKept = true;
     }
   bool volOk = RdVolEq(buyVol, wantRest);
   bool slOk = RdPriceEq(m_ts, restSl, b0.sl);
   bool restNamed = (rest == pb) || StringFind(st, "is now " + RdTicketText(rest)) > 0;
   bool formOk = StringFind(st, "Half-closed 1 position on " + _Symbol + " (" + closeText + " lot)") == 0 &&
                 StringFind(st, RdTicketText(pb) + " " + closeText + " of " + RdFormatLots(m_ts, big) + " lot") > 0;
   bool skipOk = !hedge || (StringFind(st, "1 skipped") > 0 &&
                            StringFind(st, RdTicketText(ps) + " " + RdFormatLots(m_ts, m_ts.volMin) + " lot cannot be split") > 0);
   bool sevOk = m_status.Severity() == (hedge ? SEV_WARN : SEV_OK);
   bool shot = !m_cfg.autoScreenshot || (m_state.lastShot != "" && FileIsExist(m_state.lastShot) &&
               StringFind(m_state.lastShot, "_half_" + IntegerToString((long)pb)) > 0);
   Check(volOk && slOk && restNamed && sellKept && formOk && skipOk && sevOk && shot, "T-17 half close",
         "buy " + RdTicketText(pb) + " " + RdFormatLots(m_ts, big) + " -> " + RdFormatLots(m_ts, buyVol) + " lot (wanted " +
         RdFormatLots(m_ts, wantRest) + ") as " + RdTicketText(rest) + (rest != pb ? " (new ticket, named " + RdBoolText(restNamed) + ")" : "") +
         ", SL kept " + RdBoolText(slOk) + (hedge ? ", sell " + RdTicketText(ps) + " untouched " + RdBoolText(sellKept) : "") +
         ", screenshot " + RdBoolText(shot) + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   Shot("t17_half");
   MgCleanup("after T-17");
   RestoreTp();
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   MgScopes();
  }

#include "UiSelfTestManageClose.mqh"

#endif // RD_APP_UISELFTESTMANAGE_MQH
