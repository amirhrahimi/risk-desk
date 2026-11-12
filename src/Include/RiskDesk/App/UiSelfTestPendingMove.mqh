//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestPendingMove.mqh                         |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : pending suite steps on placed orders: F-22 overlay,    |
//|           T-39 drags of its lines (OP-16), T-23 expiry, T-15     |
//|           Del Pending, BC-10 netting. Part of CUiSelfTest;       |
//|           included by App/UiSelfTest.mqh after                   |
//|           UiSelfTestPending.mqh (helpers there).                 |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTPENDINGMOVE_MQH
#define RD_APP_UISELFTESTPENDINGMOVE_MQH

//+------------------------------------------------------------------+
//| F-22: the T-13 orders drawn (AC1); a change made outside the     |
//| overlay is followed, a deleted overlay line comes back, the      |
//| overlay goes with the order (AC3); the input switches it (AC4).  |
//+------------------------------------------------------------------+
void CUiSelfTest::PendF22()
  {
   SOrder o;
   if(m_pendBuyStop == 0 || !FindTestOrder(m_pendBuyStop, o))
     {
      Line("INFO F-22: no Buy Stop from T-13");
      return;
     }
   ulong t = o.ticket;
   m_ctl.Refresh();
   string why = "";
   bool drawn = OverlayDrawn(t, o, why);
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar);
   string en = Text(CPendingOverlay::LabelName(t, LINEROLE_ENTRY));
   string slLabel = Text(CPendingOverlay::LabelName(t, LINEROLE_SL));
   string tpLabel = Text(CPendingOverlay::LabelName(t, LINEROLE_TP));
   string wantEn = RdOrderText(o.side, o.kind) + " " + RdFormatLots(m_ts, o.volume) + " @ " + RdFormatPrice(m_ts, o.price);
   double risk = OrderRisk(o);
   double base = Base();
   string wantSl = "SL " + RdGlyphMinus() + RdMoney(acc, risk) + " (" + RdFormatPct(base > 0.0 ? risk / base * 100.0 : 0.0) + ")";
   bool labels = en == wantEn && StringFind(slLabel, "SL " + RdGlyphMinus()) == 0 && HasMoney(slLabel, acc, risk) &&
                 StringFind(slLabel, " (") > 0 &&
                 (o.tp > 0.0 ? StringFind(tpLabel, "TP +") == 0 && StringFind(tpLabel, " (R ") > 0 : tpLabel == "");
   Check(drawn && labels, "F-22 overlay drawn", RdTicketText(t) + ": " + why + "; labels '" + en + "' / '" + slLabel + "' / '" +
         tpLabel + "' (expected '" + wantEn + "' / '" + wantSl + "')");
   int n = 0;
   int shown = 0;
   for(int i = 0; i < ArraySize(m_pendTickets); i++)
     {
      SOrder oi;
      if(!FindTestOrder(m_pendTickets[i], oi))
         continue;
      n++;
      string w = "";
      if(OverlayDrawn(oi.ticket, oi, w))
         shown++;
     }
   Check(n >= 1 && shown == n, "F-22 every order drawn", IntegerToString(shown) + " of " + IntegerToString(n) +
         " T-13 orders drawn");
   Shot("f22_overlay");

   //--- AC3: a change made outside RiskDesk's overlay (MetaTrader's trade levels, another tool) is followed
   double newSl = RdRoundPriceDown(m_ts, o.sl - 0.25 * m_dist);
   SResult mr;
   bool mod = m_gw.ModifyPending(t, o.price, newSl, o.tp, mr);
   m_ctl.Refresh();
   double lineSl = ObjectGetDouble(0, CPendingOverlay::LineName(t, LINEROLE_SL), OBJPROP_PRICE, 0);
   string slLabel2 = Text(CPendingOverlay::LabelName(t, LINEROLE_SL));
   Check(mod && RdPriceEq(m_ts, lineSl, newSl) && slLabel2 != slLabel, "F-22 follows the order", "SL changed to " +
         RdFormatPrice(m_ts, newSl) + " outside the overlay (" + mr.message + "): line at " + RdFormatPrice(m_ts, lineSl) +
         ", label '" + slLabel2 + "' (was '" + slLabel + "')");

   //--- AC3: a deleted overlay line is drawn again, the order stays
   ObjectDelete(0, CPendingOverlay::LineName(t, LINEROLE_ENTRY));
   m_ctl.Refresh();
   SOrder o2;
   bool still = FindTestOrder(t, o2);
   Check(ObjectFind(0, CPendingOverlay::LineName(t, LINEROLE_ENTRY)) >= 0 && still && RdPriceEq(m_ts, o2.price, o.price),
         "F-22 deleted line redrawn", "entry line of " + RdTicketText(t) + " deleted: drawn again " +
         RdBoolText(ObjectFind(0, CPendingOverlay::LineName(t, LINEROLE_ENTRY)) >= 0) + ", order still there " + RdBoolText(still));

   //--- AC3: the overlay goes with the order (one T-13 order deleted outside the overlay)
   ulong gone = 0;
   for(int k = 0; k < ArraySize(m_pendTickets) && gone == 0; k++)
     {
      SOrder ok_;
      if(m_pendTickets[k] != t && FindTestOrder(m_pendTickets[k], ok_))
         gone = m_pendTickets[k];
     }
   if(gone > 0)
     {
      SResult dr;
      bool del = m_gw.DeletePending(gone, dr);
      m_ctl.Refresh();
      string prefix = RD_OVERLAY_LINE_PREFIX + IntegerToString((long)gone) + "_";
      string prefix2 = RD_OVERLAY_LABEL_PREFIX + IntegerToString((long)gone) + "_";
      int left = CountObjects(prefix) + CountObjects(prefix2);
      Check(del && left == 0, "F-22 removed with the order", RdTicketText(gone) + " deleted (" + dr.message + "): " +
            IntegerToString(left) + " overlay object(s) left");
     }

   //--- AC4: switched off -> nothing drawn; on -> drawn again
   m_cfg.showPendingOverlay = false;
   m_ctl.Refresh();
   int off = CountObjects(RD_OVERLAY_LINE_PREFIX) + CountObjects(RD_OVERLAY_LABEL_PREFIX);
   m_cfg.showPendingOverlay = true;
   m_ctl.Refresh();
   FindTestOrder(t, o2);
   string w2 = "";
   bool back = OverlayDrawn(t, o2, w2);
   Check(off == 0 && back, "F-22 overlay off / on", IntegerToString(off) + " overlay object(s) while off; on again: " + w2);
  }

