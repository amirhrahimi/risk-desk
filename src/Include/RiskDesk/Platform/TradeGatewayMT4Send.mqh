//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayMT4Send.mqh                      |
//| Layer   : Platform. Included only by TradeGatewayMT4.mqh.        |
//| Purpose : the MT4 send engine of CTradeGateway: trade context    |
//|           wait (02 section 12), RefreshRates and a fresh price   |
//|           before every attempt, BC-13 retries, BC-08 error 147   |
//|           fallback, BC-14 ambiguity check before any resend      |
//|           (rule R9), one log line per request and per answer.    |
//| Nothing here knows a broker: every decision comes from the       |
//| symbol's properties or from the server's answer.                 |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYMT4SEND_MQH
#define RD_PLATFORM_TRADEGATEWAYMT4SEND_MQH

//+------------------------------------------------------------------+
//| true : the call succeeded ('ticket' = new order for OPEN/PENDING,|
//|        else q.ticket), or its effect was found after an          |
//|        ambiguous answer, or error 1 on a modify (c.alreadyDone). |
//| false: r.message is the status text; c.stopsRejected = error 130.|
//+------------------------------------------------------------------+
bool CTradeGateway::Send(const string op, const EGwAction act, SMt4Request &q, const SSymbolSpec &s, SSendCtx &c,
                         int &ticket, SResult &r)
  {
   r.Reset();
   ticket = 0;
   bool isDeal = (act == GWACT_OPEN || act == GWACT_CLOSE);
   if(c.requestTime == 0)
      c.requestTime = RdServerTime();

   while(!IsStopped())
     {
      STradeCode tc;
      if(!WaitTradeContext())
        {
         RdTradeCode(ERR_TRADE_CONTEXT_BUSY, tc);
         RD_LOG_WARN("[" + op + "] " + q.symbol + " trade context still busy after " +
                     IntegerToString(RD_GW_CONTEXT_WAIT_MS) + " ms");
        }
      else
        {
         if(!RefreshRates())
           {
            // no new tick since the last call: the stored prices are the latest
           }
         if(isDeal && !FreshPrice(act, q, s, c))
            return Failed(op, q.symbol, r, "No quote for " + q.symbol + " - market closed?");
         c.sends++;
         LogRequest(op, act, q, s, c);
         ResetLastError();
         bool ok = false;
         int newTicket = -1;
         int slippage = (m_cfg.slippagePoints > 0) ? m_cfg.slippagePoints : 0;
         switch(act)
           {
            case GWACT_OPEN:
               newTicket = OrderSend(q.symbol, q.cmd, q.volume, q.price, slippage, q.sl, q.tp, m_cfg.comment,
                                     (int)m_cfg.magic, 0, clrNONE);
               ok = (newTicket > 0);
               break;
            case GWACT_PENDING:
               newTicket = OrderSend(q.symbol, q.cmd, q.volume, q.price, 0, q.sl, q.tp, m_cfg.comment,
                                     (int)m_cfg.magic, q.expiration, clrNONE);
               ok = (newTicket > 0);
               break;
            case GWACT_CLOSE:
               ok = OrderClose(q.ticket, q.volume, q.price, slippage, clrNONE);
               break;
            case GWACT_SLTP:
               ok = OrderModify(q.ticket, q.price, q.sl, q.tp, 0, clrNONE);
               break;
            case GWACT_MODIFY:
               ok = OrderModify(q.ticket, q.price, q.sl, q.tp, q.expiration, clrNONE);
               break;
            case GWACT_REMOVE:
               ok = OrderDelete(q.ticket, clrNONE);
               break;
           }
         int err = GetLastError();
         if(ok)
           {
            ticket = (act == GWACT_OPEN || act == GWACT_PENDING) ? newTicket : q.ticket;
            RD_LOG_INFO("[" + op + "] " + q.symbol + " ok ticket=" + RdTicketText((ulong)ticket));
            return RdOk(r, "Done");
           }
         if(err == ERR_NO_ERROR)
            RdTradeCodeNoReply(tc);
         else
            RdTradeCode(err, tc);
         string line = "[" + op + "] " + q.symbol + " error=" + IntegerToString(err) + " " + tc.name + " \"" + tc.message + "\"";
         if(tc.cls == TCLASS_NO_CHANGE)
            RD_LOG_INFO(line);
         else
            RD_LOG_WARN(line);
        }

      switch(tc.cls)
        {
         case TCLASS_SUCCESS:
         case TCLASS_PARTIAL:
            ticket = q.ticket;
            return RdOk(r, tc.message);

         case TCLASS_NO_CHANGE:
            if(act == GWACT_SLTP || act == GWACT_MODIFY)
              {
               c.alreadyDone = true;
               ticket = q.ticket;
               return RdOk(r, tc.message);
              }
            break;

         case TCLASS_FIX_EXPIRATION:
            if(act == GWACT_PENDING && q.expiration != 0)
              {
               q.expiration = 0;
               c.expiryDropped = true;
               RD_LOG_WARN("[" + op + "] " + q.symbol + " -> resending without expiration (BC-08)");
               continue;
              }
            break;

         case TCLASS_FIX_STOPS:
            c.stopsRejected = true;
            break;

         case TCLASS_RETRY_ONCE:
         case TCLASS_RETRY:
         case TCLASS_RETRY_LONG:
         case TCLASS_RETRY_CONTEXT:
         case TCLASS_RETRY_CONNECT:
           {
            bool allowed = (c.retries < m_cfg.maxRetries);
            if(tc.cls == TCLASS_RETRY_ONCE)
              {
               allowed = allowed && !c.retriedOnce;
               c.retriedOnce = true;
              }
            if(!allowed)
               return Failed(op, q.symbol, r, tc.message + " (" + IntegerToString(c.sends) + " attempts)", tc.code);
            int wait = RetryDelayMs(c.retries, tc.cls);
            c.retries++;
            RD_LOG_WARN("[" + op + "] " + q.symbol + " -> retry " + IntegerToString(c.retries) + "/" +
                        IntegerToString(m_cfg.maxRetries) + " in " + IntegerToString(wait) + " ms (BC-13)");
            Pause(wait);
            if(tc.cls == TCLASS_RETRY_CONNECT && !WaitConnection())
               return Failed(op, q.symbol, r, "No connection to trade server", tc.code);
            continue;
           }

         case TCLASS_AMBIGUOUS:
            RD_LOG_WARN("[" + op + "] " + q.symbol + " " + tc.message + " looking for the request's effect before any resend (BC-14)");
            Pause(RD_GW_AMBIGUOUS_WAIT_MS);
            if(Executed(act, q, s, c, ticket))
              {
               RD_LOG_WARN("[" + op + "] " + q.symbol + " BC-14: the request WAS executed - not resending (ticket " +
                           RdTicketText((ulong)ticket) + ")");
               return RdOk(r, "Done (confirmed after: " + tc.message + ")");
              }
            if(!c.ambiguousRetried)
              {
               c.ambiguousRetried = true;
               RD_LOG_WARN("[" + op + "] " + q.symbol + " BC-14: not executed - sending once more");
               continue;
              }
            return Failed(op, q.symbol, r, "No answer from the server and the request was not found - " +
                          "check the Trade tab before trying again", tc.code);

         default:
            break;
        }
      string text = tc.message;
      string detail = Detail(tc, q, s, c);
      if(detail != "")
         text += " " + detail;
      return Failed(op, q.symbol, r, text, tc.code);
     }
   return Failed(op, q.symbol, r, "Stopped before the request completed - check the Trade tab");
  }

