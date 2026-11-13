//+------------------------------------------------------------------+
//| RiskDesk - App/CommandsTrade.mqh                                 |
//| Layer   : App                                                    |
//| Purpose : OP-03 Buy / OP-04 Sell (06 section 2): pre-flight      |
//|           PF-1..PF-5, plan (04 sections 6-8), BC-05 valuation,   |
//|           lots (04 sections 2-4, commission F-30), MT5 volume    |
//|           limit (BC-04), risk caps (F-16, 04 section 5), margin  |
//|           (F-31, BC-09), netting (BC-10), confirmation, G-01,    |
//|           status with the risk at the fill price, lines removed, |
//|           screenshot. Every refusal names the reason and the     |
//|           numbers (rule R8); nothing is sent before every check  |
//|           has passed.                                            |
//|           Part of CCommands; included at the end of              |
//|           App/Commands.mqh (split to stay near ~600 lines).      |
//+------------------------------------------------------------------+
#ifndef RD_APP_COMMANDSTRADE_MQH
#define RD_APP_COMMANDSTRADE_MQH

//+------------------------------------------------------------------+
bool CCommands::OpenMarket(const ESide side, SResult &r)
  {
   string name = (side == SIDE_BUY) ? "Buy" : "Sell";
   string refused = name + " refused: ";
   string op = (side == SIDE_BUY) ? "[OP-03]" : "[OP-04]";

   //--- PF-1 BC-15 permissions
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, refused + why.message);
   //--- PF-2 spec, PF-3 quote
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(name, s, q, r))
      return false;
   //--- PF-4 Risk %
   if(!(m_state.riskPct > 0.0) || m_state.riskPct > m_cfg.maxRiskPerTradePct + RD_PCT_EPS)
      return RdFail(r, refused + "Risk % " + RdNum(m_state.riskPct, 2) + " is outside (0, " +
                    RdFormatCapPct(m_cfg.maxRiskPerTradePct) + "]");
   //--- PF-5 lines
   if(m_state.lineMode == LINES_PENDING)
      return RdFail(r, refused + "the lines on the chart are for a pending order - Add Line draws the lines for " +
                    (side == SIDE_BUY ? "Buy" : "Sell"));
   if(m_state.lineMode != LINES_MARKET || !m_lines.Exists(LINEROLE_SL))
      return RdFail(r, refused + "no SL line - click Add Line first");

   //--- plan: side vs lines, BC-07 distances, TP by mode (04 sections 6-8)
   SLines lines;
   m_lines.Read(LINES_MARKET, lines);
   SPlanSettings p;
   m_cfg.Plan(p);
   STradePlan plan;
   SResult pr;
   if(!CPlanner::Market(side, lines, q, s, p, plan, pr))
      return RdFail(r, refused + pr.message);
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar, m_cfg.centMode, m_cfg.centDivisor))
      return RdFail(r, refused + ar.message);

   //--- BC-05: money of the SL distance for 1 lot (commission is added by CRiskMath, F-30)
   double loss = 0.0;
   SResult lr;
   if(!m_money.LossPerLot(s, acc.currency, side, plan.entry, plan.sl, loss, lr))
      return RdFail(r, refused + lr.message);
   string notes = (lr.sev == SEV_WARN) ? lr.message : "";
   double profit = 0.0;
   if(plan.tp > 0.0)
     {
      SResult tr;
      if(!m_money.ProfitPerLot(s, acc.currency, side, plan.entry, plan.tp, profit, tr))
         profit = 0.0;
     }

   //--- BC-10 netting: at most one position on the symbol
   SPosition net;
   bool hasNet = false;
   if(!m_gw.IsHedging())
     {
      SResult nr;
      if(!NettingPosition(net, hasNet, nr))
         return RdFail(r, refused + nr.message);
     }
   //--- BC-04: MT5 volume limit per direction
   double sameSide = 0.0;
   if(s.volLimit > 0.0)
     {
      SResult vr;
      if(!SameSideVolume(side, sameSide, vr))
         return RdFail(r, refused + vr.message);
     }
   //--- 04 sections 2-4: lots
   SLotResult lot;
   SResult zr;
   if(!CPlanner::Size(plan, s, acc, p, m_state.riskPct, loss, profit, sameSide, lot, zr))
      return RdFail(r, refused + zr.message);
   if(zr.sev == SEV_WARN)
      notes = RdJoin(notes, zr.message, "; ");
   RD_LOG_INFO(op + " plan: " + name + " " + RdFormatLots(s, plan.lots) + " " + _Symbol + " entry " + RdFormatPrice(s, plan.entry) +
               " " + LevelsText(s, plan.sl, plan.tp, m_cfg.tpMode == TPMODE_AUTO_RR) + ", risk " + RdMoney(acc, plan.riskMoney) +
               " (" + RdFormatPct(plan.riskPct) + " of " + RdMoney(acc, lot.base) + "), loss/lot " + RdNum(loss, 2) +
               " + commission " + RdNum(p.commissionPerLot, 2) + ", raw lots " + RdNum(lot.rawLots, 6));

   if(hasNet && net.side != side)
      return OppositeNetting(name, side, s, acc, p, plan, lot, net, notes, r);

   //--- F-16 caps: per trade and total (a netting add replaces the whole position's SL)
   double added = plan.riskMoney;
   if(hasNet)
     {
      SResult mr;
      if(!MergedRisk(s, acc, p, net, plan, added, mr))
         return RdFail(r, refused + mr.message);
     }
   SBudgetResult bud;
   SResult br;
   if(!CheckBudget(acc, p, hasNet ? net.ticket : 0, added, plan.riskMoney, bud, br))
      return RdFail(r, refused + br.message);

   //--- F-31 margin (may reduce the lots with InpReduceToMargin)
   double lots = plan.lots;
   SResult gm;
   if(!CheckMargin(s, side, acc, plan.entry, lots, notes, gm))
      return RdFail(r, refused + gm.message);
   if(RdVolLt(lots, plan.lots))
     {
      plan.lots = lots;
      plan.riskMoney = lots * lot.lossPerLotAll;
      plan.riskPct = (lot.base > 0.0) ? plan.riskMoney / lot.base * 100.0 : 0.0;
     }

   //--- confirmations: BC-10 netting add (always), InpConfirmTrades
   string order = name + " " + RdFormatLots(s, plan.lots) + " " + _Symbol;
   bool autoTp = (m_cfg.tpMode == TPMODE_AUTO_RR);
   if(hasNet)
     {
      if(!Confirm("netting account", "Netting account: this " + order + " merges with the open " + RdSideText(net.side) + " " +
                  RdFormatLots(s, net.volume) + " lot position on " + _Symbol + " and replaces its SL/TP with " +
                  LevelsText(s, plan.sl, plan.tp, autoTp) + ".\n\nRisk of the whole position at the new SL: " +
                  RdMoney(acc, added) + ".\n\nContinue?"))
         return RdWarn(r, name + " cancelled - nothing was sent");
     }
   else
      if(m_cfg.confirmTrades && !Confirm(name, order + " at market?\n\n" + LevelsText(s, plan.sl, plan.tp, autoTp) +
                                         "\nRisk " + RdMoney(acc, plan.riskMoney) + " (" + RdFormatPct(plan.riskPct) + ")"))
         return RdWarn(r, name + " cancelled - nothing was sent");

   //--- G-01: Auto R/R TP recomputed from the fresh price of every attempt
   STradeOutcome out;
   SResult gr;
   double tpLine = (m_cfg.tpMode == TPMODE_MANUAL_LINE) ? plan.tp : 0.0;
   double rr = autoTp ? m_cfg.tpRR : 0.0;
   if(!m_gw.OpenMarket(_Symbol, side, plan.lots, plan.sl, tpLine, out, gr, rr))
      return RdFail(r, name + " failed: " + gr.message);
   return Opened(name, side, s, acc, p, plan, out, notes, r);
  }

