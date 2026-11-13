//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestExtras.mqh                 |
//| Purpose : unit tests of the P7 extras' pure parts:               |
//|           - F-24 cent display (Domain/Format: RdApplyCent,       |
//|             RdMoney), BC-12 detection                            |
//|           - F-20 the names of MetaTrader's trade objects         |
//|             (RdTradeObjectTicket)                                |
//|           - F-19 / OP-14 screenshot names (RdShotFileName)       |
//|           - F-21 candle countdown (Domain/TimeMath: text, red    |
//|             threshold Q20, MN1, market closed, between ticks)    |
//|           - F-32 daily log file names and retention              |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_EXTRAS_MQH
#define RD_TESTS_EXTRAS_MQH

#include "TestRunner.mqh"
#include "TestFixtures.mqh"
#include "..\..\..\Include\RiskDesk\Domain\Format.mqh"
#include "..\..\..\Include\RiskDesk\Domain\TimeMath.mqh"

//+------------------------------------------------------------------+
void TestCentDisplay(CTestRunner &t)
  {
   t.Begin("F-24 cent display (BC-12)");
   string euro = RdCurrencySymbol("EUR");
   ASSERT_TRUE("USC is cent", RdIsCentCurrency("USC"));
   ASSERT_TRUE("USc is cent", RdIsCentCurrency("USc"));
   ASSERT_TRUE("USDcent is cent", RdIsCentCurrency("USDcent"));
   ASSERT_FALSE("USD is not cent", RdIsCentCurrency("USD"));
   ASSERT_EQ_STR("USC -> USD", RdCentMajor("USC"), "USD");
   ASSERT_EQ_STR("EUc -> EUR", RdCentMajor("EUc"), "EUR");
   ASSERT_EQ_STR("GBC -> GBP", RdCentMajor("GBC"), "GBP");
   ASSERT_EQ_STR("USDcent -> USD", RdCentMajor("USDcent"), "USD");
   ASSERT_EQ_STR("USD Cent -> USD", RdCentMajor("USD Cent"), "USD");
   ASSERT_EQ_STR("EUR_cent -> EUR", RdCentMajor("EUR_cent"), "EUR");
   ASSERT_EQ_STR("UScent -> USD", RdCentMajor("UScent"), "USD");
   ASSERT_EQ_STR("cent alone -> unknown", RdCentMajor("cent"), "");
   ASSERT_EQ_STR("CHF -> unknown", RdCentMajor("CHF"), "");

   SAccountSpec a;
   //--- AUTO on a cent currency: the BC-12 example
   TfAccount(a, "USC", 100000.0);
   RdApplyCent(a, CENT_AUTO, 100.0);
   ASSERT_TRUE("AUTO on USC shows cents", a.centShow);
   ASSERT_EQ_STR("SL label money (T-31)", RdMoney(a, 1000.0), "1,000.00 USC ($10.00)");
   ASSERT_EQ_STR("negative P/L", RdMoney(a, -1000.0), "-1,000.00 USC (-$10.00)");
   ASSERT_EQ_STR("major rounded to cents", RdMoney(a, 123.45), "123.45 USC ($1.23)");
   TfAccount(a, "USDcent", 1.0);
   RdApplyCent(a, CENT_AUTO, 100.0);
   ASSERT_EQ_STR("USDcent", RdMoney(a, 250.0), "250.00 USDcent ($2.50)");
   //--- AUTO on a standard currency, OFF on a cent currency: unchanged
   TfAccount(a, "USD", 1000.0);
   RdApplyCent(a, CENT_AUTO, 100.0);
   ASSERT_FALSE("AUTO on USD: no cents", a.centShow);
   ASSERT_EQ_STR("AUTO on USD", RdMoney(a, 1000.0), "$1,000.00");
   TfAccount(a, "USC", 1000.0);
   RdApplyCent(a, CENT_OFF, 100.0);
   ASSERT_FALSE("OFF on USC: no major", a.centShow);
   ASSERT_TRUE("OFF still detects the cent currency", a.isCent);
   ASSERT_EQ_STR("OFF on USC", RdMoney(a, 1000.0), "1,000.00 USC");
   //--- ON on a server that reports cents as a standard code (D38)
   TfAccount(a, "USD", 1000.0);
   RdApplyCent(a, CENT_ON, 100.0);
   ASSERT_EQ_STR("ON on USD", RdMoney(a, 1000.0), "1,000.00 USC ($10.00)");
   TfAccount(a, "EUR", 1000.0);
   RdApplyCent(a, CENT_ON, 100.0);
   ASSERT_EQ_STR("ON on EUR", RdMoney(a, 1000.0), "1,000.00 EUC (" + euro + "10.00)");
   TfAccount(a, "CHF", 1000.0);
   RdApplyCent(a, CENT_ON, 100.0);
   ASSERT_EQ_STR("ON on CHF", RdMoney(a, 1000.0), "1,000.00 CHF cents (10.00 CHF)");
   TfAccount(a, "USD", 1000.0);
   RdApplyCent(a, CENT_ON, 1000.0);
   ASSERT_EQ_STR("divisor 1000", RdMoney(a, 1000.0), "1,000.00 USC ($1.00)");
   RdApplyCent(a, CENT_ON, 0.0);
   ASSERT_NEAR("divisor 0 -> 100", a.centDivisor, 100.0, 1e-9);
   //--- unknown major: plain number
   TfAccount(a, "cent", 1000.0);
   RdApplyCent(a, CENT_AUTO, 100.0);
   ASSERT_EQ_STR("unknown major", RdMoney(a, 1000.0), "1,000.00 cent (10.00)");
  }

