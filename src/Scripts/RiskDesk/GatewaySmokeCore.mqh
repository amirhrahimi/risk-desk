//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/GatewaySmokeCore.mqh                 |
//| Layer   : diagnostics script (shared body of GatewaySmoke.mq4    |
//|           and GatewaySmoke.mq5, 08-testing L3b, 09 P2)           |
//| Purpose : drives the real CTradeGateway on the chart symbol of a |
//|           DEMO account with the smallest volume and distances    |
//|           derived from the symbol's own properties:              |
//|             M01 open buy with SL/TP   M02 verify SL/TP           |
//|             M03 modify SL             M04 partial close          |
//|             M05 close the rest        M06 open sell  M07 close   |
//|             P01 place buy limit       P02 modify price/SL/TP     |
//|             P03 delete                                           |
//|           and writes a PASS/FAIL/SKIP table to the Experts tab   |
//|           and to Files/RiskDesk/smoke_<company>_<platform>_      |
//|           <login>_<yyyymmdd>.txt (one block per run, appended).  |
//|                                                                  |
//| No #ifdef: it uses only the gateway's public API, which is the   |
//| same on MT4 and MT5 (ADR-001), so it also proves that parity.    |
//| Nothing here knows a broker or a symbol name.                    |
//| The entry files refuse non-demo accounts BEFORE calling this     |
//| (rule R13); SmokeRun checks it again.                            |
//+------------------------------------------------------------------+
#ifndef RD_SCRIPTS_GATEWAYSMOKECORE_MQH
#define RD_SCRIPTS_GATEWAYSMOKECORE_MQH

#include "..\..\Include\RiskDesk\Build.mqh"
#include "..\..\Include\RiskDesk\Domain\Types.mqh"
#include "..\..\Include\RiskDesk\Domain\PriceMath.mqh"
#include "..\..\Include\RiskDesk\Domain\Format.mqh"
#include "..\..\Include\RiskDesk\Domain\RiskMath.mqh"
#include "..\..\Include\RiskDesk\Services\Logger.mqh"
#include "..\..\Include\RiskDesk\Platform\Compat.mqh"
#include "..\..\Include\RiskDesk\Platform\SymbolSpec.mqh"
#include "..\..\Include\RiskDesk\Platform\AccountSpec.mqh"
#include "..\..\Include\RiskDesk\Platform\Market.mqh"
#include "..\..\Include\RiskDesk\Platform\Money.mqh"
#include "..\..\Include\RiskDesk\Platform\TradeGateway.mqh"

input double           InpDistancePct        = 0.30;          // SL/TP distance in % of price (raised to the stops/freeze level and spread)
input double           InpMaxRiskPct         = 1.0;           // Abort if a test position would risk more than this % of balance at SL
input bool             InpTestPartialClose   = true;          // Open 2 x min lot so a partial close can be tested
input bool             InpTestSell           = true;          // Also open and close a sell
input bool             InpTestPending        = true;          // Place, modify and delete a buy limit
input bool             InpConfirm            = true;          // Ask before sending anything
input long             InpSmokeMagic         = 772299;        // Magic number of the test trades (not the EA's)
input int              InpSlippagePoints     = 20;            // Max deviation for market orders (points)
input int              InpMaxRetries         = 3;             // Retries per request (BC-13)
input int              InpRetryDelayMs       = 300;           // First retry delay, doubles each retry
input EFillingOverride InpFillingOverride    = FILLPOL_AUTO;  // Filling policy (MT5; Auto = from the symbol's flags)
input EStopsMode       InpStopsMode          = STOPS_AUTO;    // How SL/TP are attached (BC-11)
input int              InpPendingExpiryHours = 0;             // Pending expiry in hours (0 = no expiry, BC-08)

#define RD_SMOKE_STEP_WIDTH   30
#define RD_SMOKE_PAUSE_MS     500     // between steps: lets the terminal settle

struct SSmokeRow
  {
   string            id;
   string            step;
   string            result;   // PASS / FAIL / SKIP
   string            detail;
   uint              ms;
  };

