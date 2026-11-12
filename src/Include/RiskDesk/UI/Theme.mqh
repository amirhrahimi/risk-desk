//+------------------------------------------------------------------+
//| RiskDesk - UI/Theme.mqh                                          |
//| Layer   : UI                                                     |
//| Purpose : colours and fonts of the panel (05-ui-spec section 2). |
//|           App configures it from Settings; the UI reads it.      |
//|           Also the button identities (EPanelButton), shared by   |
//|           Layout, Panel, App/State and App/Controller.           |
//+------------------------------------------------------------------+
#ifndef RD_UI_THEME_MQH
#define RD_UI_THEME_MQH

#include "..\Domain\Types.mqh"
#include "..\Platform\Compat.mqh"

// The clickable buttons of the panel that run a command (06), in panel
// order. The hide toggle is not a command; it is handled by the panel.
enum EPanelButton
  {
   PB_ADDLINE = 0,
   PB_DELLINE,
   PB_BUY,
   PB_SELL,
   PB_ADDPEND,
   PB_SETPEND,
   PB_DELPEND,
   PB_RISKFREE,
   PB_HALF,
   PB_CHARTCLOSE,
   PB_FULLCLOSE,
   PB_SHOT,
   PB_COUNT
  };

// How a button is drawn (05 section 2).
enum EButtonLook
  {
   LOOK_NORMAL,     // its own colour
   LOOK_DIM,        // 40 % towards the background (F-33, invalid side)
   LOOK_DISABLED,   // grey; the tooltip says why
   LOOK_WORKING     // dark grey "..." while its command runs
  };

#define RD_THEME_DIM_FACTOR   0.40

class CTheme
  {
public:
   //--- fonts (05 section 1: title = semibold variant, size + 3; status = size - 1)
   string            fontBody;
   string            fontTitle;
   string            fontHandle;       // move handle glyph (05 section 1)
   string            glyphHandle;
   string            fontCamera;       // manual screenshot button glyph
   string            glyphCamera;
   int               fontSize;         // body size before scaling
   //--- panel
   color             bg;
   color             border;
   color             buttonBorder;
   color             text;
   color             titleAccent;
   color             fieldBg;
   color             fieldBorder;
   color             pendingInfo;
   color             spread;
   color             statusOk;
   color             statusWarn;
   color             statusError;
   color             disabledBg;
   color             disabledText;
   color             workingBg;
   color             workingText;
   //--- buttons
   color             buttonBg[PB_COUNT];
   color             buttonText[PB_COUNT];

                     CTheme();
   void              Configure(const EFontPreset preset, const int size, const color background, const color systemBorder,
                               const color btnBorder, const color textColor, const color pendingInfoColor,
                               const color spreadColor);
   void              SetButton(const EPanelButton b, const color background, const color foreground);
   void              ButtonColors(const EPanelButton b, const EButtonLook look, color &back, color &fore) const;
   color             SeverityColor(const ESeverity sev) const;

   static string     FontName(const EFontPreset preset);
   static string     TitleFontName(const EFontPreset preset);
   static color      Blend(const color from, const color to, const double f);
  };

//+------------------------------------------------------------------+
CTheme::CTheme()
  {
   Configure(FONT_SEGOE_UI, 8, clrBlack, C'136,136,136', C'136,136,136', clrWhite, clrGold, clrWhite);
   for(int i = 0; i < PB_COUNT; i++)
      SetButton((EPanelButton)i, C'44,64,97', clrWhite);
  }

