//+------------------------------------------------------------------+
//| RiskDesk - App/State.mqh                                         |
//| Layer   : App                                                    |
//| Purpose : the mutable UI/session state (02-architecture section  |
//|           5): Risk %, panel position and hidden flag, line mode, |
//|           busy flag and click times. CApp owns the one instance. |
//|           An EA's objects survive a timeframe or symbol change   |
//|           (the terminal calls OnDeinit/OnInit without reloading  |
//|           the program), so 'loaded' tells OnInit whether the     |
//|           persisted state was already read in this run.          |
//+------------------------------------------------------------------+
#ifndef RD_APP_STATE_MQH
#define RD_APP_STATE_MQH

#include "..\Domain\Types.mqh"
#include "..\UI\Theme.mqh"

class CState
  {
public:
   bool              loaded;            // ui.ini read in this program run
   //--- Risk % (F-02), per account
   double            riskPct;
   long              riskLogin;         // account riskPct belongs to; 0 = not known yet
   //--- panel (F-01, F-23)
   int               panelX;            // wanted anchor (persisted)
   int               panelY;
   bool              hidden;
   int               inputX;            // X/Y Start when the position was saved (D15)
   int               inputY;
   bool              uiDirty;           // save ui.ini when 1 s has passed since uiDirtyAt
   uint              uiDirtyAt;
   //--- lines (P4/P5)
   ELineMode         lineMode;
   //--- commands (06 section 0)
   bool              busy;
   int               busyButton;        // EPanelButton while busy, -1 otherwise
   uint              lastClickAt[PB_COUNT];
   bool              clicked[PB_COUNT];

                     CState() { Reset(); }

   void              Reset()
     {
      loaded = false;
      riskPct = 1.0;
      riskLogin = 0;
      panelX = 20;
      panelY = 40;
      hidden = false;
      inputX = -1;
      inputY = -1;
      uiDirty = false;
      uiDirtyAt = 0;
      lineMode = LINES_NONE;
      busy = false;
      busyButton = -1;
      for(int i = 0; i < PB_COUNT; i++)
        {
         lastClickAt[i] = 0;
         clicked[i] = false;
        }
     }

   void              MarkUiDirty()
     {
      uiDirty = true;
      uiDirtyAt = GetTickCount();
     }
  };

#endif // RD_APP_STATE_MQH
