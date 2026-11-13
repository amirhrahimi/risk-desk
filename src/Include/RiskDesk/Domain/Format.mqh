//+------------------------------------------------------------------+
//| RiskDesk - Domain/Format.mqh                                     |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : display formatting shared by the Domain messages and   |
//|           the UI (04-risk-engine section 11, BC-12): money in    |
//|           the account currency with thousands separators,        |
//|           percent, lots with the step's decimals, prices, points |
//|           and order names; cent accounts (F-24); the names of    |
//|           MetaTrader's trade objects (F-20) and of screenshots   |
//|           (F-19, OP-14).                                         |
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

//====================================================================
// Cent accounts (F-24, BC-12). Lot math is unchanged: every amount is
// in the account currency; only the display adds the major unit.
//====================================================================

// BC-12: USC/EUC/GBC/USc/EUc, or any currency containing "cent".
bool RdIsCentCurrency(const string currency)
  {
   if(currency == "USC" || currency == "EUC" || currency == "GBC" || currency == "USc" || currency == "EUc")
      return true;
   string lower = currency;
   StringToLower(lower);
   return StringFind(lower, "cent") >= 0;
  }

// "US" -> "USD", "EU" -> "EUR", "GB" -> "GBP"; "" for anything else.
string RdCentMajorOf2(const string two)
  {
   if(two == "US")
      return "USD";
   if(two == "EU")
      return "EUR";
   if(two == "GB")
      return "GBP";
   return "";
  }

// The major unit of a cent currency: USC / USc -> USD, EUC / EUc -> EUR,
// GBC -> GBP; "USDcent", "USD Cent", "EUR_cent" -> the three letters left
// without "cent". "" when it cannot be told (the major amount is then
// shown as a plain number).
string RdCentMajor(const string currency)
  {
   string up = currency;
   StringToUpper(up);
   if(StringLen(up) == 3 && StringGetCharacter(up, 2) == 'C' && RdCentMajorOf2(StringSubstr(up, 0, 2)) != "")
      return RdCentMajorOf2(StringSubstr(up, 0, 2));
   int at = StringFind(up, "CENT");
   if(at < 0)
      return "";
   string rest = StringSubstr(up, 0, at) + StringSubstr(up, at + 4);
   string letters = "";
   for(int i = 0; i < StringLen(rest); i++)
     {
      ushort c = StringGetCharacter(rest, i);
      if(c >= 'A' && c <= 'Z')
         letters += ShortToString(c);
     }
   if(StringLen(letters) == 3)
      return letters;
   if(StringLen(letters) == 2)
      return RdCentMajorOf2(letters);
   return "";
  }

//+------------------------------------------------------------------+
//| F-24 display, applied right after the account is read            |
//| (CAccountSpec::Read): CENT_ON, or CENT_AUTO on a cent currency,  |
//| shows money as "-1,000.00 USC ($10.00)" with 'divisor' cents per |
//| major unit. CENT_ON on a currency that is no cent code (a server |
//| that reports cents as "USD", D38): unit USC / EUC / GBC for      |
//| USD / EUR / GBP, else "<ccy> cents"; the major is the currency.  |
//+------------------------------------------------------------------+
void RdApplyCent(SAccountSpec &a, const ECentMode mode, const double divisor)
  {
   a.isCent = RdIsCentCurrency(a.currency);
   a.centShow = (mode == CENT_ON) || (mode == CENT_AUTO && a.isCent);
   a.centDivisor = (divisor > 0.0) ? divisor : 100.0;
   a.centUnit = "";
   a.centMajor = "";
   if(!a.centShow)
      return;
   if(a.isCent)
     {
      a.centUnit = a.currency;
      a.centMajor = RdCentMajor(a.currency);
      return;
     }
   a.centMajor = a.currency;
   if(a.currency == "USD")
      a.centUnit = "USC";
   else
      if(a.currency == "EUR")
         a.centUnit = "EUC";
      else
         if(a.currency == "GBP")
            a.centUnit = "GBC";
         else
            a.centUnit = a.currency + " cents";
  }

// Money in the account's currency with its decimals; cent accounts add
// the major unit (F-24 AC2): "-1,000.00 USC (-$10.00)".
string RdMoney(const SAccountSpec &acc, const double amount)
  {
   if(!acc.centShow || !(acc.centDivisor > 0.0))
      return RdFormatMoney(amount, acc.currency, acc.digitsCcy);
   return RdFormatMoney(amount, acc.centUnit, acc.digitsCcy) + " (" +
          RdFormatMoney(amount / acc.centDivisor, acc.centMajor, 2) + ")";
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

//====================================================================
// MetaTrader's trade objects (F-20)
//====================================================================

//+------------------------------------------------------------------+
//| The terminal names the arrows and lines it draws for a trade     |
//| "#<ticket> ...": "#12345678 buy 0.10 EURUSD at 1.10000",         |
//| "#12345678 1.10000 -> 1.10120". True, with the ticket, when      |
//| 'name' is '#', 1-19 digits and a space. Whether the ticket is a  |
//| closed trade of the chart's symbol is checked against the        |
//| account history (Platform/History) before anything is deleted.   |
//+------------------------------------------------------------------+
bool RdTradeObjectTicket(const string name, ulong &ticket)
  {
   ticket = 0;
   int n = StringLen(name);
   if(n < 3 || StringGetCharacter(name, 0) != '#')
      return false;
   int i = 1;
   ulong value = 0;
   while(i < n && i <= 19)
     {
      ushort c = StringGetCharacter(name, i);
      if(c < '0' || c > '9')
         break;
      value = value * 10 + (ulong)(c - '0');
      i++;
     }
   if(i == 1 || i >= n || StringGetCharacter(name, i) != ' ' || value == 0)
      return false;
   ticket = value;
   return true;
  }

//====================================================================
// Screenshot names (F-19 AC1, OP-14)
//====================================================================

// OP-14: / \ : * ? " < > | (and spaces) -> _
string RdSanitizeFileText(const string text)
  {
   string s = text;
   string bad[] = {"/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "};
   for(int i = 0; i < ArraySize(bad); i++)
      StringReplace(s, bad[i], "_");
   return s;
  }

// PERIOD_H1 -> "H1"
string RdTimeframeText(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   if(StringFind(s, "PERIOD_") == 0)
      s = StringSubstr(s, 7);
   return s;
  }

// <login>_<symbol>_<TF>_<yyyy-mm-dd_HH-MM-SS>_<action>_<ticket>.png
string RdShotFileName(const long login, const string symbol, const ENUM_TIMEFRAMES tf, const datetime when,
                      const string action, const ulong ticket)
  {
   string t = TimeToString(when, TIME_DATE | TIME_SECONDS);   // 2026.11.12 10:43:21
   StringReplace(t, ".", "-");
   StringReplace(t, " ", "_");
   StringReplace(t, ":", "-");
   return IntegerToString(login) + "_" + RdSanitizeFileText(symbol) + "_" + RdTimeframeText(tf) + "_" + t + "_" +
          RdSanitizeFileText(action) + "_" + IntegerToString((long)ticket) + ".png";
  }

#endif // RD_DOMAIN_FORMAT_MQH