//+------------------------------------------------------------------+
//| T-39 part 1 (OP-16): SL dragged farther (modified, label and     |
//| open risk updated, amber above the panel's Risk %), TP dragged,  |
//| entry dragged up (SL and TP follow, risk unchanged).             |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT39a()
  {
   SOrder o;
   if(m_pendBuyStop == 0 || !FindTestOrder(m_pendBuyStop, o))
     {
      Line("INFO T-39: no Buy Stop from T-13");
      return;
     }
   ulong t = o.ticket;
   string name = RdOrderText(o.side, o.kind) + " " + RdTicketText(t);
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar);
   m_ctl.Refresh();
   string idle0 = m_status.IdleText();
   //--- SL farther
   double dist = MathAbs(o.price - o.sl);
   double newSl = RdRoundPriceDown(m_ts, o.price - 1.6 * dist);
   DropOverlay(t, LINEROLE_SL, newSl);
   string st = m_status.Text();
   ESeverity sev = m_status.Severity();
   string shotPath = m_state.lastShot;
   SOrder o1;
   bool found = FindTestOrder(t, o1);
   double risk1 = OrderRisk(o1);
   double pct1 = (Base() > 0.0) ? risk1 / Base() * 100.0 : 0.0;
   bool amber = NormalizeDouble(pct1, 2) > m_state.riskPct + RD_PCT_EPS;
   bool statusOk = StringFind(st, name + " SL " + RdFormatPrice(m_ts, newSl)) == 0 && HasMoney(st, acc, risk1) &&
                   (amber ? sev == SEV_WARN && StringFind(st, "(panel " + RdFormatPct(m_state.riskPct) + ")") > 0 : sev == SEV_OK);
   m_ctl.Refresh();
   string slLabel = Text(CPendingOverlay::LabelName(t, LINEROLE_SL));
   double lineSl = ObjectGetDouble(0, CPendingOverlay::LineName(t, LINEROLE_SL), OBJPROP_PRICE, 0);
   //--- F-29 readout after the drop (OP-16 asks for a fresh one) = the test orders' risk summed here
   string idle1 = m_status.IdleText();
   SOrder cur[];
   double openAll = 0.0;
   int nc = TestOrders(cur);
   for(int i = 0; i < nc; i++)
      openAll += OrderRisk(cur[i]);
   string wantIdle = "Open risk " + RdFormatPct(Base() > 0.0 ? openAll / Base() * 100.0 : 0.0) + " / " +
                     RdFormatCapPct(m_cfg.maxTotalRiskPct);
   bool idleOk = StringFind(idle1, "Open risk") != 0 || idle1 == wantIdle;
   bool shot = !m_cfg.autoScreenshot || (StringFind(shotPath, "_modify_" + IntegerToString((long)t)) > 0 && FileIsExist(shotPath));
   Check(found && RdPriceEq(m_ts, o1.sl, newSl) && RdPriceEq(m_ts, o1.price, o.price) && RdPriceEq(m_ts, lineSl, newSl) &&
         HasMoney(slLabel, acc, risk1) && statusOk && idleOk && shot, "T-39 SL farther",
         "SL " + RdFormatPrice(m_ts, o.sl) + " -> " + RdFormatPrice(m_ts, newSl) + ": order SL " + RdFormatPrice(m_ts, o1.sl) +
         ", line " + RdFormatPrice(m_ts, lineSl) + ", label '" + slLabel + "', risk " + RdFormatPct(pct1) + " (panel " +
         RdFormatPct(m_state.riskPct) + ", amber expected " + RdBoolText(amber) + "), idle '" + idle0 + "' -> '" + idle1 +
         "' (expected '" + wantIdle + "'), screenshot " + RdBoolText(shot) + " (" + shotPath + "), status " + RdSeverityText(sev) + " '" + st + "'");

   //--- TP dragged: only the TP changes
   if(o1.tp > 0.0)
     {
      double newTp = RdRoundPriceUp(m_ts, o1.price + 2.5 * MathAbs(o1.price - o1.sl));
      DropOverlay(t, LINEROLE_TP, newTp);
      SOrder o2;
      FindTestOrder(t, o2);
      st = m_status.Text();
      Check(RdPriceEq(m_ts, o2.tp, newTp) && RdPriceEq(m_ts, o2.sl, o1.sl) && RdPriceEq(m_ts, o2.price, o1.price) &&
            StringFind(st, name + " TP " + RdFormatPrice(m_ts, newTp)) == 0 && m_status.Severity() != SEV_ERROR, "T-39 TP dragged",
            "TP " + RdFormatPrice(m_ts, o1.tp) + " -> " + RdFormatPrice(m_ts, newTp) + ": order @" + RdFormatPrice(m_ts, o2.price) +
            " SL " + RdFormatPrice(m_ts, o2.sl) + " TP " + RdFormatPrice(m_ts, o2.tp) + ", status '" + st + "'");
      o1 = o2;
     }
   else
      Line("INFO T-39 TP: the order has no TP (TP mode " + m_cfg.TpModeText() + ")");

   //--- entry dragged up: the whole order moves, the risk stays
   double up = RdRoundPriceUp(m_ts, o1.price + 0.5 * m_dist);
   double delta = up - o1.price;
   double riskBefore = OrderRisk(o1);
   DropOverlay(t, LINEROLE_ENTRY, up);
   SOrder o3;
   FindTestOrder(t, o3);
   st = m_status.Text();
   double riskAfter = OrderRisk(o3);
   double wantSl = RdNormalizePrice(m_ts, o1.sl + delta);
   double wantTp = (o1.tp > 0.0) ? RdNormalizePrice(m_ts, o1.tp + delta) : 0.0;
   bool riskSame = MathAbs(riskAfter - riskBefore) <= MathMax(0.005 * riskBefore, 2.0 * MathPow(10.0, -RdAccountCurrencyDigits()));
   m_ctl.Refresh();
   string why = "";
   bool drawn = OverlayDrawn(t, o3, why);
   Check(RdPriceEq(m_ts, o3.price, up) && RdPriceEq(m_ts, o3.sl, wantSl) && (wantTp > 0.0 ? RdPriceEq(m_ts, o3.tp, wantTp) : !(o3.tp > 0.0)) &&
         riskSame && drawn && StringFind(st, name + " moved to " + RdFormatPrice(m_ts, up)) == 0, "T-39 entry dragged up",
         "entry " + RdFormatPrice(m_ts, o1.price) + " -> " + RdFormatPrice(m_ts, up) + ": order @" + RdFormatPrice(m_ts, o3.price) +
         " SL " + RdFormatPrice(m_ts, o3.sl) + " (wanted " + RdFormatPrice(m_ts, wantSl) + ") TP " + RdFormatPrice(m_ts, o3.tp) +
         ", risk " + RdNum(riskBefore, 2) + " -> " + RdNum(riskAfter, 2) + ", overlay: " + why + ", status '" + st + "'");
   Shot("t39_moved");
  }

