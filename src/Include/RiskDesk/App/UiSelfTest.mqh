// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTest.mqh                                    |
//| Layer   : App, DEBUG builds only (compiled with RD_TEST_HOOKS;   |
//|           08-testing section 2, ADR-021)                         |
//| Purpose : unattended check of the panel (phase P3) on a real     |
//|           terminal: drives the same event handlers a user does   |
//|           (OBJECT_ENDEDIT, OBJECT_CLICK, MOUSE_MOVE, chart       |
//|           symbol/period changes), checks the results, saves      |
//|           chart screenshots and a report to                      |
//|           MQLx/Files/RiskDesk/uitest/, then removes itself and   |
//|           closes the terminal (build/run-uitest.ps1 starts it).  |
//|           Suites (the request file says which):                  |
//|           - panel (P3): T-01, T-02, T-20, T-21 (across two runs),|
//|             T-25, T-37, every button's status, hide, drag,       |
//|             clamp, text fit at scales 0.40-1.60 and every font   |
//|             preset, one and two columns (ADR-023). Never trades. |
//|           - trade / trade-basic (P4): the planning lines and the |
//|             Buy / Sell buttons with REAL orders on a DEMO        |
//|             account only (rule R13), own magic number, every     |
//|             test trade closed again: App/UiSelfTestTrade.mqh.    |
//|           - pending (P5): Set Pending, Del Pending, the overlay  |
//|             and dragging its lines (OP-16) with REAL pending     |
//|             orders far from the price, same safety rules:        |
//|             App/UiSelfTestPending*.mqh.                          |
//|           - manage (P6): Risk Free, Half Close, Chart Close and  |
//|             Full Close on REAL test positions, same safety       |
//|             rules, never touching anyone else's trades:          |
//|             App/UiSelfTestManage*.mqh.                           |
//|           - half: Half Close over the symbol's volume grid       |
//|             (index and FX grids of every broker), same safety    |
//|             rules: App/UiSelfTestHalf.mqh.                       |
//|           - extras (P7): candle time, closed-trade objects,      |
//|             screenshot names, cent display, log retention (T-31, |
//|             T-33, T-34), one test Buy with the same safety       |
//|             rules: App/UiSelfTestExtras.mqh.                     |
//|           - safety (ADR-031): rule R7 (SL cannot be attached,    |
//|             T-29), rule R9 / BC-14 (lost replies, T-35) and the  |
//|             MT5 filling fallback (BC-06) with REAL requests and  |
//|             a fault armed in the gateway: UiSelfTestSafety.mqh.  |
//|           Neither replaces T-24 (Windows DPI) or real clicks.    |
//| Safety : runs only when the runner left the request file         |
//|          RiskDesk/uitest.request (deleted at start), so a chart  |
//|          left in a profile never re-runs it; App points ui.ini / |
//|          acct_*.ini to the sandbox RiskDesk/uitest/store, so the |
//|          owner's saved panel state and Risk % are untouched.     |
//| Steps and checks: App/UiSelfTestSteps.mqh.                       |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTEST_MQH
#define RD_APP_UISELFTEST_MQH

#include "..\Domain\Types.mqh"
#include "..\Platform\Compat.mqh"
#include "..\Platform\AccountSpec.mqh"
#include "..\Platform\Market.mqh"
#include "..\Platform\Money.mqh"
#include "..\Platform\TradeGateway.mqh"
#include "..\Platform\History.mqh"
#include "..\Services\Logger.mqh"
#include "..\Services\Screenshot.mqh"
#include "..\Services\Persistence.mqh"
#include "..\UI\Theme.mqh"
#include "..\UI\Layout.mqh"
#include "..\UI\Widgets.mqh"
#include "..\UI\Panel.mqh"
#include "..\UI\StatusBar.mqh"
#include "..\UI\Lines.mqh"
#include "..\UI\PendingOverlay.mqh"
#include "Settings.mqh"
#include "State.mqh"
#include "Commands.mqh"
#include "Controller.mqh"

#define RD_UITEST_DIR     "RiskDesk\\uitest"
#define RD_UITEST_STEP_MS 400
#define RD_UITEST_MAGIC   772288    // trade suite: not the EA's magic, so the owner's RiskDesk trades never count
#define RD_UITEST_MAGIC2  772289    // manage suite: a "manual" trade (another magic) on the chart symbol
#define RD_UITEST_T28_S   90        // T-28: wait at most 90 s for the SL or TP to be hit
#define RD_UITEST_RF_S    180       // T-16 / T-30: wait at most 180 s for a position to be far enough in profit

// half suite: a test position before a Half Close click (App/UiSelfTestHalf.mqh)
struct SUiHalfPos
  {
   ulong             ticket;
   ESide             side;
   double            volume;
   double            open;
   double            sl;
   double            tp;
   int               units;           // volume in grid steps (min = step)
  };

