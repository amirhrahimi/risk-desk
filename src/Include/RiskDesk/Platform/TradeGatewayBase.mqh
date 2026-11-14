// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Platform/TradeGatewayBase.mqh                         |
//| Layer   : Platform (platform-neutral part of CTradeGateway, no   |
//|           #ifdef)                                                |
//| Purpose : what TradeGatewayMT4 and TradeGatewayMT5 share:        |
//|           - SGatewaySettings (07-settings, Execution group)      |
//|           - STradeOutcome / STradeFilter                         |
//|           - the checks made before any request is sent: BC-15    |
//|             permissions and symbol trade mode, BC-02 spec, quote,|
//|             BC-04 volume grid, BC-09 order count, BC-11 order    |
//|             modes, rule R7 (no trade without SL)                 |
//|           - BC-11 per-symbol memory, BC-13 delays, log helpers   |
//|           CTradeGateway (MT4 or MT5 file) derives from           |
//|           CTradeGatewayBase; no virtual methods (ADR-001).       |
//+------------------------------------------------------------------+
#ifndef RD_PLATFORM_TRADEGATEWAYBASE_MQH
#define RD_PLATFORM_TRADEGATEWAYBASE_MQH

#include "..\Domain\Types.mqh"
#include "..\Domain\PriceMath.mqh"
#include "..\Domain\Format.mqh"
#include "..\Domain\RiskMath.mqh"
#include "..\Domain\Validators.mqh"
#include "..\Services\Logger.mqh"
#include "Compat.mqh"
#include "SymbolSpec.mqh"
#include "AccountSpec.mqh"
#include "Market.mqh"
#include "TradeErrors.mqh"

#define RD_GW_AMBIGUOUS_WAIT_MS  1000   // BC-14: wait before looking for the request's effect
#define RD_GW_AMBIGUOUS_WINDOW_S 5      // BC-14: open time >= request time - 5 s
#define RD_GW_LONG_WAIT_FACTOR   4      // "retry (longer wait)" codes wait 4x the normal delay
#define RD_GW_MAX_DELAY_MS       10000  // cap of one BC-13 delay
#define RD_GW_VERIFY_PASSES      3      // BC-11: read/fix rounds after an open
#define RD_GW_SELECT_TRIES       20     // wait up to 20 x 50 ms for a new position/order to show up
#define RD_GW_SELECT_SLEEP_MS    50
#define RD_GW_KNOWN_MAX          16     // BC-14: trades of ours (same symbol and magic) that existed before the request

// BC-14: is 'ticket' one of the 'count' tickets that existed before the request was sent?
bool RdGwKnown(const ulong &known[], const int count, const ulong ticket)
  {
   for(int i = 0; i < count; i++)
      if(known[i] == ticket)
         return true;
   return false;
  }

#ifdef RD_TEST_HOOKS
// Faults the self-test's safety suite arms (App/UiSelfTestSafety.mqh, ADR-031) to drive
// paths a healthy demo server never takes. They act on REAL requests: the server sees
// either a real order (and the gateway must then clean up) or nothing at all.
// Debug builds only: a release build contains none of this.
enum EGwFault
  {
   GWFAULT_NONE = 0,
   GWFAULT_SL_ATTACH,        // T-29: the open goes out without SL/TP and every SL/TP modify is refused (R7)
   GWFAULT_REPLY_LOST,       // T-35: the first open is sent and executes, its reply is dropped (BC-14, R9)
   GWFAULT_SEND_LOST,        // T-35: the first open never reaches the server (BC-14 finds nothing, resends once)
   GWFAULT_NEVER_ANSWERED,   // T-35: no open ever reaches the server (BC-14 resends once, then reports)
   GWFAULT_BAD_FILL          // BC-06 (MT5): the first filling policy is one the server should reject
  };

enum EGwSendFault
  {
   GWSEND_NONE = 0,
   GWSEND_SWALLOW,           // do not send the request, answer "no reply"
   GWSEND_DROP_REPLY         // send the request for real, then answer "no reply"
  };

#define RD_GW_TEST_FAULT_CODE 99001   // r.code of a refusal made by GWFAULT_SL_ATTACH
#endif

// The gateway primitives (06 section 5).
enum EGwAction
  {
   GWACT_OPEN,      // G-01 market deal that opens (or adds on netting)
   GWACT_PENDING,   // G-02
   GWACT_SLTP,      // G-03
   GWACT_CLOSE,     // G-04
   GWACT_REMOVE,    // G-05
   GWACT_MODIFY     // G-08
  };