class CGatewaySmoke
  {
private:
   CTradeGateway     m_gw;
   CMoney            m_money;
   SAccountSpec      m_acc;
   SSymbolSpec       m_s;
   SSmokeRow         m_rows[];
   string            m_info[];        // [run] lines
   ulong             m_positions[];   // opened by this run, still open
   ulong             m_orders[];      // placed by this run, still pending
   double            m_dist;          // SL/TP distance (price)
   double            m_volume;
   uint              m_t0;
   int               m_pass;
   int               m_fail;
   int               m_skip;

   void              Info(const string key, const string value);
   void              Row(const string id, const string step, const string result, const string detail);
   bool              Pass(const string id, const string step, const string detail) { Row(id, step, "PASS", detail); return true; }
   bool              Fail(const string id, const string step, const string detail) { Row(id, step, "FAIL", detail); return false; }
   void              Skip(const string id, const string step, const string detail) { Row(id, step, "SKIP", detail); }
   void              Clock() { m_t0 = GetTickCount(); }
   void              Settle() { if(!IsStopped()) Sleep(RD_SMOKE_PAUSE_MS); }
   void              Track(ulong &list[], const ulong ticket);
   void              Untrack(ulong &list[], const ulong ticket);
   string            Px(const double price) const { return (price > 0.0) ? DoubleToString(price, m_s.digits) : "0"; }
   string            Lots(const double lots) const { return RdFormatLots(m_s, lots); }
   bool              LevelEq(const double a, const double b) const;
   string            OutcomeText(const STradeOutcome &out) const;

   bool              Prepare();
   bool              ChooseDistanceAndVolume();
   bool              Confirmed();
   void              MarketSequence(const ESide side, const string idOpen, const string idClose, const bool fullTest);
   void              PendingSequence();
   void              Cleanup();
   void              Report();

public:
                     CGatewaySmoke() : m_dist(0.0), m_volume(0.0), m_t0(0), m_pass(0), m_fail(0), m_skip(0) {}
   void              Run();
  };

//+------------------------------------------------------------------+
void CGatewaySmoke::Info(const string key, const string value)
  {
   int n = ArraySize(m_info);
   ArrayResize(m_info, n + 1);
   m_info[n] = "  " + RdPadRight(key + ":", 16) + " " + value;
   RD_LOG_INFO("GatewaySmoke " + key + ": " + value);
  }

void CGatewaySmoke::Row(const string id, const string step, const string result, const string detail)
  {
   int n = ArraySize(m_rows);
   ArrayResize(m_rows, n + 1);
   m_rows[n].id = id;
   m_rows[n].step = step;
   m_rows[n].result = result;
   m_rows[n].detail = detail;
   m_rows[n].ms = GetTickCount() - m_t0;
   if(result == "PASS")
      m_pass++;
   else
      if(result == "FAIL")
         m_fail++;
      else
         m_skip++;
   string line = "GatewaySmoke " + id + " " + result + " " + step + " - " + detail;
   if(result == "FAIL")
      RD_LOG_ERROR(line);
   else
      RD_LOG_INFO(line);
  }

void CGatewaySmoke::Track(ulong &list[], const ulong ticket)
  {
   if(ticket == 0)
      return;
   int n = ArraySize(list);
   for(int i = 0; i < n; i++)
      if(list[i] == ticket)
         return;
   ArrayResize(list, n + 1);
   list[n] = ticket;
  }

void CGatewaySmoke::Untrack(ulong &list[], const ulong ticket)
  {
   int n = ArraySize(list);
   for(int i = 0; i < n; i++)
      if(list[i] == ticket)
        {
         list[i] = list[n - 1];
         ArrayResize(list, n - 1);
         return;
        }
  }

bool CGatewaySmoke::LevelEq(const double a, const double b) const
  {
   if((a > 0.0) != (b > 0.0))
      return false;
   return !(a > 0.0) || RdPriceEq(m_s, a, b);
  }

string CGatewaySmoke::OutcomeText(const STradeOutcome &out) const
  {
   string text = RdTicketText(out.ticket) + " " + Lots(out.volume) + " lot @" + Px(out.price);
   if(out.filling != "")
      text += " fill=" + out.filling;
   if(out.timePolicy != "")
      text += " time=" + out.timePolicy;
   text += " sends=" + IntegerToString(out.sends);
   if(out.notes != "")
      text += " (" + out.notes + ")";
   return text;
  }

