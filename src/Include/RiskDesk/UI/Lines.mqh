//+------------------------------------------------------------------+
//| RiskDesk - UI/Lines.mqh                                          |
//| Layer   : UI                                                     |
//| Purpose : the planning lines (05 section 5): SL, TP and Entry    |
//|           OBJ_HLINE objects and their OBJ_TEXT labels (F-18).    |
//|           Creates, adopts (they are chart objects: a timeframe   |
//|           change or a restart keeps them), moves, deletes and    |
//|           reads them. Which lines a mode needs, where they go    |
//|           and what the labels say is decided by App.             |
//|           Lines: selectable, not hidden, created selected so the |
//|           user can drag at once. Labels: not selectable, hidden  |
//|           from the object list, right of the current candle;     |
//|           where the panel would cover one it goes left of the    |
//|           panel, else right of it (ADR-024).                     |
//|           The "TP line placed by the user" flag (InpTpFollowsSl) |
//|           is kept in the TP line's tooltip, so it survives a     |
//|           restart together with the line.                        |
//+------------------------------------------------------------------+
#ifndef RD_UI_LINES_MQH
#define RD_UI_LINES_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "..\Platform\Compat.mqh"
#include "Theme.mqh"
#include "Layout.mqh"
#include "Widgets.mqh"

#define RD_LINE_PREFIX        "RD_LN_"   // RD_LN_SL, RD_LN_TP, RD_LN_EN
#define RD_LINE_LABEL_PREFIX  "RD_LT_"   // RD_LT_SL, RD_LT_TP, RD_LT_EN
#define RD_LINE_ROLES         3          // ELineRole: ENTRY, SL, TP
#define RD_ZORDER_LINES       100        // below the panel: a click on the panel goes to the panel
#define RD_LINE_TIP_FREE      "placed by you"

// Look of the lines and labels (07-settings Colors, Chart extras).
struct SLineStyle
  {
   color             sl;
   color             tp;
   color             entry;
   color             slLabel;         // InpColorSlLoss
   int               width;           // InpLineWidth (SL/TP; the entry line is dash-dot, width 1)
   int               labelSize;       // InpSlLossFontSize
   string            labelFont;
   double            tpRR;            // shown in the TP line's tooltip

   void              Defaults()
     {
      sl = clrRed;
      tp = clrLimeGreen;
      entry = clrWhite;
      slLabel = clrWhite;
      width = 2;
      labelSize = 10;
      labelFont = "Segoe UI";
      tpRR = 1.0;
     }
  };

class CLines
  {
private:
   SLineStyle        m_style;
   CRdRedraw        *m_redraw;
   //--- last written label properties (05 section 3: write only what changed)
   bool              m_known[RD_LINE_ROLES];
   string            m_text[RD_LINE_ROLES];
   color             m_color[RD_LINE_ROLES];
   datetime          m_time[RD_LINE_ROLES];
   double            m_price[RD_LINE_ROLES];
   int               m_anchor[RD_LINE_ROLES];
   //--- the panel's shown rectangle in chart pixels (ADR-024); w = 0: none
   int               m_avoidX, m_avoidY, m_avoidW, m_avoidH, m_avoidGap;

   void              Mark() { if(m_redraw != NULL) m_redraw.Mark(); }
   void              StyleLine(const ELineRole role, const bool tpFree);
   string            Tooltip(const ELineRole role, const bool tpFree) const;
   void              LabelAnchor(datetime &t, int &anchor) const;
   void              AvoidPanel(const string text, const double price, datetime &t, int &anchor) const;
   bool              Covers(const int left, const int top, const int w, const int h) const;
   static bool       BarTimeAtX(const int x, const bool atOrLeft, const double price, datetime &t);

public:
                     CLines();
   void              Init(const SLineStyle &style, CRdRedraw *redraw);

   static string     Suffix(const ELineRole role);
   static string     LineName(const ELineRole role) { return RD_LINE_PREFIX + Suffix(role); }
   static string     LabelName(const ELineRole role) { return RD_LINE_LABEL_PREFIX + Suffix(role); }
   static string     RoleText(const ELineRole role);
   static bool       RoleOf(const string name, ELineRole &role);
   static int        DeleteAll();
   static bool       VisibleRange(double &lo, double &hi);

   bool              Exists(const ELineRole role) const { return ObjectFind(0, LineName(role)) >= 0; }
   bool              LabelExists(const ELineRole role) const { return ObjectFind(0, LabelName(role)) >= 0; }
   double            Price(const ELineRole role) const;
   ELineMode         ModeOnChart() const;
   void              Read(const ELineMode mode, SLines &l) const;
   bool              Place(const ELineRole role, const double price);
   void              Delete(const ELineRole role);
   bool              TpFree() const;
   void              SetTpFree(const bool free);
   void              Restyle();
   void              SetAvoid(const int x, const int y, const int w, const int h, const int gap);
   bool              ShowLabel(const ELineRole role, const string text, const color clr);
   void              HideLabel(const ELineRole role);
   static bool       BoxAt(const string font, const int size, const string text, const double price, const datetime t,
                           const int anchor, int &left, int &top, int &w, int &h);
   static bool       LabelBox(const string name, int &left, int &top, int &w, int &h);
   color             LineColor(const ELineRole role) const;
   color             LabelColor() const { return m_style.slLabel; }
  };

