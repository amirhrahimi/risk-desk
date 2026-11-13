// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - App/ControllerModel.mqh                               |
//| Layer   : App                                                    |
//| Purpose : CController's view model and readouts: symbol spec     |
//|           cache with the BC-05 valuation check, BC-15 disabled   |
//|           buttons, spread text, Buy/Sell prices, the idle        |
//|           readout (warnings, open risk F-29). Part of            |
//|           CController; included at the end of App/Controller.mqh|
//|           (split to stay near ~600 lines, ADR-021).              |
//+------------------------------------------------------------------+
#ifndef RD_APP_CONTROLLERMODEL_MQH
#define RD_APP_CONTROLLERMODEL_MQH

//+------------------------------------------------------------------+
//| Spec of the chart symbol (cached, 60 s). On MT4 also the BC-05   |
//| valuation check of a 100-tick move, for the idle warning.        |
//+------------------------------------------------------------------+
void CController::ReadSpec()
  {
   m_specAt = GetTickCount();
   SResult r;
   m_specOk = CSymbolSpec::Read(_Symbol, m_spec, r);
   if(r.message != m_specMsg && r.sev != SEV_OK)
     {
      if(m_specOk)
         RD_LOG_WARN(r.message);
      else
         RD_LOG_ERROR(r.message);
     }
   m_specMsg = r.message;
   m_mismatch = "";
   if(!m_specOk)
      return;
   SQuote q;
   SAccountSpec acc;
   SResult ar;
   if(!CMarket::Quote(_Symbol, q) || !CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor))
      return;
   double sl = RdNormalizePrice(m_spec, q.bid - 100.0 * RdTick(m_spec));
   if(!(sl > 0.0))
      return;
   double loss = 0.0;
   SResult lr;
   if(m_money.LossPerLot(m_spec, acc.currency, SIDE_BUY, q.ask, sl, loss, lr) && lr.sev == SEV_WARN)
      m_mismatch = lr.message;
  }

//+------------------------------------------------------------------+
//| BC-15: buttons the symbol's trade mode does not allow are drawn  |
//| disabled; a click explains why.                                  |
//+------------------------------------------------------------------+
string CController::DisabledWhy(const EPanelButton b) const
  {
   if(!m_specOk)
      return "";
   int mode = m_spec.tradeMode;
   if(mode == SYMBOL_TRADE_MODE_DISABLED &&
      b != PB_ADDLINE && b != PB_DELLINE && b != PB_ADDPEND && b != PB_FULLCLOSE && b != PB_SHOT)
      return "trading is disabled on " + _Symbol + " by the broker";
   if(mode == SYMBOL_TRADE_MODE_CLOSEONLY && (b == PB_BUY || b == PB_SELL || b == PB_SETPEND))
      return _Symbol + " is close-only: no new trades";
   if(mode == SYMBOL_TRADE_MODE_LONGONLY && b == PB_SELL)
      return _Symbol + " allows buy trades only";
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY && b == PB_BUY)
      return _Symbol + " allows sell trades only";
   return "";
  }