//+------------------------------------------------------------------+
//| S00: demo, permissions, spec, quote, netting state.              |
//+------------------------------------------------------------------+
bool CGatewaySmoke::Prepare()
  {
   Clock();
   SResult r;
   if(!RdIsDemoAccount())
      return Fail("S00", "preflight", "not a demo account (rule R13) - nothing sent");
   if(!CAccountSpec::Read(m_acc, r))
      return Fail("S00", "preflight", r.message);
   Info("platform", RD_PLATFORM + ", terminal build " + IntegerToString(RdTerminalBuild()));
   Info("account", CAccountSpec::Describe(m_acc));
   if(!CAccountSpec::CanTrade(r))
      return Fail("S00", "preflight", r.message);
   if(!CSymbolSpec::Read(_Symbol, m_s, r))
      return Fail("S00", "preflight", r.message);
   Info("symbol", CSymbolSpec::Describe(m_s, m_acc.currency));
   SQuote q;
   if(!CMarket::Quote(_Symbol, q))
      return Fail("S00", "preflight", "no quote for " + _Symbol + " - market closed?");
   if(CMarket::IsStale(q, 300))
      Info("warning", "last tick is " + IntegerToString(CMarket::AgeSeconds(q)) + " s old - market may be closed");

   SGatewaySettings cfg;
   cfg.Defaults();
   cfg.magic = InpSmokeMagic;
   cfg.comment = "RiskDesk smoke";
   cfg.slippagePoints = InpSlippagePoints;
   cfg.maxRetries = InpMaxRetries;
   cfg.retryDelayMs = InpRetryDelayMs;
   cfg.fillingOverride = InpFillingOverride;
   cfg.stopsMode = InpStopsMode;
   cfg.closeIfStopFails = true;   // rule R7, not optional here
   cfg.pendingExpiryHours = InpPendingExpiryHours;
   m_gw.Configure(cfg);
   Info("settings", "magic " + IntegerToString(InpSmokeMagic) + ", fill " + EnumToString(InpFillingOverride) +
        ", stops " + EnumToString(InpStopsMode) + ", retries " + IntegerToString(InpMaxRetries) +
        ", delay " + IntegerToString(InpRetryDelayMs) + " ms, slippage " + IntegerToString(InpSlippagePoints) +
        " pts, expiry " + IntegerToString(InpPendingExpiryHours) + " h");

   if(!m_gw.IsHedging())
     {
      STradeFilter f;
      f.Reset();
      f.symbol = _Symbol;
      SPosition existing[];
      m_gw.ListPositions(f, existing, r);
      if(ArraySize(existing) > 0)
         return Fail("S00", "preflight", "netting account with an open position on " + _Symbol +
                     " - the test would merge with it; run it on a symbol without a position");
     }
   if(!ChooseDistanceAndVolume())
      return false;
   return Pass("S00", "preflight", "demo, permissions, spec and quote OK; " + (m_gw.IsHedging() ? "hedging" : "netting"));
  }

