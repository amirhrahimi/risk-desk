// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Domain/RiskBudget.mqh                                 |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : open risk of the tool's trades and the risk caps       |
//|           (F-16, F-29, 04-risk-engine section 5).                |
//|                                                                  |
//| Platform lists positions/orders and fills each item's lossToSl   |
//| (LossPerLot x volume + commission x volume, a finite number);    |
//| this module sums and decides:                                    |
//|   1. OpenRisk(positions, orders)       -> bud.openRisk           |
//|   2. Check(openRisk, removed, added, trade)                      |
//|        trade: risk of this trade alone       (per-trade cap)     |
//|        total = openRisk - removed + added    (total cap)         |
//|      new trade          : removed 0, added = trade               |
//|      netting same side  : removed = old position's contribution, |
//|                           added = post-trade position (BC-10)    |
//|      moved tool order   : removed = its old risk, added = new    |
//|      moved other order  : CheckPerTrade only                     |
//|   3. CheckMove: the OP-16 decision for a moved order (both rows  |
//|      above, and a move that does not raise the order's risk is  |
//|      always allowed); MoveNeedsOpenRisk says when the caller     |
//|      must list the open risk first.                              |
//| Equality at a cap is allowed.                                    |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_RISKBUDGET_MQH
#define RD_DOMAIN_RISKBUDGET_MQH

#include "Types.mqh"
#include "PriceMath.mqh"
#include "Format.mqh"
#include "RiskMath.mqh"

struct SBudgetResult
  {
   double            base;
   double            openRisk;        // tool positions + tool pending orders now
   double            removedRisk;     // contribution replaced by this action
   double            addedRisk;       // contribution after this action
   double            tradeRisk;       // this trade alone
   double            totalRisk;       // openRisk - removedRisk + addedRisk
   double            openPct;
   double            tradePct;
   double            totalPct;
   int               positions;       // tool positions counted
   int               orders;          // tool pending orders counted

   void              Reset()
     {
      base = 0.0;
      openRisk = 0.0;
      removedRisk = 0.0;
      addedRisk = 0.0;
      tradeRisk = 0.0;
      totalRisk = 0.0;
      openPct = 0.0;
      tradePct = 0.0;
      totalPct = 0.0;
      positions = 0;
      orders = 0;
     }
  };

class CRiskBudget
  {
public:
   static bool       OpenRisk(const SPosition &positions[], const SOrder &orders[], const SPlanSettings &cfg,
                              SBudgetResult &bud, SResult &r);
   static bool       CheckPerTrade(const SAccountSpec &acc, const SPlanSettings &cfg, const double tradeRisk,
                                   SBudgetResult &bud, SResult &r);
   static bool       Check(const SAccountSpec &acc, const SPlanSettings &cfg, const double openRisk,
                           const double removedRisk, const double addedRisk, const double tradeRisk,
                           SBudgetResult &bud, SResult &r);
   static bool       MoveNeedsOpenRisk(const bool counted, const double oldRisk, const double newRisk);
   static bool       CheckMove(const SAccountSpec &acc, const SPlanSettings &cfg, const bool counted,
                               const double openRisk, const double oldRisk, const double newRisk,
                               SBudgetResult &bud, SResult &r);
   static string     Readout(const SAccountSpec &acc, const SPlanSettings &cfg, const double openRisk,
                             ESeverity &sev);
  };

#define RD_BUDGET_MONEY_EPS  1e-9   // a move "raises" the risk only by more than this