//+------------------------------------------------------------------+
//| Status after a fill: the risk of what was filled, at the fill    |
//| price and the SL on the server (it can differ from the plan by   |
//| the slippage). Lines removed, screenshot asked for.              |
//+------------------------------------------------------------------+
bool CCommands::Opened(const string name, const ESide side, const SSymbolSpec &s, const SAccountSpec &acc,
                       const SPlanSettings &p, const STradePlan &plan, const STradeOutcome &out, string notes, SResult &r)
  {
   double vol = (out.volume > 0.0) ? out.volume : plan.lots;
   double price = (out.price > 0.0) ? out.price : plan.entry;
   double sl = (out.sl > 0.0) ? out.sl : plan.sl;
   double risk = (plan.lots > 0.0) ? plan.riskMoney * vol / plan.lots : plan.riskMoney;
   double perLot = 0.0;
   SResult lr;
   if(m_money.LossPerLot(s, acc.currency, side, price, sl, perLot, lr))
      risk = CRiskMath::PositionRisk(perLot, MathMax(0.0, p.commissionPerLot), vol);
   double base = CRiskMath::RiskBase(p.riskBase, acc.balance, acc.equity);
   double pct = (base > 0.0) ? risk / base * 100.0 : 0.0;
   notes = RdJoin(notes, out.notes, "; ");
   LinesDone();
   AskShot(side == SIDE_BUY ? "buy" : "sell", out.ticket);
   string msg = name + " " + RdFormatLots(s, vol) + " " + _Symbol + " @" + RdFormatPrice(s, price) + RdSep() + "risk " +
                RdMoney(acc, risk) + " (" + RdFormatPct(pct) + ")" + RdSep() + RdTicketText(out.ticket);
   RD_LOG_INFO("[OP-0" + (side == SIDE_BUY ? "3" : "4") + "] done: " + msg + ", SL " + RdFormatPrice(s, sl) + ", TP " +
               (out.tp > 0.0 ? RdFormatPrice(s, out.tp) : "none") + (notes != "" ? " (" + notes + ")" : ""));
   if(notes != "")
      return RdWarn(r, msg + " - " + notes);
   return RdOk(r, msg);
  }

