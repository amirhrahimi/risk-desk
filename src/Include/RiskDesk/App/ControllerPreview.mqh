//+------------------------------------------------------------------+
//| RiskDesk - App/ControllerPreview.mqh                             |
//| Layer   : App                                                    |
//| Purpose : CController's handling of the planning lines:          |
//|           - adopt the lines found on the chart (F-23), detect a  |
//|             line deleted by hand (05 section 5 "Mode rules")     |
//|           - the live preview: Lots (OP-15, F-03), Pending Info   |
//|             (OP-06, F-08), the line labels (F-18) and the side   |
//|             the lines make invalid (F-33); computed only when    |
//|             lines, prices, Risk % or the account changed         |
//|           - a dropped line: snapped to the tick grid (BC-03),    |
//|             manual TP line follows (InpTpFollowsSl)              |
//|           - the screenshot after a command (F-19)                |
//|           Part of CController; included at the end of           |
//|           App/Controller.mqh.                                    |
//+------------------------------------------------------------------+
#ifndef RD_APP_CONTROLLERPREVIEW_MQH
#define RD_APP_CONTROLLERPREVIEW_MQH

//+------------------------------------------------------------------+
//| OnInit: the lines on the chart decide the mode (a timeframe      |
//| change or a restart keeps them, 02 section 8).                   |
//+------------------------------------------------------------------+
void CController::AdoptLines()
  {
   ELineMode mode = m_lines.ModeOnChart();
   if(mode == LINES_NONE)
      CLines::DeleteAll();   // stray pieces (a TP line without SL, labels)
   else
     {
      m_lines.Restyle();
      SLines l;
      m_lines.Read(mode, l);
      int digits = m_specOk ? m_spec.digits : _Digits;
      RD_LOG_INFO("Planning lines on the chart adopted: " + (mode == LINES_PENDING ? "pending, entry " +
                  DoubleToString(l.entry, digits) + ", " : "market, ") + "SL " + DoubleToString(l.sl, digits) +
                  (l.hasTp ? ", TP " + DoubleToString(l.tp, digits) : ""));
     }
   m_state.lineMode = mode;
   m_tpWas = m_lines.Exists(LINEROLE_TP);
   m_pv.key = "";
  }

//+------------------------------------------------------------------+
//| A line deleted by hand (object list, Delete key) drops to a      |
//| consistent mode on the next refresh, with an amber note.         |
//+------------------------------------------------------------------+
void CController::SyncLines()
  {
   ELineMode mode = m_state.lineMode;
   string note = "";
   if(mode == LINES_MARKET && !m_lines.Exists(LINEROLE_SL))
     {
      CLines::DeleteAll();
      mode = LINES_NONE;
      note = "SL line deleted from the chart - RiskDesk's lines removed";
     }
   else
      if(mode == LINES_PENDING && (!m_lines.Exists(LINEROLE_ENTRY) || !m_lines.Exists(LINEROLE_SL)))
        {
         string gone = m_lines.Exists(LINEROLE_ENTRY) ? "SL" : "Entry";
         CLines::DeleteAll();
         mode = LINES_NONE;
         note = gone + " line deleted from the chart - RiskDesk's lines removed";
        }
      else
         if(mode != LINES_NONE && m_tpWas && !m_lines.Exists(LINEROLE_TP))
            note = "TP line deleted from the chart - orders go without TP now (" +
                   (mode == LINES_MARKET ? "Add Line" : "Add Pend Line") + " puts it back)";
         else
            if(mode == LINES_NONE && m_lines.ModeOnChart() != LINES_NONE)
              {
               AdoptLines();   // lines appeared (e.g. restored by the terminal)
               mode = m_state.lineMode;
              }
   //--- labels whose line is gone
   for(int i = 0; i < RD_LINE_ROLES; i++)
     {
      ELineRole role = (ELineRole)i;
      if(!m_lines.Exists(role) && m_lines.LabelExists(role))
         m_lines.HideLabel(role);
     }
   if(mode != m_state.lineMode)
     {
      m_state.lineMode = mode;
      m_pv.key = "";
     }
   m_tpWas = m_lines.Exists(LINEROLE_TP);
   if(note != "")
     {
      m_pv.key = "";
      SResult r;
      RdWarn(r, note);
      Report(r);
     }
  }

