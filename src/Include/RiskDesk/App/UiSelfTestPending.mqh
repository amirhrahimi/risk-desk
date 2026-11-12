//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestPending.mqh                             |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : the pending suite of the self-test (phase P5,          |
//|           run-uitest.ps1 -Suite pending). Drives Add Pend Line,  |
//|           line drops, Set Pending, Del Pending and drops of the  |
//|           overlay lines through the same event handlers a user   |
//|           triggers, with REAL pending orders, and checks T-13,   |
//|           T-14, T-15, T-23, T-39, F-22, the pending part of T-08,|
//|           the Set Pending refusals and (netting accounts) BC-10. |
//| Safety : as the trade suite (App/UiSelfTestTrade.mqh): rule R13  |
//|          (demo accounts only, checked by TradeStart before       |
//|          anything is sent), own magic RD_UITEST_MAGIC, a test   |
//|          lot of about 2.5 x the minimum lot's risk (at most 1 %),|
//|          every test order deleted again (also those of an        |
//|          aborted earlier run). Orders are placed 3 SL distances  |
//|          (0.75 % of the price or more) away, so they do not fill |
//|          during the test. Del Pending is limited to the test's   |
//|          own orders when anyone else's are on the symbol.        |
//|          Part of CUiSelfTest; included at the end of             |
//|          App/UiSelfTest.mqh. This file: dispatch, helpers,       |
//|          T-13, T-14, refusals, T-08; the overlay steps are in    |
//|          UiSelfTestPendingMove.mqh.                              |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTPENDING_MQH
#define RD_APP_UISELFTESTPENDING_MQH

//+------------------------------------------------------------------+
void CUiSelfTest::StepPending(const uint now)
  {
   bool trade = m_tradeOk && !m_marketClosed;
   switch(m_step)
     {
      case 0:
        {
         SQuote q;
         if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
            return;   // wait for a first quote, at most 15 s
         TradeStart();
         m_cfg.showPendingOverlay = true;
         ArrayResize(m_pendTickets, 0);
         m_pendBuyStop = 0;
         if(m_tradeOk && m_marketClosed)
            Line("INFO " + _Symbol + " is outside its trading sessions - the pending order steps are skipped");
         break;
        }
      case 1:
         if(trade)
            PendT13(SIDE_BUY, KIND_STOP, 3.0);
         break;
      case 2:
         if(trade)
            PendT13(SIDE_BUY, KIND_LIMIT, 3.0);
         break;
      case 3:
         if(trade)
            PendT13(SIDE_SELL, KIND_STOP, 3.5);
         break;
      case 4:
         if(trade)
            PendT13(SIDE_SELL, KIND_LIMIT, 3.5);
         break;
      case 5:
         if(trade)
            PendF22();
         break;
      case 6:
         if(trade)
            PendT39a();
         break;
      case 7:
         if(trade)
            PendT39b();
         break;
      case 8:
         if(trade)
            PendT39c();
         break;
      case 9:
         if(trade)
            PendT15();
         break;
      case 10:
         if(trade)
            PendT14();
         break;
      case 11:
         if(trade)
            PendRefusals();
         break;
      case 12:
         if(trade)
            PendT08(TPMODE_NONE);
         break;
      case 13:
         if(trade)
            PendT08(TPMODE_AUTO_RR);
         break;
      case 14:
         if(trade)
            PendT08(TPMODE_MANUAL_LINE);
         break;
      case 15:
         if(trade)
            PendT23();
         break;
      case 16:
         if(trade && !m_gw.IsHedging())
            PendNet();
         break;
      default:
         TradeEnd();
         Finish();
         return;
     }
   m_step++;
  }

//====================================================================
// Helpers
//====================================================================

// Test orders (RD_UITEST_MAGIC) on a symbol ("" = the chart's).
int CUiSelfTest::TestOrders(SOrder &arr[], const string symbol)
  {
   STradeFilter f;
   f.Reset();
   f.symbol = (symbol == "") ? _Symbol : symbol;
   f.toolOnly = true;
   SResult r;
   if(!m_gw.ListPending(f, arr, r))
      ArrayResize(arr, 0);
   return ArraySize(arr);
  }

