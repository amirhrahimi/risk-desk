// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayMT5Send.mqh                      |
//| Layer   : Platform. Included only by TradeGatewayMT5.mqh.        |
//| Purpose : the MT5 send engine of CTradeGateway:                  |
//|           - BC-06 filling ladder (deals: allowed by the symbol's |
//|             SYMBOL_FILLING_* flags first, then the others, RETURN|
//|             last; pending: RETURN, FOK, IOC), cached per symbol  |
//|           - BC-08 expiration ladder for pending orders           |
//|           - BC-13 retries with a fresh price, BC-14 ambiguity    |
//|             check before any resend (rule R9)                    |
//|           - one log line per request and per answer (06 sec. 6)  |
//| Nothing here knows a broker: every decision comes from the       |
//| symbol's properties or from the server's answer.                 |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYMT5SEND_MQH
#define RD_PLATFORM_TRADEGATEWAYMT5SEND_MQH

//+------------------------------------------------------------------+
//| Sends 'req' until it succeeds or a final answer arrives.         |
//| true : res holds the result (DONE/PLACED, or NO_CHANGES /        |
//|        POSITION_CLOSED with c.alreadyDone, or the effect found   |
//|        after an ambiguous answer).                               |
//| false: r.message is the status text; c.stopsRejected tells the   |
//|        caller that the server refused SL/TP (BC-11).             |
//+------------------------------------------------------------------+
bool CTradeGateway::Send(const string op, const EGwAction act, MqlTradeRequest &req, const SSymbolSpec &s,
                         SSendCtx &c, MqlTradeResult &res, SResult &r)
  {
   r.Reset();
   bool isDeal = (act == GWACT_OPEN || act == GWACT_CLOSE);
   bool usesFill = isDeal || act == GWACT_PENDING;
   bool pending = (act == GWACT_PENDING);
   if(c.requestTime == 0)
     {
      c.requestTime = RdServerTime();
      Baseline(act, req, c);
     }

   while(!IsStopped())
     {
      if(isDeal && !FreshPrice(req, s, c))
         return Failed(op, req.symbol, r, "No quote for " + req.symbol + " - market closed?");
      if(usesFill && c.fillCount > 0)
         req.type_filling = (ENUM_ORDER_TYPE_FILLING)c.fills[c.fillIndex];
      if(pending && c.timeCount > 0)
        {
         req.type_time = (ENUM_ORDER_TYPE_TIME)c.times[c.timeIndex];
         req.expiration = c.exps[c.timeIndex];
        }
      c.sends++;
      LogRequest(op, act, req, s, c);
      ZeroMemory(res);
      ResetLastError();
#ifdef RD_TEST_HOOKS
      EGwSendFault fault = SendFault(act, c.sends);
      bool sent = (fault == GWSEND_SWALLOW) ? false : OrderSend(req, res);
      if(fault != GWSEND_NONE)
        {
         ZeroMemory(res);   // no reply reaches the terminal: the ambiguous case of BC-14
         sent = false;
         RD_LOG_WARN("[" + op + "] TEST FAULT: " + (fault == GWSEND_SWALLOW ? "request not sent" : "request sent, reply dropped") +
                     " (attempt " + IntegerToString(c.sends) + ")");
        }
#else
      bool sent = OrderSend(req, res);
#endif
      int lastError = GetLastError();
      int rc = (int)res.retcode;
      STradeCode tc;
      if(!sent && rc == 0)
         RdTradeCodeNoReply(tc);
      else
         RdTradeCode(rc, tc);
      LogResult(op, req, res, tc, s, lastError);

      switch(tc.cls)
        {
         case TCLASS_SUCCESS:
         case TCLASS_PARTIAL:
            c.partial = (tc.cls == TCLASS_PARTIAL);
            if(usesFill)
               RememberFill(req.symbol, pending, (int)req.type_filling);
            return RdOk(r, tc.message);

         case TCLASS_NO_CHANGE:
            if(act == GWACT_SLTP || act == GWACT_MODIFY)
              {
               c.alreadyDone = true;
               return RdOk(r, tc.message);
              }
            break;

         case TCLASS_ALREADY_CLOSED:
            if(act == GWACT_CLOSE)
              {
               c.alreadyDone = true;
               return RdOk(r, tc.message);
              }
            break;

         case TCLASS_FIX_FILL:
            if(usesFill && c.fillIndex + 1 < c.fillCount)
              {
               c.fillIndex++;
               RD_LOG_WARN("[" + op + "] " + req.symbol + " -> next fill=" + FillName(c.fills[c.fillIndex]) + " (BC-06)");
               continue;
              }
            return Failed(op, req.symbol, r, WithComment(tc.message + " (tried " + FillsTried(c) + ")", res.comment), rc);

         case TCLASS_FIX_EXPIRATION:
            if(pending && c.timeIndex + 1 < c.timeCount)
              {
               c.timeIndex++;
               RD_LOG_WARN("[" + op + "] " + req.symbol + " -> next time=" + TimeName(c.times[c.timeIndex]) + " (BC-08)");
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
               return Failed(op, req.symbol, r, WithComment(tc.message + " (" + IntegerToString(c.sends) + " attempts)",
                             res.comment), rc);
            int wait = RetryDelayMs(c.retries, tc.cls);
            c.retries++;
            RD_LOG_WARN("[" + op + "] " + req.symbol + " -> retry " + IntegerToString(c.retries) + "/" +
                        IntegerToString(m_cfg.maxRetries) + " in " + IntegerToString(wait) + " ms (BC-13)");
            Pause(wait);
            continue;
           }

         case TCLASS_AMBIGUOUS:
            RD_LOG_WARN("[" + op + "] " + req.symbol + " " + tc.message + " looking for the request's effect before any resend (BC-14)");
            Pause(RD_GW_AMBIGUOUS_WAIT_MS);
            if(Executed(act, req, s, c, res))
              {
               RD_LOG_WARN("[" + op + "] " + req.symbol + " BC-14: the request WAS executed - not resending");
               if(usesFill)
                  RememberFill(req.symbol, pending, (int)req.type_filling);
               return RdOk(r, "Done (confirmed after: " + tc.message + ")");
              }
            if(!c.ambiguousRetried)
              {
               c.ambiguousRetried = true;
               RD_LOG_WARN("[" + op + "] " + req.symbol + " BC-14: not executed - sending once more");
               continue;
              }
            return Failed(op, req.symbol, r, WithComment("No answer from the server and the request was not found - " +
                          "check the Trade tab before trying again", res.comment), rc);

         default:
            break;
        }
      //--- fatal (or a fix that does not apply to this request)
      string text = tc.message;
      string detail = Detail(tc, req, s, c);
      if(detail != "")
         text += " " + detail;
      return Failed(op, req.symbol, r, WithComment(text, res.comment), rc);
     }
   return Failed(op, req.symbol, r, "Stopped before the request completed - check the Trade tab");
  }

