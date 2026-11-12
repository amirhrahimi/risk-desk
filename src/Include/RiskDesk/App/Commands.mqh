//+------------------------------------------------------------------+
//| RiskDesk - App/Commands.mqh                                      |
//| Layer   : App                                                    |
//| Purpose : one function per user action (06-trade-operations).    |
//|           Each ends with an SResult whose message is the status  |
//|           text (rule R8); the Controller shows and logs it, then |
//|           takes the screenshot the command asked for (F-19).     |
//|           This file: dispatch, Risk % (F-02), the line commands  |
//|           Add Line (OP-01), Delete Line (OP-02), Add Pend Line   |
//|           (OP-05), the camera button (OP-14), confirmations      |
//|           (F-28, BC-10) and the button tooltips.                 |
//|           Buy / Sell (OP-03/04): App/CommandsTrade.mqh.          |
//|           Set Pending (OP-07), Del Pending (OP-08) and moving a  |
//|           placed order by its overlay line (OP-16):              |
//|           App/CommandsPending.mqh.                               |
//| Status  : P5. The management buttons (P6) answer amber "not     |
//|           implemented yet" with the phase that brings them.      |
//+------------------------------------------------------------------+
#ifndef RD_APP_COMMANDS_MQH
#define RD_APP_COMMANDS_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "..\Domain\PriceMath.mqh"
#include "..\Domain\RiskMath.mqh"
#include "..\Domain\Validators.mqh"
#include "..\Domain\Planner.mqh"
#include "..\Domain\RiskBudget.mqh"
#include "..\Platform\Compat.mqh"
#include "..\Platform\SymbolSpec.mqh"
#include "..\Platform\AccountSpec.mqh"
#include "..\Platform\Market.mqh"
#include "..\Platform\Money.mqh"
#include "..\Platform\TradeGateway.mqh"
#include "..\Services\Logger.mqh"
#include "..\Services\Persistence.mqh"
#include "..\UI\Theme.mqh"
#include "..\UI\Panel.mqh"
#include "..\UI\Lines.mqh"
#include "Settings.mqh"
#include "State.mqh"

#define RD_CONFIRM_ASK  0   // show the dialog
#define RD_CONFIRM_YES  1   // debug builds only: answered by the self-test
#define RD_CONFIRM_NO   2

class CCommands
  {
private:
   CSettings        *m_cfg;
   CState           *m_state;
   CPersistence     *m_store;
   CTradeGateway    *m_gw;
   CMoney           *m_money;
   CLines           *m_lines;
   bool              m_raise;          // chart objects were created: the panel goes on top again
   string            m_shotAction;     // screenshot the last command asked for, "" = none
   ulong             m_shotTicket;
   string            m_lastConfirm;    // text of the last confirmation asked
   int               m_testConfirm;    // RD_CONFIRM_*; only a debug build changes it

   string            RiskBaseText() const;
   bool              SpecQuote(const string what, SSymbolSpec &s, SQuote &q, SResult &r);
   bool              AddLine(SResult &r);
   bool              AddPendLine(SResult &r);
   bool              PlaceTpAgain(const string what, const SSymbolSpec &s, const SQuote &q, const SPlanSettings &p,
                                  SResult &r);
   bool              DeleteLine(SResult &r);
   bool              CameraShot(SResult &r);
   bool              Confirm(const string caption, const string text);
   void              AskShot(const string action, const ulong ticket);
   string            LevelsText(const SSymbolSpec &s, const double sl, const double tp, const bool autoTp) const;

   //--- App/CommandsTrade.mqh (OP-03/04)
   bool              OpenMarket(const ESide side, SResult &r);
   bool              NettingPosition(SPosition &p, bool &found, SResult &r);
   bool              SameSideVolume(const ESide side, double &volume, SResult &r);
   bool              CheckBudget(const SAccountSpec &acc, const SPlanSettings &p, const ulong replaced, const double added,
                                 const double tradeRisk, SBudgetResult &bud, SResult &r);
   bool              MergedRisk(const SSymbolSpec &s, const SAccountSpec &acc, const SPlanSettings &p, const SPosition &net,
                                const STradePlan &plan, double &risk, SResult &r);
   bool              CheckMargin(const SSymbolSpec &s, const ESide side, const SAccountSpec &acc, const double price,
                                 double &lots, string &notes, SResult &r);
   bool              OppositeNetting(const string name, const ESide side, const SSymbolSpec &s, const SAccountSpec &acc,
                                     const SPlanSettings &p, STradePlan &plan, const SLotResult &lot, const SPosition &net,
                                     string notes, SResult &r);
   bool              Opened(const string name, const ESide side, const SSymbolSpec &s, const SAccountSpec &acc,
                            const SPlanSettings &p, const STradePlan &plan, const STradeOutcome &out, string notes,
                            SResult &r);
   void              LinesDone();

   //--- App/CommandsPending.mqh (OP-07, OP-08, OP-16)
   bool              SetPending(SResult &r);
   bool              Placed(const string order, const SSymbolSpec &s, const SAccountSpec &acc, const STradePlan &plan,
                            const STradeOutcome &out, string notes, SResult &r);
   bool              DelPending(SResult &r);
   static bool       SameLevel(const SSymbolSpec &s, const double a, const double b);

public:
                     CCommands();
   void              Init(CSettings *cfg, CState *state, CPersistence *store, CTradeGateway *gw, CMoney *money,
                          CLines *lines);

   bool              SetRisk(const string text, SResult &r);
   bool              Run(const EPanelButton b, SResult &r);
   bool              MoveOrder(const ulong ticket, const ELineRole role, const double dropped, SResult &r);
   bool              TakeRaise();
   bool              TakeShot(string &action, ulong &ticket);
   string            LastConfirm() const { return m_lastConfirm; }
#ifdef RD_TEST_HOOKS
   void              SetTestConfirm(const int answer) { m_testConfirm = answer; }
#endif

   string            Tooltip(const EPanelButton b, const string symbol) const;
   string            RiskTooltip() const;
   static string     Phase(const EPanelButton b);
   static bool       Implemented(const EPanelButton b);
  };

