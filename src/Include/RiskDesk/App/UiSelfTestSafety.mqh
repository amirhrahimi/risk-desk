// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestSafety.mqh                              |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS, ADR-031)        |
//| Purpose : the safety suite of the self-test: the three paths a   |
//|           healthy demo server never takes, driven through the    |
//|           real Buy button with a REAL request and a fault armed  |
//|           in the gateway (EGwFault):                             |
//|           - T-29  rule R7: the SL cannot be attached -> the      |
//|             position is closed (InpCloseIfStopFails on), or the  |
//|             red "WITHOUT a valid SL" warning (off)               |
//|           - T-35  rule R9, BC-14: the reply of an open is lost   |
//|             (executed / not executed / never answered) -> no     |
//|             blind resend: exactly one position, or none and a    |
//|             red message; a trade of the last seconds is not      |
//|             taken for the lost request                           |
//|           - BC-06 (MT5): the first filling policy is one the     |
//|             server rejects -> the ladder's next step opens the   |
//|             trade and the policy is cached                       |
//|           The evidence is the position count, the status bar and |
//|           the daily log file (RiskDesk/Logs), read from where it |
//|           ended before each click.                               |
//| Safety : rule R13 (demo only, checked by TradeStart), own magic  |
//|          RD_UITEST_MAGIC, test lots about 2.5 x the risk of the  |
//|          minimum lot, every test position closed again.          |
//|          Part of CUiSelfTest; included at the end of             |
//|          App/UiSelfTest.mqh.                                     |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTSAFETY_MQH
#define RD_APP_UISELFTESTSAFETY_MQH

//+------------------------------------------------------------------+
void CUiSelfTest::StepSafety(const uint now)
  {
   switch(m_step)
     {
      case 0:
        {
         SQuote q;
         if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
            return;   // wait for a first quote, at most 15 s
         TradeStart();
         if(m_tradeOk && m_marketClosed)
           {
            Line("INFO " + _Symbol + " is closed: the safety cases need a live market and are skipped");
            m_tradeOk = false;
           }
         break;
        }
      case 1:
         if(m_tradeOk)
            SfSlAttach(true);
         break;
      case 2:
         if(m_tradeOk)
            SfSlAttach(false);
         break;
      case 3:
         if(m_tradeOk)
            SfReplyLost();
         break;
      case 4:
         if(m_tradeOk)
            SfSendLost();
         break;
      case 5:
         if(m_tradeOk)
            SfNeverAnswered();
         break;
      case 6:
         if(m_tradeOk)
            SfNotAdopted();
         break;
      case 7:
         if(m_tradeOk)
            SfFillFallback();
         break;
      default:
         m_gw.ArmFault(GWFAULT_NONE);
         TradeEnd();
         Finish();
         return;
     }
   m_step++;
  }

//====================================================================
// Helpers
//====================================================================

