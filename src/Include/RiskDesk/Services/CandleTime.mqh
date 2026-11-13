// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Services/CandleTime.mqh                               |
//| Layer   : Services                                               |
//| Purpose : countdown to the close of the current candle (F-21,    |
//|           05 section 6, Q4, Q20): OBJ_LABEL RD_CT at the Bid     |
//|           price, a few pixels right of the current candle,       |
//|           "<-- mm:ss" / "<-- hh:mm:ss" / "<-- Nd hh:mm:ss"; when |
//|           the chart has no room there (no chart shift, D39),     |
//|           left of the candle, "mm:ss -->"; hidden while the      |
//|           current candle or the Bid is out of view. Gold         |
//|           (InpColorCandleTime), red (InpColorCandleTimeWarn) in  |
//|           the last InpCandleTimeWarnPct % of the candle and at   |
//|           00:00 (market closed). Driven by CServerClock, so it   |
//|           keeps running between ticks; the math is               |
//|           Domain/TimeMath.mqh (RdCandleClock, unit-tested).      |
//|           Placed in pixels from bar 0's own coordinates and      |
//|           moved every refresh: MT4 froze drawing a time/price    |
//|           text at a future time on a W1 chart (ADR-027), so no   |
//|           object is ever placed at a time without a bar.         |
//|           Off (InpShowCandleTime=false): the object is removed   |
//|           and Update() costs one bool test.                      |
//|           Never touches anything but RD_CT; the caller redraws.  |
//+------------------------------------------------------------------+
#ifndef RD_SERVICES_CANDLETIME_MQH
#define RD_SERVICES_CANDLETIME_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\TimeMath.mqh"
#include "..\Platform\Compat.mqh"
#include "..\Platform\Market.mqh"

#define RD_CANDLE_OBJ   "RD_CT"
#define RD_CANDLE_GAP   4        // pixels between the candle's half width and the text

struct SCandleStyle
  {
   bool              on;
   int               fontSize;
   string            font;
   color             normal;
   color             warn;
   int               warnPct;

   void              Defaults()
     {
      on = true;
      fontSize = 10;
      font = "Segoe UI";
      normal = clrGold;
      warn = clrRed;
      warnPct = 10;
     }
  };

class CCandleTime
  {
private:
   SCandleStyle      m_style;
   CServerClock      m_clock;
   SCandleClock      m_last;          // the last countdown drawn
   bool              m_styled;        // font / size / corner written to the object
   bool              m_offDone;       // switched off and RD_CT removed: nothing more to do
   string            m_text;
   color             m_color;
   int               m_x;
   int               m_y;
   int               m_anchor;        // ANCHOR_LEFT right of the candle, ANCHOR_RIGHT left of it (D39)
   int               m_shown;         // 1 shown, 0 hidden (candle or Bid out of view), -1 not written yet

   void              Forget();
   bool              Place(const datetime open, const double price, const long left, int &x, int &y, int &anchor,
                           string &text, bool &visible) const;

public:
                     CCandleTime();
   void              Configure(const SCandleStyle &style);
   bool              On() const { return m_style.on; }
   // Draws, updates or moves RD_CT. True when the chart changed (redraw);
   // created: the object was made (App raises the panel above it).
   bool              Update(const double bid, bool &created);
   // True when an object was deleted.
   bool              Remove();
   // The countdown as last drawn (self-test); false when none was drawn.
   bool              Last(SCandleClock &c) const;
   // The estimated server time the countdown uses (self-test).
   datetime          ServerNow() { return m_clock.Now(); }
   static string     ObjectName() { return RD_CANDLE_OBJ; }
  };

//+------------------------------------------------------------------+
CCandleTime::CCandleTime()
  {
   m_style.Defaults();
   m_last.Reset();
   m_offDone = false;
   Forget();
  }

void CCandleTime::Forget()
  {
   m_styled = false;
   m_text = "";
   m_color = clrNONE;
   m_x = -1;
   m_y = -1;
   m_anchor = -1;
   m_shown = -1;
  }

// An EA keeps RD_CT across a timeframe change or new inputs: rewrite it all.
void CCandleTime::Configure(const SCandleStyle &style)
  {
   m_style = style;
   m_last.Reset();
   m_offDone = false;
   Forget();
  }

bool CCandleTime::Remove()
  {
   Forget();
   m_last.Reset();
   if(ObjectFind(0, RD_CANDLE_OBJ) < 0)
      return false;
   return ObjectDelete(0, RD_CANDLE_OBJ);
  }

bool CCandleTime::Last(SCandleClock &c) const
  {
   c = m_last;
   return m_last.close > 0;
  }

