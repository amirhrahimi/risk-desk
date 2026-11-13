// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Domain/Validators.mqh                                 |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : every "is this allowed?" rule that needs no terminal:  |
//|           - ParseRiskPct: the Risk % field (F-02, V-21)          |
//|           - PreviewSide / MarketSide: market orders (04 sec. 6)  |
//|           - ClassifyPending / PendingGeometry: pending order     |
//|             type and SL/TP sides (04 section 7)                  |
//|           - MarketStops / PendingStops: stops level (BC-07)      |
//|           - PositionNotFrozen / PendingNotFrozen: freeze level   |
//|             (BC-07)                                              |
//|           - VolumeLimit: MT5 SYMBOL_VOLUME_LIMIT (BC-04)         |
//| Prices passed in must already be normalized to the tick size.   |
//| A price of 0 means "not set" for SL and TP.                      |
//| Messages are final status-bar text without a "Refused:" prefix.  |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_VALIDATORS_MQH
#define RD_DOMAIN_VALIDATORS_MQH

#include "Types.mqh"
#include "PriceMath.mqh"
#include "Format.mqh"

class CValidators
  {
private:
   static bool       IsDigit(const ushort c) { return c >= '0' && c <= '9'; }
   static string     TooClose(const string what, const string ref, const string forWhat, const SSymbolSpec &s,
                              const double minDist, const double limit, const bool lower);
   static string     Frozen(const string what, const string ref, const SSymbolSpec &s);

public:
   static bool       ParseRiskPct(const string text, const double maxPct, double &pct, SResult &r);
   static bool       QuoteOk(const SQuote &q, const SSymbolSpec &s, SResult &r);
   static bool       PreviewSide(const double sl, const SQuote &q, const SSymbolSpec &s, ESide &side, SResult &r);
   static bool       MarketSide(const ESide side, const double sl, const double tp, const SQuote &q,
                                const SSymbolSpec &s, SResult &r);
   static bool       MarketStops(const ESide side, const double sl, const double tp, const SQuote &q,
                                 const SSymbolSpec &s, SResult &r);
   static bool       ClassifyPending(const double entry, const double sl, const double tp, const SQuote &q,
                                     const SSymbolSpec &s, ESide &side, EOrderKind &kind, SResult &r);
   static bool       PendingGeometry(const ESide side, const EOrderKind kind, const double entry, const double sl,
                                     const double tp, const SQuote &q, const SSymbolSpec &s, SResult &r);
   static bool       PendingStops(const ESide side, const EOrderKind kind, const double entry, const double sl,
                                  const double tp, const SQuote &q, const SSymbolSpec &s, SResult &r);
   static bool       PositionNotFrozen(const ESide side, const double sl, const double tp, const SQuote &q,
                                       const SSymbolSpec &s, SResult &r);
   static bool       PendingNotFrozen(const ESide side, const EOrderKind kind, const double entry,
                                      const SQuote &q, const SSymbolSpec &s, SResult &r);
   static bool       VolumeLimit(const SSymbolSpec &s, const double sameSideVolume, const double lots, SResult &r);
  };

//+------------------------------------------------------------------+
//| "SL too close to Bid: needs >= 30 pts (0.00030), move it to      |
//|  1.09970 or lower"                                               |
//+------------------------------------------------------------------+
string CValidators::TooClose(const string what, const string ref, const string forWhat, const SSymbolSpec &s,
                             const double minDist, const double limit, const bool lower)
  {
   return what + " too close to " + ref + forWhat + ": needs >= " + RdFormatPoints(s.stopsLevel) +
          " (" + RdFormatPrice(s, minDist) + "), move it to " + RdFormatPrice(s, limit) +
          (lower ? " or lower" : " or higher");
  }

string CValidators::Frozen(const string what, const string ref, const SSymbolSpec &s)
  {
   return what + " is within the freeze level (" + RdFormatPoints(s.freezeLevel) + ") of " + ref +
          " - the broker blocks changes until price moves away";
  }

