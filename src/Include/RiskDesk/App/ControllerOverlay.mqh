//+------------------------------------------------------------------+
//| RiskDesk - App/ControllerOverlay.mqh                             |
//| Layer   : App                                                    |
//| Purpose : CController's side of the pending order overlay (F-22, |
//|           05 section 6):                                         |
//|           - every refresh: the placed pending orders in chart    |
//|             scope (InpScopeChartOps), their label texts (money   |
//|             at SL and TP need the BC-05 valuation, recomputed    |
//|             only when the orders or the account changed), then   |
//|             CPendingOverlay::Render                              |
//|           - a dropped overlay line (CHARTEVENT_OBJECT_DRAG, or   |
//|             its price typed in the properties dialog) runs OP-16 |
//|             (CCommands::MoveOrder) behind the busy guard, ends   |
//|             with a status and a log line (R8) and puts the lines |
//|             back on the order's values (snap back when refused)  |
//|           and the other optional overlays (P7, 05 section 6):    |
//|           - the candle countdown (F-21, Services/CandleTime)     |
//|           - MetaTrader's closed-trade objects kept or removed    |
//|             (F-20, Services/ChartHousekeeping)                   |
//|           Part of CController; included at the end of           |
//|           App/Controller.mqh.                                    |
//+------------------------------------------------------------------+
#ifndef RD_APP_CONTROLLEROVERLAY_MQH
#define RD_APP_CONTROLLEROVERLAY_MQH

//+------------------------------------------------------------------+
//| P7 chart extras, every refresh; each is one flag test when off.  |
//| True when objects were created (the panel goes on top again).    |
//+------------------------------------------------------------------+
bool CController::SyncExtras(const SQuote &q, const bool quoteOk)
  {
   bool created = false;
   if(m_candle != NULL && m_candle.Update(quoteOk ? q.bid : 0.0, created))
      m_redraw.Mark();
   if(m_house != NULL && m_house.Run(m_houseFirst) > 0)
      m_redraw.Mark();
   m_houseFirst = false;
   return created;
  }

//+------------------------------------------------------------------+
//| One refresh of the overlay. True when objects were created (the  |
//| panel goes on top again).                                        |
//+------------------------------------------------------------------+
bool CController::SyncOverlay()
  {
   if(m_overlay == NULL)
      return false;
   if(!m_cfg.showPendingOverlay)
     {
      if(m_ovOn)
        {
         m_overlay.Clear();   // F-22 AC4: off -> nothing drawn, nothing to drag
         ArrayResize(m_ov, 0);
         m_ovKey = "";
         m_ovOn = false;
        }
      return false;
     }
   m_ovOn = true;
   STradeFilter f;
   f.Reset();
   f.symbol = _Symbol;
   f.toolOnly = (m_cfg.scopeChartOps == SCOPE_TOOL_ON_SYMBOL);
   SOrder arr[];
   SResult r;
   if(!m_gw.ListPending(f, arr, r))
      return false;   // keep what is drawn
   SAccountSpec acc;
   SResult ar;
   bool accOk = CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor);
   string key = (accOk ? DoubleToString(acc.balance, 2) + "|" + (m_cfg.riskBase != RISKBASE_BALANCE ?
                 DoubleToString(acc.equity, 2) : "") + "|" + (acc.centShow ? acc.centUnit : "") : "-") + "|" +
                IntegerToString(m_specAt);
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
      key += "|" + IntegerToString((long)arr[i].ticket) + ":" + IntegerToString(arr[i].side) + IntegerToString(arr[i].kind) +
             ":" + DoubleToString(arr[i].volume, 8) + ":" + DoubleToString(arr[i].price, 8) + ":" +
             DoubleToString(arr[i].sl, 8) + ":" + DoubleToString(arr[i].tp, 8);
   if(key != m_ovKey)
     {
      m_ovKey = key;
      OverlayLabels(arr, acc, accOk);
     }
   return m_overlay.Render(m_ov);
  }

