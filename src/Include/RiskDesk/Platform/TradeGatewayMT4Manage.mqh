// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayMT4Manage.mqh                    |
//| Layer   : Platform. Included only by TradeGatewayMT4.mqh.        |
//| Purpose : MT4 CTradeGateway, managing existing trades:           |
//|           G-03 ModifyPositionSLTP, G-08 ModifyPending,           |
//|           G-04 ClosePosition, G-05 DeletePending,                |
//|           G-06 ListPositions, G-07 ListPending, single selects.  |
//|           Every primitive checks BC-15 permissions and the BC-07 |
//|           stops/freeze levels before sending.                    |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYMT4MANAGE_MQH
#define RD_PLATFORM_TRADEGATEWAYMT4MANAGE_MQH

//+------------------------------------------------------------------+
//| G-03 ModifyPositionSLTP: OrderModify(ticket, open price, sl, tp) |
//+------------------------------------------------------------------+
bool CTradeGateway::ModifyPositionSLTP(const ulong ticket, const double sl, const double tp, SResult &r)
  {
   const string op = "G-03";
   r.Reset();
   string who = RdTicketText(ticket);
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, who, r);
   if(!SelectLive(ticket))
      return Refuse(op, who, r, "Position " + who + " not found (closed?)");
   if(OrderType() > OP_SELL)
      return Refuse(op, who, r, who + " is a pending order, not a position");
   string symbol = OrderSymbol();
   int type = OrderType();
   ESide side = (type == OP_BUY) ? SIDE_BUY : SIDE_SELL;
   double open = OrderOpenPrice();
   double curSl = OrderStopLoss();
   double curTp = OrderTakeProfit();
   SSymbolSpec s;
   SQuote quote;
   if(!SpecQuote(op, symbol, s, quote, r))
      return false;
   double nsl = (sl > 0.0) ? RdNormalizePrice(s, sl) : 0.0;
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   bool slChange = !LevelEq(s, curSl, nsl);
   bool tpChange = !LevelEq(s, curTp, ntp);
   if(!slChange && !tpChange)
     {
      RD_LOG_INFO("[" + op + "] " + symbol + " " + who + " SL/TP already " + Px(s, nsl) + "/" + Px(s, ntp));
      return RdOk(r, "Already set");
     }
#ifdef RD_TEST_HOOKS
   if(FaultIs(GWFAULT_SL_ATTACH))
      return Failed(op, symbol, r, "TEST FAULT: the server refuses to set SL/TP", RD_GW_TEST_FAULT_CODE);
#endif
   if(!CValidators::PositionNotFrozen(side, curSl, curTp, quote, s, r) ||
      !CValidators::MarketStops(side, slChange ? nsl : 0.0, tpChange ? ntp : 0.0, quote, s, r))
      return Refused(op, symbol, r);

   SMt4Request q;
   BaseRequest(q, symbol);
   q.cmd = type;
   q.ticket = (int)ticket;
   q.price = open;
   q.sl = nsl;
   q.tp = ntp;
   SSendCtx c;
   c.Reset();
   c.side = side;
   int done = 0;
   if(!Send(op, GWACT_SLTP, q, s, c, done, r))
      return false;
   return RdOk(r, "SL " + Px(s, nsl) + " TP " + Px(s, ntp) + " set on " + who);
  }

//+------------------------------------------------------------------+
//| G-08 ModifyPending: OrderModify(ticket, price, sl, tp, expiry)   |
//+------------------------------------------------------------------+
bool CTradeGateway::ModifyPending(const ulong ticket, const double price, const double sl, const double tp, SResult &r)
  {
   const string op = "G-08";
   r.Reset();
   string who = RdTicketText(ticket);
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, who, r);
   SOrder o;
   if(!SelectLive(ticket) || !ReadSelectedOrder(o))
      return Refuse(op, who, r, "Order " + who + " no longer exists");
   int type = OrderType();
   datetime expiration = OrderExpiration();
   SSymbolSpec s;
   SQuote quote;
   if(!SpecQuote(op, o.symbol, s, quote, r))
      return false;
   double np = RdNormalizePrice(s, price);
   double nsl = (sl > 0.0) ? RdNormalizePrice(s, sl) : 0.0;
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   if(RdPriceEq(s, np, o.price) && LevelEq(s, nsl, o.sl) && LevelEq(s, ntp, o.tp))
     {
      RD_LOG_INFO("[" + op + "] " + o.symbol + " " + who + " already @" + Px(s, np) + " sl=" + Px(s, nsl) + " tp=" + Px(s, ntp));
      return RdOk(r, "Already set");
     }
   if(!CValidators::PendingNotFrozen(o.side, o.kind, o.price, quote, s, r) ||
      !CValidators::PendingGeometry(o.side, o.kind, np, nsl, ntp, quote, s, r) ||
      !CValidators::PendingStops(o.side, o.kind, np, nsl, ntp, quote, s, r))
      return Refused(op, o.symbol, r);

   SMt4Request q;
   BaseRequest(q, o.symbol);
   q.cmd = type;
   q.ticket = (int)ticket;
   q.price = np;
   q.sl = nsl;
   q.tp = ntp;
   q.expiration = expiration;
   SSendCtx c;
   c.Reset();
   c.side = o.side;
   int done = 0;
   if(!Send(op, GWACT_MODIFY, q, s, c, done, r))
      return false;
   return RdOk(r, RdOrderText(o.side, o.kind) + " " + who + " @" + Px(s, np) + " sl " + Px(s, nsl) + " tp " + Px(s, ntp));
  }