//+------------------------------------------------------------------+
//| T-39 part 2: refused moves snap back - entry below Ask (order    |
//| type), risk above the per-trade cap, total risk above its cap.   |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT39b()
  {
   SOrder o;
   if(m_pendBuyStop == 0 || !FindTestOrder(m_pendBuyStop, o))
     {
      Line("INFO T-39: no Buy Stop from T-13");
      return;
     }
   ulong t = o.ticket;
   //--- entry below Ask: a Buy Stop must stay above it
   SQuote q;
   FreshQuote(q);
   double below = RdRoundPriceDown(m_ts, q.ask - m_dist);
   DropOverlay(t, LINEROLE_ENTRY, below);
   string st = m_status.Text();
   SOrder o1;
   FindTestOrder(t, o1);
   double line = ObjectGetDouble(0, CPendingOverlay::LineName(t, LINEROLE_ENTRY), OBJPROP_PRICE, 0);
   Check(m_status.Severity() == SEV_ERROR && StringFind(st, "not moved: A Buy Stop must stay above Ask") > 0 &&
         RdPriceEq(m_ts, o1.price, o.price) && RdPriceEq(m_ts, line, o.price), "T-39 entry below Ask refused",
         "dropped at " + RdFormatPrice(m_ts, below) + " (Ask " + RdFormatPrice(m_ts, q.ask) + "): order @" +
         RdFormatPrice(m_ts, o1.price) + ", line snapped back to " + RdFormatPrice(m_ts, line) + ", status '" + st + "'");

   //--- SL so far that the risk is above the per-trade cap
   double base = Base();
   double risk = OrderRisk(o);
   double pct = (base > 0.0) ? risk / base * 100.0 : 0.0;
   double dist = MathAbs(o.price - o.sl);
   double far = RdRoundPriceDown(m_ts, o.price - 2.0 * dist);
   m_cfg.maxRiskPerTradePct = MathMax(0.01, NormalizeDouble(1.3 * pct, 2));
   DropOverlay(t, LINEROLE_SL, far);
   st = m_status.Text();
   FindTestOrder(t, o1);
   line = ObjectGetDouble(0, CPendingOverlay::LineName(t, LINEROLE_SL), OBJPROP_PRICE, 0);
   Check(m_status.Severity() == SEV_ERROR && StringFind(st, "per-trade cap") > 0 && StringFind(st, "Risk ") > 0 &&
         RdPriceEq(m_ts, o1.sl, o.sl) && RdPriceEq(m_ts, line, o.sl), "T-39 above the per-trade cap refused",
         "per-trade cap " + RdNum(m_cfg.maxRiskPerTradePct, 2) + " % (order " + RdFormatPct(pct) + "), SL dropped at " +
         RdFormatPrice(m_ts, far) + ": order SL " + RdFormatPrice(m_ts, o1.sl) + ", line snapped back to " +
         RdFormatPrice(m_ts, line) + ", status '" + st + "'");
   RestoreTp();

   //--- the same move above the total cap (old risk replaced, 04 section 5)
   SOrder all[];
   STradeFilter f;
   f.Reset();
   f.toolOnly = true;
   SResult lr;
   m_gw.ListPending(f, all, lr);
   double open = 0.0;
   int elsewhere = 0;
   for(int i = 0; i < ArraySize(all); i++)
     {
      if(all[i].symbol == _Symbol)
         open += OrderRisk(all[i]);
      else
         elsewhere++;
     }
   SPosition pos[];
   SPosition posAll[];
   f.symbol = "";
   m_gw.ListPositions(f, posAll, lr);
   SOrder fake = o;
   fake.sl = far;
   double farRisk = OrderRisk(fake);
   // the open risk is summed here with this symbol's valuation: only when nothing else is open
   if(base > 0.0 && farRisk > risk && elsewhere == 0 && ArraySize(posAll) == 0 && TestPositions(pos) == 0)
     {
      m_cfg.maxTotalRiskPct = MathMax(0.01, NormalizeDouble((open + 0.5 * (farRisk - risk)) / base * 100.0, 2));
      DropOverlay(t, LINEROLE_SL, far);
      st = m_status.Text();
      FindTestOrder(t, o1);
      line = ObjectGetDouble(0, CPendingOverlay::LineName(t, LINEROLE_SL), OBJPROP_PRICE, 0);
      Check(m_status.Severity() == SEV_ERROR && StringFind(st, "Total risk too high: open ") > 0 && StringFind(st, " - ") > 0 &&
            RdPriceEq(m_ts, o1.sl, o.sl) && RdPriceEq(m_ts, line, o.sl), "T-39 above the total cap refused",
            "total cap " + RdNum(m_cfg.maxTotalRiskPct, 2) + " % (open " + RdFormatPct(open / base * 100.0) + ", this order " +
            RdFormatPct(pct) + " -> " + RdFormatPct(farRisk / base * 100.0) + "): order SL " + RdFormatPrice(m_ts, o1.sl) +
            ", line " + RdFormatPrice(m_ts, line) + ", status '" + st + "'");
     }
   else
      Line("INFO T-39 total cap: test trades on other symbols or test positions are open - skipped");
   RestoreTp();
   Shot("t39_refused");
  }

