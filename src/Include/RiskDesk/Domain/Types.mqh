// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Domain/Types.mqh                                      |
//| Layer   : Domain (pure: no terminal calls at all)                |
//| Purpose : enums, plain data structs and small pure helpers       |
//|           shared by every layer (02-architecture section 6, enum |
//|           list in 07-settings).                                  |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_TYPES_MQH
#define RD_DOMAIN_TYPES_MQH

//====================================================================
// Core enums (02-architecture section 6)
//====================================================================
enum ESide
  {
   SIDE_BUY  = 0,
   SIDE_SELL = 1
  };

enum EOrderKind
  {
   KIND_MARKET = 0,
   KIND_LIMIT  = 1,
   KIND_STOP   = 2
  };

enum ELineMode
  {
   LINES_NONE    = 0,
   LINES_MARKET  = 1,
   LINES_PENDING = 2
  };

enum ESeverity
  {
   SEV_OK    = 0,
   SEV_WARN  = 1,
   SEV_ERROR = 2
  };

//====================================================================
// Input enums (07-settings). The comment after each value is the text
// shown in the terminal's properties dialog.
//====================================================================
enum ERiskBase
  {
   RISKBASE_BALANCE,      // Balance
   RISKBASE_EQUITY,       // Equity
   RISKBASE_MIN_BAL_EQ    // Lower of balance and equity
  };

enum EScopeChart
  {
   SCOPE_ALL_ON_SYMBOL,   // All trades on the chart symbol
   SCOPE_TOOL_ON_SYMBOL   // RiskDesk trades on the chart symbol
  };

enum EScopeAccount
  {
   SCOPE_ALL_ACCOUNT,     // All trades on the account
   SCOPE_TOOL_ACCOUNT     // RiskDesk trades on the account
  };

enum ERiskFreeMode
  {
   RF_SPREAD_COMMISSION,  // Open price + spread + commission
   RF_SPREAD,             // Open price + spread
   RF_COMMISSION,         // Open price + commission
   RF_EXACT               // Exact open price
  };

enum EIndivisible
  {
   INDIV_SKIP,            // Skip and report
   INDIV_CLOSE_ALL        // Close the whole position
  };

enum EFillingOverride
  {
   FILLPOL_AUTO,          // Auto (from the symbol's flags)
   FILLPOL_FOK,           // Fill or Kill
   FILLPOL_IOC,           // Immediate or Cancel
   FILLPOL_RETURN         // Return
  };

enum EStopsMode
  {
   STOPS_AUTO,            // Auto
   STOPS_WITH_ORDER,      // Send SL/TP with the order
   STOPS_MODIFY_AFTER     // Add SL/TP right after the open
  };

enum ECentMode
  {
   CENT_AUTO,             // Auto-detect
   CENT_ON,               // Cent account
   CENT_OFF               // Standard account
  };

enum ESpreadUnit
  {
   SPREAD_POINTS,         // Points
   SPREAD_PIPS            // Pips
  };

enum ELogLevel
  {
   LOGLEVEL_ERROR,        // Errors
   LOGLEVEL_WARN,         // Warnings
   LOGLEVEL_INFO,         // Info
   LOGLEVEL_DEBUG         // Debug
  };

enum EClosedTradeObjects
  {
   CTO_KEEP,              // Keep closed trade objects
   CTO_REMOVE             // Remove closed trade objects
  };

enum EFontPreset
  {
   FONT_SEGOE_UI,         // Segoe UI
   FONT_ARIAL,            // Arial
   FONT_TAHOMA,           // Tahoma
   FONT_CALIBRI,          // Calibri
   FONT_VERDANA,          // Verdana
   FONT_CONSOLAS          // Consolas
  };

// Panel layout (05 section 1, ADR-023).
enum EPanelColumns
  {
   PANEL_COLUMNS_AUTO,    // Auto (two when one column would shrink a lot)
   PANEL_COLUMNS_ONE,     // One column
   PANEL_COLUMNS_TWO      // Two columns
  };

// Derived once in Settings from the two TP inputs (ADR-013); not an input.
enum ETpMode
  {
   TPMODE_NONE,
   TPMODE_AUTO_RR,
   TPMODE_MANUAL_LINE
  };

// Which line of a placed pending order was dropped (OP-16).
enum ELineRole
  {
   LINEROLE_ENTRY,
   LINEROLE_SL,
   LINEROLE_TP
  };

//====================================================================
// Structs (02-architecture section 6)
//====================================================================