//+------------------------------------------------------------------+
CCommands::CCommands()
  {
   m_cfg = NULL;
   m_state = NULL;
   m_store = NULL;
   m_gw = NULL;
   m_money = NULL;
   m_lines = NULL;
   m_raise = false;
   m_shotAction = "";
   m_shotTicket = 0;
   m_lastConfirm = "";
   m_testConfirm = RD_CONFIRM_ASK;
  }

void CCommands::Init(CSettings *cfg, CState *state, CPersistence *store, CTradeGateway *gw, CMoney *money, CLines *lines)
  {
   m_cfg = cfg;
   m_state = state;
   m_store = store;
   m_gw = gw;
   m_money = money;
   m_lines = lines;
  }

string CCommands::RiskBaseText() const
  {
   if(m_cfg.riskBase == RISKBASE_EQUITY)
      return "equity";
   if(m_cfg.riskBase == RISKBASE_MIN_BAL_EQ)
      return "the lower of balance and equity";
   return "balance";
  }

//+------------------------------------------------------------------+
//| F-02 / T-02: the Risk % field was edited. Valid -> used, shown   |
//| with 2 decimals and saved for this account; invalid -> the       |
//| caller shows the previous value again (r is a refusal).          |
//+------------------------------------------------------------------+
bool CCommands::SetRisk(const string text, SResult &r)
  {
   double pct = 0.0;
   if(!CValidators::ParseRiskPct(text, m_cfg.maxRiskPerTradePct, pct, r))
     {
      r.message = "Risk % not changed: " + r.message + " - still " + RdFormatPct(m_state.riskPct);
      return false;
     }
   bool changed = MathAbs(pct - m_state.riskPct) > 1e-9;
   m_state.riskPct = pct;
   string text2 = "Risk set to " + RdFormatPct(pct) + " of " + RiskBaseText() + " per trade";
   if(m_store.Enabled() && m_state.riskLogin > 0 && changed && !m_store.SaveRisk(m_state.riskLogin, pct))
      return RdWarn(r, text2 + " (not saved: cannot write " + m_store.AccountPath(m_state.riskLogin) + ")");
   return RdOk(r, text2);
  }

//+------------------------------------------------------------------+
//| 06 section 0 steps 2-6 of the clicked button. The Controller has |
//| done the guard (busy, cooldown) and does the cleanup.            |
//+------------------------------------------------------------------+
bool CCommands::Run(const EPanelButton b, SResult &r)
  {
   r.Reset();
   m_raise = false;
   m_shotAction = "";
   m_shotTicket = 0;
   switch(b)
     {
      case PB_ADDLINE:
         return AddLine(r);
      case PB_DELLINE:
         return DeleteLine(r);
      case PB_BUY:
         return OpenMarket(SIDE_BUY, r);
      case PB_SELL:
         return OpenMarket(SIDE_SELL, r);
      case PB_ADDPEND:
         return AddPendLine(r);
      case PB_SETPEND:
         return SetPending(r);
      case PB_DELPEND:
         return DelPending(r);
      case PB_SHOT:
         return CameraShot(r);
      default:
         break;
     }
   return RdWarn(r, CPanel::ButtonCaption(b) + ": not implemented yet (coming in phase " + Phase(b) + ")");
  }