//+------------------------------------------------------------------+
//| F-02 / V-21: digits with one '.' or ',' decimal separator, an    |
//| optional leading sign and trailing '%'. Rounded to the 2 shown   |
//| decimals, then 0 < pct <= maxPct.                                |
//+------------------------------------------------------------------+
bool CValidators::ParseRiskPct(const string text, const double maxPct, double &pct, SResult &r)
  {
   pct = 0.0;
   r.Reset();
   string s = RdTrim(text);
   int n = StringLen(s);
   if(n > 0 && StringGetCharacter(s, n - 1) == '%')
     {
      s = RdTrim(StringSubstr(s, 0, n - 1));
      n = StringLen(s);
     }
   if(n == 0)
      return RdFail(r, "Enter a risk % such as 1 or 0.5");

   string notNumber = "Risk % \"" + RdTrim(text) + "\" is not a number - use digits and . or , (e.g. 1.5)";
   int digits = 0;
   int separators = 0;
   string clean = "";
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(s, i);
      if(IsDigit(c))
        {
         digits++;
         clean += ShortToString(c);
        }
      else
         if(c == '.' || c == ',')
           {
            separators++;
            clean += ".";
           }
         else
            if(i == 0 && c == '-')
               clean += "-";
            else
               if(!(i == 0 && c == '+'))
                  return RdFail(r, notNumber);
     }
   if(digits == 0 || separators > 1)
      return RdFail(r, notNumber);
   // "5." -> "5.0", ".5" -> "0.5", "-.5" -> "-0.5": plain digits for StringToDouble
   if(StringGetCharacter(clean, StringLen(clean) - 1) == '.')
      clean += "0";
   int lead = (StringGetCharacter(clean, 0) == '-') ? 1 : 0;
   if(StringGetCharacter(clean, lead) == '.')
      clean = StringSubstr(clean, 0, lead) + "0" + StringSubstr(clean, lead);

   double value = NormalizeDouble(StringToDouble(clean), 2);
   if(!MathIsValidNumber(value) || value <= 0.0)
      return RdFail(r, "Risk % must be above 0");
   if(value > maxPct + RD_PCT_EPS)
      return RdFail(r, "Risk % cannot be above " + RdFormatCapPct(maxPct) + " per trade (entered " +
                    RdNum(value, 2) + " %)");
   pct = value;
   return RdOk(r, "Risk " + RdFormatPct(value));
  }