// The size of today's log file now: what is written after it belongs to the case.
long CUiSelfTest::SfLogMark() const
  {
   int h = FileOpen(CLogger::TodayFile(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return 0;
   long size = (long)FileSize(h);
   FileClose(h);
   return size;
  }

string CUiSelfTest::SfLogSince(const long mark) const
  {
   string text = "";
   int h = FileOpen(CLogger::TodayFile(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
      return text;
   if(mark > 0)
      FileSeek(h, mark, SEEK_SET);
   while(!FileIsEnding(h))
      text += FileReadString(h) + "\n";
   FileClose(h);
   return text;
  }

// Lines of 'text' containing both strings.
int CUiSelfTest::SfCountLines(const string text, const string a, const string b) const
  {
   string lines[];
   int n = StringSplit(text, '\n', lines);
   int count = 0;
   for(int i = 0; i < n; i++)
      if(StringFind(lines[i], a) >= 0 && StringFind(lines[i], b) >= 0)
         count++;
   return count;
  }

// The fill= of the last G-01 request line ("" on MT4).
string CUiSelfTest::SfLastFill(const string text) const
  {
   string lines[];
   int n = StringSplit(text, '\n', lines);
   string fill = "";
   for(int i = 0; i < n; i++)
     {
      if(StringFind(lines[i], "[G-01]") < 0 || StringFind(lines[i], "attempt=") < 0)
         continue;
      int p = StringFind(lines[i], " fill=");
      if(p < 0)
         continue;
      string rest = StringSubstr(lines[i], p + 6);
      int e = StringFind(rest, " ");
      fill = (e >= 0) ? StringSubstr(rest, 0, e) : rest;
     }
   return fill;
  }

// Gateway settings from the inputs, with the test's own magic and no click cooldown.
void CUiSelfTest::SfSettings(const bool closeIfStopFails)
  {
   RestoreTp();
   m_cfg.closeIfStopFails = closeIfStopFails;
   SGatewaySettings gs;
   m_cfg.Gateway(gs);
   m_gw.Configure(gs);
  }

// A clean Add Line, the SL one test distance below Bid, then one click on Buy with 'fault'
// armed. The lines the click leaves behind (a failed trade keeps them) are removed first.
bool CUiSelfTest::SfBuy(const EGwFault fault, int &before, int &after, string &log)
  {
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   if(!PlaceStop(SIDE_BUY, 1.0, q, sl))
     {
      Check(false, "safety setup", "no SL line could be placed on " + _Symbol);
      return false;
     }
   SPosition arr[];
   before = TestPositions(arr);
   m_pvLots = Text("RD_E_LOTS");
   long mark = SfLogMark();
   m_gw.ArmFault(fault);
   ClickButton(PB_BUY);
   m_gw.ArmFault(GWFAULT_NONE);
   after = TestPositions(arr);
   log = SfLogSince(mark);
   return true;
  }

string CUiSelfTest::SfState(const int before, const int after) const
  {
   return "positions " + IntegerToString(before) + " -> " + IntegerToString(after) + ", status " +
          RdSeverityText(m_status.Severity()) + " '" + m_status.Text() + "'";
  }

// Every case ends the same way: lines and test trades removed, the inputs' settings back.
void CUiSelfTest::SfEnd(const string shot)
  {
   Shot(shot);
   CloseTestTrades("after " + shot);
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
   RestoreTp();   // the inputs' settings again (a case may have changed InpCloseIfStopFails)
  }

//====================================================================
// Cases
//====================================================================

//+------------------------------------------------------------------+
//| T-29, rule R7: the server never gets an SL on the position.      |
//| closeIfFails: the position is closed and the status is red       |
//| "SL could not be attached - position closed"; otherwise it stays |
//| open and the red message says it has no SL.                      |
//+------------------------------------------------------------------+
void CUiSelfTest::SfSlAttach(const bool closeIfFails)
  {
   SfSettings(closeIfFails);
   int before = 0;
   int after = 0;
   string log = "";
   if(!SfBuy(GWFAULT_SL_ATTACH, before, after, log))
      return;
   string st = m_status.Text();
   bool red = m_status.Severity() == SEV_ERROR;
   bool logged = (log == "") || StringFind(log, "has no valid SL") >= 0;
   if(closeIfFails)
     {
      bool text = StringFind(st, "SL could not be attached - position closed") >= 0;   // "Buy failed: SL could not ..."
      bool closed = (log == "") || SfCountLines(log, "[G-04]", "attempt=") >= 1;
      Check(after == before && red && text && logged && closed, "T-29 SL fails, position closed",
            "Buy with the SL refused (R7, InpCloseIfStopFails on): " + SfState(before, after) + ", log: no-valid-SL line " +
            RdBoolText(StringFind(log, "has no valid SL") >= 0) + ", close request " + RdBoolText(SfCountLines(log, "[G-04]", "attempt=") >= 1));
     }
   else
     {
      SPosition arr[];
      int n = TestPositions(arr);
      bool noSl = (n == before + 1) && !(arr[n - 1].sl > 0.0);
      bool text = StringFind(st, "WITHOUT a valid SL") >= 0;
      Check(red && text && noSl && logged, "T-29 SL fails, kept open",
            "Buy with the SL refused (InpCloseIfStopFails off): " + SfState(before, after) + ", position without SL " + RdBoolText(noSl));
     }
   SfEnd(closeIfFails ? "t29_closed" : "t29_kept");
  }

//+------------------------------------------------------------------+
//| T-35 (a): the request executed, its reply was lost. BC-14 finds  |
//| the position: one send, one position, no resend.                 |
//+------------------------------------------------------------------+
void CUiSelfTest::SfReplyLost()
  {
   SfSettings(true);
   int before = 0;
   int after = 0;
   string log = "";
   if(!SfBuy(GWFAULT_REPLY_LOST, before, after, log))
      return;
   int sends = SfCountLines(log, "[G-01]", "attempt=");
   bool logged = (log == "") || (StringFind(log, "reply dropped") >= 0 && StringFind(log, "BC-14") >= 0 &&
                 StringFind(log, "the request WAS executed - not resending") >= 0 && sends == 1);
   bool ok = after == before + 1 && m_status.Severity() != SEV_ERROR && StringFind(m_status.Text(), "Buy ") == 0;
   Check(ok && logged, "T-35 reply lost, executed",
         "Buy sent and executed, reply dropped: " + SfState(before, after) + ", requests sent " + IntegerToString(sends) +
         " (want 1), 'WAS executed - not resending' " + RdBoolText(StringFind(log, "the request WAS executed - not resending") >= 0));
   SfEnd("t35_reply_lost");
  }

//+------------------------------------------------------------------+
//| T-35 (b): the request never arrived. BC-14 finds nothing and     |
//| resends ONCE: two sends, one position.                           |
//+------------------------------------------------------------------+
void CUiSelfTest::SfSendLost()
  {
   SfSettings(true);
   int before = 0;
   int after = 0;
   string log = "";
   if(!SfBuy(GWFAULT_SEND_LOST, before, after, log))
      return;
   int sends = SfCountLines(log, "[G-01]", "attempt=");
   bool logged = (log == "") || (StringFind(log, "request not sent") >= 0 && StringFind(log, "not executed - sending once more") >= 0 &&
                 sends == 2);
   bool ok = after == before + 1 && m_status.Severity() != SEV_ERROR && StringFind(m_status.Text(), "Buy ") == 0;
   Check(ok && logged, "T-35 request lost, resent once",
         "Buy not sent, no reply: " + SfState(before, after) + ", requests " + IntegerToString(sends) + " (want 2), 'sending once more' " +
         RdBoolText(StringFind(log, "not executed - sending once more") >= 0));
   SfEnd("t35_send_lost");
  }

//+------------------------------------------------------------------+
//| T-35 (c): nothing ever arrives. One resend, then a red message;  |
//| no position, no third request.                                   |
//+------------------------------------------------------------------+
void CUiSelfTest::SfNeverAnswered()
  {
   SfSettings(true);
   int before = 0;
   int after = 0;
   string log = "";
   if(!SfBuy(GWFAULT_NEVER_ANSWERED, before, after, log))
      return;
   int sends = SfCountLines(log, "[G-01]", "attempt=");
   bool logged = (log == "") || (StringFind(log, "not executed - sending once more") >= 0 && sends == 2);
   bool ok = after == before && m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "No answer from the server") >= 0;
   Check(ok && logged, "T-35 never answered",
         "Buy never reaches the server: " + SfState(before, after) + ", requests " + IntegerToString(sends) + " (want 2)");
   SfEnd("t35_never_answered");
  }

//+------------------------------------------------------------------+
//| T-35 (d): a trade of the last seconds (same symbol, side, magic, |
//| volume) must not be taken for a lost request. A real Buy, then   |
//| at once a Buy that never arrives: still ONE position and a red   |
//| message, not a "confirmed" status that names the first trade.    |
//+------------------------------------------------------------------+
void CUiSelfTest::SfNotAdopted()
  {
   SfSettings(true);
   int before = 0;
   int after = 0;
   string log = "";
   if(!SfBuy(GWFAULT_NONE, before, after, log))
      return;
   if(after != before + 1)
     {
      Check(false, "T-35 earlier trade not adopted", "the first, normal Buy did not open: " + SfState(before, after));
      SfEnd("t35_adopt_setup");
      return;
     }
   SPosition arr[];
   int n = TestPositions(arr);
   double firstVolume = arr[n - 1].volume;
   ulong firstTicket = arr[n - 1].ticket;
   int before2 = 0;
   int after2 = 0;
   if(!SfBuy(GWFAULT_NEVER_ANSWERED, before2, after2, log))
      return;
   string lots = m_pvLots;   // the Lots the second click was sized with
   bool sameVolume = (lots == RdFormatLots(m_ts, firstVolume));
   bool ok = after2 == before2 && m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "No answer from the server") >= 0 &&
             StringFind(m_status.Text(), RdTicketText(firstTicket)) < 0;
   Check(ok, "T-35 earlier trade not adopted",
         "Buy " + RdTicketText(firstTicket) + " " + RdFormatLots(m_ts, firstVolume) + " lot, then within seconds a Buy that never arrives: " +
         SfState(before2, after2) + (sameVolume ? "" : " (the second Buy was sized differently: " + lots + " lot)"));
   SfEnd("t35_not_adopted");
  }

//+------------------------------------------------------------------+
//| BC-06 (MT5): the ladder starts with a policy the symbol does not |
//| allow. The server's real rejection (10030) must lead to the next |
//| policy and a position; the next Buy starts with the policy that  |
//| worked (cache). A server that accepts the first policy anyway    |
//| leaves nothing to test: INFO.                                    |
//+------------------------------------------------------------------+
void CUiSelfTest::SfFillFallback()
  {
#ifdef __MQL5__
   SfSettings(true);
   int before = 0;
   int after = 0;
   string log = "";
   if(!SfBuy(GWFAULT_BAD_FILL, before, after, log))
      return;
   int sends = SfCountLines(log, "[G-01]", "attempt=");
   string worked = SfLastFill(log);
   bool opened = after == before + 1 && m_status.Severity() != SEV_ERROR;
   if(opened && sends == 1)
     {
      Line("INFO BC-06: " + _Symbol + " accepted the policy it should reject (" + SfState(before, after) + "): no rejection to test here");
      SfEnd("bc06_accepted");
      return;
     }
   bool logged = (log == "") || (StringFind(log, "retcode=10030") >= 0 && StringFind(log, "-> next fill=") >= 0 && sends >= 2);
   Check(opened && logged, "BC-06 fill rejected, next policy",
         "first policy refused by the server: " + SfState(before, after) + ", requests " + IntegerToString(sends) + ", policy that worked " +
         worked + ", 10030 answered " + RdBoolText(StringFind(log, "retcode=10030") >= 0));
   CloseTestTrades("before the cache check");
   //--- the cache: the next Buy sends once, with the policy that worked
   string log2 = "";
   int before2 = 0;
   int after2 = 0;
   if(!SfBuy(GWFAULT_NONE, before2, after2, log2))
      return;
   int sends2 = SfCountLines(log2, "[G-01]", "attempt=");
   string again = SfLastFill(log2);
   Check(after2 == before2 + 1 && (log2 == "" || (sends2 == 1 && again == worked)), "BC-06 policy cached",
         "next Buy: " + SfState(before2, after2) + ", requests " + IntegerToString(sends2) + " (want 1), policy " + again +
         " (cached " + worked + ")");
   SfEnd("bc06_fill");
#else
   Line("INFO BC-06: MT4 has no filling policy - the ladder case is MT5 only");
#endif
  }

#endif // RD_APP_UISELFTESTSAFETY_MQH
