//+------------------------------------------------------------------+
//| RiskDesk - UI/Panel.mqh                                          |
//| Layer   : UI                                                     |
//| Purpose : the panel (05-ui-spec sections 1-4): builds or adopts  |
//|           its chart objects, renders an SPanelModel, moves with  |
//|           the handle (drag), collapses to title + handle (hide), |
//|           stays inside the chart (clamp). It shows state and     |
//|           reports gestures; it decides nothing (App does).       |
//|           Positions: the panel anchor is the top-left corner of  |
//|           the handle row. 'Wanted' is where the user put it (the |
//|           persisted value); the shown anchor is that position    |
//|           clamped into the current chart, so a panel pushed in   |
//|           by a small window goes back when the window grows.     |
//|           Object names/types/captions: UI/PanelObjects.mqh.      |
//+------------------------------------------------------------------+
#ifndef RD_UI_PANEL_MQH
#define RD_UI_PANEL_MQH

#include "..\Domain\Types.mqh"
#include "Theme.mqh"
#include "Layout.mqh"
#include "Widgets.mqh"

// What the panel shows; App fills it on every refresh (02 section 5).
struct SPanelModel
  {
   string            riskText;
   string            riskTip;
   string            lotsText;
   bool              lotsWarn;        // red: below the minimum lot (F-03 AC3)
   string            lotsTip;
   string            pinfoText;
   bool              pinfoWarn;       // amber: "Invalid: ..."
   string            pinfoTip;
   string            spreadText;
   bool              spreadWarn;      // amber above InpSpreadWarnPts
   string            spreadTip;
   string            buttonText[PB_COUNT];
   EButtonLook       buttonLook[PB_COUNT];
   string            buttonTip[PB_COUNT];
   string            statusLine[RD_STATUS_LINES];
   ESeverity         statusSev;
   string            statusTip;
  };

class CPanel
  {
private:
   CRdWidget         m_w[PI_COUNT];
   CLayout          *m_layout;
   CTheme           *m_theme;
   CRdRedraw        *m_redraw;
   bool              m_built;
   bool              m_collapsed;
   int               m_x, m_y;            // shown anchor
   int               m_wantX, m_wantY;    // wanted anchor
   int               m_chartW, m_chartH;
   int               m_resW, m_resH;      // top-left area covered by the terminal (One-Click Trading); 0 = none
   int               m_title1W;           // width of "Risk" in the title font
   bool              m_refit;             // scale/font changed: fit every button text again
   //--- drag (05 section 3 "Move")
   bool              m_dragging;
   bool              m_mouseDown;
   bool              m_dropped;
   int               m_grabX, m_grabY;
   bool              m_scrollWas;

   void              ApplyStatic();
   void              ApplyGeometry();
   void              ApplyVisibility();
   void              PlaceLabel(const EPanelItem i, const int x, const int y, const int anchor);
   void              FitText(const EPanelItem i, const string font, const int size, const string text);
   void              ClampShown();
   bool              ItemShown(const EPanelItem i) const;

public:
                     CPanel();
   void              Init(CLayout *layout, CTheme *theme, CRdRedraw *redraw);
   bool              Build();
   void              Destroy();
   bool              ObjectsOk() const;
   void              Relayout();

   void              SetChartSize(const int w, const int h);
   void              SetReserved(const int w, const int h);
   void              SetWanted(const int x, const int y);
   int               WantedX() const { return m_wantX; }
   int               WantedY() const { return m_wantY; }
   int               ShownX() const { return m_x; }
   int               ShownY() const { return m_y; }
   void              SetCollapsed(const bool collapsed);
   bool              Collapsed() const { return m_collapsed; }

   void              Render(const SPanelModel &m);

   //--- gestures
   bool              OnMouseMove(const int x, const int y, const int buttons);
   bool              Dragging() const { return m_dragging; }
   bool              TakeDrop();
   void              CancelDrag();

   //--- object names
   static string     ItemName(const EPanelItem i);
   static ENUM_OBJECT ItemType(const EPanelItem i);
   static string     ButtonName(const EPanelButton b) { return ItemName(RdButtonItem(b)); }
   static string     ButtonCaption(const EPanelButton b);
   static bool       ButtonOf(const string name, EPanelButton &b);
   static bool       IsHide(const string name) { return name == ItemName(PI_HIDE); }
   static bool       IsHandle(const string name) { return name == ItemName(PI_HANDLE); }
   static bool       IsRiskEdit(const string name) { return name == ItemName(PI_RISK); }
   static bool       IsPanelObject(const string name);

   //--- widget access for App/Controller
   string            RiskEditText() const { return m_w[PI_RISK].ReadText(); }
   string            RiskShownText() const { return m_w[PI_RISK].Text(); }
   // After an edit the object holds what the user typed: the next Render writes the model's text again.
   void              ForgetRiskText() { m_w[PI_RISK].ForgetText(); }
   bool              ButtonPressed(const EPanelButton b) const { return m_w[RdButtonItem(b)].Pressed(); }
   void              ReleaseButton(const EPanelButton b) { m_w[RdButtonItem(b)].Release(); }
   bool              HidePressed() const { return m_w[PI_HIDE].Pressed(); }
   void              ReleaseHide() { m_w[PI_HIDE].Release(); }
   void              ReleaseHandle() { m_w[PI_HANDLE].Release(); }
   string            ShownText(const EPanelItem i) const { return m_w[i].Text(); }
   int               StatusWidth() const;
  };