//+------------------------------------------------------------------+
//| Distance: InpDistancePct of price, at least 2 x (stops + freeze) |
//| + 3 x spread + 10 ticks. Volume: 2 x min lot (partial close) or  |
//| min lot, within InpMaxRiskPct and the free margin.               |
//+------------------------------------------------------------------+
bool CGatewaySmoke::ChooseDistanceAndVolume()
  {
   SQuote q;
   if(!CMarket::Quote(_Symbol, q))
      return Fail("S00", "preflight", "no quote for " + _Symbol);
   double tick = RdTick(m_s);
   double spread = q.ask - q.bid;
   double byPct = q.ask * MathMax(InpDistancePct, 0.0) / 100.0;
   double byLevels = 2.0 * (m_s.stopsLevel + m_s.freezeLevel) * m_s.point + 3.0 * spread + 10.0 * tick;
   m_dist = RdRoundPriceUp(m_s, MathMax(byPct, byLevels));
   if(!(m_dist > 0.0) || q.ask - 3.0 * m_dist <= 0.0)
      return Fail("S00", "preflight", "no usable SL distance for " + _Symbol + " (" + RdNum(m_dist, m_s.digits) + ")");

   double lossPerLot = 0.0;
   SResult r;
   if(!m_money.LossPerLot(m_s, m_acc.currency, SIDE_BUY, q.ask, q.ask - m_dist, lossPerLot, r))
      return Fail("S00", "preflight", r.message);
   if(r.sev == SEV_WARN)
      Info("warning", r.message);

   double vol = m_s.volMin;
   if(InpTestPartialClose && !RdFloorVolume(m_s, 2.0 * m_s.volMin, vol))
      vol = m_s.volMin;
   if(RdVolGt(vol, m_s.volMax))
      vol = m_s.volMin;
   double maxRisk = m_acc.balance * MathMax(InpMaxRiskPct, 0.0) / 100.0;
   if(RdVolGt(vol, m_s.volMin) && vol * lossPerLot > maxRisk)
     {
      Info("note", "2 x min lot would risk " + RdMoney(m_acc, vol * lossPerLot) + " - using the min lot (no partial close)");
      vol = m_s.volMin;
     }
   if(vol * lossPerLot > maxRisk)
      return Fail("S00", "preflight", "min lot " + Lots(vol) + " would risk " + RdMoney(m_acc, vol * lossPerLot) + " at SL " +
                  RdFormatPoints(RdPointsBetween(m_s, q.ask, q.ask - m_dist)) + " away, above " + RdFormatCapPct(InpMaxRiskPct) +
                  " of balance - lower InpDistancePct or raise InpMaxRiskPct");

   double maxLots = 0.0;
   if(m_money.MaxLotsByMargin(m_s, SIDE_BUY, q.ask, m_acc.freeMargin, 5.0, maxLots, r) && RdVolGt(vol, maxLots))
      return Fail("S00", "preflight", "not enough free margin for " + Lots(vol) + " lot (max about " + Lots(maxLots) + ")");
   m_volume = vol;
   Info("test", Lots(vol) + " lot, SL/TP distance " + Px(m_dist) + " (" + RdFormatPoints(RdPointsBetween(m_s, 0.0, m_dist)) +
        "), risk at SL about " + RdMoney(m_acc, vol * lossPerLot) + " (" +
        RdFormatPct(vol * lossPerLot / m_acc.balance * 100.0) + ")");
   return true;
  }

bool CGatewaySmoke::Confirmed()
  {
   if(!InpConfirm)
      return true;
   string text = "GatewaySmoke will send REAL orders on demo account " + IntegerToString(m_acc.login) + " (" + m_acc.server +
                 "):\n\n" + RdOrderText(SIDE_BUY, KIND_MARKET) + " " + Lots(m_volume) + " " + _Symbol +
                 " with SL/TP " + Px(m_dist) + " away, modify, partial close, close" +
                 (InpTestSell ? "\nSell " + Lots(m_volume) + " with SL/TP, close" : "") +
                 (InpTestPending ? "\nBuy Limit far below the market: place, modify, delete" : "") +
                 "\n\nEvery trade is closed or deleted at the end. Continue?";
   return MessageBox(text, "RiskDesk GatewaySmoke", MB_YESNO | MB_ICONQUESTION) == IDYES;
  }

