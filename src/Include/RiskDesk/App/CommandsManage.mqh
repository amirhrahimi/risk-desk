//+------------------------------------------------------------------+
//| RiskDesk - App/CommandsManage.mqh                                |
//| Layer   : App                                                    |
//| Purpose : managing open trades (06 section 3, OP-09..OP-12):     |
//|           - Risk Free: the SL of every position in chart scope   |
//|             that is far enough in profit goes to the open price  |
//|             + offset (04 section 9); never loosened, TP kept;    |
//|             G-03 each                                            |
//|           - Half Close: InpPartialClosePct of every position in  |
//|             chart scope (04 section 10), indivisible ones per    |
//|             InpPartialIndivisible; G-04 each                     |
//|           - Chart Close: every position in chart scope; G-04     |
//|           - Full Close: every position in account scope, grouped |
//|             by symbol, "Closing 4/9..." while it runs; pending   |
//|             orders too with InpFullCloseAlsoPending; G-04 / G-05 |
//|           Tickets are collected first and each one is selected   |
//|           again before acting: a position gone meanwhile counts  |
//|           as "already closed" (amber). BC-07 freeze levels and   |
//|           BC-10 netting are checked / handled by the gateway     |
//|           (G-03, G-04). Confirmations per F-28. Every command    |
//|           ends with the counts and every skipped or failed item  |
//|           with its reason (R8).                                  |
//|           Part of CCommands; included at the end of              |
//|           App/Commands.mqh.                                      |
//+------------------------------------------------------------------+
#ifndef RD_APP_COMMANDSMANAGE_MQH
#define RD_APP_COMMANDSMANAGE_MQH

#define RD_MANAGE_MAX_PARTS  100   // D35: requests for one full close above the max volume

//====================================================================
// Scopes, progress, text
//====================================================================

// 06 section 3 ChartScope(): the chart symbol; RiskDesk's own trades only with SCOPE_TOOL_ON_SYMBOL.
void CCommands::ChartFilter(STradeFilter &f) const
  {
   f.Reset();
   f.symbol = _Symbol;
   f.toolOnly = (m_cfg.scopeChartOps == SCOPE_TOOL_ON_SYMBOL);
  }

// 06 section 3 AccountScope(): every symbol; RiskDesk's own trades only with SCOPE_TOOL_ACCOUNT.
// Pending orders (InpFullCloseAlsoPending) include MT5 stop-limit orders, as Del Pending does.
void CCommands::AccountFilter(STradeFilter &f) const
  {
   f.Reset();
   f.toolOnly = (m_cfg.scopeFullClose == SCOPE_TOOL_ACCOUNT);
   f.includeStopLimit = true;
  }

// "+$3.20", "-$12.40", "$0.00"
string CCommands::PlText(const SAccountSpec &acc, const double pl) const
  {
   return (NormalizeDouble(pl, acc.digitsCcy) > 0.0 ? "+" : "") + RdMoney(acc, pl);
  }

void CCommands::Progress(const string text)
  {
   m_lastProgress = text;
   if(CheckPointer(m_progress) != POINTER_INVALID)
      m_progress.Progress(text);
  }

//====================================================================
// OP-09 Risk Free (F-11)
//====================================================================