//+------------------------------------------------------------------+
CLines::CLines()
  {
   m_style.Defaults();
   m_redraw = NULL;
   for(int i = 0; i < RD_LINE_ROLES; i++)
      m_known[i] = false;
   m_avoidX = 0;
   m_avoidY = 0;
   m_avoidW = 0;
   m_avoidH = 0;
   m_avoidGap = 0;
  }

void CLines::Init(const SLineStyle &style, CRdRedraw *redraw)
  {
   m_style = style;
   m_redraw = redraw;
   for(int i = 0; i < RD_LINE_ROLES; i++)
      m_known[i] = false;   // write every label property once (the inputs may have changed)
  }

string CLines::Suffix(const ELineRole role)
  {
   if(role == LINEROLE_ENTRY)
      return "EN";
   if(role == LINEROLE_SL)
      return "SL";
   return "TP";
  }

string CLines::RoleText(const ELineRole role)
  {
   if(role == LINEROLE_ENTRY)
      return "Entry";
   if(role == LINEROLE_SL)
      return "SL";
   return "TP";
  }

bool CLines::RoleOf(const string name, ELineRole &role)
  {
   for(int i = 0; i < RD_LINE_ROLES; i++)
      if(name == LineName((ELineRole)i))
        {
         role = (ELineRole)i;
         return true;
        }
   return false;
  }

// Planning lines and their labels. Returns the number of objects deleted.
int CLines::DeleteAll()
  {
   return RdDeleteObjects(RD_LINE_PREFIX) + RdDeleteObjects(RD_LINE_LABEL_PREFIX);
  }

// Price range of the main window as drawn now (05 section 5). false when unknown.
bool CLines::VisibleRange(double &lo, double &hi)
  {
   lo = ChartGetDouble(0, CHART_PRICE_MIN, 0);
   hi = ChartGetDouble(0, CHART_PRICE_MAX, 0);
   return MathIsValidNumber(lo) && MathIsValidNumber(hi) && lo > 0.0 && hi > lo;
  }

double CLines::Price(const ELineRole role) const
  {
   if(!Exists(role))
      return 0.0;
   return ObjectGetDouble(0, LineName(role), OBJPROP_PRICE, 0);
  }

//+------------------------------------------------------------------+
//| The mode the objects on the chart describe: Entry + SL = pending,|
//| SL without Entry = market, else none (05 section 5 "Mode rules").|
//+------------------------------------------------------------------+
ELineMode CLines::ModeOnChart() const
  {
   bool sl = Exists(LINEROLE_SL);
   if(sl && Exists(LINEROLE_ENTRY))
      return LINES_PENDING;
   if(sl)
      return LINES_MARKET;
   return LINES_NONE;
  }

// Raw line prices (the planner normalizes them, BC-03).
void CLines::Read(const ELineMode mode, SLines &l) const
  {
   l.Reset();
   l.mode = mode;
   l.sl = Price(LINEROLE_SL);
   l.hasTp = Exists(LINEROLE_TP);
   l.tp = l.hasTp ? Price(LINEROLE_TP) : 0.0;
   l.entry = (mode == LINES_PENDING) ? Price(LINEROLE_ENTRY) : 0.0;
  }

//+------------------------------------------------------------------+
//| Create the line (selected, so it can be dragged at once) or move |
//| it. True when it had to be created.                              |
//+------------------------------------------------------------------+
bool CLines::Place(const ELineRole role, const double price)
  {
   string name = LineName(role);
   if(ObjectFind(0, name) >= 0)
     {
      if(MathAbs(Price(role) - price) > 0.0)
        {
         ObjectMove(0, name, 0, 0, price);
         Mark();
        }
      return false;
     }
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
      return false;
   StyleLine(role, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, true);
   Mark();
   return true;
  }

void CLines::StyleLine(const ELineRole role, const bool tpFree)
  {
   string name = LineName(role);
   bool entry = (role == LINEROLE_ENTRY);
   ObjectSetInteger(0, name, OBJPROP_COLOR, LineColor(role));
   // MetaTrader draws dash/dot styles only at width 1 (05 section 5)
   ObjectSetInteger(0, name, OBJPROP_STYLE, entry ? STYLE_DASHDOT : STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, entry ? 1 : m_style.width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, RD_ZORDER_LINES);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, RD_OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, Tooltip(role, tpFree));
  }

