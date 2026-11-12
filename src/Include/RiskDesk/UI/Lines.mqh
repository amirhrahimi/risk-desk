//+------------------------------------------------------------------+
//| RiskDesk - UI/Lines.mqh                                          |
//| Layer   : UI                                                     |
//| Purpose : Creates, adopts and deletes the SL/TP/Entry planning   |
//|           lines and their labels; reads their prices.            |
//| Status  : P3 has only DeleteAll (a symbol change removes the     |
//|           lines of the old symbol, F-23 AC2). Market and pending |
//|           lines are implemented in phase P4, P5.                 |
//+------------------------------------------------------------------+
#ifndef RD_UI_LINES_MQH
#define RD_UI_LINES_MQH

#include "..\Domain\Types.mqh"
#include "Widgets.mqh"

#define RD_LINE_PREFIX        "RD_LN_"   // RD_LN_SL, RD_LN_TP, RD_LN_EN
#define RD_LINE_LABEL_PREFIX  "RD_LT_"   // RD_LT_SL, RD_LT_TP, RD_LT_EN

class CLines
  {
public:
   // Planning lines and their labels. Returns the number of objects deleted.
   static int        DeleteAll()
     {
      return RdDeleteObjects(RD_LINE_PREFIX) + RdDeleteObjects(RD_LINE_LABEL_PREFIX);
     }
  };

#endif // RD_UI_LINES_MQH
