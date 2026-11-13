//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestExtras.mqh                              |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : the extras suite (P7, 08 section 3i):                  |
//|           - T-33 candle time (F-21): RD_CT against a countdown   |
//|             computed here from the bar's open and the server     |
//|             clock (text, mm:ss / hh:mm:ss / Nd hh:mm:ss form,    |
//|             gold / red at InpCandleTimeWarnPct, place, look),    |
//|             running between ticks, switched off and on, right of |
//|             the candle with chart shift and left of it without   |
//|             (D39), on the runner's timeframe, M1, H4 and W1      |
//|           - T-34 screenshot names (F-19): the camera button and  |
//|             a Buy (REAL test position on a DEMO account only,    |
//|             rule R13, magic 772288, closed again)                |
//|           - T-33 closed-trade objects (F-20): MetaTrader's       |
//|             "#ticket ..." arrows and lines of a closed trade of  |
//|             the chart symbol are removed with CTO_REMOVE and     |
//|             kept with CTO_KEEP; user drawings and objects whose  |
//|             ticket is no closed trade stay (AC3); MT5 "Show      |
//|             trade history" off and given back                    |
//|           - T-31 cent display (F-24) forced with CENT_ON: the SL |
//|             label shows the cent unit and the major unit, the    |
//|             lots do not change                                   |
//|           - F-32 daily log files older than InpLogKeepDays are   |
//|             deleted, other files are not                         |
//|           The timeframe steps run before TradeStart: a timeframe |
//|           change runs OnInit, which reloads the inputs.          |
//|           Part of CUiSelfTest; included by App/UiSelfTest.mqh.   |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTEXTRAS_MQH
#define RD_APP_UISELFTESTEXTRAS_MQH

#include "..\Domain\TimeMath.mqh"
#include "..\Services\CandleTime.mqh"
#include "..\Services\ChartHousekeeping.mqh"

void CUiSelfTest::StepExtras(const uint now)
  {
   long left = 0;
   switch(m_step)
     {
      case 0:
        {
         SQuote q;
         if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
            return;   // wait for a first quote, at most 15 s
         ExStart();
         break;
        }
      case 1:
         ExCandle("T-33 candle time " + RdTimeframeText((ENUM_TIMEFRAMES)_Period), m_exLeft);
         m_exAt = GetTickCount();
         m_exTick = TimeCurrent();
         Shot("candle_" + RdTimeframeText((ENUM_TIMEFRAMES)_Period));
         m_nextAt = now + 2500;
         break;
      case 2:
         ExBetweenTicks();
         break;
      case 3:
         ExCandleToggle();
         break;
      case 4:
         ExShift(true);    // chart shift on; checked in the next step
         break;
      case 5:
         ExShiftCheck(true);
         ExShift(false);
         break;
      case 6:
         ExShiftCheck(false);
         ChartSetInteger(0, CHART_SHIFT, m_exShiftWas);
         ChartNavigate(0, CHART_END, 0);
         break;
      case 7:
         if(!ExTf(PERIOD_M1))
            return;
         ExCandle("T-33 candle time M1", left);
         Shot("candle_M1");
         break;
      case 8:
         if(!ExTf(PERIOD_H4))
            return;
         ExCandle("T-33 candle time H4", left);
         Shot("candle_H4");
         break;
      case 9:
         if(!ExTf(PERIOD_W1))
            return;
         ExCandle("T-33 candle time W1", left);
         ExChartShot("W1");   // the camera on a W1 chart (MT4 froze on a screenshot of a short W1 history, ADR-027)
         Shot("candle_W1");
         break;
      case 10:
         if(!ExTf(m_exPeriod))
            return;
         Check(_Period == m_exPeriod, "T-33 timeframe back", EnumToString((ENUM_TIMEFRAMES)_Period));
         break;
      case 11:
         TradeStart();   // R13, test magic, Risk %; no timeframe change after this
         break;
      case 12:
         ExCameraShot();
         break;
      case 13:
         ExBuyShot();
         break;
      case 14:
         ExClosedObjects();
         break;
      case 15:
         ExCent();
         break;
      case 16:
         ExLogs();
         break;
      default:
         ExEnd();
         Finish();
         return;
     }
   m_step++;
  }

