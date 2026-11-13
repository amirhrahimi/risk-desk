//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestHalf.mqh                                |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : the half suite of the self-test (run-uitest.ps1 -Suite |
//|           half): Half Close (OP-10, F-12, 04 section 10) over    |
//|           the volume grid of the chart symbol, so the index and  |
//|           FX grids of every broker are covered: even and odd     |
//|           multiples of the minimum lot, repeated clicks down to  |
//|           the minimum lot, the minimum lot with Skip and Close   |
//|           all, 30 % and 70 %, several positions in one click     |
//|           (hedging), a merged position (netting). Every click is |
//|           checked against the split expected in whole grid steps:|
//|           the rest's ticket (MT4: new, BC-16), volume, side,     |
//|           open price, SL and TP; the volume closed and the P/L   |
//|           in the account history; the status text, colour and   |
//|           progress. One INFO line lists the splits of the run.   |
//| Safety : as the manage suite (App/UiSelfTestManage.mqh): rule    |
//|          R13 (TradeStart, demo accounts only), magic             |
//|          RD_UITEST_MAGIC, tool scope when anyone else's positions|
//|          are on the symbol (netting: not run, a test order would |
//|          merge into theirs); a case runs only when its positions |
//|          risk at most 2.5 % of the balance at their SL and need  |
//|          at most half the free margin; every test position is   |
//|          closed after each case. Part of CUiSelfTest; included   |
//|          at the end of App/UiSelfTest.mqh.                       |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTHALF_MQH
#define RD_APP_UISELFTESTHALF_MQH

//+------------------------------------------------------------------+
void CUiSelfTest::StepHalf(const uint now)
  {
   bool run = m_tradeOk && !m_marketClosed && m_hfOk;
   bool hedge = m_gw.IsHedging();
   switch(m_step)
     {
      case 0:
        {
         SQuote q;
         if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
            return;   // wait for a first quote, at most 15 s
         TradeStart();
         if(m_tradeOk && m_marketClosed)
            Line("INFO " + _Symbol + " is outside its trading sessions - the Half Close cases are skipped");
         if(m_tradeOk && !m_marketClosed)
            HfStart();
         break;
        }
      case 1:
         if(run)
           {
            int s[] = {SIDE_BUY};
            int u[] = {2};
            HfCase("H-1 even", s, u, 50.0, INDIV_SKIP, 1);
           }
         break;
      case 2:
         if(run)
           {
            int s[] = {SIDE_SELL};
            int u[] = {3};
            HfCase("H-2 odd", s, u, 50.0, INDIV_SKIP, 1);
           }
         break;
      case 3:
         if(run)
           {
            int s[] = {SIDE_BUY};
            int u[] = {4};
            HfCase("H-3 repeated", s, u, 50.0, INDIV_SKIP, 3);
           }
         break;
      case 4:
         if(run)
           {
            int s[] = {SIDE_BUY};
            int u[] = {1};
            HfCase("H-4 min lot, Close all", s, u, 50.0, INDIV_CLOSE_ALL, 1);
           }
         break;
      case 5:
         if(run)
           {
            int s[] = {SIDE_BUY};
            int u[] = {10};
            HfCase("H-5 30 %", s, u, 30.0, INDIV_SKIP, 1);
           }
         break;
      case 6:
         if(run)
           {
            int s[] = {SIDE_SELL};
            int u[] = {3};
            HfCase("H-6 70 %", s, u, 70.0, INDIV_SKIP, 1);
           }
         break;
      case 7:
         if(run && hedge)
           {
            int s[] = {SIDE_BUY, SIDE_SELL, SIDE_BUY};
            int u[] = {2, 3, 1};
            HfCase("H-7 several", s, u, 50.0, INDIV_SKIP, 1);
           }
         break;
      case 8:
         if(run && hedge)
           {
            int s[] = {SIDE_BUY, SIDE_SELL};
            int u[] = {3, 1};
            HfCase("H-8 several, Close all", s, u, 50.0, INDIV_CLOSE_ALL, 1);
           }
         break;
      case 9:
         if(run && !hedge)
            HfNetMerged();
         break;
      case 10:
         if(run)
           {
            // the owner's path (Q23): 25 -> 13 -> 7 -> 4 -> 2 -> 1 -> cannot be split
            int s[] = {SIDE_BUY};
            int u[] = {25};
            HfCase("H-10 halving to the minimum", s, u, 50.0, INDIV_SKIP, 6);
           }
         break;
      default:
         if(run)
            Line("INFO Half Close splits on " + _Symbol + " (grid " + RdFormatLots(m_ts, m_ts.volStep) + " lot): " + m_hfTable);
         TradeEnd();
         Finish();
         return;
     }
   m_step++;
  }

