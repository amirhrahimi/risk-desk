//+------------------------------------------------------------------+
//| RiskDesk - App/UiSelfTestTradeOrders.mqh                         |
//| Layer   : App, DEBUG builds only (RD_TEST_HOOKS)                 |
//| Purpose : trade suite steps that open real DEMO positions:       |
//|           T-05, T-06, T-08, T-11, F-16 AC3, T-12, T-25, T-28 and |
//|           the netting steps (BC-10). Part of CUiSelfTest;        |
//|           included by App/UiSelfTestTrade.mqh.                   |
//+------------------------------------------------------------------+
#ifndef RD_APP_UISELFTESTTRADEORDERS_MQH
#define RD_APP_UISELFTESTTRADEORDERS_MQH


//+------------------------------------------------------------------+
//| T-05 Buy / T-06 Sell with the inputs' TP mode.                   |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT05()
  {
   if(m_state.lineMode != LINES_MARKET)
      ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   m_pvLots = Text("RD_E_LOTS");
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   double tpWanted = (m_cfg.tpMode == TPMODE_AUTO_RR) ? -1.0 : 0.0;
   CheckOpened("T-05 Buy", SIDE_BUY, before, sl, tpWanted, m_cfg.tpRR);
   Shot("t05_buy");
  }

void CUiSelfTest::TradeT06()
  {
   CloseTestTrades("after T-05");
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_SELL, 1.0, q, sl);
   m_pvLots = Text("RD_E_LOTS");
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_SELL);
   double tpWanted = (m_cfg.tpMode == TPMODE_AUTO_RR) ? -1.0 : 0.0;
   CheckOpened("T-06 Sell", SIDE_SELL, before, sl, tpWanted, m_cfg.tpRR);
   Shot("t06_sell");
   CloseTestTrades("after T-06");
  }

//+------------------------------------------------------------------+
//| T-08 TP modes (F-17, ADR-013), R/R 2.                            |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT08a()
  {
   SetTpMode(TPMODE_NONE, 2.0);
   ClickButton(PB_ADDLINE);
   Check(!m_plan.Exists(LINEROLE_TP), "T-08a no TP line", "Trade with TP Line = false: TP line " +
         RdBoolText(m_plan.Exists(LINEROLE_TP)));
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   m_pvLots = Text("RD_E_LOTS");
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   CheckOpened("T-08a Buy without TP", SIDE_BUY, before, sl, 0.0, 0.0);
   CloseTestTrades("after T-08a");
   RestoreTp();
  }

void CUiSelfTest::TradeT08b()
  {
   SetTpMode(TPMODE_AUTO_RR, 2.0);
   ClickButton(PB_ADDLINE);
   Check(!m_plan.Exists(LINEROLE_TP), "T-08b no TP line", "Auto R/R: TP line " + RdBoolText(m_plan.Exists(LINEROLE_TP)));
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_SELL, 1.0, q, sl);
   m_pvLots = Text("RD_E_LOTS");
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_SELL);
   CheckOpened("T-08b Sell, TP at R/R 2", SIDE_SELL, before, sl, -1.0, 2.0);
   CloseTestTrades("after T-08b");
   RestoreTp();
  }