bool CUiSelfTest::FindTestOrder(const ulong ticket, SOrder &o)
  {
   SOrder arr[];
   int n = TestOrders(arr);
   for(int i = 0; i < n; i++)
      if(arr[i].ticket == ticket)
        {
         o = arr[i];
         return true;
        }
   return false;
  }

//+------------------------------------------------------------------+
//| Pending lines for this order type, dropped like a user drop:     |
//| entry 'factor' SL distances beyond the price (above Ask for a    |
//| Buy Stop / Sell Limit, below Bid for a Buy Limit / Sell Stop),   |
//| SL one distance from the entry. Rounded away from the price.     |
//+------------------------------------------------------------------+
bool CUiSelfTest::PendLines(const ESide side, const EOrderKind kind, const double factor, double &entry, double &sl)
  {
   entry = 0.0;
   sl = 0.0;
   if(m_state.lineMode != LINES_PENDING)
      ClickButton(PB_ADDPEND);
   SQuote q;
   if(!FreshQuote(q))
      return false;
   bool above = (side == SIDE_BUY) == (kind == KIND_STOP);
   entry = above ? RdRoundPriceUp(m_ts, q.ask + factor * m_dist) : RdRoundPriceDown(m_ts, q.bid - factor * m_dist);
   sl = (side == SIDE_BUY) ? RdRoundPriceDown(m_ts, entry - m_dist) : RdRoundPriceUp(m_ts, entry + m_dist);
   if(!(entry > 0.0) || !(sl > 0.0))
      return false;
   DropLine(LINEROLE_ENTRY, entry);
   DropLine(LINEROLE_SL, sl);
   return true;
  }

// F-17 Auto R/R: entry +/- rr x |entry - SL|, on the tick grid.
double CUiSelfTest::AutoTp(const ESide side, const double entry, const double sl, const double rr) const
  {
   double d = MathAbs(entry - sl);
   return RdNormalizePrice(m_ts, (side == SIDE_BUY) ? entry + rr * d : entry - rr * d);
  }

// Money at the SL of an order as RiskDesk counts it (04 section 5), from the raw valuation.
double CUiSelfTest::OrderRisk(const SOrder &o)
  {
   if(!(o.sl > 0.0))
      return 0.0;
   return (ExpectedLoss(o.side, o.price, o.sl) + MathMax(0.0, m_cfg.commissionPerLot)) * o.volume;
  }

//+------------------------------------------------------------------+
//| 'text' shows 'amount' in the account currency. RiskDesk's sum and |
//| the test's are equal up to floating-point noise, so an amount on |
//| half a cent (3 lot x 45.485 = 136.455) may round either way.     |
//+------------------------------------------------------------------+
bool CUiSelfTest::HasMoney(const string text, const SAccountSpec &acc, const double amount) const
  {
   double half = 0.5 * MathPow(10.0, -acc.digitsCcy);
   return StringFind(text, RdMoney(acc, amount)) >= 0 || StringFind(text, RdMoney(acc, amount - half)) >= 0 ||
          StringFind(text, RdMoney(acc, amount + half)) >= 0;
  }