bool CTradeGateway::WaitTradeContext() const
  {
   uint start = GetTickCount();
   while(IsTradeContextBusy())
     {
      if(GetTickCount() - start >= (uint)RD_GW_CONTEXT_WAIT_MS || IsStopped())
         return false;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return true;
  }

bool CTradeGateway::WaitConnection() const
  {
   uint start = GetTickCount();
   while(!IsConnected())
     {
      if(GetTickCount() - start >= (uint)RD_GW_CONNECT_WAIT_MS || IsStopped())
         return false;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return true;
  }

//+------------------------------------------------------------------+
//| BC-13/BC-18: open buy / close sell at Ask, open sell / close buy |
//| at Bid; the Auto R/R TP follows the fresh entry.                 |
//+------------------------------------------------------------------+
bool CTradeGateway::FreshPrice(const EGwAction act, SMt4Request &q, const SSymbolSpec &s, SSendCtx &c)
  {
   SQuote quote;
   if(!CMarket::Quote(q.symbol, quote))
      return false;
   bool atAsk = (act == GWACT_OPEN) ? (q.cmd == OP_BUY) : (q.cmd == OP_SELL);
   q.price = RdNormalizePrice(s, atAsk ? quote.ask : quote.bid);
   if(act == GWACT_OPEN && c.tpRR > 0.0 && c.sl > 0.0)
     {
      double tp = 0.0;
      SResult tr;
      if(CRiskMath::TpFromRR(c.side, q.price, c.sl, c.tpRR, s, tp, tr))
        {
         c.tp = tp;
         if(q.tp > 0.0)
            q.tp = tp;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| BC-14: did the ambiguous request take effect?                    |
//+------------------------------------------------------------------+
bool CTradeGateway::Executed(const EGwAction act, const SMt4Request &q, const SSymbolSpec &s, const SSendCtx &c,
                             int &ticket)
  {
   ticket = q.ticket;
   switch(act)
     {
      case GWACT_OPEN:
      case GWACT_PENDING:
        {
         datetime from = c.requestTime - RD_GW_AMBIGUOUS_WINDOW_S;
         for(int i = OrdersTotal() - 1; i >= 0; i--)
           {
            if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
               continue;
            if(OrderSymbol() != q.symbol || OrderMagicNumber() != (int)m_cfg.magic || OrderType() != q.cmd)
               continue;
            if(!RdVolEq(OrderLots(), q.volume) || OrderOpenTime() < from)
               continue;
            if(act == GWACT_PENDING && !RdPriceEq(s, OrderOpenPrice(), q.price))
               continue;
            ticket = OrderTicket();
            return true;
           }
         return false;
        }
      case GWACT_CLOSE:
      case GWACT_REMOVE:
         return OrderSelect(q.ticket, SELECT_BY_TICKET) && OrderCloseTime() > 0;
      case GWACT_SLTP:
         return SelectLive((ulong)q.ticket) && LevelEq(s, OrderStopLoss(), q.sl) && LevelEq(s, OrderTakeProfit(), q.tp);
      case GWACT_MODIFY:
         return SelectLive((ulong)q.ticket) && RdPriceEq(s, OrderOpenPrice(), q.price) &&
                LevelEq(s, OrderStopLoss(), q.sl) && LevelEq(s, OrderTakeProfit(), q.tp);
     }
   return false;
  }

string CTradeGateway::CmdText(const int cmd) const
  {
   switch(cmd)
     {
      case OP_BUY:
         return "BUY";
      case OP_SELL:
         return "SELL";
      case OP_BUYLIMIT:
         return "BUY_LIMIT";
      case OP_SELLLIMIT:
         return "SELL_LIMIT";
      case OP_BUYSTOP:
         return "BUY_STOP";
      case OP_SELLSTOP:
         return "SELL_STOP";
     }
   return "CMD_" + IntegerToString(cmd);
  }

//+------------------------------------------------------------------+
//| Numbers that make a fatal answer actionable (03 section 5).      |
//+------------------------------------------------------------------+
string CTradeGateway::Detail(const STradeCode &tc, const SMt4Request &q, const SSymbolSpec &s, const SSendCtx &c) const
  {
   switch(tc.code)
     {
      case ERR_INVALID_TRADE_VOLUME:
         return "(" + RdFormatLots(s, q.volume) + " lot; min/step/max = " + VolumeGrid(s) + ")";
      case ERR_MARKET_CLOSED:
      case ERR_TRADE_DISABLED:
         return "for " + s.name;
      case ERR_TRADE_MODIFY_DENIED:
         return "(freeze level " + RdFormatPoints(s.freezeLevel) + " on " + s.name + ")";
      case ERR_NOT_ENOUGH_MONEY:
        {
         double perLot = MarketInfo(s.name, MODE_MARGINREQUIRED);
         if(perLot > 0.0 && q.volume > 0.0)
            return "- needs " + AccountMoney(perLot * q.volume) + ", " + AccountMoney(AccountFreeMargin()) + " free";
         return "";
        }
      case ERR_INVALID_STOPS:
        {
         if(q.cmd > OP_SELL)
            return StopsDistances(s, q.price, "the entry", q.sl, q.tp);
         SQuote quote;
         if(!CMarket::Quote(s.name, quote))
            return "";
         bool buy = (c.side == SIDE_BUY);   // a buy closes at Bid, a sell at Ask
         return StopsDistances(s, buy ? quote.bid : quote.ask, buy ? "Bid" : "Ask", q.sl, q.tp);
        }
     }
   return "";
  }

//+------------------------------------------------------------------+
//| 06 section 6: one line per attempt.                              |
//+------------------------------------------------------------------+
void CTradeGateway::LogRequest(const string op, const EGwAction act, const SMt4Request &q, const SSymbolSpec &s,
                               const SSendCtx &c) const
  {
   string text = "[" + op + "] " + q.symbol + " ";
   switch(act)
     {
      case GWACT_OPEN:
         text += CmdText(q.cmd) + " " + RdFormatLots(s, q.volume) + " @" + Px(s, q.price) + " sl=" + Px(s, q.sl) +
                 " tp=" + Px(s, q.tp) + " slippage=" + IntegerToString(m_cfg.slippagePoints);
         break;
      case GWACT_PENDING:
         text += CmdText(q.cmd) + " " + RdFormatLots(s, q.volume) + " @" + Px(s, q.price) + " sl=" + Px(s, q.sl) +
                 " tp=" + Px(s, q.tp) + " exp=" + (q.expiration > 0 ? TimeToString(q.expiration, TIME_DATE | TIME_MINUTES) : "-");
         break;
      case GWACT_CLOSE:
         text += "CLOSE " + RdTicketText((ulong)q.ticket) + " " + CmdText(q.cmd) + " " + RdFormatLots(s, q.volume) + " @" +
                 Px(s, q.price) + " slippage=" + IntegerToString(m_cfg.slippagePoints);
         break;
      case GWACT_SLTP:
         text += "MODIFY position " + RdTicketText((ulong)q.ticket) + " sl=" + Px(s, q.sl) + " tp=" + Px(s, q.tp);
         break;
      case GWACT_MODIFY:
         text += "MODIFY order " + RdTicketText((ulong)q.ticket) + " @" + Px(s, q.price) + " sl=" + Px(s, q.sl) +
                 " tp=" + Px(s, q.tp) + " exp=" + (q.expiration > 0 ? TimeToString(q.expiration, TIME_DATE | TIME_MINUTES) : "-");
         break;
      case GWACT_REMOVE:
         text += "DELETE order " + RdTicketText((ulong)q.ticket);
         break;
     }
   text += " magic=" + IntegerToString(m_cfg.magic) + " attempt=" + IntegerToString(c.sends);
   RD_LOG_INFO(text);
  }

#endif // RD_PLATFORM_TRADEGATEWAYMT4SEND_MQH