void CUiSelfTest::TradeT08c()
  {
   SetTpMode(TPMODE_MANUAL_LINE, 2.0);
   m_cfg.tpFollowsSl = true;
   ClickButton(PB_ADDLINE);
   SQuote q;
   FreshQuote(q);
   double sl = m_plan.Price(LINEROLE_SL);
   double tp = m_plan.Price(LINEROLE_TP);
   double rr0 = (q.ask - sl > 0.0) ? (tp - q.ask) / (q.ask - sl) : 0.0;
   Check(m_plan.Exists(LINEROLE_TP) && MathAbs(rr0 - 2.0) < 0.1, "T-08c TP line at R/R 2", "SL " + RdFormatPrice(m_ts, sl) +
         ", TP " + RdFormatPrice(m_ts, tp) + ", R/R from Ask " + RdNum(rr0, 3));
   //--- the SL moves: the TP line follows
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   double tp1 = m_plan.Price(LINEROLE_TP);
   FreshQuote(q);
   double rr1 = (q.ask - sl > 0.0) ? (tp1 - q.ask) / (q.ask - sl) : 0.0;
   Check(MathAbs(rr1 - 2.0) < 0.1 && !m_plan.TpFree() && StringFind(Text(CLines::LabelName(LINEROLE_TP)), "TP  +") == 0,
         "T-08c TP follows the SL", "SL " + RdFormatPrice(m_ts, sl) + " -> TP " + RdFormatPrice(m_ts, tp1) + " (R/R " +
         RdNum(rr1, 3) + "), label '" + Text(CLines::LabelName(LINEROLE_TP)) + "'");
   //--- the user drags the TP line: from now on it stays
   double myTp = RdRoundPriceUp(m_ts, q.ask + 3.0 * m_dist);
   DropLine(LINEROLE_TP, myTp);
   PlaceStop(SIDE_BUY, 1.5, q, sl);
   double tp2 = m_plan.Price(LINEROLE_TP);
   Check(m_plan.TpFree() && RdPriceEq(m_ts, tp2, myTp), "T-08c dragged TP stays", "TP dragged to " + RdFormatPrice(m_ts, myTp) +
         ", SL moved to " + RdFormatPrice(m_ts, sl) + ": TP " + RdFormatPrice(m_ts, tp2) + ", placed by the user " +
         RdBoolText(m_plan.TpFree()));
   Shot("t08c_manual_tp");
   m_pvLots = Text("RD_E_LOTS");
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   CheckOpened("T-08c Buy, TP = line", SIDE_BUY, before, sl, myTp, 0.0);
   CloseTestTrades("after T-08c");
   RestoreTp();
  }

//+------------------------------------------------------------------+
//| T-11 total cap: one trade passes; then the cap is set to 1.5 x   |
//| the risk that trade really has (lots are floored, so it is below |
//| Risk %), and the same trade again is refused with the numbers.   |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT11a()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   m_ticket = StatusTicket();
   SPosition p;
   double pct = 0.0;
   if(m_ticket > 0 && FindTestPosition(m_ticket, p) && Base() > 0.0)
      pct = (ExpectedLoss(p.side, p.open, p.sl) + MathMax(0.0, m_cfg.commissionPerLot)) * p.volume / Base() * 100.0;
   m_cfg.maxTotalRiskPct = MathMax(0.01, NormalizeDouble(1.5 * pct, 2));
   Check(after == before + 1 && m_status.Severity() != SEV_ERROR && pct > 0.0, "T-11 first trade", "positions " +
         IntegerToString(before) + " -> " + IntegerToString(after) + ", its risk " + RdFormatPct(pct) + " -> total cap set to " +
         RdNum(m_cfg.maxTotalRiskPct, 2) + " %, status '" + m_status.Text() + "'");
  }

void CUiSelfTest::TradeT11b()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   string st = m_status.Text();
   Check(after == before && m_status.Severity() == SEV_ERROR && StringFind(st, "Total risk too high: open ") >= 0 &&
         StringFind(st, " > " + RdFormatCapPct(m_cfg.maxTotalRiskPct) + " cap") > 0, "T-11 total cap",
         "positions " + IntegerToString(before) + " -> " + IntegerToString(after) + ", status '" + st + "'");
   RestoreTp();
  }