//+------------------------------------------------------------------+
void CUiSelfTest::ExStart()
  {
   Line("RiskDesk " + RD_VERSION + " extras self-test, " + RD_PLATFORM + " build " + IntegerToString(RdTerminalBuild()) +
        ", account " + IntegerToString(CAccountSpec::Login()) + " " + AccountInfoString(ACCOUNT_SERVER) + " " +
        AccountInfoString(ACCOUNT_CURRENCY) + " (" + RdAccountTradeModeText(AccountInfoInteger(ACCOUNT_TRADE_MODE)) + "), chart " +
        _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) + "; inputs: Candle Time " + RdBoolText(m_cfg.showCandleTime) +
        " (red in the last " + IntegerToString(m_cfg.candleTimeWarnPct) + " %), Closed Trade History Objects " +
        (m_cfg.closedTradeObjects == CTO_REMOVE ? "Remove" : "Keep") + ", log files kept " + IntegerToString(m_cfg.logKeepDays) +
        " days");
   m_exPeriod = (ENUM_TIMEFRAMES)_Period;
   m_exWant = m_exPeriod;
   m_exShiftWas = ChartGetInteger(0, CHART_SHIFT) != 0;
   m_exTicket = 0;
   m_waits = 0;
   SResult sr;
   CSymbolSpec::Read(_Symbol, m_ts, sr);
   if(m_state.hidden)
      ClickObject("RD_P_HIDE");   // the panel shown in the screenshots
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| False while the chart is not on 'tf' (or has no bar yet), at     |
//| most 25 steps; the change runs OnInit (the EA's objects stay).   |
//+------------------------------------------------------------------+
bool CUiSelfTest::ExTf(const ENUM_TIMEFRAMES tf)
  {
   if(_Period != tf)
     {
      if(m_exWant != tf)
        {
         m_exWant = tf;
         m_waits = 0;
         ChartSetSymbolPeriod(0, _Symbol, tf);
         return false;
        }
      if(m_waits++ < 25)
         return false;
      Check(false, "T-33 timeframe " + RdTimeframeText(tf), "the chart stayed on " + EnumToString((ENUM_TIMEFRAMES)_Period));
      return true;
     }
   if(iTime(_Symbol, PERIOD_CURRENT, 0) <= 0 && m_waits++ < 25)
      return false;
   m_waits = 0;
   return true;
  }

//+------------------------------------------------------------------+
//| "<-- mm:ss" -> form 0, "<-- hh:mm:ss" -> 1, "<-- Nd hh:mm:ss" -> |
//| 2, also with the arrow after the time ("mm:ss -->", D39);        |
//| returns the seconds, -1 when the text is none of them.           |
//+------------------------------------------------------------------+
long CUiSelfTest::ExParseCountdown(const string text, int &form)
  {
   form = -1;
   int len = StringLen(text);
   string rest;
   if(StringFind(text, "<-- ") == 0)
      rest = StringSubstr(text, 4);
   else
      if(len > 4 && StringSubstr(text, len - 4) == " -->")
         rest = StringSubstr(text, 0, len - 4);
      else
         return -1;
   long days = 0;
   int d = StringFind(rest, "d ");
   if(d > 0)
     {
      days = StringToInteger(StringSubstr(rest, 0, d));
      rest = StringSubstr(rest, d + 2);
     }
   string parts[];
   int n = StringSplit(rest, ':', parts);
   if(n < 2 || n > 3)
      return -1;
   for(int i = 0; i < n; i++)
      if(StringLen(parts[i]) != 2 || StringToInteger(parts[i]) < 0 || StringToInteger(parts[i]) > 59)
         return -1;
   if(d > 0 && n != 3)
      return -1;
   form = (d > 0) ? 2 : (n == 3 ? 1 : 0);
   long h = (n == 3) ? StringToInteger(parts[0]) : 0;
   long m = StringToInteger(parts[n - 2]);
   long s = StringToInteger(parts[n - 1]);
   return days * RD_DAY_SEC + h * 3600 + m * 60 + s;
  }

