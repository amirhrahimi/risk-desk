//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/BrokerProbeCore.mqh                  |
//| Layer   : diagnostics script (shared body of BrokerProbe.mq4 and |
//|           BrokerProbe.mq5, F-27, 08-testing section 3)           |
//| Purpose : writes Files/RiskDesk/probe_<company>_<platform>_      |
//|           <login>_<yyyymmdd>.txt: terminal, account and symbol   |
//|           properties, value/margin calculations and (MT5)        |
//|           OrderCheck results, as plain 'key: value' text that    |
//|           diffs well in git.                                     |
//|                                                                  |
//| NOTHING IS EVER EXECUTED: no OrderSend anywhere. MT5 checks use  |
//| OrderCheck, which only validates a request.                      |
//|                                                                  |
//| This file is platform-neutral (no #ifdef). What differs between  |
//| MT4 and MT5 lives in Platform/ or in the three hooks below, which|
//| each entry file defines:                                         |
//|   ProbePlatformAccount, ProbePlatformSymbol, ProbePlatformChecks |
//+------------------------------------------------------------------+
#ifndef RD_SCRIPTS_BROKERPROBECORE_MQH
#define RD_SCRIPTS_BROKERPROBECORE_MQH

#include "..\..\Include\RiskDesk\Build.mqh"
#include "..\..\Include\RiskDesk\Domain\Types.mqh"
#include "..\..\Include\RiskDesk\Services\Logger.mqh"
#include "..\..\Include\RiskDesk\Platform\Compat.mqh"
#include "..\..\Include\RiskDesk\Platform\SymbolSpec.mqh"
#include "..\..\Include\RiskDesk\Platform\AccountSpec.mqh"
#include "..\..\Include\RiskDesk\Platform\Market.mqh"
#include "..\..\Include\RiskDesk\Platform\Money.mqh"

input string InpExtraSymbols       = "";     // Extra symbols, comma separated (broker's exact names)
input bool   InpIncludeMarketWatch = true;   // Probe every Market Watch symbol
input bool   InpFindTestSymbols    = true;   // Find the test-matrix instruments (EURUSD ... BTCUSD)
input int    InpMaxSymbols         = 150;    // Maximum number of symbols in one report

#define RD_PROBE_FORMAT        "1"
#define RD_PROBE_KEY_WIDTH     24
#define RD_PROBE_TICKS         100      // loss calculations use a move of this many ticks
#define RD_PROBE_MISMATCH_PCT  5.0      // BC-05 cross-check threshold
#define RD_PROBE_CANDIDATES    3        // candidates listed per test instrument
#define RD_PROBE_QUOTE_WAIT_MS 2000     // wait for quotes of symbols added to Market Watch

//+------------------------------------------------------------------+
//| Report writer: UTF-8 text, CRLF line ends.                       |
//+------------------------------------------------------------------+
class CProbeWriter
  {
private:
   int               m_handle;

public:
                     CProbeWriter() : m_handle(INVALID_HANDLE) {}
                    ~CProbeWriter() { Close(); }

   bool              Open(const string relativePath, int &error)
     {
      ResetLastError();
      m_handle = FileOpen(relativePath, FILE_WRITE | FILE_TXT | FILE_ANSI, '\t', CP_UTF8);
      error = GetLastError();
      return m_handle != INVALID_HANDLE;
     }
   void              Close()
     {
      if(m_handle != INVALID_HANDLE)
         FileClose(m_handle);
      m_handle = INVALID_HANDLE;
     }
   void              Raw(const string text)
     {
      if(m_handle != INVALID_HANDLE)
         FileWriteString(m_handle, text + "\r\n");
     }
   void              Comment(const string text)                    { Raw("# " + text); }
   void              Section(const string title)                   { Raw(""); Raw("[" + title + "]"); }
   void              Kv(const string key, const string value)      { Raw("  " + RdPadRight(key + ":", RD_PROBE_KEY_WIDTH) + " " + value); }
   void              Group(const string title)                     { Raw("  " + title + ":"); }
   void              Kv2(const string key, const string value)     { Raw("    " + RdPadRight(key + ":", RD_PROBE_KEY_WIDTH - 2) + " " + value); }
  };