//+------------------------------------------------------------------+
//| G-04 ClosePosition: OrderClose. A partial close leaves the rest  |
//| under a NEW ticket (BC-16), returned in out.remainder.           |
//+------------------------------------------------------------------+
bool CTradeGateway::ClosePosition(const ulong ticket, const double volume, STradeOutcome &out, SResult &r)
  {
   const string op = "G-04";
   out.Reset();
   out.ticket = ticket;
   r.Reset();
   string who = RdTicketText(ticket);
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, who, r);
   if(!OrderSelect((int)ticket, SELECT_BY_TICKET))
      return Refuse(op, who, r, "Position " + who + " not found");
   if(OrderCloseTime() > 0)
     {
      out.alreadyDone = true;
      RD_LOG_INFO("[" + op + "] " + who + " already closed");
      return RdWarn(r, "Position " + who + " was already closed");
     }
   if(OrderType() > OP_SELL)
      return Refuse(op, who, r, who + " is a pending order - delete it instead");
   string symbol = OrderSymbol();
   int type = OrderType();
   ESide side = (type == OP_BUY) ? SIDE_BUY : SIDE_SELL;
   double posVolume = OrderLots();
   double curSl = OrderStopLoss();
   double curTp = OrderTakeProfit();
   datetime openTime = OrderOpenTime();
   double openPrice = OrderOpenPrice();
   SSymbolSpec s;
   SQuote quote;
   double vol = 0.0;
   if(!SpecQuote(op, symbol, s, quote, r) || !CheckClose(op, s, r) || !CloseVolume(op, s, posVolume, volume, vol, r))
      return false;
   if(!CValidators::PositionNotFrozen(side, curSl, curTp, quote, s, r))
      return Refused(op, symbol, r);

   SMt4Request q;
   BaseRequest(q, symbol);
   q.cmd = type;
   q.ticket = (int)ticket;
   q.volume = vol;
   q.price = RdNormalizePrice(s, side == SIDE_BUY ? quote.bid : quote.ask);
   SSendCtx c;
   c.Reset();
   c.side = side;
   int done = 0;
   datetime sentAt = RdServerTime();
   bool ok = Send(op, GWACT_CLOSE, q, s, c, done, r);
   out.sends = c.sends;
   if(!ok)
      return false;

   out.requested = vol;
   out.volume = vol;
   out.order = ticket;
   if(OrderSelect((int)ticket, SELECT_BY_TICKET) && OrderCloseTime() > 0)
     {
      out.price = OrderClosePrice();
      out.volume = OrderLots();
      out.profit = OrderProfit() + OrderSwap() + OrderCommission();
      out.profitKnown = true;
     }
   if(RdVolLt(vol, posVolume))
     {
      // The rest is usually a NEW ticket (BC-16), but some servers (IG MT4)
      // keep the original ticket open with the smaller volume.
      for(int i = 0; i < RD_GW_SELECT_TRIES && out.remainder == 0; i++)
        {
         if(SelectLive(ticket) && RdVolLt(OrderLots(), posVolume))
            out.remainder = ticket;
         else
            out.remainder = FindRemainder(ticket, s, type, openTime, openPrice, posVolume - vol);
         if(out.remainder == 0 && !IsStopped())
            Sleep(RD_GW_SELECT_SLEEP_MS);
        }
      if(out.remainder > 0 && SelectLive(out.remainder))
         out.remaining = OrderLots();
      // the original ticket kept open (IG MT4): the closed part is a new order in the history
      if(!out.profitKnown && out.remainder == ticket)
         ClosedPart(ticket, s, type, openTime, openPrice, vol, sentAt, out);
     }
   string msg = "Closed " + RdFormatLots(s, out.volume) + " of " + RdFormatLots(s, posVolume) + " " + symbol + " " + who;
   if(out.price > 0.0)
      msg += " @" + Px(s, out.price);
   if(out.profitKnown)
      msg += " P/L " + AccountMoney(out.profit);
   if(out.remainder > 0)
      msg += ", rest " + RdFormatLots(s, out.remaining) + " is now " + RdTicketText(out.remainder);
   RD_LOG_INFO("[" + op + "] " + symbol + " done: " + msg);
   if(RdVolLt(vol, posVolume) && out.remainder == 0)
      return RdWarn(r, msg + " - the remaining position was not found yet, check the Trade tab");
   return RdOk(r, msg);
  }

