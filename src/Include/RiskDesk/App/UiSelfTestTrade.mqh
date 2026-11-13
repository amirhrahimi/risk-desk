//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestTrade.mqh                               |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : the trade suite of the self-test (phase P4). Drives    |
//|           Add Line, Add Pend Line, Delete Line, line drops, the  |
//|           Risk % field, Buy and Sell through the same event      |
//|           handlers a user triggers, with REAL orders, and checks |
//|           T-03..T-09, T-11, T-12, T-25, T-28, F-16 AC3, F-33 and |
//|           the netting confirmations (BC-10, A6).                 |
//|           "trade-basic" runs T-03..T-07, T-09, T-05/T-06, T-28   |
//|           (for the extra symbols of an account).                 |
//| Safety : rule R13 - no order unless the account is a DEMO        |
//|          account (checked before anything is sent); own magic   |
//|          RD_UITEST_MAGIC, so the owner's RiskDesk trades never   |
//|          count; about 2.5 x the risk of the minimum lot, at most |
//|          1 % of the balance and half the free margin; every test |
//|          position is closed again (also those of an aborted      |
//|          earlier run). The settings the steps change are read   |
//|          from the inputs again at the end.                       |
//|          Part of CUiSelfTest; included at the end of             |
//|          App/UiSelfTest.mqh. This file: step dispatch and        |
//|          helpers; the steps are in UiSelfTestTradeLines.mqh     |
//|          and UiSelfTestTradeOrders.mqh (~600 lines per file).    |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTTRADE_MQH
#define RD_APP_UISELFTESTTRADE_MQH

//+------------------------------------------------------------------+
void CUiSelfTest::StepTrade(const uint now)
  {
   bool done = true;
   bool trade = m_tradeOk;
   bool full = m_tradeOk && m_full;
   bool net = full && !m_gw.IsHedging();
   switch(m_step)
     {
      case 0:
        {
         SQuote q;
         if(!CMarket::Quote(_Symbol, q) && (uint)(now - m_startAt) < 15000)
            return;   // wait for a first quote, at most 15 s
         TradeStart();
         break;
        }
      case 1:
         if(!m_labelWait)
           {
            TradeT03();
            done = !m_labelWait;   // ADR-024 check waits for the runner's window capture
           }
         else
            done = LabelCheckRestore();
         break;
      case 2:
         TradeT03b();
         break;
      case 3:
         TradeT03c();
         break;
      case 4:
         if(trade && m_marketClosed)
           {
            TradeT27();
            m_tradeOk = false;   // every other order step would only meet the closed market
           }
         else
            if(trade)
               TradeT04Buy();
            else
               if(m_permWhy != "")
                  TradeT26();
         break;
      case 5:
         if(trade)
            TradeT04Sell();
         break;
      case 6:
         if(trade)
            TradeT04Risk();
         break;
      case 7:
         if(trade)
            TradeT07();
         break;
      case 8:
         if(trade)
            TradeT09();
         break;
      case 9:
         if(trade)
            TradeT05();
         break;
      case 10:
         if(trade)
            TradeT06();
         break;
      case 11:
         if(full)
            TradeT08a();
         break;
      case 12:
         if(full)
            TradeT08b();
         break;
      case 13:
         if(full)
            TradeT08c();
         break;
      case 14:
         if(full)
            TradeT11a();
         break;
      case 15:
         if(full)
            TradeT11b();
         break;
      case 16:
         if(full)
            TradeF16();
         break;
      case 17:
         if(full)
            TradeT12a();
         break;
      case 18:
         if(full)
            TradeT12b();
         break;
      case 19:
         if(full)
            TradeT25();
         break;
      case 20:
         if(trade)
            TradeT28Open();
         break;
      case 21:
         if(trade)
            done = TradeT28Wait();
         break;
      case 22:
         if(trade)
            TradeT28Check();
         break;
      case 23:
         if(net)
            TradeNet1();
         break;
      case 24:
         if(net)
            TradeNet2();
         break;
      default:
         TradeEnd();
         Finish();
         return;
     }
   if(done)
      m_step++;
  }

//====================================================================
// Helpers
//====================================================================
bool CUiSelfTest::FreshQuote(SQuote &q)
  {
   return CMarket::Quote(_Symbol, q);
  }