//+------------------------------------------------------------------+
//| F-24 AC1: lot sizing is the same with and without the display.   |
//+------------------------------------------------------------------+
void TestCentLots(CTestRunner &t)
  {
   t.Begin("F-24 AC1 lots unchanged on a cent account");
   SSymbolSpec s;
   TfFx(s);
   SAccountSpec plain;
   TfAccount(plain, "USC", 100000.0);   // 1,000 USD in cents
   RdApplyCent(plain, CENT_OFF, 100.0);
   SAccountSpec cent = plain;
   RdApplyCent(cent, CENT_AUTO, 100.0);
   SPlanSettings cfg;
   cfg.Defaults();
   SLotResult a;
   SLotResult b;
   SResult ra;
   SResult rb;
   // 1 % of 100,000 USC = 1,000 USC; 200 ticks at 1 USC per tick and lot = 200 USC per lot -> 5 lots
   double loss = CRiskMath::LossPerLotByTicks(s, 1.10000, 1.09800);
   bool okA = CRiskMath::LotsFromRisk(1.0, loss, s, plain, cfg, a, ra);
   bool okB = CRiskMath::LotsFromRisk(1.0, loss, s, cent, cfg, b, rb);
   ASSERT_TRUE("both sized", okA && okB);
   ASSERT_NEAR("5 lots", a.lots, 5.0, 1e-9);
   ASSERT_NEAR("same lots", b.lots, a.lots, 1e-9);
   ASSERT_NEAR("same risk money", b.riskMoney, a.riskMoney, 1e-9);
   ASSERT_EQ_STR("refusal texts show both units", RdMoney(cent, b.riskMoney), "1,000.00 USC ($10.00)");
  }

//+------------------------------------------------------------------+
void TestTradeObjectNames(CTestRunner &t)
  {
   t.Begin("F-20 MetaTrader trade object names");
   ulong k = 0;
   ASSERT_TRUE("open arrow", RdTradeObjectTicket("#12345678 buy 0.10 EURUSD at 1.10000", k));
   ASSERT_EQ_INT("its ticket", k, 12345678);
   ASSERT_TRUE("close line", RdTradeObjectTicket("#12345678 1.10000 -> 1.10120", k));
   ASSERT_TRUE("19 digits", RdTradeObjectTicket("#1234567890123456789 x", k));
   ASSERT_FALSE("20 digits", RdTradeObjectTicket("#12345678901234567890 x", k));
   ASSERT_FALSE("no space after the ticket", RdTradeObjectTicket("#12345678", k));
   ASSERT_FALSE("letters after #", RdTradeObjectTicket("#abc 1", k));
   ASSERT_FALSE("space after #", RdTradeObjectTicket("# 123 x", k));
   ASSERT_FALSE("ticket 0", RdTradeObjectTicket("#0 x", k));
   ASSERT_FALSE("digits then letters", RdTradeObjectTicket("#123abc x", k));
   ASSERT_FALSE("RiskDesk object", RdTradeObjectTicket("RD_PO_123_EN", k));
   ASSERT_FALSE("user drawing", RdTradeObjectTicket("Trendline 12345", k));
   ASSERT_FALSE("# in the middle", RdTradeObjectTicket("my #123 note", k));
   ASSERT_FALSE("empty", RdTradeObjectTicket("", k));
  }