// The inputs the gateway reads (07-settings, Execution). App/Settings
// fills it in P3; GatewaySmoke fills it from its own inputs.
struct SGatewaySettings
  {
   long              magic;               // InpMagic (BC-16)
   string            comment;             // InpComment
   int               slippagePoints;      // InpSlippagePoints (BC-13)
   int               maxRetries;          // InpMaxRetries: retries after the first send
   int               retryDelayMs;        // InpRetryDelayMs, doubles each retry
   EFillingOverride  fillingOverride;     // InpFillingOverride (BC-06, MT5 only)
   EStopsMode        stopsMode;           // InpStopsMode (BC-11)
   bool              closeIfStopFails;    // InpCloseIfStopFails (rule R7)
   int               pendingExpiryHours;  // InpPendingExpiryHours (BC-08), 0 = no expiry

   void              Defaults()
     {
      magic = 772211;
      comment = "RiskDesk";
      slippagePoints = 20;
      maxRetries = 3;
      retryDelayMs = 300;
      fillingOverride = FILLPOL_AUTO;
      stopsMode = STOPS_AUTO;
      closeIfStopFails = true;
      pendingExpiryHours = 0;
     }
  };

// What a primitive did, for the command's status text and the log.
struct STradeOutcome
  {
   ulong             ticket;        // G-01/G-04: position ticket; G-02: order ticket
   ulong             order;         // order ticket of the request (MT4: same as ticket)
   ulong             deal;          // MT5 deal ticket; 0 on MT4
   ulong             remainder;     // G-04 partial close: ticket of the rest (MT4: a NEW ticket, BC-16)
   double            requested;     // volume asked for
   double            volume;        // volume filled / placed / closed
   double            remaining;     // G-04: volume still open
   double            price;         // fill / placement / close price
   double            sl;            // SL/TP on the server after verification
   double            tp;
   double            profit;        // G-04: realized profit + swap + commission of the closed part
   bool              profitKnown;
   int               sends;         // requests sent, including ladder steps and retries
   string            filling;       // MT5 policy used (FOK/IOC/RETURN); "" on MT4
   string            timePolicy;    // G-02: GTC/DAY/SPECIFIED/SPECIFIED_DAY
   datetime          expiration;    // G-02: 0 = none
   bool              stopsAfter;    // SL/TP attached by a modify right after the open (BC-11)
   bool              partialFill;   // MT5 DONE_PARTIAL
   bool              alreadyDone;   // was already closed / deleted / set
   string            notes;         // amber notes (policy differs from the request, ...)

   void              Reset()
     {
      ticket = 0;
      order = 0;
      deal = 0;
      remainder = 0;
      requested = 0.0;
      volume = 0.0;
      remaining = 0.0;
      price = 0.0;
      sl = 0.0;
      tp = 0.0;
      profit = 0.0;
      profitKnown = false;
      sends = 0;
      filling = "";
      timePolicy = "";
      expiration = 0;
      stopsAfter = false;
      partialFill = false;
      alreadyDone = false;
      notes = "";
     }
  };

// G-06 / G-07 filter (06 section 3 scopes).
struct STradeFilter
  {
   string            symbol;            // "" = every symbol
   bool              toolOnly;          // only magic == settings magic
   bool              includeStopLimit;  // G-07 for deletion: MT5 stop-limit orders too (listed as KIND_STOP)

   void              Reset() { symbol = ""; toolOnly = false; includeStopLimit = false; }
  };