//+------------------------------------------------------------------+
//| F-22 AC1 / 05 section 5-6: the order's overlay lines exist at its|
//| values, in the overlay colours and styles, selectable and in the |
//| object list, with their labels.                                  |
//+------------------------------------------------------------------+
bool CUiSelfTest::OverlayDrawn(const ulong ticket, const SOrder &o, string &why)
  {
   why = "";
   double value[RD_LINE_ROLES];
   value[LINEROLE_ENTRY] = o.price;
   value[LINEROLE_SL] = o.sl;
   value[LINEROLE_TP] = o.tp;
   color want[RD_LINE_ROLES];
   want[LINEROLE_ENTRY] = m_cfg.colorPendOverlayEntry;
   want[LINEROLE_SL] = m_cfg.colorPendOverlaySL;
   want[LINEROLE_TP] = m_cfg.colorPendOverlayTP;
   bool ok = true;
   for(int r = 0; r < RD_LINE_ROLES; r++)
     {
      ELineRole role = (ELineRole)r;
      string name = CPendingOverlay::LineName(ticket, role);
      string label = CPendingOverlay::LabelName(ticket, role);
      bool exists = ObjectFind(0, name) >= 0;
      if(!(value[r] > 0.0))
        {
         if(exists)
           {
            ok = false;
            why = RdJoin(why, name + " drawn although the order has no " + CLines::RoleText(role), "; ");
           }
         continue;
        }
      if(!exists || ObjectFind(0, label) < 0)
        {
         ok = false;
         why = RdJoin(why, (exists ? label : name) + " missing", "; ");
         continue;
        }
      int style = Prop(name, OBJPROP_STYLE);
      int wantStyle = (role == LINEROLE_ENTRY) ? STYLE_DASHDOT : STYLE_DASH;
      bool look = style == wantStyle && Prop(name, OBJPROP_WIDTH) == 1 && (color)Prop(name, OBJPROP_COLOR) == want[r] &&
                  Prop(name, OBJPROP_SELECTABLE) != 0 && Prop(name, OBJPROP_HIDDEN) == 0;
      bool at = RdPriceEq(m_ts, ObjectGetDouble(0, name, OBJPROP_PRICE, 0), value[r]);
      if(!look || !at)
        {
         ok = false;
         why = RdJoin(why, name + (at ? "" : " at " + RdFormatPrice(m_ts, ObjectGetDouble(0, name, OBJPROP_PRICE, 0)) +
                      " (order " + RdFormatPrice(m_ts, value[r]) + ")") + (look ? "" : " style " + IntegerToString(style) +
                      " width " + IntegerToString(Prop(name, OBJPROP_WIDTH)) + " colour " + IntegerToString(Prop(name, OBJPROP_COLOR))), "; ");
        }
     }
   if(ok)
      why = "lines and labels at " + RdFormatPrice(m_ts, o.price) + " / " + RdFormatPrice(m_ts, o.sl) + " / " +
            (o.tp > 0.0 ? RdFormatPrice(m_ts, o.tp) : "no TP") + ", overlay colours and styles";
   return ok;
  }

// What the terminal does when the user drops an overlay line.
void CUiSelfTest::DropOverlay(const ulong ticket, const ELineRole role, const double price)
  {
   string name = CPendingOverlay::LineName(ticket, role);
   ObjectMove(0, name, 0, 0, price);
   long l = 0;
   double d = 0.0;
   m_ctl.OnChartEvent(CHARTEVENT_OBJECT_DRAG, l, d, name);
  }

