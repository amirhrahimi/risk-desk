//+------------------------------------------------------------------+
//| RiskDesk - App/Inputs.mqh                                        |
//| Layer   : App (the only App file allowed to use #ifdef           |
//|           __MQL5__, rule R2: MQL5 has input groups, MQL4 uses    |
//|           sinput separators)                                     |
//| Purpose : every input of the EA (07-settings), in the order and  |
//|           with the defaults of 07. The trailing comment is the   |
//|           name shown in the properties dialog; where the         |
//|           original tool has the same input, it is the original's |
//|           label (ADR-012). Inputs are read in one place only:    |
//|           CSettings::Load (App/Settings.mqh) validates them.     |
//+------------------------------------------------------------------+
#ifndef RD_APP_INPUTS_MQH
#define RD_APP_INPUTS_MQH

#include "..\Domain\Types.mqh"

//--- Risk
#ifdef __MQL5__
input group "Risk"
#else
sinput string InpSep_Risk = "==== Risk ====";   // ==== Risk ====
#endif
input double            InpDefaultRiskPct            = 1.0;               // Risk % on first start
input double            InpMaxRiskPerTradePct        = 10.0;              // Max risk per trade %
input double            InpMaxTotalRiskPct           = 10.0;              // Max total open risk % (RiskDesk trades)
input ERiskBase         InpRiskBase                  = RISKBASE_BALANCE;  // Risk % of
input bool              InpIncludePendingInTotalRisk = true;              // Count RiskDesk pending orders in the total risk
input double            InpCommissionPerLot          = 0.0;               // Commission per lot, round turn (account currency)
input bool              InpAllowMinLotOverRisk       = false;             // Allow the min lot when it risks more than Risk %
input double            InpMarginBufferPct           = 5.0;               // Free margin kept unused %
input bool              InpReduceToMargin            = false;             // Reduce lots to the affordable margin instead of refusing

//--- Take profit
#ifdef __MQL5__
input group "Take profit"
#else
sinput string InpSep_TakeProfit = "==== Take profit ====";   // ==== Take profit ====
#endif
input bool              InpTradeWithTpLine           = true;              // Trade with TP Line
input bool              InpManualTpLine              = false;             // Manual TP Line - It doesn't work if Trade with TP Line is False
input double            InpTpRR                      = 1.0;               // R/R | Only Active When Trade with TP Line is True
input bool              InpTpFollowsSl               = true;              // Manual TP line keeps its R/R when SL/Entry move

//--- Execution
#ifdef __MQL5__
input group "Execution"
#else
sinput string InpSep_Execution = "==== Execution ====";   // ==== Execution ====
#endif
input int               InpMagic                     = 772211;            // Magic number of RiskDesk trades
input string            InpComment                   = "RiskDesk";        // Order comment
input int               InpSlippagePoints            = 20;                // Max slippage (points)
input int               InpMaxRetries                = 3;                 // Retries per request
input int               InpRetryDelayMs              = 300;               // Retry delay ms (doubles each retry)
input EFillingOverride  InpFillingOverride           = FILLPOL_AUTO;      // Filling policy (MT5)
input EStopsMode        InpStopsMode                 = STOPS_AUTO;        // How SL/TP are attached
input bool              InpCloseIfStopFails          = true;              // Close a position whose SL cannot be attached
input int               InpPendingExpiryHours        = 0;                 // Pending order expiry hours (0 = none)
input bool              InpNettingAllowOpposite      = false;             // Netting: allow an opposite order to reduce/reverse
input int               InpClickCooldownMs           = 800;               // Ignore repeated clicks within ms

//--- Management
#ifdef __MQL5__
input group "Management"
#else
sinput string InpSep_Management = "==== Management ====";   // ==== Management ====
#endif
input EScopeChart       InpScopeChartOps             = SCOPE_ALL_ON_SYMBOL;   // Risk Free / Half / Chart Close / Del Pending act on
input EScopeAccount     InpScopeFullClose            = SCOPE_ALL_ACCOUNT;     // Full Close acts on
input bool              InpFullCloseAlsoPending      = false;                 // Full Close also deletes pending orders
input ERiskFreeMode     InpRiskFreeMode              = RF_SPREAD_COMMISSION;  // Risk Free moves the SL to
input int               InpRiskFreeExtraPoints       = 0;                     // Risk Free extra points
input double            InpPartialClosePct           = 50.0;                  // Half Close % (1-99)
input EIndivisible      InpPartialIndivisible        = INDIV_SKIP;            // Half Close on a position that cannot be split
input bool              InpKeepLinesAfterTrade       = false;                 // Keep the lines after a successful order
input bool              InpConfirmTrades             = false;                 // Confirm Buy / Sell / Set Pending
input bool              InpConfirmHalfClose          = false;                 // Confirm Half Close
input bool              InpConfirmChartClose         = false;                 // Confirm Chart Close
input bool              InpConfirmFullClose          = true;                  // Confirm Full Close