// Adopted lines take the current inputs' colours and width.
void CLines::Restyle()
  {
   for(int i = 0; i < RD_LINE_ROLES; i++)
     {
      ELineRole role = (ELineRole)i;
      if(Exists(role))
         StyleLine(role, role == LINEROLE_TP && TpFree());
     }
   Mark();
  }

color CLines::LineColor(const ELineRole role) const
  {
   if(role == LINEROLE_ENTRY)
      return m_style.entry;
   if(role == LINEROLE_SL)
      return m_style.sl;
   return m_style.tp;
  }

string CLines::Tooltip(const ELineRole role, const bool tpFree) const
  {
   if(role == LINEROLE_ENTRY)
      return "RiskDesk entry line of the pending order - drag it to the entry price";
   if(role == LINEROLE_SL)
      return "RiskDesk SL line - drag it to your stop-loss; the lot size follows";
   if(tpFree)
      return "RiskDesk TP line, " + RD_LINE_TIP_FREE + " (it no longer follows the SL)";
   return "RiskDesk TP line - keeps R/R " + RdNum(m_style.tpRR, 2) +
          " while you move the SL; drag it to place it yourself";
  }

void CLines::Delete(const ELineRole role)
  {
   if(ObjectFind(0, LineName(role)) >= 0)
      ObjectDelete(0, LineName(role));
   HideLabel(role);
   Mark();
  }

//+------------------------------------------------------------------+
//| InpTpFollowsSl: the TP line follows the SL until the user drags  |
//| it (05 section 5).                                               |
//+------------------------------------------------------------------+
bool CLines::TpFree() const
  {
   if(!Exists(LINEROLE_TP))
      return false;
   return StringFind(ObjectGetString(0, LineName(LINEROLE_TP), OBJPROP_TOOLTIP), RD_LINE_TIP_FREE) >= 0;
  }

void CLines::SetTpFree(const bool free)
  {
   if(Exists(LINEROLE_TP))
      ObjectSetString(0, LineName(LINEROLE_TP), OBJPROP_TOOLTIP, Tooltip(LINEROLE_TP, free));
  }

//+------------------------------------------------------------------+
//| 05 section 5 labels: time = open of the current bar + 3 bars,    |
//| left-anchored, when the chart has its right margin (chart shift);|
//| else right-anchored at the current bar, so the text stays in     |
//| view.                                                            |
//+------------------------------------------------------------------+
void CLines::LabelAnchor(datetime &t, int &anchor) const
  {
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t0 <= 0)
      t0 = TimeCurrent();
   bool shift = ChartGetInteger(0, CHART_SHIFT) != 0;
   t = shift ? (datetime)(t0 + 3 * PeriodSeconds(PERIOD_CURRENT)) : t0;
   anchor = shift ? ANCHOR_LEFT_LOWER : ANCHOR_RIGHT_LOWER;
  }

//+------------------------------------------------------------------+
//| The panel's shown rectangle (anchor to camera, chart pixels) that |
//| labels keep clear of, 'gap' px apart. w or h 0: none.            |
//+------------------------------------------------------------------+
void CLines::SetAvoid(const int x, const int y, const int w, const int h, const int gap)
  {
   m_avoidX = x;
   m_avoidY = y;
   m_avoidW = w;
   m_avoidH = h;
   m_avoidGap = MathMax(0, gap);
  }

bool CLines::Covers(const int left, const int top, const int w, const int h) const
  {
   return m_avoidW > 0 && m_avoidH > 0 &&
          left < m_avoidX + m_avoidW + m_avoidGap && left + w > m_avoidX - m_avoidGap &&
          top < m_avoidY + m_avoidH && top + h > m_avoidY;
  }

//+------------------------------------------------------------------+
//| Pixel box of an OBJ_TEXT label (lower anchors only) drawn at     |
//| (t, price) with 'anchor'.                                        |
//+------------------------------------------------------------------+
bool CLines::BoxAt(const string font, const int size, const string text, const double price, const datetime t,
                   const int anchor, int &left, int &top, int &w, int &h)
  {
   int x = 0;
   int y = 0;
   left = 0;
   top = 0;
   if(!ChartTimePriceToXY(0, 0, t, price, x, y))
      return false;
   if(!CLayout::TextSize(font, size, text, w, h))
      return false;
   left = (anchor == ANCHOR_RIGHT_LOWER) ? x - w : x;
   top = y - h;
   return true;
  }

