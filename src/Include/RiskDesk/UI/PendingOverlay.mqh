// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - UI/PendingOverlay.mqh                                 |
//| Layer   : UI                                                     |
//| Purpose : the pending order overlay (F-22, 05 section 6): every  |
//|           placed pending order in chart scope drawn by RiskDesk  |
//|           with OBJ_HLINE lines RD_PO_<ticket>_EN/SL/TP (entry    |
//|           dash-dot, SL/TP dashed, width 1, the overlay colours,  |
//|           selectable, not hidden) and OBJ_TEXT labels            |
//|           RD_PT_<ticket>_EN/SL/TP placed like the planning line  |
//|           labels (05 section 5, ADR-024).                        |
//|           App lists the orders and writes the label texts (they  |
//|           need the money valuation); Render() draws them every   |
//|           refresh:                                               |
//|           - a line moves only when its order's value changed     |
//|             (MetaTrader's own trade levels, another tool, OP-16) |
//|             or after Snap(): a line the user is dragging is left |
//|             alone until it is dropped (CHARTEVENT_OBJECT_DRAG,   |
//|             handled by App as OP-16)                             |
//|           - a deleted overlay object is drawn again; deleting it |
//|             never touches the order (F-22 AC3)                   |
//|           - the objects of an order that is gone are removed     |
//| Never sends a request: dropping a line is OP-16 in App.          |
//+------------------------------------------------------------------+
#ifndef RD_UI_PENDINGOVERLAY_MQH
#define RD_UI_PENDINGOVERLAY_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "..\Platform\Compat.mqh"
#include "Theme.mqh"
#include "Widgets.mqh"
#include "Lines.mqh"

#define RD_OVERLAY_LINE_PREFIX   "RD_PO_"   // RD_PO_<ticket>_EN / _SL / _TP
#define RD_OVERLAY_LABEL_PREFIX  "RD_PT_"   // RD_PT_<ticket>_EN / _SL / _TP

// Overlay colours (07 Colors: "Pending Overlay Entry / SL / TP Line Color").
struct SOverlayStyle
  {
   color             entry;
   color             sl;
   color             tp;

   void              Defaults() { entry = clrLimeGreen; sl = clrRed; tp = clrRed; }
  };

// One placed order as App hands it over: the order and its label texts.
struct SOverlayItem
  {
   SOrder            o;
   string            label[RD_LINE_ROLES];        // "" = no label
   color             labelColor[RD_LINE_ROLES];   // clrNONE = the line's colour
  };

// What is drawn for one ticket (05 section 3: write only what changed).
struct SOverlayDrawn
  {
   ulong             ticket;
   double            level[RD_LINE_ROLES];        // order value the line was last put at, 0 = no line
   bool              force;                       // Snap(): every line back to the order's value
   bool              seen;
   bool              known[RD_LINE_ROLES];        // label properties written once
   string            text[RD_LINE_ROLES];
   color             clr[RD_LINE_ROLES];
   datetime          time[RD_LINE_ROLES];
   double            price[RD_LINE_ROLES];
   int               anchor[RD_LINE_ROLES];

   void              Reset(const ulong t)
     {
      ticket = t;
      force = true;
      seen = false;
      for(int i = 0; i < RD_LINE_ROLES; i++)
        {
         level[i] = 0.0;
         known[i] = false;
         text[i] = "";
         clr[i] = clrNONE;
         time[i] = 0;
         price[i] = 0.0;
         anchor[i] = ANCHOR_LEFT_LOWER;
        }
     }
  };

class CPendingOverlay
  {
private:
   SOverlayStyle     m_style;
   CLines           *m_lines;          // label placement and font (ADR-024)
   CRdRedraw        *m_redraw;
   SOverlayDrawn     m_drawn[];
   bool              m_sweep;          // first Render: remove objects of orders that are gone

   void              Mark() { if(m_redraw != NULL) m_redraw.Mark(); }
   int               Find(const ulong ticket) const;
   void              StyleLine(const string name, const ELineRole role, const SOrder &o);
   string            Tooltip(const ELineRole role, const SOrder &o) const;
   bool              DrawLine(const int i, const ELineRole role, const SOrder &o);
   bool              DrawLabel(const int i, const ELineRole role, const string text, const color clr);
   void              RemoveObjects(const ulong ticket, const ELineRole role);
   void              Sweep(const SOverlayItem &items[]);
   static bool       ParseWith(const string prefix, const string name, ulong &ticket, ELineRole &role);

public:
                     CPendingOverlay();
   void              Init(const SOverlayStyle &style, CLines *lines, CRdRedraw *redraw);

   static string     LineName(const ulong ticket, const ELineRole role);
   static string     LabelName(const ulong ticket, const ELineRole role);
   static bool       Parse(const string name, ulong &ticket, ELineRole &role);
   static int        DeleteAll();

   bool              Render(const SOverlayItem &items[]);
   void              Snap(const ulong ticket);
   double            Drawn(const ulong ticket, const ELineRole role) const;
   int               Count() const { return ArraySize(m_drawn); }
   void              Clear();
   color             LineColor(const ELineRole role) const;
  };