//+------------------------------------------------------------------+
//| BC-13/BC-18: fresh Ask (buy deal) / Bid (sell deal) before every |
//| attempt; Auto R/R TP follows the fresh entry (06 OP-03).         |
//+------------------------------------------------------------------+
bool CTradeGateway::FreshPrice(MqlTradeRequest &req, const SSymbolSpec &s, SSendCtx &c)
  {
   SQuote q;
   if(!CMarket::Quote(req.symbol, q))
      return false;
   req.price = RdNormalizePrice(s, (req.type == ORDER_TYPE_BUY) ? q.ask : q.bid);
   if(c.tpRR > 0.0 && c.sl > 0.0)
     {
      double tp = 0.0;
      SResult tr;
      if(CRiskMath::TpFromRR(c.side, req.price, c.sl, c.tpRR, s, tp, tr))
        {
         c.tp = tp;
         if(req.tp > 0.0)
            req.tp = tp;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| BC-14: the deals, positions and orders of ours (same symbol and  |
//| magic) that exist BEFORE the first send. A trade of the seconds  |
//| before (a second click, a test case) matches symbol, side and    |
//| volume just as well as the request's own effect would; only what |
//| is not in this list can be the effect.                           |
//+------------------------------------------------------------------+
void CTradeGateway::Baseline(const EGwAction act, const MqlTradeRequest &req, SSendCtx &c) const
  {
   c.knownDealCount = 0;
   c.knownPositionCount = 0;
   c.knownOrderCount = 0;
   if(act == GWACT_OPEN)
     {
      if(HistorySelect(c.requestTime - RD_GW_AMBIGUOUS_WINDOW_S - 60, c.requestTime + 60))
         for(int i = HistoryDealsTotal() - 1; i >= 0 && c.knownDealCount < RD_GW_KNOWN_MAX; i--)
           {
            ulong deal = HistoryDealGetTicket(i);
            if(deal > 0 && HistoryDealGetString(deal, DEAL_SYMBOL) == req.symbol &&
               HistoryDealGetInteger(deal, DEAL_MAGIC) == (long)req.magic)
               c.knownDeals[c.knownDealCount++] = deal;
           }
      for(int j = PositionsTotal() - 1; j >= 0 && c.knownPositionCount < RD_GW_KNOWN_MAX; j--)
        {
         ulong t = PositionGetTicket(j);
         if(t > 0 && PositionGetString(POSITION_SYMBOL) == req.symbol && PositionGetInteger(POSITION_MAGIC) == (long)req.magic)
            c.knownPositions[c.knownPositionCount++] = t;
        }
     }
   if(act == GWACT_PENDING)
      for(int k = OrdersTotal() - 1; k >= 0 && c.knownOrderCount < RD_GW_KNOWN_MAX; k--)
        {
         ulong o = OrderGetTicket(k);
         if(o > 0 && OrderGetString(ORDER_SYMBOL) == req.symbol && OrderGetInteger(ORDER_MAGIC) == (long)req.magic)
            c.knownOrders[c.knownOrderCount++] = o;
        }
  }

//+------------------------------------------------------------------+
//| BC-14: did the ambiguous request take effect?                    |
//+------------------------------------------------------------------+
bool CTradeGateway::Executed(const EGwAction act, const MqlTradeRequest &req, const SSymbolSpec &s, SSendCtx &c,
                             MqlTradeResult &res)
  {
   switch(act)
     {
      case GWACT_OPEN:
         return FindOpenDeal(req, c, res);
      case GWACT_CLOSE:
         return CloseTookEffect(req, c, res);
      case GWACT_PENDING:
         return FindPlacedOrder(req, s, c, res);
      case GWACT_SLTP:
         if(!PositionSelectByTicket(req.position))
            return false;
         return LevelEq(s, PositionGetDouble(POSITION_SL), req.sl) && LevelEq(s, PositionGetDouble(POSITION_TP), req.tp);
      case GWACT_MODIFY:
         if(!OrderSelect(req.order))
            return false;
         return RdPriceEq(s, OrderGetDouble(ORDER_PRICE_OPEN), req.price) &&
                LevelEq(s, OrderGetDouble(ORDER_SL), req.sl) && LevelEq(s, OrderGetDouble(ORDER_TP), req.tp);
      case GWACT_REMOVE:
         return !OrderSelect(req.order);
     }
   return false;
  }

// A deal with our magic, symbol, direction and volume, at or after the
// request time - 5 s (history: works on hedging and netting).
bool CTradeGateway::FindOpenDeal(const MqlTradeRequest &req, SSendCtx &c, MqlTradeResult &res)
  {
   datetime from = c.requestTime - RD_GW_AMBIGUOUS_WINDOW_S;
   long dealType = (req.type == ORDER_TYPE_BUY) ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
   if(HistorySelect(from - 60, RdServerTime() + 60))
     {
      for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != req.symbol)
            continue;
         if(RdGwKnown(c.knownDeals, c.knownDealCount, deal))
            continue;   // older than the request
         if(HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)req.magic || HistoryDealGetInteger(deal, DEAL_TYPE) != dealType)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT)
            continue;
         if((datetime)HistoryDealGetInteger(deal, DEAL_TIME) < from)
            continue;
         double vol = HistoryDealGetDouble(deal, DEAL_VOLUME);
         if(RdVolGt(vol, req.volume))
            continue;
         res.retcode = TRADE_RETCODE_DONE;
         res.deal = deal;
         res.order = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
         res.volume = vol;
         res.price = HistoryDealGetDouble(deal, DEAL_PRICE);
         c.foundPosition = TicketOfPositionId(HistoryDealGetInteger(deal, DEAL_POSITION_ID));
         c.partial = RdVolLt(vol, req.volume);
         return true;
        }
     }
   if(!IsHedging())
      return false;
   long posType = (req.type == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   for(int j = PositionsTotal() - 1; j >= 0; j--)
     {
      ulong t = PositionGetTicket(j);
      if(t == 0 || PositionGetString(POSITION_SYMBOL) != req.symbol || PositionGetInteger(POSITION_MAGIC) != (long)req.magic)
         continue;
      if(RdGwKnown(c.knownPositions, c.knownPositionCount, t))
         continue;   // older than the request
      if(PositionGetInteger(POSITION_TYPE) != posType || !RdVolEq(PositionGetDouble(POSITION_VOLUME), req.volume))
         continue;
      if((datetime)PositionGetInteger(POSITION_TIME) < from)
         continue;
      res.retcode = TRADE_RETCODE_DONE;
      res.volume = req.volume;
      res.price = PositionGetDouble(POSITION_PRICE_OPEN);
      c.foundPosition = t;
      return true;
     }
   return false;
  }

// An order with our magic, symbol, type, price and volume, set up at or
// after the request time - 5 s.
bool CTradeGateway::FindPlacedOrder(const MqlTradeRequest &req, const SSymbolSpec &s, SSendCtx &c, MqlTradeResult &res)
  {
   datetime from = c.requestTime - RD_GW_AMBIGUOUS_WINDOW_S;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong t = OrderGetTicket(i);
      if(t == 0 || OrderGetString(ORDER_SYMBOL) != req.symbol || OrderGetInteger(ORDER_MAGIC) != (long)req.magic)
         continue;
      if(RdGwKnown(c.knownOrders, c.knownOrderCount, t))
         continue;   // older than the request
      if(OrderGetInteger(ORDER_TYPE) != (long)req.type || !RdPriceEq(s, OrderGetDouble(ORDER_PRICE_OPEN), req.price))
         continue;
      if(!RdVolEq(OrderGetDouble(ORDER_VOLUME_INITIAL), req.volume) || (datetime)OrderGetInteger(ORDER_TIME_SETUP) < from)
         continue;
      res.retcode = TRADE_RETCODE_PLACED;
      res.order = t;
      res.volume = req.volume;
      res.price = req.price;
      return true;
     }
   return false;
  }

