//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestManageClose.mqh                         |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : manage suite steps that close positions: T-18 Chart    |
//|           Close (tool scope, then all on the symbol with a       |
//|           "manual" position), T-19 Full Close (positions on up   |
//|           to three symbols and a pending order), T-32 (the       |
//|           open-risk readout counts every symbol), T-30 on        |
//|           netting accounts (merged position, Half Close reduces, |
//|           Risk Free on the averaged open price). Part of         |
//|           CUiSelfTest; included by App/UiSelfTestManage.mqh      |
//|           (split to stay near ~600 lines). Same safety rules.    |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTMANAGECLOSE_MQH
#define RD_APP_UISELFTESTMANAGECLOSE_MQH

// Money at the SL of a position (04 section 5), valued as RiskDesk does (BC-05).
double CUiSelfTest::MgRisk(const ulong ticket)
  {
   SPosition p;
   SSymbolSpec s;
   SAccountSpec acc;
   SResult r;
   if(!m_gw.SelectPosition(ticket, p) || !(p.sl > 0.0) || !CSymbolSpec::Read(p.symbol, s, r) || !CAccountSpec::Read(acc, r, m_cfg.centMode, m_cfg.centDivisor))
      return 0.0;
   double loss = 0.0;
   if(!m_money.LossPerLot(s, acc.currency, p.side, p.open, p.sl, loss, r))
      return 0.0;
   return (loss + MathMax(0.0, m_cfg.commissionPerLot)) * p.volume;
  }

// Realized P/L (profit + swap + commission of the exits) of these tickets in the history since 'from'.
double CUiSelfTest::MgClosedPl(const ulong &t[], const datetime from, int &found)
  {
   found = 0;
   double pl = 0.0;
   SClosedTrade ct[];
   SResult r;
   if(!CHistory::ClosedTrades("", from, ct, r))
      return 0.0;
   for(int i = 0; i < ArraySize(ct); i++)
      for(int k = 0; k < ArraySize(t); k++)
         if(ct[i].ticket == t[k])
           {
            pl += ct[i].profit;
            found++;
           }
   return pl;
  }

//====================================================================
// T-18 Chart Close
//====================================================================