//+------------------------------------------------------------------+
CPendingOverlay::CPendingOverlay()
  {
   m_style.Defaults();
   m_lines = NULL;
   m_redraw = NULL;
   m_sweep = true;
  }

//+------------------------------------------------------------------+
//| Every OnInit: the inputs may have changed (colours), and objects |
//| kept across a timeframe change are adopted by name.              |
//+------------------------------------------------------------------+
void CPendingOverlay::Init(const SOverlayStyle &style, CLines *lines, CRdRedraw *redraw)
  {
   m_style = style;
   m_lines = lines;
   m_redraw = redraw;
   ArrayResize(m_drawn, 0);
   m_sweep = true;
  }

string CPendingOverlay::LineName(const ulong ticket, const ELineRole role)
  {
   return RD_OVERLAY_LINE_PREFIX + IntegerToString((long)ticket) + "_" + CLines::Suffix(role);
  }

string CPendingOverlay::LabelName(const ulong ticket, const ELineRole role)
  {
   return RD_OVERLAY_LABEL_PREFIX + IntegerToString((long)ticket) + "_" + CLines::Suffix(role);
  }

//+------------------------------------------------------------------+
//| "RD_PO_123457_SL" -> ticket 123457, LINEROLE_SL.                 |
//+------------------------------------------------------------------+
bool CPendingOverlay::ParseWith(const string prefix, const string name, ulong &ticket, ELineRole &role)
  {
   ticket = 0;
   role = LINEROLE_ENTRY;
   int pl = StringLen(prefix);
   if(StringSubstr(name, 0, pl) != prefix)
      return false;
   int us = StringFind(name, "_", pl);
   if(us <= pl || us - pl > 20)
      return false;
   for(int i = pl; i < us; i++)
     {
      ushort c = StringGetCharacter(name, i);
      if(c < '0' || c > '9')
         return false;
     }
   string suffix = StringSubstr(name, us + 1);
   bool found = false;
   for(int k = 0; k < RD_LINE_ROLES && !found; k++)
      if(suffix == CLines::Suffix((ELineRole)k))
        {
         role = (ELineRole)k;
         found = true;
        }
   if(!found)
      return false;
   ticket = (ulong)StringToInteger(StringSubstr(name, pl, us - pl));
   return ticket > 0;
  }

// A line of the overlay (not a label).
bool CPendingOverlay::Parse(const string name, ulong &ticket, ELineRole &role)
  {
   return ParseWith(RD_OVERLAY_LINE_PREFIX, name, ticket, role);
  }

int CPendingOverlay::DeleteAll()
  {
   return RdDeleteObjects(RD_OVERLAY_LINE_PREFIX) + RdDeleteObjects(RD_OVERLAY_LABEL_PREFIX);
  }

// Overlay switched off (InpShowPendingOverlay) or RiskDesk leaves: nothing drawn, nothing remembered.
void CPendingOverlay::Clear()
  {
   if(DeleteAll() > 0)
      Mark();
   ArrayResize(m_drawn, 0);
   m_sweep = true;
  }

int CPendingOverlay::Find(const ulong ticket) const
  {
   int n = ArraySize(m_drawn);
   for(int i = 0; i < n; i++)
      if(m_drawn[i].ticket == ticket)
         return i;
   return -1;
  }

color CPendingOverlay::LineColor(const ELineRole role) const
  {
   if(role == LINEROLE_ENTRY)
      return m_style.entry;
   if(role == LINEROLE_SL)
      return m_style.sl;
   return m_style.tp;
  }

