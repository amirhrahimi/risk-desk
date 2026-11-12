//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayMT5.mqh                          |
//| Layer   : Platform. Included only by TradeGateway.mqh (MQL5).    |
//| Purpose : MT5 implementation of CTradeGateway (MqlTradeRequest + |
//|           OrderSend, no Standard Library, ADR-002): the gateway  |
//|           primitives G-01..G-08 of 06 section 5 with BC-06/07/08/|
//|           09/10/11/13/14/15/16/18. Same public API as            |
//|           TradeGatewayMT4.mqh (ADR-001).                         |
//|           This file: class declaration, G-01 OpenMarket, G-02    |
//|           PlacePending and their SL verification (BC-11, R7).    |
//|           G-03..G-08: TradeGatewayMT5Manage.mqh. The             |
//|           send engine (ladders, retries, ambiguity check, log)   |
//|           is in TradeGatewayMT5Send.mqh.                         |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYMT5_MQH
#define RD_PLATFORM_TRADEGATEWAYMT5_MQH

#include "TradeGatewayBase.mqh"

#define RD_GW_FILLS_MAX 4
#define RD_GW_TIMES_MAX 4

// One request on its way through the ladders, retries and checks.
struct SSendCtx
  {
   int               fills[RD_GW_FILLS_MAX];   // ENUM_ORDER_TYPE_FILLING candidates (BC-06)
   int               fillCount;
   int               fillIndex;
   int               times[RD_GW_TIMES_MAX];   // ENUM_ORDER_TYPE_TIME rungs (BC-08)
   datetime          exps[RD_GW_TIMES_MAX];
   int               timeCount;
   int               timeIndex;
   datetime          requestTime;   // server time of the first send (BC-14)
   int               sends;         // OrderSend calls for this request
   int               retries;       // BC-13 retries used
   bool              retriedOnce;   // "retry once" codes used their retry
   bool              ambiguousRetried;
   bool              stopsRejected; // the server answered INVALID_STOPS
   bool              alreadyDone;   // NO_CHANGES / POSITION_CLOSED
   bool              partial;       // DONE_PARTIAL
   ESide             side;          // side of the trade (position / order), for texts and the TP refresh
   double            sl;            // G-01: SL, for the R/R TP refresh
   double            tp;            // G-01: TP of the latest attempt, attached or not
   double            tpRR;          // G-01: > 0 = TP follows the fresh entry (Auto R/R)
   double            preVolume;     // G-01 netting / G-04: position volume before the request
   ulong             foundPosition; // position found for the request (BC-14)

   void              Reset()
     {
      for(int i = 0; i < RD_GW_FILLS_MAX; i++)
         fills[i] = ORDER_FILLING_FOK;
      for(int j = 0; j < RD_GW_TIMES_MAX; j++)
        {
         times[j] = ORDER_TIME_GTC;
         exps[j] = 0;
        }
      fillCount = 0;
      fillIndex = 0;
      timeCount = 0;
      timeIndex = 0;
      requestTime = 0;
      sends = 0;
      retries = 0;
      retriedOnce = false;
      ambiguousRetried = false;
      stopsRejected = false;
      alreadyDone = false;
      partial = false;
      side = SIDE_BUY;
      sl = 0.0;
      tp = 0.0;
      tpRR = 0.0;
      preVolume = 0.0;
      foundPosition = 0;
     }
  };

// BC-06: the policy that worked, per symbol and kind of request.
struct SFillMemo
  {
   string            symbol;
   bool              pending;
   int               fill;
  };