//+------------------------------------------------------------------+
//| F-16 AC3: a RiskDesk position without SL blocks new trades.      |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeF16()
  {
   SPosition p;
   if(m_ticket == 0 || !FindTestPosition(m_ticket, p))
     {
      Line("INFO F-16 no SL: no test position from T-11");
      return;
     }
   SResult r;
   bool removed = m_gw.ModifyPositionSLTP(m_ticket, 0.0, p.tp, r);
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   Check(removed && after == before && m_status.Severity() == SEV_ERROR &&
         StringFind(m_status.Text(), RdTicketText(m_ticket) + " (" + _Symbol + ") has no SL") >= 0, "F-16 position without SL",
         "SL of " + RdTicketText(m_ticket) + " removed " + RdBoolText(removed) + " (" + r.message + "), Buy: positions " +
         IntegerToString(before) + " -> " + IntegerToString(after) + ", status '" + m_status.Text() + "'");
   CloseTestTrades("after F-16");
  }

//+------------------------------------------------------------------+
//| T-12 margin (F-31, BC-09): the buffer leaves half the margin the |
//| trade needs -> refused with the numbers; with InpReduceToMargin  |
//| the affordable lot is sent (amber).                              |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT12a()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   m_pvLots = Text("RD_E_LOTS");
   double lots = StringToDouble(m_pvLots);
   double need = 0.0;
   SResult mr;
   m_money.MarginFor(m_ts, SIDE_BUY, lots, RdNormalizePrice(m_ts, q.ask), need, mr);
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar);
   if(!(need > 0.0) || !(acc.freeMargin > 0.0))
     {
      Line("INFO T-12: margin of " + m_pvLots + " lot unknown (" + mr.message + ")");
      return;
     }
   m_cfg.marginBufferPct = (1.0 - 0.5 * need / acc.freeMargin) * 100.0;
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   string st = m_status.Text();
   Check(after == before && m_status.Severity() == SEV_ERROR && StringFind(st, "Not enough margin: needs ") >= 0 &&
         StringFind(st, " free (") > 0 && StringFind(st, "max ") > 0, "T-12 margin", "buffer " + RdNum(m_cfg.marginBufferPct, 4) +
         " % leaves half of " + RdNum(need, 2) + ": positions " + IntegerToString(before) + " -> " + IntegerToString(after) +
         ", status '" + st + "'");
  }

void CUiSelfTest::TradeT12b()
  {
   m_cfg.reduceToMargin = true;
   SPosition arr[];
   int before = TestPositions(arr);
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   SPosition p;
   ulong ticket = StatusTicket();
   bool found = ticket > 0 && FindTestPosition(ticket, p);
   bool canReduce = StringToDouble(m_pvLots) >= 2.0 * m_ts.volMin - 1e-9;
   if(canReduce)
      Check(after == before + 1 && found && m_status.Severity() == SEV_WARN && StringFind(m_status.Text(), "reduced to ") > 0 &&
            RdVolLt(p.volume, StringToDouble(m_pvLots)), "T-12 reduce to margin", "Lots showed " + m_pvLots + ", sent " +
            (found ? RdFormatLots(m_ts, p.volume) : "?") + ", status '" + m_status.Text() + "'");
   else
      Line("INFO T-12 reduce: " + m_pvLots + " lot cannot be halved on the " + RdFormatLots(m_ts, m_ts.volMin) + " grid; status '" +
           m_status.Text() + "'");
   CloseTestTrades("after T-12");
   RestoreTp();
  }

//+------------------------------------------------------------------+
//| T-25 double click: the second click arrives right after the      |
//| first command returns (a click made while a synchronous trade    |
//| was sent is queued until then). The lines are kept after the     |
//| trade, so only the cooldown can stop a second order.             |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT25()
  {
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   m_cfg.keepLinesAfterTrade = true;
   m_cfg.clickCooldownMs = MathMax(800, m_cooldownWas);
   m_state.clicked[PB_BUY] = false;
   SPosition arr[];
   int before = TestPositions(arr);
   uint t0 = GetTickCount();
   ClickButton(PB_BUY);
   uint took = GetTickCount() - t0;
   string first = m_status.Text();
   ClickButton(PB_BUY);
   int after = TestPositions(arr);
   Check(after == before + 1 && StringFind(first, "Buy ") == 0 && m_status.Text() == first && m_plan.Exists(LINEROLE_SL),
         "T-25 double click", "second Buy right after the first (which took " + IntegerToString((int)took) + " ms, cooldown " +
         IntegerToString(m_cfg.clickCooldownMs) + " ms, lines kept): positions " + IntegerToString(before) + " -> " +
         IntegerToString(after) + ", status '" + m_status.Text() + "'");
   CloseTestTrades("after T-25");
   RestoreTp();
   CLines::DeleteAll();
   m_state.lineMode = LINES_NONE;
  }

