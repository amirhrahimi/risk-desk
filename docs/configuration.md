# Configuration: input reference

Inputs are set in the EA's properties dialog (**Inputs** tab) when you attach Risk Desk to a chart, or later with a right-click on the chart → **Expert Advisors → Properties**. *Label* is the text the dialog shows. A value outside its *range* is clamped to the nearest allowed value, and the status bar and the log say so. Defaults marked ★ follow the original tool's defaults ([NOTICE.md](../NOTICE.md)).

The panel itself remembers your last **Risk %** per account, and the panel's position and hidden state. Those are not inputs. Specification of every input: [design/07-settings.md](design/07-settings.md).

## Risk

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpDefaultRiskPct` | Risk % on first start | double | 1.0 | 0.01 – max per trade | Risk % shown the first time on an account |
| `InpMaxRiskPerTradePct` | Max risk per trade % | double | 10.0 | 0.01 – 100 | The panel refuses a higher Risk % |
| `InpMaxTotalRiskPct` | Max total open risk % (RiskDesk trades) | double | 10.0 | 0.01 – 100 | A new trade is refused when the open risk of Risk Desk's positions (and pending orders, see below) plus the new trade would exceed this |
| `InpRiskBase` | Risk % of | Balance / Equity / Lower of balance and equity | Balance | – | What the % refers to |
| `InpIncludePendingInTotalRisk` | Count RiskDesk pending orders in the total risk | bool | true | – | Pending orders count towards the total open risk |
| `InpCommissionPerLot` | Commission per lot, round turn (account currency) | double | 0.0 | 0 – 1,000,000 | Added to the loss per lot, so the lot shrinks to keep the risk. Set it on commission accounts (e.g. "Raw" or ECN) |
| `InpAllowMinLotOverRisk` | Allow the min lot when it risks more than Risk % | bool | false | – | false: refuse when even the minimum lot is too large. true: send the minimum lot if its risk is within the per-trade cap; the status bar shows the real risk in amber |
| `InpMarginBufferPct` | Free margin kept unused % | double | 5.0 | 0 – 90 | The required margin must fit into free margin minus this share |
| `InpReduceToMargin` | Reduce lots to the affordable margin instead of refusing | bool | false | – | true: send the largest lot the margin allows |

## Take profit

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpTradeWithTpLine` | Trade with TP Line | bool | true ★ | – | false: orders have no TP |
| `InpManualTpLine` | Manual TP Line - It doesn't work if Trade with TP Line is False | bool | false ★ | – | true: a green TP line you drag; false: TP computed from R/R |
| `InpTpRR` | R/R \| Only Active When Trade with TP Line is True | double | 1.0 ★ | 0.01 – 50 | TP distance = R/R × SL distance (automatic mode) and the starting distance of the manual TP line |
| `InpTpFollowsSl` | Manual TP line keeps its R/R when SL/Entry move | bool | true | – | The manual TP line moves with the SL until you drag the TP line itself |

The three TP modes:

| Trade with TP Line | Manual TP Line | Mode | TP line | Order TP |
|---|---|---|---|---|
| false | any | No TP | none | none |
| true | false | Automatic R/R (default) | none | entry ± R/R × \|entry − SL\| |
| true | true | Manual TP line | green, draggable | the line's price |

