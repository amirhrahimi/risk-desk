//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestTradeLines.mqh                          |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : trade suite steps without orders, or refused ones:     |
//|           setup (rule R13, test lot), end, T-03, T-04, T-07,     |
//|           T-09, T-26, T-27. Part of CUiSelfTest; included by     |
//|           App/UiSelfTestTrade.mqh (split to stay near ~600       |
//|           lines).                                                |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTTRADELINES_MQH
#define RD_APP_UISELFTESTTRADELINES_MQH

//====================================================================
// Steps
//====================================================================

//+------------------------------------------------------------------+
//| Rule R13 first; then the test SL distance and Risk %: 0.25 % of  |
//| the price, at least 2 x (stops + freeze) + 3 x spread + 10 ticks;|
//| about 2.5 x the risk of the minimum lot there, at most 1 %.      |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeStart()
  {
   Line("RiskDesk " + RD_VERSION + " trade self-test (" + m_suite + "), " + RD_PLATFORM + " build " +
        IntegerToString(RdTerminalBuild()) + ", account " + IntegerToString(CAccountSpec::Login()) + " " +
        AccountInfoString(ACCOUNT_SERVER) + " " + AccountInfoString(ACCOUNT_CURRENCY) + " (" +
        RdAccountTradeModeText(AccountInfoInteger(ACCOUNT_TRADE_MODE)) + ", " + RdMarginModeText(RdAccountMarginMode()) +
        "), chart " + _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period));
   m_ctl.Refresh();   // MT4 logs in after OnInit
   m_tradeOk = false;
   m_cooldownWas = m_cfg.clickCooldownMs;
   SResult sr;
   if(!CSymbolSpec::Read(_Symbol, m_ts, sr))
     {
      Check(false, "setup", "spec of " + _Symbol + ": " + sr.message);
      return;
     }
   RestoreTp();   // own magic, no click cooldown
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   if(m_state.hidden)
      ClickObject("RD_P_HIDE");   // the panel shown in the screenshots
   m_panel.SetWanted(m_cfg.panelX, m_cfg.panelY);
   m_state.panelX = m_cfg.panelX;
   m_state.panelY = m_cfg.panelY;
   Line("setup: magic " + IntegerToString(RD_UITEST_MAGIC) + " (not the EA's), click cooldown off, confirmations answered Yes; " +
        CSymbolSpec::Describe(m_ts, AccountInfoString(ACCOUNT_CURRENCY)));
   if(!RdIsDemoAccount())
     {
      Line("INFO rule R13: not a demo account - no order is sent; only the line steps run");
      return;
     }
   CloseTestTrades("left by an earlier run");
   SResult why;
   if(!CAccountSpec::CanTrade(why))
     {
      m_permWhy = why.message;
      Line("INFO trading not possible (" + why.message + ") - the order steps are skipped; T-26 checks the refusal");
      return;
     }
   if(m_ts.tradeMode != SYMBOL_TRADE_MODE_FULL)
     {
      Line("INFO " + _Symbol + " trade mode is " + RdSymbolTradeModeText(m_ts.tradeMode) + " - the order steps are skipped");
      return;
     }
   SQuote q;
   if(!FreshQuote(q))
     {
      Line("INFO no quote for " + _Symbol + " - the order steps are skipped");
      return;
     }
   double tick = RdTick(m_ts);
   double dist = MathMax(0.0025 * q.bid, 2.0 * (m_ts.stopsLevel + m_ts.freezeLevel) * m_ts.point + 3.0 * (q.ask - q.bid) +
                         10.0 * tick);
   m_dist = MathCeil(dist / tick - 1e-9) * tick;
   double ask = RdNormalizePrice(m_ts, q.ask);
   double sl = RdRoundPriceDown(m_ts, q.bid - m_dist);
   double loss = ExpectedLoss(SIDE_BUY, ask, sl);
   double base = Base();
   if(!(loss > 0.0) || !(base > 0.0))
     {
      Check(false, "setup", "cannot value a " + RdFormatPrice(m_ts, m_dist) + " SL distance (loss/lot " + RdNum(loss, 2) +
            ", risk base " + RdNum(base, 2) + ")");
      return;
     }
   double minPct = m_ts.volMin * (loss + MathMax(0.0, m_cfg.commissionPerLot)) / base * 100.0;
   m_testRisk = MathMax(0.05, MathCeil(minPct * 2.5 * 100.0 - 1e-9) / 100.0);
   if(m_suite == "half")
      m_testRisk = MathMin(m_testRisk, 1.0);   // the half suite sizes its cases itself (HfAffordable), not by Risk %
   if(m_testRisk > 1.0)
     {
      Line("INFO the minimum lot " + RdFormatLots(m_ts, m_ts.volMin) + " risks " + RdFormatPct(minPct) + " at a " +
           RdFormatPrice(m_ts, m_dist) + " SL - more than a test should risk; the order steps are skipped");
      return;
     }
   Edit(DoubleToString(m_testRisk, 2));
   double raw = 0.0;
   double lots = ExpectedLots(SIDE_BUY, ask, sl, m_testRisk, raw);
   double need = 0.0;
   SResult mr;
   m_money.MarginFor(m_ts, SIDE_BUY, lots, ask, need, mr);
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   if(!(lots > 0.0) || need > 0.5 * acc.freeMargin)
     {
      Line("INFO a " + RdFormatLots(m_ts, lots) + " lot test position needs " + RdNum(need, 2) + " margin of " +
           RdNum(acc.freeMargin, 2) + " free - the order steps are skipped");
      return;
     }
   m_tradeOk = true;
   Line("setup: SL distance " + RdFormatPrice(m_ts, m_dist) + " (" + RdFormatPoints(RdPointsBetween(m_ts, ask, sl)) +
        "), Risk % " + RdNum(m_testRisk, 2) + " (min lot risks " + RdFormatPct(minPct) + ") -> about " +
        RdFormatLots(m_ts, lots) + " lot, margin " + RdNum(need, 2) + " of " + RdNum(acc.freeMargin, 2) + " free");
   bool known = false;
   datetime now = RdServerTime();
   m_marketClosed = !CMarket::InSession(_Symbol, now, known) && known;
   if(m_marketClosed)
      Line("INFO " + _Symbol + " is outside its trading sessions at " + TimeToString(now, TIME_MINUTES) +
           " server time (last quote " + IntegerToString(CMarket::AgeSeconds(q)) + " s old): T-27 runs, the other order steps do not");
  }