//+------------------------------------------------------------------+
//| Setup after TradeStart: earlier test positions closed, someone   |
//| else's positions looked for, the grid checked (the cases count in|
//| whole steps from a minimum of one step).                         |
//+------------------------------------------------------------------+
void CUiSelfTest::HfStart()
  {
   m_hfOk = false;
   m_hfTable = "";
   MgCleanup("left by an earlier run");
   m_mgOthersSym = MgOthers(_Symbol, false) > 0;
   m_mgOthersAcc = true;
   if(!RdVolEq(m_ts.volMin, m_ts.volStep))
     {
      Line("INFO " + _Symbol + " has a minimum of " + RdFormatLots(m_ts, m_ts.volMin) + " and a step of " +
           RdFormatLots(m_ts, m_ts.volStep) + " lot: the cases count in whole steps from a minimum of one step - not run " +
           "(the unit tests cover such grids)");
      return;
     }
   if(m_mgOthersSym && !m_gw.IsHedging())
     {
      Line("INFO someone else's position is on " + _Symbol + " on this netting account: a test order would merge into it - " +
           "the Half Close cases are not run");
      return;
     }
   if(m_mgOthersSym)
      Line("INFO someone else's positions are on " + _Symbol + ": Half Close acts on the test's own positions only (tool scope)");
   MgScopes();
   m_hfOk = true;
   Line("setup (half): grid min " + RdFormatLots(m_ts, m_ts.volMin) + " / step " + RdFormatLots(m_ts, m_ts.volStep) + " / max " +
        RdFormatLots(m_ts, m_ts.volMax) + " lot, " + (m_gw.IsHedging() ? "hedging" : "netting") + " account, magic " +
        IntegerToString(RD_UITEST_MAGIC) + ", confirmation off");
  }

// 04 section 10 (Q23) in whole grid steps (min = step): the steps a click closes, the
// nearest to the percentage, a tie keeping the larger part; 0 = cannot be split
// (nothing or everything is nearest).
int CUiSelfTest::HfExpectClose(const int units, const double pct) const
  {
   int c = (int)MathCeil(units * pct / 100.0 - 0.5 - 1e-9);
   return (c >= 1 && c < units) ? c : 0;
  }

double CUiSelfTest::HfLots(const int units) const
  {
   return NormalizeDouble(units * m_ts.volStep, RdLotDigits(m_ts));
  }

// SL distance of the cases: 0.1 % of the price, at least 2 x (stops + freeze) + 3 x spread
// + 10 ticks (tighter than the trade suites': the positions live a few seconds, so whole-lot
// index grids fit the risk cap).
double CUiSelfTest::HfDist(const SQuote &q) const
  {
   double tick = RdTick(m_ts);
   double d = MathMax(0.001 * q.bid, 2.0 * (m_ts.stopsLevel + m_ts.freezeLevel) * m_ts.point + 3.0 * (q.ask - q.bid) +
                      10.0 * tick);
   return MathCeil(d / tick - 1e-9) * tick;
  }