//+------------------------------------------------------------------+
//| T-39 part 3: the user selects an overlay line and presses Delete:|
//| the line comes back, the order is untouched.                     |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT39c()
  {
   SOrder o;
   if(m_pendBuyStop == 0 || !FindTestOrder(m_pendBuyStop, o))
     {
      Line("INFO T-39: no Buy Stop from T-13");
      return;
     }
   ulong t = o.ticket;
   string name = CPendingOverlay::LineName(t, LINEROLE_SL);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, true);
   ObjectDelete(0, name);
   m_ctl.Refresh();
   SOrder o1;
   bool still = FindTestOrder(t, o1);
   string why = "";
   bool drawn = still && OverlayDrawn(t, o1, why);
   Check(drawn && RdPriceEq(m_ts, o1.sl, o.sl) && RdPriceEq(m_ts, o1.price, o.price), "T-39 Delete key",
         "SL line of " + RdTicketText(t) + " deleted: order still there " + RdBoolText(still) + " (SL " +
         RdFormatPrice(m_ts, o1.sl) + "), overlay: " + why);
  }

//+------------------------------------------------------------------+
//| T-15 / F-10: test orders on the chart symbol and on a second     |
//| symbol; Del Pending deletes only the chart symbol's and says     |
//| "Deleted n of n"; a second click finds nothing (amber).          |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT15()
  {
   m_otherSymbol2 = "";
   m_otherTicket = 0;
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar);
   double base = Base();
   int tries = 0;
   for(int i = 0; i < SymbolsTotal(true) && m_otherTicket == 0 && tries < 3; i++)
     {
      string sym = SymbolName(i, true);
      if(sym == _Symbol)
         continue;
      SSymbolSpec os;
      SResult sr;
      SQuote oq;
      if(!CSymbolSpec::Read(sym, os, sr) || os.tradeMode != SYMBOL_TRADE_MODE_FULL || !RdSymbolAcceptsKind(os, KIND_LIMIT) ||
         !CMarket::Quote(sym, oq) || CMarket::IsStale(oq, 300))
         continue;
      bool known = false;
      if(!CMarket::InSession(sym, RdServerTime(), known) && known)
         continue;
      double tick = RdTick(os);
      double d = MathMax(0.0025 * oq.bid, 2.0 * (os.stopsLevel + os.freezeLevel) * os.point + 3.0 * (oq.ask - oq.bid) + 10.0 * tick);
      double entry = RdRoundPriceDown(os, oq.bid - 3.0 * d);
      double sl = RdRoundPriceDown(os, entry - d);
      double loss = 0.0;
      SResult lr;
      double need = 0.0;
      SResult mr;
      if(!(sl > 0.0) || !m_money.LossPerLot(os, acc.currency, SIDE_BUY, entry, sl, loss, lr) ||
         os.volMin * loss > 0.01 * base || !m_money.MarginFor(os, SIDE_BUY, os.volMin, entry, need, mr) || need > 0.5 * acc.freeMargin)
         continue;
      tries++;
      STradeOutcome out;
      SResult pr;
      if(m_gw.PlacePending(sym, SIDE_BUY, KIND_LIMIT, os.volMin, entry, sl, 0.0, out, pr))
        {
         m_otherSymbol2 = sym;
         m_otherTicket = out.ticket;
        }
      else
         Line("INFO T-15: test order on " + sym + " not placed: " + pr.message);
     }
   if(m_otherTicket == 0)
      Line("INFO T-15: no second symbol with a test order - only the chart symbol is checked");
   else
      Line("T-15 setup: Buy Limit " + RdTicketText(m_otherTicket) + " on " + m_otherSymbol2 + " (chart B)");

   //--- the chart symbol: T-13's orders that are left, else one new
   SOrder mine[];
   int n = TestOrders(mine);
   if(n == 0)
     {
      double entry = 0.0;
      double sl = 0.0;
      PendLines(SIDE_SELL, KIND_STOP, 3.0, entry, sl);
      ClickButton(PB_SETPEND);
      n = TestOrders(mine);
     }
   STradeFilter f;
   f.Reset();
   f.symbol = _Symbol;
   f.includeStopLimit = true;
   SOrder all[];
   SResult lr2;
   m_gw.ListPending(f, all, lr2);
   int others = ArraySize(all) - n;
   if(others > 0)
     {
      m_cfg.scopeChartOps = SCOPE_TOOL_ON_SYMBOL;
      Line("INFO T-15: " + IntegerToString(others) + " order(s) of someone else on " + _Symbol +
           " - Del Pending limited to RiskDesk's (the test's) orders for this check");
     }
   ulong ids[];
   ArrayResize(ids, n);
   for(int k = 0; k < n; k++)
      ids[k] = mine[k].ticket;
   ClickButton(PB_DELPEND);
   string st = m_status.Text();
   ESeverity sev = m_status.Severity();
   string shotPath = m_state.lastShot;
   int left = TestOrders(mine);
   SOrder oo;
   bool otherKept = (m_otherTicket == 0) || m_gw.SelectPending(m_otherTicket, oo);
   string want = "Deleted " + IntegerToString(n) + " of " + IntegerToString(n) + " " + (others > 0 ? "RiskDesk " : "") +
                 "pending order" + (n == 1 ? "" : "s") + " on " + _Symbol;
   bool shot = !m_cfg.autoScreenshot || (StringFind(shotPath, "_delpending_") > 0 && FileIsExist(shotPath));
   m_ctl.Refresh();
   int overlayLeft = 0;
   for(int j = 0; j < n; j++)
      overlayLeft += CountObjects(RD_OVERLAY_LINE_PREFIX + IntegerToString((long)ids[j]) + "_");
   Check(left == 0 && otherKept && st == want && sev == SEV_OK && shot && overlayLeft == 0, "T-15 Del Pending",
         IntegerToString(n) + " test order(s) on " + _Symbol + ", 1 on " + (m_otherSymbol2 != "" ? m_otherSymbol2 : "(none)") +
         ": " + IntegerToString(left) + " left on the chart symbol, other symbol's kept " + RdBoolText(otherKept) +
         ", overlay objects left " + IntegerToString(overlayLeft) + ", screenshot " + RdBoolText(shot) + " (" + shotPath +
         "), status '" + st + "' (expected '" + want + "')");
   ClickButton(PB_DELPEND);
   Check(m_status.Severity() == SEV_WARN && StringFind(m_status.Text(), "No ") == 0 &&
         StringFind(m_status.Text(), "pending orders on " + _Symbol) > 0, "T-15 Del Pending again", "status '" + m_status.Text() + "'");
   Shot("t15_del_pending");
   if(m_otherTicket > 0)
     {
      SResult dr;
      m_gw.DeletePending(m_otherTicket, dr);
     }
   ArrayResize(m_pendTickets, 0);
   m_pendBuyStop = 0;
   RestoreTp();
  }

