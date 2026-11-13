//+------------------------------------------------------------------+
//| RiskDesk - Services/ChartHousekeeping.mqh                        |
//| Layer   : Services                                               |
//| Purpose : keeps or removes MetaTrader's closed-trade objects     |
//|           (F-20, 05 section 6, Q12, Q16), input "Closed Trade    |
//|           History Objects":                                      |
//|           - CTO_REMOVE: on init, whenever the chart's object     |
//|             count changes (a trade closed, a deal dragged from   |
//|             the history) and every 5 s:                          |
//|             MT5 "Show trade history" (CHART_SHOW_TRADE_HISTORY)  |
//|             off; the user's value is kept in the hidden chart    |
//|             object RD_S_CTO and put back when RiskDesk leaves    |
//|             the chart or the input becomes Keep (as D20 does for |
//|             "Chart on foreground");                              |
//|             MT4 and MT5: objects named "#<ticket> ..." (arrows,  |
//|             trend lines) whose ticket is a closed trade of the   |
//|             chart's symbol in the account history are deleted.   |
//|           - CTO_KEEP: nothing is touched (only the saved "Show   |
//|             trade history" is given back once).                  |
//|           F-20 AC3: user drawings and other programs' objects    |
//|           never match (RdTradeObjectTicket + the history check). |
//|           RiskDesk's own orders are sent with arrow colour       |
//|           clrNONE, so they create no such objects.               |
//+------------------------------------------------------------------+
#ifndef RD_SERVICES_CHARTHOUSEKEEPING_MQH
#define RD_SERVICES_CHARTHOUSEKEEPING_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\Format.mqh"
#include "..\Platform\Compat.mqh"
#include "..\Platform\History.mqh"
#include "Logger.mqh"

#define RD_CTO_MEMO      "RD_S_CTO"   // the user's "Show trade history" (MT5) before RiskDesk switched it off
#define RD_CTO_SCAN_MS   5000

class CChartHousekeeping
  {
private:
   EClosedTradeObjects m_mode;
   int               m_objects;       // object count after the last scan, -1 = scan now
   uint              m_scanAt;
   int               m_removed;       // closed-trade objects removed in this run

   void              HistoryOff();
   void              HistoryRestore(const string why);

public:
                     CChartHousekeeping();
   void              Configure(const EClosedTradeObjects mode);
   // Every refresh. Scans only when forced, when the chart's object count
   // changed or 5 s passed; nothing at all with CTO_KEEP. Returns the
   // number of objects deleted (the caller redraws).
   int               Run(const bool force);
   // RiskDesk leaves the chart: the user's "Show trade history" back (MT5).
   void              Leave() { HistoryRestore("RiskDesk removed from the chart"); }
   int               Removed() const { return m_removed; }
   // F-20 AC1/AC3: one of MetaTrader's objects of a closed trade of this chart's symbol.
   static bool       IsClosedTradeObject(const string name);
  };

//+------------------------------------------------------------------+
CChartHousekeeping::CChartHousekeeping()
  {
   m_mode = CTO_KEEP;
   m_objects = -1;
   m_scanAt = 0;
   m_removed = 0;
  }

void CChartHousekeeping::Configure(const EClosedTradeObjects mode)
  {
   m_mode = mode;
   m_objects = -1;
   m_scanAt = 0;
   if(mode == CTO_KEEP)
      HistoryRestore("Closed Trade History Objects = Keep");
  }

//+------------------------------------------------------------------+
bool CChartHousekeeping::IsClosedTradeObject(const string name)
  {
   ulong ticket = 0;
   if(!RdTradeObjectTicket(name, ticket))
      return false;
   ENUM_OBJECT type = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
   if(type != OBJ_ARROW && type != OBJ_ARROW_BUY && type != OBJ_ARROW_SELL && type != OBJ_TREND)
      return false;
   return CHistory::IsClosedTradeOf(ticket, _Symbol);
  }

//+------------------------------------------------------------------+
int CChartHousekeeping::Run(const bool force)
  {
   if(m_mode != CTO_REMOVE)
      return 0;
   uint now = GetTickCount();
   int total = ObjectsTotal(0, -1, -1);
   if(!force && total == m_objects && m_scanAt != 0 && (uint)(now - m_scanAt) < RD_CTO_SCAN_MS)
      return 0;
   m_scanAt = now;
   HistoryOff();
   int deleted = 0;
   string first = "";
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringGetCharacter(name, 0) != '#' || !IsClosedTradeObject(name))
         continue;
      if(ObjectDelete(0, name))
        {
         deleted++;
         if(first == "")
            first = name;
        }
     }
   m_objects = ObjectsTotal(0, -1, -1);
   if(deleted > 0)
     {
      m_removed += deleted;
      RD_LOG_INFO("Closed-trade objects removed: " + IntegerToString(deleted) + " (\"" + first + "\"" +
                  (deleted > 1 ? " and others" : "") + "; Closed Trade History Objects = Remove)");
     }
   return deleted;
  }

//+------------------------------------------------------------------+
//| MT5: "Show trade history" off; the first time on this chart, the |
//| user's value goes into RD_S_CTO (kept with the chart, so a       |
//| terminal restart does not lose it). MT4: nothing to switch.      |
//+------------------------------------------------------------------+
void CChartHousekeeping::HistoryOff()
  {
   bool on = false;
   if(!RdChartTradeHistory(on))
      return;
   if(ObjectFind(0, RD_CTO_MEMO) < 0 && ObjectCreate(0, RD_CTO_MEMO, OBJ_LABEL, 0, 0, 0))
     {
      ObjectSetInteger(0, RD_CTO_MEMO, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, RD_CTO_MEMO, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, RD_CTO_MEMO, OBJPROP_TIMEFRAMES, RD_OBJ_NO_PERIODS);
      ObjectSetString(0, RD_CTO_MEMO, OBJPROP_TEXT, on ? "history=1" : "history=0");
     }
   if(!on)
      return;
   if(RdSetChartTradeHistory(false))
      RD_LOG_INFO("Show trade history switched off on this chart (Closed Trade History Objects = Remove); "
                  "it is switched on again when RiskDesk leaves the chart");
   else
      RD_LOG_WARN("Show trade history could not be switched off (error " + IntegerToString(GetLastError()) + ")");
  }

void CChartHousekeeping::HistoryRestore(const string why)
  {
   if(ObjectFind(0, RD_CTO_MEMO) < 0)
      return;
   bool was = (ObjectGetString(0, RD_CTO_MEMO, OBJPROP_TEXT) == "history=1");
   ObjectDelete(0, RD_CTO_MEMO);
   bool on = false;
   if(was && RdChartTradeHistory(on) && !on && RdSetChartTradeHistory(true))
      RD_LOG_INFO("Show trade history switched on again (" + why + ")");
  }

#endif // RD_SERVICES_CHARTHOUSEKEEPING_MQH