//+------------------------------------------------------------------+
//| The case's positions risk at most 2.5 % of the balance at the    |
//| test SL distance and need at most half the free margin.          |
//+------------------------------------------------------------------+
bool CUiSelfTest::HfAffordable(const string id, const int &units[])
  {
   int total = 0;
   int biggest = 0;
   for(int i = 0; i < ArraySize(units); i++)
     {
      total += units[i];
      biggest = MathMax(biggest, units[i]);
     }
   double lots = HfLots(total);
   if(RdVolGt(HfLots(biggest), m_ts.volMax))
     {
      Line("INFO " + id + ": " + RdFormatLots(m_ts, HfLots(biggest)) + " lot is above the maximum " +
           RdFormatLots(m_ts, m_ts.volMax) + " - skipped");
      return false;
     }
   SQuote q;
   if(!FreshQuote(q))
     {
      Line("INFO " + id + ": no quote - skipped");
      return false;
     }
   double ask = RdNormalizePrice(m_ts, q.ask);
   double loss = ExpectedLoss(SIDE_BUY, ask, RdRoundPriceDown(m_ts, q.bid - HfDist(q)));
   double risk = lots * (loss + MathMax(0.0, m_cfg.commissionPerLot));
   double base = Base();
   double need = 0.0;
   SResult mr;
   m_money.MarginFor(m_ts, SIDE_BUY, lots, ask, need, mr);
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   if(!(loss > 0.0) || !(base > 0.0) || risk > 0.025 * base || need > 0.5 * acc.freeMargin)
     {
      Line("INFO " + id + ": " + RdFormatLots(m_ts, lots) + " lot would risk " + RdNum(risk, 2) +
           (base > 0.0 ? " (" + RdFormatPct(risk / base * 100.0) + ")" : "") + " at the test SL and need " + RdNum(need, 2) +
           " margin of " + RdNum(acc.freeMargin, 2) + " free - skipped");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| A test position through the gateway: 'units' grid steps, SL at   |
//| the test distance, TP at twice it. 0 = not opened (INFO line).   |
//+------------------------------------------------------------------+
ulong CUiSelfTest::HfOpen(const ESide side, const int units)
  {
   SQuote q;
   double lots = HfLots(units);
   if(!FreshQuote(q))
     {
      Line("INFO test " + RdSideText(side) + " " + RdFormatLots(m_ts, lots) + " not opened: no quote");
      return 0;
     }
   double d = HfDist(q);
   double sl = (side == SIDE_BUY) ? RdRoundPriceDown(m_ts, q.bid - d) : RdRoundPriceUp(m_ts, q.ask + d);
   double tp = (side == SIDE_BUY) ? RdRoundPriceUp(m_ts, q.ask + 2.0 * d) : RdRoundPriceDown(m_ts, q.bid - 2.0 * d);
   STradeOutcome out;
   SResult r;
   if(!m_gw.OpenMarket(_Symbol, side, lots, sl, tp, out, r))
     {
      Line("INFO test " + RdSideText(side) + " " + RdFormatLots(m_ts, lots) + " " + _Symbol + " not opened: " + r.message);
      return 0;
     }
   return out.ticket;
  }

// Volume and P/L of the exits on the chart symbol since the case started.
void CUiSelfTest::HfHistory(double &vol, double &pl, SClosedTrade &ct[])
  {
   vol = 0.0;
   pl = 0.0;
   SResult r;
   if(!CHistory::ClosedTrades(_Symbol, m_hfFrom, ct, r))
     {
      ArrayResize(ct, 0);
      return;
     }
   for(int i = 0; i < ArraySize(ct); i++)
     {
      vol += ct[i].volume;
      pl += ct[i].profit;
     }
  }

bool CUiSelfTest::HfFind(const SPosition &arr[], const ulong ticket, SPosition &p) const
  {
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i].ticket == ticket)
        {
         p = arr[i];
         return true;
        }
   return false;
  }