string CController::TradeModeWarning() const
  {
   if(!m_specOk)
      return m_specMsg;
   int mode = m_spec.tradeMode;
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
      return "Trading is disabled on " + _Symbol + " by the broker";
   if(mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return _Symbol + " is close-only: no new trades";
   if(mode == SYMBOL_TRADE_MODE_LONGONLY)
      return _Symbol + " allows buy trades only";
   if(mode == SYMBOL_TRADE_MODE_SHORTONLY)
      return _Symbol + " allows sell trades only";
   return "";
  }

//+------------------------------------------------------------------+
//| 05 section 4 Spread: points, or pips (10 points on 3/5-digit     |
//| symbols, else 1 point; ADR-021).                                 |
//+------------------------------------------------------------------+
void CController::SpreadText(const SQuote &q, const bool quoteOk, string &text, bool &warn) const
  {
   warn = false;
   if(!quoteOk || !m_specOk || !(m_spec.point > 0.0))
     {
      text = "Spread: -";
      return;
     }
   int points = (int)MathRound((q.ask - q.bid) / m_spec.point);
   warn = (m_cfg.spreadWarnPts > 0 && points > m_cfg.spreadWarnPts);
   if(m_cfg.spreadUnit == SPREAD_PIPS)
     {
      bool fractional = (m_spec.digits == 3 || m_spec.digits == 5);
      text = "Spread: " + (fractional ? DoubleToString(points / 10.0, 1) : IntegerToString(points)) + " pips";
      return;
     }
   text = "Spread: " + IntegerToString(points) + " pts";
  }

//+------------------------------------------------------------------+
void CController::BuildModel(SPanelModel &m, const SQuote &q, const bool quoteOk)
  {
   string dash = ShortToString((ushort)0x2014);
   m.riskText = DoubleToString(m_state.riskPct, 2);
   m.riskTip = m_cmd.RiskTooltip();
   m.lotsText = dash;
   m.lotsWarn = false;
   m.lotsTip = "Lots for Risk % and the SL line (read-only); " + dash + " while no lines are on the chart";
   m.pinfoText = "";
   m.pinfoWarn = false;
   m.pinfoTip = "Pending order type implied by the Entry and SL lines (Add Pend Line)";
   SpreadText(q, quoteOk, m.spreadText, m.spreadWarn);
   m.spreadTip = "Current spread of " + _Symbol + (m_cfg.spreadWarnPts > 0 ? " (amber above " +
                 IntegerToString(m_cfg.spreadWarnPts) + " pts)" : "");

   int digits = m_specOk ? m_spec.digits : 5;
   for(int i = 0; i < PB_COUNT; i++)
     {
      EPanelButton b = (EPanelButton)i;
      m.buttonText[i] = CPanel::ButtonCaption(b);
      m.buttonLook[i] = LOOK_NORMAL;
      m.buttonTip[i] = m_tips[i];
      string why = DisabledWhy(b);
      if(why != "")
        {
         m.buttonLook[i] = LOOK_DISABLED;
         m.buttonTip[i] = "Disabled: " + why;
        }
      if(m_state.busy && m_state.busyButton == i)
         m.buttonLook[i] = LOOK_WORKING;
     }
   if(m_cfg.showPricesOnButtons && quoteOk)
     {
      m.buttonText[PB_BUY] = "Buy " + DoubleToString(q.ask, digits);
      m.buttonText[PB_SELL] = "Sell " + DoubleToString(q.bid, digits);
     }
   ApplyPreview(m);
  }

string CController::AgeText(const int seconds)
  {
   if(seconds >= 2 * 86400)
      return IntegerToString(seconds / 86400) + " days";
   if(seconds >= 2 * 3600)
      return IntegerToString(seconds / 3600) + " h";
   return IntegerToString(MathMax(1, seconds / 60)) + " min";
  }

//+------------------------------------------------------------------+
//| 05 section 4 idle readout: the highest-priority warning, else    |
//| "Open risk x % / cap" (F-29; amber above 75 % of the cap).       |
//+------------------------------------------------------------------+
void CController::UpdateIdle(const SQuote &q, const bool quoteOk)
  {
   SResult why;
   if(!CAccountSpec::CanTrade(why))
     {
      m_status.SetIdle(SEV_WARN, why.message);
      return;
     }
   string trade = TradeModeWarning();
   if(trade != "")
     {
      m_status.SetIdle(SEV_WARN, trade);
      return;
     }
   if(!quoteOk)
     {
      m_status.SetIdle(SEV_WARN, "No quote for " + _Symbol + " yet");
      return;
     }
   if(CMarket::IsStale(q, m_cfg.staleQuoteSec))
     {
      m_status.SetIdle(SEV_WARN, "No quotes for " + AgeText(CMarket::AgeSeconds(q)) + " - market may be closed");
      return;
     }
   if(m_mismatch != "")
     {
      m_status.SetIdle(SEV_WARN, m_mismatch);
      return;
     }
   uint now = GetTickCount();
   if(m_riskAt == 0 || (uint)(now - m_riskAt) >= RD_CTL_RISK_MS)
     {
      m_riskAt = now;
      ComputeOpenRisk();
     }
   m_status.SetIdle(m_riskSev, m_riskText);
  }

//+------------------------------------------------------------------+
//| F-29: open risk of RiskDesk positions (and pending orders) on    |
//| the whole account, read fresh (NFR-07: several charts agree).    |
//+------------------------------------------------------------------+
void CController::ComputeOpenRisk()
  {
   SAccountSpec acc;
   SResult r;
   m_riskSev = SEV_WARN;
   if(!CAccountSpec::Read(acc, r, m_cfg.centMode, m_cfg.centDivisor))
     {
      m_riskText = "Open risk n/a: " + r.message;
      return;
     }
   STradeFilter f;
   f.Reset();
   f.toolOnly = true;
   SPosition positions[];
   SOrder orders[];
   if(!m_gw.ListPositions(f, positions, r))
     {
      m_riskText = "Open risk n/a: " + r.message;
      return;
     }
   if(m_cfg.includePendingInTotalRisk && !m_gw.ListPending(f, orders, r))
     {
      m_riskText = "Open risk n/a: " + r.message;
      return;
     }
   m_money.FillLossToSl(positions, acc.currency, m_cfg.commissionPerLot);
   m_money.FillLossToSl(orders, acc.currency, m_cfg.commissionPerLot);
   SPlanSettings plan;
   m_cfg.Plan(plan);
   SBudgetResult bud;
   if(!CRiskBudget::OpenRisk(positions, orders, plan, bud, r))
     {
      m_riskText = r.message;
      return;
     }
   m_riskText = CRiskBudget::Readout(acc, plan, bud.openRisk, m_riskSev);
  }

#endif // RD_APP_CONTROLLERMODEL_MQH