//+------------------------------------------------------------------+
void CController::ComputePreview(const SQuote &q, const bool quoteOk)
  {
   ELineMode mode = m_state.lineMode;
   SLines l;
   m_lines.Read(mode, l);
   SAccountSpec acc;
   SResult ar;
   bool accOk = CAccountSpec::Read(acc, ar);
   string key = IntegerToString(mode) + "|" + DoubleToString(l.entry, 8) + "|" + DoubleToString(l.sl, 8) + "|" +
                (l.hasTp ? DoubleToString(l.tp, 8) : "-") + "|" + DoubleToString(q.bid, 8) + "|" + DoubleToString(q.ask, 8) +
                "|" + DoubleToString(m_state.riskPct, 2) + "|" + DoubleToString(acc.balance, 2) + "|" +
                (m_cfg.riskBase != RISKBASE_BALANCE ? DoubleToString(acc.equity, 2) : "") + "|" + IntegerToString(m_specAt) +
                "|" + (quoteOk ? "q" : "-") + (m_specOk ? "s" : "-") + (accOk ? "a" : "-");
   if(key == m_pv.key)
      return;
   m_pv.Reset();
   m_pv.key = key;
   m_pv.lotsText = RdGlyphDash();
   m_pv.lotsTip = "Lots for Risk % and the SL line (read-only); " + RdGlyphDash() + " while no lines are on the chart";
   m_pv.pinfoTip = "Pending order type implied by the Entry and SL lines (Add Pend Line)";
   if(mode == LINES_NONE)
      return;
   if(!quoteOk || !m_specOk || !accOk)
     {
      string why = !m_specOk ? m_specMsg : (!quoteOk ? "no quote for " + _Symbol : ar.message);
      m_pv.lotsTip = "Lots cannot be computed: " + why;
      m_pv.label[LINEROLE_SL] = "SL  (" + why + ")";
      m_pv.labelColor[LINEROLE_SL] = m_status.WarnColor();
      return;
     }
   SPlanSettings p;
   m_cfg.Plan(p);
   if(mode == LINES_MARKET)
      PreviewMarket(l, q, acc, p);
   else
      PreviewPending(l, q, acc, p);
  }

// "SL  -$100.00 (1.00 %) . 0.50 lot . 200 pts" (F-18 AC1)
string CController::RiskLabel(const SAccountSpec &acc, const STradePlan &plan) const
  {
   return "SL  " + RdGlyphMinus() + RdMoney(acc, plan.riskMoney) + " (" + RdFormatPct(plan.riskPct) + ")" + RdSep() +
          RdFormatLots(m_spec, plan.lots) + " lot" + RdSep() + RdFormatPoints(RdPointsBetween(m_spec, plan.entry, plan.sl));
  }

// "TP  +$200.00 (R 2.00) . 400 pts"
string CController::RewardLabel(const SAccountSpec &acc, const STradePlan &plan) const
  {
   return "TP  +" + RdMoney(acc, plan.rewardMoney) + " (R " + DoubleToString(plan.rr, 2) + ")" + RdSep() +
          RdFormatPoints(RdPointsBetween(m_spec, plan.entry, plan.tp));
  }