//+------------------------------------------------------------------+
CPanel::CPanel()
  {
   m_layout = NULL;
   m_theme = NULL;
   m_redraw = NULL;
   m_built = false;
   m_collapsed = false;
   m_x = 0;
   m_y = 0;
   m_wantX = 0;
   m_wantY = 0;
   m_chartW = 0;
   m_chartH = 0;
   m_resW = 0;
   m_resH = 0;
   m_title1W = 0;
   m_refit = true;
   m_dragging = false;
   m_mouseDown = false;
   m_dropped = false;
   m_grabX = 0;
   m_grabY = 0;
   m_scrollWas = true;
  }

void CPanel::Init(CLayout *layout, CTheme *theme, CRdRedraw *redraw)
  {
   m_layout = layout;
   m_theme = theme;
   m_redraw = redraw;
  }

//+------------------------------------------------------------------+
//| Create or adopt every object. Drawing order is creation order,   |
//| so when only some objects exist (an older build, or the user     |
//| deleted one) all are deleted and created again in order.         |
//+------------------------------------------------------------------+
bool CPanel::Build()
  {
   int existing = 0;
   for(int i = 0; i < PI_COUNT; i++)
      if(ObjectFind(0, ItemName((EPanelItem)i)) >= 0)
         existing++;
   if(existing > 0 && existing < PI_COUNT)
      for(int i = 0; i < PI_COUNT; i++)
         ObjectDelete(0, ItemName((EPanelItem)i));

   m_built = true;
   for(int i = 0; i < PI_COUNT; i++)
     {
      EPanelItem item = (EPanelItem)i;
      ENUM_OBJECT type = ItemType(item);
      long z = RD_ZORDER_PANEL + (type == OBJ_RECTANGLE_LABEL ? 0 : (type == OBJ_LABEL ? 1 : 2));
      m_w[i].Create(ItemName(item), type, m_redraw, z);
      if(ObjectFind(0, ItemName(item)) < 0)
         m_built = false;
     }
   m_w[PI_RISK].SetReadOnly(false);
   m_w[PI_LOTS].SetReadOnly(true);
   m_w[PI_PINFO].SetReadOnly(true);
   ClampShown();
   ApplyStatic();
   ApplyGeometry();
   ApplyVisibility();
   return m_built;
  }

void CPanel::Destroy()
  {
   CancelDrag();
   for(int i = 0; i < PI_COUNT; i++)
      m_w[i].Destroy();
   m_built = false;
  }

bool CPanel::ObjectsOk() const
  {
   if(!m_built)
      return false;
   for(int i = 0; i < PI_COUNT; i++)
      if(!m_w[i].Exists())
         return false;
   return true;
  }

//+------------------------------------------------------------------+
//| After a scale change (auto-fit) or a new theme.                  |
//+------------------------------------------------------------------+
void CPanel::Relayout()
  {
   if(!m_built)
      return;
   ClampShown();
   ApplyStatic();
   ApplyGeometry();
   ApplyVisibility();
  }

