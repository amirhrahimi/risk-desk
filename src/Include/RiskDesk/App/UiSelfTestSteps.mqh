//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestSteps.mqh                               |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : the steps and checks of the panel self-test (T-01,     |
//|           T-02, T-20, T-21, T-25, T-37, text fit, glyph sheets). |
//|           Part of CUiSelfTest; included at the end of            |
//|           App/UiSelfTest.mqh (split to stay near ~600 lines,     |
//|           ADR-021).                                              |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTSTEPS_MQH
#define RD_APP_UISELFTESTSTEPS_MQH

//+------------------------------------------------------------------+
//| 05 section 1 / AC5: no text wider than its widget. Heights are   |
//| reported only: TextGetSize includes the font's line spacing, so  |
//| at the smallest scales a 6 pt line is taller than a 10 px button |
//| while its glyphs still fit (the screenshots show it).            |
//+------------------------------------------------------------------+
void CUiSelfTest::CheckTextFits(const string where)
  {
   string bad = "";
   int checked = 0;
   int tallest = 0;
   for(int b = 0; b < PB_COUNT; b++)
     {
      if(b == PB_SHOT)
         continue;
      string name = CPanel::ButtonName((EPanelButton)b);
      string text = ObjectGetString(0, name, OBJPROP_TEXT);
      string font = ObjectGetString(0, name, OBJPROP_FONT);
      int size = Prop(name, OBJPROP_FONTSIZE);
      int w = 0;
      int h = 0;
      CLayout::TextSize(font, size, text, w, h);
      checked++;
      tallest = MathMax(tallest, h - Prop(name, OBJPROP_YSIZE));
      if(w > Prop(name, OBJPROP_XSIZE) - 2)
         bad = RdJoin(bad, name + " '" + text + "' " + IntegerToString(w) + " px in " +
                      IntegerToString(Prop(name, OBJPROP_XSIZE)), "; ");
     }
   //--- the read-only fields shrink their font too (T-24: "Buy Stop · 0.27" had lost its "lot")
   string fields[] = {"RD_E_LOTS", "RD_E_PINFO"};
   for(int i = 0; i < ArraySize(fields); i++)
     {
      int w = 0;
      int h = 0;
      CLayout::TextSize(ObjectGetString(0, fields[i], OBJPROP_FONT), Prop(fields[i], OBJPROP_FONTSIZE),
                        ObjectGetString(0, fields[i], OBJPROP_TEXT), w, h);
      checked++;
      if(w > Prop(fields[i], OBJPROP_XSIZE) - 2)
         bad = RdJoin(bad, fields[i] + " '" + ObjectGetString(0, fields[i], OBJPROP_TEXT) + "' " + IntegerToString(w) +
                      " px in " + IntegerToString(Prop(fields[i], OBJPROP_XSIZE)), "; ");
     }
   //--- ADR-023: every widget inside the background, none on top of another; two columns: rows level
   EPanelItem items[] = {PI_HIDE, PI_RISK_CAP, PI_RISK, PI_LOTS_CAP, PI_LOTS, PI_ADDLINE, PI_DELLINE, PI_BUY, PI_SELL,
                         PI_ADDPEND, PI_SETPEND, PI_PINFO_CAP, PI_PINFO, PI_DELPEND, PI_RISKFREE, PI_HALF,
                         PI_CHARTCLOSE, PI_FULLCLOSE, PI_SPREAD, PI_STATUS1, PI_STATUS2, PI_STATUS3};
   SRect bg;
   m_layout.Rect(PI_BG, bg);
   for(int i = 0; i < ArraySize(items); i++)
     {
      SRect a;
      m_layout.Rect(items[i], a);
      checked++;
      if(a.x < bg.x || a.y < bg.y || a.x + a.w > bg.x + bg.w || a.y + a.h > bg.y + bg.h)
         bad = RdJoin(bad, CPanel::ItemName(items[i]) + " outside the panel", "; ");
      for(int j = i + 1; j < ArraySize(items); j++)
        {
         SRect b;
         m_layout.Rect(items[j], b);
         if(a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)
            bad = RdJoin(bad, CPanel::ItemName(items[i]) + " overlaps " + CPanel::ItemName(items[j]), "; ");
        }
     }
   if(m_layout.Columns() == 2)
     {
      EPanelItem lft[] = {PI_RISK, PI_LOTS, PI_ADDLINE, PI_DELLINE, PI_BUY, PI_SELL, PI_ADDPEND};
      EPanelItem rgt[] = {PI_PINFO_CAP, PI_PINFO, PI_DELPEND, PI_RISKFREE, PI_HALF, PI_CHARTCLOSE, PI_FULLCLOSE};
      for(int i = 0; i < ArraySize(lft); i++)
        {
         SRect a;
         SRect b;
         m_layout.Rect(lft[i], a);
         m_layout.Rect(rgt[i], b);
         checked++;
         if(a.y != b.y || a.h != b.h)
            bad = RdJoin(bad, CPanel::ItemName(rgt[i]) + " not level with " + CPanel::ItemName(lft[i]), "; ");
        }
     }
   //--- status lines must stay inside the panel
   int bgRight = Prop("RD_P_BG", OBJPROP_XDISTANCE) + Prop("RD_P_BG", OBJPROP_XSIZE);
   for(int i = 1; i <= RD_STATUS_LINES; i++)
     {
      string name = "RD_L_STATUS" + IntegerToString(i);
      int w = 0;
      int h = 0;
      CLayout::TextSize(ObjectGetString(0, name, OBJPROP_FONT), Prop(name, OBJPROP_FONTSIZE),
                        ObjectGetString(0, name, OBJPROP_TEXT), w, h);
      checked++;
      if(Prop(name, OBJPROP_XDISTANCE) + w > bgRight)
         bad = RdJoin(bad, name + " " + IntegerToString(w) + " px wide", "; ");
     }
   //--- rows at least one text line tall; captions inside their column; status inside the panel
   SRect r;
   int lineStatus = CLayout::LineHeight(m_theme.fontBody, m_layout.FontStatus());
   int lineBody = CLayout::LineHeight(m_theme.fontBody, m_layout.FontBody());
   m_layout.Rect(PI_STATUS1, r);
   checked++;
   if(r.h < lineStatus)
      bad = RdJoin(bad, "status row " + IntegerToString(r.h) + " px < line " + IntegerToString(lineStatus), "; ");
   m_layout.Rect(PI_SPREAD, r);
   checked++;
   if(r.h < lineBody)
      bad = RdJoin(bad, "spread row " + IntegerToString(r.h) + " px < line " + IntegerToString(lineBody), "; ");
   m_layout.Rect(PI_STATUS3, r);
   int statusBottom = r.y + r.h;
   m_layout.Rect(PI_BG, r);
   checked++;
   if(statusBottom > r.y + r.h)
      bad = RdJoin(bad, "status below the panel", "; ");
   int capW = 0;
   int capH = 0;
   CLayout::TextSize(m_theme.fontBody, m_layout.FontBody(), "Risk %", capW, capH);
   m_layout.Rect(PI_RISK_CAP, r);
   checked++;
   if(capW > r.w)
      bad = RdJoin(bad, "'Risk %' " + IntegerToString(capW) + " px in a " + IntegerToString(r.w) + " px column", "; ");
   Check(bad == "", "text fit " + where, IntegerToString(checked) + " texts checked, scale " + RdNum(m_layout.Scale(), 2) +
         ", body font " + m_theme.fontBody + " " + IntegerToString(m_layout.FontBody()) + " pt, panel " +
         IntegerToString(m_layout.Width()) + " x " + IntegerToString(m_layout.Height()) + " px, " +
         IntegerToString(m_layout.Columns()) + (m_layout.Columns() == 2 ? " columns" : " column") + ", line height - button height " +
         IntegerToString(tallest) + " px" + (bad == "" ? "" : " - overflow: " + bad));
  }

