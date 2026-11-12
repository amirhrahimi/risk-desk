//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGateway.mqh                             |
//| Layer   : Platform                                               |
//| Purpose : Single trade gateway (rule R6): every OrderSend,       |
//|           modify, close and delete goes through CTradeGateway.   |
//|           Selects the MT4 or MT5 implementation at compile       |
//|           time; both define the same class name and public       |
//|           methods (02 section 4, ADR-001).                       |
//| Status  : stub - implemented in phase P2.                        |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAY_MQH
#define RD_PLATFORM_TRADEGATEWAY_MQH

#include "..\Domain\Types.mqh"

// Compile-time selection: same class name, same public API (ADR-001).
#ifdef __MQL5__
   #include "TradeGatewayMT5.mqh"
#else
   #include "TradeGatewayMT4.mqh"
#endif

#endif // RD_PLATFORM_TRADEGATEWAY_MQH
