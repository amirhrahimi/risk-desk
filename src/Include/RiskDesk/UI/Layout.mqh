//+------------------------------------------------------------------+
//| RiskDesk - UI/Layout.mqh                                         |
//| Layer   : UI                                                     |
//| Purpose : panel geometry (05-ui-spec section 1).                 |
//|           - pixel scale = scale x DPI / 96; with auto-fit (F-34) |
//|             scale = min(Shape Size Scale, largest scale at which |
//|             the whole panel, handle to camera, fits the chart    |
//|             minus 10 px)                                         |
//|           - every rectangle comes from one running y-cursor in   |
//|             unscaled pixels; an edge is Px(cursor), so rounding  |
//|             never accumulates                                    |
//|           - font sizes are multiplied by the scale only (the     |
//|             terminal applies the DPI to fonts), minimum 6 pt     |
//|           - text measuring (TextSetFont / TextGetSize) to shrink |
//|             a font until its text fits its widget                |
//|           Rectangles are relative to the panel anchor: the top-  |
//|           left corner of the move-handle row.                    |
//+------------------------------------------------------------------+
#ifndef RD_UI_LAYOUT_MQH
#define RD_UI_LAYOUT_MQH

#include "..\Domain\Types.mqh"
#include "Theme.mqh"

// Every chart object of the panel, in creation (= drawing) order.
enum EPanelItem
  {
   PI_BG = 0,
   PI_HANDLE,
   PI_TITLE,
   PI_TITLE2,
   PI_HIDE,
   PI_RISK_CAP,
   PI_RISK,
   PI_LOTS_CAP,
   PI_LOTS,
   PI_ADDLINE,
   PI_DELLINE,
   PI_BUY,
   PI_SELL,
   PI_ADDPEND,
   PI_SETPEND,
   PI_PINFO_CAP,
   PI_PINFO,
   PI_DELPEND,
   PI_RISKFREE,
   PI_HALF,
   PI_CHARTCLOSE,
   PI_FULLCLOSE,
   PI_SPREAD,
   PI_STATUS1,
   PI_STATUS2,
   PI_STATUS3,
   PI_SHOT,
   PI_COUNT
  };

#define RD_STATUS_LINES     3

//--- geometry at scale 1.0 and 96 DPI (05 section 1)
#define RD_LY_WIDTH         160
#define RD_LY_PAD           8
#define RD_LY_LABELCOL      48
#define RD_LY_FIELD_H       22
#define RD_LY_BUTTON_H      24
#define RD_LY_GAP           5
#define RD_LY_HANDLE_W      36
#define RD_LY_HANDLE_H      16
#define RD_LY_HANDLE_GAP    2
#define RD_LY_TITLE_TOP     6
#define RD_LY_TITLE_H       20
#define RD_LY_HIDE_SIZE     16
#define RD_LY_CAPTION_H     14
#define RD_LY_CAPTION_GAP   3
#define RD_LY_STATUS_LINE   13
#define RD_LY_BOTTOM_PAD    6
#define RD_LY_SHOT_GAP      4
#define RD_LY_SHOT_W        30
#define RD_LY_SHOT_H        20
#define RD_LY_TEXT_PAD      4      // horizontal room kept free inside a widget for its text
#define RD_LY_FIT_MARGIN    10     // F-34: chart size minus 10 px
#define RD_LY_MIN_SCALE     0.40
#define RD_LY_MIN_FONT      6
// The terminal's One-Click Trading panel in the chart's top-left corner, at
// 96 DPI (it scales with the DPI, not with Shape Size Scale). Measured in P3
// on window captures of MT4 build 1492 and MT5 build 6311 at 125 %: it ends at
// x 254, y 99 (203 x 79 at 96 DPI) on both; plus a margin (ADR-021).
#define RD_LY_ONECLICK_W    215
#define RD_LY_ONECLICK_H    90

struct SRect
  {
   int               x;
   int               y;
   int               w;
   int               h;

   void              Set(const int ax, const int ay, const int aw, const int ah) { x = ax; y = ay; w = aw; h = ah; }
   bool              Contains(const int px, const int py) const { return px >= x && px < x + w && py >= y && py < y + h; }
  };

EPanelItem RdButtonItem(const EPanelButton b)
  {
   switch(b)
     {
      case PB_ADDLINE:
         return PI_ADDLINE;
      case PB_DELLINE:
         return PI_DELLINE;
      case PB_BUY:
         return PI_BUY;
      case PB_SELL:
         return PI_SELL;
      case PB_ADDPEND:
         return PI_ADDPEND;
      case PB_SETPEND:
         return PI_SETPEND;
      case PB_DELPEND:
         return PI_DELPEND;
      case PB_RISKFREE:
         return PI_RISKFREE;
      case PB_HALF:
         return PI_HALF;
      case PB_CHARTCLOSE:
         return PI_CHARTCLOSE;
      case PB_FULLCLOSE:
         return PI_FULLCLOSE;
      default:
         return PI_SHOT;
     }
  }