// Symbol properties as reported by the broker, read by Platform/SymbolSpec.
// Flags are the MT5 bit masks; they are 0 on MT4.
struct SSymbolSpec
  {
   string            name;
   int               digits;
   double            point;
   double            tickSize;          // BC-02: equals point when the broker reports 0 (tickSizeFromPoint)
   double            tickValue;
   double            tickValueProfit;   // MT4: same as tickValue
   double            tickValueLoss;     // MT4: same as tickValue
   double            contractSize;
   double            volMin;
   double            volMax;
   double            volStep;
   double            volLimit;          // 0 = unlimited, always 0 on MT4
   int               stopsLevel;        // points
   int               freezeLevel;       // points
   int               fillingFlags;
   int               expirationFlags;
   int               orderModeFlags;
   int               tradeMode;
   int               execMode;
   int               calcMode;          // MT5 ENUM_SYMBOL_CALC_MODE, MT4 MODE_PROFITCALCMODE
   string            baseCcy;
   string            profitCcy;
   string            marginCcy;
   bool              tickSizeFromPoint;

   void              Reset()
     {
      name = "";
      digits = 0;
      point = 0.0;
      tickSize = 0.0;
      tickValue = 0.0;
      tickValueProfit = 0.0;
      tickValueLoss = 0.0;
      contractSize = 0.0;
      volMin = 0.0;
      volMax = 0.0;
      volStep = 0.0;
      volLimit = 0.0;
      stopsLevel = 0;
      freezeLevel = 0;
      fillingFlags = 0;
      expirationFlags = 0;
      orderModeFlags = 0;
      tradeMode = 0;
      execMode = 0;
      calcMode = 0;
      baseCcy = "";
      profitCcy = "";
      marginCcy = "";
      tickSizeFromPoint = false;
     }
  };

// Account and terminal properties, read by Platform/AccountSpec.
struct SAccountSpec
  {
   long              login;
   string            currency;
   string            server;
   string            company;
   double            balance;
   double            equity;
   double            freeMargin;
   long              leverage;
   int               marginMode;        // MT5 ENUM_ACCOUNT_MARGIN_MODE, -1 on MT4
   bool              hedging;           // MT4: always true (BC-10)
   bool              isCent;            // auto-detected from the currency (BC-12)
   //--- F-24 display (RdApplyCent): money shown as cents plus the major unit
   bool              centShow;          // InpCentMode ON, or AUTO and isCent
   double            centDivisor;       // InpCentDivisor (100)
   string            centUnit;          // "USC": the cent amount's unit
   string            centMajor;         // "USD": the major unit ("" = unknown, plain number)
   bool              isDemo;
   bool              terminalConnected;
   bool              terminalTradeAllowed;
   bool              eaTradeAllowed;
   bool              accountTradeAllowed;
   bool              accountExpertAllowed;
   int               limitOrders;       // 0 = no limit
   int               digitsCcy;

   void              Reset()
     {
      login = 0;
      currency = "";
      server = "";
      company = "";
      balance = 0.0;
      equity = 0.0;
      freeMargin = 0.0;
      leverage = 0;
      marginMode = -1;
      hedging = true;
      isCent = false;
      centShow = false;
      centDivisor = 100.0;
      centUnit = "";
      centMajor = "";
      isDemo = false;
      terminalConnected = false;
      terminalTradeAllowed = false;
      eaTradeAllowed = false;
      accountTradeAllowed = false;
      accountExpertAllowed = false;
      limitOrders = 0;
      digitsCcy = 2;
     }
  };

struct SQuote
  {
   double            bid;
   double            ask;
   datetime          time;

   void              Reset() { bid = 0.0; ask = 0.0; time = 0; }
  };

struct SLines
  {
   ELineMode         mode;
   double            sl;
   double            tp;
   double            entry;
   bool              hasTp;

   void              Reset() { mode = LINES_NONE; sl = 0.0; tp = 0.0; entry = 0.0; hasTp = false; }
  };

struct STradePlan
  {
   ESide             side;
   EOrderKind        kind;
   double            entry;
   double            sl;
   double            tp;
   double            lots;
   double            lossPerLot;
   double            riskMoney;
   double            riskPct;
   double            rewardMoney;
   double            rr;
   string            warnings;

   void              Reset()
     {
      side = SIDE_BUY;
      kind = KIND_MARKET;
      entry = 0.0;
      sl = 0.0;
      tp = 0.0;
      lots = 0.0;
      lossPerLot = 0.0;
      riskMoney = 0.0;
      riskPct = 0.0;
      rewardMoney = 0.0;
      rr = 0.0;
      warnings = "";
     }
  };

struct SPosition
  {
   ulong             ticket;
   string            symbol;
   ESide             side;
   double            volume;
   double            open;
   double            sl;
   double            tp;
   double            profit;
   long              magic;
   double            lossToSl;
  };

struct SOrder
  {
   ulong             ticket;
   string            symbol;
   ESide             side;
   EOrderKind        kind;
   double            volume;
   double            price;
   double            sl;
   double            tp;
   long              magic;
   double            lossToSl;
   datetime          expiration;      // 0 = none (GTC, or MT5 DAY); BC-08, kept by G-08
  };

// Result of every function that can fail. 'message' is final,
// plain-English text suitable for the status bar (02 section 13).
struct SResult
  {
   bool              ok;
   ESeverity         sev;
   int               code;
   string            message;
   ulong             ticket;

   void              Reset() { ok = true; sev = SEV_OK; code = 0; message = ""; ticket = 0; }
  };