// The box of a label as it is on the chart (self-test).
bool CLines::LabelBox(const string name, int &left, int &top, int &w, int &h)
  {
   w = 0;
   h = 0;
   if(ObjectFind(0, name) < 0)
      return false;
   return BoxAt(ObjectGetString(0, name, OBJPROP_FONT), (int)ObjectGetInteger(0, name, OBJPROP_FONTSIZE),
                ObjectGetString(0, name, OBJPROP_TEXT), ObjectGetDouble(0, name, OBJPROP_PRICE, 0),
                (datetime)ObjectGetInteger(0, name, OBJPROP_TIME, 0), (int)ObjectGetInteger(0, name, OBJPROP_ANCHOR),
                left, top, w, h);
  }

//+------------------------------------------------------------------+
//| Time of the bar whose x is the largest <= x (atOrLeft) or the    |
//| smallest >= x. Bars are evenly spaced on the chart, also in the  |
//| empty area right of the current bar (future times), so the time |
//| follows from bar 0's x and the bar spacing.                      |
//+------------------------------------------------------------------+
bool CLines::BarTimeAtX(const int x, const bool atOrLeft, const double price, datetime &t)
  {
   t = 0;
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 1);
   int x0 = 0;
   int x1 = 0;
   int y = 0;
   if(t0 <= 0 || t1 <= 0 || !ChartTimePriceToXY(0, 0, t0, price, x0, y) || !ChartTimePriceToXY(0, 0, t1, price, x1, y))
      return false;
   int spacing = x0 - x1;
   if(spacing <= 0)
      return false;
   double bars = (double)(x - x0) / spacing;   // > 0: right of the current bar
   int n = atOrLeft ? (int)MathFloor(bars) : (int)MathCeil(bars);
   if(n >= 0)
      t = (datetime)(t0 + n * PeriodSeconds(PERIOD_CURRENT));
   else
      t = iTime(_Symbol, PERIOD_CURRENT, -n);
   return t > 0;
  }

//+------------------------------------------------------------------+
//| ADR-024: a label the panel would cover goes left of the panel    |
//| (right-aligned, so it ends 'gap' px before it); without room     |
//| there, right of the panel when it ends before the price scale;   |
//| else it stays where 05 section 5 puts it.                        |
//+------------------------------------------------------------------+
void CLines::AvoidPanel(const string text, const double price, datetime &t, int &anchor) const
  {
   int left = 0;
   int top = 0;
   int w = 0;
   int h = 0;
   if(!BoxAt(m_style.labelFont, m_style.labelSize, text, price, t, anchor, left, top, w, h) || !Covers(left, top, w, h))
      return;
   datetime moved = 0;
   int edge = m_avoidX - m_avoidGap;
   if(edge - w >= 0 && BarTimeAtX(edge, true, price, moved))
     {
      t = moved;
      anchor = ANCHOR_RIGHT_LOWER;
      return;
     }
   edge = m_avoidX + m_avoidW + m_avoidGap;
   if(edge + w <= (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS) && BarTimeAtX(edge, false, price, moved))
     {
      t = moved;
      anchor = ANCHOR_LEFT_LOWER;
     }
  }

//+------------------------------------------------------------------+
//| Label of a line at its price; true when the object was created.  |
//+------------------------------------------------------------------+
bool CLines::ShowLabel(const ELineRole role, const string text, const color clr)
  {
   string name = LabelName(role);
   double price = Price(role);
   datetime t = 0;
   int anchor = ANCHOR_LEFT_LOWER;
   LabelAnchor(t, anchor);
   AvoidPanel(text, price, t, anchor);
   bool created = false;
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return false;
      created = true;
     }
   if(created || !m_known[role])
     {
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, RD_ZORDER_LINES);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, RD_OBJ_ALL_PERIODS);
      ObjectSetString(0, name, OBJPROP_FONT, m_style.labelFont);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_style.labelSize);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, RD_TOOLTIP_NONE);
      m_known[role] = false;
     }
   bool all = !m_known[role];
   if(all || text != m_text[role])
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      m_text[role] = text;
      Mark();
     }
   if(all || clr != m_color[role])
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      m_color[role] = clr;
      Mark();
     }
   if(all || anchor != m_anchor[role])
     {
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      m_anchor[role] = anchor;
      Mark();
     }
   // exact change detection of the cached value (not a price comparison)
   if(all || t != m_time[role] || MathAbs(price - m_price[role]) > 0.0)
     {
      ObjectMove(0, name, 0, t, price);
      m_time[role] = t;
      m_price[role] = price;
      Mark();
     }
   m_known[role] = true;
   return created;
  }

void CLines::HideLabel(const ELineRole role)
  {
   if(ObjectFind(0, LabelName(role)) >= 0)
     {
      ObjectDelete(0, LabelName(role));
      Mark();
     }
   m_known[role] = false;
  }

#endif // RD_UI_LINES_MQH
