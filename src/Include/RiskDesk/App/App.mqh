//+------------------------------------------------------------------+
//| RiskDesk - App/App.mqh                                           |
//| Layer   : App (composition root)                                 |
//| Purpose : creates and wires everything in OnInit and receives    |
//|           the five event handlers from the entry files           |
//|           (02-architecture sections 4 and 7).                    |
//| Status  : P0 shell. Init() logs version, platform, account and   |
//|           the chart symbol's spec; nothing else happens. Panel,  |
//|           timer and chart events arrive in phase P3.             |
//+------------------------------------------------------------------+
#ifndef RD_APP_APP_MQH
#define RD_APP_APP_MQH

#include "..\Build.mqh"

//--- Domain
#include "..\Domain\Types.mqh"
#include "..\Domain\PriceMath.mqh"
#include "..\Domain\RiskMath.mqh"
#include "..\Domain\Validators.mqh"
#include "..\Domain\Planner.mqh"
#include "..\Domain\RiskBudget.mqh"

//--- Platform
#include "..\Platform\Compat.mqh"
#include "..\Platform\SymbolSpec.mqh"
#include "..\Platform\AccountSpec.mqh"
#include "..\Platform\Market.mqh"
#include "..\Platform\Money.mqh"
#include "..\Platform\TradeGateway.mqh"
#include "..\Platform\History.mqh"

//--- Services
#include "..\Services\Logger.mqh"
#include "..\Services\Persistence.mqh"
#include "..\Services\Screenshot.mqh"
#include "..\Services\ChartHousekeeping.mqh"
#include "..\Services\CandleTime.mqh"

//--- UI
#include "..\UI\Theme.mqh"
#include "..\UI\Layout.mqh"
#include "..\UI\Widgets.mqh"
#include "..\UI\Panel.mqh"
#include "..\UI\Lines.mqh"
#include "..\UI\PendingOverlay.mqh"
#include "..\UI\StatusBar.mqh"

//--- App
#include "Inputs.mqh"
#include "Settings.mqh"
#include "State.mqh"
#include "Commands.mqh"
#include "Controller.mqh"

class CApp
  {
private:
   void              LogStartup();

public:
   int               Init();
   void              Deinit(const int reason);
   void              Tick() {}
   void              Timer() {}
   void              ChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {}
  };

//+------------------------------------------------------------------+
int CApp::Init()
  {
   CLogger::Configure(InpLogLevel, InpLogToFile && !RdIsTester(), RD_PRODUCT + " " + _Symbol);
   LogStartup();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void CApp::Deinit(const int reason)
  {
   RD_LOG_INFO(RD_PRODUCT + " stopped: " + RdDeinitReasonText(reason));
  }

//+------------------------------------------------------------------+
//| T-01: version, platform, account (currency, leverage, margin     |
//| mode) and the chart symbol's spec.                               |
//+------------------------------------------------------------------+
void CApp::LogStartup()
  {
   string build = "release build";
#ifdef RD_TEST_HOOKS
   build = "DEBUG build (test hooks on)";
#endif
   RD_LOG_INFO(RD_PRODUCT + " " + RD_VERSION + " starting: " + RD_PLATFORM +
               ", terminal build " + IntegerToString(RdTerminalBuild()) +
               ", " + build +
               ", chart " + _Symbol + " " + EnumToString((ENUM_TIMEFRAMES)_Period) +
               ", DPI " + IntegerToString(RdTerminalDpi()));

   SAccountSpec account;
   SResult accountResult;
   if(CAccountSpec::Read(account, accountResult))
      RD_LOG_INFO("Account " + CAccountSpec::Describe(account));
   else
      RD_LOG_WARN("Account: " + accountResult.message);

   SResult permission;
   if(CAccountSpec::CanTrade(permission))
      RD_LOG_INFO("Trade permissions: OK");
   else
      RD_LOG_WARN("Trade permissions: " + permission.message);

   SSymbolSpec spec;
   SResult specResult;
   bool specOk = CSymbolSpec::Read(_Symbol, spec, specResult);
   if(spec.digits > 0)
      RD_LOG_INFO("Symbol " + CSymbolSpec::Describe(spec, account.currency));
   if(!specOk)
      RD_LOG_ERROR(specResult.message);
   else
      if(specResult.sev == SEV_WARN)
         RD_LOG_WARN(specResult.message);
  }

#endif // RD_APP_APP_MQH