//+------------------------------------------------------------------+
void TestShotNames(CTestRunner &t)
  {
   t.Begin("F-19 / OP-14 screenshot names");
   datetime when = D'2026.11.12 10:43:21';
   ASSERT_EQ_STR("buy", RdShotFileName(A1, "EURUSD", PERIOD_H1, when, "buy", 123),
                 "A1_EURUSD_H1_2026-11-12_10-43-21_buy_123.png");
   ASSERT_EQ_STR("camera", RdShotFileName(A3, "XAUUSD", PERIOD_M15, when, "manual", 0),
                 "A3_XAUUSD_M15_2026-11-12_10-43-21_manual_0.png");
   ASSERT_EQ_STR("symbol with a space and a slash", RdShotFileName(1, "Nasdaq 100/x", PERIOD_MN1, when, "half", 7),
                 "1_Nasdaq_100_x_MN1_2026-11-12_10-43-21_half_7.png");
   ASSERT_EQ_STR("sanitize", RdSanitizeFileText("a/b\\c:d*e?f\"g<h>i|j k"), "a_b_c_d_e_f_g_h_i_j_k");
   ASSERT_EQ_STR("D1", RdTimeframeText(PERIOD_D1), "D1");
   ASSERT_EQ_STR("W1", RdTimeframeText(PERIOD_W1), "W1");
  }

//+------------------------------------------------------------------+
void TestCountdownText(CTestRunner &t)
  {
   t.Begin("F-21 countdown text (Q4, D3)");
   ASSERT_EQ_STR("0", RdCountdownText(0), "<-- 00:00");
   ASSERT_EQ_STR("negative", RdCountdownText(-5), "<-- 00:00");
   ASSERT_EQ_STR("52 s", RdCountdownText(52), "<-- 00:52");
   ASSERT_EQ_STR("59:59", RdCountdownText(3599), "<-- 59:59");
   ASSERT_EQ_STR("one hour", RdCountdownText(3600), "<-- 01:00:00");
   ASSERT_EQ_STR("owner's H4", RdCountdownText(2 * 3600 + 33 * 60 + 29), "<-- 02:33:29");
   ASSERT_EQ_STR("23:59:59", RdCountdownText(86399), "<-- 23:59:59");
   ASSERT_EQ_STR("one day", RdCountdownText(86400), "<-- 1d 00:00:00");
   ASSERT_EQ_STR("owner's W1", RdCountdownText(2 * 86400 + 22 * 3600 + 32 * 60 + 16), "<-- 2d 22:32:16");
   ASSERT_EQ_STR("left of the candle (D39)", RdCountdownText(820, true), "13:40 -->");
   ASSERT_EQ_STR("left of the candle, hours", RdCountdownText(9209, true), "02:33:29 -->");
   ASSERT_EQ_STR("left of the candle, days", RdCountdownText(86400 + 5, true), "1d 00:00:05 -->");
  }

// Countdown of a candle opened at 'open', 'now' later, market open unless said.
void CandleAt(SCandleClock &c, const datetime open, const ENUM_TIMEFRAMES tf, const datetime now,
              const bool inSession = true, const int pct = 10)
  {
   RdCandleClock(open, PeriodSeconds(tf), tf == PERIOD_MN1, now, inSession, pct, c);
  }