//+------------------------------------------------------------------+
//| T-28 risk accuracy: a buy with a tight SL and the TP at R/R 1,   |
//| left until the server closes it (at most 90 s, else closed by    |
//| the test). The broker's booked profit of the price move must     |
//| equal RiskDesk's valuation of the same move within 5 % (the      |
//| valuation that sized the lot and showed the risk).               |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeT28Open()
  {
   SetTpMode(TPMODE_AUTO_RR, 1.0);
   SQuote q;
   FreshQuote(q);
   double tick = RdTick(m_ts);
   double d = MathMax(1.2 * (m_ts.stopsLevel + m_ts.freezeLevel) * m_ts.point + 2.0 * (q.ask - q.bid) + 5.0 * tick,
                      0.0003 * q.bid);
   d = MathCeil(d / tick - 1e-9) * tick;
   double ask = RdNormalizePrice(m_ts, q.ask);
   double sl = RdRoundPriceDown(m_ts, q.bid - d);
   double loss = ExpectedLoss(SIDE_BUY, ask, sl);
   double base = Base();
   double minPct = (base > 0.0) ? m_ts.volMin * (loss + MathMax(0.0, m_cfg.commissionPerLot)) / base * 100.0 : 0.0;
   double pct = MathMax(0.01, MathCeil(minPct * 2.5 * 100.0 - 1e-9) / 100.0);
   if(!(loss > 0.0) || pct > 1.0)
     {
      Line("INFO T-28: no safe test lot at a " + RdFormatPrice(m_ts, d) + " SL");
      m_t28Start = 0;
      return;
     }
   Edit(DoubleToString(pct, 2));
   ClickButton(PB_ADDLINE);
   DropLine(LINEROLE_SL, sl);
   m_pvLots = Text("RD_E_LOTS");
   SPosition arr[];
   int before = TestPositions(arr);
   m_t28From = RdServerTime();
   ClickButton(PB_BUY);
   SPosition p;
   ulong ticket = StatusTicket();
   if(TestPositions(arr) != before + 1 || ticket == 0 || !FindTestPosition(ticket, p))
     {
      Check(false, "T-28 open", "status '" + m_status.Text() + "'");
      m_t28Start = 0;
      Edit(DoubleToString(m_testRisk, 2));
      return;
     }
   m_ticket = ticket;
   m_t28Side = p.side;
   m_t28Open = p.open;
   m_t28Sl = p.sl;
   m_t28Vol = p.volume;
   m_t28Risk = ExpectedLoss(SIDE_BUY, p.open, p.sl) * p.volume;
   m_t28Start = GetTickCount();
   m_t28Closed = false;
   Line("T-28 setup: " + RdTicketText(ticket) + " buy " + RdFormatLots(m_ts, p.volume) + " @" + RdFormatPrice(m_ts, p.open) +
        ", SL " + RdFormatPrice(m_ts, p.sl) + ", TP " + RdFormatPrice(m_ts, p.tp) + ", status '" + m_status.Text() +
        "'; waiting up to " + IntegerToString(RD_UITEST_T28_S) + " s for the SL or TP");
   Edit(DoubleToString(m_testRisk, 2));
  }