//+------------------------------------------------------------------+
//| T-27 market closed (BC-17): RiskDesk does not block (the server  |
//| decides); the broker's refusal must arrive as a red "Market      |
//| closed" with no position. Runs only when the chart symbol is     |
//| outside its trading sessions.                                    |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT27()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   string st = m_status.Text();
   Check(after == before && m_status.Severity() == SEV_ERROR && StringFind(st, "Market closed") >= 0, "T-27 market closed",
         "Buy on " + _Symbol + " outside its session: positions " + IntegerToString(before) + " -> " + IntegerToString(after) +
         ", status '" + st + "'");
   Line("INFO T-27 idle readout: '" + m_status.IdleText() + "' (last quote " + IntegerToString(CMarket::AgeSeconds(q)) +
        " s old, stale above " + IntegerToString(m_cfg.staleQuoteSec) + " s)");
   Shot("t27_market_closed");
   CloseTestTrades("after T-27");
  }

void CUiSelfTest::TradeEnd()
  {
   if(m_tradeOk)
      CloseTestTrades("end of the test");
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   m_cfg.Load();   // every setting the steps changed back to the inputs
   SGatewaySettings gs;
   m_cfg.Gateway(gs);
   m_gw.Configure(gs);
   m_cmd.SetTestConfirm(RD_CONFIRM_ASK);
   Edit(DoubleToString(m_cfg.defaultRiskPct, 2));
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| T-03 lines lifecycle (05 section 5 mode rules).                  |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT03()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   FreshQuote(q);
   double sl = m_plan.Price(LINEROLE_SL);
   bool wantTp = (m_cfg.tpMode == TPMODE_MANUAL_LINE);
   bool selected = ObjectGetInteger(0, CLines::LineName(LINEROLE_SL), OBJPROP_SELECTED) != 0;
   bool selectable = ObjectGetInteger(0, CLines::LineName(LINEROLE_SL), OBJPROP_SELECTABLE) != 0;
   bool ok = m_state.lineMode == LINES_MARKET && m_plan.Exists(LINEROLE_SL) && selected && selectable &&
             m_plan.Exists(LINEROLE_TP) == wantTp && !m_plan.Exists(LINEROLE_ENTRY) && sl > 0.0 && RdPriceLt(m_ts, sl, q.bid) &&
             m_status.Severity() == SEV_OK && StringFind(m_status.Text(), "SL line at") >= 0 && m_plan.LabelExists(LINEROLE_SL);
   Check(ok, "T-03 Add Line", "mode " + IntegerToString(m_state.lineMode) + ", SL line " + DoubleToString(sl, _Digits) +
         " (Bid " + DoubleToString(q.bid, _Digits) + "), selected " + RdBoolText(selected) + ", TP line " +
         RdBoolText(m_plan.Exists(LINEROLE_TP)) + " (TP mode " + m_cfg.TpModeText() + "), label '" +
         Text(CLines::LabelName(LINEROLE_SL)) + "', status '" + m_status.Text() + "'");
   ClickButton(PB_ADDLINE);
   Check(m_status.Severity() == SEV_WARN && StringFind(m_status.Text(), "already on chart") >= 0 &&
         MathAbs(m_plan.Price(LINEROLE_SL) - sl) < RdTick(m_ts) / 2.0, "T-03 Add Line again",
         "nothing moved, status '" + m_status.Text() + "'");
   Shot("t03_market_lines");
   CheckLabelBesidePanel(LINEROLE_SL);
  }