bool CCommands::TakeRaise()
  {
   bool raise = m_raise;
   m_raise = false;
   return raise;
  }

bool CCommands::TakeShot(string &action, ulong &ticket)
  {
   action = m_shotAction;
   ticket = m_shotTicket;
   m_shotAction = "";
   m_shotTicket = 0;
   return action != "";
  }

void CCommands::AskShot(const string action, const ulong ticket)
  {
   m_shotAction = action;
   m_shotTicket = ticket;
  }

//+------------------------------------------------------------------+
//| PF-2 / PF-3: fresh spec (BC-02 sanity) and quote.                |
//+------------------------------------------------------------------+
bool CCommands::SpecQuote(const string what, SSymbolSpec &s, SQuote &q, SResult &r)
  {
   SResult sr;
   if(!CSymbolSpec::Read(_Symbol, s, sr))
      return RdFail(r, what + " refused: " + sr.message);
   if(!CMarket::Quote(_Symbol, q))
      return RdFail(r, what + " refused: no quote for " + _Symbol + " - market closed, or the symbol is not in Market Watch");
   SResult qr;
   if(!CValidators::QuoteOk(q, s, qr))
      return RdFail(r, what + " refused: " + qr.message);
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| OP-01 Add Line (F-04): SL line (+ TP line in Manual TP line      |
//| mode) at the default placement; pending lines are replaced;      |
//| market lines already there are left alone (a deleted manual TP   |
//| line is put back).                                               |
//+------------------------------------------------------------------+
bool CCommands::AddLine(SResult &r)
  {
   const string what = "Add Line";
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(what, s, q, r))
      return false;
   SPlanSettings p;
   m_cfg.Plan(p);
   if(m_state.lineMode == LINES_MARKET)
     {
      if(m_cfg.tpMode == TPMODE_MANUAL_LINE && !m_lines.Exists(LINEROLE_TP))
         return PlaceTpAgain(what, s, q, p, r);
      return RdWarn(r, "Lines already on chart - drag them, or click Delete Line first");
     }
   double lo = 0.0;
   double hi = 0.0;
   CLines::VisibleRange(lo, hi);
   SLinePlacement pl;
   SResult pr;
   if(!CPlanner::MarketLines(q, lo, hi, m_cfg.defaultOffsetPct, s, p, pl, pr))
      return RdFail(r, what + " refused: " + pr.message);
   string note = "";
   if(m_state.lineMode == LINES_PENDING)
     {
      CLines::DeleteAll();
      note = "Pending lines replaced by market lines: ";
     }
   m_lines.Place(LINEROLE_SL, pl.sl);
   if(pl.tp > 0.0)
     {
      m_lines.Place(LINEROLE_TP, pl.tp);
      m_lines.SetTpFree(false);
     }
   m_state.lineMode = LINES_MARKET;
   m_raise = true;
   RD_LOG_INFO("[OP-01] SL line at " + RdFormatPrice(s, pl.sl) + (pl.tp > 0.0 ? ", TP line at " + RdFormatPrice(s, pl.tp) : "") +
               " (Bid " + RdFormatPrice(s, q.bid) + ", distance " + RdFormatPrice(s, pl.offset) + " = " +
               RdNum(m_cfg.defaultOffsetPct, 1) + " % of " + (pl.range > 0.0 ? "the visible range" : "0.5 % of the price") + ")");
   return RdOk(r, note + "SL line at " + RdFormatPrice(s, pl.sl) +
               (pl.tp > 0.0 ? ", TP line at " + RdFormatPrice(s, pl.tp) : "") +
               " - drag the SL to your stop, then Buy or Sell");
  }

//+------------------------------------------------------------------+
//| OP-05 Add Pend Line (F-07): Entry + SL (+ TP) lines; market      |
//| lines are replaced. Set Pending places the order (OP-07).        |
//+------------------------------------------------------------------+
bool CCommands::AddPendLine(SResult &r)
  {
   const string what = "Add Pend Line";
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(what, s, q, r))
      return false;
   SPlanSettings p;
   m_cfg.Plan(p);
   if(m_state.lineMode == LINES_PENDING)
     {
      if(m_cfg.tpMode == TPMODE_MANUAL_LINE && !m_lines.Exists(LINEROLE_TP))
         return PlaceTpAgain(what, s, q, p, r);
      return RdWarn(r, "Lines already on chart - drag them, or click Delete Line first");
     }
   double lo = 0.0;
   double hi = 0.0;
   CLines::VisibleRange(lo, hi);
   SLinePlacement pl;
   SResult pr;
   if(!CPlanner::PendingLines(q, lo, hi, m_cfg.defaultOffsetPct, s, p, pl, pr))
      return RdFail(r, what + " refused: " + pr.message);
   string note = "";
   if(m_state.lineMode == LINES_MARKET)
     {
      CLines::DeleteAll();
      note = "Market lines replaced by pending lines: ";
     }
   m_lines.Place(LINEROLE_ENTRY, pl.entry);
   m_lines.Place(LINEROLE_SL, pl.sl);
   if(pl.tp > 0.0)
     {
      m_lines.Place(LINEROLE_TP, pl.tp);
      m_lines.SetTpFree(false);
     }
   m_state.lineMode = LINES_PENDING;
   m_raise = true;
   RD_LOG_INFO("[OP-05] Entry line at " + RdFormatPrice(s, pl.entry) + ", SL line at " + RdFormatPrice(s, pl.sl) +
               (pl.tp > 0.0 ? ", TP line at " + RdFormatPrice(s, pl.tp) : "") + " (Ask " + RdFormatPrice(s, q.ask) + ")");
   return RdOk(r, note + "Entry line at " + RdFormatPrice(s, pl.entry) + ", SL line at " + RdFormatPrice(s, pl.sl) +
               (pl.tp > 0.0 ? ", TP line at " + RdFormatPrice(s, pl.tp) : "") +
               " - drag them (Pending Info shows the order type), then Set Pending");
  }