class CTradeGateway : public CTradeGatewayBase
  {
private:
   SFillMemo         m_fillMemo[];

   //--- send engine (TradeGatewayMT5Send.mqh)
   bool              Send(const string op, const EGwAction act, MqlTradeRequest &req, const SSymbolSpec &s,
                          SSendCtx &c, MqlTradeResult &res, SResult &r);
   bool              FreshPrice(MqlTradeRequest &req, const SSymbolSpec &s, SSendCtx &c);
   bool              Executed(const EGwAction act, const MqlTradeRequest &req, const SSymbolSpec &s, SSendCtx &c,
                              MqlTradeResult &res);
   bool              FindOpenDeal(const MqlTradeRequest &req, SSendCtx &c, MqlTradeResult &res);
   bool              FindPlacedOrder(const MqlTradeRequest &req, const SSymbolSpec &s, SSendCtx &c, MqlTradeResult &res);
   bool              CloseTookEffect(const MqlTradeRequest &req, SSendCtx &c, MqlTradeResult &res);
   void              DealFillings(const SSymbolSpec &s, SSendCtx &c);
   void              PendingFillings(const SSymbolSpec &s, SSendCtx &c);
   void              ExpirationRungs(const SSymbolSpec &s, SSendCtx &c);
   void              AddFill(SSendCtx &c, const int fill) const;
   void              AddTime(SSendCtx &c, const int typeTime, const datetime expiration) const;
   int               CachedFill(const string symbol, const bool pending) const;
   void              RememberFill(const string symbol, const bool pending, const int fill);
   string            FillName(const int fill) const;
   string            TimeName(const int typeTime) const;
   string            FillsTried(const SSendCtx &c) const;
   string            TypeText(const ENUM_ORDER_TYPE type) const;
   string            Detail(const STradeCode &tc, const MqlTradeRequest &req, const SSymbolSpec &s, const SSendCtx &c) const;
   string            StopsHint(const MqlTradeRequest &req, const SSymbolSpec &s, const SSendCtx &c) const;
   void              LogRequest(const string op, const EGwAction act, const MqlTradeRequest &req, const SSymbolSpec &s,
                                const SSendCtx &c) const;
   void              LogResult(const string op, const MqlTradeRequest &req, const MqlTradeResult &res, const STradeCode &tc,
                               const SSymbolSpec &s, const int lastError) const;

   //--- helpers of the operations (this file)
   void              BaseRequest(MqlTradeRequest &req, const string symbol) const;
   ulong             OpenedPosition(const MqlTradeResult &res, const SSendCtx &c, const string symbol) const;
   ulong             TicketOfPositionId(const long id) const;
   bool              ReadStops(const ulong ticket, double &sl, double &tp) const;
   bool              VerifyStops(const string op, const ulong ticket, const SSymbolSpec &s, const double sl, const double tp,
                                 const double addedVolume, STradeOutcome &out, SResult &r);
   bool              VerifyPending(const ulong ticket, const SSymbolSpec &s, const double price, const double sl,
                                   const double tp, SResult &r);
   bool              ReadSelectedOrder(SOrder &o, bool &stopLimit) const;
   bool              OrderListed(const ulong ticket) const;
   bool              WaitUnlisted(const ulong ticket) const;
   void              ReadSelectedPosition(SPosition &p) const;
   bool              DealProfit(const ulong deal, double &profit) const;
   ulong             DealOfOrder(const ulong order, const long positionId) const;
   string            ExpirationNote(const SSymbolSpec &s, const SSendCtx &c) const;

public:
   bool              IsHedging() const;
   // G-01. sl > 0 required (rule R7). tpRR > 0: TP = entry +/- tpRR x |entry - sl|,
   // recomputed from the fresh price of every attempt (Auto R/R mode); 'tp' is then ignored.
   bool              OpenMarket(const string symbol, const ESide side, const double lots, const double sl, const double tp,
                                STradeOutcome &out, SResult &r, const double tpRR = 0.0);
   bool              PlacePending(const string symbol, const ESide side, const EOrderKind kind, const double lots,
                                  const double price, const double sl, const double tp, STradeOutcome &out, SResult &r);
   bool              ModifyPositionSLTP(const ulong ticket, const double sl, const double tp, SResult &r);
   bool              ModifyPending(const ulong ticket, const double price, const double sl, const double tp, SResult &r);
   // volume <= 0 or >= the position: close it all.
   bool              ClosePosition(const ulong ticket, const double volume, STradeOutcome &out, SResult &r);
   bool              DeletePending(const ulong ticket, SResult &r);
   bool              ListPositions(const STradeFilter &f, SPosition &arr[], SResult &r);
   bool              ListPending(const STradeFilter &f, SOrder &arr[], SResult &r);
   bool              SelectPosition(const ulong ticket, SPosition &p);
   bool              SelectPending(const ulong ticket, SOrder &o);
  };

#include "TradeGatewayMT5Send.mqh"
#include "TradeGatewayMT5Manage.mqh"

//+------------------------------------------------------------------+
//| BC-10: only RETAIL_HEDGING is hedging.                           |
//+------------------------------------------------------------------+
bool CTradeGateway::IsHedging() const
  {
   return RdIsHedgingMarginMode(RdAccountMarginMode());
  }

