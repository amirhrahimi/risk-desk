//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayMT5Manage.mqh                    |
//| Layer   : Platform. Included only by TradeGatewayMT5.mqh.        |
//| Purpose : MT5 CTradeGateway, managing existing trades:           |
//|           G-03 ModifyPositionSLTP, G-08 ModifyPending,           |
//|           G-04 ClosePosition, G-05 DeletePending,                |
//|           G-06 ListPositions, G-07 ListPending, single selects.  |
//|           Every primitive checks BC-15 permissions and the BC-07 |
//|           stops/freeze levels before sending.                    |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYMT5MANAGE_MQH
#define RD_PLATFORM_TRADEGATEWAYMT5MANAGE_MQH

//+------------------------------------------------------------------+
//| G-03 ModifyPositionSLTP                                          |
//+------------------------------------------------------------------+
bool CTradeGateway::ModifyPositionSLTP(const ulong ticket, const double sl, const double tp, SResult &r)
  {
   const string op = "G-03";
   r.Reset();
   string who = RdTicketText(ticket);
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, who, r);
   if(!PositionSelectByTicket(ticket))
      return Refuse(op, who, r, "Position " + who + " not found (closed?)");
   string symbol = PositionGetString(POSITION_SYMBOL);
   ESide side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SIDE_BUY : SIDE_SELL;
   double curSl = PositionGetDouble(POSITION_SL);
   double curTp = PositionGetDouble(POSITION_TP);
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(op, symbol, s, q, r))
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
   if(slChange && nsl > 0.0 && !RdSymbolAcceptsSl(s))
      return Refuse(op, symbol, r, "Broker does not accept SL on " + symbol);
   if(tpChange && ntp > 0.0 && !RdSymbolAcceptsTp(s))
      return Refuse(op, symbol, r, "Broker does not accept TP on " + symbol);
   if(!CValidators::PositionNotFrozen(side, curSl, curTp, q, s, r) ||
      !CValidators::MarketStops(side, slChange ? nsl : 0.0, tpChange ? ntp : 0.0, q, s, r))
      return Refused(op, symbol, r);

   MqlTradeRequest req;
   BaseRequest(req, symbol);
   req.action   = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.sl       = nsl;
   req.tp       = ntp;
   SSendCtx c;
   c.Reset();
   c.side = side;
   MqlTradeResult res;
   if(!Send(op, GWACT_SLTP, req, s, c, res, r))
      return false;
   return RdOk(r, "SL " + Px(s, nsl) + " TP " + Px(s, ntp) + " set on " + who);
  }

//+------------------------------------------------------------------+
//| G-08 ModifyPending: price/SL/TP; type_time and expiration kept.  |
//+------------------------------------------------------------------+
bool CTradeGateway::ModifyPending(const ulong ticket, const double price, const double sl, const double tp, SResult &r)
  {
   const string op = "G-08";
   r.Reset();
   string who = RdTicketText(ticket);
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, who, r);
   SOrder o;
   bool stopLimit = false;
   if(!OrderSelect(ticket) || !ReadSelectedOrder(o, stopLimit))
      return Refuse(op, who, r, "Order " + who + " no longer exists");
   if(stopLimit)
      return Refuse(op, o.symbol, r, "Order " + who + " is a stop-limit order - RiskDesk does not modify those");
   ENUM_ORDER_TYPE_TIME typeTime = (ENUM_ORDER_TYPE_TIME)OrderGetInteger(ORDER_TYPE_TIME);
   datetime expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(op, o.symbol, s, q, r))
      return false;
   double np = RdNormalizePrice(s, price);
   double nsl = (sl > 0.0) ? RdNormalizePrice(s, sl) : 0.0;
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   if(RdPriceEq(s, np, o.price) && LevelEq(s, nsl, o.sl) && LevelEq(s, ntp, o.tp))
     {
      RD_LOG_INFO("[" + op + "] " + o.symbol + " " + who + " already @" + Px(s, np) + " sl=" + Px(s, nsl) + " tp=" + Px(s, ntp));
      return RdOk(r, "Already set");
     }
   if(!CValidators::PendingNotFrozen(o.side, o.kind, o.price, q, s, r) ||
      !CValidators::PendingGeometry(o.side, o.kind, np, nsl, ntp, q, s, r) ||
      !CValidators::PendingStops(o.side, o.kind, np, nsl, ntp, q, s, r))
      return Refused(op, o.symbol, r);

   MqlTradeRequest req;
   BaseRequest(req, o.symbol);
   req.action     = TRADE_ACTION_MODIFY;
   req.order      = ticket;
   req.price      = np;
   req.sl         = nsl;
   req.tp         = ntp;
   req.type_time  = typeTime;
   req.expiration = expiration;
   SSendCtx c;
   c.Reset();
   c.side = o.side;
   MqlTradeResult res;
   if(!Send(op, GWACT_MODIFY, req, s, c, res, r))
      return false;
   return RdOk(r, RdOrderText(o.side, o.kind) + " " + who + " @" + Px(s, np) + " sl " + Px(s, nsl) + " tp " + Px(s, ntp));
  }