//+------------------------------------------------------------------+
//| Pixel place from bar 0 (a bar that exists) at 'price': right of  |
//| the candle when the text fits before the chart's right edge,     |
//| else left of it (D39). visible = false while bar 0 or the price  |
//| is outside the chart. False when the chart gives no coordinates. |
//+------------------------------------------------------------------+
bool CCandleTime::Place(const datetime open, const double price, const long left, int &x, int &y, int &anchor,
                        string &text, bool &visible) const
  {
   visible = false;
   int x0 = 0;
   int y0 = 0;
   if(!ChartTimePriceToXY(0, 0, open, price, x0, y0))
      return false;
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(x0 < 0 || x0 > w || y0 < 0 || y0 > h)
      return true;
   int half = 2;
   datetime prev = iTime(_Symbol, PERIOD_CURRENT, 1);
   int x1 = 0;
   int y1 = 0;
   if(prev > 0 && ChartTimePriceToXY(0, 0, prev, price, x1, y1) && x0 - x1 > 0)
      half = MathMax(1, (x0 - x1) / 2);
   string right = RdCountdownText(left);
   uint tw = 0;
   uint th = 0;
   bool measured = TextSetFont(m_style.font, -m_style.fontSize * 10) && TextGetSize(right, tw, th);
   int xr = x0 + half + RD_CANDLE_GAP;
   if(!measured || xr + (int)tw <= w)
     {
      x = xr;
      anchor = ANCHOR_LEFT;
      text = right;
     }
   else
     {
      x = x0 - half - RD_CANDLE_GAP;
      anchor = ANCHOR_RIGHT;
      text = RdCountdownText(left, true);
     }
   y = y0;
   visible = true;
   return true;
  }

//+------------------------------------------------------------------+
bool CCandleTime::Update(const double bid, bool &created)
  {
   created = false;
   if(!m_style.on)
     {
      if(m_offDone)
         return false;
      m_offDone = true;
      return Remove();
     }
   datetime open = iTime(_Symbol, PERIOD_CURRENT, 0);
   int period = PeriodSeconds(PERIOD_CURRENT);
   if(open <= 0 || period <= 0)
      return false;   // no bars yet
   bool monthly = (_Period == PERIOD_MN1);
   datetime now = m_clock.Now();
   bool inSession = false;
   if(now >= RdCandleClose(open, period, monthly))
     {
      bool known = false;
      inSession = CMarket::InSession(_Symbol, now, known) && known;
     }
   SCandleClock c;
   if(!RdCandleClock(open, period, monthly, now, inSession, m_style.warnPct, c))
      return false;
   m_last = c;
   double price = bid;
   if(!(price > 0.0))
      price = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(!(price > 0.0))
      return false;
   int x = 0;
   int y = 0;
   int anchor = ANCHOR_LEFT;
   string text = c.text;
   bool visible = false;
   if(!Place(open, price, c.left, x, y, anchor, text, visible))
      return false;
   color col = c.warn ? m_style.warn : m_style.normal;

   bool changed = false;
   if(ObjectFind(0, RD_CANDLE_OBJ) < 0)
     {
      Forget();
      if(!ObjectCreate(0, RD_CANDLE_OBJ, OBJ_LABEL, 0, 0, 0))
         return false;
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_BACK, false);
      ObjectSetString(0, RD_CANDLE_OBJ, OBJPROP_TOOLTIP, "Time left until this candle closes (server time)");
      created = true;
      changed = true;
     }
   if(!m_styled)
     {
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(0, RD_CANDLE_OBJ, OBJPROP_FONT, m_style.font);
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_FONTSIZE, m_style.fontSize);
      m_styled = true;
      changed = true;
     }
   int shown = visible ? 1 : 0;
   if(shown != m_shown)
     {
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_TIMEFRAMES, visible ? RD_OBJ_ALL_PERIODS : RD_OBJ_NO_PERIODS);
      m_shown = shown;
      changed = true;
     }
   if(!visible)
      return changed;
   if(anchor != m_anchor)
     {
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_ANCHOR, anchor);
      m_anchor = anchor;
      changed = true;
     }
   if(text != m_text)
     {
      ObjectSetString(0, RD_CANDLE_OBJ, OBJPROP_TEXT, text);
      m_text = text;
      changed = true;
     }
   if(col != m_color)
     {
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_COLOR, col);
      m_color = col;
      changed = true;
     }
   if(x != m_x || y != m_y)
     {
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, RD_CANDLE_OBJ, OBJPROP_YDISTANCE, y);
      m_x = x;
      m_y = y;
      changed = true;
     }
   return changed;
  }

#endif // RD_SERVICES_CANDLETIME_MQH