// The settings the Domain layer needs, as one plain struct (Domain never
// reads inputs). App/Settings fills every field from the validated
// inputs; Defaults() holds the 07-settings defaults (used by the tests).
struct SPlanSettings
  {
   ERiskBase         riskBase;
   double            maxRiskPerTradePct;
   double            maxTotalRiskPct;
   double            commissionPerLot;          // round turn, account currency
   bool              allowMinLotOverRisk;
   bool              includePendingInTotalRisk;
   long              magic;                     // identifies tool trades (BC-16)
   ETpMode           tpMode;
   double            tpRR;
   ERiskFreeMode     riskFreeMode;
   int               riskFreeExtraPoints;
   double            partialClosePct;
   EIndivisible      partialIndivisible;

   void              Defaults()
     {
      riskBase = RISKBASE_BALANCE;
      maxRiskPerTradePct = 10.0;
      maxTotalRiskPct = 10.0;
      commissionPerLot = 0.0;
      allowMinLotOverRisk = false;
      includePendingInTotalRisk = true;
      magic = 772211;
      tpMode = TPMODE_AUTO_RR;
      tpRR = 1.0;
      riskFreeMode = RF_SPREAD_COMMISSION;
      riskFreeExtraPoints = 0;
      partialClosePct = 50.0;
      partialIndivisible = INDIV_SKIP;
     }
  };

//====================================================================
// SResult helpers. RdOk/RdWarn return true and RdFail returns false,
// so a function can end with 'return RdFail(r, "...")'.
//====================================================================
bool RdOk(SResult &r, const string message)
  {
   r.ok = true;
   r.sev = SEV_OK;
   r.code = 0;
   r.message = message;
   return true;
  }

bool RdWarn(SResult &r, const string message)
  {
   r.ok = true;
   r.sev = SEV_WARN;
   r.code = 0;
   r.message = message;
   return true;
  }

bool RdFail(SResult &r, const string message, const int code = 0)
  {
   r.ok = false;
   r.sev = SEV_ERROR;
   r.code = code;
   r.message = message;
   return false;
  }

// Nothing to do for this item, for a reason the user should see in amber
// (e.g. Risk Free "not enough profit", Half Close "indivisible").
bool RdSkip(SResult &r, const string message)
  {
   r.ok = false;
   r.sev = SEV_WARN;
   r.code = 0;
   r.message = message;
   return false;
  }

// ADR-013: the TP mode from "Trade with TP Line" and "Manual TP Line".
ETpMode RdTpModeFrom(const bool tradeWithTpLine, const bool manualTpLine)
  {
   if(!tradeWithTpLine)
      return TPMODE_NONE;
   return manualTpLine ? TPMODE_MANUAL_LINE : TPMODE_AUTO_RR;
  }

string RdSeverityText(const ESeverity sev)
  {
   if(sev == SEV_WARN)
      return "WARN";
   if(sev == SEV_ERROR)
      return "ERROR";
   return "OK";
  }

//====================================================================
// Pure string helpers (identical on MQL4 and MQL5; the built-in trim
// functions have different signatures on the two platforms).
//====================================================================
string RdBoolText(const bool value)
  {
   return value ? "true" : "false";
  }

// Number without trailing zeros, at most maxDecimals decimals: 0.00001, 100000, 0.85.
string RdNum(const double value, const int maxDecimals = 8)
  {
   if(!MathIsValidNumber(value))
      return "nan";
   string s = DoubleToString(value, maxDecimals);
   if(StringFind(s, ".") < 0)
      return s;
   int n = StringLen(s);
   while(n > 0 && StringGetCharacter(s, n - 1) == '0')
      n--;
   if(n > 0 && StringGetCharacter(s, n - 1) == '.')
      n--;
   s = StringSubstr(s, 0, n);
   if(s == "-0")
      s = "0";
   return s;
  }

bool RdIsSpace(const ushort c)
  {
   return c == ' ' || c == '\t' || c == '\r' || c == '\n';
  }

string RdTrim(const string text)
  {
   int first = 0;
   int last = StringLen(text) - 1;
   while(first <= last && RdIsSpace(StringGetCharacter(text, first)))
      first++;
   while(last >= first && RdIsSpace(StringGetCharacter(text, last)))
      last--;
   if(last < first)
      return "";
   return StringSubstr(text, first, last - first + 1);
  }

// "FOK" + "IOC" -> "FOK|IOC"
string RdJoin(const string left, const string right, const string separator = "|")
  {
   if(left == "")
      return right;
   if(right == "")
      return left;
   return left + separator + right;
  }

string RdPadRight(const string text, const int width)
  {
   string s = text;
   while(StringLen(s) < width)
      s += " ";
   return s;
  }

#endif // RD_DOMAIN_TYPES_MQH
