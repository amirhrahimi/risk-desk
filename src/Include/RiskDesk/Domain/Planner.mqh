//+------------------------------------------------------------------+
//| RiskDesk - Domain/Planner.mqh                                    |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : builds what a command will send, from lines + quote +  |
//|           specs + settings. No I/O.                              |
//|                                                                  |
//| Opening a trade is two steps, because the money value of the SL  |
//| distance comes from the platform (BC-05) and depends on the side |
//| and the entry the planner chooses:                               |
//|   1. Market / MarketPreview / Pending -> side, kind, entry, SL,  |
//|      TP (normalized, validated: 04 sections 6-8, BC-07)          |
//|   2. platform: LossPerLot(plan.side, plan.entry, plan.sl) and    |
//|      ProfitPerLot(plan.side, plan.entry, plan.tp)                |
//|   3. Size -> lots, money risk, reward (04 sections 2-4, BC-04)   |
//| then RiskBudget.Check and the margin check (Platform).           |
//|                                                                  |
//| Managing trades:                                                 |
//|   RiskFree    -> new SL for one position (04 section 9, F-11)    |
//|   MovePending -> new price/SL/TP of a dragged order (OP-16)      |
//| (Partial close volume: CRiskMath::PartialClose.)                 |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_PLANNER_MQH
#define RD_DOMAIN_PLANNER_MQH

#include "Types.mqh"
#include "PriceMath.mqh"
#include "Format.mqh"
#include "RiskMath.mqh"
#include "Validators.mqh"

// One position as Risk Free needs it.
struct SRiskFreeInput
  {
   ESide             side;
   double            open;            // average open price on netting accounts (BC-10)
   double            sl;              // 0 = none
   double            tp;              // 0 = none; never changed by Risk Free
   double            volume;
   double            tickValue;       // money of a one-tick move for 1.0 lot, account currency (Platform)
   double            bookedCost;      // RF_COMMISSION: commission + swap booked on the position, as a cost (> 0)

   void              Reset()
     {
      side = SIDE_BUY;
      open = 0.0;
      sl = 0.0;
      tp = 0.0;
      volume = 0.0;
      tickValue = 0.0;
      bookedCost = 0.0;
     }
  };

struct SRiskFreeResult
  {
   double            offset;          // price distance from the open price
   double            costDistance;    // commission (or booked cost) part of the offset
   double            target;          // the new SL
   double            needPrice;       // Bid (buy) / Ask (sell) from which the target can be applied

   void              Reset() { offset = 0.0; costDistance = 0.0; target = 0.0; needPrice = 0.0; }
  };

class CPlanner
  {
private:
   static bool       PlanTp(const ESide side, const double entry, const double sl, const SLines &lines,
                            const SSymbolSpec &s, const SPlanSettings &cfg, double &tp, SResult &r);

public:
   static bool       Market(const ESide side, const SLines &lines, const SQuote &q, const SSymbolSpec &s,
                            const SPlanSettings &cfg, STradePlan &plan, SResult &r);
   static bool       MarketPreview(const SLines &lines, const SQuote &q, const SSymbolSpec &s,
                                   const SPlanSettings &cfg, STradePlan &plan, SResult &r);
   static bool       Pending(const SLines &lines, const SQuote &q, const SSymbolSpec &s,
                             const SPlanSettings &cfg, STradePlan &plan, SResult &r);
   static bool       Size(STradePlan &plan, const SSymbolSpec &s, const SAccountSpec &acc, const SPlanSettings &cfg,
                          const double riskPct, const double lossPerLot, const double profitPerLotTp,
                          const double sameSideVolume, SLotResult &lot, SResult &r);
   static bool       RiskFree(const SRiskFreeInput &in, const SQuote &q, const SSymbolSpec &s,
                              const SPlanSettings &cfg, SRiskFreeResult &rf, SResult &r);
   static bool       MovePending(const SOrder &o, const ELineRole role, const double dropped, const SQuote &q,
                                 const SSymbolSpec &s, SOrder &moved, SResult &r);
  };