//+------------------------------------------------------------------+
//| OP-15 market mode: side from the SL (04 section 6), entry = Ask  |
//| or Bid; the SL alone decides the lots; a manual TP line on the   |
//| wrong side makes the trade invalid ("-") but the SL label keeps  |
//| its risk. F-33: each side checked on its own.                    |
//+------------------------------------------------------------------+
void CController::PreviewMarket(const SLines &l, const SQuote &q, const SAccountSpec &acc, const SPlanSettings &p)
  {
   STradePlan pb;
   STradePlan ps;
   SResult rb;
   SResult rs;
   m_pv.dimBuy = !CPlanner::Market(SIDE_BUY, l, q, m_spec, p, pb, rb);
   m_pv.dimSell = !CPlanner::Market(SIDE_SELL, l, q, m_spec, p, ps, rs);
   m_pv.buyWhy = rb.message;
   m_pv.sellWhy = rs.message;

   color warn = m_status.WarnColor();
   ESide side = SIDE_BUY;
   SResult sr;
   if(!CValidators::PreviewSide(RdNormalizePrice(m_spec, l.sl), q, m_spec, side, sr))
     {
      m_pv.label[LINEROLE_SL] = "SL  (invalid: " + sr.message + ")";
      m_pv.labelColor[LINEROLE_SL] = warn;
      m_pv.lotsTip = "No trade: " + sr.message;
      if(l.hasTp)
        {
         m_pv.label[LINEROLE_TP] = "TP";
         m_pv.labelColor[LINEROLE_TP] = m_lines.LineColor(LINEROLE_TP);
        }
      return;
     }
   SLines slOnly = l;
   slOnly.hasTp = false;
   slOnly.tp = 0.0;
   STradePlan plan;
   SResult pr;
   if(!CPlanner::Market(side, slOnly, q, m_spec, p, plan, pr))
     {
      m_pv.label[LINEROLE_SL] = "SL  (invalid: " + pr.message + ")";
      m_pv.labelColor[LINEROLE_SL] = warn;
      m_pv.lotsTip = "No trade: " + pr.message;
      return;
     }
   bool tpOk = true;
   string tpWhy = "";
   if(m_cfg.tpMode == TPMODE_MANUAL_LINE && l.hasTp)
     {
      STradePlan full;
      SResult fr;
      tpOk = CPlanner::Market(side, l, q, m_spec, p, full, fr);
      if(tpOk)
         plan.tp = full.tp;
      else
         tpWhy = fr.message;
     }
   double loss = 0.0;
   SResult lr;
   if(!m_money.LossPerLot(m_spec, acc.currency, side, plan.entry, plan.sl, loss, lr))
     {
      m_pv.label[LINEROLE_SL] = "SL  (" + lr.message + ")";
      m_pv.labelColor[LINEROLE_SL] = warn;
      m_pv.lotsTip = lr.message;
      return;
     }
   double profit = 0.0;
   if(plan.tp > 0.0 && tpOk)
     {
      SResult tr;
      if(!m_money.ProfitPerLot(m_spec, acc.currency, side, plan.entry, plan.tp, profit, tr))
         profit = 0.0;
     }
   SLotResult lot;
   SResult zr;
   if(!CPlanner::Size(plan, m_spec, acc, p, m_state.riskPct, loss, profit, 0.0, lot, zr))
     {
      m_pv.lotsTip = zr.message;
      m_pv.labelColor[LINEROLE_SL] = warn;
      if(lot.belowMin)
        {
         // F-03 AC3: the computed lot in red
         m_pv.lotsText = RdNum(lot.rawLots, RdLotDigits(m_spec) + 1) + " < " + RdFormatLots(m_spec, m_spec.volMin);
         m_pv.lotsWarn = true;
         m_pv.label[LINEROLE_SL] = "SL  min lot " + RdFormatLots(m_spec, m_spec.volMin) + " risks " +
                                   RdMoney(acc, lot.minLotRisk) + " (" + RdFormatPct(lot.minLotPct) + ")" + RdSep() +
                                   RdFormatPoints(RdPointsBetween(m_spec, plan.entry, plan.sl));
        }
      else
         m_pv.label[LINEROLE_SL] = "SL  (" + zr.message + ")";
      return;
     }
   m_pv.label[LINEROLE_SL] = RiskLabel(acc, plan);
   m_pv.labelColor[LINEROLE_SL] = m_lines.LabelColor();
   m_pv.lotsText = tpOk ? RdFormatLots(m_spec, plan.lots) : RdGlyphDash();
   m_pv.lotsTip = RdOrderText(side, KIND_MARKET) + " " + RdFormatLots(m_spec, plan.lots) + " lot: " + RdMoney(acc, plan.riskMoney) +
                  " (" + RdFormatPct(plan.riskPct) + ") lost at the SL" + (zr.sev == SEV_WARN ? " - " + zr.message : "") +
                  (lr.sev == SEV_WARN ? " - " + lr.message : "");
   if(m_cfg.tpMode == TPMODE_MANUAL_LINE && l.hasTp)
     {
      if(tpOk)
        {
         m_pv.label[LINEROLE_TP] = RewardLabel(acc, plan);
         m_pv.labelColor[LINEROLE_TP] = m_lines.LineColor(LINEROLE_TP);
        }
      else
        {
         m_pv.label[LINEROLE_TP] = "TP  (invalid: " + tpWhy + ")";
         m_pv.labelColor[LINEROLE_TP] = warn;
         m_pv.lotsTip = "No trade: " + tpWhy;
        }
     }
  }

