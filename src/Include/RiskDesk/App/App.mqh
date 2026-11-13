//+------------------------------------------------------------------+
//| RiskDesk - App/App.mqh                                           |
//| Layer   : App (composition root)                                 |
//| Purpose : creates and wires everything in OnInit and receives    |
//|           the five event handlers from the entry files           |
//|           (02-architecture sections 4, 7 and 8).                 |
//|           Init: settings -> startup log -> gateway config ->     |
//|           persisted state (once per program run) -> symbol-change|
//|           check -> theme/layout -> panel build (adopts existing  |
//|           objects) -> timer and mouse events -> first refresh.   |
//|           Deinit: save what changed; delete every RD_ object     |
//|           only when RiskDesk leaves the chart.                   |
//+------------------------------------------------------------------+
#ifndef RD_APP_APP_MQH
#define RD_APP_APP_MQH

#include "..\Build.mqh"

//--- Domain
#include "..\Domain\Types.mqh"
#include "..\Domain\PriceMath.mqh"
#include "..\Domain\RiskMath.mqh"
#include "..\Domain\Validators.mqh"
#include "..\Domain\Planner.mqh"
#include "..\Domain\RiskBudget.mqh"

//--- Platform
#include "..\Platform\Compat.mqh"
#include "..\Platform\SymbolSpec.mqh"
#include "..\Platform\AccountSpec.mqh"
#include "..\Platform\Market.mqh"
#include "..\Platform\Money.mqh"
#include "..\Platform\TradeGateway.mqh"
#include "..\Platform\History.mqh"

//--- Services
#include "..\Services\Logger.mqh"
#include "..\Services\Persistence.mqh"
#include "..\Services\Screenshot.mqh"
#include "..\Services\ChartHousekeeping.mqh"
#include "..\Services\CandleTime.mqh"

//--- UI
#include "..\UI\Theme.mqh"
#include "..\UI\Layout.mqh"
#include "..\UI\Widgets.mqh"
#include "..\UI\Panel.mqh"
#include "..\UI\Lines.mqh"
#include "..\UI\PendingOverlay.mqh"
#include "..\UI\StatusBar.mqh"

//--- App
#include "Inputs.mqh"
#include "Settings.mqh"
#include "State.mqh"
#include "Commands.mqh"
#include "Controller.mqh"
#ifdef RD_TEST_HOOKS
#include "UiSelfTest.mqh"
#endif

// Hidden chart object that remembers the chart's symbol, so the next
// OnInit can tell a symbol change from a timeframe change (F-23 AC2, ADR-021).
#define RD_CHART_MEMO   "RD_S_CHART"

class CApp
  {
private:
   CSettings         m_cfg;
   CState            m_state;
   CTheme            m_theme;
   CLayout           m_layout;
   CRdRedraw         m_redraw;
   CPanel            m_panel;
   CStatusBar        m_status;
   CPersistence      m_store;
   CCommands         m_cmd;
   CController       m_ctl;
   CTradeGateway     m_gw;
   CMoney            m_money;
   CLines            m_lines;
   CPendingOverlay   m_overlay;
   bool              m_running;
   bool              m_mouseEventsWere;
   bool              m_foregroundWas;   // "Chart on foreground" before RiskDesk switched it off
#ifdef RD_TEST_HOOKS
   CUiSelfTest       m_selfTest;
#endif

   void              LogStartup();
   void              LoadUiState();
   string            CheckChartSymbol();
   void              ConfigureTheme();
   void              ConfigureLines();

public:
                     CApp() { m_running = false; m_mouseEventsWere = false; m_foregroundWas = false; }
   int               Init();
   void              Deinit(const int reason);
   void              Tick();
   void              Timer();
   void              ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
  };