//+------------------------------------------------------------------+
//| T-13 / F-09: the click placed exactly one order of the type shown|
//| with the lines' entry and SL, the expected TP (0 = none), the    |
//| lots shown (= the lots computed here); green/amber status with   |
//| the risk and ticket; lines removed; screenshot; overlay drawn.   |
//+------------------------------------------------------------------+
bool CUiSelfTest::CheckPlaced(const string id, const ESide side, const EOrderKind kind, const int before, const double entry,
                              const double sl, const double tpWanted)
  {
   SOrder arr[];
   int n = TestOrders(arr);
   string st = m_status.Text();
   ulong ticket = StatusTicket();
   SOrder o;
   bool found = ticket > 0 && FindTestOrder(ticket, o);
   if(!found || n != before + 1)
     {
      Check(false, id, "orders " + IntegerToString(before) + " -> " + IntegerToString(n) + ", status " +
            RdSeverityText(m_status.Severity()) + " '" + st + "'");
      return false;
     }
   m_ticket = ticket;
   string name = RdOrderText(side, kind);
   bool typeOk = o.side == side && o.kind == kind;
   bool statusOk = m_status.Severity() != SEV_ERROR && StringFind(st, name + " ") == 0 && StringFind(st, " placed") > 0 &&
                   StringFind(st, "risk ") > 0;
   double raw = 0.0;
   double lots = ExpectedLots(side, entry, sl, m_testRisk, raw);
   bool volOk = RdFormatLots(m_ts, o.volume) == m_pvLots && RdVolEq(o.volume, lots);
   bool priceOk = RdPriceEq(m_ts, o.price, entry) && RdPriceEq(m_ts, o.sl, sl);
   bool tpOk = (tpWanted > 0.0) ? RdPriceEq(m_ts, o.tp, tpWanted) : !(o.tp > 0.0);
   bool linesGone = m_cfg.keepLinesAfterTrade || (m_state.lineMode == LINES_NONE && CountObjects(RD_LINE_PREFIX) == 0);
   bool shot = !m_cfg.autoScreenshot || (m_state.lastShot != "" && FileIsExist(m_state.lastShot) &&
               StringFind(m_state.lastShot, "_pending_" + IntegerToString((long)ticket)) > 0);
   m_ctl.Refresh();
   string why = "";
   bool overlay = OverlayDrawn(ticket, o, why);
   Check(typeOk && statusOk && volOk && priceOk && tpOk && linesGone && shot && overlay, id,
         RdTicketText(ticket) + " " + RdOrderText(o.side, o.kind) + " " + RdFormatLots(m_ts, o.volume) + " lot (Lots showed " +
         m_pvLots + ", expected " + RdFormatLots(m_ts, lots) + ") @" + RdFormatPrice(m_ts, o.price) + " (line " +
         RdFormatPrice(m_ts, entry) + "), SL " + RdFormatPrice(m_ts, o.sl) + " (line " + RdFormatPrice(m_ts, sl) + "), TP " +
         RdFormatPrice(m_ts, o.tp) + " (wanted " + (tpWanted > 0.0 ? RdFormatPrice(m_ts, tpWanted) : "none") + "), lines removed " +
         RdBoolText(linesGone) + ", screenshot " + RdBoolText(shot) + ", overlay: " + why + ", status " +
         RdSeverityText(m_status.Severity()) + " '" + st + "'");
   return true;
  }

//====================================================================
// Steps
//====================================================================

//+------------------------------------------------------------------+
//| T-13 / F-08 / F-09: lines for one order type -> Pending Info and |
//| Lots; Set Pending -> that order. The orders stay for F-22, T-39  |
//| and T-15.                                                        |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT13(const ESide side, const EOrderKind kind, const double factor)
  {
   string type = RdOrderText(side, kind);
   string id = "T-13 " + type;
   double entry = 0.0;
   double sl = 0.0;
   if(!PendLines(side, kind, factor, entry, sl))
     {
      Check(false, id, "no room for the lines");
      return;
     }
   string pinfo = Text("RD_E_PINFO");
   m_pvLots = Text("RD_E_LOTS");
   double raw = 0.0;
   double lots = ExpectedLots(side, entry, sl, m_testRisk, raw);
   string entryLabel = Text(CLines::LabelName(LINEROLE_ENTRY));
   bool infoOk = pinfo == type + RdSep() + m_pvLots + " lot" && m_pvLots == RdFormatLots(m_ts, lots) &&
                 entryLabel == "ENTRY  " + type + "  " + RdFormatPrice(m_ts, entry);
   Check(infoOk, id + " Pending Info", "entry " + RdFormatPrice(m_ts, entry) + ", SL " + RdFormatPrice(m_ts, sl) +
         ": Pending Info '" + pinfo + "', Lots '" + m_pvLots + "' (expected " + RdFormatLots(m_ts, lots) + ", raw " +
         RdNum(raw, 4) + "), entry label '" + entryLabel + "'");
   double tp = 0.0;
   if(m_cfg.tpMode == TPMODE_AUTO_RR)
      tp = AutoTp(side, entry, sl, m_cfg.tpRR);
   else
      if(m_cfg.tpMode == TPMODE_MANUAL_LINE && m_plan.Exists(LINEROLE_TP))
         tp = RdNormalizePrice(m_ts, m_plan.Price(LINEROLE_TP));
   SOrder arr[];
   int before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   if(CheckPlaced(id + " placed", side, kind, before, entry, sl, tp))
     {
      int n = ArraySize(m_pendTickets);
      ArrayResize(m_pendTickets, n + 1);
      m_pendTickets[n] = m_ticket;
      if(side == SIDE_BUY && kind == KIND_STOP)
         m_pendBuyStop = m_ticket;
     }
   string shot = type;
   StringReplace(shot, " ", "_");
   StringToLower(shot);
   Shot("t13_" + shot);
  }