//+------------------------------------------------------------------+
//| BC-18: every field set explicitly.                               |
//+------------------------------------------------------------------+
void CTradeGateway::BaseRequest(MqlTradeRequest &req, const string symbol) const
  {
   ZeroMemory(req);
   req.symbol       = symbol;
   req.magic        = (ulong)m_cfg.magic;
   req.comment      = m_cfg.comment;
   req.deviation    = (ulong)(m_cfg.slippagePoints > 0 ? m_cfg.slippagePoints : 0);
   req.type_filling = ORDER_FILLING_FOK;
   req.type_time    = ORDER_TIME_GTC;
   req.expiration   = 0;
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
   SQuote q;
   if(!Prepare(op, symbol, s, q, r))
      return false;
   bool wantsTp = (tp > 0.0 || tpRR > 0.0);   // CheckOpen only tests "TP > 0" (BC-11 TP flag)
   if(!CheckOpen(op, s, side, KIND_MARKET, lots, sl, wantsTp ? 1.0 : 0.0, r))
      return false;

   double entry = RdNormalizePrice(s, side == SIDE_BUY ? q.ask : q.bid);
   double nsl = RdNormalizePrice(s, sl);
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   if(tpRR > 0.0 && !CRiskMath::TpFromRR(side, entry, nsl, tpRR, s, ntp, r))
      return Refused(op, symbol, r);
   if(!CValidators::MarketSide(side, nsl, ntp, q, s, r))
      return Refused(op, symbol, r);

   //--- BC-10: on netting an opposite deal would reduce or reverse the position
   double preVolume = 0.0;
   if(!IsHedging() && PositionSelect(symbol))
     {
      ESide posSide = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? SIDE_BUY : SIDE_SELL;
      if(posSide != side)
         return Refuse(op, symbol, r, "Netting account: a " + RdSideText(side) + " would reduce or reverse the open " +
                       RdSideText(posSide) + " position on " + symbol + " - use Half Close or Chart Close");
      preVolume = PositionGetDouble(POSITION_VOLUME);
     }

   bool attach = WantStopsWithOrder(symbol);
   MqlTradeRequest req;
   BaseRequest(req, symbol);
   req.action = TRADE_ACTION_DEAL;
   req.type   = (side == SIDE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.volume = lots;
   req.price  = entry;
   req.sl     = attach ? nsl : 0.0;
   req.tp     = attach ? ntp : 0.0;

   SSendCtx c;
   c.Reset();
   c.side = side;
   c.sl = nsl;
   c.tp = ntp;
   c.tpRR = tpRR;
   c.preVolume = preVolume;
   DealFillings(s, c);
   MqlTradeResult res;
   bool ok = Send(op, GWACT_OPEN, req, s, c, res, r);

   //--- BC-11 Auto: stops refused although BC-07 passed -> send without, attach right after
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
         req.sl = 0.0;
         req.tp = 0.0;
         attach = false;
         c.stopsRejected = false;
         ok = Send(op, GWACT_OPEN, req, s, c, res, r);
        }
      else
         if(!check.ok)
            r.message = r.message + " - " + check.message;
     }
   out.sends = c.sends;
   if(!ok)
      return false;

   out.order = res.order;
   out.deal = res.deal;
   out.volume = (res.volume > 0.0) ? res.volume : lots;
   out.price = res.price;
   out.filling = FillName(req.type_filling);
   out.partialFill = c.partial;
   out.stopsAfter = !attach;
   ulong pos = OpenedPosition(res, c, symbol);
   if(pos == 0)
      return Failed(op, symbol, r, "Order executed (deal " + RdTicketText(res.deal) + ") but the position was not found - " +
                    "check its SL in the Trade tab now");
   out.ticket = pos;
   if(!(out.price > 0.0) && PositionSelectByTicket(pos))
      out.price = PositionGetDouble(POSITION_PRICE_OPEN);

   SResult vr;
   if(!VerifyStops(op, pos, s, nsl, c.tp, out.volume, out, vr))
     {
      r = vr;
      return false;
     }
   string notes = "";
   if(c.partial)
      notes = "Partially filled " + RdFormatLots(s, out.volume) + " of " + RdFormatLots(s, lots);
   if(out.stopsAfter)
      notes = RdJoin(notes, "SL/TP attached right after the open", "; ");
   if(vr.sev == SEV_WARN)
      notes = RdJoin(notes, vr.message, "; ");
   if(c.preVolume > 0.0)
      notes = RdJoin(notes, "merged with the open " + RdFormatLots(s, c.preVolume) + " lot position (netting)", "; ");
   out.notes = notes;
   string msg = RdOrderText(side, KIND_MARKET) + " " + RdFormatLots(s, out.volume) + " " + symbol + " @" + Px(s, out.price) +
                " " + RdTicketText(pos);
   RD_LOG_INFO("[" + op + "] " + symbol + " done: " + msg + " fill=" + out.filling + (notes != "" ? " (" + notes + ")" : ""));
   if(notes != "")
      return RdWarn(r, msg + " - " + notes);
   return RdOk(r, msg);
  }

