// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - App/Controller.mqh                                    |
//| Layer   : App                                                    |
//| Purpose : maps chart events, timer and ticks to actions          |
//|           (02-architecture section 7):                           |
//|           - button clicks -> Commands, behind the busy guard and |
//|             the per-button click cooldown (06 section 0, F-06    |
//|             AC6); every click ends with a status + log line (R8) |
//|           - Risk % edits (F-02), hide toggle, panel drag         |
//|           - chart resize: clamp at once, auto-fit debounced      |
//|             300 ms (F-34)                                        |
//|           - Strategy Tester: OnChartEvent does not arrive, so    |
//|             button states and the Risk % text are polled on      |
//|             every tick (02 section 10)                           |
//|           - Refresh: quote, spread, prices on Buy/Sell, button   |
//|             looks, idle readout, debounced ui.ini save, panel    |
//|             self-repair; one ChartRedraw per cycle.              |
//|           - planning lines (P4): dropped lines snap to the tick  |
//|             grid and the manual TP line follows; manual deletion |
//|             is detected; Lots / Pending Info / labels / dimmed   |
//|             side from the live preview (OP-06, OP-15, F-18,      |
//|             F-33); the panel is raised above new chart objects;  |
//|             screenshots after commands (F-19).                   |
//|           - pending order overlay (P5, F-22): drawn every        |
//|             refresh; a dropped overlay line runs OP-16.          |
//|           - chart extras (P7): candle countdown (F-21) and       |
//|             closed-trade objects (F-20) every refresh; old daily |
//|             log files pruned at start and each new day (F-32).   |
//|           View model and idle readout: App/ControllerModel.mqh.  |
//|           Preview and lines: App/ControllerPreview.mqh.          |
//|           Overlay and OP-16 drops: App/ControllerOverlay.mqh.    |
//+------------------------------------------------------------------+
#ifndef RD_APP_CONTROLLER_MQH
#define RD_APP_CONTROLLER_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "..\Domain\PriceMath.mqh"
#include "..\Domain\RiskBudget.mqh"
#include "..\Platform\Compat.mqh"
#include "..\Platform\SymbolSpec.mqh"
#include "..\Platform\AccountSpec.mqh"
#include "..\Platform\Market.mqh"
#include "..\Platform\Money.mqh"
#include "..\Platform\TradeGateway.mqh"
#include "..\Domain\Planner.mqh"
#include "..\Services\Logger.mqh"
#include "..\Services\Persistence.mqh"
#include "..\Services\Screenshot.mqh"
#include "..\Services\CandleTime.mqh"
#include "..\Services\ChartHousekeeping.mqh"
#include "..\UI\Theme.mqh"
#include "..\UI\Layout.mqh"
#include "..\UI\Widgets.mqh"
#include "..\UI\Panel.mqh"
#include "..\UI\Lines.mqh"
#include "..\UI\PendingOverlay.mqh"
#include "..\UI\StatusBar.mqh"
#include "Settings.mqh"
#include "State.mqh"
#include "Commands.mqh"

// What the planning lines mean right now (OP-06, OP-15, F-18, F-33).
struct SPreview
  {
   string            key;             // inputs of the last computation (05 section 3: skip when unchanged)
   string            lotsText;
   bool              lotsWarn;
   string            lotsTip;
   string            pinfoText;
   bool              pinfoWarn;
   string            pinfoTip;
   bool              dimBuy;
   bool              dimSell;
   string            buyWhy;
   string            sellWhy;
   string            label[RD_LINE_ROLES];
   color             labelColor[RD_LINE_ROLES];

   void              Reset()
     {
      key = "";
      lotsText = "";
      lotsWarn = false;
      lotsTip = "";
      pinfoText = "";
      pinfoWarn = false;
      pinfoTip = "";
      dimBuy = false;
      dimSell = false;
      buyWhy = "";
      sellWhy = "";
      for(int i = 0; i < RD_LINE_ROLES; i++)
        {
         label[i] = "";
         labelColor[i] = clrNONE;
        }
     }
  };

#define RD_CTL_SPEC_MS        60000   // symbol spec re-read (02 section 7.2: cached, refreshed every 60 s)
#define RD_CTL_IDLE_MS        1000    // idle readout warnings
#define RD_CTL_RISK_MS        2000    // open-risk readout (lists positions and orders)
#define RD_CTL_HOUSEKEEP_MS   1000    // chart size poll, panel objects check
#define RD_CTL_FIT_DEBOUNCE   300     // 05 section 1: auto-fit debounced 300 ms
#define RD_CTL_UI_SAVE_MS     1000    // 02 section 8: ui.ini debounced 1 s
#define RD_CTL_TICK_MIN_MS    50      // ticks refresh at most every 50 ms