// What the terminal does when the user drops a line.
void CUiSelfTest::DropLine(const ELineRole role, const double price)
  {
   string name = CLines::LineName(role);
   ObjectMove(0, name, 0, 0, price);
   long l = 0;
   double d = 0.0;
   m_ctl.OnChartEvent(CHARTEVENT_OBJECT_DRAG, l, d, name);
  }

// Test positions (RD_UITEST_MAGIC) on the chart symbol.
int CUiSelfTest::TestPositions(SPosition &arr[])
  {
   STradeFilter f;
   f.Reset();
   f.symbol = _Symbol;
   f.toolOnly = true;
   SResult r;
   if(!m_gw.ListPositions(f, arr, r))
      ArrayResize(arr, 0);
   return ArraySize(arr);
  }

bool CUiSelfTest::FindTestPosition(const ulong ticket, SPosition &p)
  {
   SPosition arr[];
   int n = TestPositions(arr);
   for(int i = 0; i < n; i++)
      if(arr[i].ticket == ticket)
        {
         p = arr[i];
         return true;
        }
   return false;
  }

// The "#123456" of the status message.
ulong CUiSelfTest::StatusTicket() const
  {
   string t = m_status.Text();
   int i = StringFind(t, "#");
   if(i < 0)
      return 0;
   string digits = "";
   for(int k = i + 1; k < StringLen(t); k++)
     {
      ushort c = StringGetCharacter(t, k);
      if(c < '0' || c > '9')
         break;
      digits += ShortToString(c);
     }
   return (digits == "") ? 0 : (ulong)StringToInteger(digits);
  }

//+------------------------------------------------------------------+
//| Close every test position and delete every test order on the     |
//| account (RD_UITEST_MAGIC only).                                  |
//+------------------------------------------------------------------+
void CUiSelfTest::CloseTestTrades(const string why)
  {
   STradeFilter f;
   f.Reset();
   f.toolOnly = true;
   SPosition arr[];
   SResult r;
   if(!m_gw.ListPositions(f, arr, r))
     {
      Line("WARN cleanup (" + why + "): " + r.message);
      return;
     }
   int closed = 0;
   int n = ArraySize(arr);
   for(int i = 0; i < n; i++)
     {
      STradeOutcome out;
      SResult cr;
      if(m_gw.ClosePosition(arr[i].ticket, 0.0, out, cr))
         closed++;
      else
         Line("WARN cleanup: " + RdTicketText(arr[i].ticket) + " not closed: " + cr.message);
     }
   f.includeStopLimit = true;
   SOrder ord[];
   int deleted = 0;
   if(m_gw.ListPending(f, ord, r))
      for(int j = 0; j < ArraySize(ord); j++)
        {
         SResult dr;
         if(m_gw.DeletePending(ord[j].ticket, dr))
            deleted++;
        }
   if(n > 0 || deleted > 0)
      Line("cleanup (" + why + "): " + IntegerToString(closed) + " of " + IntegerToString(n) + " test position(s) closed" +
           (deleted > 0 ? ", " + IntegerToString(deleted) + " order(s) deleted" : ""));
   m_ctl.Refresh();
  }

//+------------------------------------------------------------------+
//| Loss of 1 lot from entry to SL, composed here from the raw       |
//| valuations (BC-05): MT5 OrderCalcProfit; MT4 tick value, the     |
//| larger of it and contract x rate when they are > 5 % apart.      |
//+------------------------------------------------------------------+
double CUiSelfTest::ExpectedLoss(const ESide side, const double entry, const double sl)
  {
   SAccountSpec acc;
   SResult r;
   CAccountSpec::Read(acc, r, m_cfg.centMode, m_cfg.centDivisor);
   double calc = 0.0;
   SResult cr;
   if(m_money.LossByCalcProfit(m_ts, side, entry, sl, calc, cr) && calc > 0.0)
      return calc;
   double byTick = 0.0;
   SResult tr;
   if(!m_money.LossByTickValue(m_ts, entry, sl, byTick, tr))
      byTick = 0.0;
   double byContract = 0.0;
   string via = "";
   SResult kr;
   bool checkable = (m_ts.calcMode == 0 || m_ts.calcMode == 1);
   if(!checkable || !m_money.LossByContract(m_ts, entry, sl, acc.currency, byContract, via, kr))
      byContract = 0.0;
   if(byTick > 0.0 && byContract > 0.0 && MathAbs(byTick - byContract) / byContract * 100.0 > RD_MONEY_MISMATCH_PCT)
      return MathMax(byTick, byContract);
   return (byTick > 0.0) ? byTick : byContract;
  }