bool CUiSelfTest::TradeT28Wait()
  {
   if(m_t28Start == 0)
      return true;
   SPosition p;
   if(!FindTestPosition(m_ticket, p))
     {
      m_t28Closed = true;   // closed by the server: SL or TP hit
      return true;
     }
   if((uint)(GetTickCount() - m_t28Start) < (uint)RD_UITEST_T28_S * 1000)
     {
      m_nextAt = GetTickCount() + 1000;
      return false;
     }
   STradeOutcome out;
   SResult r;
   m_gw.ClosePosition(m_ticket, 0.0, out, r);
   Line("T-28: neither SL nor TP hit in " + IntegerToString(RD_UITEST_T28_S) + " s - closed by the test (" + r.message + ")");
   return true;
  }

void CUiSelfTest::TradeT28Check()
  {
   if(m_t28Start == 0)
      return;
   Sleep(500);   // the deal reaches the history a moment after the close
   SClosedTrade arr[];
   SResult r;
   CHistory::ClosedTrades(_Symbol, m_t28From - 120, arr, r);
   double gross = 0.0;
   double vol = 0.0;
   double priceVol = 0.0;
   for(int i = 0; i < ArraySize(arr); i++)
      if(arr[i].ticket == m_ticket && arr[i].magic == RD_UITEST_MAGIC)
        {
         gross += arr[i].grossProfit;
         vol += arr[i].volume;
         priceVol += arr[i].closePrice * arr[i].volume;
        }
   if(!(vol > 0.0))
     {
      Check(false, "T-28 history", "no closing deal of " + RdTicketText(m_ticket) + " in the history (" + r.message + ")");
      return;
     }
   double close = priceVol / vol;
   bool losing = RdPriceLt(m_ts, close, m_t28Open);
   double v = 0.0;
   SResult vr;
   SAccountSpec acc;
   SResult ar;
   CAccountSpec::Read(acc, ar);
   if(RdPriceEq(m_ts, close, m_t28Open))
      v = 0.0;
   else
      if(losing)
         m_money.LossPerLot(m_ts, acc.currency, SIDE_BUY, m_t28Open, close, v, vr);
      else
         m_money.ProfitPerLot(m_ts, acc.currency, SIDE_BUY, m_t28Open, close, v, vr);
   double valued = (losing ? -v : v) * vol;
   double tol = MathMax(0.05 * MathAbs(valued), 2.0 * MathPow(10.0, -RdAccountCurrencyDigits()));
   bool hitSl = m_t28Closed && losing;
   // BC-05 / Q21: when the MT4 tick value and contract x rate disagree, RiskDesk values a move
   // conservatively (the larger loss, the smaller profit): then it may only err on that side.
   bool conservative = (vr.sev == SEV_WARN);
   bool ok = MathAbs(gross - valued) <= tol || (conservative && valued <= gross + tol);
   Check(ok, "T-28 risk accuracy", (conservative ? "[conservative valuation: " + vr.message + "] " : "") +
         RdTicketText(m_ticket) + " " + RdNum(vol, 2) + " lot " +
         RdFormatPrice(m_ts, m_t28Open) + " -> " + RdFormatPrice(m_ts, close) + (m_t28Closed ? (losing ? " (SL hit)" : " (TP hit)") :
         " (closed by the test)") + ": broker booked " + RdMoney(acc, gross) + ", RiskDesk values the move at " +
         RdMoney(acc, valued) + " (" + (MathAbs(valued) > 0.0 ? RdNum(MathAbs(gross - valued) / MathAbs(valued) * 100.0, 2) +
         " % apart" : "no move") + ", tolerance " + RdNum(tol, 2) + ")" + (hitSl ? "; displayed risk without commission " +
         RdMoney(acc, m_t28Risk) + ", booked loss " + RdNum(-gross / m_t28Risk * 100.0, 1) + " % of it (slippage " +
         RdFormatPoints(RdPointsBetween(m_ts, close, m_t28Sl)) + ")" : ""));
   RestoreTp();
  }