//+------------------------------------------------------------------+
//| Position of a filled deal: DEAL_POSITION_ID, else the order      |
//| ticket (hedging) or the symbol's position (netting).             |
//+------------------------------------------------------------------+
ulong CTradeGateway::OpenedPosition(const MqlTradeResult &res, const SSendCtx &c, const string symbol) const
  {
   if(c.foundPosition > 0)
      return c.foundPosition;
   for(int i = 0; i < RD_GW_SELECT_TRIES; i++)
     {
      if(res.deal > 0 && HistoryDealSelect(res.deal))
        {
         ulong t = TicketOfPositionId(HistoryDealGetInteger(res.deal, DEAL_POSITION_ID));
         if(t > 0)
            return t;
        }
      if(IsHedging())
        {
         if(res.order > 0 && PositionSelectByTicket(res.order))
            return res.order;
        }
      else
         if(PositionSelect(symbol))
            return (ulong)PositionGetInteger(POSITION_TICKET);
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return 0;
  }

ulong CTradeGateway::TicketOfPositionId(const long id) const
  {
   if(id <= 0)
      return 0;
   if(PositionSelectByTicket((ulong)id))
      return (ulong)id;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_IDENTIFIER) == id)
         return t;
     }
   return 0;
  }

bool CTradeGateway::ReadStops(const ulong ticket, double &sl, double &tp) const
  {
   for(int i = 0; i < RD_GW_SELECT_TRIES; i++)
     {
      if(PositionSelectByTicket(ticket))
        {
         sl = PositionGetDouble(POSITION_SL);
         tp = PositionGetDouble(POSITION_TP);
         return true;
        }
      if(IsStopped())
         break;
      Sleep(RD_GW_SELECT_SLEEP_MS);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| BC-11 verify: SL/TP on the server equal the request (half tick). |
//| Wrong -> modify (G-03 retries itself). SL still wrong -> rule R7:|
//| close the volume this request added (InpCloseIfStopFails).       |
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
         break;   // refused before sending (stops/freeze level): repeating cannot help
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
   string rest = "";
   if(closed.remaining > 0.0 && ReadStops(ticket, curSl, curTp) && !(curSl > 0.0))
      rest = "; the remaining " + RdFormatLots(s, closed.remaining) + " lot has NO SL - set it now";
   return Failed(op, s.name, r, "SL could not be attached - position closed (" + why + ")" + rest);
  }

//+------------------------------------------------------------------+
//| G-02 PlacePending                                                |
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
   SQuote q;
   if(!Prepare(op, symbol, s, q, r))
      return false;
   if(!CheckOpen(op, s, side, kind, lots, sl, tp, r) || !CheckOrderLimit(op, symbol, r))
      return false;
   double np = RdNormalizePrice(s, price);
   double nsl = RdNormalizePrice(s, sl);
   double ntp = (tp > 0.0) ? RdNormalizePrice(s, tp) : 0.0;
   if(!CValidators::PendingGeometry(side, kind, np, nsl, ntp, q, s, r) ||
      !CValidators::PendingStops(side, kind, np, nsl, ntp, q, s, r))
      return Refused(op, symbol, r);

   MqlTradeRequest req;
   BaseRequest(req, symbol);
   req.action = TRADE_ACTION_PENDING;
   if(side == SIDE_BUY)
      req.type = (kind == KIND_LIMIT) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
   else
      req.type = (kind == KIND_LIMIT) ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;
   req.volume = lots;
   req.price  = np;
   req.sl     = nsl;
   req.tp     = ntp;

   SSendCtx c;
   c.Reset();
   c.side = side;
   PendingFillings(s, c);
   ExpirationRungs(s, c);
   MqlTradeResult res;
   bool ok = Send(op, GWACT_PENDING, req, s, c, res, r);
   out.sends = c.sends;
   if(!ok)
      return false;

   out.ticket = res.order;
   out.order = res.order;
   out.price = np;
   out.volume = lots;
   out.sl = nsl;
   out.tp = ntp;
   out.filling = FillName(req.type_filling);
   out.timePolicy = TimeName(req.type_time);
   out.expiration = req.expiration;
   out.notes = ExpirationNote(s, c);

   SResult vr;
   if(!VerifyPending(out.ticket, s, np, nsl, ntp, vr))
     {
      r = vr;
      return false;
     }
   out.notes = RdJoin(out.notes, (vr.sev == SEV_WARN) ? vr.message : "", "; ");
   string msg = RdOrderText(side, kind) + " " + RdFormatLots(s, lots) + " " + symbol + " @" + Px(s, np) + " placed " +
                RdTicketText(out.ticket);
   RD_LOG_INFO("[" + op + "] " + symbol + " done: " + msg + " fill=" + out.filling + " time=" + out.timePolicy +
               (out.notes != "" ? " (" + out.notes + ")" : ""));
   if(out.notes != "")
      return RdWarn(r, msg + " - " + out.notes);
   return RdOk(r, msg);
  }

//+------------------------------------------------------------------+
//| A placed order carries the SL it was sent with (rule R7): fix it |
//| once, else delete the order (InpCloseIfStopFails).               |
//+------------------------------------------------------------------+
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

#endif // RD_PLATFORM_TRADEGATEWAYMT5_MQH