// The rest of a partial close under a new ticket (MT4, BC-16): a position that was not
// there before the click, same side and open price, the expected volume.
ulong CUiSelfTest::HfNewTicket(const SPosition &before[], const SPosition &after[], const SUiHalfPos &was,
                               const double restVol, SPosition &p) const
  {
   for(int i = 0; i < ArraySize(after); i++)
     {
      SPosition old;
      if(HfFind(before, after[i].ticket, old))
         continue;
      if(after[i].side == was.side && RdPriceEq(m_ts, after[i].open, was.open) && RdVolEq(after[i].volume, restVol))
        {
         p = after[i];
         return after[i].ticket;
        }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Opens the case's positions, clicks Half Close 'clicks' times     |
//| (each click checked by HfClick on what is left), closes them.    |
//+------------------------------------------------------------------+
void CUiSelfTest::HfCase(const string id, const int &sides[], const int &units[], const double pct, const EIndivisible indiv,
                         const int clicks)
  {
   int n = ArraySize(units);
   if(n == 0 || ArraySize(sides) != n || !HfAffordable(id, units))
      return;
   MgScopes();
   m_hfFrom = RdServerTime() - 60;
   SUiHalfPos p[];
   ArrayResize(p, n);
   for(int i = 0; i < n; i++)
     {
      ESide side = (ESide)sides[i];
      ulong t = HfOpen(side, units[i]);
      SPosition sp;
      if(t == 0 || !m_gw.SelectPosition(t, sp) || !RdVolEq(sp.volume, HfLots(units[i])))
        {
         Check(false, id + " setup", "test " + RdSideText(side) + " " + RdFormatLots(m_ts, HfLots(units[i])) + " lot " +
               RdTicketText(t) + " not opened as expected");
         CloseTestTrades("after the " + id + " setup");
         RestoreTp();
         MgScopes();
         return;
        }
      p[i].ticket = t;
      p[i].side = sp.side;
      p[i].volume = sp.volume;
      p[i].open = sp.open;
      p[i].sl = sp.sl;
      p[i].tp = sp.tp;
      p[i].units = units[i];
     }
   string split = "";
   for(int c = 0; c < clicks; c++)
      if(!HfClick(id + (clicks > 1 ? " click " + IntegerToString(c + 1) : ""), p, pct, indiv, split))
         break;
   int sp = StringFind(id, " ");
   string tag = (sp > 0) ? StringSubstr(id, 0, sp) : id;   // "H-10"
   m_hfTable = RdJoin(m_hfTable, tag + (MathAbs(pct - 50.0) > 1e-9 ? " " + RdNum(pct, 0) + "%" : "") + " " + split, "; ");
   Shot("half_" + tag);
   CloseTestTrades("after " + id);
   RestoreTp();
   MgScopes();
  }

//+------------------------------------------------------------------+
//| One Half Close click on the test positions 'p' (their state      |
//| before it) and its checks. 'p' is updated to what is left (rest  |
//| tickets followed), 'split' extended ("3 -> 1 + 2"). False when   |
//| the click failed a check (the case stops).                       |
//+------------------------------------------------------------------+
bool CUiSelfTest::HfClick(const string id, SUiHalfPos &p[], const double pct, const EIndivisible indiv, string &split)
  {
   m_cfg.partialClosePct = pct;
   m_cfg.partialIndivisible = indiv;
   m_cfg.confirmHalfClose = false;
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   int n = ArraySize(p);

   //--- what the click should do
   int cut[];
   bool all[];
   ArrayResize(cut, n);
   ArrayResize(all, n);
   double wantVol = 0.0;
   int wantClosed = 0;
   int wantSkipped = 0;
   int wantAll = 0;
   for(int i = 0; i < n; i++)
     {
      cut[i] = HfExpectClose(p[i].units, pct);
      all[i] = (cut[i] == 0 && indiv == INDIV_CLOSE_ALL);
      if(all[i])
         cut[i] = p[i].units;
      if(cut[i] > 0)
        {
         wantClosed++;
         wantVol += HfLots(cut[i]);
        }
      else
         wantSkipped++;
      if(all[i])
         wantAll++;
     }

   //--- the click
   SPosition before[];
   TestPositions(before);
   double vol0 = 0.0, pl0 = 0.0;
   SClosedTrade h0[];
   HfHistory(vol0, pl0, h0);
   ClickButton(PB_HALF);
   string st = m_status.Text();
   ESeverity sev = m_status.Severity();
   string prog = m_cmd.LastProgress();
   SPosition after[];
   TestPositions(after);

   //--- every position
   bool itemsOk = true;
   bool keptTicket = false;
   string items = "";
   string table = "";
   for(int i = 0; i < n; i++)
     {
      string who = RdTicketText(p[i].ticket);
      string vText = RdFormatLots(m_ts, p[i].volume);
      SPosition q;
      bool ok = false;
      string got = "";
      if(cut[i] == 0)
        {
         bool same = HfFind(after, p[i].ticket, q) && RdVolEq(q.volume, p[i].volume) && RdPriceEq(m_ts, q.sl, p[i].sl) &&
                     RdPriceEq(m_ts, q.tp, p[i].tp);
         bool said = StringFind(st, who + " " + vText + " lot cannot be split at " + RdFormatCapPct(pct)) >= 0;
         ok = same && said;
         got = who + " " + vText + " lot kept " + RdBoolText(same) + ", reason given " + RdBoolText(said);
         table = RdJoin(table, vText + " -> kept", ", ");
        }
      else
         if(all[i])
           {
            bool gone = !HfFind(after, p[i].ticket, q);
            bool said = StringFind(st, who + " all " + vText + " lot (cannot be split)") >= 0;
            ok = gone && said;
            got = who + " " + vText + " lot closed whole " + RdBoolText(gone) + ", named " + RdBoolText(said);
            table = RdJoin(table, vText + " -> all", ", ");
            p[i].units = 0;
           }
         else
           {
            int restUnits = p[i].units - cut[i];
            double restVol = HfLots(restUnits);
            string cText = RdFormatLots(m_ts, HfLots(cut[i]));
            ulong rest = 0;
            if(HfFind(after, p[i].ticket, q))
               rest = p[i].ticket;
            else
               rest = HfNewTicket(before, after, p[i], restVol, q);
            bool volOk = rest > 0 && RdVolEq(q.volume, restVol);
            bool keptOk = rest > 0 && q.side == p[i].side && RdPriceEq(m_ts, q.open, p[i].open) && RdPriceEq(m_ts, q.sl, p[i].sl) &&
                          RdPriceEq(m_ts, q.tp, p[i].tp);
            bool said = StringFind(st, who + " " + cText + " of " + vText + " lot") >= 0 &&
                        (rest == 0 || rest == p[i].ticket || StringFind(st, "is now " + RdTicketText(rest)) >= 0);
            ok = volOk && keptOk && said;
            if(rest == p[i].ticket)
               keptTicket = true;
            got = who + " " + vText + " -> " + (rest > 0 ? RdFormatLots(m_ts, q.volume) : "nothing") + " lot (wanted " +
                  RdFormatLots(m_ts, restVol) + ") as " + (rest == p[i].ticket ? "the same ticket" : RdTicketText(rest)) +
                  ", open/SL/TP/side kept " + RdBoolText(keptOk) + ", named " + RdBoolText(said);
            table = RdJoin(table, vText + " -> " + cText + " + " + RdFormatLots(m_ts, restVol), ", ");
            if(rest > 0)
              {
               p[i].ticket = rest;
               p[i].volume = q.volume;
              }
            p[i].units = restUnits;
           }
      itemsOk = itemsOk && ok;
      items = RdJoin(items, (ok ? "" : "WRONG ") + got, "; ");
     }
   // what is left for the next click
   int k = 0;
   for(int i = 0; i < n; i++)
      if(p[i].units > 0)
         p[k++] = p[i];
   ArrayResize(p, k);

   //--- the account history: volume closed, P/L
   double vol1 = 0.0, pl1 = 0.0;
   SClosedTrade h1[];
   for(int w = 0; w < 30; w++)
     {
      HfHistory(vol1, pl1, h1);
      if(MathAbs(vol1 - vol0 - wantVol) < 0.5 * m_ts.volStep || IsStopped())
         break;
      Sleep(100);
     }
   double volDiff = vol1 - vol0;
   double plDiff = pl1 - pl0;
   bool histOk = MathAbs(volDiff - wantVol) < 0.5 * m_ts.volStep;
   bool hasPl = StringFind(st, RdSep() + "P/L ") > 0;
   bool plOk = !hasPl || HasMoney(st, acc, plDiff);
   bool plMissing = wantClosed > 0 && !hasPl;
   if(plMissing)
     {
      string fresh = "";
      for(int i = 0; i < ArraySize(h1); i++)
        {
         bool seen = false;
         for(int j = 0; j < ArraySize(h0) && !seen; j++)
            seen = h0[j].ticket == h1[i].ticket && h0[j].closeTime == h1[i].closeTime && RdVolEq(h0[j].volume, h1[i].volume);
         if(!seen)
            fresh = RdJoin(fresh, RdTicketText(h1[i].ticket) + " " + RdFormatLots(m_ts, h1[i].volume) + " lot P/L " +
                           RdNum(h1[i].profit, 2) + " magic " + IntegerToString(h1[i].magic), ", ");
        }
      Line("INFO " + id + ": no P/L in the status; new exits in the history: " + (fresh != "" ? fresh : "none"));
     }

   //--- status text, colour, progress
   bool headOk = false;
   if(wantClosed == 0)
      headOk = StringFind(st, "Half Close: nothing closed on " + _Symbol + RdSep() + IntegerToString(wantSkipped) + " skipped - ") == 0;
   else
     {
      headOk = StringFind(st, "Half-closed " + IntegerToString(wantClosed) + " position" + (wantClosed == 1 ? "" : "s") + " on " +
                          _Symbol + " (") == 0;
      if(wantSkipped > 0)
         headOk = headOk && StringFind(st, RdSep() + IntegerToString(wantSkipped) + " skipped") > 0;
     }
   ESeverity wantSev = (wantClosed > 0 && wantSkipped == 0 && wantAll == 0) ? SEV_OK : SEV_WARN;
   bool sevOk = (sev == wantSev);
   string wantProg = (wantClosed > 1) ? "Half Close: closing " + IntegerToString(wantClosed) + "/" + IntegerToString(wantClosed) + "..." : "";
   bool progOk = (prog == wantProg);

   bool pass = itemsOk && histOk && plOk && !plMissing && headOk && sevOk && progOk;
   Check(pass, id, items + "; history: " + RdFormatLots(m_ts, volDiff) + " lot closed (wanted " + RdFormatLots(m_ts, wantVol) +
         "), P/L " + RdNum(plDiff, 2) + (hasPl ? " in the status " + RdBoolText(plOk) : (plMissing ? " NOT in the status" : "")) +
         (keptTicket ? " (the rest kept the original ticket)" : "") + "; progress '" + prog + "'" +
         (progOk ? "" : " (wanted '" + wantProg + "')") + "; status " + RdSeverityText(sev) + (sevOk ? "" : " (wanted " +
         RdSeverityText(wantSev) + ")") + (headOk ? "" : " head WRONG") + " '" + st + "'");
   split = RdJoin(split, table, ", ");
   return pass;
  }

//+------------------------------------------------------------------+
//| Netting (BC-10): a buy of 2 steps and one of 1 merge into one    |
//| position of 3; Half Close sends an opposite deal of 1 step (Q23):|
//| the same position keeps 2 at its averaged open price, SL and TP. |
//+------------------------------------------------------------------+
void CUiSelfTest::HfNetMerged()
  {
   const string id = "H-9 merged (netting)";
   int u[] = {3};
   if(!HfAffordable(id, u))
      return;
   MgScopes();
   m_hfFrom = RdServerTime() - 60;
   ulong t1 = HfOpen(SIDE_BUY, 2);
   ulong t2 = (t1 > 0) ? HfOpen(SIDE_BUY, 1) : 0;
   SPosition sp;
   bool merged = t1 > 0 && t2 == t1 && m_gw.SelectPosition(t1, sp) && RdVolEq(sp.volume, HfLots(3));
   if(!merged)
     {
      Check(false, id + " setup", "buys " + RdTicketText(t1) + " and " + RdTicketText(t2) + " did not merge into one position of " +
            RdFormatLots(m_ts, HfLots(3)) + " lot");
      CloseTestTrades("after the " + id + " setup");
      RestoreTp();
      MgScopes();
      return;
     }
   SUiHalfPos p[];
   ArrayResize(p, 1);
   p[0].ticket = t1;
   p[0].side = sp.side;
   p[0].volume = sp.volume;
   p[0].open = sp.open;
   p[0].sl = sp.sl;
   p[0].tp = sp.tp;
   p[0].units = 3;
   string split = "";
   HfClick(id, p, 50.0, INDIV_SKIP, split);
   m_hfTable = RdJoin(m_hfTable, "H-9 merged " + split, "; ");
   Shot("half_H-9");
   CloseTestTrades("after " + id);
   RestoreTp();
   MgScopes();
  }

#endif // RD_APP_UISELFTESTHALF_MQH
