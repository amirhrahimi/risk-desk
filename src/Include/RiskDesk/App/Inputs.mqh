//+------------------------------------------------------------------+
//| RiskDesk - App/Inputs.mqh                                        |
//| Layer   : App (the only App file allowed to use #ifdef           |
//|           __MQL5__, rule R2: MQL5 has input groups, MQL4 uses    |
//|           sinput separators)                                     |
//| Purpose : every input of the EA (07-settings).                   |
//| Status  : P0 declares the Diagnostics group only. The full list  |
//|           from 07-settings is added in phase P3.                 |
//+------------------------------------------------------------------+
#ifndef RD_APP_INPUTS_MQH
#define RD_APP_INPUTS_MQH

#include "..\Domain\Types.mqh"

//--- Diagnostics
#ifdef __MQL5__
input group "Diagnostics"
#else
sinput string InpSep_Diagnostics = "==== Diagnostics ====";   // ==== Diagnostics ====
#endif
input ELogLevel InpLogLevel  = LOGLEVEL_INFO;   // Log level
input bool      InpLogToFile = true;            // Mirror the log to Files/RiskDesk/Logs

#endif // RD_APP_INPUTS_MQH