//+------------------------------------------------------------------+
//| Market sequence. fullTest (buy): open, verify, modify SL,        |
//| partial close, close. Otherwise (sell): open, verify, close.     |
//+------------------------------------------------------------------+
void CGatewaySmoke::MarketSequence(const ESide side, const string idOpen, const string idClose, const bool fullTest)
  {
   string name = RdSideText(side);
   SQuote q;
   if(!CMarket::Quote(_Symbol, q))
     {
      Clock();
      Fail(idOpen, "open " + name + " with SL/TP", "no quote for " + _Symbol);
      return;
     }
   double sl = (side == SIDE_BUY) ? RdRoundPriceDown(m_s, q.bid - m_dist) : RdRoundPriceUp(m_s, q.ask + m_dist);
   double tp = (side == SIDE_BUY) ? RdRoundPriceUp(m_s, q.ask + m_dist) : RdRoundPriceDown(m_s, q.bid - m_dist);

   //--- open
   Clock();
   STradeOutcome out;
   SResult r;
   bool ok = m_gw.OpenMarket(_Symbol, side, m_volume, sl, tp, out, r);
   SPosition p;
   if(out.ticket > 0 && m_gw.SelectPosition(out.ticket, p))
      Track(m_positions, out.ticket);
   if(!ok)
     {
      Fail(idOpen, "open " + name + " with SL/TP", r.message);
      return;
     }
   Pass(idOpen, "open " + name + " with SL/TP", OutcomeText(out));
   ulong ticket = out.ticket;
   Settle();

   //--- verify (G-01 verified already; this is the independent check)
   string idVerify = fullTest ? "M02" : idOpen + "v";
   Clock();
   if(!m_gw.SelectPosition(ticket, p))
     {
      Fail(idVerify, "verify " + name + " SL/TP", "position " + RdTicketText(ticket) + " not found");
      return;
     }
   string seen = "sl " + Px(p.sl) + " tp " + Px(p.tp) + " vol " + Lots(p.volume) + " magic " + IntegerToString(p.magic);
   if(LevelEq(p.sl, sl) && LevelEq(p.tp, tp) && RdVolEq(p.volume, out.volume) && p.magic == InpSmokeMagic)
      Pass(idVerify, "verify " + name + " SL/TP", seen);
   else
      Fail(idVerify, "verify " + name + " SL/TP", seen + ", expected sl " + Px(sl) + " tp " + Px(tp) + " vol " + Lots(out.volume));

   if(fullTest)
     {
      //--- M03 modify SL (tighter, still beyond the stops level)
      Clock();
      double newSl = (side == SIDE_BUY) ? RdRoundPriceDown(m_s, p.open - 0.6 * m_dist) : RdRoundPriceUp(m_s, p.open + 0.6 * m_dist);
      if(m_gw.ModifyPositionSLTP(ticket, newSl, p.tp, r) && m_gw.SelectPosition(ticket, p) && LevelEq(p.sl, newSl))
         Pass("M03", "modify SL", "sl " + Px(newSl) + " tp " + Px(p.tp));
      else
         Fail("M03", "modify SL", r.ok ? "server shows sl " + Px(p.sl) + ", expected " + Px(newSl) : r.message);
      Settle();

      //--- M04 partial close
      Clock();
      SPlanSettings plan;
      plan.Defaults();
      SPartialClose pc;
      SResult pr;
      if(!CRiskMath::PartialClose(p.volume, m_s, plan, pc, pr))
         Skip("M04", "partial close", pr.message);
      else
        {
         STradeOutcome half;
         double keepSl = p.sl;
         if(!m_gw.ClosePosition(ticket, pc.closeVolume, half, r))
            Fail("M04", "partial close", r.message);
         else
           {
            ulong rest = (half.remainder > 0) ? half.remainder : ticket;
            SPosition rp;
            bool found = m_gw.SelectPosition(rest, rp);
            if(rest != ticket)
              {
               Untrack(m_positions, ticket);
               Track(m_positions, rest);
              }
            string detail = "closed " + Lots(half.volume) + ", rest " + (found ? Lots(rp.volume) : "?") + " " +
                            RdTicketText(rest) + (rest != ticket ? " (new ticket)" : " (same ticket)") +
                            (half.profitKnown ? ", P/L " + RdMoney(m_acc, half.profit) : "");
            if(found && RdVolEq(rp.volume, pc.remainVolume) && LevelEq(rp.sl, keepSl))
               Pass("M04", "partial close", detail);
            else
               Fail("M04", "partial close", detail + ", expected rest " + Lots(pc.remainVolume) + " with sl " + Px(keepSl) +
                    (found ? " (sl now " + Px(rp.sl) + ")" : ""));
            ticket = rest;
           }
        }
      Settle();
     }

   //--- close what is left
   string closeStep = fullTest ? "close the rest" : "close " + name;
   Clock();
   STradeOutcome closed;
   if(!m_gw.ClosePosition(ticket, 0.0, closed, r))
     {
      Fail(idClose, closeStep, r.message);
      return;
     }
   Settle();
   if(m_gw.SelectPosition(ticket, p))
     {
      Fail(idClose, closeStep, "position " + RdTicketText(ticket) + " still open with " + Lots(p.volume) + " lot");
      return;
     }
   Untrack(m_positions, ticket);
   Pass(idClose, closeStep, Lots(closed.volume) + " lot @" + Px(closed.price) +
        (closed.profitKnown ? " P/L " + RdMoney(m_acc, closed.profit) : "") +
        (closed.filling != "" ? " fill=" + closed.filling : ""));
  }