class CUiSelfTest
  {
private:
   CSettings        *m_cfg;
   CState           *m_state;
   CTheme           *m_theme;
   CLayout          *m_layout;
   CPanel           *m_panel;
   CStatusBar       *m_status;
   CController      *m_ctl;
   CRdRedraw        *m_redraw;
   CPersistence     *m_store;
   CTradeGateway    *m_gw;
   CMoney           *m_money;
   CCommands        *m_cmd;
   CLines           *m_plan;            // the planning lines (the report text is m_lines)
   CPendingOverlay  *m_overlay;

   string            m_suite;           // "panel", "trade", "trade-basic", "pending", "manage", "half", "extras", "safety"
   bool              m_active;
   bool              m_closeOnDeinit;
   int               m_step;
   int               m_shot;
   uint              m_nextAt;
   uint              m_startAt;
   string            m_lines[];
   int               m_pass;
   int               m_fail;
   int               m_homeX, m_homeY;
   bool              m_scrollAtStart;
   string            m_lastShot;
   //--- T-20 bookkeeping (survives the OnDeinit/OnInit of a chart change)
   string            m_origSymbol;
   ENUM_TIMEFRAMES   m_origPeriod;
   ENUM_TIMEFRAMES   m_tfPeriod;
   string            m_otherSymbol;
   int               m_objCount;
   int               m_t20Lines;        // line + label objects of Add Line
   int               m_waits;
   int               m_t20X, m_t20Y;
   double            m_t20Risk;
   //--- T-21: what this run saved, checked by the next run
   int               m_saveX, m_saveY;
   //--- One-Click Trading as the chart had it (restored at the end)
   bool              m_oneClickWas;
   //--- trade suite (P4, App/UiSelfTestTrade.mqh)
   bool              m_tradeOk;         // demo account, a safe test lot exists: the trade steps run
   bool              m_full;            // "trade": every step; "trade-basic": T-03..T-07, T-09, T-05/06, T-28
   SSymbolSpec       m_ts;              // chart symbol
   double            m_dist;            // SL distance of the trade steps
   double            m_testRisk;        // Risk % of the trade steps
   string            m_pvLots;          // Lots field before the click
   ulong             m_ticket;
   int               m_cooldownWas;
   ESide             m_t28Side;
   double            m_t28Open, m_t28Sl, m_t28Risk, m_t28Vol;
   datetime          m_t28From;
   uint              m_t28Start;
   bool              m_t28Closed;
   string            m_permWhy;         // T-26: why the terminal/EA/account may not trade, "" = it may
   bool              m_marketClosed;    // T-27: the chart symbol is outside its trading sessions
   //--- ADR-024 label check: undone after the runner's window capture
   bool              m_labelWait;
   ELineRole         m_labelRole;
   bool              m_labelMoved;
   double            m_labelPriceWas;
   int               m_labelWantX, m_labelWantY;
   //--- pending suite (P5, App/UiSelfTestPending*.mqh)
   ulong             m_pendBuyStop;     // the T-13 Buy Stop that F-22 / T-39 work on
   ulong             m_pendTickets[];   // T-13 orders (T-15 deletes them)
   string            m_otherSymbol2;    // T-15: the second symbol with a test order
   ulong             m_otherTicket;
   //--- manage suite (P6, App/UiSelfTestManage*.mqh)
   bool              m_mgOthersSym;     // someone else's positions on the chart symbol: chart buttons in tool scope
   bool              m_mgOthersAcc;     // someone else's trades on the account: Full Close in tool scope
   string            m_mgSym2;          // other symbols for T-18 / T-19 ("" = none)
   string            m_mgSym3;
   ulong             m_mgBuy[];         // T-16: two buys and two sells
   ulong             m_mgSell[];
   ulong             m_mgMoved;         // T-16: the position Risk Free moved
   uint              m_mgWaitFrom;      // T-16 / T-30: start of the wait for enough profit
   ulong             m_mgT19[];         // T-19 positions
   ulong             m_mgOrder;         // T-19 pending order
   ulong             m_mgNet;           // T-30 netting position
   //--- half suite (App/UiSelfTestHalf.mqh)
   bool              m_hfOk;            // the cases can run on this symbol and account
   datetime          m_hfFrom;          // start of the current case (history window)
   string            m_hfTable;         // the splits of the run, for the summary line
   //--- extras suite (P7, App/UiSelfTestExtras.mqh)
   ENUM_TIMEFRAMES   m_exPeriod;        // the runner's timeframe (back at the end)
   ENUM_TIMEFRAMES   m_exWant;          // timeframe asked for
   long              m_exLeft;          // countdown seconds at the first reading
   uint              m_exAt;            // when it was read
   datetime          m_exTick;          // TimeCurrent() then
   ulong             m_exTicket;        // the closed test trade (F-20), 0 = none
   bool              m_exShiftWas;      // the chart's CHART_SHIFT at the start
   bool              m_exRightOf;       // the last ExCandle found RD_CT right of the candle

   void              Line(const string text);
   void              Check(const bool ok, const string id, const string detail);
   void              Shot(const string name);
   void              Edit(const string text);
   void              ClickObject(const string name);
   void              Mouse(const int x, const int y, const int buttons);
   void              Drag(const int dx, const int dy);
   int               Prop(const string name, const ENUM_OBJECT_PROPERTY_INTEGER prop) const;
   int               ChartW() const { return (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS); }
   int               ChartH() const { return (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0); }
   void              ApplyLook(const double scale, const bool autoFit, const EFontPreset preset, const EPanelColumns columns);
   void              CheckTextFits(const string where);
   void              CheckFitMath();
   void              CheckKeyValueFile();
   void              CheckInView(const string id);
   void              GlyphSheet(const string font, const bool show);
   void              Finish();
   string            FilePrefix() const;
   void              StepPanel(const uint now);
   static string     ReadSuite();

   void              StepInit();
   void              StepRisk();
   void              StepButtons();
   void              StepCooldownOver();
   void              StepHide();
   void              StepShow();
   void              StepDrag();
   void              StepClamp();
   void              StepHome();
   void              StepRestartCheck();
   void              StepTfChange();
   bool              StepTfCheck();
   bool              StepSymbolCheck();
   bool              StepBack();
   void              StepSaveState();
   void              StepSavedFiles();
   void              StepChartLookOn();
   void              StepChartLookCheck();
   void              StepChartLookCorner();
   void              RequestWindowCapture(const string name);
   bool              WindowCaptured();
   int               CountObjects(const string prefix) const;
   static string     ExpectPath() { return StoreDir() + "\\expect_restart.ini"; }
   // ChartScreenShot does not draw terminal overlays (One-Click Trading): the runner
   // captures the real window when this file appears, then deletes it.
   static string     CapturePath() { return RD_UITEST_DIR + "\\capture.request"; }

   //--- trade suite (App/UiSelfTestTrade.mqh)
   void              StepTrade(const uint now);
   void              TradeStart();
   void              TradeEnd();
   void              ClickButton(const EPanelButton b) { ClickObject(CPanel::ButtonName(b)); }
   void              DropLine(const ELineRole role, const double price);
   bool              FreshQuote(SQuote &q);
   int               TestPositions(SPosition &arr[]);
   bool              FindTestPosition(const ulong ticket, SPosition &p);
   ulong             StatusTicket() const;
   void              CloseTestTrades(const string why);
   double            ExpectedLoss(const ESide side, const double entry, const double sl);
   double            ExpectedLots(const ESide side, const double entry, const double sl, const double pct, double &raw);
   double            Base();
   void              SetTpMode(const ETpMode mode, const double rr);
   void              RestoreTp();
   bool              HasLook(const EPanelButton b, const EButtonLook look) const;
   string            Text(const string name) const { return ObjectGetString(0, name, OBJPROP_TEXT); }
   double            FarStop(const SQuote &q, const double pct);
   bool              PlaceStop(const ESide side, const double distFactor, SQuote &q, double &sl);
   bool              CheckOpened(const string id, const ESide side, const int before, const double sl, const double tpWanted,
                                 const double rr);
   void              TradeT03();
   void              CheckLabelBesidePanel(const ELineRole role);
   bool              LabelCheckRestore();
   void              TradeT03b();
   void              TradeT03c();
   void              TradeT04Buy();
   void              TradeT04Sell();
   void              TradeT04Risk();
   void              TradeT26();
   void              TradeT27();
   void              TradeT07();
   void              TradeT09();
   void              TradeT05();
   void              TradeT06();
   void              TradeT08a();
   void              TradeT08b();
   void              TradeT08c();
   void              TradeT11a();
   void              TradeT11b();
   void              TradeF16();
   void              TradeT12a();
   void              TradeT12b();
   void              TradeT25();
   void              TradeT28Open();
   bool              TradeT28Wait();
   void              TradeT28Check();
   void              TradeNet1();
   void              TradeNet2();

   //--- pending suite (App/UiSelfTestPending.mqh, UiSelfTestPendingMove.mqh)
   void              StepPending(const uint now);
   int               TestOrders(SOrder &arr[], const string symbol = "");
   bool              FindTestOrder(const ulong ticket, SOrder &o);
   bool              PendLines(const ESide side, const EOrderKind kind, const double factor, double &entry, double &sl);
   double            AutoTp(const ESide side, const double entry, const double sl, const double rr) const;
   bool              CheckPlaced(const string id, const ESide side, const EOrderKind kind, const int before, const double entry,
                                 const double sl, const double tpWanted);
   bool              OverlayDrawn(const ulong ticket, const SOrder &o, string &why);
   void              DropOverlay(const ulong ticket, const ELineRole role, const double price);
   double            OrderRisk(const SOrder &o);
   bool              HasMoney(const string text, const SAccountSpec &acc, const double amount) const;
   void              PendT13(const ESide side, const EOrderKind kind, const double factor);
   void              PendT14();
   void              PendRefusals();
   void              PendT08(const ETpMode mode);
   void              PendF22();
   void              PendT39a();
   void              PendT39b();
   void              PendT39c();
   void              PendT23();
   void              PendT15();
   void              PendNet();
   //--- manage suite (P6, App/UiSelfTestManage*.mqh)
   void              StepManage(const uint now);
   bool              MgIsTest(const long magic) const;
   int               MgOthers(const string symbol, const bool orders);
   void              MgScopes();
   void              MgStart();
   void              MgCleanup(const string why);
   double            MgDist(const SSymbolSpec &s, const SQuote &q) const;
   ulong             MgOpen(const string sym, const ESide side, const double lots, const long magic, double &price);
   string            MgPickSymbol(const string not1, const string not2);
   void              MgT16Tickets(ulong &t[]);
   void              MgSls(const ulong &t[], double &sl[]);
   bool              MgNotLoosened(const ulong &t[], const double &before[], string &why);
   double            MgPerTick(const ESide side, const double open);
   double            MgRfTarget(const SPosition &p, const SQuote &q);
   bool              MgRfReady(const SPosition &p, const SQuote &q, const double margin, SRiskFreeResult &rf);
   int               ManageScopeCount(const EPanelButton b);
   double            MgRisk(const ulong ticket);
   double            MgClosedPl(const ulong &t[], const datetime from, int &found);
   void              MgT16Open();
   bool              MgT16Wait(const uint now);
   void              MgT16Again();
   void              MgT17();
   void              MgT18();
   void              MgT19Open();
   void              MgT19Close();
   void              MgT30Open();
   bool              MgT30Wait(const uint now);
   //--- half suite (App/UiSelfTestHalf.mqh)
   void              StepHalf(const uint now);
   void              HfStart();
   int               HfExpectClose(const int units, const double pct) const;
   double            HfLots(const int units) const;
   double            HfDist(const SQuote &q) const;
   bool              HfAffordable(const string id, const int &units[]);
   ulong             HfOpen(const ESide side, const int units);
   void              HfHistory(double &vol, double &pl, SClosedTrade &ct[]);
   bool              HfFind(const SPosition &arr[], const ulong ticket, SPosition &p) const;
   ulong             HfNewTicket(const SPosition &before[], const SPosition &after[], const SUiHalfPos &was,
                                 const double restVol, SPosition &p) const;
   void              HfCase(const string id, const int &sides[], const int &units[], const double pct,
                            const EIndivisible indiv, const int clicks);
   bool              HfClick(const string id, SUiHalfPos &p[], const double pct, const EIndivisible indiv, string &split);
   void              HfNetMerged();
   //--- extras suite (App/UiSelfTestExtras.mqh)
   void              StepExtras(const uint now);
   void              ExStart();
   bool              ExTf(const ENUM_TIMEFRAMES tf);
   static long       ExParseCountdown(const string text, int &form);
   bool              ExCandle(const string id, long &left);
   void              ExBetweenTicks();
   void              ExCandleToggle();
   void              ExShift(const bool on);
   void              ExShiftCheck(const bool on);
   bool              ExShotNamed(const string path, const string action, const ulong ticket, const datetime t0,
                                 const datetime t1, string &want);
   void              ExCameraShot();
   void              ExChartShot(const string tf);
   void              ExBuyShot();
   bool              ExMakeObject(const string name, const ENUM_OBJECT type, const double p1, const double p2);
   void              ExClosedObjects();
   void              ExCent();
   void              ExLogs();
   void              ExEnd();
   //--- safety suite (ADR-031, App/UiSelfTestSafety.mqh)
   void              StepSafety(const uint now);
   long              SfLogMark() const;
   string            SfLogSince(const long mark) const;
   int               SfCountLines(const string text, const string a, const string b) const;
   string            SfLastFill(const string text) const;
   void              SfSettings(const bool closeIfStopFails);
   bool              SfBuy(const EGwFault fault, int &before, int &after, string &log);
   string            SfState(const int before, const int after) const;
   void              SfEnd(const string shot);
   void              SfSlAttach(const bool closeIfFails);
   void              SfReplyLost();
   void              SfSendLost();
   void              SfNeverAnswered();
   void              SfNotAdopted();
   void              SfFillFallback();

public:
                     CUiSelfTest();
   static string     RequestFile() { return "RiskDesk\\uitest.request"; }
   static bool       Requested() { return FileIsExist(RequestFile()); }
   // Sandbox for ui.ini / acct_*.ini during the self-test (App points CPersistence here).
   static string     StoreDir() { return RD_UITEST_DIR + "\\store"; }
   // The trade suites keep their own sandbox, so they never disturb the panel suite's T-21 chain.
   static string     StoreDirFor(const string suite) { return (suite == "panel") ? StoreDir() : RD_UITEST_DIR + "\\store_trade"; }
   static string     RequestedSuite() { return ReadSuite(); }
   string            Suite() const { return m_suite; }
   void              Start(CSettings *cfg, CState *state, CTheme *theme, CLayout *layout, CPanel *panel,
                           CStatusBar *status, CController *ctl, CRdRedraw *redraw, CPersistence *store,
                           CTradeGateway *gw, CMoney *money, CCommands *cmd, CLines *lines, CPendingOverlay *overlay);
   bool              Active() const { return m_active; }
   void              Step();
   void              OnDeinit(const int reason);
  };