//+------------------------------------------------------------------+
//| T-33 / F-21: RD_CT against the countdown computed here: bar 0's  |
//| open + the period (MN1: + 1 month) - the server clock, the form  |
//| for that many seconds, the colour (either one within 2 s of the  |
//| red threshold), one bar right of bar 0 at the Bid, the look.     |
//+------------------------------------------------------------------+
bool CUiSelfTest::ExCandle(const string id, long &left)
  {
   left = -1;
   m_ctl.Refresh();
   string name = CCandleTime::ObjectName();
   if(!m_cfg.showCandleTime)
     {
      Check(ObjectFind(0, name) < 0, id, "Candle Time is off in the inputs: RD_CT " +
            (ObjectFind(0, name) < 0 ? "not drawn" : "DRAWN"));
      return false;
     }
   if(ObjectFind(0, name) < 0)
     {
      Check(false, id, "RD_CT is not on the chart");
      return false;
     }
   CCandleTime *ct = m_ctl.Candle();
   string text = ObjectGetString(0, name, OBJPROP_TEXT);
   int form = -1;
   long shown = ExParseCountdown(text, form);
   datetime now = ct.ServerNow();
   datetime open = iTime(_Symbol, PERIOD_CURRENT, 0);
   int period = PeriodSeconds(PERIOD_CURRENT);
   bool monthly = (_Period == PERIOD_MN1);
   datetime close = monthly ? RdAddMonths(open, 1) : (datetime)((long)open + period);
   long length = (long)close - (long)open;
   bool known = false;
   bool inSession = CMarket::InSession(_Symbol, now, known) && known;
   bool ranOut = (now >= close);
   string expectText;
   bool timeOk;
   if(!ranOut)
     {
      long expect = (long)close - (long)now;
      timeOk = shown >= 0 && MathAbs(shown - expect) <= 2;
      expectText = IntegerToString(expect) + " s";
     }
   else
      if(inSession)
        {
         timeOk = shown > 0 && shown <= period;   // the candle running by the clock, no tick yet
         expectText = "1.." + IntegerToString(period) + " s (no tick in the new candle yet)";
        }
      else
        {
         timeOk = (shown == 0);
         expectText = "0 (market closed)";
        }
   int wantForm = (shown >= RD_DAY_SEC) ? 2 : (shown >= 3600 ? 1 : 0);
   int pct = m_cfg.candleTimeWarnPct;
   double redFrom = pct * (double)length / 100.0;
   bool red = (shown == 0) || (pct > 0 && shown <= redFrom);
   bool edge = pct > 0 && MathAbs(shown - redFrom) <= 2.0;
   color col = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
   bool colOk = edge ? (col == m_cfg.colorCandleTimeWarn || col == m_cfg.colorCandleTime) :
                (col == (red ? m_cfg.colorCandleTimeWarn : m_cfg.colorCandleTime));
   //--- in pixels from bar 0 at the Bid: right of the candle "<-- ..." (05 section 6), or left of it
   //--- "... -->" without room (D39); within 40 px of the candle, at the Bid's height (the Bid may move)
   SQuote q;
   CMarket::Quote(_Symbol, q);
   int x0 = 0;
   int y0 = 0;
   ChartTimePriceToXY(0, 0, open, q.bid, x0, y0);
   int ox = (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
   int oy = (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE);
   long anchor = ObjectGetInteger(0, name, OBJPROP_ANCHOR);
   bool rightOf = (anchor == ANCHOR_LEFT);
   bool placeOk = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_LABEL &&
                  (rightOf ? (ox > x0 && ox - x0 <= 40 && StringFind(text, "<-- ") == 0) :
                   (anchor == ANCHOR_RIGHT && ox < x0 && x0 - ox <= 40 && StringFind(text, " -->") > 0));
   bool posOk = placeOk && MathAbs(oy - y0) <= 6 && ObjectGetInteger(0, name, OBJPROP_TIMEFRAMES) != RD_OBJ_NO_PERIODS;
   m_exRightOf = rightOf;
   bool lookOk = ObjectGetInteger(0, name, OBJPROP_HIDDEN) != 0 && ObjectGetInteger(0, name, OBJPROP_SELECTABLE) == 0 &&
                 ObjectGetInteger(0, name, OBJPROP_FONTSIZE) == m_cfg.candleTimeFontSize;
   Check(timeOk && form == wantForm && colOk && posOk && lookOk, id,
         "'" + text + "' = " + IntegerToString(shown) + " s, expected " + expectText + "; candle " +
         TimeToString(open, TIME_DATE | TIME_MINUTES) + " -> " + TimeToString(close, TIME_DATE | TIME_MINUTES) +
         ", server clock " + TimeToString(now, TIME_DATE | TIME_SECONDS) + " (last tick " +
         TimeToString(TimeCurrent(), TIME_SECONDS) + "); form " + IntegerToString(form) + " (want " + IntegerToString(wantForm) +
         "); " + (col == m_cfg.colorCandleTimeWarn ? "red" : (col == m_cfg.colorCandleTime ? "gold" : "OTHER COLOUR")) +
         " (red from " + RdNum(redFrom, 0) + " s" + (edge ? ", at the edge" : "") + "); " +
         (rightOf ? "right of the candle" : "left of the candle (no room right of it)") + " at x " + IntegerToString(ox) +
         ", y " + IntegerToString(oy) + " (bar 0 at the Bid: x " + IntegerToString(x0) + ", y " + IntegerToString(y0) + ")" +
         (posOk ? "" : " WRONG PLACE") + (lookOk ? "" : "; look WRONG (hidden, selectable, size)"));
   left = shown;
   return timeOk;
  }

//+------------------------------------------------------------------+
//| F-21 AC1: updated every second from the server clock, also       |
//| between ticks: the countdown went down by the time that passed.  |
//+------------------------------------------------------------------+
void CUiSelfTest::ExBetweenTicks()
  {
   long left = 0;
   bool ok = ExCandle("T-33 candle time again", left);
   double elapsed = (GetTickCount() - m_exAt) / 1000.0;
   if(!ok || m_exLeft < 0 || left < 0)
     {
      Check(false, "T-33 between ticks", "no countdown to compare");
      return;
     }
   if(m_exLeft == 0 && left == 0)
     {
      Line("INFO T-33 between ticks: the market is closed (00:00 both times), nothing runs");
      return;
     }
   if(left > m_exLeft)
     {
      Line("INFO T-33 between ticks: a new candle started meanwhile (" + IntegerToString(m_exLeft) + " -> " +
           IntegerToString(left) + " s) - not compared");
      return;
     }
   // whole seconds on both readings: up to 1 s of rounding each way, plus the clock's own second
   double went = (double)(m_exLeft - left);
   Check(MathAbs(went - elapsed) <= 2.0, "T-33 between ticks", "countdown " + IntegerToString(m_exLeft) + " -> " +
         IntegerToString(left) + " s in " + DoubleToString(elapsed, 1) + " s" +
         (TimeCurrent() == m_exTick ? " (no tick meanwhile)" : " (ticks meanwhile)"));
  }

//+------------------------------------------------------------------+
//| T-33 toggle Candle Time: off removes RD_CT, on draws it again.   |
//+------------------------------------------------------------------+
void CUiSelfTest::ExCandleToggle()
  {
   string name = CCandleTime::ObjectName();
   SCandleStyle cs;
   m_cfg.CandleStyle(cs, m_theme.fontBody);
   cs.on = false;
   m_ctl.Candle().Configure(cs);
   m_ctl.Refresh();
   bool gone = ObjectFind(0, name) < 0;
   uint t0 = GetTickCount();
   for(int i = 0; i < 20; i++)
      m_ctl.Refresh();
   int ms = (int)(GetTickCount() - t0);
   cs.on = m_cfg.showCandleTime;
   m_ctl.Candle().Configure(cs);
   m_ctl.Refresh();
   bool back = (ObjectFind(0, name) >= 0) == m_cfg.showCandleTime;
   Check(gone && back, "T-33 candle time off / on", "off: RD_CT " + (gone ? "removed" : "STILL DRAWN") + " (20 refreshes " +
         IntegerToString(ms) + " ms); back to the input (" + RdBoolText(m_cfg.showCandleTime) + "): RD_CT " +
         (ObjectFind(0, name) >= 0 ? "drawn" : "not drawn"));
  }

//+------------------------------------------------------------------+
//| D39: with chart shift the countdown stands right of the current  |
//| candle; without it (bar 0 at the right edge) left of it. The     |
//| change is drawn by the terminal before the next step checks it.  |
//+------------------------------------------------------------------+
void CUiSelfTest::ExShift(const bool on)
  {
   ChartSetInteger(0, CHART_AUTOSCROLL, true);
   ChartSetInteger(0, CHART_SHIFT, on);
   ChartNavigate(0, CHART_END, 0);
   ChartRedraw(0);
  }

void CUiSelfTest::ExShiftCheck(const bool on)
  {
   long left = 0;
   string id = on ? "T-33 candle time with chart shift" : "T-33 candle time without chart shift";
   bool ok = ExCandle(id + " (countdown)", left);
   Check(ok && m_exRightOf == on, id, (m_exRightOf ? "right of the current candle" : "left of the current candle") +
         ", expected " + (on ? "right of it" : "left of it") + " ('" + ObjectGetString(0, CCandleTime::ObjectName(), OBJPROP_TEXT) +
         "')");
   Shot(on ? "candle_shift_on" : "candle_shift_off");
  }

//+------------------------------------------------------------------+
//| RiskDesk's own screenshot (CScreenshot: the chart's size) on the |
//| current timeframe, with the bars the chart has and fits: MT4     |
//| froze when the self-test asked for a picture wider than a W1     |
//| chart with fewer bars than its width; the product must not.      |
//+------------------------------------------------------------------+
void CUiSelfTest::ExChartShot(const string tf)
  {
   int bars = iBars(_Symbol, PERIOD_CURRENT);
   int width = (int)ChartGetInteger(0, CHART_WIDTH_IN_BARS);
   string path = "";
   SResult sr;
   bool ok = CScreenshot::Take("uitest", 0, 0, 0, path, sr);
   bool exists = ok && FileIsExist(path);
   Check(exists, "T-34 screenshot on " + tf, IntegerToString(bars) + " bars in a chart " + IntegerToString(width) +
         " bars wide: '" + sr.message + "'" + (exists ? "" : " (NO FILE)"));
   if(exists)
      FileDelete(path);
  }

//+------------------------------------------------------------------+
//| F-19 AC1 name for 'action' / 'ticket' taken between t0 and t1    |
//| (local time), "_2" ... allowed for a second shot in that second. |
//+------------------------------------------------------------------+
bool CUiSelfTest::ExShotNamed(const string path, const string action, const ulong ticket, const datetime t0,
                              const datetime t1, string &want)
  {
   want = "";
   for(datetime t = t0; t <= t1 + 1; t++)
     {
      string name = RD_SHOT_DIR + "\\" + RdShotFileName(CAccountSpec::Login(), _Symbol, (ENUM_TIMEFRAMES)_Period, t, action, ticket);
      if(want == "")
         want = name;
      if(path == name)
         return true;
      string stem = StringSubstr(name, 0, StringLen(name) - 4) + "_";
      if(StringFind(path, stem) == 0 && StringSubstr(path, StringLen(path) - 4) == ".png")
         return true;
     }
   return false;
  }

// T-34: the camera button's file.
void CUiSelfTest::ExCameraShot()
  {
   m_state.lastShot = "";
   datetime t0 = TimeLocal();
   ClickButton(PB_SHOT);
   datetime t1 = TimeLocal();
   string path = m_state.lastShot;
   string want = "";
   bool named = ExShotNamed(path, "manual", 0, t0, t1, want);
   bool saved = path != "" && FileIsExist(path);
   string st = m_status.Text();
   Check(named && saved && m_status.Severity() == SEV_OK && StringFind(st, "Screenshot saved") >= 0, "T-34 camera",
         "file '" + path + "' (" + (saved ? "exists" : "MISSING") + "), expected like '" + want + "'; status '" + st + "'");
  }

//+------------------------------------------------------------------+
//| T-34: the screenshot after a Buy names the action and the ticket.|
//| The test position is closed again, and its ticket is the closed  |
//| trade the F-20 step works with. Netting: only when the symbol    |
//| has no position (a Buy would merge into it).                     |
//+------------------------------------------------------------------+
void CUiSelfTest::ExBuyShot()
  {
   if(!m_tradeOk || m_marketClosed)
     {
      Line("INFO T-34 Buy screenshot skipped: no test trade possible here (see the setup lines)");
      return;
     }
   if(!m_gw.IsHedging())
     {
      STradeFilter f;
      f.Reset();
      f.symbol = _Symbol;
      SPosition arr[];
      SResult r;
      if(!m_gw.ListPositions(f, arr, r) || ArraySize(arr) > 0)
        {
         Line("INFO T-34 Buy screenshot skipped: netting account with a position on " + _Symbol);
         return;
        }
     }
   bool autoWas = m_cfg.autoScreenshot;
   m_cfg.autoScreenshot = true;
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   m_state.lastShot = "";
   datetime t0 = TimeLocal();
   ClickButton(PB_BUY);
   datetime t1 = TimeLocal();
   ulong ticket = StatusTicket();
   string st = m_status.Text();
   string path = m_state.lastShot;
   string want = "";
   bool opened = (m_status.Severity() == SEV_OK && ticket > 0);
   bool named = opened && ExShotNamed(path, "buy", ticket, t0, t1, want);
   Check(opened && named && FileIsExist(path), "T-34 Buy screenshot", "status '" + st + "'; file '" + path +
         "', expected like '" + want + "'");
   m_cfg.autoScreenshot = autoWas;
   CloseTestTrades("after the T-34 Buy");
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   m_ctl.Refresh();
   if(opened)
      m_exTicket = ticket;
  }

bool CUiSelfTest::ExMakeObject(const string name, const ENUM_OBJECT type, const double p1, const double p2)
  {
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 8);
   datetime t2 = iTime(_Symbol, PERIOD_CURRENT, 2);
   ObjectDelete(0, name);
   bool ok = (type == OBJ_TREND) ? ObjectCreate(0, name, type, 0, t1, p1, t2, p2) : ObjectCreate(0, name, type, 0, t2, p2);
   if(!ok)
      return false;
   if(type == OBJ_TEXT)
      ObjectSetString(0, name, OBJPROP_TEXT, "user note");
   if(type == OBJ_ARROW)
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 1);
   if(type == OBJ_TREND)
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
   return true;
  }