double CUiSelfTest::Base()
  {
   SAccountSpec a;
   SResult r;
   CAccountSpec::Read(a, r, m_cfg.centMode, m_cfg.centDivisor);
   return CRiskMath::RiskBase(m_cfg.riskBase, a.balance, a.equity);
  }

// 04 sections 2-4 from ExpectedLoss: floor(base x pct / (loss + commission)).
double CUiSelfTest::ExpectedLots(const ESide side, const double entry, const double sl, const double pct, double &raw)
  {
   raw = 0.0;
   double loss = ExpectedLoss(side, entry, sl);
   double base = Base();
   if(!(loss > 0.0) || !(base > 0.0))
      return 0.0;
   raw = base * pct / 100.0 / (loss + MathMax(0.0, m_cfg.commissionPerLot));
   double lots = 0.0;
   if(!RdFloorVolume(m_ts, raw, lots))
      return 0.0;
   if(RdVolGt(lots, m_ts.volMax) && !RdFloorVolume(m_ts, m_ts.volMax, lots))
      return 0.0;
   return lots;
  }

void CUiSelfTest::SetTpMode(const ETpMode mode, const double rr)
  {
   m_cfg.tpMode = mode;
   m_cfg.tpRR = rr;
   m_cfg.tradeWithTpLine = (mode != TPMODE_NONE);
   m_cfg.manualTpLine = (mode == TPMODE_MANUAL_LINE);
  }

//+------------------------------------------------------------------+
//| The inputs' values again (CSettings::Load), then the suite's own |
//| magic and no click cooldown.                                     |
//+------------------------------------------------------------------+
void CUiSelfTest::RestoreTp()
  {
   m_cfg.Load();
   m_cfg.magic = RD_UITEST_MAGIC;
   m_cfg.clickCooldownMs = 0;
   SGatewaySettings gs;
   m_cfg.Gateway(gs);
   m_gw.Configure(gs);
  }

// F-33: the button is drawn with that look (its background colour).
bool CUiSelfTest::HasLook(const EPanelButton b, const EButtonLook look) const
  {
   color back = clrNONE;
   color fore = clrNONE;
   m_theme.ButtonColors(b, look, back, fore);
   return (color)ObjectGetInteger(0, CPanel::ButtonName(b), OBJPROP_BGCOLOR) == back;
  }

// SL line at distFactor x m_dist below Bid (buy) or above Ask (sell), dropped like a user drop.
bool CUiSelfTest::PlaceStop(const ESide side, const double distFactor, SQuote &q, double &sl)
  {
   sl = 0.0;
   if(!FreshQuote(q))
      return false;
   double raw = (side == SIDE_BUY) ? q.bid - distFactor * m_dist : q.ask + distFactor * m_dist;
   sl = (side == SIDE_BUY) ? RdRoundPriceDown(m_ts, raw) : RdRoundPriceUp(m_ts, raw);
   if(!(sl > 0.0))
      return false;
   DropLine(LINEROLE_SL, sl);
   return true;
  }

// A buy-side SL far enough below Bid that Risk % 'pct' cannot buy the minimum lot; 0 = none.
double CUiSelfTest::FarStop(const SQuote &q, const double pct)
  {
   double ask = RdNormalizePrice(m_ts, q.ask);
   for(double k = 1.0; k <= 128.0; k *= 2.0)
     {
      double sl = RdRoundPriceDown(m_ts, q.bid - k * m_dist);
      if(!(sl > RdTick(m_ts)))
         break;
      double raw = 0.0;
      ExpectedLots(SIDE_BUY, ask, sl, pct, raw);
      if(raw > 0.0 && raw < m_ts.volMin)
         return sl;
     }
   return 0.0;
  }