//+------------------------------------------------------------------+
CUiSelfTest::CUiSelfTest()
  {
   m_active = false;
   m_closeOnDeinit = false;
   m_step = 0;
   m_shot = 0;
   m_nextAt = 0;
   m_startAt = 0;
   m_pass = 0;
   m_fail = 0;
   m_homeX = 0;
   m_homeY = 0;
   m_scrollAtStart = true;
   m_lastShot = "";
   m_origSymbol = "";
   m_origPeriod = PERIOD_CURRENT;
   m_tfPeriod = PERIOD_CURRENT;
   m_otherSymbol = "";
   m_objCount = 0;
   m_t20Lines = 0;
   m_waits = 0;
   m_t20X = 0;
   m_t20Y = 0;
   m_t20Risk = 0.0;
   m_saveX = 0;
   m_saveY = 0;
   m_oneClickWas = false;
   m_suite = "panel";
   m_gw = NULL;
   m_money = NULL;
   m_cmd = NULL;
   m_plan = NULL;
   m_tradeOk = false;
   m_full = true;
   m_dist = 0.0;
   m_testRisk = 0.0;
   m_pvLots = "";
   m_ticket = 0;
   m_cooldownWas = 0;
   m_t28Side = SIDE_BUY;
   m_t28Open = 0.0;
   m_t28Sl = 0.0;
   m_t28Risk = 0.0;
   m_t28Vol = 0.0;
   m_t28From = 0;
   m_t28Start = 0;
   m_t28Closed = false;
   m_permWhy = "";
   m_marketClosed = false;
   m_labelWait = false;
   m_labelRole = LINEROLE_SL;
   m_labelMoved = false;
   m_labelPriceWas = 0.0;
   m_labelWantX = 0;
   m_labelWantY = 0;
   m_overlay = NULL;
   m_pendBuyStop = 0;
   m_otherSymbol2 = "";
   m_otherTicket = 0;
   m_mgOthersSym = true;   // tool scope until MgStart has looked
   m_mgOthersAcc = true;
   m_mgSym2 = "";
   m_mgSym3 = "";
   m_mgMoved = 0;
   m_mgWaitFrom = 0;
   m_mgOrder = 0;
   m_mgNet = 0;
   m_hfOk = false;
   m_hfFrom = 0;
   m_hfTable = "";
   m_exPeriod = PERIOD_CURRENT;
   m_exWant = PERIOD_CURRENT;
   m_exLeft = -1;
   m_exAt = 0;
   m_exTick = 0;
   m_exTicket = 0;
   m_exShiftWas = false;
   m_exRightOf = true;
  }