class CLayout
  {
private:
   double            m_userScale;     // Shape Size Scale
   bool              m_autoFit;
   double            m_dpiFactor;     // DPI / 96
   int               m_fontSize;      // body size before scaling
   string            m_fontBody;      // for the row minimums (text never taller than its row)
   string            m_fontTitle;
   double            m_scale;         // effective scale (after auto-fit)
   SRect             m_r[PI_COUNT];
   int               m_height;        // handle to camera, px
   int               m_collapsedBgH;  // BG height when collapsed, px
   //--- y-cursor state of one ComputeAt pass
   double            m_k;             // pixels per unscaled pixel in this pass
   double            m_u;             // unscaled cursor
   int               m_extra;         // pixels added by rows grown to fit their text

   int               P(const double v) const { return (int)MathRound(v * m_scale * m_dpiFactor); }
   int               Pk(const double v) const { return (int)MathRound(v * m_k); }
   int               Row(const double h, const int minPx, int &top);
   void              Gap(const double g) { m_u += g; }
   int               FontAt(const int points, const double scale) const;
   int               ComputeAt(const double scale, const bool store);

public:
                     CLayout();
   void              Configure(const double userScale, const bool autoFit, const int dpi, const int fontSize,
                               const string fontBody, const string fontTitle);
   bool              Fit(const int chartW, const int chartH);
   void              Compute() { m_height = ComputeAt(m_scale, true); }

   double            Scale() const { return m_scale; }
   double            UserScale() const { return m_userScale; }
   double            PixelScale() const { return m_scale * m_dpiFactor; }
   int               Px(const double v) const { return P(v); }
   // Terminal UI sizes: DPI only, not the panel scale.
   int               TerminalPx(const double v) const { return (int)MathRound(v * m_dpiFactor); }
   void              Rect(const EPanelItem item, SRect &r) const { r = m_r[item]; }
   int               Width() const { return P(RD_LY_WIDTH); }
   int               Height() const { return m_height; }
   int               BgHeight(const bool collapsed) const { return collapsed ? m_collapsedBgH : m_r[PI_BG].h; }
   // Handle to camera when expanded; handle to the title row's bottom when collapsed.
   int               ShownHeight(const bool collapsed) const;
   int               HeightAt(const double scale) { return ComputeAt(scale, false); }
   int               WidthAt(const double scale) const;

   int               FontBody() const { return FontAt(m_fontSize, m_scale); }
   int               FontTitle() const { return FontAt(m_fontSize + 3, m_scale); }
   int               FontStatus() const { return FontAt(m_fontSize - 1, m_scale); }
   int               FontGlyph() const { return FontAt(m_fontSize + 2, m_scale); }
   int               TextPad() const { return MathMax(1, P(RD_LY_TEXT_PAD)); }

   static bool       TextSize(const string font, const int points, const string text, int &w, int &h);
   static int        LineHeight(const string font, const int points);
   static int        FitFont(const string font, const int points, const string text, const int maxW, const int maxH);
  };

//+------------------------------------------------------------------+
CLayout::CLayout()
  {
   m_userScale = 1.0;
   m_autoFit = false;
   m_dpiFactor = 1.0;
   m_fontSize = 8;
   m_fontBody = "Segoe UI";
   m_fontTitle = "Segoe UI Semibold";
   m_scale = 1.0;
   m_height = 0;
   m_collapsedBgH = 0;
   m_k = 1.0;
   m_u = 0.0;
   m_extra = 0;
  }

void CLayout::Configure(const double userScale, const bool autoFit, const int dpi, const int fontSize,
                        const string fontBody, const string fontTitle)
  {
   m_userScale = userScale;
   m_autoFit = autoFit;
   m_dpiFactor = (dpi > 0 ? dpi : 96) / 96.0;
   m_fontSize = fontSize;
   m_fontBody = fontBody;
   m_fontTitle = fontTitle;
   m_scale = userScale;
   Compute();
  }

int CLayout::FontAt(const int points, const double scale) const
  {
   return MathMax(RD_LY_MIN_FONT, (int)MathRound(points * scale));
  }

//+------------------------------------------------------------------+
//| One row of unscaled height h at the cursor: its top and height   |
//| in pixels. Edges are Px(cursor), so rounding never accumulates;  |
//| a row is never shorter than minPx (its text), and what it grows  |
//| by moves every following row down.                               |
//+------------------------------------------------------------------+
int CLayout::Row(const double h, const int minPx, int &top)
  {
   top = Pk(m_u) + m_extra;
   int natural = Pk(m_u + h) - Pk(m_u);
   int actual = MathMax(MathMax(1, natural), minPx);
   m_extra += actual - natural;
   m_u += h;
   return actual;
  }

