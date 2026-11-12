//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayMT4.mqh                          |
//| Layer   : Platform. Included only by TradeGateway.mqh (MQL4).    |
//| Purpose : MT4 implementation of CTradeGateway (OrderSend /       |
//|           OrderModify / OrderClose / OrderDelete): the gateway   |
//|           primitives G-01..G-08 of 06 section 5 with BC-07/08/09/|
//|           11/13/14/15/16/18. Same public API as                  |
//|           TradeGatewayMT5.mqh (ADR-001). MT4 accounts behave     |
//|           like hedging (BC-10); filling policies do not exist.   |
//|           This file: class declaration, G-01 OpenMarket, G-02    |
//|           PlacePending and their SL verification (BC-11, R7).    |
//|           G-03..G-08: TradeGatewayMT4Manage.mqh. The send engine |
//|           is in TradeGatewayMT4Send.mqh.                         |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYMT4_MQH
#define RD_PLATFORM_TRADEGATEWAYMT4_MQH

#include "TradeGatewayBase.mqh"

#define RD_GW_CONTEXT_WAIT_MS  5000   // 02 section 12: wait up to 5 s for the trade context
#define RD_GW_CONNECT_WAIT_MS  5000   // ERR_NO_CONNECTION: wait for the terminal to reconnect

// One MT4 trade call.
struct SMt4Request
  {
   string            symbol;
   int               cmd;          // OP_BUY ... OP_SELLSTOP; for close/modify: the order's own type
   int               ticket;       // close / modify / delete
   double            volume;
   double            price;        // open/close price, pending entry, or the open price for OrderModify
   double            sl;
   double            tp;
   datetime          expiration;
  };

// One request on its way through retries and checks.
struct SSendCtx
  {
   datetime          requestTime;   // server time of the first send (BC-14)
   int               sends;
   int               retries;
   bool              retriedOnce;
   bool              ambiguousRetried;
   bool              stopsRejected; // error 130
   bool              alreadyDone;   // error 1 on a modify
   bool              expiryDropped; // error 147: resent without expiration (BC-08)
   ESide             side;
   double            sl;            // G-01: for the R/R TP refresh
   double            tp;            // G-01: TP of the latest attempt
   double            tpRR;

   void              Reset()
     {
      requestTime = 0;
      sends = 0;
      retries = 0;
      retriedOnce = false;
      ambiguousRetried = false;
      stopsRejected = false;
      alreadyDone = false;
      expiryDropped = false;
      side = SIDE_BUY;
      sl = 0.0;
      tp = 0.0;
      tpRR = 0.0;
     }
  };

class CTradeGateway : public CTradeGatewayBase
  {
private:
   //--- send engine (TradeGatewayMT4Send.mqh)
   bool              Send(const string op, const EGwAction act, SMt4Request &q, const SSymbolSpec &s, SSendCtx &c,
                          int &ticket, SResult &r);
   bool              WaitTradeContext() const;
   bool              WaitConnection() const;
   bool              FreshPrice(const EGwAction act, SMt4Request &q, const SSymbolSpec &s, SSendCtx &c);
   bool              Executed(const EGwAction act, const SMt4Request &q, const SSymbolSpec &s, const SSendCtx &c,
                              int &ticket);
   string            CmdText(const int cmd) const;
   string            Detail(const STradeCode &tc, const SMt4Request &q, const SSymbolSpec &s, const SSendCtx &c) const;
   void              LogRequest(const string op, const EGwAction act, const SMt4Request &q, const SSymbolSpec &s,
                                const SSendCtx &c) const;

   //--- helpers of the operations (this file)
   void              BaseRequest(SMt4Request &q, const string symbol) const;
   bool              SelectLive(const ulong ticket) const;
   bool              ReadStops(const ulong ticket, double &sl, double &tp) const;
   bool              VerifyStops(const string op, const ulong ticket, const SSymbolSpec &s, const double sl, const double tp,
                                 const double addedVolume, STradeOutcome &out, SResult &r);
   bool              VerifyPending(const ulong ticket, const SSymbolSpec &s, const double price, const double sl,
                                   const double tp, SResult &r);
   void              ReadSelectedPosition(SPosition &p) const;
   bool              ReadSelectedOrder(SOrder &o) const;
   ulong             FindRemainder(const ulong oldTicket, const SSymbolSpec &s, const int type, const datetime openTime,
                                   const double openPrice, const double expected) const;

public:
   bool              IsHedging() const { return true; }
   bool              OpenMarket(const string symbol, const ESide side, const double lots, const double sl, const double tp,
                                STradeOutcome &out, SResult &r, const double tpRR = 0.0);
   bool              PlacePending(const string symbol, const ESide side, const EOrderKind kind, const double lots,
                                  const double price, const double sl, const double tp, STradeOutcome &out, SResult &r);
   bool              ModifyPositionSLTP(const ulong ticket, const double sl, const double tp, SResult &r);
   bool              ModifyPending(const ulong ticket, const double price, const double sl, const double tp, SResult &r);
   bool              ClosePosition(const ulong ticket, const double volume, STradeOutcome &out, SResult &r);
   bool              DeletePending(const ulong ticket, SResult &r);
   bool              ListPositions(const STradeFilter &f, SPosition &arr[], SResult &r);
   bool              ListPending(const STradeFilter &f, SOrder &arr[], SResult &r);
   bool              SelectPosition(const ulong ticket, SPosition &p);
   bool              SelectPending(const ulong ticket, SOrder &o);
  };