//+------------------------------------------------------------------+
//| T-33 / F-20 with the test trade closed above (or the newest      |
//| closed trade of the chart symbol in the last 90 days): objects   |
//| named as MetaTrader names a closed trade's arrows and line (Q24: |
//| the owner's MT4 object list), and                                |
//| objects that must stay (AC3): a text with the same "#ticket "    |
//| (not an arrow or line), an arrow of a ticket that is no trade,   |
//| a user trend line, an arrow named "#<ticket>x".                  |
//+------------------------------------------------------------------+
void CUiSelfTest::ExClosedObjects()
  {
   ulong t = m_exTicket;
   if(t == 0)
     {
      SClosedTrade ct[];
      SResult r;
      if(CHistory::ClosedTrades(_Symbol, TimeCurrent() - 90 * RD_DAY_SEC, ct, r) && ArraySize(ct) > 0)
         t = ct[ArraySize(ct) - 1].ticket;
     }
   SQuote q;
   CMarket::Quote(_Symbol, q);
   double p1 = q.bid;
   double p2 = q.bid + 10.0 * RdTick(m_ts);
   string tk = IntegerToString((long)t);
   string a = DoubleToString(p1, _Digits);
   string b = DoubleToString(p2, _Digits);
   string trade[3];
   trade[0] = "#" + tk + " buy 0.01 " + _Symbol + " at " + a;
   trade[1] = "#" + tk + " " + a + " -> " + b;
   trade[2] = "#" + tk + " buy 0.01 " + _Symbol + " at " + a + " close at " + b;
   ENUM_OBJECT tradeType[3] = {OBJ_ARROW, OBJ_TREND, OBJ_ARROW_SELL};
   string keep[4];
   keep[0] = "#" + tk + " user note";
   keep[1] = "#1 buy 0.01 " + _Symbol + " at " + a;
   keep[2] = "Trendline 12345";
   keep[3] = "#" + tk + "x note";
   ENUM_OBJECT keepType[4] = {OBJ_TEXT, OBJ_ARROW, OBJ_TREND, OBJ_ARROW};
   bool haveTrade = (t > 0);
   if(!haveTrade)
      Line("INFO F-20: no closed trade of " + _Symbol + " in the last 90 days - only the objects that must stay are checked");
   CChartHousekeeping *hk = m_ctl.House();
   bool histWas = false;
   bool histKnown = RdChartTradeHistory(histWas);
   //--- Remove
   hk.Configure(CTO_REMOVE);
   for(int i = 0; i < 4; i++)
      ExMakeObject(keep[i], keepType[i], p1, p2);
   if(haveTrade)
      for(int i = 0; i < 3; i++)
         ExMakeObject(trade[i], tradeType[i], p1, p2);
   m_ctl.Refresh();   // the object count changed: scanned now
   int tradeLeft = 0;
   int keepLeft = 0;
   for(int i = 0; i < 3 && haveTrade; i++)
      if(ObjectFind(0, trade[i]) >= 0)
         tradeLeft++;
   for(int i = 0; i < 4; i++)
      if(ObjectFind(0, keep[i]) >= 0)
         keepLeft++;
   bool hist = false;
   bool histOk = !histKnown || (RdChartTradeHistory(hist) && !hist && ObjectFind(0, RD_CTO_MEMO) >= 0);
   string memo = ObjectGetString(0, RD_CTO_MEMO, OBJPROP_TEXT);
   Check(tradeLeft == 0 && keepLeft == 4 && histOk, "T-33 closed-trade objects removed",
         (haveTrade ? "closed trade " + RdTicketText(t) + ": " + IntegerToString(3 - tradeLeft) + " of 3 objects removed" :
          "no closed trade") + ", " + IntegerToString(keepLeft) + " of 4 other objects kept" +
         (histKnown ? "; Show trade history " + (hist ? "ON" : "off") + ", memo '" + memo + "'" : " (MT4: no Show trade history property)"));
   Shot("cto_remove");
   //--- Keep: the saved "Show trade history" back, new objects stay
   bool wasOn = (memo == "history=1");
   hk.Configure(CTO_KEEP);
   if(haveTrade)
      for(int i = 0; i < 3; i++)
         ExMakeObject(trade[i], tradeType[i], p1, p2);
   m_ctl.Refresh();
   tradeLeft = 0;
   for(int i = 0; i < 3 && haveTrade; i++)
      if(ObjectFind(0, trade[i]) >= 0)
         tradeLeft++;
   bool histBack = !histKnown || (RdChartTradeHistory(hist) && hist == wasOn && ObjectFind(0, RD_CTO_MEMO) < 0);
   Check((!haveTrade || tradeLeft == 3) && histBack, "T-33 closed-trade objects kept",
         (haveTrade ? IntegerToString(tradeLeft) + " of 3 objects kept" : "no closed trade") +
         (histKnown ? "; Show trade history " + (hist ? "on" : "off") + " (the user's value: " + (wasOn ? "on" : "off") + ")" : ""));
   //--- clean up, back to the input
   for(int i = 0; i < 3; i++)
      ObjectDelete(0, trade[i]);
   for(int i = 0; i < 4; i++)
      ObjectDelete(0, keep[i]);
   hk.Configure(m_cfg.closedTradeObjects);
   m_ctl.Refresh();
   if(histKnown)
      Line("INFO F-20: Show trade history was " + (histWas ? "on" : "off") + " at the start of this step, with RiskDesk running");
  }