class CController : public CProgressSink
  {
private:
   CSettings        *m_cfg;
   CState           *m_state;
   CPanel           *m_panel;
   CStatusBar       *m_status;
   CCommands        *m_cmd;
   CLayout          *m_layout;
   CRdRedraw        *m_redraw;
   CPersistence     *m_store;
   CTradeGateway    *m_gw;
   CMoney           *m_money;
   CLines           *m_lines;
   CPendingOverlay  *m_overlay;
   CCandleTime      *m_candle;          // F-21 (NULL = none)
   CChartHousekeeping *m_house;         // F-20 (NULL = none)
   bool              m_houseFirst;      // first refresh: scan for closed-trade objects at once
   int               m_logDay;          // local day of the last log pruning (F-32), -1 = not yet

   SPreview          m_pv;
   SOverlayItem      m_ov[];            // placed pending orders as drawn (F-22)
   string            m_ovKey;           // orders + account of the last label texts
   bool              m_ovOn;            // overlay objects may exist (removed when switched off)
   bool              m_tpWas;           // a TP line existed at the last refresh (manual deletion note)
   bool              m_raiseWanted;     // chart objects were created: raise the panel in this refresh
   string            m_tips[PB_COUNT];
   SSymbolSpec       m_spec;
   bool              m_specOk;
   string            m_specMsg;
   string            m_mismatch;        // BC-05 MT4 tick-value warning for the chart symbol
   uint              m_specAt, m_idleAt, m_riskAt, m_housekeepAt, m_refreshAt;
   string            m_riskText;
   ESeverity         m_riskSev;
   int               m_chartW, m_chartH;
   bool              m_fitPending;
   uint              m_chartAt;
   int               m_oneClick;        // last seen CHART_SHOW_ONE_CLICK, -1 = not read yet

   void              ReadSpec();
   void              CheckAccount();
   void              BuildModel(SPanelModel &m, const SQuote &q, const bool quoteOk);
   void              SpreadText(const SQuote &q, const bool quoteOk, string &text, bool &warn) const;
   string            DisabledWhy(const EPanelButton b) const;
   string            TradeModeWarning() const;
   void              UpdateIdle(const SQuote &q, const bool quoteOk);
   void              ComputeOpenRisk();
   void              Housekeeping();
   void              ApplyFit();
   void              SaveUi();
   void              ToggleHide();
   void              RiskEdited();
   static string     AgeText(const int seconds);
   //--- App/ControllerPreview.mqh
   void              SyncLines();
   void              ComputePreview(const SQuote &q, const bool quoteOk);
   void              PreviewMarket(const SLines &l, const SQuote &q, const SAccountSpec &acc, const SPlanSettings &p);
   void              PreviewPending(const SLines &l, const SQuote &q, const SAccountSpec &acc, const SPlanSettings &p);
   string            RiskLabel(const SAccountSpec &acc, const STradePlan &plan) const;
   string            RewardLabel(const SAccountSpec &acc, const STradePlan &plan) const;
   bool              ApplyLabels();
   void              ApplyPreview(SPanelModel &m) const;
   void              LineDropped(const ELineRole role);
   void              TakeShot(SResult &r);
   //--- App/ControllerOverlay.mqh
   bool              SyncOverlay();
   void              OverlayLabels(const SOrder &arr[], const SAccountSpec &acc, const bool accOk);
   void              OverlayDropped(const ulong ticket, const ELineRole role, const bool drag);
   bool              SyncExtras(const SQuote &q, const bool quoteOk);

public:
                     CController();
   void              Init(CSettings *cfg, CState *state, CPanel *panel, CStatusBar *status, CCommands *cmd,
                          CLayout *layout, CRdRedraw *redraw, CPersistence *store, CTradeGateway *gw, CMoney *money,
                          CLines *lines, CPendingOverlay *overlay);
   void              AdoptLines();
   // P7 chart extras, owned by CApp (05 section 6).
   void              SetExtras(CCandleTime *candle, CChartHousekeeping *house)
     {
      m_candle = candle;
      m_house = house;
      m_houseFirst = true;
     }
   string            LotsTip() const { return m_pv.lotsTip; }
   CCandleTime      *Candle() { return m_candle; }   // self-test
   CChartHousekeeping *House() { return m_house; }   // self-test
   void              OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam);
   void              OnTimer();
   void              OnTick();
   void              Refresh();
   void              Click(const EPanelButton b);
   void              Report(const SResult &r);
   virtual void      Progress(const string text);
   void              LoadRisk(const long login);
   bool              ChartSizeChanged();
   bool              CheckChartLook();
   void              FlushUi() { if(m_state.uiDirty) SaveUi(); }
  };