//+------------------------------------------------------------------+
int CApp::Init()
  {
   bool firstRun = !m_state.loaded;
   m_cfg.Load();
   CLogger::Configure(m_cfg.logLevel, m_cfg.logToFile && !RdIsTester(), RD_PRODUCT + " " + _Symbol);
   LogStartup();
   RD_LOG_INFO(m_cfg.Summary());
   for(int i = 0; i < m_cfg.WarningCount(); i++)
      RD_LOG_WARN("Input fixed: " + m_cfg.Warning(i));

   SGatewaySettings gs;
   m_cfg.Gateway(gs);
   m_gw.Configure(gs);

   bool selfTest = false;
#ifdef RD_TEST_HOOKS
   // Active: a timeframe/symbol change during the test re-runs OnInit (the EA's objects survive it).
   selfTest = m_cfg.testUiSelfTest && (m_selfTest.Active() || CUiSelfTest::Requested());
   if(m_cfg.testUiSelfTest && !selfTest)
      RD_LOG_WARN("TEST: panel self-test input is on, but no request file " + CUiSelfTest::RequestFile() + " - ignored");
   if(selfTest)
      // the owner's ui.ini / acct_*.ini are never touched
      m_store.SetDir(CUiSelfTest::StoreDirFor(m_selfTest.Active() ? m_selfTest.Suite() : CUiSelfTest::RequestedSuite()));
#endif
   // No saved state is read or written in the Strategy Tester.
   m_store.Enable(!RdIsTester());
   if(firstRun)
      LoadUiState();
   m_state.busy = false;
   m_state.busyButton = -1;
   string symbolNote = CheckChartSymbol();

   ConfigureTheme();
   m_layout.Configure(m_cfg.scale, m_cfg.autoFitPanel, m_cfg.panelColumns, RdTerminalDpi(), m_cfg.fontSize,
                      m_theme.fontBody, m_theme.fontTitle);
   m_status.Init(GetPointer(m_layout), GetPointer(m_theme), m_cfg.statusHoldSec);
   m_panel.Init(GetPointer(m_layout), GetPointer(m_theme), GetPointer(m_redraw));
   m_panel.SetWanted(m_state.panelX, m_state.panelY);
   m_panel.SetCollapsed(m_state.hidden);
   ConfigureLines();
   m_cmd.Init(GetPointer(m_cfg), GetPointer(m_state), GetPointer(m_store), GetPointer(m_gw), GetPointer(m_money),
              GetPointer(m_lines));
   m_ctl.Init(GetPointer(m_cfg), GetPointer(m_state), GetPointer(m_panel), GetPointer(m_status), GetPointer(m_cmd),
              GetPointer(m_layout), GetPointer(m_redraw), GetPointer(m_store), GetPointer(m_gw), GetPointer(m_money),
              GetPointer(m_lines), GetPointer(m_overlay));
   m_cmd.SetProgress(GetPointer(m_ctl));   // "Closing 4/9..." (OP-12)
   m_ctl.ChartSizeChanged();   // chart size + auto-fit before the objects exist

   ResetLastError();
   if(!m_panel.Build())
     {
      RD_LOG_ERROR("The panel could not be created on this chart (error " + IntegerToString(GetLastError()) + ")");
      return INIT_FAILED;
     }

   if(!EventSetMillisecondTimer(m_cfg.refreshMs))
     {
      RD_LOG_WARN("Millisecond timer unavailable (error " + IntegerToString(GetLastError()) + ") - refreshing every second");
      EventSetTimer(1);
     }
   m_mouseEventsWere = ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE) != 0;
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   long login = CAccountSpec::Login();
   if(login > 0 && login != m_state.riskLogin)
      m_ctl.LoadRisk(login);
   m_ctl.AdoptLines();   // F-23: the planning lines on the chart decide the mode

   //--- first message (rule R8: the user sees what happened)
   SResult r;
   r.Reset();
   if(m_cfg.WarningCount() > 0)
      RdWarn(r, "Input fixed: " + m_cfg.Warning(0) + (m_cfg.WarningCount() > 1 ? " (+" +
             IntegerToString(m_cfg.WarningCount() - 1) + " more in the Experts log)" : ""));
   else
      if(symbolNote != "")
         RdWarn(r, symbolNote);
      else
         if(firstRun)
            RdOk(r, RD_PRODUCT + " " + RD_VERSION + " ready - risk " + RdFormatPct(m_state.riskPct) +
                 " per trade. Add Line, drag the SL, then Buy or Sell");
   if(r.message != "")
      m_ctl.Report(r);

   m_running = true;
#ifdef RD_TEST_HOOKS
   if(selfTest && !m_selfTest.Active())
      m_selfTest.Start(GetPointer(m_cfg), GetPointer(m_state), GetPointer(m_theme), GetPointer(m_layout),
                       GetPointer(m_panel), GetPointer(m_status), GetPointer(m_ctl), GetPointer(m_redraw),
                       GetPointer(m_store), GetPointer(m_gw), GetPointer(m_money), GetPointer(m_cmd),
                       GetPointer(m_lines), GetPointer(m_overlay));
#endif
   m_ctl.Refresh();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| 02 section 7.1 OnDeinit. ui.ini is written only when this chart  |
//| changed something (several charts share it).                     |
//+------------------------------------------------------------------+
void CApp::Deinit(const int reason)
  {
   EventKillTimer();
   m_panel.CancelDrag();
   if(m_running)
      m_ctl.FlushUi();
   m_running = false;
   bool leaving = (reason == REASON_REMOVE || reason == REASON_PROGRAM || reason == REASON_INITFAILED ||
                   reason == REASON_CHARTCLOSE);
   if(leaving)
     {
      m_panel.Destroy();
      int lines = CLines::DeleteAll() + CPendingOverlay::DeleteAll();   // the orders themselves stay
      int rest = RdDeleteObjects("RD_");
      RD_LOG_INFO("Chart objects removed (" + IntegerToString(lines + rest) + " besides the panel)");
      if(m_foregroundWas)
         ChartSetInteger(0, CHART_FOREGROUND, true);   // the user's setting, switched off while RiskDesk ran
     }
   if(!m_mouseEventsWere)
      ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, false);
   ChartRedraw(0);
   RD_LOG_INFO(RD_PRODUCT + " stopped: " + RdDeinitReasonText(reason));