string CPendingOverlay::Tooltip(const ELineRole role, const SOrder &o) const
  {
   string order = RdOrderText(o.side, o.kind) + " " + RdTicketText(o.ticket);
   if(role == LINEROLE_ENTRY)
      return "Risk Desk overlay: " + order + " " + RdNum(o.volume) + " lot @ " + DoubleToString(o.price, _Digits) +
             (o.expiration > 0 ? " (expires " + TimeToString(o.expiration, TIME_DATE | TIME_MINUTES) + " server time)" : "") +
             " - drag to move the whole order (SL and TP move with it)";
   if(role == LINEROLE_SL)
      return "Risk Desk overlay: SL " + DoubleToString(o.sl, _Digits) + " of " + order + " - drag to change the order's SL";
   return "Risk Desk overlay: TP " + DoubleToString(o.tp, _Digits) + " of " + order + " - drag to change the order's TP";
  }

//+------------------------------------------------------------------+
//| 05 section 5 table: entry dash-dot, SL/TP dashed, width 1 (dash  |
//| styles are drawn only at width 1), selectable, not hidden.       |
//+------------------------------------------------------------------+
void CPendingOverlay::StyleLine(const string name, const ELineRole role, const SOrder &o)
  {
   ObjectSetInteger(0, name, OBJPROP_COLOR, LineColor(role));
   ObjectSetInteger(0, name, OBJPROP_STYLE, role == LINEROLE_ENTRY ? STYLE_DASHDOT : STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, RD_ZORDER_LINES);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, RD_OBJ_ALL_PERIODS);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, Tooltip(role, o));
  }

//+------------------------------------------------------------------+
//| One line of item i at its order's value. Created when missing    |
//| (also after the user deleted it); moved only when the order's    |
//| value changed or after Snap(). True when it had to be created.   |
//+------------------------------------------------------------------+
bool CPendingOverlay::DrawLine(const int i, const ELineRole role, const SOrder &o)
  {
   double value = (role == LINEROLE_ENTRY) ? o.price : (role == LINEROLE_SL ? o.sl : o.tp);
   string name = LineName(o.ticket, role);
   bool exists = ObjectFind(0, name) >= 0;
   if(!(value > 0.0))
     {
      if(exists)
         RemoveObjects(o.ticket, role);
      m_drawn[i].level[role] = 0.0;
      return false;
     }
   if(!exists)
     {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, value))
         return false;
      StyleLine(name, role, o);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      m_drawn[i].level[role] = value;
      Mark();
      return true;
     }
   // exact change detection of the cached value (not a price comparison)
   if(m_drawn[i].force || MathAbs(m_drawn[i].level[role] - value) > 0.0)
     {
      if(MathAbs(ObjectGetDouble(0, name, OBJPROP_PRICE, 0) - value) > 0.0)
         ObjectMove(0, name, 0, 0, value);
      StyleLine(name, role, o);
      m_drawn[i].level[role] = value;
      Mark();
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Label of a line at the order's value, placed like the planning   |
//| labels. True when the object was created.                        |
//+------------------------------------------------------------------+
bool CPendingOverlay::DrawLabel(const int i, const ELineRole role, const string text, const color clr)
  {
   ulong ticket = m_drawn[i].ticket;
   string name = LabelName(ticket, role);
   double price = m_drawn[i].level[role];
   if(text == "" || !(price > 0.0) || m_lines == NULL)
     {
      if(ObjectFind(0, name) >= 0)
        {
         ObjectDelete(0, name);
         Mark();
        }
      m_drawn[i].known[role] = false;
      return false;
     }
   datetime t = 0;
   int anchor = ANCHOR_LEFT_LOWER;
   m_lines.LabelSpot(text, price, t, anchor);
   bool created = false;
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
         return false;
      created = true;
     }
   if(created || !m_drawn[i].known[role])
     {
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, RD_ZORDER_LINES);
      ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, RD_OBJ_ALL_PERIODS);
      ObjectSetString(0, name, OBJPROP_FONT, m_lines.LabelFont());
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, m_lines.LabelSize());
      ObjectSetString(0, name, OBJPROP_TOOLTIP, RD_TOOLTIP_NONE);
      m_drawn[i].known[role] = false;
     }
   bool all = !m_drawn[i].known[role];
   if(all || text != m_drawn[i].text[role])
     {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      m_drawn[i].text[role] = text;
      Mark();
     }
   if(all || clr != m_drawn[i].clr[role])
     {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      m_drawn[i].clr[role] = clr;
      Mark();
     }
   if(all || anchor != m_drawn[i].anchor[role])
     {
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      m_drawn[i].anchor[role] = anchor;
      Mark();
     }
   if(all || t != m_drawn[i].time[role] || MathAbs(price - m_drawn[i].price[role]) > 0.0)
     {
      ObjectMove(0, name, 0, t, price);
      m_drawn[i].time[role] = t;
      m_drawn[i].price[role] = price;
      Mark();
     }
   m_drawn[i].known[role] = true;
   return created;
  }