//+------------------------------------------------------------------+
//| Status "Risk-free on EURUSD: 1 moved . 1 not enough profit .     |
//| 1 already protected - #123 SL 1.09800 -> 1.10012; #124 needs     |
//| Bid >= 1.10043; #125 already at SL 1.10020". Green only when     |
//| something moved and nothing needs attention ("already protected" |
//| does not); red when nothing moved because of failures.           |
//+------------------------------------------------------------------+
bool CCommands::RiskFree(SResult &r)
  {
   const string name = "Risk Free";
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, name + " refused: " + why.message);
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(name, s, q, r))   // PF-2, PF-3
      return false;
   STradeFilter f;
   ChartFilter(f);
   SPosition pos[];
   SResult lr;
   if(!m_gw.ListPositions(f, pos, lr))
      return RdFail(r, name + " failed: " + lr.message);
   int n = ArraySize(pos);
   string which = (f.toolOnly ? "RiskDesk " : "") + "positions";
   if(n == 0)
      return RdWarn(r, name + ": no " + which + " on " + _Symbol);
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar))
      return RdFail(r, name + " refused: " + ar.message);
   SPlanSettings p;
   m_cfg.Plan(p);
   ulong tickets[];
   ArrayResize(tickets, n);
   for(int i = 0; i < n; i++)
      tickets[i] = pos[i].ticket;

   int moved = 0, notInProfit = 0, notEnough = 0, prot = 0, frozen = 0, gone = 0, failed = 0;
   ulong one = 0;
   string items = "";
   for(int k = 0; k < n; k++)
     {
      if(n > 1)
         Progress(name + ": " + IntegerToString(k + 1) + "/" + IntegerToString(n) + "...");
      SPosition cur;
      string who = RdTicketText(tickets[k]);
      if(!m_gw.SelectPosition(tickets[k], cur))
        {
         gone++;
         items = RdJoin(items, who + " already closed", "; ");
         continue;
        }
      SRiskFreeResult rf;
      SResult pr;
      if(!PlanRiskFree(cur, s, acc, p, rf, pr))
        {
         string item = who + " " + pr.message;
         if(pr.sev == SEV_ERROR)
           {
            failed++;
            item = who + " not moved: " + pr.message;
           }
         else
            switch(rf.skip)
              {
               case RFSKIP_NOT_IN_PROFIT:
                  notInProfit++;
                  break;
               case RFSKIP_PROTECTED:
                  prot++;
                  item = who + " already at SL " + RdFormatPrice(s, cur.sl);
                  break;
               case RFSKIP_NOT_ENOUGH:
                  notEnough++;
                  item = who + " needs " + (cur.side == SIDE_BUY ? "Bid >= " : "Ask <= ") + RdFormatPrice(s, rf.needPrice);
                  break;
               default:
                  frozen++;
                  break;
              }
         RD_LOG_INFO("[OP-09] " + RdSideText(cur.side) + " " + who + " " + RdFormatLots(s, cur.volume) + " @" +
                     RdFormatPrice(s, cur.open) + " SL " + RdFormatPrice(s, cur.sl) + ": " + pr.message);
         items = RdJoin(items, item, "; ");
         continue;
        }
      SResult gr;
      if(!m_gw.ModifyPositionSLTP(cur.ticket, rf.target, cur.tp, gr))
        {
         SPosition again;
         if(!m_gw.SelectPosition(cur.ticket, again))
           {
            gone++;
            items = RdJoin(items, who + " already closed", "; ");
            continue;
           }
         failed++;
         items = RdJoin(items, who + " not moved: " + gr.message, "; ");
         continue;
        }
      moved++;
      one = cur.ticket;
      items = RdJoin(items, who + " SL " + (cur.sl > 0.0 ? RdFormatPrice(s, cur.sl) : "none") + " -> " +
                     RdFormatPrice(s, rf.target), "; ");
      RD_LOG_INFO("[OP-09] " + RdSideText(cur.side) + " " + who + " " + RdFormatLots(s, cur.volume) + " @" +
                  RdFormatPrice(s, cur.open) + ": SL " + RdFormatPrice(s, cur.sl) + " -> " + RdFormatPrice(s, rf.target) +
                  " (offset " + RdNum(rf.offset, s.digits) + " = " + EnumToString(p.riskFreeMode) + ", cost part " +
                  RdNum(rf.costDistance, s.digits + 2) + ", extra " + IntegerToString(p.riskFreeExtraPoints) + " pts), TP " +
                  (cur.tp > 0.0 ? RdFormatPrice(s, cur.tp) : "none") + " kept");
     }

   if(moved > 0)
      AskShot("riskfree", moved == 1 ? one : 0);
   string msg = "Risk-free on " + _Symbol + ": " + IntegerToString(moved) + " moved";
   if(notInProfit > 0)
      msg += RdSep() + IntegerToString(notInProfit) + " not in profit";
   if(notEnough > 0)
      msg += RdSep() + IntegerToString(notEnough) + " not enough profit";
   if(prot > 0)
      msg += RdSep() + IntegerToString(prot) + " already protected";
   if(frozen > 0)
      msg += RdSep() + IntegerToString(frozen) + " frozen";
   if(gone > 0)
      msg += RdSep() + IntegerToString(gone) + " already closed";
   if(failed > 0)
      msg += RdSep() + IntegerToString(failed) + " failed";
   msg += " - " + items;
   if(failed > 0 && moved == 0)
      return RdFail(r, msg);
   if(moved > 0 && failed + notInProfit + notEnough + frozen + gone == 0)
      return RdOk(r, msg);
   return RdWarn(r, msg);
  }