## Execution

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpMagic` | Magic number of RiskDesk trades | int | 772211 | – | Marks Risk Desk's trades. The total open-risk cap and the "RiskDesk trades" scopes count the trades that carry this number |
| `InpComment` | Order comment | string | "RiskDesk" | – | Informational; brokers may change or drop it |
| `InpSlippagePoints` | Max slippage (points) | int | 20 | 0 – 100,000 | Maximum price deviation for market orders. The same value is used for every symbol |
| `InpMaxRetries` | Retries per request | int | 3 | 0 – 10 | For requotes and other retryable answers. An unclear result is never resent before it is checked |
| `InpRetryDelayMs` | Retry delay ms (doubles each retry) | int | 300 | 0 – 10,000 | Wait before the first retry |
| `InpFillingOverride` | Filling policy (MT5) | Auto / Fill or Kill / Immediate or Cancel / Return | Auto | – | Auto reads the symbol's flags and falls back if the server refuses. Force a policy only to work around a broker |
| `InpStopsMode` | How SL/TP are attached | Auto / Send SL/TP with the order / Add SL/TP right after the open | Auto | – | Auto sends SL/TP with the order; if the server refuses the stops although they are valid, it opens without them and adds them immediately, and remembers that for the symbol. SL/TP are verified after every open |
| `InpCloseIfStopFails` | Close a position whose SL cannot be attached | bool | true | – | Keeps a Risk Desk position from staying open without a stop-loss |
| `InpPendingExpiryHours` | Pending order expiry hours (0 = none) | int | 0 | 0 – 8760 | 0: good till cancelled (or the nearest policy the broker allows) |
| `InpNettingAllowOpposite` | Netting: allow an opposite order to reduce/reverse | bool | false | – | MT5 netting accounts only |
| `InpClickCooldownMs` | Ignore repeated clicks within ms | int | 800 | 0 – 10,000 | Double-click protection |

## Management

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpScopeChartOps` | Risk Free / Half / Chart Close / Del Pending act on | All trades on the chart symbol / RiskDesk trades on the chart symbol | All trades on the chart symbol | – | **Includes manual trades and other EAs' trades by default** |
| `InpScopeFullClose` | Full Close acts on | All trades on the account / RiskDesk trades on the account | All trades on the account | – | **Closes every position on the account by default** |
| `InpFullCloseAlsoPending` | Full Close also deletes pending orders | bool | false | – | |
| `InpRiskFreeMode` | Risk Free moves the SL to | Open price + spread + commission / Open price + spread / Open price + commission / Exact open price | Open price + spread + commission | – | "Commission" uses `InpCommissionPerLot`. The SL is never moved against the trade |
| `InpRiskFreeExtraPoints` | Risk Free extra points | int | 0 | 0 – 100,000 | Extra distance beyond the break-even price |
| `InpPartialClosePct` | Half Close % (1-99) | double | 50.0 | 1 – 99 | Share of each position that Half Close closes, rounded to the volume grid (a tie keeps the larger part open) |
| `InpPartialIndivisible` | Half Close on a position that cannot be split | Skip and report / Close the whole position | Skip and report | – | E.g. a position of the minimum lot |
| `InpKeepLinesAfterTrade` | Keep the lines after a successful order | bool | false | – | |
| `InpConfirmTrades` | Confirm Buy / Sell / Set Pending | bool | false | – | Shows a dialog with lots and risk before sending |
| `InpConfirmHalfClose` | Confirm Half Close | bool | false | – | |
| `InpConfirmChartClose` | Confirm Chart Close | bool | false | – | |
| `InpConfirmFullClose` | Confirm Full Close | bool | true | – | |