//+------------------------------------------------------------------+
void CTheme::Configure(const EFontPreset preset, const int size, const color background, const color systemBorder,
                       const color btnBorder, const color textColor, const color pendingInfoColor,
                       const color spreadColor)
  {
   fontBody     = FontName(preset);
   fontTitle    = TitleFontName(preset);
   if(RD_OBJ_TEXT_UNICODE)
     {
      fontHandle  = "Segoe UI Symbol";
      glyphHandle = ShortToString((ushort)0x2725);                                      // four club-spoked asterisk
      fontCamera  = "Segoe UI Symbol";
      glyphCamera = ShortToString((ushort)0xD83D) + ShortToString((ushort)0xDCF7);      // U+1F4F7 camera
     }
   else
     {
      // MT4 (ANSI): symbol-font characters, picked from the P3 glyph sheets
      // drawn on MT4 (codes 0x80-0x9F do not survive the ANSI mapping).
      fontHandle  = "Wingdings";
      glyphHandle = ShortToString((ushort)0x76);   // four diamonds
      fontCamera  = "Webdings";
      glyphCamera = ShortToString((ushort)0xB5);   // still camera
     }
   fontSize     = size;
   bg           = background;
   border       = systemBorder;
   buttonBorder = btnBorder;
   text         = textColor;
   titleAccent  = C'150,120,255';
   fieldBg      = clrBlack;
   fieldBorder  = C'200,200,200';
   pendingInfo  = pendingInfoColor;
   spread       = spreadColor;
   statusOk     = C'76,175,80';
   statusWarn   = C'255,179,0';
   statusError  = C'239,83,80';
   disabledBg   = C'60,60,60';
   disabledText = C'140,140,140';
   workingBg    = C'45,45,45';
   workingText  = C'200,200,200';
  }

void CTheme::SetButton(const EPanelButton b, const color background, const color foreground)
  {
   if(b < 0 || b >= PB_COUNT)
      return;
   buttonBg[b] = background;
   buttonText[b] = foreground;
  }

//+------------------------------------------------------------------+
void CTheme::ButtonColors(const EPanelButton b, const EButtonLook look, color &back, color &fore) const
  {
   back = buttonBg[b];
   fore = buttonText[b];
   if(look == LOOK_DIM)
     {
      back = Blend(back, bg, RD_THEME_DIM_FACTOR);
      fore = Blend(fore, bg, RD_THEME_DIM_FACTOR);
     }
   else
      if(look == LOOK_DISABLED)
        {
         back = disabledBg;
         fore = disabledText;
        }
      else
         if(look == LOOK_WORKING)
           {
            back = workingBg;
            fore = workingText;
           }
  }

color CTheme::SeverityColor(const ESeverity sev) const
  {
   if(sev == SEV_ERROR)
      return statusError;
   if(sev == SEV_WARN)
      return statusWarn;
   return statusOk;
  }

//+------------------------------------------------------------------+
//| 07 "Panel Font Preset".                                          |
//+------------------------------------------------------------------+
string CTheme::FontName(const EFontPreset preset)
  {
   switch(preset)
     {
      case FONT_ARIAL:
         return "Arial";
      case FONT_TAHOMA:
         return "Tahoma";
      case FONT_CALIBRI:
         return "Calibri";
      case FONT_VERDANA:
         return "Verdana";
      case FONT_CONSOLAS:
         return "Consolas";
      default:
         return "Segoe UI";
     }
  }

// Semibold where the family has one, else the bold face (05 section 1).
string CTheme::TitleFontName(const EFontPreset preset)
  {
   if(preset == FONT_SEGOE_UI)
      return "Segoe UI Semibold";
   return FontName(preset) + " Bold";
  }

//+------------------------------------------------------------------+
//| f = 0 -> from, f = 1 -> to (per RGB channel).                    |
//+------------------------------------------------------------------+
color CTheme::Blend(const color from, const color to, const double f)
  {
   double k = MathMax(0.0, MathMin(1.0, f));
   int c1 = (int)from;
   int c2 = (int)to;
   int r = (int)MathRound((c1 & 0xFF) + (((c2 & 0xFF) - (c1 & 0xFF)) * k));
   int g = (int)MathRound(((c1 >> 8) & 0xFF) + ((((c2 >> 8) & 0xFF) - ((c1 >> 8) & 0xFF)) * k));
   int b = (int)MathRound(((c1 >> 16) & 0xFF) + ((((c2 >> 16) & 0xFF) - ((c1 >> 16) & 0xFF)) * k));
   return (color)(r | (g << 8) | (b << 16));
  }

#endif // RD_UI_THEME_MQH