//+------------------------------------------------------------------+
CController::CController()
  {
   m_cfg = NULL;
   m_state = NULL;
   m_panel = NULL;
   m_status = NULL;
   m_cmd = NULL;
   m_layout = NULL;
   m_redraw = NULL;
   m_store = NULL;
   m_gw = NULL;
   m_money = NULL;
   m_lines = NULL;
   m_overlay = NULL;
   m_candle = NULL;
   m_house = NULL;
   m_houseFirst = true;
   m_logDay = -1;
   m_pv.Reset();
   m_ovKey = "";
   m_ovOn = true;     // objects kept with the chart are removed if the overlay is off
   m_tpWas = false;
   m_raiseWanted = false;
   m_specOk = false;
   m_specMsg = "";
   m_mismatch = "";
   m_specAt = 0;
   m_idleAt = 0;
   m_riskAt = 0;
   m_housekeepAt = 0;
   m_refreshAt = 0;
   m_riskText = "";
   m_riskSev = SEV_OK;
   m_chartW = 0;
   m_chartH = 0;
   m_fitPending = false;
   m_chartAt = 0;
   m_oneClick = -1;
  }

//+------------------------------------------------------------------+
void CController::Init(CSettings *cfg, CState *state, CPanel *panel, CStatusBar *status, CCommands *cmd,
                       CLayout *layout, CRdRedraw *redraw, CPersistence *store, CTradeGateway *gw, CMoney *money,
                       CLines *lines, CPendingOverlay *overlay)
  {
   m_lines = lines;
   m_overlay = overlay;
   ArrayResize(m_ov, 0);
   m_ovKey = "";
   m_ovOn = true;
   m_pv.Reset();
   m_raiseWanted = false;
   m_cfg = cfg;
   m_state = state;
   m_panel = panel;
   m_status = status;
   m_cmd = cmd;
   m_layout = layout;
   m_redraw = redraw;
   m_store = store;
   m_gw = gw;
   m_money = money;
   for(int i = 0; i < PB_COUNT; i++)
      m_tips[i] = m_cmd.Tooltip((EPanelButton)i, _Symbol);
   m_specAt = 0;
   m_idleAt = 0;
   m_riskAt = 0;
   m_housekeepAt = 0;
   m_refreshAt = 0;
   m_fitPending = false;
   m_chartW = 0;     // an EA keeps its objects across a timeframe change: measure and fit again
   m_chartH = 0;
   m_oneClick = -1;
   m_logDay = -1;
   m_houseFirst = true;
   CheckChartLook();
   ReadSpec();
  }

//+------------------------------------------------------------------+
//| 02 section 7.1 OnChartEvent.                                     |
//+------------------------------------------------------------------+
void CController::OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      EPanelButton b = PB_ADDLINE;
      if(CPanel::ButtonOf(sparam, b))
         Click(b);
      else
         if(CPanel::IsHide(sparam))
            ToggleHide();
         else
            if(CPanel::IsHandle(sparam))
              {
               m_panel.ReleaseHandle();
               m_redraw.Flush();
              }
      return;
     }
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      if(CPanel::IsRiskEdit(sparam))
         RiskEdited();
      return;
     }
   //--- a planning line was dropped (or its price typed in its properties dialog);
   //--- a line of a placed order's overlay was dropped: OP-16
   if(id == CHARTEVENT_OBJECT_DRAG || id == CHARTEVENT_OBJECT_CHANGE)
     {
      ELineRole role = LINEROLE_SL;
      ulong ticket = 0;
      if(CLines::RoleOf(sparam, role))
         LineDropped(role);
      else
         if(CPendingOverlay::Parse(sparam, ticket, role))
            OverlayDropped(ticket, role, id == CHARTEVENT_OBJECT_DRAG);
      return;
     }
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      if(m_panel.OnMouseMove((int)lparam, (int)dparam, (int)StringToInteger(sparam)))
         m_redraw.Flush();
      if(m_panel.TakeDrop())
        {
         m_state.panelX = m_panel.WantedX();
         m_state.panelY = m_panel.WantedY();
         m_state.MarkUiDirty();
         RD_LOG_INFO("Panel moved to x " + IntegerToString(m_state.panelX) + ", y " + IntegerToString(m_state.panelY));
         m_redraw.Flush();
        }
      return;
     }
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      bool look = CheckChartLook();
      bool moved = false;
      if(m_candle != NULL && m_candle.On())   // F-21: RD_CT is placed in pixels, follow a scroll or zoom at once
        {
         SQuote q;
         bool created = false;
         moved = m_candle.Update(CMarket::Quote(_Symbol, q) ? q.bid : 0.0, created);
         if(created)
            m_raiseWanted = true;
        }
      if(ChartSizeChanged() || look || moved)
        {
         m_redraw.Mark();
         m_redraw.Flush();
        }
      return;
     }
  }