// The rest of a partial close: comment "from #<old>" when the broker
// keeps it, else same symbol/type/open time/open price and the volume left.
ulong CTradeGateway::FindRemainder(const ulong oldTicket, const SSymbolSpec &s, const int type, const datetime openTime,
                                   const double openPrice, const double expected) const
  {
   string tag = "from #" + IntegerToString((long)oldTicket);
   ulong best = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if((ulong)OrderTicket() == oldTicket || OrderSymbol() != s.name || OrderType() != type)
         continue;
      if(StringFind(OrderComment(), tag) >= 0)
         return (ulong)OrderTicket();
      if(best == 0 && OrderOpenTime() == openTime && RdPriceEq(s, OrderOpenPrice(), openPrice) && RdVolEq(OrderLots(), expected))
         best = (ulong)OrderTicket();
     }
   return best;
  }

//+------------------------------------------------------------------+
//| The closed part of a partial close on a server that keeps the    |
//| original ticket open (IG MT4, BC-16): it is booked as a NEW      |
//| order in the history (observed: the next ticket number, magic 0).|
//| Same symbol, type, open price and the closed volume, closed since|
//| the request, not attributed to another close yet; a comment that |
//| names the old ticket or the same open time is preferred. Fills   |
//| out.price / out.profit; false = not found (P/L stays unknown).   |
//+------------------------------------------------------------------+
#define RD_GW_CLAIMED 32
bool CTradeGateway::ClosedPart(const ulong oldTicket, const SSymbolSpec &s, const int type, const datetime openTime,
                               const double openPrice, const double volume, const datetime sentAt, STradeOutcome &out)
  {
   string tag = "#" + IntegerToString((long)oldTicket);
   for(int k = 0; k < RD_GW_SELECT_TRIES; k++)
     {
      int best = 0;
      int bestScore = -1;
      for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
        {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
            continue;
         ulong t = (ulong)OrderTicket();
         if(t == oldTicket || OrderSymbol() != s.name || OrderType() != type || OrderCloseTime() < sentAt - 2 ||
            !RdVolEq(OrderLots(), volume) || !RdPriceEq(s, OrderOpenPrice(), openPrice))
            continue;
         bool claimed = false;
         for(int j = 0; j < ArraySize(m_claimed) && !claimed; j++)
            claimed = (m_claimed[j] == t);
         if(claimed)
            continue;
         int score = (StringFind(OrderComment(), tag) >= 0 ? 2 : 0) + (OrderOpenTime() == openTime ? 1 : 0);
         if(score > bestScore)
           {
            bestScore = score;
            best = OrderTicket();
           }
        }
      if(best > 0 && OrderSelect(best, SELECT_BY_TICKET))
        {
         out.price = OrderClosePrice();
         out.profit = OrderProfit() + OrderSwap() + OrderCommission();
         out.profitKnown = true;
         int n = ArraySize(m_claimed);
         if(n >= RD_GW_CLAIMED)
           {
            for(int j = 1; j < n; j++)
               m_claimed[j - 1] = m_claimed[j];
            n--;
           }
         ArrayResize(m_claimed, n + 1);
         m_claimed[n] = (ulong)best;
         RD_LOG_INFO("[G-04] " + s.name + " " + RdTicketText(oldTicket) + " stays open; its closed part is " +
                     RdTicketText((ulong)best) + " in the history");
         return true;
        }
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   RD_LOG_WARN("[G-04] " + s.name + " " + RdTicketText(oldTicket) + " stays open; its closed part was not found in the " +
               "history - P/L unknown");
   return false;
  }

//+------------------------------------------------------------------+
//| G-05 DeletePending                                               |
//+------------------------------------------------------------------+
bool CTradeGateway::DeletePending(const ulong ticket, SResult &r)
  {
   const string op = "G-05";
   r.Reset();
   string who = RdTicketText(ticket);
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, who, r);
   SOrder o;
   if(!SelectLive(ticket) || !ReadSelectedOrder(o))
     {
      RD_LOG_INFO("[" + op + "] " + who + " already gone");
      return RdWarn(r, "Order " + who + " no longer exists");
     }
   int type = OrderType();
   SSymbolSpec s;
   SQuote quote;
   if(!SpecQuote(op, o.symbol, s, quote, r))
      return false;
   if(!CValidators::PendingNotFrozen(o.side, o.kind, o.price, quote, s, r))
      return Refused(op, o.symbol, r);
   SMt4Request q;
   BaseRequest(q, o.symbol);
   q.cmd = type;
   q.ticket = (int)ticket;
   SSendCtx c;
   c.Reset();
   c.side = o.side;
   int done = 0;
   if(!Send(op, GWACT_REMOVE, q, s, c, done, r))
     {
      // a delete refused for a ticket the terminal then drops was done already (06 section 3)
      if(WaitUnlisted(ticket))
        {
         RD_LOG_INFO("[" + op + "] " + who + " already gone (" + r.message + ")");
         return RdWarn(r, "Order " + who + " no longer exists");
        }
      return false;
     }
   // the terminal can list a deleted order a moment longer (observed: Dukascopy MT4); wait, so the
   // caller's next list (overlay, Del Pending again) no longer shows it
   if(!WaitUnlisted(ticket))
      RD_LOG_WARN("[" + op + "] " + who + " deleted, but the terminal still lists it");
   RD_LOG_INFO("[" + op + "] " + o.symbol + " done: " + who + " deleted");
   return RdOk(r, RdOrderText(o.side, o.kind) + " " + who + " deleted");
  }

