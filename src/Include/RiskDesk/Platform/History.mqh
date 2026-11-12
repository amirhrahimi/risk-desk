//+------------------------------------------------------------------+
//| RiskDesk - Platform/History.mqh                                  |
//| Layer   : Platform (uses #ifdef __MQL5__, rule R2)               |
//| Purpose : closed trades, for the realized P/L of close summaries |
//|           (OP-11/OP-12, phase P6) and a future history overlay.  |
//|           One record per exit: MT5 exit deals (DEAL_ENTRY_OUT /  |
//|           INOUT / OUT_BY; grouping by position is the caller's), |
//|           MT4 closed orders of the history pool.                 |
//| Status  : P2 minimal implementation (the roadmap allows a stub). |
//|           The gateway already reports the P/L of each close it   |
//|           makes (STradeOutcome.profit).                          |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_HISTORY_MQH
#define RD_PLATFORM_HISTORY_MQH

#include "..\Domain\Types.mqh"
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
   datetime          closeTime;
   long              magic;
  };

class CHistory
  {
public:
   // Exits since 'from' (server time) on 'symbol' ("" = every symbol), oldest first.
   static bool       ClosedTrades(const string symbol, const datetime from, SClosedTrade &arr[], SResult &r);
  };

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
      t.profit     = HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) +
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