// The position is gone, or smaller by at least the requested volume.
bool CTradeGateway::CloseTookEffect(const MqlTradeRequest &req, SSendCtx &c, MqlTradeResult &res)
  {
   bool exists = (req.position > 0) ? PositionSelectByTicket(req.position) : PositionSelect(req.symbol);
   double vol = exists ? PositionGetDouble(POSITION_VOLUME) : 0.0;
   if(exists && RdVolGt(vol, c.preVolume - req.volume))
      return false;
   res.retcode = TRADE_RETCODE_DONE;
   res.volume = req.volume;
   return true;
  }

//+------------------------------------------------------------------+
//| BC-06 ladders. SYMBOL_FILLING_* are bit flags; ORDER_FILLING_*   |
//| are enum values: never mix them.                                 |
//+------------------------------------------------------------------+
void CTradeGateway::AddFill(SSendCtx &c, const int fill) const
  {
   for(int i = 0; i < c.fillCount; i++)
      if(c.fills[i] == fill)
         return;
   if(c.fillCount < RD_GW_FILLS_MAX)
      c.fills[c.fillCount++] = fill;
  }

void CTradeGateway::DealFillings(const SSymbolSpec &s, SSendCtx &c)
  {
   c.fillCount = 0;
   c.fillIndex = 0;
   if(m_cfg.fillingOverride == FILLPOL_FOK)
     {
      AddFill(c, ORDER_FILLING_FOK);
      return;
     }
   if(m_cfg.fillingOverride == FILLPOL_IOC)
     {
      AddFill(c, ORDER_FILLING_IOC);
      return;
     }
   if(m_cfg.fillingOverride == FILLPOL_RETURN)
     {
      AddFill(c, ORDER_FILLING_RETURN);
      return;
     }
   int cached = CachedFill(s.name, false);
   if(cached >= 0)
      AddFill(c, cached);
   bool fok = (s.fillingFlags & SYMBOL_FILLING_FOK) != 0;
   bool ioc = (s.fillingFlags & SYMBOL_FILLING_IOC) != 0;
   if(fok)
      AddFill(c, ORDER_FILLING_FOK);
   if(ioc)
      AddFill(c, ORDER_FILLING_IOC);
   AddFill(c, ORDER_FILLING_FOK);     // last resorts: some servers report flags that do not
   AddFill(c, ORDER_FILLING_IOC);     // match what they accept
   AddFill(c, ORDER_FILLING_RETURN);
#ifdef RD_TEST_HOOKS
   if(FaultIs(GWFAULT_BAD_FILL))
      BadFillFirst(s, c);
#endif
  }