//+------------------------------------------------------------------+
//| 04 section 9 for one position with a fresh quote. The commission |
//| distance needs the money of one tick (BC-05); RF_COMMISSION the  |
//| costs booked on the position (Platform/History).                 |
//+------------------------------------------------------------------+
bool CCommands::PlanRiskFree(const SPosition &pos, const SSymbolSpec &s, const SAccountSpec &acc, const SPlanSettings &p,
                             SRiskFreeResult &rf, SResult &r)
  {
   rf.Reset();
   r.Reset();
   SQuote q;
   if(!CMarket::Quote(pos.symbol, q))
      return RdFail(r, "no quote for " + pos.symbol);
   SRiskFreeInput in;
   in.Reset();
   in.side = pos.side;
   in.open = pos.open;     // netting: the averaged open price (BC-10)
   in.sl = pos.sl;
   in.tp = pos.tp;
   in.volume = pos.volume;
   bool needTick = (p.riskFreeMode == RF_SPREAD_COMMISSION && p.commissionPerLot > 0.0);
   if(p.riskFreeMode == RF_COMMISSION)
     {
      SResult cr;
      if(!CHistory::BookedCost(pos.ticket, in.bookedCost, cr))
         return RdFail(r, cr.message);
      needTick = (in.bookedCost > 0.0);
     }
   if(needTick)
     {
      SResult mr;
      // on failure the planner still says "not in profit" first, else "Cannot value the commission"
      if(!MoneyPerTick(s, acc, pos.side, pos.open, in.tickValue, mr))
         RD_LOG_WARN("[OP-09] " + RdTicketText(pos.ticket) + ": " + mr.message);
     }
   return CPlanner::RiskFree(in, q, s, p, rf, r);
  }

//+------------------------------------------------------------------+
//| BC-05: money of a one-tick move for 1.0 lot in the position's    |
//| favour, valued over 1000 ticks (OrderCalcProfit rounds to cents).|
//+------------------------------------------------------------------+
bool CCommands::MoneyPerTick(const SSymbolSpec &s, const SAccountSpec &acc, const ESide side, const double open,
                             double &perTick, SResult &r)
  {
   perTick = 0.0;
   double tick = RdTick(s);
   if(!(tick > 0.0) || !(open > 0.0))
      return RdFail(r, "Cannot value a tick of " + s.name);
   double ticks = 1000.0;
   if(side == SIDE_SELL && !(open - ticks * tick > 0.5 * open))
      ticks = MathMax(1.0, MathFloor(0.5 * open / tick));
   double to = RdNormalizePrice(s, (side == SIDE_BUY) ? open + ticks * tick : open - ticks * tick);
   double value = 0.0;
   if(!m_money.ProfitPerLot(s, acc.currency, side, open, to, value, r))
      return false;
   double moved = RdTicksBetween(s, open, to);
   if(!(value > 0.0) || !(moved > 0.0))
      return RdFail(r, "Cannot value a tick of " + s.name);
   perTick = value / moved;
   return RdOk(r, "");
  }

//====================================================================
// OP-10 Half Close (F-12)
//====================================================================