//+------------------------------------------------------------------+
//| OP-06 / F-08 pending mode: classification (04 section 7), lots   |
//| from Entry - SL, Pending Info "Buy Stop . 0.35 lot".             |
//+------------------------------------------------------------------+
void CController::PreviewPending(const SLines &l, const SQuote &q, const SAccountSpec &acc, const SPlanSettings &p)
  {
   color warn = m_status.WarnColor();
   STradePlan plan;
   SResult pr;
   bool ok = CPlanner::Pending(l, q, m_spec, p, plan, pr);
   m_pv.label[LINEROLE_SL] = "SL";
   m_pv.labelColor[LINEROLE_SL] = m_lines.LabelColor();
   if(l.hasTp)
     {
      m_pv.label[LINEROLE_TP] = "TP";
      m_pv.labelColor[LINEROLE_TP] = m_lines.LineColor(LINEROLE_TP);
     }
   if(!ok)
     {
      m_pv.pinfoText = "Invalid: " + pr.message;
      m_pv.pinfoWarn = true;
      m_pv.pinfoTip = pr.message;
      m_pv.lotsTip = "No order: " + pr.message;
      m_pv.label[LINEROLE_ENTRY] = "ENTRY  (invalid: " + pr.message + ")";
      m_pv.labelColor[LINEROLE_ENTRY] = warn;
      return;
     }
   string kind = RdOrderText(plan.side, plan.kind);
   m_pv.label[LINEROLE_ENTRY] = "ENTRY  " + kind + "  " + RdFormatPrice(m_spec, plan.entry);
   m_pv.labelColor[LINEROLE_ENTRY] = m_lines.LineColor(LINEROLE_ENTRY);
   double loss = 0.0;
   SResult lr;
   if(!m_money.LossPerLot(m_spec, acc.currency, plan.side, plan.entry, plan.sl, loss, lr))
     {
      m_pv.pinfoText = kind;
      m_pv.lotsTip = lr.message;
      m_pv.label[LINEROLE_SL] = "SL  (" + lr.message + ")";
      m_pv.labelColor[LINEROLE_SL] = warn;
      return;
     }
   double profit = 0.0;
   if(plan.tp > 0.0)
     {
      SResult tr;
      if(!m_money.ProfitPerLot(m_spec, acc.currency, plan.side, plan.entry, plan.tp, profit, tr))
         profit = 0.0;
     }
   SLotResult lot;
   SResult zr;
   if(!CPlanner::Size(plan, m_spec, acc, p, m_state.riskPct, loss, profit, 0.0, lot, zr))
     {
      m_pv.pinfoText = kind + RdSep() + (lot.belowMin ? "below min lot" : "not tradable");
      m_pv.pinfoWarn = true;
      m_pv.pinfoTip = zr.message;
      m_pv.lotsTip = zr.message;
      m_pv.labelColor[LINEROLE_SL] = warn;
      if(lot.belowMin)
        {
         m_pv.lotsText = RdNum(lot.rawLots, RdLotDigits(m_spec) + 1) + " < " + RdFormatLots(m_spec, m_spec.volMin);
         m_pv.lotsWarn = true;
         m_pv.label[LINEROLE_SL] = "SL  min lot " + RdFormatLots(m_spec, m_spec.volMin) + " risks " +
                                   RdMoney(acc, lot.minLotRisk) + " (" + RdFormatPct(lot.minLotPct) + ")";
        }
      else
         m_pv.label[LINEROLE_SL] = "SL  (" + zr.message + ")";
      return;
     }
   m_pv.pinfoText = kind + RdSep() + RdFormatLots(m_spec, plan.lots) + " lot";
   m_pv.pinfoTip = kind + " " + RdFormatLots(m_spec, plan.lots) + " lot at " + RdFormatPrice(m_spec, plan.entry) +
                   ": " + RdMoney(acc, plan.riskMoney) + " (" + RdFormatPct(plan.riskPct) + ") lost at the SL";
   m_pv.lotsText = RdFormatLots(m_spec, plan.lots);
   m_pv.lotsTip = m_pv.pinfoTip + (zr.sev == SEV_WARN ? " - " + zr.message : "");
   m_pv.label[LINEROLE_SL] = RiskLabel(acc, plan);
   if(m_cfg.tpMode == TPMODE_MANUAL_LINE && l.hasTp)
      m_pv.label[LINEROLE_TP] = RewardLabel(acc, plan);
  }

//+------------------------------------------------------------------+
//| Labels at their lines (also when only the bar time moved). True  |
//| when a label object had to be created (the panel goes on top).   |
//+------------------------------------------------------------------+
bool CController::ApplyLabels()
  {
   bool created = false;
   for(int i = 0; i < RD_LINE_ROLES; i++)
     {
      ELineRole role = (ELineRole)i;
      if(m_state.lineMode != LINES_NONE && m_lines.Exists(role) && m_pv.label[i] != "")
        {
         if(m_lines.ShowLabel(role, m_pv.label[i], m_pv.labelColor[i] == clrNONE ? m_lines.LineColor(role) : m_pv.labelColor[i]))
            created = true;
        }
      else
         m_lines.HideLabel(role);
     }
   return created;
  }

