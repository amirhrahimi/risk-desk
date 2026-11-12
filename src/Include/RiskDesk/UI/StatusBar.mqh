//+------------------------------------------------------------------+
//| RiskDesk - UI/StatusBar.mqh                                      |
//| Layer   : UI                                                     |
//| Purpose : the status bar (05 section 4, F-25): the last message  |
//|           with its severity colour, word-wrapped into up to 3    |
//|           lines measured in the status font; the full text is    |
//|           the tooltip. After InpStatusHoldSec the idle readout   |
//|           (open risk or the highest-priority warning, set by     |
//|           App) is shown instead. Logging is the caller's job.    |
//+------------------------------------------------------------------+
#ifndef RD_UI_STATUSBAR_MQH
#define RD_UI_STATUSBAR_MQH

#include "..\Domain\Types.mqh"
#include "Theme.mqh"
#include "Layout.mqh"
#include "Panel.mqh"

class CStatusBar
  {
private:
   CLayout          *m_layout;
   CTheme           *m_theme;
   int               m_holdMs;
   //--- message
   bool              m_hasMessage;
   string            m_text;
   ESeverity         m_sev;
   uint              m_shownAt;
   //--- idle readout
   string            m_idleText;
   ESeverity         m_idleSev;
   //--- wrap cache
   string            m_wrapText;
   int               m_wrapWidth;
   int               m_wrapFont;
   string            m_lines[RD_STATUS_LINES];

   void              Wrap(const string text, const int width);
   int               Width(const string text) const;
   string            Ellipsize(const string text, const int width) const;

public:
                     CStatusBar();
   void              Init(CLayout *layout, CTheme *theme, const int holdSec);
   void              Show(const ESeverity sev, const string text);
   void              SetIdle(const ESeverity sev, const string text);
   bool              Holding() const;
   void              Fill(SPanelModel &m, const int width);
   string            Text() const { return m_text; }
   ESeverity         Severity() const { return m_sev; }
   string            IdleText() const { return m_idleText; }
  };

//+------------------------------------------------------------------+
CStatusBar::CStatusBar()
  {
   m_layout = NULL;
   m_theme = NULL;
   m_holdMs = 8000;
   m_hasMessage = false;
   m_text = "";
   m_sev = SEV_OK;
   m_shownAt = 0;
   m_idleText = "";
   m_idleSev = SEV_OK;
   m_wrapText = "";
   m_wrapWidth = -1;
   m_wrapFont = -1;
   for(int i = 0; i < RD_STATUS_LINES; i++)
      m_lines[i] = "";
  }

void CStatusBar::Init(CLayout *layout, CTheme *theme, const int holdSec)
  {
   m_layout = layout;
   m_theme = theme;
   m_holdMs = MathMax(1, holdSec) * 1000;
   m_wrapWidth = -1;
  }

void CStatusBar::Show(const ESeverity sev, const string text)
  {
   m_hasMessage = true;
   m_text = text;
   m_sev = sev;
   m_shownAt = GetTickCount();
  }

void CStatusBar::SetIdle(const ESeverity sev, const string text)
  {
   m_idleText = text;
   m_idleSev = sev;
  }

bool CStatusBar::Holding() const
  {
   return m_hasMessage && (uint)(GetTickCount() - m_shownAt) < (uint)m_holdMs;
  }

//+------------------------------------------------------------------+
//| The message while it is held, else the idle readout.             |
//+------------------------------------------------------------------+
void CStatusBar::Fill(SPanelModel &m, const int width)
  {
   bool held = Holding();
   string text = held ? m_text : m_idleText;
   m.statusSev = held ? m_sev : m_idleSev;
   m.statusTip = text;
   Wrap(text, width);
   for(int i = 0; i < RD_STATUS_LINES; i++)
      m.statusLine[i] = m_lines[i];
  }

int CStatusBar::Width(const string text) const
  {
   int w = 0;
   int h = 0;
   if(!CLayout::TextSize(m_theme.fontBody, m_layout.FontStatus(), text, w, h))
      return StringLen(text) * MathMax(1, m_layout.FontStatus());   // rough, only if measuring fails
   return w;
  }

// Longest prefix of 'text' + "..." that fits.
string CStatusBar::Ellipsize(const string text, const int width) const
  {
   string t = text;
   while(StringLen(t) > 0 && Width(t + "...") > width)
      t = StringSubstr(t, 0, StringLen(t) - 1);
   return RdTrim(t) + "...";
  }

//+------------------------------------------------------------------+
//| Greedy word wrap into RD_STATUS_LINES lines of 'width' pixels.   |
//| A word longer than a line is broken; overflow ends with "...".   |
//+------------------------------------------------------------------+
void CStatusBar::Wrap(const string text, const int width)
  {
   int font = m_layout.FontStatus();
   if(text == m_wrapText && width == m_wrapWidth && font == m_wrapFont)
      return;
   m_wrapText = text;
   m_wrapWidth = width;
   m_wrapFont = font;
   for(int i = 0; i < RD_STATUS_LINES; i++)
      m_lines[i] = "";
   if(text == "" || width <= 0)
      return;

   string words[];
   int n = StringSplit(text, ' ', words);
   int line = 0;
   string current = "";
   for(int i = 0; i < n && line < RD_STATUS_LINES; i++)
     {
      string word = words[i];
      if(word == "")
         continue;
      string candidate = (current == "") ? word : current + " " + word;
      if(Width(candidate) <= width)
        {
         current = candidate;
         continue;
        }
      if(current != "")
        {
         m_lines[line++] = current;
         current = "";
         if(line >= RD_STATUS_LINES)
           {
            // more text than lines: end the last line with "..."
            m_lines[RD_STATUS_LINES - 1] = Ellipsize(m_lines[RD_STATUS_LINES - 1] + " " + word, width);
            return;
           }
        }
      // the word alone: break it if it is wider than a line
      while(Width(word) > width && line < RD_STATUS_LINES)
        {
         int cut = StringLen(word) - 1;
         while(cut > 1 && Width(StringSubstr(word, 0, cut)) > width)
            cut--;
         m_lines[line++] = StringSubstr(word, 0, cut);
         word = StringSubstr(word, cut);
        }
      if(line >= RD_STATUS_LINES)
        {
         m_lines[RD_STATUS_LINES - 1] = Ellipsize(m_lines[RD_STATUS_LINES - 1], width);
         return;
        }
      current = word;
     }
   if(current != "" && line < RD_STATUS_LINES)
      m_lines[line] = current;
  }

#endif // RD_UI_STATUSBAR_MQH