//+------------------------------------------------------------------+
//| P01-P03: Buy Limit 2 x distance below Ask, then moved down by    |
//| half a distance with SL and TP (an entry drag, OP-16), deleted.  |
//+------------------------------------------------------------------+
void CGatewaySmoke::PendingSequence()
  {
   SQuote q;
   Clock();
   if(!CMarket::Quote(_Symbol, q))
     {
      Fail("P01", "place buy limit", "no quote for " + _Symbol);
      return;
     }
   double entry = RdRoundPriceDown(m_s, q.ask - 2.0 * m_dist);
   double sl = RdRoundPriceDown(m_s, entry - m_dist);
   double tp = RdRoundPriceUp(m_s, entry + m_dist);

   STradeOutcome out;
   SResult r;
   bool ok = m_gw.PlacePending(_Symbol, SIDE_BUY, KIND_LIMIT, m_volume, entry, sl, tp, out, r);
   SOrder o;
   ZeroMemory(o);
   if(out.ticket > 0 && m_gw.SelectPending(out.ticket, o))
      Track(m_orders, out.ticket);
   if(!ok)
     {
      Fail("P01", "place buy limit", r.message);
      return;
     }
   ulong ticket = out.ticket;
   if(m_gw.SelectPending(ticket, o) && RdPriceEq(m_s, o.price, entry) && LevelEq(o.sl, sl) && LevelEq(o.tp, tp))
      Pass("P01", "place buy limit", OutcomeText(out) + " sl " + Px(o.sl) + " tp " + Px(o.tp));
   else
      Fail("P01", "place buy limit", OutcomeText(out) + " - server shows @" + Px(o.price) + " sl " + Px(o.sl) + " tp " + Px(o.tp));
   Settle();

   Clock();
   double shift = RdNormalizePrice(m_s, 0.5 * m_dist);
   double e2 = RdNormalizePrice(m_s, entry - shift);
   double sl2 = RdNormalizePrice(m_s, sl - shift);
   double tp2 = RdNormalizePrice(m_s, tp - shift);
   if(m_gw.ModifyPending(ticket, e2, sl2, tp2, r) && m_gw.SelectPending(ticket, o) &&
      RdPriceEq(m_s, o.price, e2) && LevelEq(o.sl, sl2) && LevelEq(o.tp, tp2))
      Pass("P02", "modify price/SL/TP", "@" + Px(e2) + " sl " + Px(sl2) + " tp " + Px(tp2));
   else
      Fail("P02", "modify price/SL/TP", r.ok ? "server shows @" + Px(o.price) + " sl " + Px(o.sl) + " tp " + Px(o.tp) : r.message);
   Settle();

   Clock();
   if(!m_gw.DeletePending(ticket, r))
     {
      Fail("P03", "delete", r.message);
      return;
     }
   Settle();
   if(m_gw.SelectPending(ticket, o))
     {
      Fail("P03", "delete", "order " + RdTicketText(ticket) + " is still pending");
      return;
     }
   Untrack(m_orders, ticket);
   Pass("P03", "delete", RdTicketText(ticket) + " deleted");
  }

//+------------------------------------------------------------------+
//| Whatever this run left open is closed or deleted, and reported.  |
//+------------------------------------------------------------------+
void CGatewaySmoke::Cleanup()
  {
   SResult r;
   for(int i = ArraySize(m_positions) - 1; i >= 0; i--)
     {
      Clock();
      STradeOutcome out;
      ulong t = m_positions[i];
      if(m_gw.ClosePosition(t, 0.0, out, r))
         Pass("X01", "cleanup: close " + RdTicketText(t), r.message);
      else
         Fail("X01", "cleanup: close " + RdTicketText(t), r.message + " - CLOSE IT BY HAND");
     }
   ArrayResize(m_positions, 0);
   for(int j = ArraySize(m_orders) - 1; j >= 0; j--)
     {
      Clock();
      ulong t = m_orders[j];
      if(m_gw.DeletePending(t, r))
         Pass("X02", "cleanup: delete " + RdTicketText(t), r.message);
      else
         Fail("X02", "cleanup: delete " + RdTicketText(t), r.message + " - DELETE IT BY HAND");
     }
   ArrayResize(m_orders, 0);
  }

//+------------------------------------------------------------------+
//| Experts tab table + appended block in the smoke file + Alert.    |
//+------------------------------------------------------------------+
void SmokeAdd(string &lines[], const string text)
  {
   int n = ArraySize(lines);
   ArrayResize(lines, n + 1);
   lines[n] = text;
  }