//+------------------------------------------------------------------+
//| 05 section 6 labels: entry "Buy Stop 0.14 @ 3991.15", SL         |
//| "SL -$23.38 (0.23 %)", TP "TP +$26.60 (R 1.14)" [NEW: money on   |
//| placed orders]. The SL money is what the risk budget counts      |
//| (loss to SL + commission); without a valuation the price only.   |
//+------------------------------------------------------------------+
void CController::OverlayLabels(const SOrder &arr[], const SAccountSpec &acc, const bool accOk)
  {
   int n = ArraySize(arr);
   ArrayResize(m_ov, n);
   double base = accOk ? CRiskMath::RiskBase(m_cfg.riskBase, acc.balance, acc.equity) : 0.0;
   double comm = MathMax(0.0, m_cfg.commissionPerLot);
   for(int i = 0; i < n; i++)
     {
      SOrder o = arr[i];
      m_ov[i].o = o;
      for(int k = 0; k < RD_LINE_ROLES; k++)
        {
         m_ov[i].label[k] = "";
         m_ov[i].labelColor[k] = clrNONE;
        }
      string lots = m_specOk ? RdFormatLots(m_spec, o.volume) : RdNum(o.volume);
      string px = m_specOk ? RdFormatPrice(m_spec, o.price) : DoubleToString(o.price, _Digits);
      m_ov[i].label[LINEROLE_ENTRY] = RdOrderText(o.side, o.kind) + " " + lots + " @ " + px;
      if(o.sl > 0.0)
        {
         string text = "SL " + (m_specOk ? RdFormatPrice(m_spec, o.sl) : DoubleToString(o.sl, _Digits));
         double loss = 0.0;
         SResult lr;
         if(m_specOk && accOk && m_money.LossPerLot(m_spec, acc.currency, o.side, o.price, o.sl, loss, lr))
           {
            double risk = CRiskMath::PositionRisk(loss, comm, o.volume);
            text = "SL " + RdGlyphMinus() + RdMoney(acc, risk) + (base > 0.0 ? " (" + RdFormatPct(risk / base * 100.0) + ")" : "");
           }
         m_ov[i].label[LINEROLE_SL] = text;
        }
      if(o.tp > 0.0)
        {
         string text = "TP " + (m_specOk ? RdFormatPrice(m_spec, o.tp) : DoubleToString(o.tp, _Digits));
         double profit = 0.0;
         SResult pr;
         if(m_specOk && accOk && m_money.ProfitPerLot(m_spec, acc.currency, o.side, o.price, o.tp, profit, pr))
           {
            double reward = o.volume * profit - o.volume * comm;
            double rr = CRiskMath::RewardRatio(o.price, o.sl, o.tp);
            text = "TP +" + RdMoney(acc, reward) + (o.sl > 0.0 && rr > 0.0 ? " (R " + DoubleToString(rr, 2) + ")" : "");
           }
         m_ov[i].label[LINEROLE_TP] = text;
        }
     }
  }

//+------------------------------------------------------------------+
//| OP-16: an overlay line was dropped (drag = true) or its          |
//| properties were changed in the dialog (drag = false: only a new  |
//| price counts as a move). Every move ends with a status and a log |
//| line; the lines then show the order as it is on the server.      |
//+------------------------------------------------------------------+
void CController::OverlayDropped(const ulong ticket, const ELineRole role, const bool drag)
  {
   if(m_overlay == NULL || !m_cfg.showPendingOverlay)
      return;
   string name = CPendingOverlay::LineName(ticket, role);
   if(ObjectFind(0, name) < 0)
      return;
   if(!m_specOk)
      ReadSpec();
   double price = ObjectGetDouble(0, name, OBJPROP_PRICE, 0);
   double drawn = m_overlay.Drawn(ticket, role);
   double tick = m_specOk ? RdTick(m_spec) : _Point;
   if(!drag && drawn > 0.0 && MathAbs(price - drawn) < tick / 2.0)
      return;   // colour or style changed, not the price
   int digits = m_specOk ? m_spec.digits : _Digits;
   RD_LOG_INFO("Overlay " + CLines::RoleText(role) + " line of " + RdTicketText(ticket) + " dropped at " +
               DoubleToString(price, digits) + " (order " + DoubleToString(drawn, digits) + ")");
   SResult r;
   r.Reset();
   if(m_state.busy)
     {
      m_overlay.Snap(ticket);
      RdWarn(r, "Busy - try again: " + RdTicketText(ticket) + " was not changed");
      Report(r);
      Refresh();
      return;
     }
   m_state.busy = true;
   m_cmd.MoveOrder(ticket, role, price, r);
   m_state.busy = false;
   m_overlay.Snap(ticket);   // done: the new values; refused: back to the old ones
   m_ovKey = "";
   m_riskAt = 0;             // open risk read again (F-29)
   m_idleAt = 0;
   Report(r);
   Refresh();
   TakeShot(r);
  }

#endif // RD_APP_CONTROLLEROVERLAY_MQH