//+------------------------------------------------------------------+
//| ADR-024: the panel moved over a line's label -> after a refresh  |
//| the label is beside the panel, not under it; the panel goes back |
//| where it was. Measured on the label object as it is on the chart.|
//+------------------------------------------------------------------+
void CUiSelfTest::CheckLabelBesidePanel(const ELineRole role)
  {
   string name = CLines::LabelName(role);
   int lx = 0;
   int ly = 0;
   int lw = 0;
   int lh = 0;
   //--- the default line can be out of view (05 section 5: no clamp across the price): put it mid-chart
   double priceWas = m_plan.Price(role);
   bool movedLine = false;
   if(CLines::LabelBox(name, lx, ly, lw, lh) && (ly < 0 || ly + lh > ChartH()))
     {
      double lo = 0.0;
      double hi = 0.0;
      if(CLines::VisibleRange(lo, hi))
        {
         m_plan.Place(role, RdNormalizePrice(m_ts, (lo + hi) / 2.0));
         movedLine = true;
         m_ctl.Refresh();
        }
     }
   if(!CLines::LabelBox(name, lx, ly, lw, lh))
     {
      Check(false, "label beside panel", "no box for " + name);
      return;
     }
   int wantX = m_panel.WantedX();
   int wantY = m_panel.WantedY();
   //--- the panel's left third over the label's left part, centred on its line
   m_panel.SetWanted(lx + lw / 3, ly + lh / 2 - m_layout.Height() / 2);
   int px = m_panel.ShownX();
   int py = m_panel.ShownY();
   int pw = m_layout.Width();
   int ph = m_layout.ShownHeight(m_panel.Collapsed());
   bool coveredBefore = lx < px + pw && lx + lw > px && ly < py + ph && ly + lh > py;
   m_ctl.Refresh();
   int nx = 0;
   int ny = 0;
   int nw = 0;
   int nh = 0;
   bool boxed = CLines::LabelBox(name, nx, ny, nw, nh);
   bool coveredAfter = nx < px + pw && nx + nw > px && ny < py + ph && ny + nh > py;
   bool left = nx + nw <= px;
   Check(boxed && coveredBefore && !coveredAfter && nx >= 0 && nx + nw <= ChartW(), "label beside panel",
         "'" + Text(name) + "': " + IntegerToString(lx) + "-" + IntegerToString(lx + lw) + " px under the panel at " +
         IntegerToString(px) + "-" + IntegerToString(px + pw) + " (covered " + RdBoolText(coveredBefore) + ") -> " +
         IntegerToString(nx) + "-" + IntegerToString(nx + nw) + " px, " + (left ? "left of" : "right of") + " the panel" +
         " (y " + IntegerToString(ly) + "-" + IntegerToString(ly + lh) + ", panel y " + IntegerToString(py) + "-" +
         IntegerToString(py + ph) + (movedLine ? ", line moved into view for the check" : "") + ")");
   //--- ChartScreenShot renders the chart wider than it is, which shifts time-anchored labels against
   //    the pixel-anchored panel: the runner's capture of the real window shows the true picture
   m_labelWait = true;
   m_labelRole = role;
   m_labelMoved = movedLine;
   m_labelPriceWas = priceWas;
   m_labelWantX = wantX;
   m_labelWantY = wantY;
   RequestWindowCapture("label_beside_panel");
  }