//--- Hooks that BrokerProbe.mq4 and BrokerProbe.mq5 must each define (MQL
//--- resolves them at compile time; a bodiless prototype would be read by
//--- the MT4 compiler as a DLL import, warning 46):
//---   void ProbePlatformAccount(CProbeWriter &w);
//---   void ProbePlatformSymbol(CProbeWriter &w, const SSymbolSpec &s, const SAccountSpec &a);
//---   void ProbePlatformChecks(CProbeWriter &w, const SSymbolSpec &s, const SQuote &q,
//---                            const bool hasQuote, const SAccountSpec &a);

//====================================================================
// Small helpers
//====================================================================
void ProbeAdd(string &list[], const string value)
  {
   int n = ArraySize(list);
   ArrayResize(list, n + 1);
   list[n] = value;
  }

bool ProbeContains(const string &list[], const string value)
  {
   int n = ArraySize(list);
   for(int i = 0; i < n; i++)
      if(list[i] == value)
         return true;
   return false;
  }

void ProbeAddUnique(string &list[], const string value)
  {
   if(value != "" && !ProbeContains(list, value))
      ProbeAdd(list, value);
  }

string ProbeUpper(const string text)
  {
   string s = text;
   StringToUpper(s);
   return s;
  }

// Keep letters and digits only: "IC Markets (EU) Ltd" -> "ICMarketsEULtd".
string ProbeSanitize(const string text)
  {
   string out = "";
   int n = StringLen(text);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(text, i);
      if((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
         out += ShortToString(c);
     }
   return out == "" ? "unknown" : out;
  }

string ProbeTime(const datetime t)
  {
   if(t <= 0)
      return "none";
   return TimeToString(t, TIME_DATE | TIME_SECONDS);
  }

string ProbeHm(const long seconds)
  {
   int h = (int)(seconds / 3600);
   int m = (int)((seconds % 3600) / 60);
   return StringFormat("%02d:%02d", h, m);
  }

string ProbeDayName(const int dayOfWeek)
  {
   string names[] = {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"};
   if(dayOfWeek < 0 || dayOfWeek > 6)
      return "?";
   return names[dayOfWeek];
  }

bool ProbeInMarketWatch(const string symbol)
  {
   return SymbolInfoInteger(symbol, SYMBOL_SELECT) != 0;
  }

string ProbeMoney(const double value, const string currency)
  {
   return RdNum(value, 4) + " " + currency;
  }

string ProbePct(const double value)
  {
   return DoubleToString(value, 2) + " %";
  }

// Trade sessions of the server's current weekday (from the last quote time).
string ProbeSessionsToday(const string symbol)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string out = "";
   datetime from = 0;
   datetime to = 0;
   for(uint i = 0; i < 16; i++)
     {
      if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
         break;
      out = RdJoin(out, ProbeHm((long)from) + "-" + ProbeHm((long)to), ", ");
     }
   if(out == "")
      out = "none";
   return out + " (" + ProbeDayName(dt.day_of_week) + ", server time)";
  }

// Test-matrix discovery (08-testing section 4, ADR-017)
#include "BrokerProbeDiscovery.mqh"

//====================================================================
// Report sections
//====================================================================
void ProbeTerminal(CProbeWriter &w)
  {
   w.Section("terminal");
   w.Kv("name", TerminalInfoString(TERMINAL_NAME));
   w.Kv("company", TerminalInfoString(TERMINAL_COMPANY));
   w.Kv("build", IntegerToString(RdTerminalBuild()));
   w.Kv("platform", RD_PLATFORM);
   w.Kv("dpi", IntegerToString(RdTerminalDpi()));
   w.Kv("connected", RdBoolText(TerminalInfoInteger(TERMINAL_CONNECTED) != 0));
   w.Kv("trade_allowed", RdBoolText(TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) != 0) + "  (Algo/AutoTrading toolbar button)");
   w.Kv("mql_trade_allowed", RdBoolText(MQLInfoInteger(MQL_TRADE_ALLOWED) != 0) + "  (this script's 'Allow algo trading')");
   w.Kv("community", RdBoolText(TerminalInfoInteger(TERMINAL_COMMUNITY_ACCOUNT) != 0));
   w.Kv("data_path", TerminalInfoString(TERMINAL_DATA_PATH));
  }

void ProbeTimes(CProbeWriter &w)
  {
   w.Section("time");
   datetime server = TimeCurrent();
   datetime gmt = TimeGMT();
   w.Kv("local", ProbeTime(TimeLocal()));
   w.Kv("server_last_quote", ProbeTime(server));
   w.Kv("gmt", ProbeTime(gmt));
   w.Kv("server_minus_gmt", DoubleToString((double)(server - gmt) / 3600.0, 2) +
        " h  (from the last quote time; not exact when the market is closed)");
  }