//+------------------------------------------------------------------+
//| T-37 arithmetic: Shape Size Scale 1.6 with auto-fit on, for many |
//| chart sizes: never above 1.6, the panel fits (unless 0.40 is     |
//| reached), and it grows back when the chart grows. Auto-fit off:  |
//| always 1.6.                                                      |
//+------------------------------------------------------------------+
void CUiSelfTest::CheckFitMath()
  {
   CLayout probe;
   int dpi = RdTerminalDpi();
   int heights[] = {200, 260, 320, 400, 480, 560, 640, 720, 800, 900, 1000, 1200, 1600};
   int widths[] = {150, 260, 400, 1200};
   EPanelColumns modes[] = {PANEL_COLUMNS_ONE, PANEL_COLUMNS_TWO};
   for(int mi = 0; mi < ArraySize(modes); mi++)
     {
      string bad = "";
      string table = "";
      for(int wi = 0; wi < ArraySize(widths); wi++)
         for(int hi = 0; hi < ArraySize(heights); hi++)
           {
            probe.Configure(1.6, true, modes[mi], dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
            probe.Fit(widths[wi], heights[hi]);
            double s = probe.Scale();
            bool fits = probe.HeightAt(s) <= heights[hi] - RD_LY_FIT_MARGIN && probe.WidthAt(s) <= widths[wi] - RD_LY_FIT_MARGIN;
            bool ok = s <= 1.6 + 1e-9 && s >= RD_LY_MIN_SCALE - 1e-9 && (fits || MathAbs(s - RD_LY_MIN_SCALE) < 1e-9) &&
                      probe.Columns() == mi + 1;
            //--- one step larger would not fit (the largest fitting scale was chosen)
            if(ok && s < 1.6 - 1e-9 && s > RD_LY_MIN_SCALE + 1e-9)
               ok = probe.HeightAt(s + 0.01) > heights[hi] - RD_LY_FIT_MARGIN || probe.WidthAt(s + 0.01) > widths[wi] - RD_LY_FIT_MARGIN;
            if(!ok)
               bad = RdJoin(bad, IntegerToString(widths[wi]) + "x" + IntegerToString(heights[hi]) + " -> " + RdNum(s, 2), ", ");
            if(widths[wi] == 1200)
               table = RdJoin(table, IntegerToString(heights[hi]) + ":" + RdNum(s, 2), " ");
           }
      Check(bad == "", mi == 0 ? "T-37 fit math" : "T-37 fit math 2 columns",
            "scale by chart height (width 1200): " + table + (bad == "" ? "" : " - wrong: " + bad));
     }

   probe.Configure(1.6, true, PANEL_COLUMNS_ONE, dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
   probe.Fit(1200, 300);
   double small = probe.Scale();
   probe.Fit(1200, 2000);
   Check(small < 1.6 && MathAbs(probe.Scale() - 1.6) < 1e-9, "T-37 grows back",
         "300 px -> " + RdNum(small, 2) + ", then 2000 px -> " + RdNum(probe.Scale(), 2));

   probe.Configure(1.6, false, PANEL_COLUMNS_ONE, dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
   probe.Fit(1200, 300);
   Check(MathAbs(probe.Scale() - 1.6) < 1e-9, "T-37 auto-fit off", "300 px chart keeps scale " + RdNum(probe.Scale(), 2));

   //--- ADR-023 Auto: one column unless it fits only below 85 % of Shape Size Scale and two columns get a larger
   //    scale (or, both at 0.40, one column is cut off and two columns fit the width)
   CLayout one;
   CLayout two;
   string badAuto = "";
   string tableAuto = "";
   int autoWidths[] = {400, 1200};
   for(int wi = 0; wi < ArraySize(autoWidths); wi++)
      for(int hi = 0; hi < ArraySize(heights); hi++)
        {
         one.Configure(1.0, true, PANEL_COLUMNS_ONE, dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
         two.Configure(1.0, true, PANEL_COLUMNS_TWO, dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
         probe.Configure(1.0, true, PANEL_COLUMNS_AUTO, dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
         one.Fit(autoWidths[wi], heights[hi]);
         two.Fit(autoWidths[wi], heights[hi]);
         probe.Fit(autoWidths[wi], heights[hi]);
         bool cutOff = MathAbs(two.Scale() - one.Scale()) < 1e-9 && one.Height() > heights[hi] - RD_LY_FIT_MARGIN &&
                       two.Width() <= autoWidths[wi] - RD_LY_FIT_MARGIN;
         bool wantTwo = one.Scale() < RD_LY_TWO_COL_BELOW - 1e-9 && (two.Scale() > one.Scale() + 1e-9 || cutOff);
         double wantScale = wantTwo ? two.Scale() : one.Scale();
         string got = IntegerToString(probe.Columns()) + "c " + RdNum(probe.Scale(), 2);
         if(probe.Columns() != (wantTwo ? 2 : 1) || MathAbs(probe.Scale() - wantScale) > 1e-9)
            badAuto = RdJoin(badAuto, IntegerToString(autoWidths[wi]) + "x" + IntegerToString(heights[hi]) + " -> " + got, ", ");
         if(autoWidths[wi] == 1200)
            tableAuto = RdJoin(tableAuto, IntegerToString(heights[hi]) + ":" + got, " ");
        }
   Check(badAuto == "", "columns auto", "Shape Size Scale 1.00, width 1200: " + tableAuto +
         (badAuto == "" ? "" : " - wrong: " + badAuto));
   probe.Configure(1.6, false, PANEL_COLUMNS_AUTO, dpi, m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
   probe.Fit(1200, 300);
   int colsShort = probe.Columns();
   probe.Fit(1200, 2000);
   Check(colsShort == 2 && probe.Columns() == 1 && MathAbs(probe.Scale() - 1.6) < 1e-9, "columns auto, auto-fit off",
         "scale 1.60: 300 px chart -> " + IntegerToString(colsShort) + " columns, 2000 px -> " + IntegerToString(probe.Columns()));
  }

//+------------------------------------------------------------------+
//| F-01 AC4 / T-37: handle to camera inside the chart area.         |
//+------------------------------------------------------------------+
void CUiSelfTest::CheckInView(const string id)
  {
   int left = Prop("RD_P_BG", OBJPROP_XDISTANCE);
   int right = left + Prop("RD_P_BG", OBJPROP_XSIZE);
   int top = Prop("RD_P_HANDLE", OBJPROP_YDISTANCE);
   int bottom = m_panel.Collapsed() ? Prop("RD_P_BG", OBJPROP_YDISTANCE) + Prop("RD_P_BG", OBJPROP_YSIZE) :
                Prop("RD_B_SHOT", OBJPROP_YDISTANCE) + Prop("RD_B_SHOT", OBJPROP_YSIZE);
   bool ok = left >= 0 && top >= 0 && right <= ChartW() && bottom <= ChartH();
   Check(ok, id, "panel x " + IntegerToString(left) + "-" + IntegerToString(right) + ", y " + IntegerToString(top) + "-" +
         IntegerToString(bottom) + " in a " + IntegerToString(ChartW()) + " x " + IntegerToString(ChartH()) + " px chart");
  }

//+------------------------------------------------------------------+
//| The ui.ini / acct_*.ini file layer on a scratch file.            |
//+------------------------------------------------------------------+
void CUiSelfTest::CheckKeyValueFile()
  {
   string path = RD_UITEST_DIR + "\\kv_selftest.ini";
   CKeyValueFile f;
   f.SetInt("panel_x", 1075);
   f.SetInt("panel_y", -3);
   f.SetBool("hidden", true);
   f.SetDouble("risk_pct", 0.75, 2);
   f.SetString("text", "a = b");
   bool saved = f.Save(path, "self-test");
   CKeyValueFile g;
   bool loaded = g.Load(path);
   bool same = g.GetInt("panel_x", 0) == 1075 && g.GetInt("panel_y", 0) == -3 && g.GetBool("hidden", false) &&
               MathAbs(g.GetDouble("risk_pct", 0) - 0.75) < 1e-9 && g.GetString("text", "") == "a = b" &&
               g.GetInt("missing", 42) == 42 && g.Count() == 5;
   Check(saved && loaded && same && !FileIsExist(path + ".tmp"), "T-21 file layer",
         "save " + RdBoolText(saved) + ", load " + RdBoolText(loaded) + ", values " + RdBoolText(same));
   CKeyValueFile none;
   Check(!none.Load(RD_UITEST_DIR + "\\does_not_exist.ini") && none.Count() == 0, "T-21 missing file", "empty, defaults used");
   FileDelete(path);
  }

//+------------------------------------------------------------------+
void CUiSelfTest::StepInit()
  {
   Line("RiskDesk " + RD_VERSION + " panel self-test, " + RD_PLATFORM + " build " + IntegerToString(RdTerminalBuild()) +
        ", account " + IntegerToString(CAccountSpec::Login()) + " " + AccountInfoString(ACCOUNT_SERVER) +
        ", chart " + _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + " " + IntegerToString(ChartW()) +
        " x " + IntegerToString(ChartH()) + " px, DPI " + IntegerToString(RdTerminalDpi()));
   m_ctl.Refresh();   // MT4 logs in after OnInit: this loads the account's Risk %
   int missing = 0;
   for(int i = 0; i < PI_COUNT; i++)
      if(ObjectFind(0, CPanel::ItemName((EPanelItem)i)) < 0)
         missing++;
   Check(missing == 0, "T-01 panel", IntegerToString(PI_COUNT - missing) + "/" + IntegerToString(PI_COUNT) +
         " objects, scale " + RdNum(m_layout.Scale(), 2) + " (Shape Size Scale " + RdNum(m_layout.UserScale(), 2) + ")");
   CheckInView("T-01 in view");
   Check(m_status.Severity() == SEV_OK && StringFind(m_status.Text(), "ready") >= 0, "T-01 status",
         "'" + m_status.Text() + "'");
   SQuote q;
   bool quoteOk = CMarket::Quote(_Symbol, q);
   string buy = ObjectGetString(0, "RD_B_BUY", OBJPROP_TEXT);
   string sell = ObjectGetString(0, "RD_B_SELL", OBJPROP_TEXT);
   Check(!quoteOk || (StringFind(buy, "Buy ") == 0 && StringFind(sell, "Sell ") == 0), "prices on Buy/Sell",
         "'" + buy + "' / '" + sell + "' (quote " + RdBoolText(quoteOk) + ")");
   string spread = ObjectGetString(0, "RD_L_SPREAD", OBJPROP_TEXT);
   Check(StringFind(spread, "Spread: ") == 0, "F-15 spread", "'" + spread + "'");
   Check(ObjectGetString(0, "RD_E_LOTS", OBJPROP_TEXT) != "" && Prop("RD_E_LOTS", OBJPROP_READONLY) != 0 &&
         Prop("RD_E_PINFO", OBJPROP_READONLY) != 0 && Prop("RD_E_RISK", OBJPROP_READONLY) == 0, "fields",
         "Lots '" + ObjectGetString(0, "RD_E_LOTS", OBJPROP_TEXT) + "' read-only, Pending Info read-only, Risk % editable");
   Check(StringLen(ObjectGetString(0, "RD_B_FULLCLOSE", OBJPROP_TOOLTIP)) > 10 &&
         StringLen(ObjectGetString(0, "RD_B_HALF", OBJPROP_TOOLTIP)) > 10, "tooltips",
         "Half Close: '" + ObjectGetString(0, "RD_B_HALF", OBJPROP_TOOLTIP) + "'");
   StepRestartCheck();
   CheckTextFits("initial");
   m_homeX = m_state.panelX;
   m_homeY = m_state.panelY;
   Shot("init");
  }

//+------------------------------------------------------------------+
//| T-02: 1,5 / 0 / 12 / abc / " 0.25 " -> 1.50 / revert+red x3 /    |
//| 0.25.                                                            |
//+------------------------------------------------------------------+
void CUiSelfTest::StepRisk()
  {
   string inputs[] = {"1,5", "0", "12", "abc", " 0.25 "};
   string expect[] = {"1.50", "1.50", "1.50", "1.50", "0.25"};
   ESeverity sevs[] = {SEV_OK, SEV_ERROR, SEV_ERROR, SEV_ERROR, SEV_OK};
   for(int i = 0; i < ArraySize(inputs); i++)
     {
      Edit(inputs[i]);
      string shown = ObjectGetString(0, "RD_E_RISK", OBJPROP_TEXT);
      bool ok = shown == expect[i] && m_status.Severity() == sevs[i] && MathAbs(m_state.riskPct - StringToDouble(expect[i])) < 1e-9;
      Check(ok, "T-02 '" + inputs[i] + "'", "field " + shown + ", " + RdSeverityText(m_status.Severity()) + " '" +
            m_status.Text() + "'");
     }
   Edit(DoubleToString(m_cfg.defaultRiskPct, 2));
   Shot("risk_0_25_then_reset");
  }

//+------------------------------------------------------------------+
//| R8: every button answers with a status and a log line; the       |
//| button pops back up. Buttons of later phases are amber "not      |
//| implemented yet". The order (Add Line, Delete Line, then Buy and |
//| Sell without lines, Set Pending after the pending lines were     |
//| removed, Del Pending only when no order is in its scope) never   |
//| sends an order. Risk Free, Half Close and Chart Close are        |
//| clicked only when no position is in their scope; Full Close when |
//| none is in its scope, else with its confirmation answered No.    |
//| Then the cooldown (F-06 AC6).                                    |
//+------------------------------------------------------------------+
void CUiSelfTest::StepButtons()
  {
   for(int b = 0; b < PB_COUNT; b++)
     {
      EPanelButton pb = (EPanelButton)b;
      string name = CPanel::ButtonName(pb);
      bool answerNo = false;
      if(pb == PB_SETPEND)
        {
         CLines::DeleteAll();   // Add Pend Line left its lines: Set Pending must not place an order
         m_state.lineMode = LINES_NONE;
        }
      if(pb == PB_RISKFREE || pb == PB_HALF || pb == PB_CHARTCLOSE || pb == PB_FULLCLOSE)
        {
         int inScope = ManageScopeCount(pb);
         if(inScope != 0 && (pb != PB_FULLCLOSE || !m_cfg.confirmFullClose))
           {
            Line("INFO R8 " + CPanel::ButtonCaption(pb) + " not clicked: " + (inScope < 0 ? "the trades cannot be listed" :
                 "it would act on " + IntegerToString(inScope) + " trade(s)") + " (the panel suite never trades; the manage suite checks it)");
            continue;
           }
         answerNo = (inScope != 0);
        }
      if(pb == PB_DELPEND)
        {
         STradeFilter f;
         f.Reset();
         f.symbol = _Symbol;
         f.toolOnly = (m_cfg.scopeChartOps == SCOPE_TOOL_ON_SYMBOL);
         f.includeStopLimit = true;
         SOrder ord[];
         SResult lr;
         if(!m_gw.ListPending(f, ord, lr) || ArraySize(ord) > 0)
           {
            Line("INFO R8 Del Pending not clicked: it would delete " + IntegerToString(ArraySize(ord)) + " pending order(s) on " +
                 _Symbol + " (the panel suite never trades; the pending suite checks it)");
            continue;
           }
        }
      string before = m_status.Text();
      if(answerNo)
         m_cmd.SetTestConfirm(RD_CONFIRM_NO);
      ClickObject(name);
      if(answerNo)
         m_cmd.SetTestConfirm(RD_CONFIRM_ASK);
      string text = m_status.Text();
      bool refused = m_status.Severity() == SEV_ERROR && StringFind(text, "refused") >= 0;
      bool answered = CCommands::Implemented(pb) ? (text != "" && (text != before || pb == PB_DELLINE)) :
                      ((m_status.Severity() == SEV_WARN && StringFind(text, "not implemented yet") >= 0) || refused);
      if(pb == PB_BUY || pb == PB_SELL)
         answered = refused && StringFind(text, "no SL line") >= 0;
      if(pb == PB_SETPEND)
         answered = refused && StringFind(text, "no Entry and SL lines") >= 0;
      if(pb == PB_DELPEND)
         answered = m_status.Severity() == SEV_WARN && StringFind(text, "No ") == 0 && StringFind(text, "pending orders on") > 0;
      if(pb == PB_RISKFREE || pb == PB_HALF || pb == PB_CHARTCLOSE || pb == PB_FULLCLOSE)
        {
         answered = m_status.Severity() == SEV_WARN && StringFind(text, CPanel::ButtonCaption(pb)) == 0 &&
                    StringFind(text, answerNo ? "cancelled - nothing was sent" : ": no ") > 0;
         // BC-15 comes first: a terminal or account that does not allow trading is said in red
         if(!answered && refused && StringFind(text, CPanel::ButtonCaption(pb) + " refused: ") == 0)
            answered = true;
        }
      Check(answered && Prop(name, OBJPROP_STATE) == 0, "R8 " + CPanel::ButtonCaption(pb),
            RdSeverityText(m_status.Severity()) + " '" + text + "'");
     }
   CLines::DeleteAll();   // Add Pend Line left its lines
   m_state.lineMode = LINES_NONE;
   string before = m_status.Text();
   ClickObject("RD_B_BUY");   // clicked a moment ago: within the cooldown
   Check(m_status.Text() == before && Prop("RD_B_BUY", OBJPROP_STATE) == 0, "T-25 cooldown",
         "second Buy click within " + IntegerToString(m_cfg.clickCooldownMs) + " ms ignored, status still '" + before + "'");
   Shot("button_status");
  }

void CUiSelfTest::StepCooldownOver()
  {
   ClickObject("RD_B_BUY");
   Check(StringFind(m_status.Text(), "Buy") == 0, "T-25 after cooldown", "'" + m_status.Text() + "'");
  }

void CUiSelfTest::StepHide()
  {
   int fullH = Prop("RD_P_BG", OBJPROP_YSIZE);
   ClickObject("RD_P_HIDE");
   bool hidden = m_state.hidden && m_panel.Collapsed() && Prop("RD_B_BUY", OBJPROP_TIMEFRAMES) == RD_OBJ_NO_PERIODS &&
                 Prop("RD_P_TITLE", OBJPROP_TIMEFRAMES) != RD_OBJ_NO_PERIODS && Prop("RD_P_BG", OBJPROP_YSIZE) < fullH;
   Check(hidden, "F-01 hide", "background " + IntegerToString(fullH) + " -> " + IntegerToString(Prop("RD_P_BG", OBJPROP_YSIZE)) +
         " px, buttons hidden, title shown, ui marked for saving " + RdBoolText(m_state.uiDirty));
   Shot("hidden");
  }

void CUiSelfTest::StepShow()
  {
   ClickObject("RD_P_HIDE");
   Check(!m_state.hidden && Prop("RD_B_BUY", OBJPROP_TIMEFRAMES) != RD_OBJ_NO_PERIODS, "F-01 show", "panel restored");
  }

void CUiSelfTest::StepDrag()
  {
   int x0 = Prop("RD_P_BG", OBJPROP_XDISTANCE);
   int y0 = Prop("RD_P_BG", OBJPROP_YDISTANCE);
   int dx = (x0 + 120 + m_layout.Width() <= ChartW()) ? 120 : -120;
   int dy = (m_panel.ShownY() + 60 + m_layout.Height() <= ChartH()) ? 60 : -MathMin(60, m_panel.ShownY());
   Drag(dx, dy);
   int x1 = Prop("RD_P_BG", OBJPROP_XDISTANCE);
   int y1 = Prop("RD_P_BG", OBJPROP_YDISTANCE);
   bool scrollBack = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0) == m_scrollAtStart;
   Check(x1 - x0 == dx && y1 - y0 == dy && m_state.panelX == m_panel.WantedX() && scrollBack, "F-01 drag",
         "moved by " + IntegerToString(x1 - x0) + ", " + IntegerToString(y1 - y0) + " (asked " + IntegerToString(dx) + ", " +
         IntegerToString(dy) + "), saved position " + IntegerToString(m_state.panelX) + ", " + IntegerToString(m_state.panelY) +
         ", chart scroll restored " + RdBoolText(scrollBack));
  }

void CUiSelfTest::StepClamp()
  {
   Drag(5000, 5000);
   int x = m_panel.ShownX();
   int y = m_panel.ShownY();
   int wantX = MathMax(0, ChartW() - m_layout.Width());
   int wantY = MathMax(0, ChartH() - m_layout.Height());
   Check(x == wantX && y == wantY, "F-01 clamp", "dragged far right/down: anchor " + IntegerToString(x) + ", " +
         IntegerToString(y) + " (expected " + IntegerToString(wantX) + ", " + IntegerToString(wantY) +
         ": the whole panel in view)");
   Shot("clamped_bottom_right");
  }

void CUiSelfTest::StepHome()
  {
   Drag(-5000, -5000);
   Check(m_panel.ShownX() == 0 && m_panel.ShownY() == 0, "F-01 clamp top-left", "anchor " + IntegerToString(m_panel.ShownX()) +
         ", " + IntegerToString(m_panel.ShownY()));
   m_panel.SetWanted(m_homeX, m_homeY);
   m_state.panelX = m_homeX;
   m_state.panelY = m_homeY;
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| Debug aid for ADR-021: every character 0x21-0xFF of a symbol     |
//| font in a grid with its code, to pick glyphs that MT4 can draw.  |
//+------------------------------------------------------------------+
void CUiSelfTest::GlyphSheet(const string font, const bool show)
  {
   RdDeleteObjects("RD_T_G");
   if(!show)
      return;
   for(int c = 0x21; c <= 0xFF; c++)
     {
      int i = c - 0x21;
      int x = 230 + (i % 16) * 56;
      int y = 6 + (i / 16) * 27;
      string code = "RD_T_GC" + IntegerToString(c);
      string glyph = "RD_T_GG" + IntegerToString(c);
      ObjectCreate(0, code, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, code, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, code, OBJPROP_YDISTANCE, y + 4);
      ObjectSetString(0, code, OBJPROP_TEXT, StringFormat("%02X", c));
      ObjectSetString(0, code, OBJPROP_FONT, "Arial");
      ObjectSetInteger(0, code, OBJPROP_FONTSIZE, 7);
      ObjectSetInteger(0, code, OBJPROP_COLOR, clrSilver);
      ObjectCreate(0, glyph, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, glyph, OBJPROP_XDISTANCE, x + 20);
      ObjectSetInteger(0, glyph, OBJPROP_YDISTANCE, y);
      ObjectSetString(0, glyph, OBJPROP_TEXT, ShortToString((ushort)c));
      ObjectSetString(0, glyph, OBJPROP_FONT, font);
      ObjectSetInteger(0, glyph, OBJPROP_FONTSIZE, 13);
      ObjectSetInteger(0, glyph, OBJPROP_COLOR, clrWhite);
     }
   Line("glyph sheet " + font + " drawn");
  }

int CUiSelfTest::CountObjects(const string prefix) const
  {
   int n = 0;
   int len = StringLen(prefix);
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
      if(StringSubstr(ObjectName(0, i, -1, -1), 0, len) == prefix)
         n++;
   return n;
  }

//+------------------------------------------------------------------+
//| T-21, second half: the previous run saved a state (risk 0.75,    |
//| moved, hidden) and closed the terminal; this run must start with |
//| it. Then back to the defaults for the rest of the run.           |
//+------------------------------------------------------------------+
void CUiSelfTest::StepRestartCheck()
  {
   CKeyValueFile e;
   if(!e.Load(ExpectPath()))
     {
      Line("INFO T-21 restart: no state saved by a previous self-test run here - run it once more to check the restore");
      return;
     }
   FileDelete(ExpectPath());
   if(e.GetString("login", "") != IntegerToString(CAccountSpec::Login()))
      // ui.ini is shared by every account (D17): the other account's saved position and
      // hidden flag apply here too, so the defaults below are still needed
      Line("INFO T-21 restart: the saved state belongs to account " + e.GetString("login", "?") + " - not checked");
   else
     {
      double risk = e.GetDouble("risk_pct", -1.0);
      int x = e.GetInt("panel_x", -1);
      int y = e.GetInt("panel_y", -1);
      bool hidden = e.GetBool("hidden", false);
      bool ok = MathAbs(m_state.riskPct - risk) < 1e-9 && ObjectGetString(0, "RD_E_RISK", OBJPROP_TEXT) == DoubleToString(risk, 2) &&
                m_state.panelX == x && m_state.panelY == y && m_state.hidden == hidden && m_panel.Collapsed() == hidden;
      Check(ok, "T-21 restart", "after the terminal restart: risk " + RdNum(m_state.riskPct, 2) + " (saved " + RdNum(risk, 2) +
            "), position " + IntegerToString(m_state.panelX) + ", " + IntegerToString(m_state.panelY) + " (saved " +
            IntegerToString(x) + ", " + IntegerToString(y) + "), " + (m_state.hidden ? "hidden" : "shown") + " (saved " +
            (hidden ? "hidden" : "shown") + ")");
      Shot("restart_restored");
     }
   if(m_state.hidden)
      ClickObject("RD_P_HIDE");
   m_panel.SetWanted(m_cfg.panelX, m_cfg.panelY);
   m_state.panelX = m_cfg.panelX;
   m_state.panelY = m_cfg.panelY;
   Edit(DoubleToString(m_cfg.defaultRiskPct, 2));
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| T-20: the SL line of Add Line, Risk % 0.75, panel hidden; then a |
//| timeframe change.                                                |
//+------------------------------------------------------------------+
void CUiSelfTest::StepTfChange()
  {
   ApplyLook(m_cfg.scale, m_cfg.autoFitPanel, m_cfg.fontPreset, m_cfg.panelColumns);
   m_origSymbol = _Symbol;
   m_origPeriod = (ENUM_TIMEFRAMES)_Period;
   ClickObject(CPanel::ButtonName(PB_ADDLINE));
   Edit("0,75");
   ClickObject("RD_P_HIDE");
   m_t20X = m_state.panelX;
   m_t20Y = m_state.panelY;
   m_t20Risk = m_state.riskPct;
   m_objCount = CountObjects("RD_");
   m_t20Lines = CountObjects(RD_LINE_PREFIX) + CountObjects(RD_LINE_LABEL_PREFIX);
   m_tfPeriod = (m_origPeriod == PERIOD_M15) ? PERIOD_M30 : PERIOD_M15;
   m_waits = 0;
   Line("T-20 setup: line RD_LN_SL, Risk % " + RdNum(m_t20Risk, 2) + ", panel hidden, " + IntegerToString(m_objCount) +
        " RD_ objects; timeframe " + EnumToString(m_origPeriod) + " -> " + EnumToString(m_tfPeriod));
   ChartSetSymbolPeriod(0, _Symbol, m_tfPeriod);
  }

// False while the terminal has not switched yet (at most 20 steps).
bool CUiSelfTest::StepTfCheck()
  {
   if(_Period != m_tfPeriod && m_waits++ < 20)
      return false;
   int n = CountObjects("RD_");
   bool ok = _Period == m_tfPeriod && n == m_objCount && ObjectFind(0, "RD_LN_SL") >= 0 && m_state.hidden &&
             m_panel.Collapsed() && m_state.panelX == m_t20X && m_state.panelY == m_t20Y &&
             MathAbs(m_state.riskPct - m_t20Risk) < 1e-9 && ObjectGetString(0, "RD_E_RISK", OBJPROP_TEXT) == "0.75";
   Check(ok, "T-20 timeframe", EnumToString((ENUM_TIMEFRAMES)_Period) + ": " + IntegerToString(n) + " RD_ objects (before " +
         IntegerToString(m_objCount) + "), line kept " + RdBoolText(ObjectFind(0, "RD_LN_SL") >= 0) + ", hidden " +
         RdBoolText(m_state.hidden) + ", position " + IntegerToString(m_state.panelX) + ", " + IntegerToString(m_state.panelY) +
         ", Risk % field '" + ObjectGetString(0, "RD_E_RISK", OBJPROP_TEXT) + "'");
   Shot("tf_changed");
   m_otherSymbol = "";
   for(int i = 0; i < SymbolsTotal(true) && m_otherSymbol == ""; i++)
     {
      string name = SymbolName(i, true);
      if(name != _Symbol)
         m_otherSymbol = name;
     }
   m_waits = 0;
   if(m_otherSymbol == "")
     {
      Line("INFO T-20 symbol: no other symbol in Market Watch - not checked");
      return true;
     }
   Line("T-20 setup: symbol " + _Symbol + " -> " + m_otherSymbol);
   ChartSetSymbolPeriod(0, m_otherSymbol, m_tfPeriod);
   return true;
  }

bool CUiSelfTest::StepSymbolCheck()
  {
   if(m_otherSymbol == "")
      return true;
   if(_Symbol != m_otherSymbol && m_waits++ < 20)
      return false;
   int n = CountObjects("RD_");
   bool ok = _Symbol == m_otherSymbol && ObjectFind(0, "RD_LN_SL") < 0 && n == m_objCount - m_t20Lines &&
             ObjectGetString(0, "RD_S_CHART", OBJPROP_TEXT) == _Symbol && m_state.hidden &&
             m_state.panelX == m_t20X && m_state.panelY == m_t20Y && MathAbs(m_state.riskPct - m_t20Risk) < 1e-9 &&
             StringFind(m_status.Text(), "Lines removed") == 0;
   Check(ok, "T-20 symbol", _Symbol + ": line removed " + RdBoolText(ObjectFind(0, "RD_LN_SL") < 0) + ", " + IntegerToString(n) +
         " RD_ objects, panel kept (hidden " + RdBoolText(m_state.hidden) + ", position " + IntegerToString(m_state.panelX) +
         ", " + IntegerToString(m_state.panelY) + ", Risk % " + RdNum(m_state.riskPct, 2) + "), status '" + m_status.Text() + "'");
   Shot("symbol_changed");
   m_waits = 0;
   ChartSetSymbolPeriod(0, m_origSymbol, m_origPeriod);
   return true;
  }

bool CUiSelfTest::StepBack()
  {
   if((_Symbol != m_origSymbol || _Period != m_origPeriod) && m_waits++ < 20)
      return false;
   Check(_Symbol == m_origSymbol && _Period == m_origPeriod, "T-20 back", "chart back on " + _Symbol + " " +
         EnumToString((ENUM_TIMEFRAMES)_Period));
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   if(m_state.hidden)
      ClickObject("RD_P_HIDE");
   Edit(DoubleToString(m_cfg.defaultRiskPct, 2));
   return true;
  }

//+------------------------------------------------------------------+
//| T-21, first half: the user's gestures that are saved: Risk %,    |
//| a drag, hide. Saved for real (in the sandbox folder) once the    |
//| 1 s debounce has passed.                                         |
//+------------------------------------------------------------------+
void CUiSelfTest::StepSaveState()
  {
   ApplyLook(m_cfg.scale, m_cfg.autoFitPanel, m_cfg.fontPreset, m_cfg.panelColumns);
   Edit("0,75");
   Drag(60 - m_panel.ShownX(), 30 - m_panel.ShownY());
   ClickObject("RD_P_HIDE");
   m_saveX = m_state.panelX;
   m_saveY = m_state.panelY;
   m_nextAt = GetTickCount() + RD_CTL_UI_SAVE_MS + 400;
  }

void CUiSelfTest::StepSavedFiles()
  {
   m_ctl.Refresh();   // the debounced ui.ini save happens in the refresh
   long login = CAccountSpec::Login();
   CKeyValueFile ui;
   CKeyValueFile acct;
   bool uiOk = ui.Load(m_store.UiPath()) && ui.GetInt("panel_x", -1) == m_saveX && ui.GetInt("panel_y", -1) == m_saveY &&
               ui.GetBool("hidden", false);
   bool acctOk = acct.Load(m_store.AccountPath(login)) && MathAbs(acct.GetDouble("risk_pct", 0.0) - 0.75) < 1e-9;
   Check(uiOk && acctOk && !m_state.uiDirty, "T-21 saved", m_store.UiPath() + " (x " + IntegerToString(m_saveX) + ", y " +
         IntegerToString(m_saveY) + ", hidden) " + RdBoolText(uiOk) + "; " + m_store.AccountPath(login) + " (risk 0.75) " +
         RdBoolText(acctOk));
   CKeyValueFile e;
   e.SetString("login", IntegerToString(login));
   e.SetDouble("risk_pct", 0.75, 2);
   e.SetInt("panel_x", m_saveX);
   e.SetInt("panel_y", m_saveY);
   e.SetBool("hidden", true);
   e.Save(ExpectPath(), "state the next self-test run must find after the terminal restart (T-21)");
   Line("INFO T-21: the next self-test run on this terminal checks that this state comes back after the restart");
  }

//+------------------------------------------------------------------+
//| ADR-021 chart look: the owner's MT4 chart had "Chart on          |
//| foreground" (candles over the panel) and the One-Click Trading   |
//| panel (covering the panel's top) switched on. Both on, panel at  |
//| its home position; the check follows after one housekeeping.     |
//+------------------------------------------------------------------+
void CUiSelfTest::StepChartLookOn()
  {
   ApplyLook(m_cfg.scale, m_cfg.autoFitPanel, m_cfg.fontPreset, m_cfg.panelColumns);
   m_panel.SetWanted(m_homeX, m_homeY);
   m_state.panelX = m_homeX;
   m_state.panelY = m_homeY;
   ChartSetInteger(0, CHART_FOREGROUND, true);
   ChartSetInteger(0, CHART_SHOW_ONE_CLICK, true);
   Line("chart look setup: Chart on foreground on, One-Click Trading on, panel wanted at " + IntegerToString(m_homeX) +
        ", " + IntegerToString(m_homeY));
   m_nextAt = GetTickCount() + RD_CTL_HOUSEKEEP_MS + 400;
  }

void CUiSelfTest::StepChartLookCheck()
  {
   m_ctl.Refresh();   // housekeeping: CheckChartLook
   bool foreground = ChartGetInteger(0, CHART_FOREGROUND) != 0;
   Check(!foreground, "chart on foreground", "switched off again by RiskDesk: " + RdBoolText(!foreground));
   int rw = m_layout.TerminalPx(RD_LY_ONECLICK_W);
   int rh = m_layout.TerminalPx(RD_LY_ONECLICK_H);
   int x = m_panel.ShownX();
   int y = m_panel.ShownY();
   Check(x >= rw || y >= rh, "one-click at home", "panel shown at " + IntegerToString(x) + ", " + IntegerToString(y) +
         " (wanted " + IntegerToString(m_homeX) + ", " + IntegerToString(m_homeY) + "), One-Click area " +
         IntegerToString(rw) + " x " + IntegerToString(rh) + " px");
   CheckInView("one-click in view");
   Line("geometry for the window capture: background at chart x " + IntegerToString(Prop("RD_P_BG", OBJPROP_XDISTANCE)) +
        ", y " + IntegerToString(Prop("RD_P_BG", OBJPROP_YDISTANCE)) + ", " + IntegerToString(Prop("RD_P_BG", OBJPROP_XSIZE)) +
        " x " + IntegerToString(Prop("RD_P_BG", OBJPROP_YSIZE)) + " px");
   Shot("one_click_home");
   RequestWindowCapture("one_click_home");
  }

//+------------------------------------------------------------------+
//| The runner captures the terminal window (PrintWindow) while the  |
//| request file exists; this step waits for it, at most 15 s.       |
//+------------------------------------------------------------------+
void CUiSelfTest::RequestWindowCapture(const string name)
  {
   // the capture shows the terminal's front chart: make it this one (other charts may be open)
   ChartSetInteger(0, CHART_BRING_TO_TOP, true);
   ChartRedraw(0);
   int h = FileOpen(CapturePath(), FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return;
   FileWriteString(h, name);
   FileClose(h);
   m_waits = 0;
  }

bool CUiSelfTest::WindowCaptured()
  {
   if(!FileIsExist(CapturePath()))
     {
      Line("window capture taken by the runner");
      return true;
     }
   if(++m_waits < 38)   // 38 x 400 ms
      return false;
   FileDelete(CapturePath());
   Line("INFO window capture: no runner answered in 15 s (run-uitest.ps1 takes it)");
   return true;
  }

void CUiSelfTest::StepChartLookCorner()
  {
   int rw = m_layout.TerminalPx(RD_LY_ONECLICK_W);
   int rh = m_layout.TerminalPx(RD_LY_ONECLICK_H);
   Drag(-5000, -5000);
   int x = m_panel.ShownX();
   int y = m_panel.ShownY();
   Check(x >= rw || y >= rh, "one-click top-left", "dragged into the corner: shown at " + IntegerToString(x) + ", " +
         IntegerToString(y));
   Shot("one_click_corner");
   ChartSetInteger(0, CHART_SHOW_ONE_CLICK, false);
   m_panel.SetWanted(m_homeX, m_homeY);
   m_state.panelX = m_homeX;
   m_state.panelY = m_homeY;
   m_ctl.CheckChartLook();
   m_ctl.Refresh();
  }

#endif // RD_APP_UISELFTESTSTEPS_MQH