//+------------------------------------------------------------------+
//| Chart settings that would hide the panel (ADR-021):              |
//| - "Chart on foreground" draws the price chart above every object |
//|   (candles over the buttons, over the SL/TP lines): switched off |
//|   while RiskDesk runs; App restores it when RiskDesk leaves.     |
//| - the One-Click Trading panel covers the top-left corner: the    |
//|   panel keeps out of it while it is shown.                       |
//| True if something changed.                                       |
//+------------------------------------------------------------------+
bool CController::CheckChartLook()
  {
   bool changed = false;
   if(ChartGetInteger(0, CHART_FOREGROUND) != 0)
     {
      ChartSetInteger(0, CHART_FOREGROUND, false);
      RD_LOG_INFO("Chart on foreground switched off: the panel and lines must be drawn above the price chart");
      changed = true;
     }
   int oneClick = (ChartGetInteger(0, CHART_SHOW_ONE_CLICK) != 0) ? 1 : 0;
   if(oneClick != m_oneClick)
     {
      m_oneClick = oneClick;
      if(oneClick == 1)
         m_panel.SetReserved(m_layout.TerminalPx(RD_LY_ONECLICK_W), m_layout.TerminalPx(RD_LY_ONECLICK_H));
      else
         m_panel.SetReserved(0, 0);
      RD_LOG_DEBUG(oneClick == 1 ? "One-Click Trading panel shown: the panel keeps out of the top-left corner" :
                   "One-Click Trading panel hidden");
      changed = true;
     }
   return changed;
  }

void CController::OnTimer()
  {
   Refresh();
  }

//+------------------------------------------------------------------+
//| Same light refresh as the timer; in the Strategy Tester also the |
//| button and Risk % polling (02 section 10).                       |
//+------------------------------------------------------------------+
void CController::OnTick()
  {
   if(RdIsTester())
     {
      for(int i = 0; i < PB_COUNT; i++)
         if(m_panel.ButtonPressed((EPanelButton)i))
            Click((EPanelButton)i);
      if(m_panel.HidePressed())
         ToggleHide();
      if(m_panel.RiskEditText() != m_panel.RiskShownText())
         RiskEdited();
     }
   if((uint)(GetTickCount() - m_refreshAt) >= RD_CTL_TICK_MIN_MS)
      Refresh();
  }

//+------------------------------------------------------------------+
//| 06 section 0 steps 1, 6, 7: guard, report, cleanup; then the     |
//| screenshot the command asked for, after the redraw (F-19).       |
//+------------------------------------------------------------------+
void CController::Click(const EPanelButton b)
  {
   m_panel.ReleaseButton(b);
   string name = CPanel::ButtonCaption(b);
   if(m_state.busy)
     {
      RD_LOG_INFO("Click on " + name + " ignored: another command is running");
      m_redraw.Flush();
      return;
     }
   uint now = GetTickCount();
   if(m_state.clicked[b] && (uint)(now - m_state.lastClickAt[b]) < (uint)m_cfg.clickCooldownMs)
     {
      RD_LOG_INFO("Click on " + name + " ignored: repeated within " + IntegerToString(m_cfg.clickCooldownMs) + " ms");
      m_redraw.Flush();
      return;
     }
   m_state.clicked[b] = true;
   m_state.lastClickAt[b] = now;
   RD_LOG_INFO("Click: " + name);

   SResult r;
   r.Reset();
   string why = DisabledWhy(b);
   if(why != "")
     {
      RdFail(r, name + " refused: " + why);
      Report(r);
      Refresh();
      return;
     }
   m_state.busy = true;
   m_state.busyButton = b;
   Refresh();
   m_cmd.Run(b, r);
   m_state.busy = false;
   m_state.busyButton = -1;
   // T-25: requests are synchronous, so a second click made while a trade was being sent
   // arrives only now; the cooldown counts from the end of the command as well.
   m_state.lastClickAt[b] = GetTickCount();
   if(m_cmd.TakeRaise())
      m_raiseWanted = true;
   m_pv.key = "";      // lines or positions may have changed
   m_ovKey = "";       // pending orders too (overlay labels)
   m_riskAt = 0;       // open risk read again (F-29)
   m_idleAt = 0;
   if(b != PB_SHOT)    // the camera reports where the file went
      Report(r);
   Refresh();
   TakeShot(r);
  }

