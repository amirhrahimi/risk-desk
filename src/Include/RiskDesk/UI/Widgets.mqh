//+------------------------------------------------------------------+
//| RiskDesk - UI/Widgets.mqh                                        |
//| Layer   : UI                                                     |
//| Purpose : thin wrappers over the standard chart objects the      |
//|           panel is made of (ADR-007): CRdRect, CRdLabel,         |
//|           CRdButton, CRdEdit. Each keeps the last value it wrote |
//|           for every property and calls ObjectSet* only when a    |
//|           value changed (05 section 3 "Redraw"); every write     |
//|           marks the shared CRdRedraw, which App flushes with one |
//|           ChartRedraw() per refresh cycle.                       |
//|           Panel objects: CORNER_LEFT_UPPER, OBJPROP_HIDDEN=true, |
//|           not selectable, OBJPROP_BACK=false, high OBJPROP_ZORDER|
//|           (CLAUDE.md section 6).                                 |
//+------------------------------------------------------------------+
#ifndef RD_UI_WIDGETS_MQH
#define RD_UI_WIDGETS_MQH

#include "..\Domain\Types.mqh"
#include "..\Platform\Compat.mqh"

#define RD_ZORDER_PANEL   1000   // background; labels/buttons/edits above it
#define RD_TOOLTIP_NONE   "\n"   // MetaTrader shows no tooltip for "\n" (otherwise it shows the object name)

//+------------------------------------------------------------------+
//| One ChartRedraw() per refresh cycle, only when something changed.|
//+------------------------------------------------------------------+
class CRdRedraw
  {
private:
   bool              m_marked;

public:
                     CRdRedraw() { m_marked = false; }
   void              Mark() { m_marked = true; }
   bool              Marked() const { return m_marked; }
   bool              Flush()
     {
      if(!m_marked)
         return false;
      m_marked = false;
      ChartRedraw(0);
      return true;
     }
  };

//+------------------------------------------------------------------+
class CRdWidget
  {
protected:
   string            m_name;
   ENUM_OBJECT       m_type;
   CRdRedraw        *m_redraw;
   long              m_zorder;

   //--- last written values and whether they are known
   bool              m_okPos, m_okSize, m_okText, m_okFg, m_okBg, m_okBorder, m_okFont, m_okTip, m_okVis;
   bool              m_okAlign, m_okAnchor, m_okReadOnly;
   int               m_x, m_y, m_w, m_h;
   string            m_text, m_tip, m_font;
   int               m_fontSize;
   color             m_fg, m_bg, m_border;
   bool              m_visible;
   int               m_align;
   int               m_anchor;
   bool              m_readOnly;

   void              Wrote() { if(m_redraw != NULL) m_redraw.Mark(); }
   bool              HasSize() const { return m_type != OBJ_LABEL; }

public:
                     CRdWidget();
   //--- true when the object had to be created (it did not exist)
   bool              Create(const string name, const ENUM_OBJECT type, CRdRedraw *redraw, const long zorder);
   bool              Exists() const { return m_name != "" && ObjectFind(0, m_name) >= 0; }
   void              Invalidate();
   void              ForgetText() { m_okText = false; }
   void              Destroy();
   string            Name() const { return m_name; }

   void              Move(const int x, const int y);
   void              Resize(const int w, const int h);
   void              SetText(const string text);
   void              SetFont(const string font, const int size);
   void              SetColors(const color fg, const color bg, const color border);
   void              SetTextColor(const color fg);
   void              SetTooltip(const string tip);
   void              SetVisible(const bool visible);
   void              SetAlign(const int align);
   void              SetAnchor(const int anchor);
   void              SetReadOnly(const bool readOnly);

   string            Text() const { return m_text; }
   int               FontSize() const { return m_fontSize; }
   bool              Visible() const { return m_visible || !m_okVis; }
   string            ReadText() const { return ObjectGetString(0, m_name, OBJPROP_TEXT); }
   bool              Pressed() const { return ObjectGetInteger(0, m_name, OBJPROP_STATE) != 0; }
   void              Release();
  };

//+------------------------------------------------------------------+
CRdWidget::CRdWidget()
  {
   m_name = "";
   m_type = OBJ_LABEL;
   m_redraw = NULL;
   m_zorder = RD_ZORDER_PANEL;
   Invalidate();
  }