//+------------------------------------------------------------------+
//| T-23 / BC-08: InpPendingExpiryHours 24 -> the order expires about|
//| 24 h after placing (MT5: SPECIFIED, MT4: expiration), the status |
//| says when; a move (G-08) keeps it. A server that refuses expiry  |
//| (MT4 147) leaves the order without expiry and says so (amber).   |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT23()
  {
   m_cfg.pendingExpiryHours = 24;
   SGatewaySettings gs;
   m_cfg.Gateway(gs);
   m_gw.Configure(gs);
   double entry = 0.0;
   double sl = 0.0;
   if(!PendLines(SIDE_SELL, KIND_LIMIT, 3.0, entry, sl))
     {
      Check(false, "T-23", "no room for the lines");
      RestoreTp();
      return;
     }
   double tp = 0.0;
   if(m_cfg.tpMode == TPMODE_AUTO_RR)
      tp = AutoTp(SIDE_SELL, entry, sl, m_cfg.tpRR);
   else
      if(m_cfg.tpMode == TPMODE_MANUAL_LINE && m_plan.Exists(LINEROLE_TP))
         tp = RdNormalizePrice(m_ts, m_plan.Price(LINEROLE_TP));
   m_pvLots = Text("RD_E_LOTS");
   SOrder arr[];
   int before = TestOrders(arr);
   datetime now = RdServerTime();
   ClickButton(PB_SETPEND);
   string st = m_status.Text();
   if(!CheckPlaced("T-23 placed with expiry", SIDE_SELL, KIND_LIMIT, before, entry, sl, tp))
     {
      RestoreTp();
      return;
     }
   SOrder o;
   FindTestOrder(m_ticket, o);
   long dt = (long)o.expiration - (long)(now + 24 * 3600);
   bool expires = o.expiration > 0 && MathAbs(dt) <= 600 && StringFind(st, "expires " + TimeToString(o.expiration, TIME_DATE | TIME_MINUTES)) > 0;
   bool refused = !(o.expiration > 0) && m_status.Severity() == SEV_WARN && StringFind(st, "expiry not allowed") >= 0;
   Check(expires || refused, "T-23 expiry 24 h", "order expiration " + (o.expiration > 0 ? TimeToString(o.expiration) : "none") +
         " (wanted about " + TimeToString(now + 24 * 3600) + " server time, " + IntegerToString(dt) + " s off), status '" + st + "'");
   if(expires)
     {
      double newSl = RdRoundPriceUp(m_ts, o.sl + 0.25 * m_dist);
      DropOverlay(o.ticket, LINEROLE_SL, newSl);
      SOrder o2;
      FindTestOrder(o.ticket, o2);
      Check(RdPriceEq(m_ts, o2.sl, newSl) && o2.expiration == o.expiration && m_status.Severity() != SEV_ERROR,
            "T-23 move keeps the expiry", "SL dragged to " + RdFormatPrice(m_ts, newSl) + ": order SL " +
            RdFormatPrice(m_ts, o2.sl) + ", expiration " + TimeToString(o2.expiration) + " (was " + TimeToString(o.expiration) +
            "), status '" + m_status.Text() + "'");
     }
   SResult dr;
   m_gw.DeletePending(o.ticket, dr);
   RestoreTp();
  }

