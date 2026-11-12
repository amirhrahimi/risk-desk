//+------------------------------------------------------------------+
//| RiskDesk - App/CommandsPending.mqh                               |
//| Layer   : App                                                    |
//| Purpose : pending orders (06 OP-07, OP-08, OP-16):               |
//|           - Set Pending: PF-1..PF-5, classification and BC-07    |
//|             distances (04 section 7), TP by mode, BC-05          |
//|             valuation, lots, MT5 volume limit, risk caps, margin,|
//|             netting (BC-10: the order merges with or reduces the |
//|             position when it fills), confirmation, G-02 with the |
//|             BC-08 expiration ladder                              |
//|           - Del Pending: every pending order in chart scope      |
//|             (InpScopeChartOps), G-05 each, "Deleted n of m"      |
//|           - MoveOrder: a dropped overlay line (F-22): the new    |
//|             price/SL/TP (entry moves the whole order), order     |
//|             type, BC-07 stops and freeze levels, risk caps with  |
//|             the lot unchanged (04 section 5), G-08               |
//|           Every refusal names the reason and the numbers (R8);   |
//|           nothing is sent before every check has passed.         |
//|           Part of CCommands; included at the end of              |
//|           App/Commands.mqh.                                      |
//+------------------------------------------------------------------+
#ifndef RD_APP_COMMANDSPENDING_MQH
#define RD_APP_COMMANDSPENDING_MQH