//+------------------------------------------------------------------+
//| G-04 ClosePosition. Hedging: opposite deal with position=ticket. |
//| Netting: opposite deal of 'volume' on the symbol, never above    |
//| the position (BC-10).                                            |
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
   if(!PositionSelectByTicket(ticket))
     {
      out.alreadyDone = true;
      RD_LOG_INFO("[" + op + "] " + who + " already closed");
      return RdWarn(r, "Position " + who + " was already closed");
     }
   string symbol = PositionGetString(POSITION_SYMBOL);
   ESide side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SIDE_BUY : SIDE_SELL;
   double posVolume = PositionGetDouble(POSITION_VOLUME);
   double curSl = PositionGetDouble(POSITION_SL);
   double curTp = PositionGetDouble(POSITION_TP);
   long positionId = PositionGetInteger(POSITION_IDENTIFIER);
   SSymbolSpec s;
   SQuote q;
   double vol = 0.0;
   if(!SpecQuote(op, symbol, s, q, r) || !CheckClose(op, s, r) || !CloseVolume(op, s, posVolume, volume, vol, r))
      return false;
   if(!CValidators::PositionNotFrozen(side, curSl, curTp, q, s, r))
      return Refused(op, symbol, r);

   MqlTradeRequest req;
   BaseRequest(req, symbol);
   req.action   = TRADE_ACTION_DEAL;
   req.type     = (side == SIDE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   req.volume   = vol;
   req.position = IsHedging() ? ticket : 0;
   req.price    = RdNormalizePrice(s, side == SIDE_BUY ? q.bid : q.ask);
   SSendCtx c;
   c.Reset();
   c.side = side;
   c.preVolume = posVolume;
   DealFillings(s, c);
   MqlTradeResult res;
   bool ok = Send(op, GWACT_CLOSE, req, s, c, res, r);
   out.sends = c.sends;
   if(!ok)
      return false;

   out.requested = vol;
   out.deal = res.deal;
   out.order = res.order;
   out.volume = (res.volume > 0.0) ? res.volume : vol;
   out.price = res.price;
   out.filling = FillName(req.type_filling);
   out.alreadyDone = c.alreadyDone;
   if(PositionSelectByTicket(ticket))
     {
      out.remainder = ticket;
      out.remaining = PositionGetDouble(POSITION_VOLUME);
     }
   // Some servers answer DONE without a deal ticket or price (Dukascopy MT5):
   // find the deal through the order in the position's history.
   if(out.deal == 0)
      out.deal = DealOfOrder(res.order, positionId);
   if(out.deal > 0)
     {
      out.profitKnown = DealProfit(out.deal, out.profit);
      if(out.profitKnown && !(out.price > 0.0))
         out.price = HistoryDealGetDouble(out.deal, DEAL_PRICE);
     }
   string msg = "Closed " + RdFormatLots(s, out.volume) + " of " + RdFormatLots(s, posVolume) + " " + symbol + " " + who;
   if(out.price > 0.0)
      msg += " @" + Px(s, out.price);
   if(out.profitKnown)
      msg += " P/L " + AccountMoney(out.profit);
   RD_LOG_INFO("[" + op + "] " + symbol + " done: " + msg + " fill=" + out.filling);
   if(out.alreadyDone)
      return RdWarn(r, "Position " + who + " was already closed");
   return RdOk(r, msg);
  }