//+------------------------------------------------------------------+
//| BC-10: the symbol's position on a netting account, any magic.    |
//+------------------------------------------------------------------+
bool CCommands::NettingPosition(SPosition &p, bool &found, SResult &r)
  {
   found = false;
   STradeFilter f;
   f.Reset();
   f.symbol = _Symbol;
   SPosition arr[];
   if(!m_gw.ListPositions(f, arr, r))
      return false;
   if(ArraySize(arr) > 0)
     {
      p = arr[0];
      found = true;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| BC-04: open + pending volume in one direction on the symbol (MT5 |
//| SYMBOL_VOLUME_LIMIT counts every order, not only RiskDesk's).    |
//+------------------------------------------------------------------+
bool CCommands::SameSideVolume(const ESide side, double &volume, SResult &r)
  {
   volume = 0.0;
   STradeFilter f;
   f.Reset();
   f.symbol = _Symbol;
   SPosition pos[];
   SOrder ord[];
   if(!m_gw.ListPositions(f, pos, r) || !m_gw.ListPending(f, ord, r))
      return false;
   for(int i = 0; i < ArraySize(pos); i++)
      if(pos[i].side == side)
         volume += pos[i].volume;
   for(int j = 0; j < ArraySize(ord); j++)
      if(ord[j].side == side)
         volume += ord[j].volume;
   return true;
  }

//+------------------------------------------------------------------+
//| F-16 (04 section 5): open risk of RiskDesk's positions and       |
//| orders on the whole account, read fresh (NFR-07), then the caps. |
//| replaced: ticket whose contribution this trade replaces (netting |
//| add / reversal), 0 = none. added: contribution after the trade.  |
//+------------------------------------------------------------------+
bool CCommands::CheckBudget(const SAccountSpec &acc, const SPlanSettings &p, const ulong replaced, const double added,
                            const double tradeRisk, SBudgetResult &bud, SResult &r)
  {
   STradeFilter f;
   f.Reset();
   f.toolOnly = true;
   SPosition pos[];
   SOrder ord[];
   SResult lr;
   if(!m_gw.ListPositions(f, pos, lr))
      return RdFail(r, "open risk cannot be checked: " + lr.message);
   if(p.includePendingInTotalRisk && !m_gw.ListPending(f, ord, lr))
      return RdFail(r, "open risk cannot be checked: " + lr.message);
   m_money.FillLossToSl(pos, acc.currency, p.commissionPerLot);
   m_money.FillLossToSl(ord, acc.currency, p.commissionPerLot);
   SBudgetResult open;
   if(!CRiskBudget::OpenRisk(pos, ord, p, open, r))
      return false;
   double removed = 0.0;
   if(replaced > 0)
      for(int i = 0; i < ArraySize(pos); i++)
         if(pos[i].ticket == replaced)
            removed = MathMax(0.0, pos[i].lossToSl);
   if(!CRiskBudget::Check(acc, p, open.openRisk, removed, added, tradeRisk, bud, r))
      return false;
   RD_LOG_INFO("F-16 " + r.message + " (open " + RdFormatPct(bud.openPct) + " in " + IntegerToString(open.positions) +
               " position(s) and " + IntegerToString(open.orders) + " order(s))");
   return true;
  }

//+------------------------------------------------------------------+
//| BC-10 / 04 section 5: a same-direction add on netting makes one  |
//| position of (old + new) lots at the averaged open price, with    |
//| the new SL: its loss to that SL replaces the old contribution.   |
//+------------------------------------------------------------------+
bool CCommands::MergedRisk(const SSymbolSpec &s, const SAccountSpec &acc, const SPlanSettings &p, const SPosition &net,
                           const STradePlan &plan, double &risk, SResult &r)
  {
   risk = 0.0;
   SPosition merged[];
   ArrayResize(merged, 1);
   merged[0] = net;
   double vol = net.volume + plan.lots;
   merged[0].volume = vol;
   merged[0].open = (vol > 0.0) ? (net.volume * net.open + plan.lots * plan.entry) / vol : plan.entry;
   merged[0].sl = plan.sl;
   m_money.FillLossToSl(merged, acc.currency, p.commissionPerLot);
   if(!MathIsValidNumber(merged[0].lossToSl))
      return RdFail(r, "the risk of the merged " + RdFormatLots(s, vol) + " lot position cannot be valued");
   risk = MathMax(0.0, merged[0].lossToSl);
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| F-31 / BC-09: margin for 'lots' against free margin minus        |
//| InpMarginBufferPct. Short -> refuse with the numbers, or with    |
//| InpReduceToMargin send the largest affordable lot (amber).       |
//| A margin the terminal cannot compute is left to the server.      |
//+------------------------------------------------------------------+
bool CCommands::CheckMargin(const SSymbolSpec &s, const ESide side, const SAccountSpec &acc, const double price,
                            double &lots, string &notes, SResult &r)
  {
   r.Reset();
   double need = 0.0;
   SResult mr;
   if(!m_money.MarginFor(s, side, lots, price, need, mr))
     {
      RD_LOG_WARN("F-31 margin pre-check skipped: " + mr.message + " - the server decides");
      return RdOk(r, "");
     }
   double buffer = m_cfg.marginBufferPct;
   double usable = MathMax(0.0, acc.freeMargin) * (1.0 - buffer / 100.0);
   RD_LOG_INFO("F-31 margin for " + RdFormatLots(s, lots) + " lot: " + RdMoney(acc, need) + ", free " + RdMoney(acc, acc.freeMargin) +
               ", usable " + RdMoney(acc, usable) + " (" + RdNum(buffer, 2) + " % kept unused)");
   if(need <= usable)
      return RdOk(r, "");
   double maxLots = 0.0;
   SResult xr;
   if(!m_money.MaxLotsByMargin(s, side, price, acc.freeMargin, buffer, maxLots, xr))
      maxLots = 0.0;
   string numbers = "needs " + RdMoney(acc, need) + " margin for " + RdFormatLots(s, lots) + " lot, " +
                    RdMoney(acc, acc.freeMargin) + " free" + (buffer > 0.0 ? " (" + RdNum(buffer, 2) + " % kept unused)" : "") +
                    " - max " + (maxLots > 0.0 ? "about " + RdFormatLots(s, maxLots) + " lot" :
                                 "less than the minimum " + RdFormatLots(s, s.volMin) + " lot") + " at the current leverage";
   if(!m_cfg.reduceToMargin || !(maxLots > 0.0) || !RdVolLt(maxLots, lots))
      return RdFail(r, "Not enough margin: " + numbers);
   lots = maxLots;
   notes = RdJoin(notes, "reduced to " + RdFormatLots(s, maxLots) + " lot by the free margin (" + numbers + ")", "; ");
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-10: an order against the netting position reduces, closes or  |
//| reverses it. Refused unless InpNettingAllowOpposite; then, after |
//| a confirmation, done with the tested primitives so the BC-14     |
//| check of each request fits it (no blind resend, rule R9):        |
//|   1. G-04 closes min(lots, position) of the position,            |
//|   2. a reversal opens the rest with the lines' SL/TP (G-01).     |
//+------------------------------------------------------------------+
bool CCommands::OppositeNetting(const string name, const ESide side, const SSymbolSpec &s, const SAccountSpec &acc,
                                const SPlanSettings &p, STradePlan &plan, const SLotResult &lot, const SPosition &net,
                                string notes, SResult &r)
  {
   string refused = name + " refused: ";
   string held = RdSideText(net.side) + " " + RdFormatLots(s, net.volume) + " lot position on " + _Symbol;
   if(!m_cfg.nettingAllowOpposite)
      return RdFail(r, refused + "netting account: a " + RdSideText(side) + " would reduce or reverse the open " + held +
                    " - use Half Close or Chart Close (or allow it with the input 'Netting: allow an opposite order')");
   double closeVol = RdVolLt(plan.lots, net.volume) ? plan.lots : net.volume;
   double rest = 0.0;
   if(RdVolGt(plan.lots, net.volume) && !RdFloorVolume(s, plan.lots - net.volume, rest))
      rest = 0.0;
   bool autoTp = (m_cfg.tpMode == TPMODE_AUTO_RR);
   string effect = "";
   if(RdVolLt(plan.lots, net.volume))
      effect = "reduces the open " + held + " to " + RdFormatLots(s, net.volume - plan.lots) + " lot (its SL/TP stay)";
   else
      if(rest > 0.0)
         effect = "closes the open " + held + " and opens a " + RdSideText(side) + " " + RdFormatLots(s, rest) +
                  " lot position with " + LevelsText(s, plan.sl, plan.tp, autoTp);
      else
         effect = "closes the open " + held;

   //--- the reversed position: caps and margin of what is opened
   if(rest > 0.0)
     {
      double addRisk = rest * lot.lossPerLotAll;
      SBudgetResult bud;
      SResult br;
      if(!CheckBudget(acc, p, net.ticket, addRisk, addRisk, bud, br))
         return RdFail(r, refused + br.message);
      SResult gm;
      if(!CheckMargin(s, side, acc, plan.entry, rest, notes, gm))
         return RdFail(r, refused + gm.message);
     }
   string order = name + " " + RdFormatLots(s, plan.lots) + " " + _Symbol;
   if(!Confirm("netting account", "Netting account: this " + order + " " + effect + ".\n\nContinue?"))
      return RdWarn(r, name + " cancelled - nothing was sent");

   //--- 1. G-04 on the netting position
   STradeOutcome co;
   SResult cr;
   if(!m_gw.ClosePosition(net.ticket, closeVol, co, cr))
      return RdFail(r, name + " failed: " + cr.message);
   string done = RdSideText(net.side) + " position " + (co.remaining > 0.0 ? "reduced to " + RdFormatLots(s, co.remaining) + " lot" :
                 "closed") + (co.profitKnown ? " (P/L " + RdMoney(acc, co.profit) + ")" : "");
   if(!(rest > 0.0))
     {
      LinesDone();
      AskShot(side == SIDE_BUY ? "buy" : "sell", net.ticket);
      notes = RdJoin(notes, co.notes, "; ");
      string msg = name + " " + RdFormatLots(s, co.volume > 0.0 ? co.volume : closeVol) + " " + _Symbol + " @" +
                   RdFormatPrice(s, co.price) + ": " + done + RdSep() + RdTicketText(net.ticket);
      if(notes != "")
         return RdWarn(r, msg + " - " + notes);
      return RdOk(r, msg);
     }
   //--- 2. G-01 the rest, with the lines' SL/TP
   STradeOutcome out;
   SResult gr;
   double tpLine = (m_cfg.tpMode == TPMODE_MANUAL_LINE) ? plan.tp : 0.0;
   if(!m_gw.OpenMarket(_Symbol, side, rest, plan.sl, tpLine, out, gr, autoTp ? m_cfg.tpRR : 0.0))
      return RdFail(r, name + ": the " + done + ", but opening the " + RdSideText(side) + " " + RdFormatLots(s, rest) +
                    " lot failed: " + gr.message);
   plan.riskMoney = rest * lot.lossPerLotAll;
   plan.lots = rest;
   return Opened(name, side, s, acc, p, plan, out, RdJoin(notes, "netting: the " + done + " first", "; "), r);
  }

#endif // RD_APP_COMMANDSTRADE_MQH
