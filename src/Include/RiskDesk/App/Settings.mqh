//+------------------------------------------------------------------+
//| RiskDesk - App/Settings.mqh                                      |
//| Layer   : App                                                    |
//| Purpose : validated snapshot of the inputs (07-settings) plus    |
//|           derived values (ETpMode, ADR-013). Load() is the only  |
//|           place that reads an Inp* variable. Out-of-range values |
//|           are clamped and reported: one warning per input, shown |
//|           in the status bar on init and written to the log.      |
//|           Plan() / Gateway() fill the settings structs of the    |
//|           Domain (SPlanSettings) and the trade gateway           |
//|           (SGatewaySettings).                                    |
//|                                                                  |
//| CSettings is a plain record: fields are public and read-only by  |
//| convention after Load() (modules hold a pointer to it).          |
//+------------------------------------------------------------------+
#ifndef RD_APP_SETTINGS_MQH
#define RD_APP_SETTINGS_MQH

#include "..\Domain\Types.mqh"
#include "..\Platform\TradeGatewayBase.mqh"
#include "Inputs.mqh"

class CSettings
  {
private:
   string            m_warnings[];

   void              Warn(const string text);
   double            ClampD(const string name, const double value, const double lo, const double hi, const double fallback);
   int               ClampI(const string name, const int value, const int lo, const int hi);

public:
   //--- Risk
   double            defaultRiskPct;
   double            maxRiskPerTradePct;
   double            maxTotalRiskPct;
   ERiskBase         riskBase;
   bool              includePendingInTotalRisk;
   double            commissionPerLot;
   bool              allowMinLotOverRisk;
   double            marginBufferPct;
   bool              reduceToMargin;
   //--- Take profit
   bool              tradeWithTpLine;
   bool              manualTpLine;
   double            tpRR;
   bool              tpFollowsSl;
   ETpMode           tpMode;               // derived (ADR-013)
   //--- Execution
   long              magic;
   string            comment;
   int               slippagePoints;
   int               maxRetries;
   int               retryDelayMs;
   EFillingOverride  fillingOverride;
   EStopsMode        stopsMode;
   bool              closeIfStopFails;
   int               pendingExpiryHours;
   bool              nettingAllowOpposite;
   int               clickCooldownMs;
   //--- Management
   EScopeChart       scopeChartOps;
   EScopeAccount     scopeFullClose;
   bool              fullCloseAlsoPending;
   ERiskFreeMode     riskFreeMode;
   int               riskFreeExtraPoints;
   double            partialClosePct;
   EIndivisible      partialIndivisible;
   bool              keepLinesAfterTrade;
   bool              confirmTrades;
   bool              confirmHalfClose;
   bool              confirmChartClose;
   bool              confirmFullClose;
   //--- Chart extras
   EClosedTradeObjects closedTradeObjects;
   bool              showCandleTime;
   int               candleTimeFontSize;
   color             colorCandleTime;
   color             colorCandleTimeWarn;
   int               candleTimeWarnSec;
   int               slLossFontSize;
   bool              autoScreenshot;
   int               shotWidth;
   int               shotHeight;
   bool              showPendingOverlay;
   double            defaultOffsetPct;
   //--- Panel / Font
   EFontPreset       fontPreset;
   int               fontSize;
   double            scale;
   bool              autoFitPanel;
   EPanelColumns     panelColumns;
   int               panelX;
   int               panelY;
   bool              startHidden;
   bool              showPricesOnButtons;
   bool              dimInvalidSide;
   ESpreadUnit       spreadUnit;
   int               spreadWarnPts;
   int               statusHoldSec;
   int               refreshMs;
   //--- Colors
   color             colorEntry;
   color             colorPendOverlayEntry;
   color             colorPendOverlaySL;
   color             colorPendOverlayTP;
   color             colorSL;
   color             colorTP;
   color             colorSlLoss;
   int               lineWidth;
   color             colorAddLine;
   color             colorDeleteLine;
   color             colorBuy;
   color             colorSell;
   color             colorAddPendLine;
   color             colorSetPending;
   color             colorPendingInfo;
   color             colorDelPending;
   color             colorRiskFree;
   color             colorHalfClose;
   color             colorChartClose;
   color             colorFullClose;
   color             colorSpread;
   color             colorBg;
   color             colorSystemBorder;
   color             colorButtonBorder;
   color             colorText;
   //--- Account
   ECentMode         centMode;
   double            centDivisor;
   int               staleQuoteSec;
   //--- Diagnostics
   ELogLevel         logLevel;
   bool              logToFile;
   //--- Test hooks (always false in a release build)
   bool              testUiSelfTest;

   void              Load();
   int               WarningCount() const { return ArraySize(m_warnings); }
   string            Warning(const int i) const { return m_warnings[i]; }
   string            WarningsText() const;
   void              Plan(SPlanSettings &p) const;
   void              Gateway(SGatewaySettings &g) const;
   string            TpModeText() const;
   string            Summary() const;
  };