//+------------------------------------------------------------------+
//| Rule R8: the status bar and one log line, same text.             |
//+------------------------------------------------------------------+
void CController::Report(const SResult &r)
  {
   m_status.Show(r.sev, r.message);
   if(r.sev == SEV_ERROR)
      RD_LOG_ERROR("Status: " + r.message);
   else
      if(r.sev == SEV_WARN)
         RD_LOG_WARN("Status: " + r.message);
      else
         RD_LOG_INFO("Status: " + r.message);
  }

//+------------------------------------------------------------------+
//| OP-12 "Closing 4/9...": a command that sends several requests    |
//| shows each step at once. Requests are synchronous, so this is    |
//| the only drawing while the command runs. Not logged: the gateway |
//| logs every request, and Report() logs the final status.          |
//+------------------------------------------------------------------+
void CController::Progress(const string text)
  {
   m_status.Show(SEV_OK, text);
   SQuote q;
   bool quoteOk = CMarket::Quote(_Symbol, q);
   SPanelModel m;
   BuildModel(m, q, quoteOk);
   m_status.Fill(m, m_panel.StatusWidth());
   m_panel.Render(m);
   m_redraw.Flush();
  }

//+------------------------------------------------------------------+
//| T-02: the field shows the value in use afterwards (the new one,  |
//| with 2 decimals, or the previous one after a refusal).           |
//+------------------------------------------------------------------+
void CController::RiskEdited()
  {
   string text = m_panel.RiskEditText();
   RD_LOG_INFO("Risk % field edited: \"" + text + "\"");
   SResult r;
   m_cmd.SetRisk(text, r);
   m_panel.ForgetRiskText();
   Report(r);
   Refresh();
  }

void CController::ToggleHide()
  {
   m_panel.ReleaseHide();
   m_state.hidden = !m_state.hidden;
   m_panel.SetCollapsed(m_state.hidden);
   m_state.MarkUiDirty();
   RD_LOG_INFO(m_state.hidden ? "Panel hidden" : "Panel shown");
   Refresh();
  }

//+------------------------------------------------------------------+
//| F-02 AC1: the account's saved Risk %, else InpDefaultRiskPct.    |
//+------------------------------------------------------------------+
void CController::LoadRisk(const long login)
  {
   double pct = 0.0;
   m_state.riskPct = m_cfg.defaultRiskPct;
   if(m_store.LoadRisk(login, pct))
     {
      double shown = NormalizeDouble(pct, 2);
      if(shown > 0.0 && shown <= m_cfg.maxRiskPerTradePct + RD_PCT_EPS)
        {
         m_state.riskPct = shown;
         RD_LOG_INFO("Risk % " + RdNum(shown, 2) + " restored for account " + IntegerToString(login));
        }
      else
         RD_LOG_WARN("Saved Risk % " + RdNum(pct, 4) + " of account " + IntegerToString(login) +
                     " is outside (0, " + RdNum(m_cfg.maxRiskPerTradePct, 2) + "] - using " +
                     RdNum(m_cfg.defaultRiskPct, 2));
     }
   m_state.riskLogin = login;
  }

void CController::CheckAccount()
  {
   long login = CAccountSpec::Login();
   if(login > 0 && login != m_state.riskLogin)
     {
      LoadRisk(login);
      m_riskAt = 0;
     }
  }

//+------------------------------------------------------------------+
//| 05 section 3: clamp at once when the chart size changes; the     |
//| auto-fit follows 300 ms after the last change.                   |
//+------------------------------------------------------------------+
bool CController::ChartSizeChanged()
  {
   int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(w == m_chartW && h == m_chartH)
      return false;
   bool first = (m_chartW == 0 && m_chartH == 0);
   m_chartW = w;
   m_chartH = h;
   m_panel.SetChartSize(w, h);
   if(first)
      ApplyFit();
   else
     {
      m_fitPending = true;
      m_chartAt = GetTickCount();
     }
   return true;
  }