void CPendingOverlay::RemoveObjects(const ulong ticket, const ELineRole role)
  {
   string line = LineName(ticket, role);
   string label = LabelName(ticket, role);
   if(ObjectFind(0, line) >= 0)
      ObjectDelete(0, line);
   if(ObjectFind(0, label) >= 0)
      ObjectDelete(0, label);
   Mark();
  }

//+------------------------------------------------------------------+
//| First Render after OnInit: objects kept with the chart whose     |
//| order is gone (filled or deleted while RiskDesk was not running, |
//| another symbol's orders after a symbol change) are removed.      |
//+------------------------------------------------------------------+
void CPendingOverlay::Sweep(const SOverlayItem &items[])
  {
   m_sweep = false;
   int n = ArraySize(items);
   for(int k = ObjectsTotal(0, -1, -1) - 1; k >= 0; k--)
     {
      string name = ObjectName(0, k, -1, -1);
      ulong ticket = 0;
      ELineRole role = LINEROLE_ENTRY;
      if(!ParseWith(RD_OVERLAY_LINE_PREFIX, name, ticket, role) && !ParseWith(RD_OVERLAY_LABEL_PREFIX, name, ticket, role))
         continue;
      bool keep = false;
      for(int i = 0; i < n && !keep; i++)
         keep = (items[i].o.ticket == ticket);
      if(!keep && ObjectDelete(0, name))
         Mark();
     }
  }

//+------------------------------------------------------------------+
//| Draw these orders, remove the rest. True when objects had to be  |
//| created (App puts the panel on top again, ADR-022).              |
//+------------------------------------------------------------------+
bool CPendingOverlay::Render(const SOverlayItem &items[])
  {
   if(m_sweep)
      Sweep(items);
   int drawn = ArraySize(m_drawn);
   for(int d = 0; d < drawn; d++)
      m_drawn[d].seen = false;
   bool created = false;
   int n = ArraySize(items);
   for(int k = 0; k < n; k++)
     {
      ulong ticket = items[k].o.ticket;
      if(ticket == 0)
         continue;
      int i = Find(ticket);
      if(i < 0)
        {
         i = ArraySize(m_drawn);
         ArrayResize(m_drawn, i + 1);
         m_drawn[i].Reset(ticket);   // adopted objects take the current style and value
        }
      m_drawn[i].seen = true;
      for(int r = 0; r < RD_LINE_ROLES; r++)
        {
         ELineRole role = (ELineRole)r;
         if(DrawLine(i, role, items[k].o))
            created = true;
         color clr = (items[k].labelColor[r] == clrNONE) ? LineColor(role) : items[k].labelColor[r];
         if(DrawLabel(i, role, items[k].label[r], clr))
            created = true;
        }
      m_drawn[i].force = false;
     }
   //--- orders that are gone (filled, deleted, out of scope)
   for(int j = ArraySize(m_drawn) - 1; j >= 0; j--)
     {
      if(m_drawn[j].seen)
         continue;
      for(int r = 0; r < RD_LINE_ROLES; r++)
         RemoveObjects(m_drawn[j].ticket, (ELineRole)r);
      int last = ArraySize(m_drawn) - 1;
      if(j < last)
         m_drawn[j] = m_drawn[last];
      ArrayResize(m_drawn, last);
     }
   return created;
  }

//+------------------------------------------------------------------+
//| OP-16: after a drop (refused or done) every line of the order    |
//| goes to the order's value on the next Render.                    |
//+------------------------------------------------------------------+
void CPendingOverlay::Snap(const ulong ticket)
  {
   int i = Find(ticket);
   if(i >= 0)
      m_drawn[i].force = true;
  }

// The order value a line was last drawn at (0: no such line).
double CPendingOverlay::Drawn(const ulong ticket, const ELineRole role) const
  {
   int i = Find(ticket);
   if(i < 0)
      return 0.0;
   return m_drawn[i].level[role];
  }

#endif // RD_UI_PENDINGOVERLAY_MQH