// After the window capture: the panel and the line back where they were.
bool CUiSelfTest::LabelCheckRestore()
  {
   if(!WindowCaptured())
      return false;
   m_labelWait = false;
   m_panel.SetWanted(m_labelWantX, m_labelWantY);
   if(m_labelMoved)
      m_plan.Place(m_labelRole, m_labelPriceWas);
   m_ctl.Refresh();
   return true;
  }

void CUiSelfTest::TradeT03b()
  {
   ClickButton(PB_ADDPEND);
   string pinfo = Text("RD_E_PINFO");
   bool ok = m_state.lineMode == LINES_PENDING && m_plan.Exists(LINEROLE_ENTRY) && m_plan.Exists(LINEROLE_SL) &&
             m_status.Severity() == SEV_OK && StringFind(m_status.Text(), "Market lines replaced by pending lines") == 0 &&
             StringFind(pinfo, "Buy Stop") == 0 && m_plan.LabelExists(LINEROLE_ENTRY) &&
             StringFind(Text(CLines::LabelName(LINEROLE_ENTRY)), "ENTRY  Buy Stop") == 0 &&
             ObjectGetInteger(0, CLines::LineName(LINEROLE_ENTRY), OBJPROP_STYLE) == STYLE_DASHDOT;
   Check(ok, "T-03 Add Pend Line", "entry " + DoubleToString(m_plan.Price(LINEROLE_ENTRY), _Digits) + ", SL " +
         DoubleToString(m_plan.Price(LINEROLE_SL), _Digits) + ", Pending Info '" + pinfo + "', Lots '" + Text("RD_E_LOTS") +
         "', entry label '" + Text(CLines::LabelName(LINEROLE_ENTRY)) + "', status '" + m_status.Text() + "'");
   ClickButton(PB_ADDPEND);
   Check(m_status.Severity() == SEV_WARN && StringFind(m_status.Text(), "already on chart") >= 0, "T-03 Add Pend Line again",
         "status '" + m_status.Text() + "'");
   Shot("t03_pending_lines");
  }