## Chart extras

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpClosedTradeObjects` | Closed Trade History Objects | Keep closed trade objects / Remove closed trade objects | Remove ★ | – | Remove deletes MetaTrader's arrows and lines of closed trades on this chart; your own drawings are never touched |
| `InpShowCandleTime` | Candle Time | bool | true ★ | – | Countdown to the close of the current candle |
| `InpCandleTimeFontSize` | Candle Time Font Size | int | 10 ★ | 6 – 36 | |
| `InpColorCandleTime` | Candle time colour | color | Gold | – | |
| `InpColorCandleTimeWarn` | Candle time colour near the close | color | Red | – | |
| `InpCandleTimeWarnPct` | Candle time red in the last % of the candle (0 = only at 00:00) | int | 10 | 0 – 100 | |
| `InpSlLossFontSize` | SL Dollar Loss Font Size | int | 10 ★ | 6 – 36 | Font size of the money-at-risk label on the SL line |
| `InpAutoScreenshot` | Automatic Screenshot After Actions | bool | true ★ | – | PNG files in `Files/RiskDesk/Screenshots/` (file names contain the account number) |
| `InpShotWidth` / `InpShotHeight` | Screenshot width / height px (0 = chart size) | int | 0 / 0 | 0 – 8000 | |
| `InpShowPendingOverlay` | Draw placed pending orders (drag to modify) | bool | true | – | false: placed orders are not drawn and cannot be dragged through Risk Desk |
| `InpDefaultOffsetPct` | Add Line: SL distance in % of the visible price range | double | 15.0 | 1 – 45 | Where Add Line / Add Pend Line put the first lines |

## Panel / Font

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpFontPreset` | Panel Font Preset | Segoe UI / Arial / Tahoma / Calibri / Verdana / Consolas | Segoe UI ★ | – | |
| `InpFontSize` | Font Size | int | 8 ★ | 6 – 16 | |
| `InpScale` | Shape Size Scale (0.40 - 1.60) | double | 1.0 | 0.40 – 1.60 | Panel size; Windows display scaling is applied on top |
| `InpAutoFitPanel` | Auto fit panel size to chart/monitor | bool | true ★ | – | Shrinks the panel so it fits the chart window |
| `InpPanelColumns` | Panel columns | Auto / One column / Two columns | Auto | – | Auto uses two columns when one column would shrink a lot |
| `InpPanelX` / `InpPanelY` | X Start / Y Start | int | 20 / 40 | 0 – 20,000 | Position on first start; afterwards the last position is kept |
| `InpStartHidden` | Start with the panel hidden | bool | false | – | |
| `InpShowPricesOnButtons` | Show prices on Buy / Sell | bool | true | – | |
| `InpDimInvalidSide` | Dim the side the SL makes invalid | bool | true | – | The dimmed button still explains why when clicked |
| `InpSpreadUnit` | Spread unit | Points / Pips | Points | – | |
| `InpSpreadWarnPts` | Spread warning above points (0 = off) | int | 0 | 0 – 1,000,000 | |
| `InpStatusHoldSec` | Status message hold (seconds) | int | 8 | 1 – 600 | Then the status bar shows the open-risk readout |
| `InpRefreshMs` | Refresh period ms (100-2000) | int | 250 | 100 – 2000 | |

## Colors

All colour inputs are plain MetaTrader colours. Their labels follow the original tool's (★). The default theme is a black panel with white text.

| Input | Label | Default |
|---|---|---|
| `InpColorEntry` | Pending Line Color | White |
| `InpColorPendOverlayEntry` / `InpColorPendOverlaySL` / `InpColorPendOverlayTP` | Pending Overlay Entry / SL / TP Line Color | LimeGreen / Red / Red |
| `InpColorSL` / `InpColorTP` | Stop Line Color / TP Line Color | Red / LimeGreen |
| `InpColorSlLoss` | SL Dollar Loss Color | White |
| `InpLineWidth` | Line Width (range 1 – 5) | 2 |
| `InpColorAddLine`, `InpColorDeleteLine`, `InpColorBuy`, `InpColorSell`, `InpColorAddPendLine`, `InpColorSetPending`, `InpColorPendingInfo`, `InpColorDelPending`, `InpColorRiskFree`, `InpColorHalfClose`, `InpColorChartClose`, `InpColorFullClose`, `InpColorSpread` | Color *button name* | see [design/07-settings.md](design/07-settings.md#colors) |
| `InpColorBg` / `InpColorSystemBorder` / `InpColorButtonBorder` | Color BackGround / Color System Border / Color Button Border | Black / gray 136 / gray 136 |
| `InpColorText` | Text colour of buttons and fields | White |

## Account

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpCentMode` | Cent account | Auto-detect / Cent account / Standard account | Auto-detect | – | In cent mode every amount also shows the major unit, e.g. `-1,000.00 USC (-$10.00)`. Lot sizing is not affected |
| `InpCentDivisor` | Cent units per currency unit | double | 100 | 1 – 1,000,000 | |
| `InpStaleQuoteSec` | Warn when the last quote is older than seconds | int | 300 | 0 – 604,800 | Amber hint "market may be closed"; nothing is blocked |

## Diagnostics

| Input | Label | Type | Default | Range | Meaning |
|---|---|---|---|---|---|
| `InpLogLevel` | Log level | Errors / Warnings / Info / Debug | Info | – | |
| `InpLogToFile` | Mirror the log to Files/RiskDesk/Logs | bool | true | – | Daily files `RiskDesk_<yyyymmdd>.log` |
| `InpLogKeepDays` | Keep the daily log files for N days (0 = keep all) | int | 30 | 0 – 3650 | |

Debug builds (for development only) add one more input, `InpTestUiSelfTest`. Release builds do not have it.