//+------------------------------------------------------------------+
//| Lots, Pending Info and F-33 dimming into the panel model.        |
//+------------------------------------------------------------------+
void CController::ApplyPreview(SPanelModel &m) const
  {
   m.lotsText = m_pv.lotsText;
   m.lotsWarn = m_pv.lotsWarn;
   m.lotsTip = m_pv.lotsTip;
   m.pinfoText = m_pv.pinfoText;
   m.pinfoWarn = m_pv.pinfoWarn;
   m.pinfoTip = m_pv.pinfoTip;
   if(m_state.lineMode != LINES_MARKET || !m_cfg.dimInvalidSide)
      return;
   if(m_pv.dimBuy && m.buttonLook[PB_BUY] == LOOK_NORMAL)
     {
      m.buttonLook[PB_BUY] = LOOK_DIM;
      m.buttonTip[PB_BUY] = "Not possible with these lines: " + m_pv.buyWhy;
     }
   if(m_pv.dimSell && m.buttonLook[PB_SELL] == LOOK_NORMAL)
     {
      m.buttonLook[PB_SELL] = LOOK_DIM;
      m.buttonTip[PB_SELL] = "Not possible with these lines: " + m_pv.sellWhy;
     }
  }

//+------------------------------------------------------------------+
//| A planning line was dropped: snap to the tick grid (BC-03: what  |
//| you see is what is sent); the TP line becomes the user's; a      |
//| moved SL/Entry pulls the manual TP line along (InpTpFollowsSl).  |
//+------------------------------------------------------------------+
void CController::LineDropped(const ELineRole role)
  {
   if(!m_specOk)
      ReadSpec();
   if(!m_lines.Exists(role))
      return;
   double raw = m_lines.Price(role);
   double price = m_specOk ? RdNormalizePrice(m_spec, raw) : raw;
   if(price > 0.0)
      m_lines.Place(role, price);
   int digits = m_specOk ? m_spec.digits : _Digits;
   string what = CLines::RoleText(role) + " line moved to " + DoubleToString(price, digits);
   if(role == LINEROLE_TP)
     {
      if(m_cfg.tpFollowsSl && !m_lines.TpFree())
        {
         m_lines.SetTpFree(true);
         what += " (placed by you: it no longer follows the SL)";
        }
     }
   else
      if(m_cfg.tpMode == TPMODE_MANUAL_LINE && m_cfg.tpFollowsSl && m_lines.Exists(LINEROLE_TP) && !m_lines.TpFree() &&
         m_specOk && m_state.lineMode != LINES_NONE)
        {
         SQuote q;
         SLines l;
         m_lines.Read(m_state.lineMode, l);
         SPlanSettings p;
         m_cfg.Plan(p);
         double tp = 0.0;
         SResult fr;
         if(CMarket::Quote(_Symbol, q) && CPlanner::FollowTp(l, q, m_spec, p, tp, fr))
           {
            m_lines.Place(LINEROLE_TP, tp);
            what += ", TP line follows to " + DoubleToString(tp, digits) + " (R/R " + RdNum(m_cfg.tpRR, 2) + ")";
           }
         else
            what += ", TP line stays (" + fr.message + ")";
        }
   RD_LOG_INFO(what);
   m_pv.key = "";
   Refresh();
  }

//+------------------------------------------------------------------+
//| F-19 / OP-14: after the command's status is drawn. A trade       |
//| screenshot that fails turns the status amber (rule R8).          |
//+------------------------------------------------------------------+
void CController::TakeShot(SResult &r)
  {
   string action = "";
   ulong ticket = 0;
   if(!m_cmd.TakeShot(action, ticket))
      return;
   bool manual = (action == "manual");
   if(!manual && !m_cfg.autoScreenshot)
      return;
   string path = "";
   SResult sr;
   bool ok = CScreenshot::Take(action, ticket, m_cfg.shotWidth, m_cfg.shotHeight, path, sr);
   if(ok && sr.sev == SEV_OK)
      m_state.lastShot = path;
   if(manual)
     {
      SResult mr;
      if(ok && sr.sev == SEV_OK)
         RdOk(mr, "Screenshot saved: " + RD_MQL_DIR + "\\Files\\" + path);
      else
         if(ok)
            RdWarn(mr, "Screenshot: " + sr.message);
         else
            RdFail(mr, "Screenshot failed: " + sr.message);
      Report(mr);
      Refresh();
      return;
     }
   if(ok)
      return;
   r.message = r.message + " - " + sr.message;
   if(r.sev == SEV_OK)
      r.sev = SEV_WARN;
   Report(r);
   Refresh();
  }

#endif // RD_APP_CONTROLLERPREVIEW_MQH