//+------------------------------------------------------------------+
//| Manual TP line mode: the user deleted the TP line; Add Line /    |
//| Add Pend Line put it back at the R/R distance (05 section 5).    |
//+------------------------------------------------------------------+
bool CCommands::PlaceTpAgain(const string what, const SSymbolSpec &s, const SQuote &q, const SPlanSettings &p, SResult &r)
  {
   SLines l;
   m_lines.Read(m_state.lineMode, l);
   double tp = 0.0;
   SResult fr;
   if(!CPlanner::FollowTp(l, q, s, p, tp, fr))
      return RdWarn(r, what + ": TP line not added (" + fr.message + ") - move the SL line first");
   m_lines.Place(LINEROLE_TP, tp);
   m_lines.SetTpFree(false);
   m_raise = true;
   return RdOk(r, "TP line added again at " + RdFormatPrice(s, tp) + " (R/R " + RdNum(m_cfg.tpRR, 2) + ")");
  }

//+------------------------------------------------------------------+
//| OP-02 Delete Line (F-05).                                        |
//+------------------------------------------------------------------+
bool CCommands::DeleteLine(SResult &r)
  {
   int n = CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   if(n == 0)
      return RdWarn(r, "No RiskDesk lines on this chart");
   return RdOk(r, "Lines removed");
  }

//+------------------------------------------------------------------+
//| OP-14 camera button: the Controller takes the screenshot after   |
//| the redraw and reports where it went.                            |
//+------------------------------------------------------------------+
bool CCommands::CameraShot(SResult &r)
  {
   AskShot("manual", 0);
   return RdOk(r, "Screenshot requested");
  }

// Successful order: lines removed unless InpKeepLinesAfterTrade (Q5).
void CCommands::LinesDone()
  {
   if(m_cfg.keepLinesAfterTrade)
      return;
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
  }

//+------------------------------------------------------------------+
//| F-28 / BC-10 confirmation (MessageBox Yes/No). The Strategy      |
//| Tester shows no dialogs: answered Yes there, with a log line.    |
//+------------------------------------------------------------------+
bool CCommands::Confirm(const string caption, const string text)
  {
   m_lastConfirm = text;
   string flat = text;
   StringReplace(flat, "\n", " ");
   RD_LOG_INFO("Confirmation (" + caption + "): " + flat);
   bool yes = false;
   if(m_testConfirm == RD_CONFIRM_YES || m_testConfirm == RD_CONFIRM_NO)
     {
      yes = (m_testConfirm == RD_CONFIRM_YES);
      RD_LOG_WARN("TEST: confirmation answered by the self-test");
     }
   else
      if(RdIsTester())
        {
         yes = true;
         RD_LOG_INFO("Strategy Tester: no dialog - answered Yes");
        }
      else
         yes = (MessageBox(text, RD_PRODUCT + " - " + caption, MB_YESNO | MB_ICONQUESTION) == IDYES);
   RD_LOG_INFO("Confirmation answer: " + (yes ? "Yes" : "No"));
   return yes;
  }