//+------------------------------------------------------------------+
//| Every position is planned first (04 section 10), then the        |
//| confirmation (InpConfirmHalfClose), then G-04 each. Status       |
//| "Half-closed 2 positions on EURUSD (0.25 + 0.10 lot) . P/L       |
//| +$3.20 . 1 skipped - #123 0.25 of 0.50 lot, rest #129; #124      |
//| 0.01 lot cannot be split at 50 % (min 0.01, step 0.01)".         |
//| MT4: the rest usually gets a new ticket (BC-16), named in the    |
//| item; it is not in the collected list, so it is never halved     |
//| again by the same click.                                         |
//+------------------------------------------------------------------+
bool CCommands::HalfClose(SResult &r)
  {
   const string name = "Half Close";
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, name + " refused: " + why.message);
   SSymbolSpec s;
   SResult sr;
   if(!CSymbolSpec::Read(_Symbol, s, sr))
      return RdFail(r, name + " refused: " + sr.message);
   STradeFilter f;
   ChartFilter(f);
   SPosition pos[];
   SResult lr;
   if(!m_gw.ListPositions(f, pos, lr))
      return RdFail(r, name + " failed: " + lr.message);
   int n = ArraySize(pos);
   string which = (f.toolOnly ? "RiskDesk " : "") + "positions";
   if(n == 0)
      return RdWarn(r, name + ": no " + which + " on " + _Symbol);
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar))
      return RdFail(r, name + " refused: " + ar.message);
   SPlanSettings p;
   m_cfg.Plan(p);

   //--- plan: what to close of each position
   ulong tickets[];
   double vols[];
   double held[];
   bool whole[];
   ArrayResize(tickets, n);
   ArrayResize(vols, n);
   ArrayResize(held, n);
   ArrayResize(whole, n);
   int m = 0;
   int skipped = 0;
   string skips = "";
   string planned = "";
   for(int i = 0; i < n; i++)
     {
      SPartialClose pc;
      SResult pr;
      string who = RdTicketText(pos[i].ticket);
      if(!CRiskMath::PartialClose(pos[i].volume, s, p, pc, pr))
        {
         skipped++;
         skips = RdJoin(skips, who + " " + pr.message, "; ");
         RD_LOG_INFO("[OP-10] " + who + " skipped: " + pr.message);
         continue;
        }
      tickets[m] = pos[i].ticket;
      vols[m] = pc.closeVolume;
      held[m] = pos[i].volume;
      whole[m] = pc.closeAll;
      planned = RdJoin(planned, RdFormatLots(s, pc.closeVolume), " + ");
      m++;
     }
   string pct = RdFormatCapPct(m_cfg.partialClosePct);
   if(m == 0)
      return RdWarn(r, name + ": nothing closed on " + _Symbol + RdSep() + IntegerToString(skipped) + " skipped - " + skips);

   //--- F-28
   if(m_cfg.confirmHalfClose &&
      !Confirm(name, "Close " + pct + " of " + IntegerToString(m) + " position" + (m == 1 ? "" : "s") + " on " + _Symbol +
               " (" + planned + " lot)?" + (skipped > 0 ? "\n\n" + IntegerToString(skipped) + " cannot be split and stay" +
               (skipped == 1 ? "s" : "") + ": " + skips : "")))
      return RdWarn(r, name + " cancelled - nothing was sent");

   //--- G-04 each
   int closed = 0, gone = 0, failed = 0, known = 0, all = 0;
   double pl = 0.0;
   ulong one = 0;
   string done = "";
   string items = "";
   string notes = "";
   for(int k = 0; k < m; k++)
     {
      if(m > 1)
         Progress(name + ": closing " + IntegerToString(k + 1) + "/" + IntegerToString(m) + "...");
      string who = RdTicketText(tickets[k]);
      STradeOutcome out;
      SResult cr;
      bool ok = whole[k] ? CloseWhole(tickets[k], out, cr) : m_gw.ClosePosition(tickets[k], vols[k], out, cr);
      if(!ok)
        {
         failed++;
         items = RdJoin(items, who + " not closed: " + cr.message, "; ");
         continue;
        }
      if(out.alreadyDone)
        {
         gone++;
         items = RdJoin(items, who + " already closed", "; ");
         continue;
        }
      closed++;
      one = tickets[k];
      double vol = (out.volume > 0.0) ? out.volume : vols[k];
      done = RdJoin(done, RdFormatLots(s, vol), " + ");
      if(out.profitKnown)
        {
         known++;
         pl += out.profit;
        }
      string item = who + " " + (whole[k] ? "all " + RdFormatLots(s, vol) + " lot (cannot be split)" :
                                 RdFormatLots(s, vol) + " of " + RdFormatLots(s, held[k]) + " lot");
      if(whole[k])
         all++;
      if(out.remainder > 0 && out.remainder != tickets[k])
         item += ", rest " + RdFormatLots(s, out.remaining) + " is now " + RdTicketText(out.remainder);
      items = RdJoin(items, item, "; ");
      if(cr.sev == SEV_WARN)
         notes = RdJoin(notes, cr.message, "; ");
     }

   if(closed > 0)
      AskShot("half", closed == 1 ? one : 0);
   string msg = "Half-closed " + IntegerToString(closed) + " position" + (closed == 1 ? "" : "s") + " on " + _Symbol +
                (done != "" ? " (" + done + " lot)" : "");
   if(known > 0)
      msg += RdSep() + "P/L " + PlText(acc, pl) + (known < closed ? " (" + IntegerToString(known) + " of " +
             IntegerToString(closed) + " closes)" : "");
   if(skipped > 0)
      msg += RdSep() + IntegerToString(skipped) + " skipped";
   if(gone > 0)
      msg += RdSep() + IntegerToString(gone) + " already closed";
   if(failed > 0)
      msg += RdSep() + IntegerToString(failed) + " failed";
   msg += " - " + RdJoin(items, skips, "; ");
   if(notes != "")
      msg += RdSep() + notes;
   if(failed > 0 && closed == 0)
      return RdFail(r, msg);
   if(closed > 0 && skipped + gone + failed + all == 0 && notes == "")
      return RdOk(r, msg);
   return RdWarn(r, msg);
  }