#ifdef RD_TEST_HOOKS
//+------------------------------------------------------------------+
//| GWFAULT_BAD_FILL: a policy the symbol's flags do not allow goes  |
//| first (FOK, else IOC, else RETURN, which a market-execution      |
//| server does not take for deals), so the REAL rejection (10030)   |
//| and the ladder's next step are exercised.                        |
//+------------------------------------------------------------------+
void CTradeGateway::BadFillFirst(const SSymbolSpec &s, SSendCtx &c)
  {
   int old[RD_GW_FILLS_MAX];
   int n = c.fillCount;
   for(int i = 0; i < n; i++)
      old[i] = c.fills[i];
   int bad = ORDER_FILLING_RETURN;
   if((s.fillingFlags & SYMBOL_FILLING_FOK) == 0)
      bad = ORDER_FILLING_FOK;
   else
      if((s.fillingFlags & SYMBOL_FILLING_IOC) == 0)
         bad = ORDER_FILLING_IOC;
   c.fillCount = 0;
   c.fillIndex = 0;
   AddFill(c, bad);
   for(int j = 0; j < n; j++)
      AddFill(c, old[j]);
   RD_LOG_WARN("[G-01] " + s.name + " TEST FAULT: the ladder starts with fill=" + FillName(bad) + " (symbol flags " +
               IntegerToString(s.fillingFlags) + ")");
  }
