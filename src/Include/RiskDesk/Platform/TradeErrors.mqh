// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeErrors.mqh                              |
//| Layer   : Platform (uses #ifdef __MQL5__, rule R2)               |
//| Purpose : the one place where broker answers become a handling   |
//|           class and a status-bar message (03 section 5, 02       |
//|           section 13): MT5 MqlTradeResult.retcode, MT4           |
//|           GetLastError() after a trade function.                 |
//|           The gateway (TradeGatewayMT4/MT5) acts on the class;   |
//|           the message is final English, suffixed by the gateway  |
//|           with the broker's comment where there is one.          |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEERRORS_MQH
#define RD_PLATFORM_TRADEERRORS_MQH

#include "..\Domain\Types.mqh"

// What the gateway does with an answer (03 section 5 "Class").
enum ETradeCodeClass
  {
   TCLASS_SUCCESS,          // done / placed
   TCLASS_PARTIAL,          // MT5 DONE_PARTIAL: success, amber
   TCLASS_NO_CHANGE,        // success for a modify ("Already set"), fatal otherwise
   TCLASS_ALREADY_CLOSED,   // success for a close, fatal otherwise
   TCLASS_RETRY,            // wait, refresh the price, retry (BC-13)
   TCLASS_RETRY_LONG,       // same with a longer wait (busy, too many requests)
   TCLASS_RETRY_ONCE,       // one retry with a fresh price
   TCLASS_RETRY_CONTEXT,    // MT4: wait for the trade context, retry
   TCLASS_RETRY_CONNECT,    // MT4: wait for the connection, retry
   TCLASS_AMBIGUOUS,        // may or may not have executed: check first (BC-14, rule R9)
   TCLASS_FIX_FILL,         // next filling policy (BC-06)
   TCLASS_FIX_EXPIRATION,   // next expiration rung (BC-08)
   TCLASS_FIX_STOPS,        // BC-11 for market opens, fatal otherwise
   TCLASS_FATAL             // stop with the message
  };

struct STradeCode
  {
   int               code;
   ETradeCodeClass   cls;
   string            name;      // constant name for the log ("INVALID_FILL", "ERR_INVALID_STOPS")
   string            message;   // status-bar text

   void              Set(const int c, const ETradeCodeClass k, const string n, const string m)
     {
      code = c;
      cls = k;
      name = n;
      message = m;
     }
  };

// Answer when the trade function failed without a usable code: treated
// as ambiguous (BC-14: "OrderSend returning false without a usable retcode").
void RdTradeCodeNoReply(STradeCode &tc)
  {
   tc.Set(0, TCLASS_AMBIGUOUS, "NO_REPLY", "No reply from the server - checking...");
  }

