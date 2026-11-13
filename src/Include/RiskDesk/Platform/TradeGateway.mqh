// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGateway.mqh                             |
//| Layer   : Platform                                               |
//| Purpose : Single trade gateway (rule R6): every OrderSend,       |
//|           modify, close and delete goes through CTradeGateway.   |
//|           Selects the MT4 or MT5 implementation at compile       |
//|           time; both define the same class name and public       |
//|           methods (02 section 4, ADR-001):                       |
//|             Configure(SGatewaySettings)                          |
//|             OpenMarket          G-01   PlacePending      G-02    |
//|             ModifyPositionSLTP  G-03   ClosePosition     G-04    |
//|             DeletePending       G-05   ListPositions     G-06    |
//|             ListPending         G-07   ModifyPending     G-08    |
//|             SelectPosition, SelectPending, IsHedging,            |
//|             NeedsModifyAfter, Magic                              |
//|           Shared, platform-neutral part: TradeGatewayBase.mqh.   |
//|           Broker answers -> class + message: TradeErrors.mqh.    |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAY_MQH
#define RD_PLATFORM_TRADEGATEWAY_MQH

#include "TradeGatewayBase.mqh"

// Compile-time selection: same class name, same public API (ADR-001).
#ifdef __MQL5__
   #include "TradeGatewayMT5.mqh"
#else
   #include "TradeGatewayMT4.mqh"
#endif

#endif // RD_PLATFORM_TRADEGATEWAY_MQH