void CUiSelfTest::TradeT03c()
  {
   ClickButton(PB_ADDLINE);
   bool market = m_state.lineMode == LINES_MARKET && !m_plan.Exists(LINEROLE_ENTRY) && m_plan.Exists(LINEROLE_SL) &&
                 StringFind(m_status.Text(), "Pending lines replaced by market lines") == 0 && Text("RD_E_PINFO") == "";
   Check(market, "T-03 back to market lines", "entry line gone " + RdBoolText(!m_plan.Exists(LINEROLE_ENTRY)) +
         ", Pending Info '" + Text("RD_E_PINFO") + "', status '" + m_status.Text() + "'");
   ClickButton(PB_DELLINE);
   int left = CountObjects(RD_LINE_PREFIX) + CountObjects(RD_LINE_LABEL_PREFIX);
   Check(left == 0 && m_state.lineMode == LINES_NONE && Text("RD_E_LOTS") == RdGlyphDash() &&
         m_status.Text() == "Lines removed", "T-03 Delete Line", IntegerToString(left) + " line objects left, Lots '" +
         Text("RD_E_LOTS") + "', status '" + m_status.Text() + "'");
   ClickButton(PB_DELLINE);
   Check(m_status.Severity() == SEV_WARN, "T-03 Delete Line again", "status '" + m_status.Text() + "'");
  }

//+------------------------------------------------------------------+
//| T-04 Lots preview and F-33 dimming. Lots must equal the lots     |
//| computed here from the raw valuation (quote before or after the  |
//| refresh: a tick may arrive in between).                          |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT04Buy()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   SQuote q2;
   FreshQuote(q2);
   double raw = 0.0;
   double raw2 = 0.0;
   double lots = ExpectedLots(SIDE_BUY, RdNormalizePrice(m_ts, q.ask), sl, m_testRisk, raw);
   double lots2 = ExpectedLots(SIDE_BUY, RdNormalizePrice(m_ts, q2.ask), sl, m_testRisk, raw2);
   string shown = Text("RD_E_LOTS");
   string label = Text(CLines::LabelName(LINEROLE_SL));
   bool lotsOk = shown == RdFormatLots(m_ts, lots) || shown == RdFormatLots(m_ts, lots2);
   bool ok = lotsOk && StringFind(label, "SL  ") == 0 && StringFind(label, shown + " lot") > 0 &&
             HasLook(PB_SELL, LOOK_DIM) && HasLook(PB_BUY, LOOK_NORMAL);
   Check(ok, "T-04 buy side", "SL " + RdFormatPrice(m_ts, sl) + " below Bid " + RdFormatPrice(m_ts, q.bid) + ": Lots '" + shown +
         "' (expected " + RdFormatLots(m_ts, lots) + ", raw " + RdNum(raw, 4) + "), label '" + label + "', Sell dimmed " +
         RdBoolText(HasLook(PB_SELL, LOOK_DIM)) + ", Buy normal " + RdBoolText(HasLook(PB_BUY, LOOK_NORMAL)));
   Shot("t04_buy_side");
  }