//====================================================================
// OP-11 Chart Close (F-13) and OP-12 Full Close (F-14)
//====================================================================

//+------------------------------------------------------------------+
//| G-04 for the whole position. Above the broker's maximum volume   |
//| per request it is closed in parts (D35), following the rest's    |
//| ticket (MT4 gives it a new one, BC-16); 'out' sums the parts.    |
//+------------------------------------------------------------------+
bool CCommands::CloseWhole(const ulong ticket, STradeOutcome &out, SResult &r)
  {
   out.Reset();
   out.ticket = ticket;
   SPosition p;
   SSymbolSpec s;
   SResult sr;
   if(!m_gw.SelectPosition(ticket, p) || !CSymbolSpec::Read(p.symbol, s, sr) || !(s.volMax > 0.0) ||
      !RdVolGt(p.volume, s.volMax))
      return m_gw.ClosePosition(ticket, 0.0, out, r);   // also says "already closed" when it is gone

   string who = RdTicketText(ticket);
   double total = p.volume;
   RD_LOG_INFO("[G-04] " + p.symbol + " " + who + " " + RdFormatLots(s, total) + " lot is above the maximum " +
               RdFormatLots(s, s.volMax) + " per request: closing it in parts");
   ulong cur = ticket;
   double left = total;
   double closed = 0.0;
   double pl = 0.0;
   bool known = true;
   int parts = 0;
   int sends = 0;
   while(parts < RD_MANAGE_MAX_PARTS)
     {
      double chunk = 0.0;
      if(!CRiskMath::CloseChunk(left, s, chunk))
         break;
      bool rest = RdVolLt(chunk, left);
      STradeOutcome part;
      SResult pr;
      bool ok = m_gw.ClosePosition(cur, rest ? chunk : 0.0, part, pr);
      sends += part.sends;
      if(!ok || part.alreadyDone)
        {
         if(parts == 0)
           {
            out = part;
            r = pr;
            return ok;
           }
         if(!ok)
           {
            out.volume = closed;
            out.profit = pl;
            out.profitKnown = known;
            out.sends = sends;
            return RdFail(r, "closed " + RdFormatLots(s, closed) + " of " + RdFormatLots(s, total) + " lot, then: " + pr.message);
           }
         break;   // the rest went meanwhile
        }
      parts++;
      closed += (part.volume > 0.0) ? part.volume : chunk;
      if(part.profitKnown)
         pl += part.profit;
      else
         known = false;
      out.price = part.price;
      out.deal = part.deal;
      out.order = part.order;
      out.filling = part.filling;
      if(!rest || part.remainder == 0)
         break;
      cur = part.remainder;
      SPosition again;
      if(!m_gw.SelectPosition(cur, again))
         break;
      left = again.volume;
     }
   out.requested = total;
   out.volume = closed;
   out.profit = pl;
   out.profitKnown = known && parts > 0;
   out.sends = sends;
   if(RdVolLt(closed, total))
     {
      out.remainder = cur;
      out.remaining = total - closed;
      return RdWarn(r, "Closed " + RdFormatLots(s, closed) + " of " + RdFormatLots(s, total) + " " + p.symbol + " " + who +
                    " in " + IntegerToString(parts) + " requests - the rest is still open, check the Trade tab");
     }
   return RdOk(r, "Closed " + RdFormatLots(s, closed) + " " + p.symbol + " " + who + " in " + IntegerToString(parts) + " requests");
  }