//+------------------------------------------------------------------+
//| RiskDesk (test magic) buy and sell, a "manual" buy (another      |
//| magic) on the chart symbol, a RiskDesk buy on a second symbol.   |
//| (a) tool scope: the two RiskDesk positions are closed, the       |
//| manual one and the other symbol stay; "Closed 2 of 2 RiskDesk    |
//| positions on EURUSD . P/L x" with x = the history's P/L.         |
//| (b) all on the symbol (the default), InpConfirmChartClose: No    |
//| keeps it, Yes closes the manual one; the other symbol stays.     |
//| Then nothing is left in scope: amber "Chart Close: no ...".      |
//| Netting accounts: one position per symbol, part (b) not run.     |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT18()
  {
   MgScopes();
   bool hedge = m_gw.IsHedging();
   double price = 0.0;
   ulong t1 = MgOpen(_Symbol, SIDE_BUY, m_ts.volMin, RD_UITEST_MAGIC, price);
   ulong t2 = hedge ? MgOpen(_Symbol, SIDE_SELL, m_ts.volMin, RD_UITEST_MAGIC, price) : 0;
   ulong m1 = (hedge && !m_mgOthersSym) ? MgOpen(_Symbol, SIDE_BUY, m_ts.volMin, RD_UITEST_MAGIC2, price) : 0;
   ulong o1 = 0;
   SSymbolSpec os;
   SResult sr;
   if(m_mgSym2 != "" && CSymbolSpec::Read(m_mgSym2, os, sr))
      o1 = MgOpen(m_mgSym2, SIDE_BUY, os.volMin, RD_UITEST_MAGIC, price);
   if(t1 == 0 || (hedge && t2 == 0))
     {
      Check(false, "T-18 setup", "test positions not opened (" + RdTicketText(t1) + ", " + RdTicketText(t2) + ")");
      MgCleanup("after the T-18 setup");
      return;
     }
   Line("T-18 setup: RiskDesk " + RdTicketText(t1) + (t2 > 0 ? " and " + RdTicketText(t2) : "") + " on " + _Symbol +
        (m1 > 0 ? ", manual " + RdTicketText(m1) : "") + (o1 > 0 ? ", RiskDesk " + RdTicketText(o1) + " on " + m_mgSym2 : ""));
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   ulong tools[];
   ArrayResize(tools, (t2 > 0) ? 2 : 1);
   tools[0] = t1;
   if(t2 > 0)
      tools[1] = t2;
   int nt = ArraySize(tools);

   //--- (a) tool scope
   m_cfg.scopeChartOps = SCOPE_TOOL_ON_SYMBOL;
   datetime from = RdServerTime() - 120;
   ClickButton(PB_CHARTCLOSE);
   string st = m_status.Text();
   SPosition p;
   bool closed = !m_gw.SelectPosition(t1, p) && (t2 == 0 || !m_gw.SelectPosition(t2, p));
   bool manualKept = (m1 == 0) || m_gw.SelectPosition(m1, p);
   bool otherKept = (o1 == 0) || m_gw.SelectPosition(o1, p);
   int found = 0;
   double pl = MgClosedPl(tools, from, found);
   string want = "Closed " + IntegerToString(nt) + " of " + IntegerToString(nt) + " RiskDesk position" + (nt == 1 ? "" : "s") +
                 " on " + _Symbol;
   bool plOk = found >= nt && HasMoney(st, acc, pl);
   bool shot = !m_cfg.autoScreenshot || (m_state.lastShot != "" && FileIsExist(m_state.lastShot) &&
               StringFind(m_state.lastShot, "_chartclose_" + IntegerToString(nt == 1 ? (long)t1 : 0) + ".") > 0);
   Check(closed && manualKept && otherKept && StringFind(st, want) == 0 && plOk && m_status.Severity() == SEV_OK && shot,
         "T-18 tool scope", "RiskDesk positions closed " + RdBoolText(closed) + ", manual kept " + RdBoolText(manualKept) +
         ", other symbol kept " + RdBoolText(otherKept) + ", history P/L " + RdMoney(acc, pl) + " (" + IntegerToString(found) +
         " exits), screenshot " + RdBoolText(shot) + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   Shot("t18_chartclose_tool");

   //--- (b) every position on the symbol (the default), confirmed
   if(m1 > 0)
     {
      m_cfg.scopeChartOps = SCOPE_ALL_ON_SYMBOL;
      m_cfg.confirmChartClose = true;
      m_cmd.SetTestConfirm(RD_CONFIRM_NO);
      ClickButton(PB_CHARTCLOSE);
      st = m_status.Text();
      string conf = m_cmd.LastConfirm();
      bool kept = m_gw.SelectPosition(m1, p);
      Check(kept && StringFind(st, "Chart Close cancelled - nothing was sent") == 0 &&
            StringFind(conf, "Close 1 position on " + _Symbol + " (") == 0 && StringFind(conf, "Pending orders stay.") > 0,
            "F-28 Chart Close answered No", "manual " + RdTicketText(m1) + " kept " + RdBoolText(kept) + ", dialog '" + conf +
            "', status '" + st + "'");
      m_cmd.SetTestConfirm(RD_CONFIRM_YES);
      ClickButton(PB_CHARTCLOSE);
      st = m_status.Text();
      bool gone = !m_gw.SelectPosition(m1, p);
      otherKept = (o1 == 0) || m_gw.SelectPosition(o1, p);
      Check(gone && otherKept && StringFind(st, "Closed 1 of 1 position on " + _Symbol) == 0 && m_status.Severity() == SEV_OK,
            "T-18 all on the symbol", "manual " + RdTicketText(m1) + " closed " + RdBoolText(gone) + ", other symbol kept " +
            RdBoolText(otherKept) + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
      m_cfg.confirmChartClose = false;
     }
   else
      Line("INFO T-18: " + (hedge ? "someone else's positions are on " + _Symbol : "netting account (one position per symbol)") +
           " - the 'manual trade' part (scope all on the symbol) is not run");

   //--- nothing left in scope
   MgScopes();
   ClickButton(PB_CHARTCLOSE);
   st = m_status.Text();
   Check(m_status.Severity() == SEV_WARN && StringFind(st, "Chart Close: no ") == 0 && StringFind(st, " on " + _Symbol) > 0,
         "T-18 nothing left", "status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   MgCleanup("after T-18");
   RestoreTp();
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   MgScopes();
  }

//====================================================================
// T-19 Full Close and T-32
//====================================================================

//+------------------------------------------------------------------+
//| RiskDesk positions on the chart symbol and up to two other       |
//| symbols, and a Buy Limit far below the price. The open-risk      |
//| readout is read every 2 s, so the check waits 2.6 s.             |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT19Open()
  {
   MgScopes();
   ArrayResize(m_mgT19, 0);
   m_mgOrder = 0;
   string syms[3];
   syms[0] = _Symbol;
   syms[1] = m_mgSym2;
   syms[2] = m_mgSym3;
   string where = "";
   for(int i = 0; i < 3; i++)
     {
      SSymbolSpec s;
      SResult sr;
      if(syms[i] == "" || !CSymbolSpec::Read(syms[i], s, sr))
         continue;
      double price = 0.0;
      ulong t = MgOpen(syms[i], (i == 2) ? SIDE_SELL : SIDE_BUY, s.volMin, RD_UITEST_MAGIC, price);
      if(t == 0)
         continue;
      int n = ArraySize(m_mgT19);
      ArrayResize(m_mgT19, n + 1);
      m_mgT19[n] = t;
      where = RdJoin(where, syms[i] + " " + RdTicketText(t), ", ");
     }
   SQuote q;
   if(FreshQuote(q))
     {
      double entry = RdRoundPriceDown(m_ts, q.bid - 3.0 * m_dist);
      double sl = RdRoundPriceDown(m_ts, entry - m_dist);
      STradeOutcome out;
      SResult pr;
      if(entry > 0.0 && sl > 0.0 && m_gw.PlacePending(_Symbol, SIDE_BUY, KIND_LIMIT, m_ts.volMin, entry, sl, 0.0, out, pr))
         m_mgOrder = out.ticket;
      else
         Line("INFO T-19: test Buy Limit not placed: " + pr.message);
     }
   Line("T-19 setup: " + IntegerToString(ArraySize(m_mgT19)) + " RiskDesk position(s): " + where +
        (m_mgOrder > 0 ? "; Buy Limit " + RdTicketText(m_mgOrder) + " on " + _Symbol : ""));
   m_nextAt = GetTickCount() + 2600;
  }

//+------------------------------------------------------------------+
//| T-32: the readout counts the positions of every symbol (and the  |
//| order, InpIncludePendingInTotalRisk). T-19: InpConfirmFullClose  |
//| answered No keeps everything ("Close 3 positions on 3 symbols?   |
//| ... Also delete 1 pending order."); Yes closes every position    |
//| and (InpFullCloseAlsoPending) deletes the order, "Closing 3/3..."|
//| shown on the way, summary with the history's P/L; then nothing   |
//| is left: amber "Full Close: no positions on this account".       |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT19Close()
  {
   MgScopes();
   int n = ArraySize(m_mgT19);
   if(n == 0)
     {
      Check(false, "T-19 setup", "no test position could be opened");
      MgCleanup("after the T-19 setup");
      return;
     }
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   string syms[];
   int ns = 0;
   for(int i = 0; i < n; i++)
     {
      SPosition p;
      if(!m_gw.SelectPosition(m_mgT19[i], p))
         continue;
      bool seen = false;
      for(int j = 0; j < ns; j++)
         if(syms[j] == p.symbol)
            seen = true;
      if(!seen)
        {
         ArrayResize(syms, ns + 1);
         syms[ns++] = p.symbol;
        }
     }

   //--- T-32
   m_ctl.Refresh();
   string idle = m_status.IdleText();
   double risk = 0.0;
   for(int k = 0; k < n; k++)
      risk += MgRisk(m_mgT19[k]);
   SOrder o;
   bool hasOrder = m_mgOrder > 0 && m_gw.SelectPending(m_mgOrder, o);
   if(hasOrder && m_cfg.includePendingInTotalRisk)
      risk += OrderRisk(o);
   double base = Base();
   double pct = (base > 0.0) ? risk / base * 100.0 : 0.0;
   if(StringFind(idle, "Open risk ") < 0)
      Line("INFO T-32: the idle readout shows '" + idle + "' instead of the open risk");
   else
      Check(StringFind(idle, "Open risk " + RdFormatPct(pct)) >= 0 || StringFind(idle, "Open risk " + RdFormatPct(pct - 0.005)) >= 0 ||
            StringFind(idle, "Open risk " + RdFormatPct(pct + 0.005)) >= 0, "T-32 open risk",
            IntegerToString(n) + " RiskDesk position(s) on " + IntegerToString(ns) + " symbol(s)" +
            (hasOrder && m_cfg.includePendingInTotalRisk ? " + 1 pending order" : "") + ": " + RdMoney(acc, risk) + " = " +
            RdFormatPct(pct) + " of " + RdMoney(acc, base) + ", readout '" + idle + "'");

   //--- F-28: answered No
   if(!m_mgOthersAcc && MgOthers("", true) > 0)
     {
      m_mgOthersAcc = true;
      MgScopes();
      Line("INFO someone else's trade appeared on the account - Full Close limited to the test's own (tool scope)");
     }
   m_cfg.fullCloseAlsoPending = hasOrder;
   m_cfg.confirmFullClose = true;
   string which = (m_mgOthersAcc ? "RiskDesk " : "") + "position" + (n == 1 ? "" : "s");
   string onSyms = IntegerToString(ns) + " symbol" + (ns == 1 ? "" : "s");
   m_cmd.SetTestConfirm(RD_CONFIRM_NO);
   ClickButton(PB_FULLCLOSE);
   string st = m_status.Text();
   string conf = m_cmd.LastConfirm();
   int open = 0;
   for(int a = 0; a < n; a++)
     {
      SPosition p;
      if(m_gw.SelectPosition(m_mgT19[a], p))
         open++;
     }
   bool orderKept = !hasOrder || m_gw.SelectPending(m_mgOrder, o);
   Check(open == n && orderKept && StringFind(conf, "Close " + IntegerToString(n) + " " + which + " on " + onSyms + "?") == 0 &&
         (!hasOrder || StringFind(conf, "Also delete 1 pending order.") > 0) &&
         StringFind(st, "Full Close cancelled - nothing was sent") == 0 && m_status.Severity() == SEV_WARN,
         "F-28 Full Close answered No", IntegerToString(open) + " of " + IntegerToString(n) + " still open, order kept " +
         RdBoolText(orderKept) + ", dialog '" + conf + "', status '" + st + "'");

   //--- answered Yes
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   datetime from = RdServerTime() - 120;
   ClickButton(PB_FULLCLOSE);
   st = m_status.Text();
   open = 0;
   for(int b = 0; b < n; b++)
     {
      SPosition p;
      if(m_gw.SelectPosition(m_mgT19[b], p))
         open++;
     }
   bool orderGone = !hasOrder || !m_gw.SelectPending(m_mgOrder, o);
   int found = 0;
   double pl = MgClosedPl(m_mgT19, from, found);
   bool formOk = StringFind(st, "Closed " + IntegerToString(n) + " of " + IntegerToString(n) + " " + which + " on " + onSyms) == 0 &&
                 (!hasOrder || StringFind(st, "deleted 1 of 1 pending order") > 0);
   bool plOk = found >= n && HasMoney(st, acc, pl);
   string progress = m_cmd.LastProgress();
   bool progressOk = (n < 2) || progress == "Closing " + IntegerToString(n) + "/" + IntegerToString(n) + "...";
   long shotTicket = (n == 1 && !hasOrder) ? (long)m_mgT19[0] : 0;
   bool shot = !m_cfg.autoScreenshot || (m_state.lastShot != "" && FileIsExist(m_state.lastShot) &&
               StringFind(m_state.lastShot, "_fullclose_" + IntegerToString(shotTicket) + ".") > 0);
   Check(open == 0 && orderGone && formOk && plOk && progressOk && m_status.Severity() == SEV_OK && shot, "T-19 full close",
         IntegerToString(n - open) + " of " + IntegerToString(n) + " closed, order deleted " + RdBoolText(orderGone) +
         ", history P/L " + RdMoney(acc, pl) + " (" + IntegerToString(found) + " exits), last progress '" + progress +
         "', screenshot " + RdBoolText(shot) + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   Shot("t19_fullclose");

   //--- nothing left in scope
   ClickButton(PB_FULLCLOSE);
   st = m_status.Text();
   Check(m_status.Severity() == SEV_WARN &&
         StringFind(st, "Full Close: no " + (m_mgOthersAcc ? "RiskDesk " : "") + "positions on this account") == 0,
         "T-19 nothing left", "status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   MgCleanup("after T-19");
   ArrayResize(m_mgT19, 0);
   RestoreTp();
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   MgScopes();
  }

//====================================================================
// T-30 netting (BC-10)
//====================================================================

//+------------------------------------------------------------------+
//| Two buys of 2 x the minimum lot merge into one position at the   |
//| volume-weighted open price; Half Close sends an opposite deal of |
//| half: the same position keeps the other half and its open price. |
//+------------------------------------------------------------------+
void CUiSelfTest::MgT30Open()
  {
   MgScopes();
   m_mgNet = 0;
   double lot = 0.0;
   if(!RdFloorVolume(m_ts, 2.0 * m_ts.volMin, lot))
      return;
   double p1 = 0.0;
   double p2 = 0.0;
   ulong t1 = MgOpen(_Symbol, SIDE_BUY, lot, RD_UITEST_MAGIC, p1);
   ulong t2 = (t1 > 0) ? MgOpen(_Symbol, SIDE_BUY, lot, RD_UITEST_MAGIC, p2) : 0;
   SPosition p;
   if(t1 == 0 || t2 == 0 || !m_gw.SelectPosition(t1, p))
     {
      Check(false, "T-30 setup", "test buys not opened (" + RdTicketText(t1) + ", " + RdTicketText(t2) + ")");
      MgCleanup("after the T-30 setup");
      return;
     }
   double avg = (p1 > 0.0 && p2 > 0.0) ? (p1 + p2) / 2.0 : 0.0;
   bool merged = (t1 == t2) && RdVolEq(p.volume, 2.0 * lot) && avg > 0.0 && MathAbs(p.open - avg) <= RdTick(m_ts) + 1e-10;
   Check(merged, "T-30 merged", "fills " + RdFormatPrice(m_ts, p1) + " and " + RdFormatPrice(m_ts, p2) + " -> one position " +
         RdTicketText(p.ticket) + " " + RdFormatLots(m_ts, p.volume) + " lot @" + RdFormatPrice(m_ts, p.open) +
         " (average " + RdNum(avg, m_ts.digits + 1) + ")");
   ClickButton(PB_HALF);
   string st = m_status.Text();
   SPosition h;
   bool same = m_gw.SelectPosition(t1, h);
   bool halved = same && RdVolEq(h.volume, lot) && RdPriceEq(m_ts, h.open, p.open);
   Check(halved && StringFind(st, "Half-closed 1 position on " + _Symbol + " (" + RdFormatLots(m_ts, lot) + " lot)") == 0 &&
         m_status.Severity() == SEV_OK, "T-30 half close",
         RdTicketText(t1) + " " + RdFormatLots(m_ts, p.volume) + " -> " + (same ? RdFormatLots(m_ts, h.volume) : "gone") +
         " lot, open " + (same ? RdFormatPrice(m_ts, h.open) : "-") + ", status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   m_mgNet = t1;
   m_mgWaitFrom = GetTickCount();
   Line("T-30: waiting up to " + IntegerToString(RD_UITEST_RF_S) + " s for the position to be far enough in profit");
  }

//+------------------------------------------------------------------+
//| (waits) Risk Free once the position would be moved: SL = averaged|
//| open + spread (+ commission distance). If it never gets there,   |
//| the click must skip it with its reason and leave the SL. Then    |
//| Chart Close closes it.                                           |
//+------------------------------------------------------------------+
bool CUiSelfTest::MgT30Wait(const uint now)
  {
   if(m_mgNet == 0)
      return true;
   SPosition p;
   if(!m_gw.SelectPosition(m_mgNet, p))
     {
      Check(false, "T-30 risk free", RdTicketText(m_mgNet) + " is gone");
      return true;
     }
   SQuote q;
   if(!FreshQuote(q))
      return false;
   bool timeout = (uint)(now - m_mgWaitFrom) > (uint)RD_UITEST_RF_S * 1000;
   SRiskFreeResult rf;
   if(!timeout && !MgRfReady(p, q, MathMax(2.0 * RdTick(m_ts), 0.5 * (q.ask - q.bid)), rf))
      return false;
   SQuote q0;
   FreshQuote(q0);
   ClickButton(PB_RISKFREE);
   SQuote q1;
   FreshQuote(q1);
   string st = m_status.Text();
   SPosition a;
   m_gw.SelectPosition(m_mgNet, a);
   bool moved = !RdPriceEq(m_ts, a.sl, p.sl);
   if(!moved && !timeout)
     {
      Line("INFO T-30: the price went back during the click ('" + st + "') - waiting on");
      return false;
     }
   if(moved)
     {
      double w0 = MgRfTarget(p, q0);
      double w1 = MgRfTarget(p, q1);
      Check((RdPriceEq(m_ts, a.sl, w0) || RdPriceEq(m_ts, a.sl, w1)) && StringFind(st, ": 1 moved") > 0,
            "T-30 risk free on the averaged price", RdTicketText(p.ticket) + " @" + RdFormatPrice(m_ts, p.open) + " (averaged): SL " +
            RdFormatPrice(m_ts, p.sl) + " -> " + RdFormatPrice(m_ts, a.sl) + " (wanted " + RdFormatPrice(m_ts, w0) + " / " +
            RdFormatPrice(m_ts, w1) + "), status '" + st + "'");
      Shot("t30_riskfree");
     }
   else
     {
      Line("INFO T-30: in " + IntegerToString(RD_UITEST_RF_S) + " s the position did not get far enough in profit");
      Check((StringFind(st, "not in profit") > 0 || StringFind(st, "not enough profit") > 0) && m_status.Severity() == SEV_WARN,
            "T-30 risk free (not moved)", "SL kept " + RdFormatPrice(m_ts, a.sl) + ", status '" + st + "'");
     }
   ClickButton(PB_CHARTCLOSE);
   st = m_status.Text();
   SPosition c;
   bool gone = !m_gw.SelectPosition(m_mgNet, c);
   Check(gone && StringFind(st, "Closed 1 of 1 ") == 0 && m_status.Severity() == SEV_OK, "T-30 chart close",
         "closed " + RdBoolText(gone) + ", status '" + st + "'");
   MgCleanup("after T-30");
   m_mgNet = 0;
   return true;
  }

#endif // RD_APP_UISELFTESTMANAGECLOSE_MQH