//+------------------------------------------------------------------+
class CTradeGatewayBase
  {
protected:
   SGatewaySettings  m_cfg;
   string            m_modifyAfter[];   // BC-11: symbols whose server refused SL/TP on market orders
#ifdef RD_TEST_HOOKS
   EGwFault          m_fault;           // armed by the self-test, GWFAULT_NONE otherwise
   bool              FaultIs(const EGwFault f) const { return m_fault == f; }
   EGwSendFault      SendFault(const EGwAction act, const int attempt) const;
#endif

   bool              Prepare(const string op, const string symbol, SSymbolSpec &s, SQuote &q, SResult &r);
   bool              SpecQuote(const string op, const string symbol, SSymbolSpec &s, SQuote &q, SResult &r);
   bool              CheckOpen(const string op, const SSymbolSpec &s, const ESide side, const EOrderKind kind,
                               const double lots, const double sl, const double tp, SResult &r);
   bool              CheckClose(const string op, const SSymbolSpec &s, SResult &r);
   bool              CheckOrderLimit(const string op, const string symbol, SResult &r);
   bool              CloseVolume(const string op, const SSymbolSpec &s, const double posVolume, const double wanted,
                                 double &volume, SResult &r);
   bool              WantStopsWithOrder(const string symbol) const;
   void              RememberModifyAfter(const string symbol);
   bool              Matches(const STradeFilter &f, const string symbol, const long magic) const;
   int               RetryDelayMs(const int retry, const ETradeCodeClass cls) const;
   void              Pause(const int ms) const;

   //--- results with a log line (rule R8)
   bool              Refuse(const string op, const string symbol, SResult &r, const string message) const;
   bool              Refused(const string op, const string symbol, SResult &r) const;
   bool              Failed(const string op, const string symbol, SResult &r, const string message, const int code = 0) const;

   //--- text
   bool              LevelEq(const SSymbolSpec &s, const double a, const double b) const;
   string            Px(const SSymbolSpec &s, const double price) const;
   string            VolumeGrid(const SSymbolSpec &s) const;
   string            WithComment(const string message, const string comment) const;
   string            StopsDistances(const SSymbolSpec &s, const double ref, const string refName,
                                    const double sl, const double tp) const;
   string            AccountMoney(const double amount) const;

public:
#ifdef RD_TEST_HOOKS
                     CTradeGatewayBase() { m_cfg.Defaults(); m_fault = GWFAULT_NONE; }
   void              ArmFault(const EGwFault f) { m_fault = f; }
#else
                     CTradeGatewayBase() { m_cfg.Defaults(); }
#endif
   void              Configure(const SGatewaySettings &cfg) { m_cfg = cfg; }
   long              Magic() const { return m_cfg.magic; }
   bool              NeedsModifyAfter(const string symbol) const;
  };

#ifdef RD_TEST_HOOKS
//+------------------------------------------------------------------+
//| What the armed fault does to this send. Only market opens are    |
//| touched (never a close, modify or delete); 'attempt' is the      |
//| number of the OrderSend call within the request (1 = first).     |
//+------------------------------------------------------------------+
EGwSendFault CTradeGatewayBase::SendFault(const EGwAction act, const int attempt) const
  {
   if(act != GWACT_OPEN)
      return GWSEND_NONE;
   if(m_fault == GWFAULT_REPLY_LOST && attempt == 1)
      return GWSEND_DROP_REPLY;
   if(m_fault == GWFAULT_SEND_LOST && attempt == 1)
      return GWSEND_SWALLOW;
   if(m_fault == GWFAULT_NEVER_ANSWERED && attempt <= 2)
      return GWSEND_SWALLOW;
   return GWSEND_NONE;
  }
#endif

//+------------------------------------------------------------------+
//| BC-15 permissions, then spec and quote.                          |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::Prepare(const string op, const string symbol, SSymbolSpec &s, SQuote &q, SResult &r)
  {
   r.Reset();
   if(!CAccountSpec::CanTrade(r))
      return Refused(op, symbol, r);
   return SpecQuote(op, symbol, s, q, r);
  }

