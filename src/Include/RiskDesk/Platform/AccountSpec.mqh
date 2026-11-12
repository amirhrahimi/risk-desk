//+------------------------------------------------------------------+
//| RiskDesk - Platform/AccountSpec.mqh                              |
//| Layer   : Platform                                               |
//| Purpose : read account and terminal properties into SAccountSpec |
//|           (rule R3) and check trade permissions with the         |
//|           specific messages of BC-15. Cent detection: BC-12.     |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_ACCOUNTSPEC_MQH
#define RD_PLATFORM_ACCOUNTSPEC_MQH

#include "..\Domain\Types.mqh"
#include "Compat.mqh"

class CAccountSpec
  {
public:
   static bool       Read(SAccountSpec &a, SResult &r);
   // BC-15 terminal/EA/account checks, in the order of the table.
   // Symbol trade modes are checked per command (they depend on the side).
   static bool       CanTrade(SResult &why);
   // Right after a login (terminal started from a startup configuration,
   // account switched) the account properties arrive a moment after the
   // connection: balance 0, trade not allowed. Waits up to timeoutMs until
   // the terminal is connected and the account reports a currency and
   // either trading allowed or a balance. False on timeout (the caller
   // continues and reports what it sees).
   static bool       WaitReady(const int timeoutMs, int &waitedMs);
   static bool       IsCentCurrency(const string currency);
   static string     Describe(const SAccountSpec &a);
  };

//+------------------------------------------------------------------+
bool CAccountSpec::Read(SAccountSpec &a, SResult &r)
  {
   a.Reset();
   r.Reset();
   a.login                = AccountInfoInteger(ACCOUNT_LOGIN);
   a.currency             = AccountInfoString(ACCOUNT_CURRENCY);
   a.server               = AccountInfoString(ACCOUNT_SERVER);
   a.company              = AccountInfoString(ACCOUNT_COMPANY);
   a.balance              = AccountInfoDouble(ACCOUNT_BALANCE);
   a.equity               = AccountInfoDouble(ACCOUNT_EQUITY);
   a.freeMargin           = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   a.leverage             = AccountInfoInteger(ACCOUNT_LEVERAGE);
   a.marginMode           = RdAccountMarginMode();
   a.hedging              = RdIsHedgingMarginMode(a.marginMode);
   a.isCent               = IsCentCurrency(a.currency);
   a.isDemo               = RdIsDemoAccount();
   a.terminalConnected    = TerminalInfoInteger(TERMINAL_CONNECTED) != 0;
   a.terminalTradeAllowed = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0;
   a.eaTradeAllowed       = MQLInfoInteger(MQL_TRADE_ALLOWED) != 0;
   a.accountTradeAllowed  = AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0;
   a.accountExpertAllowed = AccountInfoInteger(ACCOUNT_TRADE_EXPERT) != 0;
   a.limitOrders          = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   a.digitsCcy            = RdAccountCurrencyDigits();

   if(a.login == 0)
      return RdFail(r, "Not logged in to a trade account");
   if(a.currency == "")
      return RdFail(r, "Broker reports no account currency");
   return RdOk(r, "Account OK");
  }

//+------------------------------------------------------------------+
bool CAccountSpec::CanTrade(SResult &why)
  {
   why.Reset();
   if(TerminalInfoInteger(TERMINAL_CONNECTED) == 0)
      return RdFail(why, "No connection to trade server");
   if(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == 0)
      return RdFail(why, "Algo/AutoTrading is off in the terminal toolbar");
   if(MQLInfoInteger(MQL_TRADE_ALLOWED) == 0)
      return RdFail(why, "Allow algo/live trading is unticked in RiskDesk's properties");
   if(AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) == 0)
      return RdFail(why, "Trading not allowed on this account (investor password?)");
   if(AccountInfoInteger(ACCOUNT_TRADE_EXPERT) == 0)
      return RdFail(why, "Broker disabled EA trading on this account");
   return RdOk(why, "Trading allowed");
  }

//+------------------------------------------------------------------+
bool CAccountSpec::WaitReady(const int timeoutMs, int &waitedMs)
  {
   uint start = GetTickCount();
   waitedMs = 0;
   while(!IsStopped())
     {
      bool ready = TerminalInfoInteger(TERMINAL_CONNECTED) != 0 &&
                   AccountInfoInteger(ACCOUNT_LOGIN) != 0 &&
                   AccountInfoString(ACCOUNT_CURRENCY) != "" &&
                   (AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) != 0 || AccountInfoDouble(ACCOUNT_BALANCE) > 0.0);
      waitedMs = (int)(GetTickCount() - start);
      if(ready)
         return true;
      if(waitedMs >= timeoutMs)
         return false;
      Sleep(250);
     }
   return false;
  }

//+------------------------------------------------------------------+
//| BC-12: USC/EUC/GBC/USc/EUc, or any currency containing "cent".   |
//+------------------------------------------------------------------+
bool CAccountSpec::IsCentCurrency(const string currency)
  {
   if(currency == "USC" || currency == "EUC" || currency == "GBC" || currency == "USc" || currency == "EUc")
      return true;
   string lower = currency;
   StringToLower(lower);
   return StringFind(lower, "cent") >= 0;
  }

//+------------------------------------------------------------------+
//| One line for the Experts tab.                                    |
//+------------------------------------------------------------------+
string CAccountSpec::Describe(const SAccountSpec &a)
  {
   return IntegerToString(a.login) + " on " + a.server + " (" + a.company + ")" +
          ", " + (a.isDemo ? "demo" : "NOT demo") +
          ", currency " + a.currency + (a.isCent ? " (cent)" : "") +
          ", leverage 1:" + IntegerToString(a.leverage) +
          ", margin mode " + RdMarginModeText(a.marginMode) +
          ", balance " + DoubleToString(a.balance, a.digitsCcy) +
          ", equity " + DoubleToString(a.equity, a.digitsCcy) +
          ", order limit " + (a.limitOrders > 0 ? IntegerToString(a.limitOrders) : "none");
  }

#endif // RD_PLATFORM_ACCOUNTSPEC_MQH
