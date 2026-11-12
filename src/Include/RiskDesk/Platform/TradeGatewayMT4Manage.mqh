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
      return false;
   RD_LOG_INFO("[" + op + "] " + o.symbol + " done: " + who + " deleted");
   return RdOk(r, RdOrderText(o.side, o.kind) + " " + who + " deleted");
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