//+------------------------------------------------------------------+
//| OP-07 Set Pending (F-09).                                        |
//+------------------------------------------------------------------+
bool CCommands::SetPending(SResult &r)
  {
   const string name = "Set Pending";
   string refused = name + " refused: ";

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
   if(m_state.lineMode == LINES_MARKET)
      return RdFail(r, refused + "the lines on the chart are for a market order - Add Pend Line draws the Entry and SL lines");
   if(m_state.lineMode != LINES_PENDING || !m_lines.Exists(LINEROLE_ENTRY) || !m_lines.Exists(LINEROLE_SL))
      return RdFail(r, refused + "no Entry and SL lines - click Add Pend Line first");

   //--- plan: order type from the lines, BC-07 distances, TP by mode (04 sections 7-8)
   SLines lines;
   m_lines.Read(LINES_PENDING, lines);
   SPlanSettings p;
   m_cfg.Plan(p);
   STradePlan plan;
   SResult pr;
   if(!CPlanner::Pending(lines, q, s, p, plan, pr))
      return RdFail(r, refused + pr.message);
   string order = RdOrderText(plan.side, plan.kind);
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar))
      return RdFail(r, refused + ar.message);

   //--- BC-05: money of Entry -> SL for 1 lot (commission added by CRiskMath, F-30)
   double loss = 0.0;
   SResult lr;
   if(!m_money.LossPerLot(s, acc.currency, plan.side, plan.entry, plan.sl, loss, lr))
      return RdFail(r, refused + lr.message);
   string notes = (lr.sev == SEV_WARN) ? lr.message : "";
   double profit = 0.0;
   if(plan.tp > 0.0)
     {
      SResult tr;
      if(!m_money.ProfitPerLot(s, acc.currency, plan.side, plan.entry, plan.tp, profit, tr))
         profit = 0.0;
     }

   //--- BC-10 netting: when it fills, the order merges with or reduces the symbol's position
   SPosition net;
   bool hasNet = false;
   if(!m_gw.IsHedging())
     {
      SResult nr;
      if(!NettingPosition(net, hasNet, nr))
         return RdFail(r, refused + nr.message);
     }
   bool opposite = hasNet && net.side != plan.side;
   string held = hasNet ? RdSideText(net.side) + " " + RdFormatLots(s, net.volume) + " lot position on " + _Symbol : "";
   if(opposite && !m_cfg.nettingAllowOpposite)
      return RdFail(r, refused + "netting account: when it fills, a " + order + " would reduce or reverse the open " + held +
                    " - use Half Close or Chart Close (or allow it with the input 'Netting: allow an opposite order')");
   //--- BC-04: MT5 volume limit per direction (open + pending)
   double sameSide = 0.0;
   if(s.volLimit > 0.0)
     {
      SResult vr;
      if(!SameSideVolume(plan.side, sameSide, vr))
         return RdFail(r, refused + vr.message);
     }
   //--- 04 sections 2-4: lots from Entry - SL
   SLotResult lot;
   SResult zr;
   if(!CPlanner::Size(plan, s, acc, p, m_state.riskPct, loss, profit, sameSide, lot, zr))
      return RdFail(r, refused + zr.message);
   if(zr.sev == SEV_WARN)
      notes = RdJoin(notes, zr.message, "; ");
   RD_LOG_INFO("[OP-07] plan: " + order + " " + RdFormatLots(s, plan.lots) + " " + _Symbol + " @" + RdFormatPrice(s, plan.entry) +
               " " + LevelsText(s, plan.sl, plan.tp, false) + ", risk " + RdMoney(acc, plan.riskMoney) + " (" +
               RdFormatPct(plan.riskPct) + " of " + RdMoney(acc, lot.base) + "), loss/lot " + RdNum(loss, 2) + " + commission " +
               RdNum(p.commissionPerLot, 2) + ", raw lots " + RdNum(lot.rawLots, 6) + ", Ask " + RdFormatPrice(s, q.ask) +
               ", Bid " + RdFormatPrice(s, q.bid));

   //--- F-16 caps; a same-direction netting order replaces the position's SL when it fills (BC-10)
   double added = plan.riskMoney;
   ulong replaced = 0;
   if(hasNet && !opposite)
     {
      SResult mr;
      if(!MergedRisk(s, acc, p, net, plan, added, mr))
         return RdFail(r, refused + mr.message);
      replaced = net.ticket;
     }
   SBudgetResult bud;
   SResult br;
   if(!CheckBudget(acc, p, replaced, added, plan.riskMoney, bud, br))
      return RdFail(r, refused + br.message);

   //--- F-31 margin at the entry price (may reduce the lots with InpReduceToMargin)
   double lots = plan.lots;
   SResult gm;
   if(!CheckMargin(s, plan.side, acc, plan.entry, lots, notes, gm))
      return RdFail(r, refused + gm.message);
   if(RdVolLt(lots, plan.lots))
     {
      plan.lots = lots;
      plan.riskMoney = lots * lot.lossPerLotAll;
      plan.riskPct = (lot.base > 0.0) ? plan.riskMoney / lot.base * 100.0 : 0.0;
     }

   //--- confirmations: BC-10 netting (always), InpConfirmTrades
   string what = order + " " + RdFormatLots(s, plan.lots) + " " + _Symbol + " @" + RdFormatPrice(s, plan.entry);
   bool yes = true;
   if(hasNet && !opposite)
      yes = Confirm("netting account", "Netting account: when it fills, this " + what + " merges with the open " + held +
                    " and replaces its SL/TP with " + LevelsText(s, plan.sl, plan.tp, false) +
                    ".\n\nRisk of the whole position at the new SL: " + RdMoney(acc, added) + ".\n\nContinue?");
   else
      if(opposite)
         yes = Confirm("netting account", "Netting account: when it fills, this " + what + " reduces, closes or reverses the open " +
                       held + ".\n\nContinue?");
      else
         if(m_cfg.confirmTrades)
            yes = Confirm(name, what + "?\n\n" + LevelsText(s, plan.sl, plan.tp, false) + "\nRisk " + RdMoney(acc, plan.riskMoney) +
                          " (" + RdFormatPct(plan.riskPct) + ")");
   if(!yes)
      return RdWarn(r, name + " cancelled - nothing was sent");

   //--- G-02 (BC-06 pending filling ladder, BC-08 expiration ladder, SL verified: rule R7)
   STradeOutcome out;
   SResult gr;
   if(!m_gw.PlacePending(_Symbol, plan.side, plan.kind, plan.lots, plan.entry, plan.sl, plan.tp, out, gr))
      return RdFail(r, name + " failed: " + gr.message);
   return Placed(order, s, acc, plan, out, notes, r);
  }

//+------------------------------------------------------------------+
//| Status after G-02: "Buy Stop 0.35 EURUSD @1.10250 placed . risk  |
//| $100.00 (1.00 %) . #123457" (+ expiry, + amber notes). Lines     |
//| removed unless kept; screenshot "pending".                       |
//+------------------------------------------------------------------+
bool CCommands::Placed(const string order, const SSymbolSpec &s, const SAccountSpec &acc, const STradePlan &plan,
                       const STradeOutcome &out, string notes, SResult &r)
  {
   double vol = (out.volume > 0.0) ? out.volume : plan.lots;
   double price = (out.price > 0.0) ? out.price : plan.entry;
   notes = RdJoin(notes, out.notes, "; ");
   LinesDone();
   AskShot("pending", out.ticket);
   string msg = order + " " + RdFormatLots(s, vol) + " " + _Symbol + " @" + RdFormatPrice(s, price) + " placed" + RdSep() +
                "risk " + RdMoney(acc, plan.riskMoney) + " (" + RdFormatPct(plan.riskPct) + ")" + RdSep() + RdTicketText(out.ticket);
   if(out.expiration > 0)
      msg += RdSep() + "expires " + TimeToString(out.expiration, TIME_DATE | TIME_MINUTES) + " server time";
   RD_LOG_INFO("[OP-07] done: " + msg + ", SL " + RdFormatPrice(s, out.sl > 0.0 ? out.sl : plan.sl) + ", TP " +
               (out.tp > 0.0 ? RdFormatPrice(s, out.tp) : "none") + ", time " + out.timePolicy +
               (out.filling != "" ? ", filling " + out.filling : "") + (notes != "" ? " (" + notes + ")" : ""));
   if(notes != "")
      return RdWarn(r, msg + " - " + notes);
   return RdOk(r, msg);
  }