void ProbeAccountSection(CProbeWriter &w, const SAccountSpec &a)
  {
   w.Section("account");
   w.Kv("login", IntegerToString(a.login));
   w.Kv("server", a.server);
   w.Kv("company", a.company);
   w.Kv("currency", a.currency + (a.isCent ? "  (cent account detected, BC-12)" : ""));
   w.Kv("currency_digits", IntegerToString(a.digitsCcy));
   w.Kv("leverage", "1:" + IntegerToString(a.leverage));
   w.Kv("trade_mode", RdAccountTradeModeText(AccountInfoInteger(ACCOUNT_TRADE_MODE)));
   w.Kv("margin_mode", RdMarginModeText(a.marginMode));
   w.Kv("limit_orders", a.limitOrders > 0 ? IntegerToString(a.limitOrders) : "0 (no limit)");
   w.Kv("trade_allowed", RdBoolText(a.accountTradeAllowed));
   w.Kv("trade_expert", RdBoolText(a.accountExpertAllowed));
   w.Kv("balance", DoubleToString(a.balance, a.digitsCcy));
   w.Kv("equity", DoubleToString(a.equity, a.digitsCcy));
   w.Kv("margin_free", DoubleToString(a.freeMargin, a.digitsCcy));
   w.Kv("margin_so_mode", RdStopoutModeText(AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE)));
   w.Kv("margin_so_call", RdNum(AccountInfoDouble(ACCOUNT_MARGIN_SO_CALL), 2));
   w.Kv("margin_so_so", RdNum(AccountInfoDouble(ACCOUNT_MARGIN_SO_SO), 2));
   ProbePlatformAccount(w);
   SResult why;
   w.Kv("riskdesk_can_trade", CAccountSpec::CanTrade(why) ? "yes" : "no - " + why.message);
  }

//+------------------------------------------------------------------+
//| One line of the 'calc' group: the three BC-05 valuations.        |
//+------------------------------------------------------------------+
void ProbeLossLine(CProbeWriter &w, const string key, const SSymbolSpec &s, const ESide side,
                   const double entry, const double sl, const SAccountSpec &a, CMoney &money, string &issues[])
  {
   double byCalc = 0.0;
   double byTick = 0.0;
   double byContract = 0.0;
   string via = "";
   SResult r1, r2, r3;
   bool hasCalc = money.LossByCalcProfit(s, side, entry, sl, byCalc, r1);
   bool hasTick = money.LossByTickValue(s, entry, sl, byTick, r2);
   bool hasContract = money.LossByContract(s, entry, sl, a.currency, byContract, via, r3);

   string text = "OrderCalcProfit=" + (hasCalc ? RdNum(byCalc, 4) : "n/a") +
                 " tickvalue_formula=" + (hasTick ? RdNum(byTick, 4) : "n/a (" + r2.message + ")") +
                 " expected_from_contract=" + (hasContract ? RdNum(byContract, 4) + " (rate via " + via + ")" : "n/a (" + r3.message + ")");

   if(hasTick && hasContract && byContract > 0.0)
     {
      double mismatch = MathAbs(byTick - byContract) / byContract * 100.0;
      text += " mismatch_pct=" + DoubleToString(mismatch, 2);
      if(mismatch > RD_PROBE_MISMATCH_PCT)
         ProbeAdd(issues, s.name + ": tick value differs from contract x rate by " + DoubleToString(mismatch, 1) +
                  " % (" + key + ", calc mode " + RdCalcModeText(s.calcMode) + "; BC-05)");
     }
   if(hasCalc && hasTick && byCalc > 0.0)
     {
      double diff = MathAbs(byTick - byCalc) / byCalc * 100.0;
      text += " calcprofit_vs_tickvalue_pct=" + DoubleToString(diff, 2);
      if(diff > RD_PROBE_MISMATCH_PCT)
         ProbeAdd(issues, s.name + ": OrderCalcProfit differs from tick value by " + DoubleToString(diff, 1) + " % (" + key + ")");
     }
   if(!hasCalc && !hasTick)
      ProbeAdd(issues, s.name + ": cannot value a price move (" + r2.message + ")");
   else
      if((hasCalc && byCalc <= 0.0) || (!hasCalc && hasTick && byTick <= 0.0))
         ProbeAdd(issues, s.name + ": loss for a losing move is not positive (" + key + ")");
   w.Kv2(key, text);
  }