void CUiSelfTest::TradeT04Sell()
  {
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_SELL, 1.0, q, sl);
   SQuote q2;
   FreshQuote(q2);
   double raw = 0.0;
   double raw2 = 0.0;
   double lots = ExpectedLots(SIDE_SELL, RdNormalizePrice(m_ts, q.bid), sl, m_testRisk, raw);
   double lots2 = ExpectedLots(SIDE_SELL, RdNormalizePrice(m_ts, q2.bid), sl, m_testRisk, raw2);
   string shown = Text("RD_E_LOTS");
   bool ok = (shown == RdFormatLots(m_ts, lots) || shown == RdFormatLots(m_ts, lots2)) &&
             HasLook(PB_BUY, LOOK_DIM) && HasLook(PB_SELL, LOOK_NORMAL);
   Check(ok, "T-04 sell side", "SL " + RdFormatPrice(m_ts, sl) + " above Ask " + RdFormatPrice(m_ts, q.ask) + ": Lots '" + shown +
         "' (expected " + RdFormatLots(m_ts, lots) + "), Buy dimmed " + RdBoolText(HasLook(PB_BUY, LOOK_DIM)) +
         ", Buy tooltip '" + ObjectGetString(0, CPanel::ButtonName(PB_BUY), OBJPROP_TOOLTIP) + "'");
   //--- inside the spread: no side (SL at Bid; again when the quote moved during the drop)
   for(int attempt = 0; attempt < 8; attempt++)
     {
      FreshQuote(q);
      DropLine(LINEROLE_SL, RdNormalizePrice(m_ts, q.bid));
      FreshQuote(q2);
      if(RdPriceEq(m_ts, q.bid, q2.bid) && RdPriceEq(m_ts, q.ask, q2.ask))
         break;
     }
   string label = Text(CLines::LabelName(LINEROLE_SL));
   Check(Text("RD_E_LOTS") == RdGlyphDash() && HasLook(PB_BUY, LOOK_DIM) && HasLook(PB_SELL, LOOK_DIM) &&
         StringFind(label, "invalid") >= 0, "T-04 inside spread", "SL at Bid: Lots '" + Text("RD_E_LOTS") + "', both dimmed " +
         RdBoolText(HasLook(PB_BUY, LOOK_DIM) && HasLook(PB_SELL, LOOK_DIM)) + ", label '" + label + "'");
   //--- F-33 dim colour: 40 % towards the background, every channel between the two (on MT4 the
   //--- blend once wrapped around and drew dimmed buttons almost white)
   int sellBg = (int)ObjectGetInteger(0, CPanel::ButtonName(PB_SELL), OBJPROP_BGCOLOR);
   int normal = (int)m_theme.buttonBg[PB_SELL];
   int panelBg = (int)m_theme.bg;
   bool between = (sellBg >= 0 && sellBg <= 0xFFFFFF);
   for(int sh = 0; sh <= 16 && between; sh += 8)
     {
      int c = (sellBg >> sh) & 255;
      int a = (normal >> sh) & 255;
      int z = (panelBg >> sh) & 255;
      between = (c >= MathMin(a, z) && c <= MathMax(a, z));
     }
   color probe = CTheme::Blend(C'192,55,42', clrBlack, 0.4);
   Check(between && probe == C'115,33,25', "F-33 dim colour", "Sell dimmed " + IntegerToString(sellBg & 255) + "," +
         IntegerToString((sellBg >> 8) & 255) + "," + IntegerToString((sellBg >> 16) & 255) + " between its colour and the " +
         "background " + RdBoolText(between) + "; Blend(192,55,42 -> black, 0.4) = " + IntegerToString(probe & 255) + "," +
         IntegerToString((probe >> 8) & 255) + "," + IntegerToString((probe >> 16) & 255) + " (expected 115,33,25)");
   Shot("t04_inside_spread");
  }

void CUiSelfTest::TradeT04Risk()
  {
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   double twice = NormalizeDouble(2.0 * m_testRisk, 2);
   Edit(DoubleToString(twice, 2));
   SQuote q2;
   FreshQuote(q2);
   double raw = 0.0;
   double lots = ExpectedLots(SIDE_BUY, RdNormalizePrice(m_ts, q2.ask), sl, twice, raw);
   double rawA = 0.0;
   double lotsA = ExpectedLots(SIDE_BUY, RdNormalizePrice(m_ts, q.ask), sl, twice, rawA);
   string shown = Text("RD_E_LOTS");
   Check(shown == RdFormatLots(m_ts, lots) || shown == RdFormatLots(m_ts, lotsA), "T-04 Risk % change",
         "Risk % " + RdNum(twice, 2) + ": Lots '" + shown + "' (expected " + RdFormatLots(m_ts, lots) + ")");
   //--- below the minimum lot: red, the computed lot shown
   Edit("0.01");
   FreshQuote(q);
   double far = FarStop(q, 0.01);
   if(far > 0.0)
     {
      DropLine(LINEROLE_SL, far);
      bool red = (color)ObjectGetInteger(0, "RD_E_LOTS", OBJPROP_COLOR) == m_theme.statusError;
      Check(red && StringFind(Text("RD_E_LOTS"), "<") > 0 && StringFind(m_ctl.LotsTip(), "Min lot") == 0, "T-04 below min lot",
            "Risk % 0.01, SL " + RdFormatPrice(m_ts, far) + ": Lots '" + Text("RD_E_LOTS") + "' red " + RdBoolText(red) +
            ", tooltip '" + m_ctl.LotsTip() + "', label '" + Text(CLines::LabelName(LINEROLE_SL)) + "'");
      Shot("t04_below_min");
     }
   else
      Line("INFO T-04 below min lot: no SL far enough on " + _Symbol);
   Edit(DoubleToString(m_testRisk, 2));
  }

