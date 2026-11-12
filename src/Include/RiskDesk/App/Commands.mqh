//+------------------------------------------------------------------+
//| RiskDesk - App/Commands.mqh                                      |
//| Layer   : App                                                    |
//| Purpose : one function per user action (06-trade-operations).    |
//|           Each ends with an SResult whose message is the status  |
//|           text (rule R8); the Controller shows and logs it.      |
//|           Also the tooltip of every button: what exactly it      |
//|           affects, from the settings (05 section 2).             |
//| Status  : P3 - Risk % field (F-02). The trading buttons answer   |
//|           amber "not implemented yet" with the phase that brings |
//|           them; they are implemented in phases P4-P7.            |
//+------------------------------------------------------------------+
#ifndef RD_APP_COMMANDS_MQH
#define RD_APP_COMMANDS_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "..\Domain\Validators.mqh"
#include "..\Services\Persistence.mqh"
#include "..\UI\Panel.mqh"
#include "Settings.mqh"
#include "State.mqh"

class CCommands
  {
private:
   CSettings        *m_cfg;
   CState           *m_state;
   CPersistence     *m_store;

   string            RiskBaseText() const;

public:
                     CCommands() { m_cfg = NULL; m_state = NULL; m_store = NULL; }
   void              Init(CSettings *cfg, CState *state, CPersistence *store);

   bool              SetRisk(const string text, SResult &r);
   bool              Run(const EPanelButton b, SResult &r);

   string            Tooltip(const EPanelButton b, const string symbol) const;
   string            RiskTooltip() const;
   static string     Phase(const EPanelButton b);
  };

void CCommands::Init(CSettings *cfg, CState *state, CPersistence *store)
  {
   m_cfg = cfg;
   m_state = state;
   m_store = store;
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
//| P3: no button trades yet (09 P3).                                |
//+------------------------------------------------------------------+
bool CCommands::Run(const EPanelButton b, SResult &r)
  {
   r.Reset();
   return RdWarn(r, CPanel::ButtonCaption(b) + ": not implemented yet (coming in phase " + Phase(b) + ")");
  }

string CCommands::Phase(const EPanelButton b)
  {
   switch(b)
     {
      case PB_ADDLINE:
      case PB_DELLINE:
      case PB_BUY:
      case PB_SELL:
      case PB_SHOT:
         return "P4";
      case PB_ADDPEND:
      case PB_SETPEND:
      case PB_DELPEND:
         return "P5";
      default:
         return "P6";
     }
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
         return "Place the pending order shown under Pending Info on " + symbol;
      case PB_DELPEND:
         return "Delete " + onSymbol + "pending order on " + symbol;
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

#endif // RD_APP_COMMANDS_MQH