//+------------------------------------------------------------------+
//| Close every collected ticket; "Closing 4/9..." while it runs.    |
//| labels[k] names the item in the failures ("#123", "XAUUSD #123").|
//+------------------------------------------------------------------+
void CCommands::CloseTickets(const ulong &tickets[], const string &labels[], SCloseTally &t)
  {
   t.Reset();
   int n = ArraySize(tickets);
   for(int k = 0; k < n; k++)
     {
      if(n > 1)
         Progress("Closing " + IntegerToString(k + 1) + "/" + IntegerToString(n) + "...");
      STradeOutcome out;
      SResult cr;
      if(!CloseWhole(tickets[k], out, cr))
        {
         t.failed++;
         t.failures = RdJoin(t.failures, labels[k] + " (" + cr.message + ")", "; ");
         continue;
        }
      if(out.alreadyDone)
        {
         t.gone++;
         continue;
        }
      t.closed++;
      t.one = tickets[k];
      t.volume += out.volume;
      if(out.profitKnown)
        {
         t.known++;
         t.pl += out.profit;
        }
      if(cr.sev == SEV_WARN)
         t.notes = RdJoin(t.notes, labels[k] + ": " + cr.message, "; ");
     }
  }

// " . P/L -$12.40 . 1 already closed . not closed: #123 (reason)"
string CCommands::CloseSummary(const SAccountSpec &acc, const SCloseTally &t) const
  {
   string msg = "";
   if(t.known > 0)
      msg += RdSep() + "P/L " + PlText(acc, t.pl) + (t.known < t.closed ? " (" + IntegerToString(t.known) + " of " +
             IntegerToString(t.closed) + " closes)" : "");
   if(t.gone > 0)
      msg += RdSep() + IntegerToString(t.gone) + " already closed";
   if(t.failures != "")
      msg += RdSep() + "not closed: " + t.failures;
   if(t.notes != "")
      msg += RdSep() + t.notes;
   return msg;
  }

// Red when nothing was closed because of failures; amber when anything needs a look.
bool CCommands::CloseResult(const string msg, const SCloseTally &t, SResult &r) const
  {
   if(t.failed > 0 && t.closed == 0)
      return RdFail(r, msg);
   if(t.failed > 0 || t.gone > 0 || t.notes != "")
      return RdWarn(r, msg);
   return RdOk(r, msg);
  }