void CController::ApplyFit()
  {
   m_fitPending = false;
   double before = m_layout.Scale();
   int colsBefore = m_layout.Columns();
   if(!m_layout.Fit(m_chartW, m_chartH))
      return;
   m_panel.Relayout();
   RD_LOG_INFO("Panel scale " + RdNum(before, 2) + " -> " + RdNum(m_layout.Scale(), 2) +
               (colsBefore != m_layout.Columns() ? ", " + IntegerToString(colsBefore) + " -> " : ", ") +
               (m_layout.Columns() == 2 ? "2 columns" : "1 column") + " (chart " +
               IntegerToString(m_chartW) + " x " + IntegerToString(m_chartH) + " px, Shape Size Scale " +
               RdNum(m_layout.UserScale(), 2) + (m_cfg.autoFitPanel ? ", auto-fit" : "") + ")");
  }

void CController::SaveUi()
  {
   SUiPersist ui;
   ui.Reset();
   ui.found = true;
   ui.x = m_state.panelX;
   ui.y = m_state.panelY;
   ui.hidden = m_state.hidden;
   ui.inputX = m_cfg.panelX;
   ui.inputY = m_cfg.panelY;
   m_store.SaveUi(ui);
   m_state.uiDirty = false;
  }

//+------------------------------------------------------------------+
void CController::Housekeeping()
  {
   uint now = GetTickCount();
   if(m_state.uiDirty && !m_panel.Dragging() && (uint)(now - m_state.uiDirtyAt) >= RD_CTL_UI_SAVE_MS)
      SaveUi();
   if(m_fitPending && (uint)(now - m_chartAt) >= RD_CTL_FIT_DEBOUNCE)
      ApplyFit();
   if(m_housekeepAt != 0 && (uint)(now - m_housekeepAt) < RD_CTL_HOUSEKEEP_MS)
      return;
   m_housekeepAt = now;
   CheckChartLook();
   ChartSizeChanged();
   //--- F-32: a new local day -> the daily files older than InpLogKeepDays go
   int day = (int)((long)TimeLocal() / RD_DAY_SEC);
   if(day != m_logDay)
     {
      m_logDay = day;
      if(m_cfg.logToFile && !RdIsTester())
         CLogger::PruneOld(m_cfg.logKeepDays);
     }
   if(!m_panel.ObjectsOk() && !m_panel.Dragging())
     {
      RD_LOG_WARN("Panel objects were missing (deleted from the chart?) - panel rebuilt");
      m_panel.Build();
     }
  }

//+------------------------------------------------------------------+
//| One refresh cycle (02 section 7.1 OnTimer).                      |
//+------------------------------------------------------------------+
void CController::Refresh()
  {
   uint now = GetTickCount();
   m_refreshAt = now;
   CheckAccount();
   if(!m_specOk || (uint)(now - m_specAt) >= RD_CTL_SPEC_MS)
      ReadSpec();
   SQuote q;
   bool quoteOk = CMarket::Quote(_Symbol, q);
   if(m_idleAt == 0 || (uint)(now - m_idleAt) >= RD_CTL_IDLE_MS)
     {
      m_idleAt = now;
      UpdateIdle(q, quoteOk);
     }
   //--- planning lines: manual deletion, preview, labels; the panel above new objects
   SyncLines();
   ComputePreview(q, quoteOk);
   // labels keep clear of the panel as it is shown now (ADR-024)
   m_lines.SetAvoid(m_panel.ShownX(), m_panel.ShownY(), m_layout.Width(), m_layout.ShownHeight(m_panel.Collapsed()),
                    m_layout.TerminalPx(RD_LY_LABEL_GAP));
   if(ApplyLabels())
      m_raiseWanted = true;
   if(SyncOverlay())   // F-22: placed pending orders
      m_raiseWanted = true;
   if(SyncExtras(q, quoteOk))   // F-21 candle time, F-20 closed-trade objects
      m_raiseWanted = true;
   if(m_raiseWanted && !m_panel.Dragging())
     {
      m_raiseWanted = false;
      m_panel.Raise();
     }
   SPanelModel m;
   BuildModel(m, q, quoteOk);
   m_status.Fill(m, m_panel.StatusWidth());
   m_panel.Render(m);
   Housekeeping();
   m_redraw.Flush();
  }

#include "ControllerModel.mqh"
#include "ControllerPreview.mqh"
#include "ControllerOverlay.mqh"

#endif // RD_APP_CONTROLLER_MQH