//+------------------------------------------------------------------+
//| The request file says which suite: "suite=trade" etc. (written   |
//| by build/run-uitest.ps1 -Suite); anything else is the panel.     |
//+------------------------------------------------------------------+
string CUiSelfTest::ReadSuite()
  {
   string suite = "panel";
   int h = FileOpen(RequestFile(), FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
      return suite;
   while(!FileIsEnding(h))
     {
      string line = RdTrim(FileReadString(h));
      if(StringFind(line, "suite=") == 0)
         suite = RdTrim(StringSubstr(line, 6));
     }
   FileClose(h);
   if(suite != "trade" && suite != "trade-basic" && suite != "pending" && suite != "manage" && suite != "half" &&
      suite != "extras" && suite != "safety")
      suite = "panel";
   return suite;
  }

void CUiSelfTest::Start(CSettings *cfg, CState *state, CTheme *theme, CLayout *layout, CPanel *panel,
                        CStatusBar *status, CController *ctl, CRdRedraw *redraw, CPersistence *store,
                        CTradeGateway *gw, CMoney *money, CCommands *cmd, CLines *lines, CPendingOverlay *overlay)
  {
   m_overlay = overlay;
   ArrayResize(m_pendTickets, 0);
   m_gw = gw;
   m_money = money;
   m_cmd = cmd;
   m_plan = lines;
   m_suite = ReadSuite();
   m_full = (m_suite == "trade");
   m_cfg = cfg;
   m_state = state;
   m_theme = theme;
   m_layout = layout;
   m_panel = panel;
   m_status = status;
   m_ctl = ctl;
   m_redraw = redraw;
   m_store = store;
   FileDelete(RequestFile());
   FolderCreate(RD_UITEST_DIR);
   FolderCreate(StoreDirFor(m_suite));
   // the main checks expect the top-left corner free; the One-Click panel gets its own steps
   m_oneClickWas = ChartGetInteger(0, CHART_SHOW_ONE_CLICK) != 0;
   ChartSetInteger(0, CHART_SHOW_ONE_CLICK, false);
   m_active = true;
   m_step = 0;
   m_shot = 0;
   m_startAt = GetTickCount();
   m_nextAt = m_startAt + 2500;
   ArrayResize(m_lines, 0);
   m_pass = 0;
   m_fail = 0;
   m_scrollAtStart = ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0;
   RD_LOG_WARN("TEST: self-test '" + m_suite + "' started (debug build); the terminal closes when it ends");
  }

// <PLATFORM>_<login>_... ; the trade and pending suites add the symbol (one run per symbol)
string CUiSelfTest::FilePrefix() const
  {
   string p = RD_UITEST_DIR + "\\" + RD_PLATFORM + "_" + IntegerToString(CAccountSpec::Login());
   if(m_suite == "pending" || m_suite == "manage" || m_suite == "half" || m_suite == "extras" || m_suite == "safety")
      p += "_" + m_suite + "_" + CScreenshot::Sanitize(_Symbol);
   else
      if(m_suite != "panel")
         p += "_trade_" + CScreenshot::Sanitize(_Symbol);
   return p;
  }

void CUiSelfTest::Line(const string text)
  {
   int n = ArraySize(m_lines);
   ArrayResize(m_lines, n + 1);
   m_lines[n] = text;
   RD_LOG_INFO("TEST " + text);
  }

void CUiSelfTest::Check(const bool ok, const string id, const string detail)
  {
   if(ok)
      m_pass++;
   else
      m_fail++;
   Line((ok ? "PASS " : "FAIL ") + id + ": " + detail);
  }

void CUiSelfTest::Shot(const string name)
  {
   m_ctl.Refresh();
   ChartRedraw(0);
   m_shot++;
   string file = FilePrefix() + "_" + StringFormat("%02d", m_shot) + "_" + name + ".png";
   // ChartScreenShot draws the whole chart, price and time scales included, into the
   // size asked for: ask for more than the chart area so nothing of it is covered.
   // Not on a chart with fewer bars than its width (a short W1 history): MT4 build 1492
   // froze there (ADR-027); the chart's own size, as CScreenshot takes it, works.
   int w = ChartW() + 100;
   int h = ChartH() + 40;
   int align = ALIGN_LEFT;
   if(iBars(_Symbol, PERIOD_CURRENT) <= (int)ChartGetInteger(0, CHART_WIDTH_IN_BARS) + 20)
     {
      w = ChartW();
      h = ChartH();
      align = ALIGN_RIGHT;
     }
   bool ok = ChartScreenShot(0, file, w, h, (ENUM_ALIGN_MODE)align);
   Line((ok ? "SHOT " : "SHOT FAILED ") + file);
   m_lastShot = file;
  }

int CUiSelfTest::Prop(const string name, const ENUM_OBJECT_PROPERTY_INTEGER prop) const
  {
   return (int)ObjectGetInteger(0, name, prop);
  }

// What the terminal does when the user types into the field and presses Enter.
void CUiSelfTest::Edit(const string text)
  {
   string name = "RD_E_RISK";
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   long l = 0;
   double d = 0.0;
   m_ctl.OnChartEvent(CHARTEVENT_OBJECT_ENDEDIT, l, d, name);
  }

// A click: the terminal sets the button state, then sends OBJECT_CLICK.
void CUiSelfTest::ClickObject(const string name)
  {
   if((ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_BUTTON)
      ObjectSetInteger(0, name, OBJPROP_STATE, true);
   long l = 0;
   double d = 0.0;
   m_ctl.OnChartEvent(CHARTEVENT_OBJECT_CLICK, l, d, name);
  }

void CUiSelfTest::Mouse(const int x, const int y, const int buttons)
  {
   long l = x;
   double d = y;
   string flags = IntegerToString(buttons);
   m_ctl.OnChartEvent(CHARTEVENT_MOUSE_MOVE, l, d, flags);
  }

// Press on the handle's centre, move by (dx, dy) in three moves, release.
void CUiSelfTest::Drag(const int dx, const int dy)
  {
   int hx = Prop("RD_P_HANDLE", OBJPROP_XDISTANCE) + Prop("RD_P_HANDLE", OBJPROP_XSIZE) / 2;
   int hy = Prop("RD_P_HANDLE", OBJPROP_YDISTANCE) + Prop("RD_P_HANDLE", OBJPROP_YSIZE) / 2;
   Mouse(hx, hy, 0);
   Mouse(hx, hy, 1);
   Mouse(hx + dx / 3, hy + dy / 3, 1);
   Mouse(hx + 2 * dx / 3, hy + 2 * dy / 3, 1);
   Mouse(hx + dx, hy + dy, 1);
   Mouse(hx + dx, hy + dy, 0);
  }

//+------------------------------------------------------------------+
//| Scale / auto-fit / font preset, as Init would set them.          |
//+------------------------------------------------------------------+
void CUiSelfTest::ApplyLook(const double scale, const bool autoFit, const EFontPreset preset, const EPanelColumns columns)
  {
   m_theme.Configure(preset, m_cfg.fontSize, m_cfg.colorBg, m_cfg.colorSystemBorder, m_cfg.colorButtonBorder,
                     m_cfg.colorText, m_cfg.colorPendingInfo, m_cfg.colorSpread);
   m_layout.Configure(scale, autoFit, columns, RdTerminalDpi(), m_cfg.fontSize, m_theme.fontBody, m_theme.fontTitle);
   m_layout.Fit(ChartW(), ChartH());
   m_panel.Relayout();
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| One step per timer event (RD_UITEST_STEP_MS apart). A waiting    |
//| step returns false and runs again on the next event.             |
//+------------------------------------------------------------------+
void CUiSelfTest::Step()
  {
   if(!m_active)
      return;
   uint now = GetTickCount();
   if((int)(now - m_nextAt) < 0)
      return;
   m_nextAt = now + RD_UITEST_STEP_MS;
   if(m_suite == "panel")
      StepPanel(now);
   else
      if(m_suite == "pending")
         StepPending(now);
      else
         if(m_suite == "manage")
            StepManage(now);
         else
            if(m_suite == "half")
               StepHalf(now);
            else
               if(m_suite == "extras")
                  StepExtras(now);
               else
                  if(m_suite == "safety")
                     StepSafety(now);
                  else
                     StepTrade(now);
  }

//+------------------------------------------------------------------+
//| The panel suite (P3).                                            |
//+------------------------------------------------------------------+
void CUiSelfTest::StepPanel(const uint now)
  {
   double scales[] = {0.40, 0.70, 1.00, 1.30, 1.60};
   double scales2[] = {0.40, 1.00, 1.60};
   int s0 = 10;                         // first scale step, one column
   int c0 = s0 + ArraySize(scales);     // two columns (ADR-023)
   int f0 = c0 + ArraySize(scales2);    // first font step
   int g0 = f0 + 6;                     // glyph sheets (Wingdings, Webdings), clean-up
   int t20 = g0 + 3;                    // T-20: timeframe, symbol, back
   int look = t20 + 4;                  // One-Click panel + chart on foreground
   int last = look + 4;                 // auto-fit on this chart, T-21 save, T-21 files, end
   bool done = true;

   if(m_step == 0)
     {
      SQuote q;
      if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
         return;   // wait for a first quote, at most 15 s
      StepInit();
     }
   else if(m_step == 1)
      StepRisk();
   else if(m_step == 2)
      StepButtons();
   else if(m_step == 3)
     {
      m_nextAt = now + (uint)m_cfg.clickCooldownMs + 100;
      m_ctl.Refresh();
     }
   else if(m_step == 4)
      StepCooldownOver();
   else if(m_step == 5)
      StepHide();
   else if(m_step == 6)
      StepShow();
   else if(m_step == 7)
      StepDrag();
   else if(m_step == 8)
      StepClamp();
   else if(m_step == 9)
      StepHome();
   else if(m_step >= s0 && m_step < c0)
     {
      double s = scales[m_step - s0];
      ApplyLook(s, false, m_cfg.fontPreset, PANEL_COLUMNS_ONE);
      CheckTextFits("scale " + RdNum(s, 2));
      Shot("scale_" + StringFormat("%03d", (int)MathRound(s * 100)));
     }
   else if(m_step >= c0 && m_step < f0)
     {
      double s = scales2[m_step - c0];
      ApplyLook(s, false, m_cfg.fontPreset, PANEL_COLUMNS_TWO);
      CheckTextFits("2 columns, scale " + RdNum(s, 2));
      Shot("cols2_scale_" + StringFormat("%03d", (int)MathRound(s * 100)));
     }
   else if(m_step >= f0 && m_step < g0)
     {
      EFontPreset p = (EFontPreset)(m_step - f0);
      ApplyLook(1.0, false, p, PANEL_COLUMNS_ONE);
      CheckTextFits(CTheme::FontName(p));
      Shot("font_" + CTheme::FontName(p));
     }
   else if(m_step == g0 || m_step == g0 + 1)
     {
      string font = (m_step == g0) ? "Wingdings" : "Webdings";
      ApplyLook(1.0, false, m_cfg.fontPreset, PANEL_COLUMNS_ONE);
      m_panel.SetCollapsed(true);
      GlyphSheet(font, true);
      Shot("glyphs_" + font);
     }
   else if(m_step == g0 + 2)
     {
      GlyphSheet("", false);
      m_panel.SetCollapsed(m_state.hidden);
      m_ctl.Refresh();
     }
   else if(m_step == t20)
      StepTfChange();
   else if(m_step == t20 + 1)
      done = StepTfCheck();
   else if(m_step == t20 + 2)
      done = StepSymbolCheck();
   else if(m_step == t20 + 3)
      done = StepBack();
   else if(m_step == look)
      StepChartLookOn();
   else if(m_step == look + 1)
      StepChartLookCheck();
   else if(m_step == look + 2)
      done = WindowCaptured();
   else if(m_step == look + 3)
      StepChartLookCorner();
   else if(m_step == last)
     {
      ApplyLook(1.6, true, m_cfg.fontPreset, m_cfg.panelColumns);
      Check(m_layout.Scale() <= 1.6 + 1e-9 && (m_layout.Height() <= ChartH() - RD_LY_FIT_MARGIN ||
            MathAbs(m_layout.Scale() - RD_LY_MIN_SCALE) < 1e-9), "T-37 this chart",
            "Shape Size Scale 1.60 + auto-fit on a " + IntegerToString(ChartH()) +
            " px chart -> scale " + RdNum(m_layout.Scale(), 2) + ", panel " +
            IntegerToString(m_layout.Height()) + " px");
      CheckInView("T-37 in view");
      CheckTextFits("auto-fit 1.60");
      Shot("autofit_160");
     }
   else if(m_step == last + 1)
      StepSaveState();
   else if(m_step == last + 2)
      StepSavedFiles();
   else
     {
      CheckFitMath();
      CheckKeyValueFile();
      Finish();
     }
   if(done)
      m_step++;
  }

//+------------------------------------------------------------------+
//| Report, restore the inputs' look, remove the EA from the chart   |
//| (no chart is closed: the runner's chart is left as the terminal  |
//| keeps it); OnDeinit then closes the terminal.                    |
//+------------------------------------------------------------------+
void CUiSelfTest::Finish()
  {
   ApplyLook(m_cfg.scale, m_cfg.autoFitPanel, m_cfg.fontPreset, m_cfg.panelColumns);
   ChartSetInteger(0, CHART_SHOW_ONE_CLICK, m_oneClickWas);
   Line("SUMMARY " + IntegerToString(m_pass) + " passed, " + IntegerToString(m_fail) + " failed");
   string file = FilePrefix() + "_report.txt";
   int h = FileOpen(file, FILE_WRITE | FILE_TXT | FILE_ANSI, '\t', CP_UTF8);
   if(h != INVALID_HANDLE)
     {
      for(int i = 0; i < ArraySize(m_lines); i++)
         FileWriteString(h, m_lines[i] + "\r\n");
      FileClose(h);
     }
   m_active = false;
   m_closeOnDeinit = true;
   RD_LOG_WARN("TEST: self-test finished (" + IntegerToString(m_pass) + " passed, " + IntegerToString(m_fail) +
               " failed); removing RiskDesk from this chart and closing the terminal");
   ExpertRemove();   // OnDeinit(REASON_PROGRAM) deletes the objects, then closes the terminal
  }

void CUiSelfTest::OnDeinit(const int reason)
  {
   if(m_closeOnDeinit)
     {
      m_closeOnDeinit = false;
      TerminalClose(0);
     }
  }

#include "UiSelfTestSteps.mqh"
#include "UiSelfTestTrade.mqh"
#include "UiSelfTestPending.mqh"
#include "UiSelfTestPendingMove.mqh"
#include "UiSelfTestManage.mqh"
#include "UiSelfTestHalf.mqh"
#include "UiSelfTestExtras.mqh"
#include "UiSelfTestSafety.mqh"

#endif // RD_APP_UISELFTEST_MQH