//+------------------------------------------------------------------+
//| OP-11: every position in chart scope; pending orders stay.       |
//| Status "Closed 3 of 3 positions on EURUSD . P/L -$12.40".        |
//+------------------------------------------------------------------+
bool CCommands::ChartClose(SResult &r)
  {
   const string name = "Chart Close";
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, name + " refused: " + why.message);
   STradeFilter f;
   ChartFilter(f);
   SPosition pos[];
   SResult lr;
   if(!m_gw.ListPositions(f, pos, lr))
      return RdFail(r, name + " failed: " + lr.message);
   int n = ArraySize(pos);
   string which = (f.toolOnly ? "RiskDesk " : "") + "position";
   if(n == 0)
      return RdWarn(r, name + ": no " + which + "s on " + _Symbol);
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar))
      return RdFail(r, name + " refused: " + ar.message);
   ulong tickets[];
   string labels[];
   ArrayResize(tickets, n);
   ArrayResize(labels, n);
   double lots = 0.0;
   double floating = 0.0;
   for(int i = 0; i < n; i++)
     {
      tickets[i] = pos[i].ticket;
      labels[i] = RdTicketText(pos[i].ticket);
      lots += pos[i].volume;
      floating += pos[i].profit;
     }
   SSymbolSpec s;
   SResult sr;
   string lotText = CSymbolSpec::Read(_Symbol, s, sr) ? RdFormatLots(s, lots) : RdNum(lots, 2);
   if(m_cfg.confirmChartClose &&
      !Confirm(name, "Close " + IntegerToString(n) + " " + which + (n == 1 ? "" : "s") + " on " + _Symbol + " (" + lotText +
               " lot, floating P/L " + PlText(acc, floating) + ")?\n\nPending orders stay."))
      return RdWarn(r, name + " cancelled - nothing was sent");

   SCloseTally t;
   CloseTickets(tickets, labels, t);
   if(t.closed > 0)
      AskShot("chartclose", t.closed == 1 ? t.one : 0);
   string msg = "Closed " + IntegerToString(t.closed) + " of " + IntegerToString(n) + " " + which + (n == 1 ? "" : "s") +
                " on " + _Symbol + CloseSummary(acc, t);
   return CloseResult(msg, t, r);
  }