//+------------------------------------------------------------------+
//| OP-08 Del Pending (F-10): tickets collected first, then G-05     |
//| each (BC-07 freeze check in the gateway).                        |
//+------------------------------------------------------------------+
bool CCommands::DelPending(SResult &r)
  {
   const string name = "Del Pending";
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, name + " refused: " + why.message);
   bool toolOnly = (m_cfg.scopeChartOps == SCOPE_TOOL_ON_SYMBOL);
   STradeFilter f;
   f.Reset();
   f.symbol = _Symbol;
   f.toolOnly = toolOnly;
   f.includeStopLimit = true;   // MT5 stop-limit orders are deleted too (06 OP-08)
   SOrder ord[];
   SResult lr;
   if(!m_gw.ListPending(f, ord, lr))
      return RdFail(r, name + " failed: " + lr.message);
   int n = ArraySize(ord);
   string which = (toolOnly ? "RiskDesk " : "") + "pending order";
   if(n == 0)
      return RdWarn(r, "No " + which + "s on " + _Symbol);
   ulong tickets[];
   ArrayResize(tickets, n);
   for(int i = 0; i < n; i++)
      tickets[i] = ord[i].ticket;
   int deleted = 0;
   int gone = 0;
   ulong one = 0;
   string failed = "";
   for(int k = 0; k < n; k++)
     {
      SResult dr;
      bool ok = m_gw.DeletePending(tickets[k], dr);
      if(ok && dr.sev == SEV_OK)
        {
         deleted++;
         one = tickets[k];
        }
      else
         if(ok)
            gone++;   // filled or deleted meanwhile
         else
            failed = RdJoin(failed, RdTicketText(tickets[k]) + " (" + dr.message + ")", "; ");
     }
   if(deleted > 0)
      AskShot("delpending", deleted == 1 ? one : 0);
   string msg = "Deleted " + IntegerToString(deleted) + " of " + IntegerToString(n) + " " + which + (n == 1 ? "" : "s") +
                " on " + _Symbol;
   if(gone > 0)
      msg += RdSep() + IntegerToString(gone) + " already gone (filled or deleted elsewhere)";
   if(failed != "")
      msg += RdSep() + "not deleted: " + failed;
   RD_LOG_INFO("[OP-08] " + msg);
   if(failed != "" && deleted == 0)
      return RdFail(r, msg);
   if(failed != "" || gone > 0)
      return RdWarn(r, msg);
   return RdOk(r, msg);
  }

// Both unset, or equal within half a tick.
bool CCommands::SameLevel(const SSymbolSpec &s, const double a, const double b)
  {
   if((a > 0.0) != (b > 0.0))
      return false;
   return !(a > 0.0) || RdPriceEq(s, a, b);
  }