void CRdWidget::Invalidate()
  {
   m_okPos = false;
   m_okSize = false;
   m_okText = false;
   m_okFg = false;
   m_okBg = false;
   m_okBorder = false;
   m_okFont = false;
   m_okTip = false;
   m_okVis = false;
   m_okAlign = false;
   m_okAnchor = false;
   m_okReadOnly = false;
   m_x = 0;
   m_y = 0;
   m_w = 0;
   m_h = 0;
   m_text = "";
   m_tip = "";
   m_font = "";
   m_fontSize = 0;
   m_fg = clrNONE;
   m_bg = clrNONE;
   m_border = clrNONE;
   m_visible = true;
   m_align = 0;
   m_anchor = 0;
   m_readOnly = false;
  }

//+------------------------------------------------------------------+
//| Create the object, or adopt it when it already exists with the   |
//| same type (timeframe change keeps chart objects, F-23). A wrong  |
//| type is deleted and created again. The cache is cleared, so the  |
//| next setters write every property once.                          |
//+------------------------------------------------------------------+
bool CRdWidget::Create(const string name, const ENUM_OBJECT type, CRdRedraw *redraw, const long zorder)
  {
   m_name = name;
   m_type = type;
   m_redraw = redraw;
   m_zorder = zorder;
   Invalidate();
   bool created = false;
   if(ObjectFind(0, name) >= 0 && (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) != type)
      ObjectDelete(0, name);
   if(ObjectFind(0, name) < 0)
     {
      if(!ObjectCreate(0, name, type, 0, 0, 0))
         return false;
      created = true;
     }
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, zorder);
   if(type == OBJ_RECTANGLE_LABEL)
     {
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
     }
   if(type == OBJ_BUTTON)
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
   Wrote();
   return created;
  }

void CRdWidget::Destroy()
  {
   if(m_name != "" && ObjectFind(0, m_name) >= 0)
     {
      ObjectDelete(0, m_name);
      Wrote();
     }
   Invalidate();
  }

//+------------------------------------------------------------------+
void CRdWidget::Move(const int x, const int y)
  {
   if(m_okPos && x == m_x && y == m_y)
      return;
   ObjectSetInteger(0, m_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, m_name, OBJPROP_YDISTANCE, y);
   m_x = x;
   m_y = y;
   m_okPos = true;
   Wrote();
  }

void CRdWidget::Resize(const int w, const int h)
  {
   if(!HasSize() || (m_okSize && w == m_w && h == m_h))
      return;
   ObjectSetInteger(0, m_name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, m_name, OBJPROP_YSIZE, h);
   m_w = w;
   m_h = h;
   m_okSize = true;
   Wrote();
  }

//+------------------------------------------------------------------+
//| An empty label or button text is written as one space: MT4 shows |
//| the words "Label" / "Button" for an empty text.                  |
//+------------------------------------------------------------------+
void CRdWidget::SetText(const string text)
  {
   if(m_okText && text == m_text)
      return;
   string shown = text;
   if(shown == "" && (m_type == OBJ_LABEL || m_type == OBJ_BUTTON))
      shown = " ";
   ObjectSetString(0, m_name, OBJPROP_TEXT, shown);
   m_text = text;
   m_okText = true;
   Wrote();
  }

void CRdWidget::SetFont(const string font, const int size)
  {
   if(m_okFont && font == m_font && size == m_fontSize)
      return;
   ObjectSetString(0, m_name, OBJPROP_FONT, font);
   ObjectSetInteger(0, m_name, OBJPROP_FONTSIZE, size);
   m_font = font;
   m_fontSize = size;
   m_okFont = true;
   Wrote();
  }

//+------------------------------------------------------------------+
//| fg = text (label/button/edit) or the flat border (rectangle);    |
//| bg = background; border = button/edit border. clrNONE = skip.    |
//+------------------------------------------------------------------+
void CRdWidget::SetColors(const color fg, const color bg, const color border)
  {
   if(m_type == OBJ_RECTANGLE_LABEL)
     {
      if(border != clrNONE && !(m_okFg && border == m_fg))
        {
         ObjectSetInteger(0, m_name, OBJPROP_COLOR, border);
         m_fg = border;
         m_okFg = true;
         Wrote();
        }
     }
   else
      SetTextColor(fg);
   if(m_type != OBJ_LABEL && bg != clrNONE && !(m_okBg && bg == m_bg))
     {
      ObjectSetInteger(0, m_name, OBJPROP_BGCOLOR, bg);
      m_bg = bg;
      m_okBg = true;
      Wrote();
     }
   if((m_type == OBJ_BUTTON || m_type == OBJ_EDIT) && border != clrNONE && !(m_okBorder && border == m_border))
     {
      ObjectSetInteger(0, m_name, OBJPROP_BORDER_COLOR, border);
      m_border = border;
      m_okBorder = true;
      Wrote();
     }
  }

