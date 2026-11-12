//+------------------------------------------------------------------+
//| RiskDesk - Domain/Format.mqh                                     |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : display formatting shared by the Domain messages and   |
//|           the UI (04-risk-engine section 11, BC-12): money in    |
//|           the account currency with thousands separators,        |
//|           percent, lots with the step's decimals, prices, points |
//|           and order names.                                       |
//|           Sources stay ASCII: the currency signs are built from  |
//|           their Unicode code points (ADR-018).                   |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_FORMAT_MQH
#define RD_DOMAIN_FORMAT_MQH

#include "Types.mqh"
#include "PriceMath.mqh"

// BC-12: "$", euro, pound, yen sign for USD/EUR/GBP/JPY; "" for every
// other currency, which is then shown as an ISO code after the amount.
string RdCurrencySymbol(const string ccy)
  {
   if(ccy == "USD")
      return "$";
   if(ccy == "EUR")
      return ShortToString((ushort)0x20AC);
   if(ccy == "GBP")
      return ShortToString((ushort)0x00A3);
   if(ccy == "JPY")
      return ShortToString((ushort)0x00A5);
   return "";
  }

// "1234567" -> "1,234,567"
string RdGroupThousands(const string digits)
  {
   int n = StringLen(digits);
   string text = "";
   for(int i = 0; i < n; i++)
     {
      if(i > 0 && (n - i) % 3 == 0)
         text += ",";
      text += StringSubstr(digits, i, 1);
     }
   return text;
  }

// "$1,234.50", "-<euro>60.00", "1,234.56 CHF", "60.00 USC".
// No minus sign when the amount rounds to zero.
string RdFormatMoney(const double amount, const string ccy, const int decimals = 2)
  {
   if(!MathIsValidNumber(amount))
      return "n/a";
   int d = decimals;
   if(d < 0)
      d = 0;
   if(d > 8)
      d = 8;
   string text = DoubleToString(MathAbs(amount), d);
   int dot = StringFind(text, ".");
   string whole = (dot < 0) ? text : StringSubstr(text, 0, dot);
   string frac = (dot < 0) ? "" : StringSubstr(text, dot);
   text = RdGroupThousands(whole) + frac;
   string sign = RdCurrencySymbol(ccy);
   if(sign != "")
      text = sign + text;
   else
      if(ccy != "")
         text = text + " " + ccy;
   if(amount < 0.0 && MathAbs(amount) >= 0.5 * MathPow(10.0, -d))
      text = "-" + text;
   return text;
  }

// Money in the account's currency with its decimals.
string RdMoney(const SAccountSpec &acc, const double amount)
  {
   return RdFormatMoney(amount, acc.currency, acc.digitsCcy);
  }

// "1.20 %"
string RdFormatPct(const double pct)
  {
   if(!MathIsValidNumber(pct))
      return "n/a %";
   return DoubleToString(pct, 2) + " %";
  }

// A cap from the settings without trailing zeros: "10 %", "7.5 %".
string RdFormatCapPct(const double pct)
  {
   return RdNum(pct, 2) + " %";
  }

string RdFormatPrice(const SSymbolSpec &s, const double price)
  {
   return DoubleToString(price, s.digits);
  }

// Lots with the decimals of the symbol's volume grid: "0.50", "1", "2.3".
string RdFormatLots(const SSymbolSpec &s, const double lots)
  {
   return DoubleToString(lots, RdLotDigits(s));
  }

string RdFormatPoints(const int points)
  {
   return IntegerToString(points) + " pts";
  }

string RdTicketText(const ulong ticket)
  {
   return "#" + IntegerToString((long)ticket);
  }

// "buy" / "sell", for sentences ("SL above Bid for a buy").
string RdSideText(const ESide side)
  {
   return (side == SIDE_BUY) ? "buy" : "sell";
  }

// "Buy", "Sell", "Buy Limit", "Sell Stop" ...
string RdOrderText(const ESide side, const EOrderKind kind)
  {
   string name = (side == SIDE_BUY) ? "Buy" : "Sell";
   if(kind == KIND_LIMIT)
      return name + " Limit";
   if(kind == KIND_STOP)
      return name + " Stop";
   return name;
  }

#endif // RD_DOMAIN_FORMAT_MQH