#ifdef __MQL5__
//+------------------------------------------------------------------+
//| MT5 trade server return codes (03 section 5, MT5 table).         |
//+------------------------------------------------------------------+
void RdTradeCode(const int code, STradeCode &tc)
  {
   switch(code)
     {
      case TRADE_RETCODE_PLACED:
         tc.Set(code, TCLASS_SUCCESS, "PLACED", "Pending placed");
         return;
      case TRADE_RETCODE_DONE:
         tc.Set(code, TCLASS_SUCCESS, "DONE", "Done");
         return;
      case TRADE_RETCODE_DONE_PARTIAL:
         tc.Set(code, TCLASS_PARTIAL, "DONE_PARTIAL", "Partially filled");
         return;
      case TRADE_RETCODE_REQUOTE:
         tc.Set(code, TCLASS_RETRY, "REQUOTE", "Requote");
         return;
      case TRADE_RETCODE_PRICE_CHANGED:
         tc.Set(code, TCLASS_RETRY, "PRICE_CHANGED", "Price changed");
         return;
      case TRADE_RETCODE_PRICE_OFF:
         tc.Set(code, TCLASS_RETRY, "PRICE_OFF", "No quotes");
         return;
      case TRADE_RETCODE_ORDER_CHANGED:
         tc.Set(code, TCLASS_RETRY, "ORDER_CHANGED", "Order state changed");
         return;
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
         tc.Set(code, TCLASS_RETRY_LONG, "TOO_MANY_REQUESTS", "Too many requests");
         return;
      case TRADE_RETCODE_LOCKED:
         tc.Set(code, TCLASS_RETRY, "LOCKED", "Order locked by dealer");
         return;
      case TRADE_RETCODE_ERROR:
         tc.Set(code, TCLASS_RETRY_ONCE, "ERROR", "Server error");
         return;
      case TRADE_RETCODE_TIMEOUT:
         tc.Set(code, TCLASS_AMBIGUOUS, "TIMEOUT", "Timeout - checking...");
         return;
      case TRADE_RETCODE_CONNECTION:
         tc.Set(code, TCLASS_AMBIGUOUS, "CONNECTION", "Connection lost - checking...");
         return;
      case TRADE_RETCODE_INVALID_FILL:
         tc.Set(code, TCLASS_FIX_FILL, "INVALID_FILL", "Filling policy rejected");
         return;
      case TRADE_RETCODE_INVALID_EXPIRATION:
         tc.Set(code, TCLASS_FIX_EXPIRATION, "INVALID_EXPIRATION", "Expiration rejected");
         return;
      case TRADE_RETCODE_INVALID_STOPS:
         tc.Set(code, TCLASS_FIX_STOPS, "INVALID_STOPS", "SL/TP too close or not allowed");
         return;
      case TRADE_RETCODE_INVALID_PRICE:
         tc.Set(code, TCLASS_RETRY_ONCE, "INVALID_PRICE", "Invalid price");
         return;
      case TRADE_RETCODE_NO_CHANGES:
         tc.Set(code, TCLASS_NO_CHANGE, "NO_CHANGES", "Already set");
         return;
      case TRADE_RETCODE_POSITION_CLOSED:
         tc.Set(code, TCLASS_ALREADY_CLOSED, "POSITION_CLOSED", "Already closed");
         return;
      case TRADE_RETCODE_REJECT:
         tc.Set(code, TCLASS_FATAL, "REJECT", "Rejected by broker");
         return;
      case TRADE_RETCODE_CANCEL:
         tc.Set(code, TCLASS_FATAL, "CANCEL", "Rejected by broker");
         return;
      case TRADE_RETCODE_INVALID:
         tc.Set(code, TCLASS_FATAL, "INVALID", "Invalid request (bug)");
         return;
      case TRADE_RETCODE_INVALID_VOLUME:
         tc.Set(code, TCLASS_FATAL, "INVALID_VOLUME", "Invalid volume");
         return;
      case TRADE_RETCODE_TRADE_DISABLED:
         tc.Set(code, TCLASS_FATAL, "TRADE_DISABLED", "Trading disabled for symbol");
         return;
      case TRADE_RETCODE_MARKET_CLOSED:
         tc.Set(code, TCLASS_FATAL, "MARKET_CLOSED", "Market closed");
         return;
      case TRADE_RETCODE_NO_MONEY:
         tc.Set(code, TCLASS_FATAL, "NO_MONEY", "Not enough margin");
         return;
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         tc.Set(code, TCLASS_FATAL, "SERVER_DISABLES_AT", "Algo trading disabled by server");
         return;
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
         tc.Set(code, TCLASS_FATAL, "CLIENT_DISABLES_AT", "Algo trading disabled by terminal");
         return;
      case TRADE_RETCODE_FROZEN:
         tc.Set(code, TCLASS_FATAL, "FROZEN", "Inside freeze level");
         return;
      case TRADE_RETCODE_LIMIT_ORDERS:
         tc.Set(code, TCLASS_FATAL, "LIMIT_ORDERS", "Order count limit reached");
         return;
      case TRADE_RETCODE_LIMIT_POSITIONS:
         tc.Set(code, TCLASS_FATAL, "LIMIT_POSITIONS", "Position count limit reached");
         return;
      case TRADE_RETCODE_LIMIT_VOLUME:
         tc.Set(code, TCLASS_FATAL, "LIMIT_VOLUME", "Volume limit for symbol reached (broker exposure cap)");
         return;
      case TRADE_RETCODE_LONG_ONLY:
         tc.Set(code, TCLASS_FATAL, "LONG_ONLY", "Symbol allows long only");
         return;
      case TRADE_RETCODE_SHORT_ONLY:
         tc.Set(code, TCLASS_FATAL, "SHORT_ONLY", "Symbol allows short only");
         return;
      case TRADE_RETCODE_CLOSE_ONLY:
         tc.Set(code, TCLASS_FATAL, "CLOSE_ONLY", "Symbol allows close only");
         return;
      case TRADE_RETCODE_FIFO_CLOSE:
         tc.Set(code, TCLASS_FATAL, "FIFO_CLOSE", "FIFO rule");
         return;
      case TRADE_RETCODE_HEDGE_PROHIBITED:
         tc.Set(code, TCLASS_FATAL, "HEDGE_PROHIBITED", "Hedging prohibited");
         return;
      //--- not in the 03 table: fatal with a readable text
      case TRADE_RETCODE_ONLY_REAL:
         tc.Set(code, TCLASS_FATAL, "ONLY_REAL", "Operation allowed on real accounts only");
         return;
      case TRADE_RETCODE_INVALID_ORDER:
         tc.Set(code, TCLASS_FATAL, "INVALID_ORDER", "Order type not allowed");
         return;
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME:
         tc.Set(code, TCLASS_FATAL, "INVALID_CLOSE_VOLUME", "Close volume exceeds the position");
         return;
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
         tc.Set(code, TCLASS_FATAL, "CLOSE_ORDER_EXIST", "A close order for this position is already pending");
         return;
      case TRADE_RETCODE_REJECT_CANCEL:
         tc.Set(code, TCLASS_FATAL, "REJECT_CANCEL", "Rejected by broker");
         return;
     }
   tc.Set(code, TCLASS_FATAL, "RETCODE_" + IntegerToString(code), "Server answered retcode " + IntegerToString(code));
  }