void CGatewaySmoke::Report()
  {
   string all[];
   SmokeAdd(all, "");
   SmokeAdd(all, "# " + RD_PRODUCT + " GatewaySmoke " + RD_VERSION + " - " +
            TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + " - " + _Symbol);
   SmokeAdd(all, "[run]");
   for(int i = 0; i < ArraySize(m_info); i++)
      SmokeAdd(all, m_info[i]);
   SmokeAdd(all, "[results]");
   SmokeAdd(all, "  " + RdPadRight("ID", 5) + RdPadRight("STEP", RD_SMOKE_STEP_WIDTH) + RdPadRight("RESULT", 8) +
            RdPadRight("MS", 7) + "DETAIL");
   for(int j = 0; j < ArraySize(m_rows); j++)
      SmokeAdd(all, "  " + RdPadRight(m_rows[j].id, 5) + RdPadRight(m_rows[j].step, RD_SMOKE_STEP_WIDTH) +
               RdPadRight(m_rows[j].result, 8) + RdPadRight(IntegerToString((long)m_rows[j].ms), 7) + m_rows[j].detail);
   string summary = "PASS " + IntegerToString(m_pass) + ", FAIL " + IntegerToString(m_fail) + ", SKIP " + IntegerToString(m_skip);
   SmokeAdd(all, "[summary]");
   SmokeAdd(all, "  " + summary);
   int n = ArraySize(all);

   for(int p = 0; p < n; p++)
      if(all[p] != "")
         Print(all[p]);

   string file = StringFormat("RiskDesk\\smoke_%s_%s_%s_%s.txt", SmokeSanitize(m_acc.company), RD_PLATFORM,
                              IntegerToString(m_acc.login), SmokeDate());
   ResetLastError();
   int h = FileOpen(file, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI, '\t', CP_UTF8);
   if(h == INVALID_HANDLE)
      RD_LOG_WARN("GatewaySmoke: cannot write " + file + " (error " + IntegerToString(GetLastError()) + ")");
   else
     {
      FileSeek(h, 0, SEEK_END);
      for(int q = 0; q < n; q++)
         FileWriteString(h, all[q] + "\r\n");
      FileClose(h);
      RD_LOG_INFO("GatewaySmoke report appended to " + RD_MQL_DIR + "\\Files\\" + file);
     }
   Alert("GatewaySmoke " + _Symbol + ": " + summary + (m_fail > 0 ? " - see the Experts tab" : ""));
  }

// Letters and digits only: "IC Markets (EU) Ltd" -> "ICMarketsEULtd".
string SmokeSanitize(const string text)
  {
   string out = "";
   int n = StringLen(text);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(text, i);
      if((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
         out += ShortToString(c);
     }
   return (out == "") ? "unknown" : out;
  }

string SmokeDate()
  {
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
  }

//+------------------------------------------------------------------+
void CGatewaySmoke::Run()
  {
   if(Prepare())
     {
      if(!Confirmed())
        {
         Clock();
         Skip("S01", "confirmation", "cancelled by the user - nothing sent");
        }
      else
        {
         MarketSequence(SIDE_BUY, "M01", "M05", true);
         Settle();
         if(InpTestSell)
           {
            MarketSequence(SIDE_SELL, "M06", "M07", false);
            Settle();
           }
         else
           {
            Clock();
            Skip("M06", "open sell with SL/TP", "InpTestSell=false");
           }
         if(InpTestPending)
            PendingSequence();
         else
           {
            Clock();
            Skip("P01", "place buy limit", "InpTestPending=false");
           }
         Cleanup();
        }
     }
   Report();
  }

//+------------------------------------------------------------------+
//| Entry point used by GatewaySmoke.mq4 / .mq5.                     |
//+------------------------------------------------------------------+
void SmokeRun()
  {
   CLogger::Configure(LOGLEVEL_INFO, true, RD_PRODUCT + " smoke " + _Symbol);
   RD_LOG_INFO("GatewaySmoke " + RD_VERSION + " on " + _Symbol + " (" + RD_PLATFORM + ")");
   int waited = 0;
   if(!CAccountSpec::WaitReady(15000, waited))
      RD_LOG_WARN("GatewaySmoke: account data still incomplete after " + IntegerToString(waited) + " ms");
   else
      if(waited > 0)
         RD_LOG_INFO("GatewaySmoke: waited " + IntegerToString(waited) + " ms for the account data after login");
   CGatewaySmoke smoke;
   smoke.Run();
  }

#endif // RD_SCRIPTS_GATEWAYSMOKECORE_MQH