//+------------------------------------------------------------------+
//| T-05/T-06/T-08: the click opened exactly one position with the   |
//| previewed lots, the SL of the line, the expected TP (tpWanted >= |
//| 0: that price, 0 = none; < 0: rr x the SL distance from the fill)|
//| green/amber status with the risk, lines removed, screenshot.     |
//+------------------------------------------------------------------+
bool CUiSelfTest::CheckOpened(const string id, const ESide side, const int before, const double sl, const double tpWanted,
                              const double rr)
  {
   SPosition arr[];
   int n = TestPositions(arr);
   string st = m_status.Text();
   ulong ticket = StatusTicket();
   SPosition p;
   bool found = ticket > 0 && FindTestPosition(ticket, p);
   if(!found || n != before + 1)
     {
      Check(false, id, "positions " + IntegerToString(before) + " -> " + IntegerToString(n) + ", status " +
            RdSeverityText(m_status.Severity()) + " '" + st + "'");
      return false;
     }
   m_ticket = ticket;
   string name = (side == SIDE_BUY) ? "Buy " : "Sell ";
   bool statusOk = m_status.Severity() != SEV_ERROR && StringFind(st, name) == 0 && StringFind(st, "risk ") > 0;
   bool volOk = RdFormatLots(m_ts, p.volume) == m_pvLots;
   bool slOk = RdPriceEq(m_ts, p.sl, sl);
   bool tpOk = true;
   string tpText = "TP " + RdFormatPrice(m_ts, p.tp);
   if(tpWanted >= 0.0)
     {
      tpOk = (tpWanted > 0.0) ? RdPriceEq(m_ts, p.tp, tpWanted) : !(p.tp > 0.0);
      tpText += " (wanted " + (tpWanted > 0.0 ? RdFormatPrice(m_ts, tpWanted) : "none") + ")";
     }
   else
     {
      // F-17 AC2: the TP is R/R x the SL distance from the price SENT (Ask/Bid at the attempt), not
      // from the fill; under market execution the fill can slip by any amount. The entry the TP
      // implies, (TP + rr x SL) / (1 + rr), must lie near the fill: within the allowed slippage +
      // spread, or 5 % of the SL distance (a wrong R/R misses by far more).
      SQuote q;
      FreshQuote(q);
      double implied = (p.tp + rr * p.sl) / (1.0 + rr);
      double tol = MathMax(m_cfg.slippagePoints * m_ts.point + (q.ask - q.bid) + RdTick(m_ts), 0.05 * MathAbs(p.open - p.sl));
      tpOk = (p.tp > 0.0) && ((side == SIDE_BUY) ? p.tp > p.open : p.tp < p.open) && MathAbs(implied - p.open) <= tol;
      tpText += " (R/R " + RdNum(rr, 2) + " from " + RdFormatPrice(m_ts, implied) + ", fill " + RdFormatPrice(m_ts, p.open) +
                " +/- " + RdNum(tol, m_ts.digits) + ")";
     }
   bool linesGone = m_cfg.keepLinesAfterTrade || (m_state.lineMode == LINES_NONE && CountObjects(RD_LINE_PREFIX) == 0);
   string action = (side == SIDE_BUY) ? "buy" : "sell";
   bool shot = !m_cfg.autoScreenshot || (m_state.lastShot != "" && FileIsExist(m_state.lastShot) &&
               StringFind(m_state.lastShot, "_" + action + "_" + IntegerToString((long)ticket)) > 0);
   Check(statusOk && volOk && slOk && tpOk && linesGone && shot, id,
         RdTicketText(ticket) + " " + RdFormatLots(m_ts, p.volume) + " lot (Lots showed " + m_pvLots + ") @" +
         RdFormatPrice(m_ts, p.open) + ", SL " + RdFormatPrice(m_ts, p.sl) + " (line " + RdFormatPrice(m_ts, sl) + "), " +
         tpText + ", lines removed " + RdBoolText(linesGone) + ", screenshot " + RdBoolText(shot) + " (" + m_state.lastShot +
         "), status " + RdSeverityText(m_status.Severity()) + " '" + st + "'");
   return true;
  }

#include "UiSelfTestTradeLines.mqh"
#include "UiSelfTestTradeOrders.mqh"

#endif // RD_APP_UISELFTESTTRADE_MQH