#endif

void CTradeGateway::PendingFillings(const SSymbolSpec &s, SSendCtx &c)
  {
   c.fillCount = 0;
   c.fillIndex = 0;
   if(m_cfg.fillingOverride == FILLPOL_FOK)
     {
      AddFill(c, ORDER_FILLING_FOK);
      return;
     }
   if(m_cfg.fillingOverride == FILLPOL_IOC)
     {
      AddFill(c, ORDER_FILLING_IOC);
      return;
     }
   if(m_cfg.fillingOverride == FILLPOL_RETURN)
     {
      AddFill(c, ORDER_FILLING_RETURN);
      return;
     }
   int cached = CachedFill(s.name, true);
   if(cached >= 0)
      AddFill(c, cached);
   AddFill(c, ORDER_FILLING_RETURN);
   AddFill(c, ORDER_FILLING_FOK);
   AddFill(c, ORDER_FILLING_IOC);
  }

int CTradeGateway::CachedFill(const string symbol, const bool pending) const
  {
   int n = ArraySize(m_fillMemo);
   for(int i = 0; i < n; i++)
      if(m_fillMemo[i].symbol == symbol && m_fillMemo[i].pending == pending)
         return m_fillMemo[i].fill;
   return -1;
  }

void CTradeGateway::RememberFill(const string symbol, const bool pending, const int fill)
  {
   if(m_cfg.fillingOverride != FILLPOL_AUTO)
      return;
   int n = ArraySize(m_fillMemo);
   for(int i = 0; i < n; i++)
      if(m_fillMemo[i].symbol == symbol && m_fillMemo[i].pending == pending)
        {
         m_fillMemo[i].fill = fill;
         return;
        }
   ArrayResize(m_fillMemo, n + 1);
   m_fillMemo[n].symbol = symbol;
   m_fillMemo[n].pending = pending;
   m_fillMemo[n].fill = fill;
  }