//+------------------------------------------------------------------+
bool CValidators::QuoteOk(const SQuote &q, const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(!(q.bid > 0.0) || !(q.ask > 0.0))
      return RdFail(r, "No quote for " + s.name + " (Bid " + RdFormatPrice(s, q.bid) + ", Ask " +
                    RdFormatPrice(s, q.ask) + ")");
   if(RdPriceLt(s, q.ask, q.bid))
      return RdFail(r, "Invalid quote for " + s.name + ": Ask " + RdFormatPrice(s, q.ask) + " below Bid " +
                    RdFormatPrice(s, q.bid));
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| F-03 / 04 section 6: SL below Bid -> BUY, above Ask -> SELL,     |
//| otherwise none ("SL inside spread").                             |
//+------------------------------------------------------------------+
bool CValidators::PreviewSide(const double sl, const SQuote &q, const SSymbolSpec &s, ESide &side, SResult &r)
  {
   side = SIDE_BUY;
   r.Reset();
   if(!(sl > 0.0))
      return RdFail(r, "No SL line");
   if(RdPriceLt(s, sl, q.bid))
      return RdOk(r, "");
   if(RdPriceGt(s, sl, q.ask))
     {
      side = SIDE_SELL;
      return RdOk(r, "");
     }
   return RdFail(r, "SL inside spread (SL " + RdFormatPrice(s, sl) + ", Bid " + RdFormatPrice(s, q.bid) +
                 ", Ask " + RdFormatPrice(s, q.ask) + ")");
  }

//+------------------------------------------------------------------+
//| 04 section 6 + BC-07 for a market order:                         |
//|   Buy  valid <=> sl < bid AND (no TP or tp > bid) AND distances  |
//|   Sell valid <=> sl > ask AND (no TP or tp < ask) AND distances  |
//+------------------------------------------------------------------+
bool CValidators::MarketSide(const ESide side, const double sl, const double tp, const SQuote &q,
                             const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(!(sl > 0.0))
      return RdFail(r, "No SL line - click Add Line first");
   if(side == SIDE_BUY)
     {
      if(!RdPriceLt(s, sl, q.bid))
         return RdFail(r, (RdPriceEq(s, sl, q.bid) ? "SL at Bid for a buy" : "SL above Bid for a buy") +
                       " (SL " + RdFormatPrice(s, sl) + ", Bid " + RdFormatPrice(s, q.bid) + ")");
      if(tp > 0.0 && !RdPriceGt(s, tp, q.bid))
         return RdFail(r, (RdPriceEq(s, tp, q.bid) ? "TP at Bid for a buy" : "TP below Bid for a buy") +
                       " (TP " + RdFormatPrice(s, tp) + ", Bid " + RdFormatPrice(s, q.bid) + ")");
     }
   else
     {
      if(!RdPriceGt(s, sl, q.ask))
         return RdFail(r, (RdPriceEq(s, sl, q.ask) ? "SL at Ask for a sell" : "SL below Ask for a sell") +
                       " (SL " + RdFormatPrice(s, sl) + ", Ask " + RdFormatPrice(s, q.ask) + ")");
      if(tp > 0.0 && !RdPriceLt(s, tp, q.ask))
         return RdFail(r, (RdPriceEq(s, tp, q.ask) ? "TP at Ask for a sell" : "TP above Ask for a sell") +
                       " (TP " + RdFormatPrice(s, tp) + ", Ask " + RdFormatPrice(s, q.ask) + ")");
     }
   return MarketStops(side, sl, tp, q, s, r);
  }

//+------------------------------------------------------------------+
//| BC-07 market orders (buys close at Bid, sells at Ask):           |
//|   Buy : Bid - SL >= S, TP - Bid >= S                             |
//|   Sell: SL - Ask >= S, Ask - TP >= S                             |
//+------------------------------------------------------------------+
bool CValidators::MarketStops(const ESide side, const double sl, const double tp, const SQuote &q,
                              const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   double stops = s.stopsLevel * s.point;
   if(side == SIDE_BUY)
     {
      if(sl > 0.0 && !RdDistAtLeast(s, q.bid, sl, stops))
         return RdFail(r, TooClose("SL", "Bid", "", s, stops, RdRoundPriceDown(s, q.bid - stops), true));
      if(tp > 0.0 && !RdDistAtLeast(s, tp, q.bid, stops))
         return RdFail(r, TooClose("TP", "Bid", "", s, stops, RdRoundPriceUp(s, q.bid + stops), false));
     }
   else
     {
      if(sl > 0.0 && !RdDistAtLeast(s, sl, q.ask, stops))
         return RdFail(r, TooClose("SL", "Ask", "", s, stops, RdRoundPriceUp(s, q.ask + stops), false));
      if(tp > 0.0 && !RdDistAtLeast(s, q.ask, tp, stops))
         return RdFail(r, TooClose("TP", "Ask", "", s, stops, RdRoundPriceDown(s, q.ask - stops), true));
     }
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| 04 section 7 (F-08). On success r.message is the order name      |
//| ("Buy Stop"). side/kind are filled as far as they could be       |
//| decided, also on failure (the Pending Info field shows them).    |
//| BC-07 distances are a separate step: PendingStops.               |
//+------------------------------------------------------------------+
bool CValidators::ClassifyPending(const double entry, const double sl, const double tp, const SQuote &q,
                                  const SSymbolSpec &s, ESide &side, EOrderKind &kind, SResult &r)
  {
   side = SIDE_BUY;
   kind = KIND_MARKET;
   r.Reset();
   if(!(entry > 0.0))
      return RdFail(r, "No entry line - click Add Pend Line first");
   if(!(sl > 0.0))
      return RdFail(r, "No SL line - click Add Pend Line first");
   if(RdPriceEq(s, entry, sl))
      return RdFail(r, "Entry and SL are equal");

   bool isLong = RdPriceLt(s, sl, entry);
   side = isLong ? SIDE_BUY : SIDE_SELL;
   if(isLong)
     {
      if(RdPriceEq(s, entry, q.ask))
         return RdFail(r, "Entry at market - use Buy");
      kind = RdPriceGt(s, entry, q.ask) ? KIND_STOP : KIND_LIMIT;
     }
   else
     {
      if(RdPriceEq(s, entry, q.bid))
         return RdFail(r, "Entry at market - use Sell");
      kind = RdPriceLt(s, entry, q.bid) ? KIND_STOP : KIND_LIMIT;
     }
   if(!PendingGeometry(side, kind, entry, sl, tp, q, s, r))
      return false;
   return RdOk(r, RdOrderText(side, kind));
  }

//+------------------------------------------------------------------+
//| The order type stays valid: a Buy Stop above Ask, a Buy Limit    |
//| below Ask, a Sell Stop below Bid, a Sell Limit above Bid; SL and |
//| TP (when set) on their side of the entry. Used by the planner    |
//| and by moves of placed orders (OP-16).                           |
//+------------------------------------------------------------------+
bool CValidators::PendingGeometry(const ESide side, const EOrderKind kind, const double entry, const double sl,
                                  const double tp, const SQuote &q, const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(kind == KIND_MARKET)
      return RdFail(r, "Not a pending order type");
   if(!(entry > 0.0))
      return RdFail(r, "No entry price");
   string name = RdOrderText(side, kind);
   bool isBuy = (side == SIDE_BUY);
   double ref = isBuy ? q.ask : q.bid;
   string refName = isBuy ? "Ask" : "Bid";
   bool above = (isBuy == (kind == KIND_STOP));   // Buy Stop and Sell Limit sit above the market
   bool entryOk = above ? RdPriceGt(s, entry, ref) : RdPriceLt(s, entry, ref);
   if(!entryOk)
      return RdFail(r, "A " + name + " must stay " + (above ? "above " : "below ") + refName + " (" +
                    RdFormatPrice(s, ref) + "), entry " + RdFormatPrice(s, entry));
   if(sl > 0.0 && !(isBuy ? RdPriceLt(s, sl, entry) : RdPriceGt(s, sl, entry)))
      return RdFail(r, "SL must be " + (isBuy ? "below" : "above") + " the entry for a " + name);
   if(tp > 0.0 && !(isBuy ? RdPriceGt(s, tp, entry) : RdPriceLt(s, tp, entry)))
      return RdFail(r, "TP on wrong side (must be " + (isBuy ? "above" : "below") + " the entry for a " + name + ")");
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-07 pending orders:                                            |
//|   Buy Limit : Ask - Entry >= S   Sell Limit: Entry - Bid >= S    |
//|   Buy Stop  : Entry - Ask >= S   Sell Stop : Bid - Entry >= S    |
//|   SL and TP at least S from the entry, on their side.            |
//+------------------------------------------------------------------+
bool CValidators::PendingStops(const ESide side, const EOrderKind kind, const double entry, const double sl,
                               const double tp, const SQuote &q, const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(kind == KIND_MARKET)
      return RdFail(r, "Not a pending order type");
   double stops = s.stopsLevel * s.point;
   string forWhat = " for a " + RdOrderText(side, kind);
   if(side == SIDE_BUY)
     {
      if(kind == KIND_LIMIT && !RdDistAtLeast(s, q.ask, entry, stops))
         return RdFail(r, TooClose("Entry", "Ask", forWhat, s, stops, RdRoundPriceDown(s, q.ask - stops), true));
      if(kind == KIND_STOP && !RdDistAtLeast(s, entry, q.ask, stops))
         return RdFail(r, TooClose("Entry", "Ask", forWhat, s, stops, RdRoundPriceUp(s, q.ask + stops), false));
      if(sl > 0.0 && !RdDistAtLeast(s, entry, sl, stops))
         return RdFail(r, TooClose("SL", "the entry", forWhat, s, stops, RdRoundPriceDown(s, entry - stops), true));
      if(tp > 0.0 && !RdDistAtLeast(s, tp, entry, stops))
         return RdFail(r, TooClose("TP", "the entry", forWhat, s, stops, RdRoundPriceUp(s, entry + stops), false));
     }
   else
     {
      if(kind == KIND_LIMIT && !RdDistAtLeast(s, entry, q.bid, stops))
         return RdFail(r, TooClose("Entry", "Bid", forWhat, s, stops, RdRoundPriceUp(s, q.bid + stops), false));
      if(kind == KIND_STOP && !RdDistAtLeast(s, q.bid, entry, stops))
         return RdFail(r, TooClose("Entry", "Bid", forWhat, s, stops, RdRoundPriceDown(s, q.bid - stops), true));
      if(sl > 0.0 && !RdDistAtLeast(s, sl, entry, stops))
         return RdFail(r, TooClose("SL", "the entry", forWhat, s, stops, RdRoundPriceUp(s, entry + stops), false));
      if(tp > 0.0 && !RdDistAtLeast(s, entry, tp, stops))
         return RdFail(r, TooClose("TP", "the entry", forWhat, s, stops, RdRoundPriceDown(s, entry - stops), true));
     }
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-07 freeze level of a position's current SL/TP. Modify and     |
//| close are blocked while Bid - SL <= F or TP - Bid <= F (buy),    |
//| SL - Ask <= F or Ask - TP <= F (sell). F = 0 never blocks: the   |
//| broker has no freeze zone, and a close must stay possible.       |
//+------------------------------------------------------------------+
bool CValidators::PositionNotFrozen(const ESide side, const double sl, const double tp, const SQuote &q,
                                    const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(s.freezeLevel <= 0)
      return RdOk(r, "");
   double freeze = s.freezeLevel * s.point;
   if(side == SIDE_BUY)
     {
      if(sl > 0.0 && !RdDistMoreThan(s, q.bid, sl, freeze))
         return RdFail(r, Frozen("SL", "Bid", s));
      if(tp > 0.0 && !RdDistMoreThan(s, tp, q.bid, freeze))
         return RdFail(r, Frozen("TP", "Bid", s));
     }
   else
     {
      if(sl > 0.0 && !RdDistMoreThan(s, sl, q.ask, freeze))
         return RdFail(r, Frozen("SL", "Ask", s));
      if(tp > 0.0 && !RdDistMoreThan(s, q.ask, tp, freeze))
         return RdFail(r, Frozen("TP", "Ask", s));
     }
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-07 freeze level of a pending order: modify/delete blocked     |
//| while its entry is within F of the activation price (Ask for     |
//| buys, Bid for sells).                                            |
//+------------------------------------------------------------------+
bool CValidators::PendingNotFrozen(const ESide side, const EOrderKind kind, const double entry,
                                   const SQuote &q, const SSymbolSpec &s, SResult &r)
  {
   r.Reset();
   if(s.freezeLevel <= 0)
      return RdOk(r, "");
   double freeze = s.freezeLevel * s.point;
   bool isBuy = (side == SIDE_BUY);
   bool ok = true;
   if(isBuy)
      ok = (kind == KIND_STOP) ? RdDistMoreThan(s, entry, q.ask, freeze) : RdDistMoreThan(s, q.ask, entry, freeze);
   else
      ok = (kind == KIND_STOP) ? RdDistMoreThan(s, q.bid, entry, freeze) : RdDistMoreThan(s, entry, q.bid, freeze);
   if(!ok)
      return RdFail(r, Frozen(RdOrderText(side, kind) + " entry", isBuy ? "Ask" : "Bid", s));
   return RdOk(r, "");
  }

//+------------------------------------------------------------------+
//| BC-04 (MT5): open + pending volume in one direction plus the new |
//| volume must not exceed SYMBOL_VOLUME_LIMIT (0 = unlimited).      |
//+------------------------------------------------------------------+
bool CValidators::VolumeLimit(const SSymbolSpec &s, const double sameSideVolume, const double lots, SResult &r)
  {
   r.Reset();
   if(!(s.volLimit > 0.0))
      return RdOk(r, "");
   if(!RdVolGt(sameSideVolume + lots, s.volLimit))
      return RdOk(r, "");
   double allowed = 0.0;
   if(!RdFloorVolume(s, s.volLimit - sameSideVolume, allowed))
      allowed = 0.0;
   return RdFail(r, "Volume limit on " + s.name + ": " + RdFormatLots(s, s.volLimit) + " lots per direction, " +
                 RdFormatLots(s, sameSideVolume) + " already open or pending - at most " +
                 RdFormatLots(s, allowed) + " more (this trade " + RdFormatLots(s, lots) + ")");
  }

#endif // RD_DOMAIN_VALIDATORS_MQH