//+------------------------------------------------------------------+
void CSettings::Warn(const string text)
  {
   int n = ArraySize(m_warnings);
   ArrayResize(m_warnings, n + 1);
   m_warnings[n] = text;
  }

//+------------------------------------------------------------------+
//| Out of [lo, hi] or not a number -> clamp (NaN -> fallback) and   |
//| one warning naming the input, the value and the value used.      |
//+------------------------------------------------------------------+
double CSettings::ClampD(const string name, const double value, const double lo, const double hi, const double fallback)
  {
   if(!MathIsValidNumber(value))
     {
      Warn(name + " is not a number - using " + RdNum(fallback, 4));
      return fallback;
     }
   if(value < lo - 1e-12)
     {
      Warn(name + " " + RdNum(value, 4) + " is below " + RdNum(lo, 4) + " - using " + RdNum(lo, 4));
      return lo;
     }
   if(value > hi + 1e-12)
     {
      Warn(name + " " + RdNum(value, 4) + " is above " + RdNum(hi, 4) + " - using " + RdNum(hi, 4));
      return hi;
     }
   return value;
  }

int CSettings::ClampI(const string name, const int value, const int lo, const int hi)
  {
   if(value < lo)
     {
      Warn(name + " " + IntegerToString(value) + " is below " + IntegerToString(lo) + " - using " + IntegerToString(lo));
      return lo;
     }
   if(value > hi)
     {
      Warn(name + " " + IntegerToString(value) + " is above " + IntegerToString(hi) + " - using " + IntegerToString(hi));
      return hi;
     }
   return value;
  }