//+------------------------------------------------------------------+
//| BC-08: rungs allowed by SYMBOL_EXPIRATION_* first, in the order  |
//| of preference, then the others as last resorts.                  |
//|   no expiry : GTC -> DAY -> SPECIFIED (now + 168 h)              |
//|   N hours   : SPECIFIED -> SPECIFIED_DAY -> GTC                  |
//+------------------------------------------------------------------+
void CTradeGateway::AddTime(SSendCtx &c, const int typeTime, const datetime expiration) const
  {
   for(int i = 0; i < c.timeCount; i++)
      if(c.times[i] == typeTime)
         return;
   if(c.timeCount < RD_GW_TIMES_MAX)
     {
      c.times[c.timeCount] = typeTime;
      c.exps[c.timeCount] = expiration;
      c.timeCount++;
     }
  }

void CTradeGateway::ExpirationRungs(const SSymbolSpec &s, SSendCtx &c)
  {
   c.timeCount = 0;
   c.timeIndex = 0;
   datetime now = RdServerTime();
   int pref[3];
   int flag[3];
   datetime exp[3];
   if(m_cfg.pendingExpiryHours <= 0)
     {
      pref[0] = ORDER_TIME_GTC;       flag[0] = SYMBOL_EXPIRATION_GTC;       exp[0] = 0;
      pref[1] = ORDER_TIME_DAY;       flag[1] = SYMBOL_EXPIRATION_DAY;       exp[1] = 0;
      pref[2] = ORDER_TIME_SPECIFIED; flag[2] = SYMBOL_EXPIRATION_SPECIFIED; exp[2] = now + 168 * 3600;
     }
   else
     {
      datetime until = now + m_cfg.pendingExpiryHours * 3600;
      pref[0] = ORDER_TIME_SPECIFIED;     flag[0] = SYMBOL_EXPIRATION_SPECIFIED;     exp[0] = until;
      pref[1] = ORDER_TIME_SPECIFIED_DAY; flag[1] = SYMBOL_EXPIRATION_SPECIFIED_DAY; exp[1] = until;
      pref[2] = ORDER_TIME_GTC;           flag[2] = SYMBOL_EXPIRATION_GTC;           exp[2] = 0;
     }
   for(int pass = 0; pass < 2; pass++)
      for(int i = 0; i < 3; i++)
        {
         bool allowed = (s.expirationFlags & flag[i]) != 0;
         if(allowed == (pass == 0))
            AddTime(c, pref[i], exp[i]);
        }
  }