//+------------------------------------------------------------------+
//| TP by mode (F-17, ADR-013): none / R/R from the entry / the line.|
//+------------------------------------------------------------------+
bool CPlanner::PlanTp(const ESide side, const double entry, const double sl, const SLines &lines,
                      const SSymbolSpec &s, const SPlanSettings &cfg, double &tp, SResult &r)
  {
   tp = 0.0;
   r.Reset();
   if(cfg.tpMode == TPMODE_AUTO_RR)
      return CRiskMath::TpFromRR(side, entry, sl, cfg.tpRR, s, tp, r);
   if(cfg.tpMode == TPMODE_MANUAL_LINE && lines.hasTp && lines.tp > 0.0)
      tp = RdNormalizePrice(s, lines.tp);
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| OP-03/04: market order of the given side. Entry = Ask (buy) or   |
//| Bid (sell); in Auto R/R mode the TP is computed from that entry  |
//| (call again with a fresh quote on every retry).                  |
//+------------------------------------------------------------------+
bool CPlanner::Market(const ESide side, const SLines &lines, const SQuote &q, const SSymbolSpec &s,
                      const SPlanSettings &cfg, STradePlan &plan, SResult &r)
  {
   plan.Reset();
   r.Reset();
   plan.side = side;
   plan.kind = KIND_MARKET;
   if(!CValidators::QuoteOk(q, s, r))
      return false;
   if(!(lines.sl > 0.0))
      return RdFail(r, "No SL line - click Add Line first");

   plan.entry = RdNormalizePrice(s, (side == SIDE_BUY) ? q.ask : q.bid);
   plan.sl = RdNormalizePrice(s, lines.sl);
   // SL first: the Auto R/R TP is derived from it.
   if(!CValidators::MarketSide(side, plan.sl, 0.0, q, s, r))
      return false;
   if(!PlanTp(side, plan.entry, plan.sl, lines, s, cfg, plan.tp, r))
      return false;
   if(plan.tp > 0.0 && !CValidators::MarketSide(side, plan.sl, plan.tp, q, s, r))
      return false;
   plan.rr = CRiskMath::RewardRatio(plan.entry, plan.sl, plan.tp);
   return RdOk(r, RdOrderText(side, KIND_MARKET));
  }

//+------------------------------------------------------------------+
//| OP-15 / F-03: the side implied by the SL line, then Market().    |
//+------------------------------------------------------------------+
bool CPlanner::MarketPreview(const SLines &lines, const SQuote &q, const SSymbolSpec &s,
                             const SPlanSettings &cfg, STradePlan &plan, SResult &r)
  {
   plan.Reset();
   r.Reset();
   if(!CValidators::QuoteOk(q, s, r))
      return false;
   ESide side = SIDE_BUY;
   if(!CValidators::PreviewSide(RdNormalizePrice(s, lines.sl), q, s, side, r))
      return false;
   return Market(side, lines, q, s, cfg, plan, r);
  }

//+------------------------------------------------------------------+
//| OP-06/07: pending order from the Entry/SL(/TP) lines. plan.side  |
//| and plan.kind are filled as far as the classification got, also  |
//| when the plan is refused (Pending Info shows them).              |
//+------------------------------------------------------------------+
bool CPlanner::Pending(const SLines &lines, const SQuote &q, const SSymbolSpec &s,
                       const SPlanSettings &cfg, STradePlan &plan, SResult &r)
  {
   plan.Reset();
   r.Reset();
   if(!CValidators::QuoteOk(q, s, r))
      return false;
   plan.entry = RdNormalizePrice(s, lines.entry);
   plan.sl = RdNormalizePrice(s, lines.sl);
   double lineTp = 0.0;
   if(cfg.tpMode == TPMODE_MANUAL_LINE && lines.hasTp && lines.tp > 0.0)
      lineTp = RdNormalizePrice(s, lines.tp);

   ESide side = SIDE_BUY;
   EOrderKind kind = KIND_MARKET;
   bool classified = CValidators::ClassifyPending(plan.entry, plan.sl, lineTp, q, s, side, kind, r);
   plan.side = side;
   plan.kind = kind;
   if(!classified)
      return false;
   if(!PlanTp(side, plan.entry, plan.sl, lines, s, cfg, plan.tp, r))
      return false;
   if(!CValidators::PendingGeometry(side, kind, plan.entry, plan.sl, plan.tp, q, s, r))
      return false;
   if(!CValidators::PendingStops(side, kind, plan.entry, plan.sl, plan.tp, q, s, r))
      return false;
   plan.rr = CRiskMath::RewardRatio(plan.entry, plan.sl, plan.tp);
   return RdOk(r, RdOrderText(side, kind));
  }

//+------------------------------------------------------------------+
//| Step 3: lots and money. lossPerLot / profitPerLotTp: platform    |
//| valuations for 1.0 lot of entry -> SL and entry -> TP (0 = no    |
//| TP or unknown). sameSideVolume: open + pending volume in the     |
//| plan's direction on the symbol (MT5 volume limit, else 0).       |
//| true with r.sev == SEV_WARN: capped / min lot above the risk.    |
//+------------------------------------------------------------------+
bool CPlanner::Size(STradePlan &plan, const SSymbolSpec &s, const SAccountSpec &acc, const SPlanSettings &cfg,
                    const double riskPct, const double lossPerLot, const double profitPerLotTp,
                    const double sameSideVolume, SLotResult &lot, SResult &r)
  {
   r.Reset();
   plan.lots = 0.0;
   plan.lossPerLot = lossPerLot;
   SResult sized;
   if(!CRiskMath::LotsFromRisk(riskPct, lossPerLot, s, acc, cfg, lot, sized))
     {
      r = sized;
      return false;
     }
   if(!CValidators::VolumeLimit(s, sameSideVolume, lot.lots, r))
      return false;

   plan.lots = lot.lots;
   plan.riskMoney = lot.actualRisk;
   plan.riskPct = lot.actualPct;
   plan.rewardMoney = 0.0;
   if(plan.tp > 0.0 && profitPerLotTp > 0.0)
      plan.rewardMoney = lot.lots * profitPerLotTp - lot.lots * MathMax(0.0, cfg.commissionPerLot);
   plan.rr = CRiskMath::RewardRatio(plan.entry, plan.sl, plan.tp);
   plan.warnings = (sized.sev == SEV_WARN) ? sized.message : "";
   r = sized;
   return true;
  }

//+------------------------------------------------------------------+
//| 04 section 9 (F-11, OP-09). true: move the SL to rf.target       |
//| (keep the TP). false: skipped, r.sev == SEV_WARN with the reason |
//| ("not in profit", "already protected", "not enough profit        |
//| (needs Bid >= x)", "frozen: ..."), or SEV_ERROR on bad input.    |
//+------------------------------------------------------------------+
bool CPlanner::RiskFree(const SRiskFreeInput &in, const SQuote &q, const SSymbolSpec &s,
                        const SPlanSettings &cfg, SRiskFreeResult &rf, SResult &r)
  {
   rf.Reset();
   r.Reset();
   if(!CValidators::QuoteOk(q, s, r))
      return false;
   if(!(in.open > 0.0) || !(in.volume > 0.0))
      return RdFail(r, "Invalid position (open " + RdFormatPrice(s, in.open) + ", volume " + RdNum(in.volume) + ")");
   bool isBuy = (in.side == SIDE_BUY);

   // OP-09: "in profit" is judged by price versus open, not by money.
   if(isBuy ? !RdPriceGt(s, q.bid, in.open) : !RdPriceLt(s, q.ask, in.open))
      return RdSkip(r, "not in profit");

   double spread = MathMax(0.0, q.ask - q.bid);
   double cost = 0.0;
   if(cfg.riskFreeMode == RF_SPREAD_COMMISSION)
     {
      if(!CRiskMath::CostDistance(MathMax(0.0, cfg.commissionPerLot) * in.volume, in.tickValue * in.volume, s, cost))
         return RdFail(r, "Cannot value the commission on " + s.name + " (tick value " + RdNum(in.tickValue) + ")");
      rf.offset = spread + cost;
     }
   else
      if(cfg.riskFreeMode == RF_SPREAD)
         rf.offset = spread;
      else
         if(cfg.riskFreeMode == RF_COMMISSION)
           {
            if(!CRiskMath::CostDistance(in.bookedCost, in.tickValue * in.volume, s, cost))
               return RdFail(r, "Cannot value the booked costs on " + s.name + " (tick value " + RdNum(in.tickValue) + ")");
            rf.offset = cost;
           }
         else
            rf.offset = 0.0;   // RF_EXACT
   rf.costDistance = cost;
   rf.offset += cfg.riskFreeExtraPoints * s.point;

   double tick = RdTick(s);
   double stops = s.stopsLevel * s.point;
   if(isBuy)
     {
      rf.target = RdRoundPriceUp(s, in.open + rf.offset);
      rf.needPrice = RdNormalizePrice(s, rf.target + stops + tick);
      if(in.sl > 0.0 && !RdPriceGt(s, rf.target, in.sl))
         return RdSkip(r, "already protected (SL " + RdFormatPrice(s, in.sl) + ")");
      if(RdPriceGt(s, rf.target, q.bid - stops - tick))
         return RdSkip(r, "not enough profit (needs Bid >= " + RdFormatPrice(s, rf.needPrice) + ")");
     }
   else
     {
      rf.target = RdRoundPriceDown(s, in.open - rf.offset);
      rf.needPrice = RdNormalizePrice(s, rf.target - stops - tick);
      if(in.sl > 0.0 && !RdPriceLt(s, rf.target, in.sl))
         return RdSkip(r, "already protected (SL " + RdFormatPrice(s, in.sl) + ")");
      if(RdPriceLt(s, rf.target, q.ask + stops + tick))
         return RdSkip(r, "not enough profit (needs Ask <= " + RdFormatPrice(s, rf.needPrice) + ")");
     }

   SResult frozen;
   if(!CValidators::PositionNotFrozen(in.side, in.sl, in.tp, q, s, frozen))
      return RdSkip(r, "frozen: " + frozen.message);
   return RdOk(r, "SL to " + RdFormatPrice(s, rf.target));
  }

//+------------------------------------------------------------------+
//| OP-16: a line of placed order 'o' was dropped at 'dropped'.      |
//| Entry line: the whole order moves (SL and TP by the same         |
//| distance, 0 stays 0). SL/TP line: only that level changes.       |
//| Validates the current freeze level, that the order type stays    |
//| valid and the BC-07 distances. The volume never changes; the     |
//| caller values the new risk and checks the caps (04 section 5).   |
//+------------------------------------------------------------------+
bool CPlanner::MovePending(const SOrder &o, const ELineRole role, const double dropped, const SQuote &q,
                           const SSymbolSpec &s, SOrder &moved, SResult &r)
  {
   r.Reset();
   moved = o;
   if(!CValidators::QuoteOk(q, s, r))
      return false;
   if(o.kind == KIND_MARKET)
      return RdFail(r, "Order " + RdTicketText(o.ticket) + " is not a pending order");
   if(!(dropped > 0.0))
      return RdFail(r, "Invalid price " + RdFormatPrice(s, dropped));

   double price = RdNormalizePrice(s, dropped);
   if(role == LINEROLE_ENTRY)
     {
      double delta = price - o.price;
      moved.price = price;
      if(o.sl > 0.0)
         moved.sl = RdNormalizePrice(s, o.sl + delta);
      if(o.tp > 0.0)
         moved.tp = RdNormalizePrice(s, o.tp + delta);
     }
   else
      if(role == LINEROLE_SL)
         moved.sl = price;
      else
         moved.tp = price;

   if(!CValidators::PendingNotFrozen(o.side, o.kind, o.price, q, s, r))
      return false;
   if(!CValidators::PendingGeometry(o.side, o.kind, moved.price, moved.sl, moved.tp, q, s, r))
      return false;
   if(!CValidators::PendingStops(o.side, o.kind, moved.price, moved.sl, moved.tp, q, s, r))
      return false;
   return RdOk(r, RdOrderText(o.side, o.kind) + " " + RdTicketText(o.ticket) + " @" + RdFormatPrice(s, moved.price) +
               " SL " + RdFormatPrice(s, moved.sl) + " TP " + RdFormatPrice(s, moved.tp));
  }

#endif // RD_DOMAIN_PLANNER_MQH
