// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/History.mqh                                  |
//| Layer   : Platform (uses #ifdef __MQL5__, rule R2)               |
//| Purpose : - ClosedTrades: closed trades (one record per exit:    |
//|             MT5 exit deals DEAL_ENTRY_OUT / INOUT / OUT_BY,      |
//|             grouping by position is the caller's; MT4 closed     |
//|             orders of the history pool), for checks of close     |
//|             summaries and a future history overlay. The close    |
//|             commands (OP-10..OP-12) take the P/L of each close   |
//|             from the gateway (STradeOutcome.profit).             |
//|           - BookedCost: commission + swap already booked on an   |
//|             open position, for Risk Free RF_COMMISSION (04       |
//|             section 9; P6). MT5 sums the commission and fee of   |
//|             the position's deals (POSITION_COMMISSION is not     |
//|             filled by MT5); MT4 reads OrderCommission/OrderSwap. |
//|           - IsClosedTradeOf: is a "#ticket ..." chart object one  |
//|             of MetaTrader's closed-trade objects (F-20)?         |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_HISTORY_MQH
#define RD_PLATFORM_HISTORY_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "Compat.mqh"

// One exit: the closed part of a position.
struct SClosedTrade
  {
   ulong             ticket;       // MT5 position id, MT4 order ticket
   string            symbol;
   ESide             side;         // side of the position that was closed
   double            volume;       // volume closed
   double            closePrice;
   double            profit;       // profit + swap + commission (+ MT5 fee) of this exit
   double            grossProfit;  // the price move alone (DEAL_PROFIT / OrderProfit)
   datetime          closeTime;
   long              magic;
  };

class CHistory
  {
public:
   // Exits since 'from' (server time) on 'symbol' ("" = every symbol), oldest first.
   static bool       ClosedTrades(const string symbol, const datetime from, SClosedTrade &arr[], SResult &r);
   // Commission + swap (+ MT5 fee) booked so far on open position 'ticket', as a cost:
   // > 0 = charged; a net credit is 0 (D10). False when the position is not open.
   static bool       BookedCost(const ulong ticket, double &cost, SResult &r);
   // F-20: 'ticket' (from a "#ticket ..." object name) is a closed trade of 'symbol'
   // in this account's history: MT4 a closed or deleted order; MT5 a deal or an
   // order of the history (the terminal's objects carry either ticket). Changes the
   // selected order (MT4) / the history selection (MT5).
   static bool       IsClosedTradeOf(const ulong ticket, const string symbol);
  };

//+------------------------------------------------------------------+
bool CHistory::IsClosedTradeOf(const ulong ticket, const string symbol)
  {
   if(ticket == 0)
      return false;
#ifdef __MQL5__
   if(HistoryDealSelect(ticket))
      return HistoryDealGetString(ticket, DEAL_SYMBOL) == symbol;
   if(HistoryOrderSelect(ticket))
      return HistoryOrderGetString(ticket, ORDER_SYMBOL) == symbol;
   return false;
#else
   if(ticket > (ulong)INT_MAX || !OrderSelect((int)ticket, SELECT_BY_TICKET))
      return false;
   return OrderCloseTime() > 0 && OrderSymbol() == symbol;
#endif
  }

//+------------------------------------------------------------------+
bool CHistory::BookedCost(const ulong ticket, double &cost, SResult &r)
  {
   r.Reset();
   cost = 0.0;
   double booked = 0.0;   // as the terminal shows it: negative = charged
#ifdef __MQL5__
   if(!PositionSelectByTicket(ticket))
      return RdFail(r, "Position " + RdTicketText(ticket) + " not found (closed?)");
   booked = PositionGetDouble(POSITION_SWAP);
   long id = PositionGetInteger(POSITION_IDENTIFIER);
   if(!HistorySelectByPosition(id))
      return RdFail(r, "Trade history of position " + RdTicketText(ticket) + " not available");
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal > 0)
         booked += HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
     }
#else
   if(!OrderSelect((int)ticket, SELECT_BY_TICKET) || OrderCloseTime() > 0 || OrderType() > OP_SELL)
      return RdFail(r, "Position " + RdTicketText(ticket) + " not found (closed?)");
   booked = OrderCommission() + OrderSwap();
#endif
   if(!MathIsValidNumber(booked))
      return RdFail(r, "Booked costs of " + RdTicketText(ticket) + " are not a number");
   cost = MathMax(0.0, -booked);
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
bool CHistory::ClosedTrades(const string symbol, const datetime from, SClosedTrade &arr[], SResult &r)
  {
   r.Reset();
   ArrayResize(arr, 0);
#ifdef __MQL5__
   if(!HistorySelect(from, RdServerTime() + 86400))
      return RdFail(r, "Trade history not available");
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;
      string sym = HistoryDealGetString(deal, DEAL_SYMBOL);
      if(symbol != "" && sym != symbol)
         continue;
      SClosedTrade t;
      t.ticket     = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      t.symbol     = sym;
      t.side       = (type == DEAL_TYPE_SELL) ? SIDE_BUY : SIDE_SELL;   // a sell deal closes a buy
      t.volume     = HistoryDealGetDouble(deal, DEAL_VOLUME);
      t.closePrice = HistoryDealGetDouble(deal, DEAL_PRICE);
      t.grossProfit = HistoryDealGetDouble(deal, DEAL_PROFIT);
      t.profit     = t.grossProfit + HistoryDealGetDouble(deal, DEAL_SWAP) +
                     HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      t.closeTime  = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      t.magic      = HistoryDealGetInteger(deal, DEAL_MAGIC);
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = t;
     }
#else
   int total = OrdersHistoryTotal();
   for(int i = 0; i < total; i++)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;
      if(OrderType() > OP_SELL || OrderCloseTime() < from)
         continue;
      if(symbol != "" && OrderSymbol() != symbol)
         continue;
      SClosedTrade t;
      t.ticket     = (ulong)OrderTicket();
      t.symbol     = OrderSymbol();
      t.side       = (OrderType() == OP_BUY) ? SIDE_BUY : SIDE_SELL;
      t.volume     = OrderLots();
      t.closePrice = OrderClosePrice();
      t.grossProfit = OrderProfit();
      t.profit     = OrderProfit() + OrderSwap() + OrderCommission();
      t.closeTime  = OrderCloseTime();
      t.magic      = OrderMagicNumber();
      int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = t;
     }
#endif
   return RdOk(r, IntegerToString(ArraySize(arr)) + " closed trade(s)");
  }

#endif // RD_PLATFORM_HISTORY_MQH