//+------------------------------------------------------------------+
//| BC-10 netting (A6): a second buy merges after the confirmation;  |
//| a sell is refused by default; with InpNettingAllowOpposite it    |
//| reduces the position after its own confirmation.                 |
//+------------------------------------------------------------------+
void CUiSelfTest::TradeNet1()
  {
   CloseTestTrades("before the netting steps");
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_BUY, 1.0, q, sl);
   string lots1 = Text("RD_E_LOTS");
   ClickButton(PB_BUY);
   SPosition p;
   ulong t1 = StatusTicket();
   bool first = t1 > 0 && FindTestPosition(t1, p);
   ClickButton(PB_ADDLINE);
   PlaceStop(SIDE_BUY, 1.2, q, sl);
   string lots2 = Text("RD_E_LOTS");
   ClickButton(PB_BUY);
   string st = m_status.Text();
   SPosition arr[];
   int n = TestPositions(arr);
   double vol = (n == 1) ? arr[0].volume : 0.0;
   bool merged = first && n == 1 && StringFind(m_cmd.LastConfirm(), "merges with the open buy " + lots1 + " lot position") >= 0 &&
                 StringFind(st, "merged with the open") > 0 &&
                 RdFormatLots(m_ts, vol) == RdFormatLots(m_ts, StringToDouble(lots1) + StringToDouble(lots2)) &&
                 RdPriceEq(m_ts, arr[0].sl, sl);
   Check(merged, "BC-10 netting merge", "buy " + lots1 + " then buy " + lots2 + ": " + IntegerToString(n) + " position(s), " +
         RdFormatLots(m_ts, vol) + " lot, SL " + (n == 1 ? RdFormatPrice(m_ts, arr[0].sl) : "?") + " (new line " +
         RdFormatPrice(m_ts, sl) + "), confirmation '" + m_cmd.LastConfirm() + "', status '" + st + "'");
   Shot("netting_merge");
  }

void CUiSelfTest::TradeNet2()
  {
   SPosition arr[];
   int n = TestPositions(arr);
   double vol = (n == 1) ? arr[0].volume : 0.0;
   ClickButton(PB_ADDLINE);
   SQuote q;
   double sl = 0.0;
   PlaceStop(SIDE_SELL, 1.0, q, sl);
   ClickButton(PB_SELL);
   TestPositions(arr);
   bool kept = ArraySize(arr) == 1 && RdVolEq(arr[0].volume, vol);
   Check(kept && m_status.Severity() == SEV_ERROR && StringFind(m_status.Text(), "would reduce or reverse the open buy") >= 0,
         "BC-10 opposite refused", "sell against the " + RdNum(vol, 2) + " lot buy: status '" + m_status.Text() + "'");
   m_cfg.nettingAllowOpposite = true;
   string lotsS = Text("RD_E_LOTS");
   double sellLots = StringToDouble(lotsS);
   ClickButton(PB_SELL);
   TestPositions(arr);
   double rest = (ArraySize(arr) == 1) ? arr[0].volume : 0.0;
   bool reduces = RdVolLt(sellLots, vol);
   bool ok = reduces ? (StringFind(m_cmd.LastConfirm(), "reduces the open buy") >= 0 && StringFind(m_status.Text(), "reduced to") > 0 &&
                        RdVolEq(rest, vol - sellLots)) : (m_status.Severity() != SEV_ERROR);
   Check(ok, "BC-10 opposite allowed", "InpNettingAllowOpposite: sell " + lotsS + " against " + RdNum(vol, 2) + " lot -> " +
         RdNum(rest, 2) + " lot left, confirmation '" + m_cmd.LastConfirm() + "', status '" + m_status.Text() + "'");
   CloseTestTrades("after the netting steps");
   RestoreTp();
  }

#endif // RD_APP_UISELFTESTTRADEORDERS_MQH