//+------------------------------------------------------------------+
//| T-14 / F-09 AC2: an entry (and an SL) inside the stops level is  |
//| refused before anything is sent, naming the distance needed.     |
//| Without a stops level only the "entry at market" rule is checked |
//| (no click: a moving quote could make it a valid order next to    |
//| the price).                                                      |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT14()
  {
   double tick = RdTick(m_ts);
   double stops = m_ts.stopsLevel * m_ts.point;
   if(m_state.lineMode != LINES_PENDING)
      ClickButton(PB_ADDPEND);
   SQuote q;
   SQuote q2;
   q.Reset();
   q2.Reset();
   if(stops < 3.0 * tick)
     {
      for(int attempt = 0; attempt < 8; attempt++)
        {
         FreshQuote(q);
         DropLine(LINEROLE_ENTRY, RdNormalizePrice(m_ts, q.ask));
         DropLine(LINEROLE_SL, RdRoundPriceDown(m_ts, q.ask - m_dist));
         FreshQuote(q2);
         if(RdPriceEq(m_ts, q.ask, q2.ask))
            break;
        }
      string pinfo = Text("RD_E_PINFO");
      Line("INFO T-14: " + _Symbol + " has a stops level of " + RdFormatPoints(m_ts.stopsLevel) +
           " on this server - nothing to refuse; the entry-at-market rule is checked instead");
      Check(StringFind(pinfo, "Invalid: Entry at market - use Buy") == 0 && Text("RD_E_LOTS") == RdGlyphDash(),
            "T-14 entry at market", "entry at Ask " + RdFormatPrice(m_ts, q.ask) + ": Pending Info '" + pinfo + "', Lots '" +
            Text("RD_E_LOTS") + "'");
      CLines::DeleteAll();
      m_state.lineMode = LINES_NONE;
      return;
     }
   //--- a Buy Stop half the stops level above Ask
   FreshQuote(q);
   double entry = RdRoundPriceUp(m_ts, q.ask + stops / 2.0);
   double sl = RdRoundPriceDown(m_ts, entry - m_dist);
   DropLine(LINEROLE_ENTRY, entry);
   DropLine(LINEROLE_SL, sl);
   string pinfo = Text("RD_E_PINFO");
   SOrder arr[];
   int before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   int after = TestOrders(arr);
   string st = m_status.Text();
   string need = "needs >= " + RdFormatPoints(m_ts.stopsLevel) + " (" + RdFormatPrice(m_ts, stops) + "), move it to ";
   Check(after == before && m_status.Severity() == SEV_ERROR && StringFind(st, "Set Pending refused: Entry too close to Ask") == 0 &&
         StringFind(st, need) > 0 && StringFind(pinfo, "Invalid: Entry too close to Ask") == 0, "T-14 entry inside the stops level",
         "entry " + RdFormatPrice(m_ts, entry) + " (Ask " + RdFormatPrice(m_ts, q.ask) + ", stops level " +
         RdFormatPoints(m_ts.stopsLevel) + "): Pending Info '" + pinfo + "', orders " + IntegerToString(before) + " -> " +
         IntegerToString(after) + ", status '" + st + "'");
   //--- an SL half the stops level from a valid entry
   FreshQuote(q);
   entry = RdRoundPriceUp(m_ts, q.ask + 3.0 * m_dist);
   sl = RdRoundPriceUp(m_ts, entry - stops / 2.0);
   if(!RdPriceLt(m_ts, sl, entry))
      sl = RdNormalizePrice(m_ts, entry - tick);
   DropLine(LINEROLE_ENTRY, entry);
   DropLine(LINEROLE_SL, sl);
   before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   after = TestOrders(arr);
   st = m_status.Text();
   Check(after == before && m_status.Severity() == SEV_ERROR &&
         StringFind(st, "SL too close to the entry for a Buy Stop: " + need) > 0, "T-14 SL inside the stops level",
         "entry " + RdFormatPrice(m_ts, entry) + ", SL " + RdFormatPrice(m_ts, sl) + ": orders " + IntegerToString(before) +
         " -> " + IntegerToString(after) + ", status '" + st + "'");
   Shot("t14_stops_level");
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
  }

