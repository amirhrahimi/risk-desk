//+------------------------------------------------------------------+
//| RiskDesk - Services/Screenshot.mqh                               |
//| Layer   : Services                                               |
//| Purpose : chart screenshots after trade actions and from the     |
//|           camera button (F-19, OP-14):                           |
//|           Files/RiskDesk/Screenshots/<login>_<symbol>_<TF>_      |
//|           <yyyy-mm-dd_HH-MM-SS>_<action>_<ticket>.png            |
//|           (symbol characters / \ : * ? " < > | become _; local   |
//|           time). The caller takes it after the chart has been    |
//|           redrawn with the new state.                            |
//+------------------------------------------------------------------+
#ifndef RD_SERVICES_SCREENSHOT_MQH
#define RD_SERVICES_SCREENSHOT_MQH

#include "..\Domain\Types.mqh"
#include "..\Platform\Compat.mqh"
#include "Logger.mqh"

#define RD_SHOT_DIR   "RiskDesk\\Screenshots"

class CScreenshot
  {
public:
   static string     Sanitize(const string text);
   static string     TimeframeText(const ENUM_TIMEFRAMES tf);
   static string     FileName(const long login, const string symbol, const ENUM_TIMEFRAMES tf, const datetime when,
                              const string action, const ulong ticket);
   static bool       Take(const string action, const ulong ticket, const int width, const int height,
                          string &path, SResult &r);
  };

// OP-14: / \ : * ? " < > | -> _
string CScreenshot::Sanitize(const string text)
  {
   string s = text;
   string bad[] = {"/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "};
   for(int i = 0; i < ArraySize(bad); i++)
      StringReplace(s, bad[i], "_");
   return s;
  }

// PERIOD_H1 -> "H1"
string CScreenshot::TimeframeText(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   if(StringFind(s, "PERIOD_") == 0)
      s = StringSubstr(s, 7);
   return s;
  }

string CScreenshot::FileName(const long login, const string symbol, const ENUM_TIMEFRAMES tf, const datetime when,
                             const string action, const ulong ticket)
  {
   string t = TimeToString(when, TIME_DATE | TIME_SECONDS);   // 2026.11.12 10:43:21
   StringReplace(t, ".", "-");
   StringReplace(t, " ", "_");
   StringReplace(t, ":", "-");
   return IntegerToString(login) + "_" + Sanitize(symbol) + "_" + TimeframeText(tf) + "_" + t + "_" +
          Sanitize(action) + "_" + IntegerToString((long)ticket) + ".png";
  }

//+------------------------------------------------------------------+
//| width/height 0 -> the chart's size (InpShotWidth/Height). Two    |
//| shots in the same second get "_2", "_3" ...                      |
//+------------------------------------------------------------------+
bool CScreenshot::Take(const string action, const ulong ticket, const int width, const int height,
                       string &path, SResult &r)
  {
   r.Reset();
   path = "";
   if(RdIsTester() && !RdIsVisualTester())
      return RdWarn(r, "no screenshot in the non-visual Strategy Tester");
   int w = (width > 0) ? width : (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (height > 0) ? height : (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(w <= 0 || h <= 0)
      return RdFail(r, "chart size unknown (" + IntegerToString(w) + " x " + IntegerToString(h) + ")");
   FolderCreate(RD_SHOT_DIR);
   string name = FileName(AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, (ENUM_TIMEFRAMES)_Period, TimeLocal(), action, ticket);
   path = RD_SHOT_DIR + "\\" + name;
   for(int n = 2; FileIsExist(path) && n < 100; n++)
      path = RD_SHOT_DIR + "\\" + StringSubstr(name, 0, StringLen(name) - 4) + "_" + IntegerToString(n) + ".png";
   ChartRedraw(0);
   ResetLastError();
   if(!ChartScreenShot(0, path, w, h, ALIGN_RIGHT))
     {
      int err = GetLastError();
      RD_LOG_WARN("Screenshot " + path + " failed (error " + IntegerToString(err) + ")");
      return RdFail(r, "screenshot not saved (error " + IntegerToString(err) + ")", err);
     }
   RD_LOG_INFO("Screenshot saved: " + RD_MQL_DIR + "\\Files\\" + path);
   return RdOk(r, path);
  }

#endif // RD_SERVICES_SCREENSHOT_MQH