//+------------------------------------------------------------------+
//| Sum over tool positions of max(0, lossToSl) (at or beyond break- |
//| even counts 0), plus tool pending orders when                    |
//| includePendingInTotalRisk. A tool item without SL makes the      |
//| total unknown -> false, naming the ticket.                       |
//+------------------------------------------------------------------+
bool CRiskBudget::OpenRisk(const SPosition &positions[], const SOrder &orders[], const SPlanSettings &cfg,
                           SBudgetResult &bud, SResult &r)
  {
   bud.Reset();
   r.Reset();
   double total = 0.0;

   int n = ArraySize(positions);
   for(int i = 0; i < n; i++)
     {
      if(positions[i].magic != cfg.magic)
         continue;
      string what = "Position " + RdTicketText(positions[i].ticket) + " (" + positions[i].symbol + ")";
      if(!(positions[i].sl > 0.0))
         return RdFail(r, what + " has no SL - total risk cannot be computed");
      if(!MathIsValidNumber(positions[i].lossToSl))
         return RdFail(r, what + ": its risk cannot be valued - total risk cannot be computed");
      total += MathMax(0.0, positions[i].lossToSl);
      bud.positions++;
     }

   if(cfg.includePendingInTotalRisk)
     {
      int m = ArraySize(orders);
      for(int j = 0; j < m; j++)
        {
         if(orders[j].magic != cfg.magic || orders[j].kind == KIND_MARKET)
            continue;
         string what = "Pending order " + RdTicketText(orders[j].ticket) + " (" + orders[j].symbol + ")";
         if(!(orders[j].sl > 0.0))
            return RdFail(r, what + " has no SL - total risk cannot be computed");
         if(!MathIsValidNumber(orders[j].lossToSl))
            return RdFail(r, what + ": its risk cannot be valued - total risk cannot be computed");
         total += MathMax(0.0, orders[j].lossToSl);
         bud.orders++;
        }
     }

   bud.openRisk = total;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| Per-trade cap only (F-16 AC1); fills bud.base/tradeRisk/tradePct.|
//+------------------------------------------------------------------+
bool CRiskBudget::CheckPerTrade(const SAccountSpec &acc, const SPlanSettings &cfg, const double tradeRisk,
                                SBudgetResult &bud, SResult &r)
  {
   r.Reset();
   bud.base = CRiskMath::RiskBase(cfg.riskBase, acc.balance, acc.equity);
   if(!MathIsValidNumber(bud.base) || bud.base <= 0.0)
      return RdFail(r, "Risk base is " + RdMoney(acc, bud.base) + " - risk caps cannot be checked");
   if(!MathIsValidNumber(tradeRisk))
      return RdFail(r, "The risk of this trade cannot be valued");
   bud.tradeRisk = MathMax(0.0, tradeRisk);
   bud.tradePct = bud.tradeRisk / bud.base * 100.0;
   if(bud.tradePct > cfg.maxRiskPerTradePct + RD_PCT_EPS)
      return RdFail(r, "Risk " + RdFormatPct(bud.tradePct) + " (" + RdMoney(acc, bud.tradeRisk) +
                    ") is above the " + RdFormatCapPct(cfg.maxRiskPerTradePct) + " per-trade cap");
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| F-16 AC1 + AC2: per-trade cap, then                              |
//| (openRisk - removedRisk + addedRisk) / base x 100 <= total cap.  |
//+------------------------------------------------------------------+
bool CRiskBudget::Check(const SAccountSpec &acc, const SPlanSettings &cfg, const double openRisk,
                        const double removedRisk, const double addedRisk, const double tradeRisk,
                        SBudgetResult &bud, SResult &r)
  {
   if(!CheckPerTrade(acc, cfg, tradeRisk, bud, r))
      return false;
   if(!MathIsValidNumber(openRisk) || !MathIsValidNumber(removedRisk) || !MathIsValidNumber(addedRisk))
      return RdFail(r, "Open risk cannot be valued - total risk cannot be checked");

   bud.openRisk = MathMax(0.0, openRisk);
   bud.removedRisk = MathMin(MathMax(0.0, removedRisk), bud.openRisk);
   bud.addedRisk = MathMax(0.0, addedRisk);
   bud.totalRisk = bud.openRisk - bud.removedRisk + bud.addedRisk;
   bud.openPct = bud.openRisk / bud.base * 100.0;
   bud.totalPct = bud.totalRisk / bud.base * 100.0;

   if(bud.totalPct > cfg.maxTotalRiskPct + RD_PCT_EPS)
     {
      string sum = "open " + RdFormatPct(bud.openPct);
      if(bud.removedRisk > 0.0)
         sum += " - " + RdFormatPct(bud.removedRisk / bud.base * 100.0);
      sum += " + " + RdFormatPct(bud.addedRisk / bud.base * 100.0);
      return RdFail(r, "Total risk too high: " + sum + " > " + RdFormatCapPct(cfg.maxTotalRiskPct) +
                    " cap (would be " + RdFormatPct(bud.totalPct) + ", " + RdMoney(acc, bud.totalRisk) + ")");
     }
   return RdOk(r, "Open risk after this trade " + RdFormatPct(bud.totalPct) + " / " +
               RdFormatCapPct(cfg.maxTotalRiskPct));
  }

//+------------------------------------------------------------------+
//| OP-16: is the open risk of the account needed to judge the move? |
//| Only when the order counts towards it (a RiskDesk order with     |
//| InpIncludePendingInTotalRisk) and the move raises its risk.      |
//+------------------------------------------------------------------+
bool CRiskBudget::MoveNeedsOpenRisk(const bool counted, const double oldRisk, const double newRisk)
  {
   if(!MathIsValidNumber(oldRisk) || !MathIsValidNumber(newRisk))
      return counted;
   return counted && newRisk > oldRisk + RD_BUDGET_MONEY_EPS;
  }

//+------------------------------------------------------------------+
//| OP-16 / 04 section 5: a placed order is moved, its lot unchanged.|
//|   new risk <= old risk  -> allowed (no total can grow); the       |
//|                            per-trade cap is not applied, so an   |
//|                            order above it can still be tightened |
//|   counted order         -> per-trade cap on the new risk, then   |
//|                            total with the old risk replaced      |
//|   other order           -> per-trade cap only (manual orders and |
//|                            other EAs' are not in the open risk)  |
//| counted: the order is in 'openRisk' (tool order, pending orders  |
//| counted). openRisk is used only when MoveNeedsOpenRisk().        |
//+------------------------------------------------------------------+
bool CRiskBudget::CheckMove(const SAccountSpec &acc, const SPlanSettings &cfg, const bool counted,
                            const double openRisk, const double oldRisk, const double newRisk,
                            SBudgetResult &bud, SResult &r)
  {
   bud.Reset();
   r.Reset();
   if(!MathIsValidNumber(newRisk))
      return RdFail(r, "The risk of the moved order cannot be valued");
   if(MathIsValidNumber(oldRisk) && newRisk <= oldRisk + RD_BUDGET_MONEY_EPS)
     {
      bud.base = CRiskMath::RiskBase(cfg.riskBase, acc.balance, acc.equity);
      bud.tradeRisk = MathMax(0.0, newRisk);
      bud.tradePct = (bud.base > 0.0) ? bud.tradeRisk / bud.base * 100.0 : 0.0;
      return RdOk(r, "Risk not raised by the move");
     }
   if(!counted)
     {
      if(!CheckPerTrade(acc, cfg, newRisk, bud, r))
         return false;
      return RdOk(r, "Per-trade cap only (the order does not count towards the open risk)");
     }
   // an old risk that cannot be valued replaces nothing: checked like a new order
   double removed = MathIsValidNumber(oldRisk) ? oldRisk : 0.0;
   return Check(acc, cfg, openRisk, removed, newRisk, newRisk, bud, r);
  }

//+------------------------------------------------------------------+
//| F-29 idle readout "Open risk 3.20 % / 10 %"; SEV_WARN above 75 % |
//| of the cap.                                                      |
//+------------------------------------------------------------------+
string CRiskBudget::Readout(const SAccountSpec &acc, const SPlanSettings &cfg, const double openRisk,
                            ESeverity &sev)
  {
   sev = SEV_OK;
   double base = CRiskMath::RiskBase(cfg.riskBase, acc.balance, acc.equity);
   if(!MathIsValidNumber(base) || base <= 0.0 || !MathIsValidNumber(openRisk))
     {
      sev = SEV_WARN;
      return "Open risk n/a";
     }
   double pct = MathMax(0.0, openRisk) / base * 100.0;
   if(pct > 0.75 * cfg.maxTotalRiskPct + RD_PCT_EPS)
      sev = SEV_WARN;
   return "Open risk " + RdFormatPct(pct) + " / " + RdFormatCapPct(cfg.maxTotalRiskPct);
  }

#endif // RD_DOMAIN_RISKBUDGET_MQH