//+------------------------------------------------------------------+
//| Texts, fonts and colours that do not depend on the model.        |
//+------------------------------------------------------------------+
void CPanel::ApplyStatic()
  {
   int body = m_layout.FontBody();
   int title = m_layout.FontTitle();
   int glyph = m_layout.FontGlyph();
   m_refit = true;

   m_w[PI_BG].SetColors(clrNONE, m_theme.bg, m_theme.border);
   m_w[PI_BG].SetTooltip("");

   m_w[PI_HANDLE].SetText(m_theme.glyphHandle);
   m_w[PI_HANDLE].SetFont(m_theme.fontHandle, glyph);
   m_w[PI_HANDLE].SetColors(m_theme.text, m_theme.bg, m_theme.border);
   m_w[PI_HANDLE].SetTooltip("Drag to move the panel");

   m_w[PI_TITLE].SetText("Risk");
   m_w[PI_TITLE].SetFont(m_theme.fontTitle, title);
   m_w[PI_TITLE].SetTextColor(m_theme.text);
   m_w[PI_TITLE].SetTooltip("");
   m_w[PI_TITLE2].SetText("Desk");
   m_w[PI_TITLE2].SetFont(m_theme.fontTitle, title);
   m_w[PI_TITLE2].SetTextColor(m_theme.titleAccent);
   m_w[PI_TITLE2].SetTooltip("");
   int h = 0;
   if(!CLayout::TextSize(m_theme.fontTitle, title, "Risk", m_title1W, h))
      m_title1W = m_layout.Px(30);

   m_w[PI_HIDE].SetFont(m_theme.fontBody, body);
   m_w[PI_HIDE].SetColors(m_theme.text, m_theme.bg, m_theme.buttonBorder);

   EPanelItem captions[] = {PI_RISK_CAP, PI_LOTS_CAP};
   for(int i = 0; i < ArraySize(captions); i++)
     {
      m_w[captions[i]].SetFont(m_theme.fontBody, body);
      m_w[captions[i]].SetTextColor(m_theme.text);
      m_w[captions[i]].SetTooltip("");
     }
   m_w[PI_RISK_CAP].SetText("Risk %");
   m_w[PI_LOTS_CAP].SetText("Lots");
   m_w[PI_PINFO_CAP].SetText("Pending Info");
   m_w[PI_PINFO_CAP].SetFont(m_theme.fontBody, body);
   m_w[PI_PINFO_CAP].SetTextColor(m_theme.pendingInfo);
   m_w[PI_PINFO_CAP].SetTooltip("");

   EPanelItem edits[] = {PI_RISK, PI_LOTS, PI_PINFO};
   for(int i = 0; i < ArraySize(edits); i++)
     {
      m_w[edits[i]].SetFont(m_theme.fontBody, body);
      m_w[edits[i]].SetAlign(ALIGN_LEFT);
     }

   m_w[PI_SPREAD].SetFont(m_theme.fontBody, body);
   for(int i = PI_STATUS1; i <= PI_STATUS3; i++)
      m_w[i].SetFont(m_theme.fontBody, m_layout.FontStatus());

   m_w[PI_SHOT].SetText(m_theme.glyphCamera);
   m_w[PI_SHOT].SetFont(m_theme.fontCamera, glyph);
   m_w[PI_SHOT].SetColors(m_theme.text, m_theme.bg, m_theme.border);
  }

//+------------------------------------------------------------------+
void CPanel::PlaceLabel(const EPanelItem i, const int x, const int y, const int anchor)
  {
   m_w[i].SetAnchor(anchor);
   m_w[i].Move(x, y);
  }

//+------------------------------------------------------------------+
//| Positions and sizes from the layout, offset by the shown anchor. |
//+------------------------------------------------------------------+
void CPanel::ApplyGeometry()
  {
   SRect r;
   for(int i = 0; i < PI_COUNT; i++)
     {
      EPanelItem item = (EPanelItem)i;
      m_layout.Rect(item, r);
      int ax = m_x + r.x;
      int ay = m_y + r.y;
      switch(item)
        {
         case PI_BG:
            m_w[i].Move(ax, ay);
            m_w[i].Resize(r.w, m_layout.BgHeight(m_collapsed));
            break;
         case PI_TITLE:
         case PI_RISK_CAP:
         case PI_LOTS_CAP:
         case PI_SPREAD:
         case PI_STATUS1:
         case PI_STATUS2:
         case PI_STATUS3:
            PlaceLabel(item, ax, ay + r.h / 2, ANCHOR_LEFT);
            break;
         case PI_TITLE2:
            PlaceLabel(item, ax + m_title1W, ay + r.h / 2, ANCHOR_LEFT);
            break;
         case PI_PINFO_CAP:
            PlaceLabel(item, ax + r.w / 2, ay + r.h / 2, ANCHOR_CENTER);
            break;
         default:
            m_w[i].Move(ax, ay);
            m_w[i].Resize(r.w, r.h);
            break;
        }
     }
  }