//--- Chart extras
#ifdef __MQL5__
input group "Chart extras"
#else
sinput string InpSep_ChartExtras = "==== Chart extras ====";   // ==== Chart extras ====
#endif
input EClosedTradeObjects InpClosedTradeObjects      = CTO_REMOVE;        // Closed Trade History Objects
input bool              InpShowCandleTime            = true;              // Candle Time
input int               InpCandleTimeFontSize        = 10;                // Candle Time Font Size
input color             InpColorCandleTime           = clrGold;           // Candle time colour
input color             InpColorCandleTimeWarn       = clrRed;            // Candle time colour near the close
input int               InpCandleTimeWarnSec         = 60;                // Candle time red below seconds (0 = only at 00:00)
input int               InpSlLossFontSize            = 10;                // SL Dollar Loss Font Size
input bool              InpAutoScreenshot            = true;              // Automatic Screenshot After Actions
input int               InpShotWidth                 = 0;                 // Screenshot width px (0 = chart size)
input int               InpShotHeight                = 0;                 // Screenshot height px (0 = chart size)
input bool              InpShowPendingOverlay        = true;              // Draw placed pending orders (drag to modify)

//--- Panel / Font
#ifdef __MQL5__
input group "Panel / Font"
#else
sinput string InpSep_Panel = "==== Panel / Font ====";   // ==== Panel / Font ====
#endif
input EFontPreset       InpFontPreset                = FONT_SEGOE_UI;     // Panel Font Preset
input int               InpFontSize                  = 8;                 // Font Size
input double            InpScale                     = 1.0;               // Shape Size Scale (0.40 - 1.60)
input bool              InpAutoFitPanel              = true;              // Auto fit panel size to chart/monitor
input int               InpPanelX                    = 20;                // X Start
input int               InpPanelY                    = 40;                // Y Start
input bool              InpStartHidden               = false;             // Start with the panel hidden
input bool              InpShowPricesOnButtons       = true;              // Show prices on Buy / Sell
input bool              InpDimInvalidSide            = true;              // Dim the side the SL makes invalid
input ESpreadUnit       InpSpreadUnit                = SPREAD_POINTS;     // Spread unit
input int               InpSpreadWarnPts             = 0;                 // Spread warning above points (0 = off)
input int               InpStatusHoldSec             = 8;                 // Status message hold (seconds)
input int               InpRefreshMs                 = 250;               // Refresh period ms (100-2000)

//--- Colors
#ifdef __MQL5__
input group "Colors"
#else
sinput string InpSep_Colors = "==== Colors ====";   // ==== Colors ====
#endif
input color             InpColorEntry                = clrWhite;          // Pending Line Color
input color             InpColorPendOverlayEntry     = clrLimeGreen;      // Pending Overlay Entry Line Color
input color             InpColorPendOverlaySL        = clrRed;            // Pending Overlay SL Line Color
input color             InpColorPendOverlayTP        = clrRed;            // Pending Overlay TP Line Color
input color             InpColorSL                   = clrRed;            // Stop Line Color
input color             InpColorTP                   = clrLimeGreen;      // TP Line Color
input color             InpColorSlLoss               = clrWhite;          // SL Dollar Loss Color
input int               InpLineWidth                 = 2;                 // Line Width
input color             InpColorAddLine              = C'44,64,97';       // Color Add Line
input color             InpColorDeleteLine           = C'62,0,106';       // Color Delete Line
input color             InpColorBuy                  = C'39,130,73';      // Color Buy
input color             InpColorSell                 = C'192,55,42';      // Color Sell
input color             InpColorAddPendLine          = C'44,64,97';       // Color Add Pend Line
input color             InpColorSetPending           = C'211,162,31';     // Color Set Pending
input color             InpColorPendingInfo          = clrGold;           // Color Pending Info
input color             InpColorDelPending           = C'62,0,106';       // Color Del Pending
input color             InpColorRiskFree             = C'116,116,116';    // Color Risk Free
input color             InpColorHalfClose            = C'0,94,94';        // Color Half Close
input color             InpColorChartClose           = C'0,94,94';        // Color Chart Close
input color             InpColorFullClose            = C'0,94,94';        // Color Full Close
input color             InpColorSpread               = clrWhite;          // Color Spread
input color             InpColorBg                   = clrBlack;          // Color BackGround
input color             InpColorSystemBorder         = C'136,136,136';    // Color System Border
input color             InpColorButtonBorder         = C'136,136,136';    // Color Button Border
input color             InpColorText                 = clrWhite;          // Text colour of buttons and fields

//--- Account
#ifdef __MQL5__
input group "Account"
#else
sinput string InpSep_Account = "==== Account ====";   // ==== Account ====
#endif
input ECentMode         InpCentMode                  = CENT_AUTO;         // Cent account
input double            InpCentDivisor               = 100.0;             // Cent units per currency unit
input int               InpStaleQuoteSec             = 300;               // Warn when the last quote is older than seconds

//--- Diagnostics
#ifdef __MQL5__
input group "Diagnostics"
#else
sinput string InpSep_Diagnostics = "==== Diagnostics ====";   // ==== Diagnostics ====
#endif
input ELogLevel         InpLogLevel                  = LOGLEVEL_INFO;     // Log level
input bool              InpLogToFile                 = true;              // Mirror the log to Files/RiskDesk/Logs

#ifdef RD_TEST_HOOKS
//--- Test hooks: debug builds only (08-testing section 2), never in a release build
#ifdef __MQL5__
input group "TEST HOOKS (debug build)"
#else
sinput string InpSep_TestHooks = "==== TEST HOOKS (debug build) ====";   // ==== TEST HOOKS (debug build) ====
#endif
input bool              InpTestUiSelfTest            = false;             // TEST: run the panel self-test, then close the terminal
#endif

#endif // RD_APP_INPUTS_MQH