//+------------------------------------------------------------------+
//| The y-cursor (05 section 1 diagram, top to bottom) at 'scale'.   |
//| Returns the height handle to camera; store = keep the rectangles.|
//| Rows are at least as tall as their font's line (the fonts stop   |
//| at 6 pt while the geometry keeps shrinking), and the caption     |
//| column is at least as wide as "Risk %" (05 section 1: adjust if  |
//| text overflows; ADR-021).                                        |
//+------------------------------------------------------------------+
int CLayout::ComputeAt(const double scale, const bool store)
  {
   m_k = scale * m_dpiFactor;
   m_u = 0.0;
   m_extra = 0;
   int bodyPt = FontAt(m_fontSize, scale);
   int lhBody = LineHeight(m_fontBody, bodyPt);
   int lhTitle = LineHeight(m_fontTitle, FontAt(m_fontSize + 3, scale));
   int lhStatus = LineHeight(m_fontBody, FontAt(m_fontSize - 1, scale));
   int lhGlyph = LineHeight(m_fontBody, FontAt(m_fontSize + 2, scale));

   int width = Pk(RD_LY_WIDTH);
   int pad = Pk(RD_LY_PAD);
   int inner = width - 2 * pad;
   int capW = 0;
   int capH = 0;
   TextSize(m_fontBody, bodyPt, "Risk %", capW, capH);
   int labelCol = MathMin(inner / 2, MathMax(Pk(RD_LY_LABELCOL), capW + Pk(RD_LY_TEXT_PAD)));
   SRect r[PI_COUNT];
   int top = 0;
   int h = 0;

   h = Row(RD_LY_HANDLE_H, lhGlyph, top);
   int handleW = MathMax(Pk(RD_LY_HANDLE_W), h * 2);
   r[PI_HANDLE].Set((width - handleW) / 2, top, handleW, h);
   Gap(RD_LY_HANDLE_GAP);
   int bgTop = Pk(m_u) + m_extra;

   Gap(RD_LY_TITLE_TOP);
   h = Row(RD_LY_TITLE_H, lhTitle, top);
   int hide = MathMin(h, MathMax(Pk(RD_LY_HIDE_SIZE), lhBody));
   r[PI_HIDE].Set(width - pad - hide, top + (h - hide) / 2, hide, hide);
   r[PI_TITLE].Set(pad, top, inner - hide - Pk(4), h);
   r[PI_TITLE2].Set(pad, top, inner - hide - Pk(4), h);   // x set by the panel after measuring "Risk"
   Gap(RD_LY_TITLE_TOP);
   int collapsedBg = Pk(m_u) + m_extra - bgTop;
   m_u -= RD_LY_TITLE_TOP;
   Gap(RD_LY_GAP);

   h = Row(RD_LY_FIELD_H, lhBody + 2, top);
   r[PI_RISK_CAP].Set(pad, top, labelCol, h);
   r[PI_RISK].Set(pad + labelCol, top, inner - labelCol, h);
   Gap(RD_LY_GAP);
   h = Row(RD_LY_FIELD_H, lhBody + 2, top);
   r[PI_LOTS_CAP].Set(pad, top, labelCol, h);
   r[PI_LOTS].Set(pad + labelCol, top, inner - labelCol, h);
   Gap(RD_LY_GAP);

   EPanelItem upper[] = {PI_ADDLINE, PI_DELLINE, PI_BUY, PI_SELL, PI_ADDPEND, PI_SETPEND};
   for(int i = 0; i < ArraySize(upper); i++)
     {
      h = Row(RD_LY_BUTTON_H, lhBody + 2, top);
      r[upper[i]].Set(pad, top, inner, h);
      Gap(RD_LY_GAP);
     }

   h = Row(RD_LY_CAPTION_H, lhBody, top);
   r[PI_PINFO_CAP].Set(pad, top, inner, h);
   Gap(RD_LY_CAPTION_GAP);
   h = Row(RD_LY_FIELD_H, lhBody + 2, top);
   r[PI_PINFO].Set(pad, top, inner, h);
   Gap(RD_LY_GAP);

   EPanelItem lower[] = {PI_DELPEND, PI_RISKFREE, PI_HALF, PI_CHARTCLOSE, PI_FULLCLOSE};
   for(int i = 0; i < ArraySize(lower); i++)
     {
      h = Row(RD_LY_BUTTON_H, lhBody + 2, top);
      r[lower[i]].Set(pad, top, inner, h);
      Gap(RD_LY_GAP);
     }

   h = Row(RD_LY_CAPTION_H, lhBody, top);
   r[PI_SPREAD].Set(pad, top, inner, h);
   Gap(RD_LY_CAPTION_GAP);
   for(int i = 0; i < RD_STATUS_LINES; i++)
     {
      h = Row(RD_LY_STATUS_LINE, lhStatus, top);
      r[PI_STATUS1 + i].Set(pad, top, inner, h);
     }
   Gap(RD_LY_BOTTOM_PAD);
   int bgBottom = Pk(m_u) + m_extra;
   r[PI_BG].Set(0, bgTop, width, bgBottom - bgTop);

   Gap(RD_LY_SHOT_GAP);
   h = Row(RD_LY_SHOT_H, lhGlyph, top);
   int shotW = MathMax(Pk(RD_LY_SHOT_W), h + h / 2);
   r[PI_SHOT].Set((width - shotW) / 2, top, shotW, h);
   int total = top + h;

   if(store)
     {
      for(int i = 0; i < PI_COUNT; i++)
         m_r[i] = r[i];
      m_collapsedBgH = collapsedBg;
     }
   return total;
  }