// Amber note when the policy used differs from the one asked for (BC-08).
string CTradeGateway::ExpirationNote(const SSymbolSpec &s, const SSendCtx &c) const
  {
   if(c.timeCount == 0)
      return "";
   int used = c.times[c.timeIndex];
   datetime exp = c.exps[c.timeIndex];
   if(m_cfg.pendingExpiryHours <= 0)
     {
      if(used == ORDER_TIME_DAY)
         return "no GTC orders on " + s.name + ": the order expires at the end of the day";
      if(used == ORDER_TIME_SPECIFIED || used == ORDER_TIME_SPECIFIED_DAY)
         return "no GTC orders on " + s.name + ": the order expires " + TimeToString(exp, TIME_DATE | TIME_MINUTES);
      return "";
     }
   if(used == ORDER_TIME_SPECIFIED_DAY)
      return "expiry rounded to the end of " + TimeToString(exp, TIME_DATE);
   if(used == ORDER_TIME_GTC)
      return "expiry not supported on " + s.name + ": the order stays until deleted";
   if(used == ORDER_TIME_DAY)
      return "expiry not supported on " + s.name + ": the order expires at the end of the day";
   return "";
  }

//+------------------------------------------------------------------+
//| Names for logs and messages                                      |
//+------------------------------------------------------------------+
string CTradeGateway::FillName(const int fill) const
  {
   if(fill == ORDER_FILLING_FOK)
      return "FOK";
   if(fill == ORDER_FILLING_IOC)
      return "IOC";
   if(fill == ORDER_FILLING_RETURN)
      return "RETURN";
   return "fill " + IntegerToString(fill);
  }

string CTradeGateway::TimeName(const int typeTime) const
  {
   if(typeTime == ORDER_TIME_GTC)
      return "GTC";
   if(typeTime == ORDER_TIME_DAY)
      return "DAY";
   if(typeTime == ORDER_TIME_SPECIFIED)
      return "SPECIFIED";
   if(typeTime == ORDER_TIME_SPECIFIED_DAY)
      return "SPECIFIED_DAY";
   return "time " + IntegerToString(typeTime);
  }

string CTradeGateway::FillsTried(const SSendCtx &c) const
  {
   string text = "";
   for(int i = 0; i <= c.fillIndex && i < c.fillCount; i++)
      text = RdJoin(text, FillName(c.fills[i]), ", ");
   return text;
  }

string CTradeGateway::TypeText(const ENUM_ORDER_TYPE type) const
  {
   string text = EnumToString(type);
   StringReplace(text, "ORDER_TYPE_", "");
   return text;
  }