bool CPanel::ItemShown(const EPanelItem i) const
  {
   if(!m_collapsed)
      return true;
   return i == PI_BG || i == PI_HANDLE || i == PI_TITLE || i == PI_TITLE2 || i == PI_HIDE;
  }

void CPanel::ApplyVisibility()
  {
   for(int i = 0; i < PI_COUNT; i++)
      m_w[i].SetVisible(ItemShown((EPanelItem)i));
   m_w[PI_HIDE].SetText(m_collapsed ? "+" : ShortToString((ushort)0x2013));
   m_w[PI_HIDE].SetTooltip(m_collapsed ? "Show the panel" : "Hide the panel (lines stay on the chart)");
  }

//+------------------------------------------------------------------+
//| Shrink the font until the text fits the widget (05 section 1:    |
//| "adjust if text overflows").                                     |
//+------------------------------------------------------------------+
void CPanel::FitText(const EPanelItem i, const string font, const int size, const string text)
  {
   if(m_refit || text != m_w[i].Text() || m_w[i].FontSize() <= 0)
     {
      SRect r;
      m_layout.Rect(i, r);
      int fitted = CLayout::FitFont(font, size, text, r.w - 2 * m_layout.TextPad(), r.h);
      m_w[i].SetFont(font, fitted);
     }
   m_w[i].SetText(text);
  }

int CPanel::StatusWidth() const
  {
   SRect r;
   m_layout.Rect(PI_STATUS1, r);
   return r.w;
  }

//+------------------------------------------------------------------+
//| 05 section 3 / F-01 AC4 / T-37: the whole panel stays in view:   |
//| x in [0, chartW - panelW], y in [0, chartH - shown height]       |
//| (stricter than 05's "chartH - 40", which let the panel hang off  |
//| the bottom; ADR-021). A panel larger than the chart keeps its    |
//| top-left corner in view. Unknown chart size (0): no clamp.       |
//| The terminal's One-Click Trading panel is drawn above every      |
//| object in the top-left corner: a panel there goes below it when  |
//| it fits, else to its right (ADR-021).                            |
//+------------------------------------------------------------------+
void CPanel::ClampShown()
  {
   int w = m_layout.Width();
   int h = m_layout.ShownHeight(m_collapsed);
   m_x = m_wantX;
   m_y = m_wantY;
   if(m_chartW > 0)
      m_x = MathMin(m_x, m_chartW - w);
   if(m_chartH > 0)
      m_y = MathMin(m_y, m_chartH - h);
   m_x = MathMax(0, m_x);
   m_y = MathMax(0, m_y);
   if(m_resW > 0 && m_resH > 0 && m_x < m_resW && m_y < m_resH)
     {
      if(m_chartH <= 0 || m_resH + h <= m_chartH)
         m_y = m_resH;
      else
         if(m_chartW <= 0 || m_resW + w <= m_chartW)
            m_x = m_resW;
     }
  }

void CPanel::SetReserved(const int w, const int h)
  {
   if(w == m_resW && h == m_resH)
      return;
   m_resW = MathMax(0, w);
   m_resH = MathMax(0, h);
   if(!m_built)
      return;
   ClampShown();
   ApplyGeometry();
  }

void CPanel::SetChartSize(const int w, const int h)
  {
   m_chartW = w;
   m_chartH = h;
   if(!m_built)
      return;
   ClampShown();
   ApplyGeometry();
  }

void CPanel::SetWanted(const int x, const int y)
  {
   m_wantX = MathMax(0, x);
   m_wantY = MathMax(0, y);
   ClampShown();
   if(m_built)
      ApplyGeometry();
  }

void CPanel::SetCollapsed(const bool collapsed)
  {
   m_collapsed = collapsed;
   if(!m_built)
      return;
   ClampShown();
   ApplyGeometry();
   ApplyVisibility();
  }