int CLayout::ShownHeight(const bool collapsed) const
  {
   if(!collapsed)
      return m_height;
   return m_r[PI_BG].y + m_collapsedBgH;
  }

int CLayout::WidthAt(const double scale) const
  {
   return (int)MathRound(RD_LY_WIDTH * scale * m_dpiFactor);
  }

//+------------------------------------------------------------------+
//| F-34: effective scale for this chart size: the largest on a 0.01 |
//| grid whose panel fits, never above the user's scale, never below |
//| 0.40 (then the panel may not fit: the clamp keeps its top-left   |
//| corner in view). Unknown chart size (0, e.g. non-visual tester)  |
//| -> user's scale. Starts at the linear estimate, steps up while   |
//| the next step still fits, then down until it fits (the height    |
//| grows with the scale, so this ends at the largest fitting step). |
//| True if the scale changed.                                       |
//+------------------------------------------------------------------+
bool CLayout::Fit(const int chartW, const int chartH)
  {
   double s = m_userScale;
   if(m_autoFit && chartW > 0 && chartH > 0)
     {
      int availH = chartH - RD_LY_FIT_MARGIN;
      int availW = chartW - RD_LY_FIT_MARGIN;
      double perScale = MathMax(1.0, (double)ComputeAt(1.0, false));   // panel height at scale 1
      double est = MathMin(availH / perScale, availW / (RD_LY_WIDTH * m_dpiFactor));
      est = MathFloor(est * 100.0) / 100.0;
      if(est < s)
        {
         s = MathMax(RD_LY_MIN_SCALE, est);
         while(s + 0.01 <= m_userScale + 1e-9 && ComputeAt(s + 0.01, false) <= availH && WidthAt(s + 0.01) <= availW)
            s += 0.01;
        }
      while(s > RD_LY_MIN_SCALE + 1e-9 && (ComputeAt(s, false) > availH || WidthAt(s) > availW))
         s -= 0.01;
      if(s < RD_LY_MIN_SCALE)
         s = RD_LY_MIN_SCALE;
     }
   s = NormalizeDouble(s, 2);
   bool changed = MathAbs(s - m_scale) > 1e-9;
   m_scale = s;
   Compute();
   return changed;
  }

//+------------------------------------------------------------------+
//| Size in pixels of 'text' as an OBJ_LABEL of 'points' would draw  |
//| it (negative tenths of a point, as the documentation says).      |
//+------------------------------------------------------------------+
bool CLayout::TextSize(const string font, const int points, const string text, int &w, int &h)
  {
   w = 0;
   h = 0;
   if(!TextSetFont(font, -points * 10))
      return false;
   uint uw = 0;
   uint uh = 0;
   if(!TextGetSize(text, uw, uh))
      return false;
   w = (int)uw;
   h = (int)uh;
   return true;
  }

// Height of one line of text (ascent + descent) in this font and size.
int CLayout::LineHeight(const string font, const int points)
  {
   int w = 0;
   int h = 0;
   if(!TextSize(font, points, "Ag", w, h) || h <= 0)
      return (int)MathCeil(points * 1.5);   // rough, only if measuring fails
   return h;
  }

//+------------------------------------------------------------------+
//| Largest size <= points (>= 6) at which 'text' fits maxW x maxH.  |
//+------------------------------------------------------------------+
int CLayout::FitFont(const string font, const int points, const string text, const int maxW, const int maxH)
  {
   int size = points;
   while(size > RD_LY_MIN_FONT)
     {
      int w = 0;
      int h = 0;
      if(!TextSize(font, size, text, w, h))
         break;
      if(w <= maxW && h <= maxH)
         break;
      size--;
     }
   return size;
  }

#endif // RD_UI_LAYOUT_MQH