//+------------------------------------------------------------------+
//| Reads every input once. Ranges from 07-settings where it gives   |
//| one; the others are the bounds of ADR-021.                       |
//+------------------------------------------------------------------+
void CSettings::Load()
  {
   ArrayResize(m_warnings, 0);

   //--- Risk
   maxRiskPerTradePct        = ClampD("Max risk per trade %", InpMaxRiskPerTradePct, 0.01, 100.0, 10.0);
   maxTotalRiskPct           = ClampD("Max total open risk %", InpMaxTotalRiskPct, 0.01, 100.0, 10.0);
   defaultRiskPct            = NormalizeDouble(ClampD("Risk % on first start", InpDefaultRiskPct, 0.01, maxRiskPerTradePct, 1.0), 2);
   riskBase                  = InpRiskBase;
   includePendingInTotalRisk = InpIncludePendingInTotalRisk;
   commissionPerLot          = ClampD("Commission per lot", InpCommissionPerLot, 0.0, 1000000.0, 0.0);
   allowMinLotOverRisk       = InpAllowMinLotOverRisk;
   marginBufferPct           = ClampD("Free margin kept unused %", InpMarginBufferPct, 0.0, 90.0, 5.0);
   reduceToMargin            = InpReduceToMargin;

   //--- Take profit (07: R/R range (0, 50])
   tradeWithTpLine           = InpTradeWithTpLine;
   manualTpLine              = InpManualTpLine;
   tpRR                      = ClampD("R/R", InpTpRR, 0.01, 50.0, 1.0);
   tpFollowsSl               = InpTpFollowsSl;
   tpMode                    = RdTpModeFrom(tradeWithTpLine, manualTpLine);

   //--- Execution
   magic                     = InpMagic;
   if(magic <= 0)
     {
      Warn("Magic number " + IntegerToString(InpMagic) + " cannot identify RiskDesk trades - using 772211");
      magic = 772211;
     }
   comment                   = InpComment;
   if(StringLen(comment) > 31)
     {
      Warn("Order comment is longer than 31 characters - shortened");
      comment = StringSubstr(comment, 0, 31);
     }
   slippagePoints            = ClampI("Max slippage", InpSlippagePoints, 0, 100000);
   maxRetries                = ClampI("Retries per request", InpMaxRetries, 0, 10);
   retryDelayMs              = ClampI("Retry delay ms", InpRetryDelayMs, 0, 10000);
   fillingOverride           = InpFillingOverride;
   stopsMode                 = InpStopsMode;
   closeIfStopFails          = InpCloseIfStopFails;
   pendingExpiryHours        = ClampI("Pending order expiry hours", InpPendingExpiryHours, 0, 8760);
   nettingAllowOpposite      = InpNettingAllowOpposite;
   clickCooldownMs           = ClampI("Click cooldown ms", InpClickCooldownMs, 0, 10000);

   //--- Management (07: Half Close % 1-99)
   scopeChartOps             = InpScopeChartOps;
   scopeFullClose            = InpScopeFullClose;
   fullCloseAlsoPending      = InpFullCloseAlsoPending;
   riskFreeMode              = InpRiskFreeMode;
   riskFreeExtraPoints       = ClampI("Risk Free extra points", InpRiskFreeExtraPoints, 0, 100000);
   partialClosePct           = ClampD("Half Close %", InpPartialClosePct, 1.0, 99.0, 50.0);
   partialIndivisible        = InpPartialIndivisible;
   keepLinesAfterTrade       = InpKeepLinesAfterTrade;
   confirmTrades             = InpConfirmTrades;
   confirmHalfClose          = InpConfirmHalfClose;
   confirmChartClose         = InpConfirmChartClose;
   confirmFullClose          = InpConfirmFullClose;

   //--- Chart extras
   closedTradeObjects        = InpClosedTradeObjects;
   showCandleTime            = InpShowCandleTime;
   candleTimeFontSize        = ClampI("Candle Time Font Size", InpCandleTimeFontSize, 6, 36);
   colorCandleTime           = InpColorCandleTime;
   colorCandleTimeWarn       = InpColorCandleTimeWarn;
   candleTimeWarnSec         = ClampI("Candle time red below seconds", InpCandleTimeWarnSec, 0, 86400);
   slLossFontSize            = ClampI("SL Dollar Loss Font Size", InpSlLossFontSize, 6, 36);
   autoScreenshot            = InpAutoScreenshot;
   shotWidth                 = ClampI("Screenshot width", InpShotWidth, 0, 8000);
   shotHeight                = ClampI("Screenshot height", InpShotHeight, 0, 8000);
   showPendingOverlay        = InpShowPendingOverlay;
   // 05 section 5 (ADR-022): beyond 45 % the pending SL (1.5 x) would leave the visible range
   defaultOffsetPct          = ClampD("Add Line distance %", InpDefaultOffsetPct, 1.0, 45.0, 15.0);

   //--- Panel / Font (07: font 6-16, scale 0.40-1.60, refresh 100-2000)
   fontPreset                = InpFontPreset;
   fontSize                  = ClampI("Font Size", InpFontSize, 6, 16);
   scale                     = ClampD("Shape Size Scale", InpScale, 0.40, 1.60, 1.0);
   autoFitPanel              = InpAutoFitPanel;
   panelColumns              = InpPanelColumns;
   panelX                    = ClampI("X Start", InpPanelX, 0, 20000);
   panelY                    = ClampI("Y Start", InpPanelY, 0, 20000);
   startHidden               = InpStartHidden;
   showPricesOnButtons       = InpShowPricesOnButtons;
   dimInvalidSide            = InpDimInvalidSide;
   spreadUnit                = InpSpreadUnit;
   spreadWarnPts             = ClampI("Spread warning points", InpSpreadWarnPts, 0, 1000000);
   statusHoldSec             = ClampI("Status message hold seconds", InpStatusHoldSec, 1, 600);
   refreshMs                 = ClampI("Refresh period ms", InpRefreshMs, 100, 2000);

   //--- Colors
   colorEntry                = InpColorEntry;
   colorPendOverlayEntry     = InpColorPendOverlayEntry;
   colorPendOverlaySL        = InpColorPendOverlaySL;
   colorPendOverlayTP        = InpColorPendOverlayTP;
   colorSL                   = InpColorSL;
   colorTP                   = InpColorTP;
   colorSlLoss               = InpColorSlLoss;
   lineWidth                 = ClampI("Line Width", InpLineWidth, 1, 5);
   colorAddLine              = InpColorAddLine;
   colorDeleteLine           = InpColorDeleteLine;
   colorBuy                  = InpColorBuy;
   colorSell                 = InpColorSell;
   colorAddPendLine          = InpColorAddPendLine;
   colorSetPending           = InpColorSetPending;
   colorPendingInfo          = InpColorPendingInfo;
   colorDelPending           = InpColorDelPending;
   colorRiskFree             = InpColorRiskFree;
   colorHalfClose            = InpColorHalfClose;
   colorChartClose           = InpColorChartClose;
   colorFullClose            = InpColorFullClose;
   colorSpread               = InpColorSpread;
   colorBg                   = InpColorBg;
   colorSystemBorder         = InpColorSystemBorder;
   colorButtonBorder         = InpColorButtonBorder;
   colorText                 = InpColorText;

   //--- Account
   centMode                  = InpCentMode;
   centDivisor               = ClampD("Cent units per currency unit", InpCentDivisor, 1.0, 1000000.0, 100.0);
   staleQuoteSec             = ClampI("Stale quote seconds", InpStaleQuoteSec, 0, 604800);

   //--- Diagnostics
   logLevel                  = InpLogLevel;
   logToFile                 = InpLogToFile;

   testUiSelfTest            = false;
#ifdef RD_TEST_HOOKS
   testUiSelfTest            = InpTestUiSelfTest;
#endif
  }