#else // MT4
//+------------------------------------------------------------------+
//| MT4 GetLastError() after OrderSend/Modify/Close/Delete           |
//| (03 section 5, MT4 table).                                       |
//+------------------------------------------------------------------+
void RdTradeCode(const int code, STradeCode &tc)
  {
   switch(code)
     {
      case ERR_NO_RESULT:
         tc.Set(code, TCLASS_NO_CHANGE, "ERR_NO_RESULT", "Already set");
         return;
      case ERR_PRICE_CHANGED:
         tc.Set(code, TCLASS_RETRY, "ERR_PRICE_CHANGED", "Price changed");
         return;
      case ERR_OFF_QUOTES:
         tc.Set(code, TCLASS_RETRY, "ERR_OFF_QUOTES", "No quotes");
         return;
      case ERR_REQUOTE:
         tc.Set(code, TCLASS_RETRY, "ERR_REQUOTE", "Requote");
         return;
      case ERR_SERVER_BUSY:
         tc.Set(code, TCLASS_RETRY_LONG, "ERR_SERVER_BUSY", "Server busy");
         return;
      case ERR_BROKER_BUSY:
         tc.Set(code, TCLASS_RETRY_LONG, "ERR_BROKER_BUSY", "Server busy");
         return;
      case ERR_TOO_MANY_REQUESTS:
         tc.Set(code, TCLASS_RETRY_LONG, "ERR_TOO_MANY_REQUESTS", "Server busy");
         return;
      case ERR_TOO_FREQUENT_REQUESTS:
         tc.Set(code, TCLASS_RETRY_LONG, "ERR_TOO_FREQUENT_REQUESTS", "Server busy");
         return;
      case ERR_TRADE_CONTEXT_BUSY:
         tc.Set(code, TCLASS_RETRY_CONTEXT, "ERR_TRADE_CONTEXT_BUSY", "Trade context busy");
         return;
      case ERR_NO_CONNECTION:
         tc.Set(code, TCLASS_RETRY_CONNECT, "ERR_NO_CONNECTION", "No connection");
         return;
      case ERR_TRADE_TIMEOUT:
         tc.Set(code, TCLASS_AMBIGUOUS, "ERR_TRADE_TIMEOUT", "Timeout - checking...");
         return;
      case ERR_INVALID_PRICE:
         tc.Set(code, TCLASS_RETRY_ONCE, "ERR_INVALID_PRICE", "Invalid price");
         return;
      case ERR_INVALID_STOPS:
         tc.Set(code, TCLASS_FIX_STOPS, "ERR_INVALID_STOPS", "SL/TP too close or not allowed");
         return;
      case ERR_TRADE_EXPIRATION_DENIED:
         tc.Set(code, TCLASS_FIX_EXPIRATION, "ERR_TRADE_EXPIRATION_DENIED", "Expiration not allowed");
         return;
      case ERR_INVALID_TRADE_VOLUME:
         tc.Set(code, TCLASS_FATAL, "ERR_INVALID_TRADE_VOLUME", "Invalid volume");
         return;
      case ERR_MARKET_CLOSED:
         tc.Set(code, TCLASS_FATAL, "ERR_MARKET_CLOSED", "Market closed");
         return;
      case ERR_TRADE_DISABLED:
         tc.Set(code, TCLASS_FATAL, "ERR_TRADE_DISABLED", "Trading disabled");
         return;
      case ERR_NOT_ENOUGH_MONEY:
         tc.Set(code, TCLASS_FATAL, "ERR_NOT_ENOUGH_MONEY", "Not enough margin");
         return;
      case ERR_ORDER_LOCKED:
         tc.Set(code, TCLASS_FATAL, "ERR_ORDER_LOCKED", "Order locked");
         return;
      case ERR_TRADE_MODIFY_DENIED:
         tc.Set(code, TCLASS_FATAL, "ERR_TRADE_MODIFY_DENIED", "Too close to market (freeze level)");
         return;
      case ERR_TRADE_TOO_MANY_ORDERS:
         tc.Set(code, TCLASS_FATAL, "ERR_TRADE_TOO_MANY_ORDERS", "Order count limit reached");
         return;
      case ERR_TRADE_HEDGE_PROHIBITED:
         tc.Set(code, TCLASS_FATAL, "ERR_TRADE_HEDGE_PROHIBITED", "Hedging prohibited");
         return;
      case ERR_TRADE_PROHIBITED_BY_FIFO:
         tc.Set(code, TCLASS_FATAL, "ERR_TRADE_PROHIBITED_BY_FIFO", "FIFO rule");
         return;
      case ERR_TRADE_NOT_ALLOWED:
         tc.Set(code, TCLASS_FATAL, "ERR_TRADE_NOT_ALLOWED", "Trading not allowed (check Algo/AutoTrading and EA properties)");
         return;
      case ERR_LONGS_NOT_ALLOWED:
         tc.Set(code, TCLASS_FATAL, "ERR_LONGS_NOT_ALLOWED", "Longs not allowed");
         return;
      case ERR_SHORTS_NOT_ALLOWED:
         tc.Set(code, TCLASS_FATAL, "ERR_SHORTS_NOT_ALLOWED", "Shorts not allowed");
         return;
      case ERR_ACCOUNT_DISABLED:
         tc.Set(code, TCLASS_FATAL, "ERR_ACCOUNT_DISABLED", "Account cannot trade");
         return;
      case ERR_INVALID_ACCOUNT:
         tc.Set(code, TCLASS_FATAL, "ERR_INVALID_ACCOUNT", "Account cannot trade");
         return;
      //--- not in the 03 table: fatal with a readable text
      case ERR_COMMON_ERROR:
         tc.Set(code, TCLASS_FATAL, "ERR_COMMON_ERROR", "Rejected by broker (common error)");
         return;
      case ERR_INVALID_TRADE_PARAMETERS:
         tc.Set(code, TCLASS_FATAL, "ERR_INVALID_TRADE_PARAMETERS", "Invalid request (bug)");
         return;
      case ERR_LONG_POSITIONS_ONLY_ALLOWED:
         tc.Set(code, TCLASS_FATAL, "ERR_LONG_POSITIONS_ONLY_ALLOWED", "Symbol allows long only");
         return;
      case ERR_INVALID_TICKET:
         tc.Set(code, TCLASS_FATAL, "ERR_INVALID_TICKET", "Ticket not found (closed or deleted?)");
         return;
      case ERR_INVALID_FUNCTION_PARAMVALUE:
         tc.Set(code, TCLASS_FATAL, "ERR_INVALID_FUNCTION_PARAMVALUE", "Invalid request (bug)");
         return;
      case ERR_UNKNOWN_SYMBOL:
         tc.Set(code, TCLASS_FATAL, "ERR_UNKNOWN_SYMBOL", "Unknown symbol");
         return;
      case ERR_INVALID_PRICE_PARAM:
         tc.Set(code, TCLASS_FATAL, "ERR_INVALID_PRICE_PARAM", "Invalid price (bug)");
         return;
     }
   tc.Set(code, TCLASS_FATAL, "ERROR_" + IntegerToString(code), "Trade error " + IntegerToString(code));
  }
#endif // __MQL5__

#endif // RD_PLATFORM_TRADEERRORS_MQH