void CRdWidget::SetTextColor(const color fg)
  {
   if(fg == clrNONE || (m_okFg && fg == m_fg))
      return;
   ObjectSetInteger(0, m_name, OBJPROP_COLOR, fg);
   m_fg = fg;
   m_okFg = true;
   Wrote();
  }

void CRdWidget::SetTooltip(const string tip)
  {
   string t = (tip == "") ? RD_TOOLTIP_NONE : tip;
   if(m_okTip && t == m_tip)
      return;
   ObjectSetString(0, m_name, OBJPROP_TOOLTIP, t);
   m_tip = t;
   m_okTip = true;
  }

void CRdWidget::SetVisible(const bool visible)
  {
   if(m_okVis && visible == m_visible)
      return;
   ObjectSetInteger(0, m_name, OBJPROP_TIMEFRAMES, visible ? RD_OBJ_ALL_PERIODS : RD_OBJ_NO_PERIODS);
   m_visible = visible;
   m_okVis = true;
   Wrote();
  }

void CRdWidget::SetAlign(const int align)
  {
   if(m_type != OBJ_EDIT || (m_okAlign && align == m_align))
      return;
   ObjectSetInteger(0, m_name, OBJPROP_ALIGN, align);
   m_align = align;
   m_okAlign = true;
   Wrote();
  }

void CRdWidget::SetAnchor(const int anchor)
  {
   if(m_type != OBJ_LABEL || (m_okAnchor && anchor == m_anchor))
      return;
   ObjectSetInteger(0, m_name, OBJPROP_ANCHOR, anchor);
   m_anchor = anchor;
   m_okAnchor = true;
   Wrote();
  }

void CRdWidget::SetReadOnly(const bool readOnly)
  {
   if(m_type != OBJ_EDIT || (m_okReadOnly && readOnly == m_readOnly))
      return;
   ObjectSetInteger(0, m_name, OBJPROP_READONLY, readOnly);
   m_readOnly = readOnly;
   m_okReadOnly = true;
  }

// A clicked OBJ_BUTTON stays pressed until reset (06 section 0, step 1).
void CRdWidget::Release()
  {
   if(m_type == OBJ_BUTTON && ObjectGetInteger(0, m_name, OBJPROP_STATE) != 0)
     {
      ObjectSetInteger(0, m_name, OBJPROP_STATE, false);
      Wrote();
     }
  }

//+------------------------------------------------------------------+
//| Typed wrappers (02-architecture section 5).                      |
//+------------------------------------------------------------------+
class CRdRect : public CRdWidget
  {
public:
   bool              Make(const string name, CRdRedraw *redraw) { return Create(name, OBJ_RECTANGLE_LABEL, redraw, RD_ZORDER_PANEL); }
  };

class CRdLabel : public CRdWidget
  {
public:
   bool              Make(const string name, CRdRedraw *redraw) { return Create(name, OBJ_LABEL, redraw, RD_ZORDER_PANEL + 1); }
  };

class CRdButton : public CRdWidget
  {
public:
   bool              Make(const string name, CRdRedraw *redraw) { return Create(name, OBJ_BUTTON, redraw, RD_ZORDER_PANEL + 2); }
  };

class CRdEdit : public CRdWidget
  {
public:
   bool              Make(const string name, CRdRedraw *redraw) { return Create(name, OBJ_EDIT, redraw, RD_ZORDER_PANEL + 2); }
  };

//+------------------------------------------------------------------+
//| Delete every chart object whose name starts with 'prefix'        |
//| (written as a loop: same behaviour on MT4 and MT5). Returns the  |
//| number deleted.                                                  |
//+------------------------------------------------------------------+
int RdDeleteObjects(const string prefix)
  {
   int deleted = 0;
   int len = StringLen(prefix);
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringSubstr(name, 0, len) == prefix && ObjectDelete(0, name))
         deleted++;
     }
   return deleted;
  }

#endif // RD_UI_WIDGETS_MQH