#include "TradeGatewayMT4Send.mqh"
#include "TradeGatewayMT4Manage.mqh"

//+------------------------------------------------------------------+
void CTradeGateway::BaseRequest(SMt4Request &q, const string symbol) const
  {
   q.symbol = symbol;
   q.cmd = OP_BUY;
   q.ticket = 0;
   q.volume = 0.0;
   q.price = 0.0;
   q.sl = 0.0;
   q.tp = 0.0;
   q.expiration = 0;
  }

// Selects an order that is still open (position or pending).
bool CTradeGateway::SelectLive(const ulong ticket) const
  {
   return OrderSelect((int)ticket, SELECT_BY_TICKET) && OrderCloseTime() == 0;
  }

//+------------------------------------------------------------------+
//| G-01 OpenMarket                                                  |
//+------------------------------------------------------------------+
bool CTradeGateway::OpenMarket(const string symbol, const ESide side, const double lots, const double sl, const double tp,
                               STradeOutcome &out, SResult &r, const double tpRR)
  {
   const string op = "G-01";
   out.Reset();
   out.requested = lots;
   SSymbolSpec s;
   SQuote quote;
   if(!Prepare(op, symbol, s, quote, r))
      return false;
   bool wantsTp = (tp > 0.0 || tpRR > 0.0);   // CheckOpen only tests "TP > 0" (BC-11 TP flag)
   // BC-09: on MT4 ACCOUNT_LIMIT_ORDERS counts open positions too
   if(!CheckOpen(op, s, side, KIND_MARKET, lots, sl, wantsTp ? 1.0 : 0.0, r) || !CheckOrderLimit(op, symbol, r))
      return false;

   double entry = RdNormalizePrice(s, side == SIDE_BUY ? quote.ask : quote.bid);
   double nsl = RdNormalizePrice(s, sl);
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   if(tpRR > 0.0 && !CRiskMath::TpFromRR(side, entry, nsl, tpRR, s, ntp, r))
      return Refused(op, symbol, r);
   if(!CValidators::MarketSide(side, nsl, ntp, quote, s, r))
      return Refused(op, symbol, r);

   bool attach = WantStopsWithOrder(symbol);
   SMt4Request q;
   BaseRequest(q, symbol);
   q.cmd    = (side == SIDE_BUY) ? OP_BUY : OP_SELL;
   q.volume = lots;
   q.price  = entry;
   q.sl     = attach ? nsl : 0.0;
   q.tp     = attach ? ntp : 0.0;
   SSendCtx c;
   c.Reset();
   c.side = side;
   c.sl = nsl;
   c.tp = ntp;
   c.tpRR = tpRR;
   int ticket = 0;
   bool ok = Send(op, GWACT_OPEN, q, s, c, ticket, r);

   //--- BC-11 Auto: error 130 although BC-07 passed -> send without, attach right after
   if(!ok && c.stopsRejected && attach && m_cfg.stopsMode == STOPS_AUTO)
     {
      SQuote fresh;
      SResult check;
      check.Reset();
      if(CMarket::Quote(symbol, fresh) && CValidators::MarketStops(side, nsl, c.tp, fresh, s, check))
        {
         RememberModifyAfter(symbol);
         RD_LOG_WARN("[" + op + "] " + symbol + " server refused SL/TP on a market order although the stops level allows them: " +
                     "sending without SL/TP and attaching them right after (BC-11, remembered for this symbol)");
         q.sl = 0.0;
         q.tp = 0.0;
         attach = false;
         c.stopsRejected = false;
         ok = Send(op, GWACT_OPEN, q, s, c, ticket, r);
        }
      else
         if(!check.ok)
            r.message = r.message + " - " + check.message;
     }
   out.sends = c.sends;
   if(!ok)
      return false;

   out.ticket = (ulong)ticket;
   out.order = (ulong)ticket;
   out.volume = lots;
   out.stopsAfter = !attach;
   if(OrderSelect(ticket, SELECT_BY_TICKET))
     {
      out.price = OrderOpenPrice();
      out.volume = OrderLots();
     }
   SResult vr;
   if(!VerifyStops(op, out.ticket, s, nsl, c.tp, out.volume, out, vr))
     {
      r = vr;
      return false;
     }
   string notes = "";
   if(out.stopsAfter)
      notes = "SL/TP attached right after the open";
   if(vr.sev == SEV_WARN)
      notes = RdJoin(notes, vr.message, "; ");
   out.notes = notes;
   string msg = RdOrderText(side, KIND_MARKET) + " " + RdFormatLots(s, out.volume) + " " + symbol + " @" + Px(s, out.price) +
                " " + RdTicketText(out.ticket);
   RD_LOG_INFO("[" + op + "] " + symbol + " done: " + msg + (notes != "" ? " (" + notes + ")" : ""));
   if(notes != "")
      return RdWarn(r, msg + " - " + notes);
   return RdOk(r, msg);
  }