//+------------------------------------------------------------------+
void TestCandleClock(CTestRunner &t)
  {
   t.Begin("F-21 candle clock and red threshold (Q20)");
   SCandleClock c;
   CandleAt(c, D'2026.11.13 08:00', PERIOD_H4, D'2026.11.13 09:26:31');
   ASSERT_EQ_STR("H4 text", c.text, "<-- 02:33:29");
   ASSERT_FALSE("H4 gold", c.warn);
   ASSERT_EQ_INT("H4 length", c.length, 4 * 3600);
   //--- the owner's 10 % examples: red from exactly 10 %, gold one second earlier
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M5, D'2026.11.13 10:04:30');
   ASSERT_TRUE("M5 red at 00:30", c.warn && c.text == "<-- 00:30");
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M5, D'2026.11.13 10:04:29');
   ASSERT_FALSE("M5 gold at 00:31", c.warn);
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M1, D'2026.11.13 10:00:54');
   ASSERT_TRUE("M1 red in the last 6 s", c.warn);
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M1, D'2026.11.13 10:00:53');
   ASSERT_FALSE("M1 gold at 7 s", c.warn);
   CandleAt(c, D'2026.11.13 10:00', PERIOD_H1, D'2026.11.13 10:54');
   ASSERT_TRUE("H1 red at 06:00", c.warn && c.text == "<-- 06:00");
   CandleAt(c, D'2026.11.13 10:00', PERIOD_H1, D'2026.11.13 10:53:59');
   ASSERT_FALSE("H1 gold at 06:01", c.warn);
   CandleAt(c, D'2026.11.13 08:00', PERIOD_H4, D'2026.11.13 11:36');
   ASSERT_TRUE("H4 red at 24:00", c.warn && c.text == "<-- 24:00");
   CandleAt(c, D'2026.11.13 00:00', PERIOD_D1, D'2026.11.13 21:36');
   ASSERT_TRUE("D1 red at 2:24:00", c.warn && c.text == "<-- 02:24:00");
   CandleAt(c, D'2026.11.13 00:00', PERIOD_D1, D'2026.11.13 21:35:59');
   ASSERT_FALSE("D1 gold at 2:24:01", c.warn);
   CandleAt(c, D'2026.11.08 00:00', PERIOD_W1, D'2026.11.14 07:12');
   ASSERT_TRUE("W1 red at 16:48:00", c.warn && c.text == "<-- 16:48:00");
   CandleAt(c, D'2026.11.08 00:00', PERIOD_W1, D'2026.11.10 01:27:44');
   ASSERT_EQ_STR("W1 days", c.text, "<-- 4d 22:32:16");
   //--- 0 % = red only at 00:00; 100 % = always red
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M1, D'2026.11.13 10:00:59', true, 0);
   ASSERT_FALSE("0 %: gold at 1 s", c.warn);
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M1, D'2026.11.13 10:00:01', true, 100);
   ASSERT_TRUE("100 %: red", c.warn);
   //--- MN1: calendar months (Q20: the length of the current month)
   CandleAt(c, D'2026.02.01', PERIOD_MN1, D'2026.02.20');
   ASSERT_EQ_INT("MN1 February 2026 = 28 days", c.length, 28 * 86400);
   ASSERT_TRUE("MN1 close 1 March", c.close == D'2026.03.01');
   CandleAt(c, D'2028.02.01', PERIOD_MN1, D'2028.02.27');
   ASSERT_EQ_INT("MN1 February 2028 = 29 days", c.length, 29 * 86400);
   ASSERT_FALSE("MN1 gold with 3 days left (10 % = 2d 21:36)", c.warn);
   CandleAt(c, D'2028.02.01', PERIOD_MN1, D'2028.02.28');
   ASSERT_TRUE("MN1 red with 2 days left", c.warn && c.text == "<-- 2d 00:00:00");
   CandleAt(c, D'2026.12.01', PERIOD_MN1, D'2026.12.02');
   ASSERT_TRUE("MN1 December closes 1 January", c.close == D'2027.01.01');
   //--- market closed: the time ran out without a new candle
   CandleAt(c, D'2026.11.13 20:00', PERIOD_H4, D'2026.11.14 10:00', false);
   ASSERT_TRUE("closed: 00:00", c.closed && c.left == 0 && c.text == "<-- 00:00");
   ASSERT_TRUE("closed: red", c.warn);
   CandleAt(c, D'2026.11.13 20:00', PERIOD_H4, D'2026.11.14 10:00', false, 0);
   ASSERT_TRUE("closed: red also at 0 %", c.warn);
   //--- in session but no tick yet: the candle running by the clock
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M1, D'2026.11.13 10:03:20');
   ASSERT_TRUE("between ticks: M1 at 10:03", c.open == D'2026.11.13 10:03' && c.text == "<-- 00:40" && !c.closed);
   CandleAt(c, D'2026.11.13 10:00', PERIOD_M1, D'2026.11.13 10:01:00');
   ASSERT_TRUE("between ticks: exactly at the close", c.open == D'2026.11.13 10:01' && c.left == 60);
   CandleAt(c, D'2026.11.13 00:00', PERIOD_D1, D'2026.11.16 00:00:05');
   ASSERT_TRUE("D1 Monday before the first tick", c.open == D'2026.11.16' && c.text == "<-- 23:59:55");
   CandleAt(c, D'2026.10.01', PERIOD_MN1, D'2026.11.13 12:00');
   ASSERT_TRUE("MN1 between ticks", c.open == D'2026.11.01' && c.close == D'2026.12.01');
   //--- no candle
   ASSERT_FALSE("open 0", RdCandleClock(0, 60, false, D'2026.11.13', true, 10, c));
   //--- months
   ASSERT_TRUE("31 Jan + 1 month", RdAddMonths(D'2026.01.31', 1) == D'2026.02.28');
   ASSERT_TRUE("Dec + 1 month", RdAddMonths(D'2026.12.15 13:00', 1) == D'2027.01.15 13:00');
   ASSERT_TRUE("Jan - 1 month", RdAddMonths(D'2026.01.15', -1) == D'2025.12.15');
   ASSERT_TRUE("Jan - 13 months", RdAddMonths(D'2026.01.15', -13) == D'2024.12.15');
  }