//+------------------------------------------------------------------+
//| Numbers that make a fatal answer actionable (03 section 5).      |
//+------------------------------------------------------------------+
string CTradeGateway::Detail(const STradeCode &tc, const MqlTradeRequest &req, const SSymbolSpec &s, const SSendCtx &c) const
  {
   switch(tc.code)
     {
      case TRADE_RETCODE_INVALID_VOLUME:
         return "(" + RdFormatLots(s, req.volume) + " lot; min/step/max = " + VolumeGrid(s) + ")";
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_TRADE_DISABLED:
         return "for " + s.name;
      case TRADE_RETCODE_FROZEN:
         return "(" + RdFormatPoints(s.freezeLevel) + " on " + s.name + ")";
      case TRADE_RETCODE_INVALID_STOPS:
         return StopsHint(req, s, c);
      case TRADE_RETCODE_LIMIT_VOLUME:
         return "on " + s.name + ((s.volLimit > 0.0) ? " (limit " + RdNum(s.volLimit) + " lots)" : "");
      case TRADE_RETCODE_NO_MONEY:
        {
         double margin = 0.0;
         ENUM_ORDER_TYPE type = (c.side == SIDE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         if(req.volume > 0.0 && req.price > 0.0 && OrderCalcMargin(type, s.name, req.volume, req.price, margin))
            return "- needs " + AccountMoney(margin) + ", " + AccountMoney(AccountInfoDouble(ACCOUNT_MARGIN_FREE)) + " free";
         return "";
        }
     }
   return "";
  }

// BC-07: "show the distance used and suggest moving the line further".
string CTradeGateway::StopsHint(const MqlTradeRequest &req, const SSymbolSpec &s, const SSendCtx &c) const
  {
   if(req.action == TRADE_ACTION_PENDING || req.action == TRADE_ACTION_MODIFY)
      return StopsDistances(s, req.price, "the entry", req.sl, req.tp);
   SQuote q;
   if(!CMarket::Quote(s.name, q))
      return "";
   bool buy = (c.side == SIDE_BUY);   // a buy closes at Bid, a sell at Ask
   return StopsDistances(s, buy ? q.bid : q.ask, buy ? "Bid" : "Ask", req.sl, req.tp);
  }

//+------------------------------------------------------------------+
//| 06 section 6: one line per attempt, one per answer.              |
//+------------------------------------------------------------------+
void CTradeGateway::LogRequest(const string op, const EGwAction act, const MqlTradeRequest &req, const SSymbolSpec &s,
                               const SSendCtx &c) const
  {
   string text = "[" + op + "] " + req.symbol + " ";
   switch(act)
     {
      case GWACT_OPEN:
      case GWACT_CLOSE:
         text += TypeText(req.type) + " " + RdFormatLots(s, req.volume) + " @" + Px(s, req.price) +
                 " sl=" + Px(s, req.sl) + " tp=" + Px(s, req.tp) + " dev=" + IntegerToString((long)req.deviation) +
                 " fill=" + FillName(req.type_filling);
         if(act == GWACT_CLOSE)
            text += (req.position > 0) ? " position=" + RdTicketText(req.position) : " (netting)";
         break;
      case GWACT_PENDING:
         text += TypeText(req.type) + " " + RdFormatLots(s, req.volume) + " @" + Px(s, req.price) +
                 " sl=" + Px(s, req.sl) + " tp=" + Px(s, req.tp) + " fill=" + FillName(req.type_filling) +
                 " time=" + TimeName(req.type_time) +
                 " exp=" + (req.expiration > 0 ? TimeToString(req.expiration, TIME_DATE | TIME_MINUTES) : "-");
         break;
      case GWACT_SLTP:
         text += "SLTP position=" + RdTicketText(req.position) + " sl=" + Px(s, req.sl) + " tp=" + Px(s, req.tp);
         break;
      case GWACT_MODIFY:
         text += "MODIFY order=" + RdTicketText(req.order) + " @" + Px(s, req.price) + " sl=" + Px(s, req.sl) +
                 " tp=" + Px(s, req.tp) + " time=" + TimeName(req.type_time) +
                 " exp=" + (req.expiration > 0 ? TimeToString(req.expiration, TIME_DATE | TIME_MINUTES) : "-");
         break;
      case GWACT_REMOVE:
         text += "REMOVE order=" + RdTicketText(req.order);
         break;
     }
   text += " magic=" + IntegerToString((long)req.magic) + " attempt=" + IntegerToString(c.sends);
   RD_LOG_INFO(text);
  }

void CTradeGateway::LogResult(const string op, const MqlTradeRequest &req, const MqlTradeResult &res, const STradeCode &tc,
                              const SSymbolSpec &s, const int lastError) const
  {
   string text = "[" + op + "] " + req.symbol + " retcode=" + IntegerToString((long)res.retcode) + " " + tc.name;
   if(res.comment != "")
      text += " \"" + res.comment + "\"";
   if(res.deal > 0)
      text += " deal=" + RdTicketText(res.deal);
   if(res.order > 0)
      text += " order=" + RdTicketText(res.order);
   if(res.price > 0.0)
      text += " price=" + Px(s, res.price);
   if(res.volume > 0.0)
      text += " vol=" + RdFormatLots(s, res.volume);
   if(lastError != 0)
      text += " last_error=" + IntegerToString(lastError);
   if(tc.cls == TCLASS_SUCCESS || tc.cls == TCLASS_NO_CHANGE || tc.cls == TCLASS_ALREADY_CLOSED)
      RD_LOG_INFO(text);
   else
      RD_LOG_WARN(text);
  }

#endif // RD_PLATFORM_TRADEGATEWAYMT5SEND_MQH