void ProbeMarginLine(CProbeWriter &w, const string key, const SSymbolSpec &s, const double volume,
                     const double price, const SAccountSpec &a, CMoney &money, string &issues[])
  {
   double margin = 0.0;
   SResult r;
   if(money.MarginRaw(s, SIDE_BUY, volume, price, margin, r))
      w.Kv2(key, ProbeMoney(margin, a.currency) + "  (" + RdNum(volume) + " lot)");
   else
     {
      w.Kv2(key, "n/a (" + r.message + ")");
      ProbeAdd(issues, s.name + ": " + r.message);
     }
  }

//+------------------------------------------------------------------+
void ProbeSymbol(CProbeWriter &w, const string symbol, const bool addedByProbe, const SAccountSpec &a, CMoney &money,
                 string &issues[], int &noQuote)
  {
   w.Section("symbol " + symbol);
   SSymbolSpec s;
   SResult sr;
   if(!CSymbolSpec::Exists(symbol))
     {
      w.Kv("error", "not available on this server");
      ProbeAdd(issues, symbol + ": not available on this server");
      return;
     }
   bool specOk = CSymbolSpec::Read(symbol, s, sr);

   w.Kv("path", SymbolInfoString(symbol, SYMBOL_PATH));
   w.Kv("description", SymbolInfoString(symbol, SYMBOL_DESCRIPTION));
   w.Kv("in_market_watch", addedByProbe ? "false (added by the probe for its quotes, removed again at the end)" : "true");
   w.Kv("currency_base", s.baseCcy);
   w.Kv("currency_profit", s.profitCcy);
   w.Kv("currency_margin", s.marginCcy);
   w.Kv("digits", IntegerToString(s.digits));
   w.Kv("point", RdNum(s.point, 10));
   w.Kv("tick_size", RdNum(s.tickSize, 10) + (s.tickSizeFromPoint ? "  (broker reported 0; point used, BC-02)" : ""));
   if(s.point > 0.0)
     {
      double ratio = s.tickSize / s.point;
      w.Kv("tick_size_in_points", RdNum(ratio, 4) + (MathAbs(ratio - 1.0) > 1e-6 ? "  (tick size != point: prices must be multiples of the tick size, BC-03)" : ""));
     }
   w.Kv("tick_value", ProbeMoney(s.tickValue, a.currency));
   w.Kv("contract_size", RdNum(s.contractSize));
   w.Kv("volume_min", RdNum(s.volMin));
   w.Kv("volume_max", RdNum(s.volMax));
   w.Kv("volume_step", RdNum(s.volStep));
   w.Kv("stops_level", IntegerToString(s.stopsLevel) + " pts (" + RdNum(s.stopsLevel * s.point, s.digits) + ")");
   w.Kv("freeze_level", IntegerToString(s.freezeLevel) + " pts (" + RdNum(s.freezeLevel * s.point, s.digits) + ")");
   w.Kv("trade_mode", RdSymbolTradeModeText(s.tradeMode));
   w.Kv("exec_mode", RdExecModeText(s.execMode));
   w.Kv("calc_mode", RdCalcModeText(s.calcMode));
   w.Kv("filling_flags", RdFillingFlagsText(s.fillingFlags));
   w.Kv("expiration_flags", RdExpirationFlagsText(s.expirationFlags));
   w.Kv("order_mode_flags", RdOrderModeFlagsText(s.orderModeFlags));
   w.Kv("spread_now", IntegerToString(SymbolInfoInteger(symbol, SYMBOL_SPREAD)) + " pts");
   w.Kv("spread_float", RdBoolText(SymbolInfoInteger(symbol, SYMBOL_SPREAD_FLOAT) != 0));
   w.Kv("swap_long", RdNum(SymbolInfoDouble(symbol, SYMBOL_SWAP_LONG)));
   w.Kv("swap_short", RdNum(SymbolInfoDouble(symbol, SYMBOL_SWAP_SHORT)));
   w.Kv("sessions_today", ProbeSessionsToday(symbol));

   SQuote q;
   bool hasQuote = CMarket::Quote(symbol, q);
   w.Kv("bid", hasQuote ? DoubleToString(q.bid, s.digits) : "none");
   w.Kv("ask", hasQuote ? DoubleToString(q.ask, s.digits) : "none");
   w.Kv("tick_time", ProbeTime(q.time));
   if(q.time > 0)
      w.Kv("tick_age_sec", IntegerToString((long)(TimeCurrent() - q.time)));
   w.Kv("spec_check", RdSeverityText(sr.sev) + " - " + sr.message);

   ProbePlatformSymbol(w, s, a);

   //--- issues visible from the properties alone
   if(!specOk)
      ProbeAdd(issues, symbol + ": " + sr.message);
   else
      if(sr.sev == SEV_WARN)
         ProbeAdd(issues, symbol + ": " + sr.message);
   if(s.tradeMode != SYMBOL_TRADE_MODE_FULL)
      ProbeAdd(issues, symbol + ": trade mode " + RdSymbolTradeModeText(s.tradeMode));
   if(!RdSymbolAcceptsSl(s))
      ProbeAdd(issues, symbol + ": order mode flags do not include SL (BC-11: RiskDesk will refuse to trade it)");
   if(!hasQuote)
     {
      noQuote++;
      ProbeAdd(issues, symbol + ": no quote (market closed, or the symbol was just added to Market Watch)");
     }

   //--- calc
   w.Group("calc");
   if(!hasQuote || !specOk)
      w.Kv2("skipped", !specOk ? "symbol spec invalid" : "no quote");
   else
     {
      double move = RD_PROBE_TICKS * s.tickSize;
      w.Kv2("move", IntegerToString(RD_PROBE_TICKS) + " ticks = " + RdNum(move, s.digits) + " price, 1.0 lot, values in " + a.currency);
      ProbeLossLine(w, "loss_100ticks_buy", s, SIDE_BUY, q.ask, q.ask - move, a, money, issues);
      ProbeLossLine(w, "loss_100ticks_sell", s, SIDE_SELL, q.bid, q.bid + move, a, money, issues);
      ProbeMarginLine(w, "margin_min_lot_buy", s, s.volMin, q.ask, a, money, issues);
      ProbeMarginLine(w, "margin_1lot_buy", s, 1.0, q.ask, a, money, issues);
     }

   //--- checks
   ProbePlatformChecks(w, s, q, hasQuote && specOk, a);
  }