#ifdef RD_TEST_HOOKS
   m_selfTest.OnDeinit(reason);
#endif
  }

void CApp::Tick()
  {
   if(m_running)
      m_ctl.OnTick();
  }

void CApp::Timer()
  {
   if(!m_running)
      return;
#ifdef RD_TEST_HOOKS
   if(m_selfTest.Active())
     {
      m_selfTest.Step();
      return;
     }
#endif
   m_ctl.OnTimer();
  }

void CApp::ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(m_running)
      m_ctl.OnChartEvent(id, lparam, dparam, sparam);
  }

//+------------------------------------------------------------------+
//| ui.ini, once per program run (an EA keeps its objects across a   |
//| timeframe change, so later OnInits keep the state in memory).    |
//| D15: when X/Y Start differ from the values saved with the        |
//| position, the user edited them: the new X/Y Start wins.          |
//| D16: Start hidden = true hides the panel at every start.         |
//+------------------------------------------------------------------+
void CApp::LoadUiState()
  {
   m_state.loaded = true;
   m_state.panelX = m_cfg.panelX;
   m_state.panelY = m_cfg.panelY;
   m_state.hidden = m_cfg.startHidden;
   m_state.inputX = m_cfg.panelX;
   m_state.inputY = m_cfg.panelY;
   m_state.riskPct = m_cfg.defaultRiskPct;
   SUiPersist ui;
   if(!m_store.LoadUi(ui))
     {
      RD_LOG_INFO("Panel at X/Y Start " + IntegerToString(m_cfg.panelX) + ", " + IntegerToString(m_cfg.panelY) +
                  (m_store.Enabled() ? " (no saved position yet)" : " (saved state not used here)"));
      return;
     }
   bool inputsEdited = (ui.inputX >= 0 && ui.inputY >= 0 && (ui.inputX != m_cfg.panelX || ui.inputY != m_cfg.panelY));
   if(!inputsEdited)
     {
      m_state.panelX = ui.x;
      m_state.panelY = ui.y;
     }
   if(!m_cfg.startHidden)
      m_state.hidden = ui.hidden;
   RD_LOG_INFO("Panel state restored: x " + IntegerToString(m_state.panelX) + ", y " + IntegerToString(m_state.panelY) +
               (m_state.hidden ? ", hidden" : ", shown") +
               (inputsEdited ? " (X/Y Start were changed: using them)" : ""));
   if(inputsEdited)
      m_state.MarkUiDirty();
  }