//+------------------------------------------------------------------+
void TestLogFiles(CTestRunner &t)
  {
   t.Begin("F-32 daily log files");
   datetime d = 0;
   ASSERT_TRUE("today's file", RdLogFileDay("RiskDesk_20261113.log", "RiskDesk", d) && d == D'2026.11.13');
   ASSERT_FALSE("7 digits", RdLogFileDay("RiskDesk_2026111.log", "RiskDesk", d));
   ASSERT_FALSE("month 13", RdLogFileDay("RiskDesk_20261332.log", "RiskDesk", d));
   ASSERT_FALSE("30 February", RdLogFileDay("RiskDesk_20260230.log", "RiskDesk", d));
   ASSERT_TRUE("29 February 2028", RdLogFileDay("RiskDesk_20280229.log", "RiskDesk", d));
   ASSERT_FALSE("other name", RdLogFileDay("RiskDesk_notes.log", "RiskDesk", d));
   ASSERT_FALSE("other prefix", RdLogFileDay("Other_20261113.log", "RiskDesk", d));
   ASSERT_FALSE("other extension", RdLogFileDay("RiskDesk_20261113.txt", "RiskDesk", d));
   ASSERT_FALSE("suffix", RdLogFileDay("RiskDesk_20261113_2.log", "RiskDesk", d));
   datetime now = D'2026.11.13 15:00';
   ASSERT_TRUE("keep 30: 14 Oct goes", RdLogFileExpired(D'2026.10.14', now, 30));
   ASSERT_FALSE("keep 30: 15 Oct stays", RdLogFileExpired(D'2026.10.15', now, 30));
   ASSERT_FALSE("keep 30: today stays", RdLogFileExpired(D'2026.11.13', now, 30));
   ASSERT_TRUE("keep 1: yesterday goes", RdLogFileExpired(D'2026.11.12', now, 1));
   ASSERT_FALSE("keep 1: today stays", RdLogFileExpired(D'2026.11.13', now, 1));
   ASSERT_FALSE("keep 0: all stay", RdLogFileExpired(D'2020.01.01', now, 0));
  }

//+------------------------------------------------------------------+
void RunExtrasTests(CTestRunner &t)
  {
   TestCentDisplay(t);
   TestCentLots(t);
   TestTradeObjectNames(t);
   TestShotNames(t);
   TestCountdownText(t);
   TestCandleClock(t);
   TestLogFiles(t);
  }

#endif // RD_TESTS_EXTRAS_MQH