//+------------------------------------------------------------------+
//| T-31 / F-24 forced with CENT_ON: the SL label shows the cent     |
//| unit and the major unit; Lots stays the same (AC1).              |
//+------------------------------------------------------------------+
void CUiSelfTest::ExCent()
  {
   ECentMode was = m_cfg.centMode;
   m_cfg.centMode = CENT_OFF;
   ClickButton(PB_ADDLINE);
   m_ctl.Refresh();
   string label = CLines::LabelName(LINEROLE_SL);
   string lots0 = Text("RD_E_LOTS");
   string text0 = Text(label);
   m_cfg.centMode = CENT_ON;
   m_ctl.Refresh();
   string lots1 = Text("RD_E_LOTS");
   string text1 = Text(label);
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar, CENT_ON, m_cfg.centDivisor);
   // the risk on the SL label is positive: "SL  -1,000.00 USC ($10.00) (1.00 %)"
   string sign = RdCurrencySymbol(acc.centMajor);
   string marker = " " + acc.centUnit + " (" + sign;
   bool shown = StringFind(text1, marker) > 0 && (sign != "" || StringFind(text1, " " + acc.centMajor + ")") > 0);
   bool notBefore = (sign == "") || StringFind(text0, marker) < 0;
   bool ok = shown && notBefore && lots1 == lots0 && lots1 != "";
   Check(ok, "T-31 cent display (forced)", "SL label '" + text0 + "' -> '" + text1 + "' (unit " + acc.centUnit + ", major " +
         acc.centMajor + ", 1:" + RdNum(acc.centDivisor, 0) + "); Lots '" + lots0 + "' -> '" + lots1 + "'");
   Shot("cent_on");
   m_cfg.centMode = was;
   ClickButton(PB_DELLINE);
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| F-32: a daily file older than InpLogKeepDays goes; a file of     |
//| another name and today's file stay. Only files this step made    |
//| are written (dates that cannot exist on the owner's terminal).   |
//+------------------------------------------------------------------+
void CUiSelfTest::ExLogs()
  {
   string dir = RD_LOG_DIR + "\\";
   string old = RD_PRODUCT + "_20010102.log";
   string other = RD_PRODUCT + "_notes_uitest.log";
   FolderCreate(RD_LOG_DIR);
   string made[2];
   made[0] = old;
   made[1] = other;
   for(int i = 0; i < 2; i++)
     {
      int h = FileOpen(dir + made[i], FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h != INVALID_HANDLE)
        {
         FileWriteString(h, "RiskDesk self-test file\r\n");
         FileClose(h);
        }
     }
   RD_LOG_INFO("TEST F-32 log pruning");   // today's file exists (when the log mirrors to a file)
   string today = CLogger::TodayFile();
   int keep = (m_cfg.logKeepDays > 0) ? m_cfg.logKeepDays : 30;
   int n = CLogger::PruneOld(keep);
   bool oldGone = !FileIsExist(dir + old);
   bool otherKept = FileIsExist(dir + other);
   bool todayKept = !m_cfg.logToFile || FileIsExist(today);
   Check(oldGone && otherKept && todayKept && n >= 1, "F-32 log retention",
         IntegerToString(n) + " file(s) older than " + IntegerToString(keep) + " days deleted; " + old + " " +
         (oldGone ? "deleted" : "STILL THERE") + ", " + other + " " + (otherKept ? "kept" : "DELETED") + ", today's " + today +
         " " + (m_cfg.logToFile ? (todayKept ? "kept" : "DELETED") : "(log file off)"));
   FileDelete(dir + other);
   FileDelete(dir + old);
  }

void CUiSelfTest::ExEnd()
  {
   TradeEnd();   // test trades closed, inputs reloaded
   SCandleStyle cs;
   m_cfg.CandleStyle(cs, m_theme.fontBody);
   m_ctl.Candle().Configure(cs);
   m_ctl.House().Configure(m_cfg.closedTradeObjects);
   m_ctl.Refresh();
  }

#endif // RD_APP_UISELFTESTEXTRAS_MQH