//+------------------------------------------------------------------+
//| F-23 AC2: lines belong to the symbol they were drawn on. Returns |
//| a status note when lines were removed.                           |
//+------------------------------------------------------------------+
string CApp::CheckChartSymbol()
  {
   string note = "";
   if(ObjectFind(0, RD_CHART_MEMO) >= 0)
     {
      string old = ObjectGetString(0, RD_CHART_MEMO, OBJPROP_TEXT);
      if(old != "" && old != _Symbol)
        {
         int n = CLines::DeleteAll();
         m_state.lineMode = LINES_NONE;
         RD_LOG_INFO("Chart symbol changed from " + old + " to " + _Symbol + ": " + IntegerToString(n) +
                     " line object(s) of " + old + " removed");
         if(n > 0)
            note = "Lines removed: the chart changed from " + old + " to " + _Symbol;
        }
     }
   else
     {
      ObjectCreate(0, RD_CHART_MEMO, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, RD_CHART_MEMO, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, RD_CHART_MEMO, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, RD_CHART_MEMO, OBJPROP_TIMEFRAMES, RD_OBJ_NO_PERIODS);
      ObjectSetInteger(0, RD_CHART_MEMO, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(0, RD_CHART_MEMO, OBJPROP_YDISTANCE, 0);
     }
   ObjectSetString(0, RD_CHART_MEMO, OBJPROP_TEXT, _Symbol);
   //--- the user's "Chart on foreground" before RiskDesk first switched it off on this chart:
   //--- kept with the chart (its profile), so a terminal restart does not lose it
   string fg = ObjectGetString(0, RD_CHART_MEMO, OBJPROP_TOOLTIP);
   if(fg == "foreground=1" || fg == "foreground=0")
      m_foregroundWas = (fg == "foreground=1");
   else
     {
      m_foregroundWas = ChartGetInteger(0, CHART_FOREGROUND) != 0;
      ObjectSetString(0, RD_CHART_MEMO, OBJPROP_TOOLTIP, m_foregroundWas ? "foreground=1" : "foreground=0");
     }
   return note;
  }

//+------------------------------------------------------------------+
//| 05 section 2 theme from the Colors and Panel / Font inputs.      |
//+------------------------------------------------------------------+
void CApp::ConfigureTheme()
  {
   m_theme.Configure(m_cfg.fontPreset, m_cfg.fontSize, m_cfg.colorBg, m_cfg.colorSystemBorder, m_cfg.colorButtonBorder,
                     m_cfg.colorText, m_cfg.colorPendingInfo, m_cfg.colorSpread);
   m_theme.SetButton(PB_ADDLINE, m_cfg.colorAddLine, m_cfg.colorText);
   m_theme.SetButton(PB_DELLINE, m_cfg.colorDeleteLine, m_cfg.colorText);
   m_theme.SetButton(PB_BUY, m_cfg.colorBuy, m_cfg.colorText);
   m_theme.SetButton(PB_SELL, m_cfg.colorSell, m_cfg.colorText);
   m_theme.SetButton(PB_ADDPEND, m_cfg.colorAddPendLine, m_cfg.colorText);
   m_theme.SetButton(PB_SETPEND, m_cfg.colorSetPending, clrBlack);   // 05 section 2: black text
   m_theme.SetButton(PB_DELPEND, m_cfg.colorDelPending, m_cfg.colorText);
   m_theme.SetButton(PB_RISKFREE, m_cfg.colorRiskFree, m_cfg.colorText);
   m_theme.SetButton(PB_HALF, m_cfg.colorHalfClose, m_cfg.colorText);
   m_theme.SetButton(PB_CHARTCLOSE, m_cfg.colorChartClose, m_cfg.colorText);
   m_theme.SetButton(PB_FULLCLOSE, m_cfg.colorFullClose, m_cfg.colorText);
   m_theme.SetButton(PB_SHOT, m_cfg.colorBg, m_cfg.colorText);
  }

//+------------------------------------------------------------------+
//| 05 sections 5-6 line look from the Colors / Chart extras inputs: |
//| planning lines and the pending order overlay (F-22).             |
//+------------------------------------------------------------------+
void CApp::ConfigureLines()
  {
   SLineStyle ls;
   ls.Defaults();
   ls.sl = m_cfg.colorSL;
   ls.tp = m_cfg.colorTP;
   ls.entry = m_cfg.colorEntry;
   ls.slLabel = m_cfg.colorSlLoss;
   ls.width = m_cfg.lineWidth;
   ls.labelSize = m_cfg.slLossFontSize;
   ls.labelFont = m_theme.fontBody;
   ls.tpRR = m_cfg.tpRR;
   m_lines.Init(ls, GetPointer(m_redraw));
   SOverlayStyle os;
   os.Defaults();
   os.entry = m_cfg.colorPendOverlayEntry;
   os.sl = m_cfg.colorPendOverlaySL;
   os.tp = m_cfg.colorPendOverlayTP;
   m_overlay.Init(os, GetPointer(m_lines), GetPointer(m_redraw));
  }

//+------------------------------------------------------------------+
//| T-01: version, platform, account (currency, leverage, margin     |
//| mode) and the chart symbol's spec.                               |
//+------------------------------------------------------------------+
void CApp::LogStartup()
  {
   string build = "release build";
#ifdef RD_TEST_HOOKS
   build = "DEBUG build (test hooks on)";
#endif
   RD_LOG_INFO(RD_PRODUCT + " " + RD_VERSION + " starting: " + RD_PLATFORM +
               ", terminal build " + IntegerToString(RdTerminalBuild()) +
               ", " + build +
               ", chart " + _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) +
               ", DPI " + IntegerToString(RdTerminalDpi()));

   SAccountSpec account;
   SResult accountResult;
   if(CAccountSpec::Read(account, accountResult))
      RD_LOG_INFO("Account " + CAccountSpec::Describe(account));
   else
      RD_LOG_WARN("Account: " + accountResult.message);

   SResult permission;
   if(CAccountSpec::CanTrade(permission))
      RD_LOG_INFO("Trade permissions: OK");
   else
      RD_LOG_WARN("Trade permissions: " + permission.message);

   SSymbolSpec spec;
   SResult specResult;
   bool specOk = CSymbolSpec::Read(_Symbol, spec, specResult);
   if(spec.digits > 0)
      RD_LOG_INFO("Symbol " + CSymbolSpec::Describe(spec, account.currency));
   if(!specOk)
      RD_LOG_ERROR(specResult.message);
   else
      if(specResult.sev == SEV_WARN)
         RD_LOG_WARN(specResult.message);
  }

#endif // RD_APP_APP_MQH