//+------------------------------------------------------------------+
//| OP-12: every position in account scope, grouped by symbol, then  |
//| (InpFullCloseAlsoPending) every pending order in account scope.  |
//| Confirmed by default: "Close 9 positions on 4 symbols?". Status  |
//| "Closed 9 of 9 positions on 4 symbols . P/L -$12.40 . deleted 2  |
//| of 2 pending orders . not closed: XAUUSD #123 (reason)".         |
//+------------------------------------------------------------------+
bool CCommands::FullClose(SResult &r)
  {
   const string name = "Full Close";
   SResult why;
   if(!CAccountSpec::CanTrade(why))
      return RdFail(r, name + " refused: " + why.message);
   STradeFilter f;
   AccountFilter(f);
   SPosition pos[];
   SOrder ord[];
   SResult lr;
   if(!m_gw.ListPositions(f, pos, lr))
      return RdFail(r, name + " failed: " + lr.message);
   if(m_cfg.fullCloseAlsoPending && !m_gw.ListPending(f, ord, lr))
      return RdFail(r, name + " failed: " + lr.message);
   int n = ArraySize(pos);
   int no = ArraySize(ord);
   string which = (f.toolOnly ? "RiskDesk " : "") + "position";
   if(n == 0 && no == 0)
      return RdWarn(r, name + ": no " + which + "s on this account" + (m_cfg.fullCloseAlsoPending ? " and no pending orders" : ""));
   SAccountSpec acc;
   SResult ar;
   if(!CAccountSpec::Read(acc, ar))
      return RdFail(r, name + " refused: " + ar.message);

   //--- group by symbol, in the order the symbols first appear
   string syms[];
   int counts[];
   int ns = 0;
   double floating = 0.0;
   for(int i = 0; i < n; i++)
     {
      floating += pos[i].profit;
      int at = -1;
      for(int j = 0; j < ns && at < 0; j++)
         if(syms[j] == pos[i].symbol)
            at = j;
      if(at < 0)
        {
         ArrayResize(syms, ns + 1);
         ArrayResize(counts, ns + 1);
         syms[ns] = pos[i].symbol;
         counts[ns] = 0;
         at = ns++;
        }
      counts[at]++;
     }
   ulong tickets[];
   string labels[];
   ArrayResize(tickets, n);
   ArrayResize(labels, n);
   int m = 0;
   string perSymbol = "";
   for(int j = 0; j < ns; j++)
     {
      perSymbol = RdJoin(perSymbol, syms[j] + " " + IntegerToString(counts[j]), ", ");
      for(int i = 0; i < n; i++)
         if(pos[i].symbol == syms[j])
           {
            tickets[m] = pos[i].ticket;
            labels[m] = pos[i].symbol + " " + RdTicketText(pos[i].ticket);
            m++;
           }
     }
   string onSyms = IntegerToString(ns) + " symbol" + (ns == 1 ? "" : "s");

   //--- F-28 (InpConfirmFullClose, default on)
   if(m_cfg.confirmFullClose)
     {
      string text = (n > 0 ? "Close " + IntegerToString(n) + " " + which + (n == 1 ? "" : "s") + " on " + onSyms + "?\n\n" +
                     perSymbol + "\nFloating P/L " + PlText(acc, floating) : "No " + which + "s to close.");
      if(no > 0)
         text += "\n\n" + (n > 0 ? "Also delete " : "Delete ") + IntegerToString(no) + " pending order" + (no == 1 ? "" : "s") +
                 (n > 0 ? "." : "?");
      if(!Confirm(name, text))
         return RdWarn(r, name + " cancelled - nothing was sent");
     }

   //--- positions, then pending orders
   SCloseTally t;
   CloseTickets(tickets, labels, t);
   int deleted = 0, goneOrders = 0;
   string notDeleted = "";
   for(int k = 0; k < no; k++)
     {
      if(no > 1)
         Progress("Deleting " + IntegerToString(k + 1) + "/" + IntegerToString(no) + " pending orders...");
      SResult dr;
      bool ok = m_gw.DeletePending(ord[k].ticket, dr);
      if(ok && dr.sev == SEV_OK)
         deleted++;
      else
         if(ok)
            goneOrders++;   // filled or deleted meanwhile
         else
            notDeleted = RdJoin(notDeleted, ord[k].symbol + " " + RdTicketText(ord[k].ticket) + " (" + dr.message + ")", "; ");
     }

   if(t.closed > 0 || deleted > 0)
      AskShot("fullclose", (t.closed == 1 && deleted == 0) ? t.one : 0);
   string msg = (n > 0 ? "Closed " + IntegerToString(t.closed) + " of " + IntegerToString(n) + " " + which + (n == 1 ? "" : "s") +
                 " on " + onSyms : "No " + which + "s to close") + CloseSummary(acc, t);
   if(no > 0)
     {
      msg += RdSep() + "deleted " + IntegerToString(deleted) + " of " + IntegerToString(no) + " pending order" + (no == 1 ? "" : "s");
      if(goneOrders > 0)
         msg += RdSep() + IntegerToString(goneOrders) + " order" + (goneOrders == 1 ? "" : "s") + " already gone";
      if(notDeleted != "")
         msg += RdSep() + "not deleted: " + notDeleted;
     }
   // the orders count like positions for the colour
   SCloseTally all = t;
   all.closed += deleted;
   all.gone += goneOrders;
   if(notDeleted != "")
     {
      all.failed++;
      all.failures = RdJoin(all.failures, notDeleted, "; ");
     }
   return CloseResult(msg, all, r);
  }

#endif // RD_APP_COMMANDSMANAGE_MQH