//+------------------------------------------------------------------+
//| Set Pending refusals: market lines, no lines, below the minimum  |
//| lot, InpConfirmTrades answered No. Nothing is sent.              |
//+------------------------------------------------------------------+
void CUiSelfTest::PendRefusals()
  {
   SOrder arr[];
   int before = TestOrders(arr);
   ClickButton(PB_ADDLINE);
   ClickButton(PB_SETPEND);
   string st1 = m_status.Text();
   bool market = m_status.Severity() == SEV_ERROR && StringFind(st1, "the lines on the chart are for a market order") > 0;
   ClickButton(PB_DELLINE);
   ClickButton(PB_SETPEND);
   string st2 = m_status.Text();
   bool none = m_status.Severity() == SEV_ERROR && StringFind(st2, "no Entry and SL lines - click Add Pend Line first") > 0;
   int after = TestOrders(arr);
   Check(market && none && after == before, "OP-07 PF-5 lines", "market lines: '" + st1 + "'; no lines: '" + st2 + "'; orders " +
         IntegerToString(before) + " -> " + IntegerToString(after));
   //--- below the minimum lot (T-09 for pending orders)
   double entry = 0.0;
   double sl = 0.0;
   PendLines(SIDE_BUY, KIND_STOP, 3.0, entry, sl);
   Edit("0.01");
   double far = 0.0;
   for(double k = 1.0; k <= 128.0 && far == 0.0; k *= 2.0)
     {
      double s = RdRoundPriceDown(m_ts, entry - k * m_dist);
      if(!(s > RdTick(m_ts)))
         break;
      double raw = 0.0;
      ExpectedLots(SIDE_BUY, entry, s, 0.01, raw);
      if(raw > 0.0 && raw < m_ts.volMin)
         far = s;
     }
   if(far > 0.0)
     {
      DropLine(LINEROLE_SL, far);
      before = TestOrders(arr);
      ClickButton(PB_SETPEND);
      after = TestOrders(arr);
      Check(after == before && m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "Min lot " +
            RdFormatLots(m_ts, m_ts.volMin) + " would risk") >= 0 && StringFind(Text("RD_E_PINFO"), "below min lot") > 0,
            "T-09 pending below min lot", "Risk % 0.01, SL " + RdFormatPrice(m_ts, far) + ": Pending Info '" +
            Text("RD_E_PINFO") + "', orders " + IntegerToString(before) + " -> " + IntegerToString(after) + ", status '" +
            m_status.Text() + "'");
     }
   else
      Line("INFO T-09 pending: no SL far enough on " + _Symbol);
   Edit(DoubleToString(m_testRisk, 2));
   //--- F-28 InpConfirmTrades answered No
   PendLines(SIDE_BUY, KIND_STOP, 3.0, entry, sl);
   m_cfg.confirmTrades = true;
   m_cmd.SetTestConfirm(RD_CONFIRM_NO);
   before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   after = TestOrders(arr);
   string conf = m_cmd.LastConfirm();
   Check(after == before && m_status.Severity() == SEV_WARN && m_status.Text() == "Set Pending cancelled - nothing was sent" &&
         StringFind(conf, "Buy Stop ") == 0 && StringFind(conf, "@" + RdFormatPrice(m_ts, entry) + "?") > 0,
         "F-28 confirm Set Pending: No", "confirmation '" + conf + "', orders " + IntegerToString(before) + " -> " +
         IntegerToString(after) + ", status '" + m_status.Text() + "'");
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   m_cfg.confirmTrades = false;
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
  }