bool CTradeGateway::ReadStops(const ulong ticket, double &sl, double &tp) const
  {
   for(int i = 0; i < RD_GW_SELECT_TRIES; i++)
     {
      if(SelectLive(ticket))
        {
         sl = OrderStopLoss();
         tp = OrderTakeProfit();
         return true;
        }
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| BC-11 verify; SL still wrong -> rule R7 (close the position).    |
//+------------------------------------------------------------------+
bool CTradeGateway::VerifyStops(const string op, const ulong ticket, const SSymbolSpec &s, const double sl, const double tp,
                                const double addedVolume, STradeOutcome &out, SResult &r)
  {
   r.Reset();
   double curSl = 0.0;
   double curTp = 0.0;
   bool slOk = false;
   bool tpOk = false;
   SResult fix;
   fix.Reset();
   for(int pass = 1; pass <= RD_GW_VERIFY_PASSES; pass++)
     {
      if(!ReadStops(ticket, curSl, curTp))
         return Failed(op, s.name, r, "Position " + RdTicketText(ticket) + " not found after the open - check the Trade tab " +
                       "(it may have been stopped out already)");
      slOk = LevelEq(s, curSl, sl);
      tpOk = LevelEq(s, curTp, tp);
      if((slOk && tpOk) || pass == RD_GW_VERIFY_PASSES)
         break;
      RD_LOG_WARN("[" + op + "] verify: " + RdTicketText(ticket) + " has sl=" + Px(s, curSl) + " tp=" + Px(s, curTp) +
                  ", wanted sl=" + Px(s, sl) + " tp=" + Px(s, tp) + " -> setting them (pass " + IntegerToString(pass) + ")");
      if(!ModifyPositionSLTP(ticket, sl, tp, fix) && fix.code == 0)
         break;
     }
   out.sl = curSl;
   out.tp = curTp;
   if(slOk && tpOk)
     {
      RD_LOG_INFO("[" + op + "] verify SL/TP ok (" + Px(s, curSl) + "/" + Px(s, curTp) + ")");
      return RdOk(r, "");
     }
   if(slOk)
     {
      RD_LOG_WARN("[" + op + "] verify: SL ok, TP not set (" + fix.message + ")");
      return RdWarn(r, "TP could not be set (" + fix.message + ")");
     }
   string why = (fix.message != "") ? fix.message : "server shows SL " + Px(s, curSl);
   RD_LOG_ERROR("[" + op + "] " + s.name + " position " + RdTicketText(ticket) + " has no valid SL: " + why);
   if(!m_cfg.closeIfStopFails)
      return Failed(op, s.name, r, "Position " + RdTicketText(ticket) + " is open WITHOUT a valid SL - set it now (" + why + ")");
   STradeOutcome closed;
   SResult cr;
   if(!ClosePosition(ticket, addedVolume, closed, cr))
      return Failed(op, s.name, r, "SL could not be attached and closing FAILED - close " + RdTicketText(ticket) +
                    " by hand now (" + cr.message + ")");
   return Failed(op, s.name, r, "SL could not be attached - position closed (" + why + ")");
  }

//+------------------------------------------------------------------+
//| G-02 PlacePending. BC-08: expiration 0 = GTC, else now + N h;    |
//| error 147 -> resend with 0 and warn.                             |
//+------------------------------------------------------------------+
bool CTradeGateway::PlacePending(const string symbol, const ESide side, const EOrderKind kind, const double lots,
                                 const double price, const double sl, const double tp, STradeOutcome &out, SResult &r)
  {
   const string op = "G-02";
   out.Reset();
   out.requested = lots;
   if(kind == KIND_MARKET)
      return Refuse(op, symbol, r, "PlacePending needs a limit or stop order type");
   SSymbolSpec s;
   SQuote quote;
   if(!Prepare(op, symbol, s, quote, r))
      return false;
   if(!CheckOpen(op, s, side, kind, lots, sl, tp, r) || !CheckOrderLimit(op, symbol, r))
      return false;
   double np = RdNormalizePrice(s, price);
   double nsl = RdNormalizePrice(s, sl);
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   if(!CValidators::PendingGeometry(side, kind, np, nsl, ntp, quote, s, r) ||
      !CValidators::PendingStops(side, kind, np, nsl, ntp, quote, s, r))
      return Refused(op, symbol, r);

   SMt4Request q;
   BaseRequest(q, symbol);
   if(side == SIDE_BUY)
      q.cmd = (kind == KIND_LIMIT) ? OP_BUYLIMIT : OP_BUYSTOP;
   else
      q.cmd = (kind == KIND_LIMIT) ? OP_SELLLIMIT : OP_SELLSTOP;
   q.volume = lots;
   q.price = np;
   q.sl = nsl;
   q.tp = ntp;
   q.expiration = (m_cfg.pendingExpiryHours > 0) ? RdServerTime() + m_cfg.pendingExpiryHours * 3600 : 0;
   SSendCtx c;
   c.Reset();
   c.side = side;
   int ticket = 0;
   bool ok = Send(op, GWACT_PENDING, q, s, c, ticket, r);
   out.sends = c.sends;
   if(!ok)
      return false;

   out.ticket = (ulong)ticket;
   out.order = (ulong)ticket;
   out.price = np;
   out.volume = lots;
   out.sl = nsl;
   out.tp = ntp;
   out.expiration = q.expiration;
   out.timePolicy = (q.expiration > 0) ? "SPECIFIED" : "GTC";
   if(c.expiryDropped)
      out.notes = "expiry not allowed on " + symbol + ": the order stays until deleted";
   SResult vr;
   if(!VerifyPending(out.ticket, s, np, nsl, ntp, vr))
     {
      r = vr;
      return false;
     }
   out.notes = RdJoin(out.notes, (vr.sev == SEV_WARN) ? vr.message : "", "; ");
   string msg = RdOrderText(side, kind) + " " + RdFormatLots(s, lots) + " " + symbol + " @" + Px(s, np) + " placed " +
                RdTicketText(out.ticket);
   RD_LOG_INFO("[" + op + "] " + symbol + " done: " + msg + " time=" + out.timePolicy + (out.notes != "" ? " (" + out.notes + ")" : ""));
   if(out.notes != "")
      return RdWarn(r, msg + " - " + out.notes);
   return RdOk(r, msg);
  }

bool CTradeGateway::VerifyPending(const ulong ticket, const SSymbolSpec &s, const double price, const double sl,
                                  const double tp, SResult &r)
  {
   const string op = "G-02";
   r.Reset();
   SOrder o;
   bool found = false;
   for(int i = 0; i < RD_GW_SELECT_TRIES && !found; i++)
     {
      found = SelectPending(ticket, o);
      if(!found && !IsStopped())
         Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   if(!found)
      return RdWarn(r, "order not visible in the terminal yet - check the Trade tab");
   if(LevelEq(s, o.sl, sl) && LevelEq(s, o.tp, tp) && RdPriceEq(s, o.price, price))
     {
      RD_LOG_INFO("[" + op + "] verify price/SL/TP ok (" + Px(s, o.price) + "/" + Px(s, o.sl) + "/" + Px(s, o.tp) + ")");
      return RdOk(r, "");
     }
   RD_LOG_WARN("[" + op + "] verify: " + RdTicketText(ticket) + " shows @" + Px(s, o.price) + " sl=" + Px(s, o.sl) + " tp=" +
               Px(s, o.tp) + " -> modifying");
   SResult fix;
   bool fixed = ModifyPending(ticket, price, sl, tp, fix) && SelectPending(ticket, o) && LevelEq(s, o.sl, sl);
   if(fixed)
      return LevelEq(s, o.tp, tp) ? RdOk(r, "") : RdWarn(r, "TP could not be set (" + fix.message + ")");
   if(!m_cfg.closeIfStopFails)
      return Failed(op, s.name, r, "Order " + RdTicketText(ticket) + " has no valid SL - set it now (" + fix.message + ")");
   SResult dr;
   if(DeletePending(ticket, dr))
      return Failed(op, s.name, r, "SL could not be attached - order deleted (" + fix.message + ")");
   return Failed(op, s.name, r, "SL could not be attached and deleting FAILED - delete " + RdTicketText(ticket) +
                 " by hand now (" + dr.message + ")");
  }

#endif // RD_PLATFORM_TRADEGATEWAYMT4_MQH