ulong CTradeGateway::DealOfOrder(const ulong order, const long positionId) const
  {
   if(order == 0 || positionId <= 0)
      return 0;
   for(int i = 0; i < RD_GW_SELECT_TRIES; i++)
     {
      if(HistorySelectByPosition(positionId))
         for(int j = HistoryDealsTotal() - 1; j >= 0; j--)
           {
            ulong d = HistoryDealGetTicket(j);
            if(d > 0 && (ulong)HistoryDealGetInteger(d, DEAL_ORDER) == order)
               return d;
           }
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return 0;
  }

bool CTradeGateway::DealProfit(const ulong deal, double &profit) const
  {
   profit = 0.0;
   for(int i = 0; i < RD_GW_SELECT_TRIES; i++)
     {
      if(HistoryDealSelect(deal))
        {
         profit = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
                  HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
         return true;
        }
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
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
   bool stopLimit = false;
   if(!OrderSelect(ticket) || !ReadSelectedOrder(o, stopLimit))
     {
      RD_LOG_INFO("[" + op + "] " + who + " already gone");
      return RdWarn(r, "Order " + who + " no longer exists");
     }
   SSymbolSpec s;
   SQuote q;
   if(!SpecQuote(op, o.symbol, s, q, r))
      return false;
   if(!stopLimit && !CValidators::PendingNotFrozen(o.side, o.kind, o.price, q, s, r))
      return Refused(op, o.symbol, r);
   MqlTradeRequest req;
   BaseRequest(req, o.symbol);
   req.action = TRADE_ACTION_REMOVE;
   req.order  = ticket;
   SSendCtx c;
   c.Reset();
   c.side = o.side;
   MqlTradeResult res;
   if(!Send(op, GWACT_REMOVE, req, s, c, res, r))
      return false;
   RD_LOG_INFO("[" + op + "] " + o.symbol + " done: " + who + " deleted");
   return RdOk(r, RdOrderText(o.side, o.kind) + " " + who + " deleted");
  }

//+------------------------------------------------------------------+
//| G-06 / G-07 and single selects                                   |
//+------------------------------------------------------------------+
void CTradeGateway::ReadSelectedPosition(SPosition &p) const
  {
   p.ticket   = (ulong)PositionGetInteger(POSITION_TICKET);
   p.symbol   = PositionGetString(POSITION_SYMBOL);
   p.side     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SIDE_BUY : SIDE_SELL;
   p.volume   = PositionGetDouble(POSITION_VOLUME);
   p.open     = PositionGetDouble(POSITION_PRICE_OPEN);
   p.sl       = PositionGetDouble(POSITION_SL);
   p.tp       = PositionGetDouble(POSITION_TP);
   p.profit   = PositionGetDouble(POSITION_PROFIT);
   p.magic    = PositionGetInteger(POSITION_MAGIC);
   p.lossToSl = 0.0;
  }

// From the selected order. False for market orders in flight and close-by.
// Stop-limit orders are read as KIND_STOP (their trigger price) with stopLimit=true.
bool CTradeGateway::ReadSelectedOrder(SOrder &o, bool &stopLimit) const
  {
   stopLimit = false;
   ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   switch(type)
     {
      case ORDER_TYPE_BUY_LIMIT:
         o.side = SIDE_BUY;
         o.kind = KIND_LIMIT;
         break;
      case ORDER_TYPE_SELL_LIMIT:
         o.side = SIDE_SELL;
         o.kind = KIND_LIMIT;
         break;
      case ORDER_TYPE_BUY_STOP:
         o.side = SIDE_BUY;
         o.kind = KIND_STOP;
         break;
      case ORDER_TYPE_SELL_STOP:
         o.side = SIDE_SELL;
         o.kind = KIND_STOP;
         break;
      case ORDER_TYPE_BUY_STOP_LIMIT:
         o.side = SIDE_BUY;
         o.kind = KIND_STOP;
         stopLimit = true;
         break;
      case ORDER_TYPE_SELL_STOP_LIMIT:
         o.side = SIDE_SELL;
         o.kind = KIND_STOP;
         stopLimit = true;
         break;
      default:
         return false;
     }
   o.ticket   = (ulong)OrderGetInteger(ORDER_TICKET);
   o.symbol   = OrderGetString(ORDER_SYMBOL);
   o.volume   = OrderGetDouble(ORDER_VOLUME_CURRENT);
   o.price    = OrderGetDouble(ORDER_PRICE_OPEN);
   o.sl       = OrderGetDouble(ORDER_SL);
   o.tp       = OrderGetDouble(ORDER_TP);
   o.magic    = OrderGetInteger(ORDER_MAGIC);
   o.lossToSl = 0.0;
   return true;
  }

bool CTradeGateway::ListPositions(const STradeFilter &f, SPosition &arr[], SResult &r)
  {
   r.Reset();
   ArrayResize(arr, 0);
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      if(PositionGetTicket(i) == 0)
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
      if(OrderGetTicket(i) == 0)
         continue;
      SOrder o;
      bool stopLimit = false;
      if(!ReadSelectedOrder(o, stopLimit) || (stopLimit && !f.includeStopLimit))
         continue;
      if(!Matches(f, o.symbol, o.magic))
         continue;
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = o;
     }
   return RdOk(r, IntegerToString(ArraySize(arr)) + " pending order(s)");
  }

bool CTradeGateway::SelectPosition(const ulong ticket, SPosition &p)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   ReadSelectedPosition(p);
   return true;
  }

bool CTradeGateway::SelectPending(const ulong ticket, SOrder &o)
  {
   bool stopLimit = false;
   return OrderSelect(ticket) && ReadSelectedOrder(o, stopLimit);
  }

#endif // RD_PLATFORM_TRADEGATEWAYMT5MANAGE_MQH