// The ticket is in the terminal's list of open orders (what G-06 / G-07 read).
bool CTradeGateway::OrderListed(const ulong ticket) const
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && (ulong)OrderTicket() == ticket)
         return true;
   return false;
  }

// Until the terminal no longer lists the ticket, at most about 2 s. True when it is gone.
bool CTradeGateway::WaitUnlisted(const ulong ticket) const
  {
   for(int i = 0; i < 2 * RD_GW_SELECT_TRIES; i++)
     {
      if(!OrderListed(ticket))
         return true;
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return !OrderListed(ticket);
  }

//+------------------------------------------------------------------+
//| G-06 / G-07 and single selects                                   |
//+------------------------------------------------------------------+
void CTradeGateway::ReadSelectedPosition(SPosition &p) const
  {
   p.ticket   = (ulong)OrderTicket();
   p.symbol   = OrderSymbol();
   p.side     = (OrderType() == OP_BUY) ? SIDE_BUY : SIDE_SELL;
   p.volume   = OrderLots();
   p.open     = OrderOpenPrice();
   p.sl       = OrderStopLoss();
   p.tp       = OrderTakeProfit();
   p.profit   = OrderProfit();
   p.magic    = OrderMagicNumber();
   p.lossToSl = 0.0;
  }

bool CTradeGateway::ReadSelectedOrder(SOrder &o) const
  {
   int type = OrderType();
   if(type == OP_BUYLIMIT || type == OP_BUYSTOP)
      o.side = SIDE_BUY;
   else
      if(type == OP_SELLLIMIT || type == OP_SELLSTOP)
         o.side = SIDE_SELL;
      else
         return false;
   o.kind     = (type == OP_BUYLIMIT || type == OP_SELLLIMIT) ? KIND_LIMIT : KIND_STOP;
   o.ticket   = (ulong)OrderTicket();
   o.symbol   = OrderSymbol();
   o.volume   = OrderLots();
   o.price    = OrderOpenPrice();
   o.sl       = OrderStopLoss();
   o.tp       = OrderTakeProfit();
   o.magic    = OrderMagicNumber();
   o.lossToSl = 0.0;
   o.expiration = OrderExpiration();
   return true;
  }

bool CTradeGateway::ListPositions(const STradeFilter &f, SPosition &arr[], SResult &r)
  {
   r.Reset();
   ArrayResize(arr, 0);
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES) || OrderType() > OP_SELL)
         continue;
      SPosition p;
      ReadSelectedPosition(p);
      if(!Matches(f, p.symbol, p.magic))
         continue;
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = p;
     }
   return RdOk(r, IntegerToString(ArraySize(arr)) + " position(s)");
  }

bool CTradeGateway::ListPending(const STradeFilter &f, SOrder &arr[], SResult &r)
  {
   r.Reset();
   ArrayResize(arr, 0);
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      SOrder o;
      if(!ReadSelectedOrder(o) || !Matches(f, o.symbol, o.magic))
         continue;
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = o;
     }
   return RdOk(r, IntegerToString(ArraySize(arr)) + " pending order(s)");
  }

bool CTradeGateway::SelectPosition(const ulong ticket, SPosition &p)
  {
   if(!SelectLive(ticket) || OrderType() > OP_SELL)
      return false;
   ReadSelectedPosition(p);
   return true;
  }

bool CTradeGateway::SelectPending(const ulong ticket, SOrder &o)
  {
   return SelectLive(ticket) && ReadSelectedOrder(o);
  }

#endif // RD_PLATFORM_TRADEGATEWAYMT4MANAGE_MQH