//+------------------------------------------------------------------+
//| Everything that changes with the model. The widgets write only   |
//| what changed.                                                    |
//+------------------------------------------------------------------+
void CPanel::Render(const SPanelModel &m)
  {
   if(!m_built)
      return;
   int body = m_layout.FontBody();

   m_w[PI_RISK].SetText(m.riskText);
   m_w[PI_RISK].SetColors(m_theme.text, m_theme.fieldBg, m_theme.fieldBorder);
   m_w[PI_RISK].SetTooltip(m.riskTip);
   m_w[PI_RISK_CAP].SetTooltip(m.riskTip);

   m_w[PI_LOTS].SetText(m.lotsText);
   m_w[PI_LOTS].SetColors(m.lotsWarn ? m_theme.statusError : m_theme.text, m_theme.fieldBg, m_theme.fieldBorder);
   m_w[PI_LOTS].SetTooltip(m.lotsTip);
   m_w[PI_LOTS_CAP].SetTooltip(m.lotsTip);

   for(int b = 0; b < PB_COUNT; b++)
     {
      EPanelButton pb = (EPanelButton)b;
      EPanelItem item = RdButtonItem(pb);
      color back = clrNONE;
      color fore = clrNONE;
      m_theme.ButtonColors(pb, m.buttonLook[b], back, fore);
      if(pb == PB_SHOT)
        {
         m_w[item].SetTooltip(m.buttonTip[b]);
         if(m.buttonLook[b] == LOOK_NORMAL)
            m_w[item].SetColors(m_theme.text, m_theme.bg, m_theme.border);
         else
            m_w[item].SetColors(fore, back, m_theme.border);
         continue;
        }
      string text = (m.buttonLook[b] == LOOK_WORKING) ? ShortToString((ushort)0x2026) : m.buttonText[b];
      FitText(item, m_theme.fontBody, body, text);
      m_w[item].SetColors(fore, back, m_theme.buttonBorder);
      m_w[item].SetTooltip(m.buttonTip[b]);
     }

   m_w[PI_PINFO].SetText(m.pinfoText);
   m_w[PI_PINFO].SetColors(m.pinfoWarn ? m_theme.statusWarn : m_theme.text, m_theme.fieldBg, m_theme.fieldBorder);
   m_w[PI_PINFO].SetTooltip(m.pinfoTip);
   m_w[PI_PINFO_CAP].SetTooltip(m.pinfoTip);

   m_w[PI_SPREAD].SetText(m.spreadText);
   m_w[PI_SPREAD].SetTextColor(m.spreadWarn ? m_theme.statusWarn : m_theme.spread);
   m_w[PI_SPREAD].SetTooltip(m.spreadTip);

   color sc = m_theme.SeverityColor(m.statusSev);
   for(int i = 0; i < RD_STATUS_LINES; i++)
     {
      EPanelItem item = (EPanelItem)(PI_STATUS1 + i);
      m_w[item].SetText(m.statusLine[i]);
      m_w[item].SetTextColor(sc);
      m_w[item].SetTooltip(m.statusTip);
     }
   m_refit = false;
  }

//+------------------------------------------------------------------+
//| CHARTEVENT_MOUSE_MOVE (x, y in chart pixels; 'buttons' bit 0 =   |
//| left). A drag starts when the left button goes down over the     |
//| handle; chart scrolling is off while dragging and restored on    |
//| release. True while the event belongs to a drag.                 |
//+------------------------------------------------------------------+
bool CPanel::OnMouseMove(const int x, const int y, const int buttons)
  {
   bool down = (buttons & 1) != 0;
   if(m_dragging)
     {
      if(down)
        {
         SetWanted(x - m_grabX, y - m_grabY);
         // remember where it is shown, so a drop at an edge stays there
         m_wantX = m_x;
         m_wantY = m_y;
        }
      else
        {
         m_dragging = false;
         m_dropped = true;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, m_scrollWas);
         ReleaseHandle();
        }
      m_mouseDown = down;
      return true;
     }
   if(down && !m_mouseDown && m_built)
     {
      SRect r;
      m_layout.Rect(PI_HANDLE, r);
      r.x += m_x;
      r.y += m_y;
      if(r.Contains(x, y))
        {
         m_dragging = true;
         m_grabX = x - m_x;
         m_grabY = y - m_y;
         m_scrollWas = ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
        }
     }
   m_mouseDown = down;
   return m_dragging;
  }

// True once after a drag ended (App saves the position, debounced).
bool CPanel::TakeDrop()
  {
   if(!m_dropped)
      return false;
   m_dropped = false;
   return true;
  }

void CPanel::CancelDrag()
  {
   if(m_dragging)
     {
      m_dragging = false;
      ChartSetInteger(0, CHART_MOUSE_SCROLL, m_scrollWas);
     }
   m_mouseDown = false;
  }

#include "PanelObjects.mqh"

#endif // RD_UI_PANEL_MQH