// "SL 1.09800, TP 1.10400" / "SL 1.09800, TP at R/R 1.00" / "SL 1.09800, no TP"
string CCommands::LevelsText(const SSymbolSpec &s, const double sl, const double tp, const bool autoTp) const
  {
   string text = "SL " + RdFormatPrice(s, sl);
   if(tp > 0.0)
      return text + ", TP " + RdFormatPrice(s, tp) + (autoTp ? " (R/R " + RdNum(m_cfg.tpRR, 2) + " from the fill)" : "");
   return text + ", no TP";
  }

//+------------------------------------------------------------------+
//| Which phase brings a button that does not work yet (09).         |
//+------------------------------------------------------------------+
string CCommands::Phase(const EPanelButton b)
  {
   switch(b)
     {
      case PB_ADDLINE:
      case PB_DELLINE:
      case PB_BUY:
      case PB_SELL:
      case PB_ADDPEND:
      case PB_SHOT:
         return "P4";
      case PB_SETPEND:
      case PB_DELPEND:
         return "P5";
      default:
         return "P6";
     }
  }

bool CCommands::Implemented(const EPanelButton b)
  {
   return Phase(b) == "P4" || Phase(b) == "P5";
  }

//+------------------------------------------------------------------+
//| 05 section 2: every tooltip says exactly what the button affects.|
//+------------------------------------------------------------------+
string CCommands::Tooltip(const EPanelButton b, const string symbol) const
  {
   bool toolOnly = (m_cfg.scopeChartOps == SCOPE_TOOL_ON_SYMBOL);
   string onSymbol = toolOnly ? "every RiskDesk " : "every ";
   switch(b)
     {
      case PB_ADDLINE:
         return "Draw the SL line" + (m_cfg.tpMode == TPMODE_MANUAL_LINE ? " and the TP line" : "") +
                " for a market order on " + symbol;
      case PB_DELLINE:
         return "Remove RiskDesk's planning lines from this chart (no order is touched)";
      case PB_BUY:
         return "Buy " + symbol + " at market: lots from Risk % and the SL line" +
                (m_cfg.tpMode == TPMODE_AUTO_RR ? ", TP at R/R " + RdNum(m_cfg.tpRR, 2) : "");
      case PB_SELL:
         return "Sell " + symbol + " at market: lots from Risk % and the SL line" +
                (m_cfg.tpMode == TPMODE_AUTO_RR ? ", TP at R/R " + RdNum(m_cfg.tpRR, 2) : "");
      case PB_ADDPEND:
         return "Draw the Entry and SL lines" + (m_cfg.tpMode == TPMODE_MANUAL_LINE ? " and the TP line" : "") +
                " for a pending order on " + symbol;
      case PB_SETPEND:
         return "Place the pending order shown under Pending Info on " + symbol + ": lots from Risk % and the Entry - SL distance" +
                (m_cfg.tpMode == TPMODE_AUTO_RR ? ", TP at R/R " + RdNum(m_cfg.tpRR, 2) : "") +
                (m_cfg.pendingExpiryHours > 0 ? ", expires after " + IntegerToString(m_cfg.pendingExpiryHours) + " h" : "");
      case PB_DELPEND:
         return "Delete " + onSymbol + "pending order on " + symbol + " (open positions stay)";
      case PB_RISKFREE:
         return "Move the SL of " + onSymbol + "position on " + symbol + " that is in profit to break-even";
      case PB_HALF:
         return "Close " + RdNum(m_cfg.partialClosePct, 2) + " % of " + onSymbol + "position on " + symbol;
      case PB_CHARTCLOSE:
         return "Close " + onSymbol + "position on " + symbol + " (pending orders stay)";
      case PB_FULLCLOSE:
         return "Close " + (m_cfg.scopeFullClose == SCOPE_TOOL_ACCOUNT ? "every RiskDesk" : "every") +
                " position on every symbol of this account" +
                (m_cfg.fullCloseAlsoPending ? " and delete the pending orders" : " (pending orders stay)");
      default:
         return "Save a screenshot of this chart to " + RD_MQL_DIR + "/Files/RiskDesk/Screenshots";
     }
  }

string CCommands::RiskTooltip() const
  {
   return "Risk per trade in % of " + RiskBaseText() + " (above 0, max " + RdFormatCapPct(m_cfg.maxRiskPerTradePct) +
          "). Type a value and press Enter";
  }

#include "CommandsTrade.mqh"
#include "CommandsPending.mqh"

#endif // RD_APP_COMMANDS_MQH