//+------------------------------------------------------------------+
//| Entry point called by OnStart of both entry files.               |
//+------------------------------------------------------------------+
void ProbeRun()
  {
   CLogger::Configure(LOGLEVEL_INFO, true, "BrokerProbe");
   RD_LOG_INFO("BrokerProbe " + RD_VERSION + " (" + RD_PLATFORM + ") started on " + _Symbol);

   SAccountSpec a;
   SResult ar;
   if(!CAccountSpec::Read(a, ar))
     {
      RD_LOG_ERROR("BrokerProbe: " + ar.message + ". Log in to the account and run the probe again.");
      Alert("BrokerProbe: " + ar.message + ". Log in to the account and run the probe again.");
      return;
     }

   //--- symbol list: chart symbol, Market Watch, extras, test matrix
   string symbols[];
   string notFound[];
   string matrixLines[];
   ProbeAddUnique(symbols, _Symbol);
   if(InpIncludeMarketWatch)
     {
      int total = SymbolsTotal(true);
      for(int i = 0; i < total; i++)
         ProbeAddUnique(symbols, SymbolName(i, true));
     }
   if(RdTrim(InpExtraSymbols) != "")
     {
      string parts[];
      int n = StringSplit(InpExtraSymbols, ',', parts);
      for(int i = 0; i < n; i++)
        {
         string name = RdTrim(parts[i]);
         if(name == "")
            continue;
         if(CSymbolSpec::Exists(name))
            ProbeAddUnique(symbols, name);
         else
            ProbeAddUnique(notFound, name);
        }
     }
   if(InpFindTestSymbols)
      ProbeFindTestSymbols(symbols, matrixLines);

   int maxSymbols = (InpMaxSymbols < 1) ? 1 : InpMaxSymbols;
   int dropped = 0;
   if(ArraySize(symbols) > maxSymbols)
     {
      dropped = ArraySize(symbols) - maxSymbols;
      ArrayResize(symbols, maxSymbols);
     }

   //--- symbols outside Market Watch need to be selected to get quotes
   string added[];
   int count = ArraySize(symbols);
   for(int i = 0; i < count; i++)
      if(!ProbeInMarketWatch(symbols[i]) && SymbolSelect(symbols[i], true))
         ProbeAdd(added, symbols[i]);

   //--- resolve the conversion routes now (BC-01), so that the pairs they
   //--- select into Market Watch receive quotes during the same wait
   CMoney money;
   for(int i = 0; i < count; i++)
     {
      double rate = 0.0;
      string via = "";
      SResult rr;
      if(!money.Rate(SymbolInfoString(symbols[i], SYMBOL_CURRENCY_PROFIT), a.currency, rate, via, rr))
        {
         // reported per symbol in its calc section
        }
     }
   int selectedTotal = ArraySize(added) + money.AddedCount();
   if(selectedTotal > 0)
     {
      RD_LOG_INFO("BrokerProbe: added " + IntegerToString(selectedTotal) +
                  " symbols to Market Watch for quotes; they are removed again at the end");
      Sleep(RD_PROBE_QUOTE_WAIT_MS);
     }

   //--- open the report
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   string fileName = StringFormat("probe_%s_%s_%s_%04d%02d%02d.txt", ProbeSanitize(a.company), RD_PLATFORM,
                                  IntegerToString(a.login), dt.year, dt.mon, dt.day);
   string relative = RD_PRODUCT + "\\" + fileName;
   string fullPath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\" + RD_MQL_DIR + "\\Files\\" + relative;
   CProbeWriter w;
   int openError = 0;
   if(!w.Open(relative, openError))
     {
      RD_LOG_ERROR("BrokerProbe: cannot create " + fullPath + " (error " + IntegerToString(openError) + ")");
      Alert("BrokerProbe: cannot create the report file (error " + IntegerToString(openError) + "). See the Experts tab.");
      return;
     }

   w.Comment("RiskDesk BrokerProbe " + RD_VERSION + ", report format " + RD_PROBE_FORMAT + ", " + RD_PLATFORM);
   w.Comment("Generated " + ProbeTime(TimeLocal()) + " local time on the chart of " + _Symbol + ".");
   w.Comment("Nothing was executed: no order was sent. MT5 checks use OrderCheck, which only validates a request.");
   w.Comment("Money values are in the account currency (" + a.currency + ") unless stated otherwise.");

   ProbeTerminal(w);
   ProbeTimes(w);
   ProbeAccountSection(w, a);

   if(InpFindTestSymbols)
     {
      w.Section("test symbols");
      w.Comment("Candidates for the test matrix (08-testing section 4), best first; found by currencies or by keywords in name/description.");
      int n = ArraySize(matrixLines);
      for(int i = 0; i < n; i++)
         w.Raw("  " + matrixLines[i]);
     }
   if(ArraySize(notFound) > 0 || dropped > 0)
     {
      w.Section("not probed");
      int n = ArraySize(notFound);
      for(int i = 0; i < n; i++)
         w.Kv(notFound[i], "not available on this server (InpExtraSymbols)");
      if(dropped > 0)
         w.Kv("limit", IntegerToString(dropped) + " symbols left out by InpMaxSymbols=" + IntegerToString(maxSymbols));
     }

   //--- symbols
   string issues[];
   int noQuote = 0;
   for(int i = 0; i < count; i++)
      ProbeSymbol(w, symbols[i], ProbeContains(added, symbols[i]), a, money, issues, noQuote);

   //--- conversion routes used by the calculations (BC-01)
   w.Section("conversion");
   int routes = money.RouteCount();
   if(routes == 0)
      w.Kv("routes", "none needed");
   for(int i = 0; i < routes; i++)
      w.Raw("  " + money.RouteText(i));

   //--- summary
   w.Section("summary");
   w.Kv("symbols_probed", IntegerToString(count));
   w.Kv("symbols_without_quote", IntegerToString(noQuote));
   w.Kv("items_to_check", IntegerToString(ArraySize(issues)));
   int issueCount = ArraySize(issues);
   for(int i = 0; i < issueCount; i++)
      w.Raw("  - " + issues[i]);
   w.Close();

   //--- restore Market Watch
   int removed = 0;
   for(int i = 0; i < ArraySize(added); i++)
      if(SymbolSelect(added[i], false))
         removed++;
   for(int i = 0; i < money.AddedCount(); i++)
      if(!ProbeContains(added, money.Added(i)) && SymbolSelect(money.Added(i), false))
         removed++;
   if(removed > 0)
      RD_LOG_INFO("BrokerProbe: removed " + IntegerToString(removed) + " symbols from Market Watch again");

   string done = "BrokerProbe: report written to " + fullPath + " (" + IntegerToString(count) + " symbols, " +
                 IntegerToString(issueCount) + " items to check)";
   RD_LOG_INFO(done);
   Alert(done);
  }

#endif // RD_SCRIPTS_BROKERPROBECORE_MQH