//+------------------------------------------------------------------+
//| T-08 with Add Pend Line + Set Pending (R/R 2): (a) no TP, (b)    |
//| Auto R/R from the entry, (c) manual TP line at R/R 2 that        |
//| follows the SL until dragged. Each order is deleted afterwards.  |
//+------------------------------------------------------------------+
void CUiSelfTest::PendT08(const ETpMode mode)
  {
   SetTpMode(mode, 2.0);
   m_cfg.tpFollowsSl = true;
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   ClickButton(PB_ADDPEND);
   string id = (mode == TPMODE_NONE) ? "T-08a pending, no TP" : (mode == TPMODE_AUTO_RR ? "T-08b pending, TP at R/R 2" :
               "T-08c pending, TP = line");
   bool tpLine = m_plan.Exists(LINEROLE_TP);
   double entry = 0.0;
   double sl = 0.0;
   if(!PendLines(SIDE_BUY, KIND_STOP, 3.0, entry, sl))
     {
      Check(false, id, "no room for the lines");
      RestoreTp();
      return;
     }
   double tpWanted = 0.0;
   if(mode == TPMODE_AUTO_RR)
      tpWanted = AutoTp(SIDE_BUY, entry, sl, 2.0);
   if(mode == TPMODE_MANUAL_LINE)
     {
      double tp1 = m_plan.Price(LINEROLE_TP);
      double rr1 = (entry - sl > 0.0) ? (tp1 - entry) / (entry - sl) : 0.0;
      Check(tpLine && MathAbs(rr1 - 2.0) < 0.05 && !m_plan.TpFree(), "T-08c pending TP line follows", "entry " +
            RdFormatPrice(m_ts, entry) + ", SL " + RdFormatPrice(m_ts, sl) + " -> TP line " + RdFormatPrice(m_ts, tp1) +
            " (R/R " + RdNum(rr1, 3) + ")");
      double myTp = RdRoundPriceUp(m_ts, entry + 3.0 * m_dist);
      DropLine(LINEROLE_TP, myTp);
      sl = RdRoundPriceDown(m_ts, entry - 1.2 * m_dist);
      DropLine(LINEROLE_SL, sl);
      Check(m_plan.TpFree() && RdPriceEq(m_ts, m_plan.Price(LINEROLE_TP), myTp), "T-08c pending dragged TP stays",
            "TP dragged to " + RdFormatPrice(m_ts, myTp) + ", SL moved to " + RdFormatPrice(m_ts, sl) + ": TP line " +
            RdFormatPrice(m_ts, m_plan.Price(LINEROLE_TP)));
      tpWanted = myTp;
     }
   else
      Check(!tpLine, id + " (no TP line)", "TP line " + RdBoolText(tpLine) + " (TP mode " + m_cfg.TpModeText() + ")");
   m_pvLots = Text("RD_E_LOTS");
   SOrder arr[];
   int before = TestOrders(arr);
   ClickButton(PB_SETPEND);
   if(CheckPlaced(id, SIDE_BUY, KIND_STOP, before, entry, sl, tpWanted))
     {
      SResult r;
      m_gw.DeletePending(m_ticket, r);
     }
   RestoreTp();
  }

#endif // RD_APP_UISELFTESTPENDING_MQH