//+------------------------------------------------------------------+
string CSettings::WarningsText() const
  {
   string text = "";
   int n = ArraySize(m_warnings);
   for(int i = 0; i < n; i++)
      text = RdJoin(text, m_warnings[i], "; ");
   return text;
  }

//+------------------------------------------------------------------+
void CSettings::Plan(SPlanSettings &p) const
  {
   p.Defaults();
   p.riskBase                  = riskBase;
   p.maxRiskPerTradePct        = maxRiskPerTradePct;
   p.maxTotalRiskPct           = maxTotalRiskPct;
   p.commissionPerLot          = commissionPerLot;
   p.allowMinLotOverRisk       = allowMinLotOverRisk;
   p.includePendingInTotalRisk = includePendingInTotalRisk;
   p.magic                     = magic;
   p.tpMode                    = tpMode;
   p.tpRR                      = tpRR;
   p.riskFreeMode              = riskFreeMode;
   p.riskFreeExtraPoints       = riskFreeExtraPoints;
   p.partialClosePct           = partialClosePct;
   p.partialIndivisible        = partialIndivisible;
  }

void CSettings::Gateway(SGatewaySettings &g) const
  {
   g.Defaults();
   g.magic              = magic;
   g.comment            = comment;
   g.slippagePoints     = slippagePoints;
   g.maxRetries         = maxRetries;
   g.retryDelayMs       = retryDelayMs;
   g.fillingOverride    = fillingOverride;
   g.stopsMode          = stopsMode;
   g.closeIfStopFails   = closeIfStopFails;
   g.pendingExpiryHours = pendingExpiryHours;
  }

//+------------------------------------------------------------------+
string CSettings::TpModeText() const
  {
   if(tpMode == TPMODE_NONE)
      return "No TP";
   if(tpMode == TPMODE_AUTO_RR)
      return "Auto R/R " + RdNum(tpRR, 2);
   return "Manual TP line (starts at R/R " + RdNum(tpRR, 2) + (tpFollowsSl ? ", follows SL" : "") + ")";
  }

//+------------------------------------------------------------------+
//| One log line with the settings that shape behaviour.             |
//+------------------------------------------------------------------+
string CSettings::Summary() const
  {
   string base = (riskBase == RISKBASE_BALANCE) ? "balance" : (riskBase == RISKBASE_EQUITY ? "equity" : "min(balance, equity)");
   return "Settings: risk " + RdNum(defaultRiskPct, 2) + " % of " + base +
          " (max " + RdNum(maxRiskPerTradePct, 2) + " % per trade, " + RdNum(maxTotalRiskPct, 2) + " % total)" +
          ", TP " + TpModeText() +
          ", magic " + IntegerToString(magic) +
          ", scale " + RdNum(scale, 2) + (autoFitPanel ? " auto-fit" : "") +
          ", columns " + (panelColumns == PANEL_COLUMNS_ONE ? "1" : (panelColumns == PANEL_COLUMNS_TWO ? "2" : "auto")) +
          ", font " + EnumToString(fontPreset) + " " + IntegerToString(fontSize) +
          ", refresh " + IntegerToString(refreshMs) + " ms" +
          ", cooldown " + IntegerToString(clickCooldownMs) + " ms";
  }

#endif // RD_APP_SETTINGS_MQH