//+------------------------------------------------------------------+
//| BC-02: the spec is read fresh before every request.              |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::SpecQuote(const string op, const string symbol, SSymbolSpec &s, SQuote &q, SResult &r)
  {
   r.Reset();
   SResult sr;
   if(!CSymbolSpec::Read(symbol, s, sr))
     {
      r = sr;
      return Refused(op, symbol, r);
     }
   if(sr.sev == SEV_WARN)
      RD_LOG_WARN("[" + op + "] " + sr.message);
   if(!CMarket::Quote(symbol, q))
      return Refuse(op, symbol, r, "No quote for " + symbol + " - market closed, or the symbol is not in Market Watch");
   if(!CValidators::QuoteOk(q, s, r))
      return Refused(op, symbol, r);
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| New orders: BC-15 symbol trade mode for the side, BC-11 order    |
//| modes (MT5 flags), rule R7 (SL required), BC-04 volume grid.     |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::CheckOpen(const string op, const SSymbolSpec &s, const ESide side, const EOrderKind kind,
                                  const double lots, const double sl, const double tp, SResult &r)
  {
   r.Reset();
   if(s.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return Refuse(op, s.name, r, "Trading disabled for " + s.name);
   if(s.tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return Refuse(op, s.name, r, s.name + " is close-only: the broker allows no new orders");
   if(s.tradeMode == SYMBOL_TRADE_MODE_LONGONLY && side == SIDE_SELL)
      return Refuse(op, s.name, r, s.name + " allows long only: sell orders are refused by the broker");
   if(s.tradeMode == SYMBOL_TRADE_MODE_SHORTONLY && side == SIDE_BUY)
      return Refuse(op, s.name, r, s.name + " allows short only: buy orders are refused by the broker");
   if(!RdSymbolAcceptsKind(s, kind))
      return Refuse(op, s.name, r, "Broker does not accept " + (kind == KIND_MARKET ? "market" : RdOrderText(side, kind)) +
                    " orders on " + s.name);
   if(!(sl > 0.0))
      return Refuse(op, s.name, r, "No SL: Risk Desk never opens a trade without a stop-loss");
   if(!RdSymbolAcceptsSl(s))
      return Refuse(op, s.name, r, "Broker does not accept SL on " + s.name);
   if(tp > 0.0 && !RdSymbolAcceptsTp(s))
      return Refuse(op, s.name, r, "Broker does not accept TP on " + s.name + " - trade without a TP line");
   if(!RdIsValidVolume(s, lots))
      return Refuse(op, s.name, r, "Invalid volume " + RdNum(lots) + " for " + s.name + " (min/step/max = " +
                    VolumeGrid(s) + ")");
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| Closing is allowed in every trade mode except "disabled".        |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::CheckClose(const string op, const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(s.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
      return Refuse(op, s.name, r, "Trading disabled for " + s.name + ": the broker accepts no orders, not even closes");
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-09: ACCOUNT_LIMIT_ORDERS (MT5: active pending orders; MT4:    |
//| open positions + pending orders, both what OrdersTotal() counts).|
//+------------------------------------------------------------------+
bool CTradeGatewayBase::CheckOrderLimit(const string op, const string symbol, SResult &r)
  {
   r.Reset();
   int limit = (int)AccountInfoInteger(ACCOUNT_LIMIT_ORDERS);
   if(limit > 0 && OrdersTotal() >= limit)
      return Refuse(op, symbol, r, "Order count limit reached: the broker allows " + IntegerToString(limit) +
                    " orders on this account (" + IntegerToString(OrdersTotal()) + " now)");
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| G-04: requested volume floored to the grid (BC-04), never above  |
//| the position (that would reverse a netting position). <= 0 or >= |
//| the position volume means the whole position.                    |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::CloseVolume(const string op, const SSymbolSpec &s, const double posVolume, const double wanted,
                                    double &volume, SResult &r)
  {
   r.Reset();
   volume = posVolume;
   if(!(wanted > 0.0) || !RdVolLt(wanted, posVolume))
      return RdOk(r, "");
   double v = 0.0;
   if(!RdFloorVolume(s, wanted, v))
      return Refuse(op, s.name, r, "Close volume " + RdNum(wanted) + " is below the minimum lot " +
                    RdFormatLots(s, s.volMin) + " of " + s.name);
   if(!RdVolLt(v, posVolume))
      return RdOk(r, "");
   double remain = posVolume - v;
   if(RdVolLt(remain, s.volMin))
      return Refuse(op, s.name, r, "Closing " + RdFormatLots(s, v) + " of " + RdFormatLots(s, posVolume) + " lot would leave " +
                    RdNum(remain) + ", below the minimum lot " + RdFormatLots(s, s.volMin));
   volume = v;
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-11: send SL/TP with the order unless the settings say         |
//| ModifyAfter or this server already refused them (Auto).          |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::WantStopsWithOrder(const string symbol) const
  {
   if(m_cfg.stopsMode == STOPS_WITH_ORDER)
      return true;
   if(m_cfg.stopsMode == STOPS_MODIFY_AFTER)
      return false;
   return !NeedsModifyAfter(symbol);
  }

bool CTradeGatewayBase::NeedsModifyAfter(const string symbol) const
  {
   int n = ArraySize(m_modifyAfter);
   for(int i = 0; i < n; i++)
      if(m_modifyAfter[i] == symbol)
         return true;
   return false;
  }

void CTradeGatewayBase::RememberModifyAfter(const string symbol)
  {
   if(NeedsModifyAfter(symbol))
      return;
   int n = ArraySize(m_modifyAfter);
   ArrayResize(m_modifyAfter, n + 1);
   m_modifyAfter[n] = symbol;
  }

bool CTradeGatewayBase::Matches(const STradeFilter &f, const string symbol, const long magic) const
  {
   if(f.symbol != "" && symbol != f.symbol)
      return false;
   if(f.toolOnly && magic != m_cfg.magic)
      return false;
   return true;
  }

//+------------------------------------------------------------------+
//| BC-13: delay doubles each retry; longer for busy servers.        |
//+------------------------------------------------------------------+
int CTradeGatewayBase::RetryDelayMs(const int retry, const ETradeCodeClass cls) const
  {
   int delay = (m_cfg.retryDelayMs > 0) ? m_cfg.retryDelayMs : 0;
   for(int i = 0; i < retry && delay < RD_GW_MAX_DELAY_MS; i++)
      delay *= 2;
   if(cls == TCLASS_RETRY_LONG || cls == TCLASS_RETRY_CONTEXT)
      delay *= RD_GW_LONG_WAIT_FACTOR;
   return (delay > RD_GW_MAX_DELAY_MS) ? RD_GW_MAX_DELAY_MS : delay;
  }

void CTradeGatewayBase::Pause(const int ms) const
  {
   if(ms > 0 && !IsStopped())
      Sleep(ms);
  }

//+------------------------------------------------------------------+
//| Refused before sending (amber/red status, WARN log).             |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::Refuse(const string op, const string symbol, SResult &r, const string message) const
  {
   RdFail(r, message);
   return Refused(op, symbol, r);
  }

bool CTradeGatewayBase::Refused(const string op, const string symbol, SResult &r) const
  {
   RD_LOG_WARN("[" + op + "] " + symbol + " refused before sending: " + r.message);
   if(r.ok)
      RdFail(r, r.message);
   return false;
  }

//+------------------------------------------------------------------+
//| Failed after (or while) sending: ERROR log.                      |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::Failed(const string op, const string symbol, SResult &r, const string message, const int code) const
  {
   RdFail(r, message, code);
   RD_LOG_ERROR("[" + op + "] " + symbol + " failed: " + message);
   return false;
  }

//+------------------------------------------------------------------+
//| SL/TP level equality: both unset, or equal within half a tick.   |
//+------------------------------------------------------------------+
bool CTradeGatewayBase::LevelEq(const SSymbolSpec &s, const double a, const double b) const
  {
   bool aSet = (a > 0.0);
   bool bSet = (b > 0.0);
   if(aSet != bSet)
      return false;
   return !aSet || RdPriceEq(s, a, b);
  }

string CTradeGatewayBase::Px(const SSymbolSpec &s, const double price) const
  {
   if(!(price > 0.0))
      return "0";
   return DoubleToString(price, s.digits);
  }

string CTradeGatewayBase::VolumeGrid(const SSymbolSpec &s) const
  {
   return RdNum(s.volMin) + "/" + RdNum(s.volStep) + "/" + RdNum(s.volMax);
  }

// "Filling policy rejected [Unsupported filling mode]"; the broker's
// comment is left out when it only repeats the message.
string CTradeGatewayBase::WithComment(const string message, const string comment) const
  {
   string c = RdTrim(comment);
   if(c == "")
      return message;
   string a = message;
   string b = c;
   StringToLower(a);
   StringToLower(b);
   if(a == b)
      return message;
   return message + " [" + c + "]";
  }

// BC-07: after an INVALID_STOPS answer show the distances used.
string CTradeGatewayBase::StopsDistances(const SSymbolSpec &s, const double ref, const string refName,
                                         const double sl, const double tp) const
  {
   string text = "";
   if(sl > 0.0)
      text = "SL " + RdFormatPoints(RdPointsBetween(s, ref, sl)) + " from " + refName;
   if(tp > 0.0)
      text = RdJoin(text, "TP " + RdFormatPoints(RdPointsBetween(s, ref, tp)) + " from " + refName, ", ");
   if(text == "")
      return "";
   return "- used " + text + ", stops level " + RdFormatPoints(s.stopsLevel) + ": move the line further";
  }

string CTradeGatewayBase::AccountMoney(const double amount) const
  {
   return RdFormatMoney(amount, AccountInfoString(ACCOUNT_CURRENCY), RdAccountCurrencyDigits());
  }

#endif // RD_PLATFORM_TRADEGATEWAYBASE_MQH