//+------------------------------------------------------------------+
//| BC-10 netting (A6): with an open buy, a Buy Stop merges with it  |
//| when it fills (confirmation); a Sell Limit is refused by default.|
//+------------------------------------------------------------------+
void CUiSelfTest::PendNet()
  {
   CloseTestTrades("before the netting steps");
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   ClickButton(PB_BUY);
   SPosition p;
   ulong t1 = StatusTicket();
   bool first = t1 > 0 && FindTestPosition(t1, p);
   if(!first)
     {
      Check(false, "BC-10 pending netting", "no buy position to merge with: status '" + m_status.Text() + "'");
      return;
     }
   double entry = 0.0;
   double psl = 0.0;
   PendLines(SIDE_BUY, KIND_STOP, 3.0, entry, psl);
   SOrder arr[];
   int before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   int after = TestOrders(arr);
   string conf = m_cmd.LastConfirm();
   Check(after == before + 1 && StringFind(conf, "when it fills, this Buy Stop") >= 0 &&
         StringFind(conf, "merges with the open buy " + RdFormatLots(m_ts, p.volume) + " lot position") > 0 &&
         m_status.Severity() != SEV_ERROR, "BC-10 pending merge confirmed", "orders " + IntegerToString(before) + " -> " +
         IntegerToString(after) + ", confirmation '" + conf + "', status '" + m_status.Text() + "'");
   PendLines(SIDE_SELL, KIND_LIMIT, 3.0, entry, psl);
   before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   after = TestOrders(arr);
   Check(after == before && m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "would reduce or reverse the open buy") > 0,
         "BC-10 pending opposite refused", "orders " + IntegerToString(before) + " -> " + IntegerToString(after) + ", status '" +
         m_status.Text() + "'");
   CloseTestTrades("after the netting steps");
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   RestoreTp();
  }

#endif // RD_APP_UISELFTESTPENDINGMOVE_MQH