//+------------------------------------------------------------------+
//| OP-16 (F-22 AC2): a line of placed order 'ticket' was dropped at |
//| 'dropped'. Entry line: the whole order moves; SL/TP line: only   |
//| that level. The lot stays (MetaTrader cannot change it), so the  |
//| risk follows the new prices: above a cap -> refused; above the   |
//| panel's Risk % -> done with an amber note (D5).                  |
//+------------------------------------------------------------------+
bool CCommands::MoveOrder(const ulong ticket, const ELineRole role, const double dropped, SResult &r)
  {
   r.Reset();
   m_raise = false;
   m_shotAction = "";
   m_shotTicket = 0;
   string who = RdTicketText(ticket);
   SOrder o;
   if(!m_gw.SelectPending(ticket, o))
      return RdWarn(r, "Order " + who + " no longer exists (filled or deleted) - nothing changed");
   string name = RdOrderText(o.side, o.kind) + " " + who;
   string refused = name + " not moved: ";
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, refused + why.message);
   SSymbolSpec s;
   SResult sr;
   if(!CSymbolSpec::Read(o.symbol, s, sr))
      return RdFail(r, refused + sr.message);
   SQuote q;
   if(!CMarket::Quote(o.symbol, q))
      return RdFail(r, refused + "no quote for " + o.symbol);
   if(!(o.sl > 0.0))
      return RdFail(r, refused + "it has no SL, so its risk cannot be checked - set an SL in MetaTrader first");

   //--- new prices, order type kept, BC-07 stops and freeze levels (04 section 7)
   SOrder moved;
   SResult pr;
   if(!CPlanner::MovePending(o, role, dropped, q, s, moved, pr))
      return RdFail(r, refused + pr.message);
   if(RdPriceEq(s, moved.price, o.price) && SameLevel(s, moved.sl, o.sl) && SameLevel(s, moved.tp, o.tp))
      return RdWarn(r, name + ": the " + CLines::RoleText(role) + " line was dropped at the order's own price - nothing changed");

   //--- risk with the lot unchanged (04 section 5)
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar))
      return RdFail(r, refused + ar.message);
   SPlanSettings p;
   m_cfg.Plan(p);
   double comm = MathMax(0.0, p.commissionPerLot);
   double newLoss = 0.0;
   SResult nl;
   if(!m_money.LossPerLot(s, acc.currency, o.side, moved.price, moved.sl, newLoss, nl))
      return RdFail(r, refused + nl.message);
   double newRisk = CRiskMath::PositionRisk(newLoss, comm, o.volume);
   double oldLoss = 0.0;
   SResult ol;
   double oldRisk = m_money.LossPerLot(s, acc.currency, o.side, o.price, o.sl, oldLoss, ol) ?
                    CRiskMath::PositionRisk(oldLoss, comm, o.volume) : MathSqrt(-1.0);
   bool counted = (o.magic == p.magic) && p.includePendingInTotalRisk;
   double open = 0.0;
   if(CRiskBudget::MoveNeedsOpenRisk(counted, oldRisk, newRisk))
     {
      STradeFilter f;
      f.Reset();
      f.toolOnly = true;
      SPosition pos[];
      SOrder ord[];
      SResult lr;
      if(!m_gw.ListPositions(f, pos, lr) || !m_gw.ListPending(f, ord, lr))
         return RdFail(r, refused + "open risk cannot be checked: " + lr.message);
      m_money.FillLossToSl(pos, acc.currency, p.commissionPerLot);
      m_money.FillLossToSl(ord, acc.currency, p.commissionPerLot);
      SBudgetResult openBud;
      SResult orr;
      if(!CRiskBudget::OpenRisk(pos, ord, p, openBud, orr))
         return RdFail(r, refused + orr.message);
      open = openBud.openRisk;
     }
   SBudgetResult bud;
   SResult br;
   if(!CRiskBudget::CheckMove(acc, p, counted, open, oldRisk, newRisk, bud, br))
      return RdFail(r, refused + br.message);
   double base = CRiskMath::RiskBase(p.riskBase, acc.balance, acc.equity);
   double pct = (base > 0.0) ? newRisk / base * 100.0 : 0.0;
   RD_LOG_INFO("[OP-16] " + name + " " + CLines::RoleText(role) + " dropped at " + RdFormatPrice(s, dropped) + ": @" +
               RdFormatPrice(s, o.price) + " SL " + RdFormatPrice(s, o.sl) + " TP " + RdFormatPrice(s, o.tp) + " -> @" +
               RdFormatPrice(s, moved.price) + " SL " + RdFormatPrice(s, moved.sl) + " TP " + RdFormatPrice(s, moved.tp) +
               ", " + RdFormatLots(s, o.volume) + " lot, risk " + RdMoney(acc, MathIsValidNumber(oldRisk) ? oldRisk : 0.0) + " -> " +
               RdMoney(acc, newRisk) + " (" + RdFormatPct(pct) + "), " + br.message);

   //--- G-08 (type_time and expiration kept, BC-08)
   SResult gr;
   if(!m_gw.ModifyPending(ticket, moved.price, moved.sl, moved.tp, gr))
      return RdFail(r, refused + gr.message);
   AskShot("modify", ticket);
   string change = "";
   if(role == LINEROLE_ENTRY)
      change = "moved to " + RdFormatPrice(s, moved.price) + " (SL " + RdFormatPrice(s, moved.sl) +
               (moved.tp > 0.0 ? ", TP " + RdFormatPrice(s, moved.tp) : "") + ")";
   else
      if(role == LINEROLE_SL)
         change = "SL " + RdFormatPrice(s, moved.sl);
      else
         change = "TP " + RdFormatPrice(s, moved.tp);
   string msg = name + " " + change + RdSep() + "risk " + RdMoney(acc, newRisk) + " (" + RdFormatPct(pct) + ")";
   if(NormalizeDouble(pct, 2) > m_state.riskPct + RD_PCT_EPS)
      return RdWarn(r, msg + " - risk now " + RdFormatPct(pct) + " (panel " + RdFormatPct(m_state.riskPct) + ")");
   return RdOk(r, msg);
  }

#endif // RD_APP_COMMANDSPENDING_MQH