//+------------------------------------------------------------------+
//| T-26 permissions (BC-15): the terminal or the EA may not trade   |
//| (run-uitest.ps1 -Permissions). A valid Buy is refused with the   |
//| specific reason, nothing is sent, and the idle readout says it.  |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT26()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   FreshQuote(q);
   double sl = RdRoundPriceDown(m_ts, q.bid - MathMax(0.0025 * q.bid, (2.0 * m_ts.stopsLevel + 10.0) * m_ts.point));
   DropLine(LINEROLE_SL, sl);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   string st = m_status.Text();
   Check(after == before && m_status.Severity() == SEV_ERROR && st == "Buy refused: " + m_permWhy, "T-26 permissions",
         "valid lines, Buy: positions " + IntegerToString(before) + " -> " + IntegerToString(after) + ", status '" + st + "'");
   Check(StringFind(m_status.IdleText(), m_permWhy) >= 0, "T-26 idle readout", "'" + m_status.IdleText() + "'");
   Shot("t26_permissions");
  }

//+------------------------------------------------------------------+
//| T-07 wrong side: red reason, no request sent.                    |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT07()
  {
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_SELL, 1.0, q, sl);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   Check(m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "SL above Bid for a buy") >= 0 && after == before,
         "T-07 wrong side", "SL " + RdFormatPrice(m_ts, sl) + " above the price, Buy: positions " + IntegerToString(before) +
         " -> " + IntegerToString(after) + ", status '" + m_status.Text() + "'");
   Shot("t07_wrong_side");
  }

//+------------------------------------------------------------------+
//| T-09 below the minimum lot: refused with the min-lot risk.       |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT09()
  {
   Edit("0.01");
   SQuote q;
   FreshQuote(q);
   double far = FarStop(q, 0.01);
   if(far <= 0.0)
     {
      Line("INFO T-09: no SL far enough on " + _Symbol);
      Edit(DoubleToString(m_testRisk, 2));
      return;
     }
   DropLine(LINEROLE_SL, far);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   Check(m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "Min lot " + RdFormatLots(m_ts, m_ts.volMin) +
         " would risk") >= 0 && after == before, "T-09 below min lot", "Risk % 0.01: positions " + IntegerToString(before) +
         " -> " + IntegerToString(after) + ", status '" + m_status.Text() + "'");
   Edit(DoubleToString(m_testRisk, 2));
   //--- F-28 InpConfirmTrades: answered No -> nothing is sent
   SQuote q2;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q2, sl);
   m_cfg.confirmTrades = true;
   m_cmd.SetTestConfirm(RD_CONFIRM_NO);
   before = TestPositions(arr);
   ClickButton(PB_BUY);
   after = TestPositions(arr);
   Check(after == before && m_status.Severity() == SEV_WARN && m_status.Text() == "Buy cancelled - nothing was sent" &&
         StringFind(m_cmd.LastConfirm(), " at market?") > 0, "F-28 confirm trades: No", "confirmation '" + m_cmd.LastConfirm() +
         "', positions " + IntegerToString(before) + " -> " + IntegerToString(after) + ", status '" + m_status.Text() + "'");
   m_cmd.SetTestConfirm(RD_CONFIRM_YES);
   m_cfg.confirmTrades = false;
  }

#endif // RD_APP_UISELFTESTTRADELINES_MQH
