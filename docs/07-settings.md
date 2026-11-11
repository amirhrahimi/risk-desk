# 07 — Settings (input parameters)

All inputs are declared in `App/Inputs.mqh`, validated once in `App/Settings.mqh` (invalid values → clamp + warning in the status bar and log). Use the trailing `// comment` on each input as the human-readable name shown in the terminal's properties dialog. **Where the original tool has an equivalent input, use its label as that comment** (column "Orig label") so the dialog feels familiar. MQL5 groups with `input group "<Group>"`; MQL4 uses `sinput string InpSep_<Group> = "──── <Group> ────";`.

Defaults marked ★ are copied from the owner's current configuration of the original (settings screenshots, 2026-11-09 and 2026-11-12). The original's input list starts at "Trade with TP Line" and ends at "Color Button Border" (Q19): every input without an Orig label is a RiskDesk addition.

Custom enums are defined in `Domain/Types.mqh` (names must not collide with built-in constants such as `ORDER_FILLING_*`).

## Risk
| Input | Type | Default | Orig label | Notes |
|---|---|---|---|---|
| `InpDefaultRiskPct` | double | 1.0 | – | First-run value of the Risk % field (Orig §01) |
| `InpMaxRiskPerTradePct` | double | 10.0 | – | Orig §01: max input 10 |
| `InpMaxTotalRiskPct` | double | 10.0 | – | Orig §01: total open risk of tool trades |
| `InpRiskBase` | `ERiskBase` | `RISKBASE_BALANCE` | – | Orig §01 uses balance |
| `InpIncludePendingInTotalRisk` | bool | true | – | Tool pending orders count towards open risk |
| `InpCommissionPerLot` | double | 0.0 | – | Round-turn commission per lot in account currency |
| `InpAllowMinLotOverRisk` | bool | false | – | 04 §4 |
| `InpMarginBufferPct` | double | 5.0 | – | Free margin kept unused |
| `InpReduceToMargin` | bool | false | – | Send max affordable lot instead of refusing |

## Take profit
| Input | Type | Default | Orig label | Notes |
|---|---|---|---|---|
| `InpTradeWithTpLine` | bool | true ★ | Trade with TP Line | false: orders have no TP and no TP line is drawn. true: orders get a TP (mode below) |
| `InpManualTpLine` | bool | false ★ | Manual TP Line - It doesn't work if Trade with TP Line is False | true: a draggable TP line is drawn at the R/R distance and order TP = line. false: no TP line, TP computed from R/R. Ignored when `InpTradeWithTpLine=false` |
| `InpTpRR` | double | 1.0 ★ | R/R \| Only Active When Trade with TP Line is True | Range (0, 50]. TP distance in Auto R/R mode; starting distance of the manual TP line |
| `InpTpFollowsSl` | bool | true | – | [NEW] The manual TP line keeps the R/R distance when the SL/Entry line is moved, until the TP line itself is dragged (05 §5). false = the original's behaviour |

Resulting TP mode (derived once in `Settings`, enum `ETpMode`, F-17, ADR-013):

| `InpTradeWithTpLine` | `InpManualTpLine` | `ETpMode` | TP line | Order TP |
|---|---|---|---|---|
| false | any | `TPMODE_NONE` | none | none |
| true | false | `TPMODE_AUTO_RR` | none | entry ± R/R × \|entry − SL\| |
| true | true | `TPMODE_MANUAL_LINE` | green, draggable, starts at the R/R distance | line price |

## Execution
| Input | Type | Default | Notes |
|---|---|---|---|
| `InpMagic` | int | 772211 | Identifies tool trades (BC-16) |
| `InpComment` | string | "RiskDesk" | Informational only |
| `InpSlippagePoints` | int | 20 | Max deviation for market orders |
| `InpMaxRetries` | int | 3 | BC-13 |
| `InpRetryDelayMs` | int | 300 | Doubles each retry |
| `InpFillingOverride` | `EFillingOverride` | `FILLPOL_AUTO` | AUTO / FOK / IOC / RETURN (BC-06; MT5 only) |
| `InpStopsMode` | `EStopsMode` | `STOPS_AUTO` | AUTO / WITH_ORDER / MODIFY_AFTER (BC-11) |
| `InpCloseIfStopFails` | bool | true | Rule R7 |
| `InpPendingExpiryHours` | int | 0 | 0 = no expiry (GTC, or the closest policy the broker allows); > 0 = expire after N hours (BC-08) |
| `InpNettingAllowOpposite` | bool | false | MT5 netting: allow an opposite order to reduce/reverse (BC-10) |
| `InpClickCooldownMs` | int | 800 | Double-click protection |

## Management
| Input | Type | Default | Notes |
|---|---|---|---|
| `InpScopeChartOps` | `EScopeChart` | `SCOPE_ALL_ON_SYMBOL` | Risk Free, Half/Chart Close, Del Pending: all trades on the symbol (as original) or tool-only |
| `InpScopeFullClose` | `EScopeAccount` | `SCOPE_ALL_ACCOUNT` | Full Close: everything (as original) or tool-only |
| `InpFullCloseAlsoPending` | bool | false | Also delete pending orders on Full Close |
| `InpRiskFreeMode` | `ERiskFreeMode` | `RF_SPREAD_COMMISSION` | SPREAD_COMMISSION (spread + `InpCommissionPerLot`) / SPREAD / COMMISSION / EXACT (04 §9, Q1) |
| `InpRiskFreeExtraPoints` | int | 0 | Extra points beyond the offset |
| `InpPartialClosePct` | double | 50.0 | Half Close percentage (1–99) |
| `InpPartialIndivisible` | `EIndivisible` | `INDIV_SKIP` | SKIP / CLOSE_ALL |
| `InpKeepLinesAfterTrade` | bool | false | Keep lines after a successful order |
| `InpConfirmTrades` / `InpConfirmHalfClose` / `InpConfirmChartClose` / `InpConfirmFullClose` | bool | false / false / false / true | F-28 |

## Chart extras
| Input | Type | Default | Orig label | Notes |
|---|---|---|---|---|
| `InpClosedTradeObjects` | `EClosedTradeObjects` | `CTO_REMOVE` ★ | Closed Trade History Objects | KEEP / REMOVE (F-20); the original has exactly these two options (Q16) |
| `InpShowCandleTime` | bool | true ★ | Candle Time | F-21 |
| `InpCandleTimeFontSize` | int | 10 ★ | Candle Time Font Size | |
| `InpColorCandleTime` | color | `clrGold` | – | Normal colour. The original has no colour inputs: gold, red near the close and at 00:00 (Q4, Q20) |
| `InpColorCandleTimeWarn` | color | `clrRed` | – | When fewer than `InpCandleTimeWarnSec` seconds are left, including `00:00` (market closed) |
| `InpCandleTimeWarnSec` | int | 60 | – | Red threshold in seconds (assumption until Q20 is answered); 0 = red only at `00:00` |
| `InpSlLossFontSize` | int | 10 ★ | SL Dollar Loss Font Size | Size of the money-risk label on the SL line (F-18) |
| `InpAutoScreenshot` | bool | true ★ | Automatic Screenshot After Actions | F-19 |
| `InpShotWidth` / `InpShotHeight` | int | 0 / 0 | – | 0 = current chart size |
| `InpShowPendingOverlay` | bool | true | – | F-22: placed pending orders drawn in the overlay colours, draggable to modify the order (OP-16) |

## Panel / Font
| Input | Type | Default | Orig label | Notes |
|---|---|---|---|---|
| `InpFontPreset` | `EFontPreset` | `FONT_SEGOE_UI` ★ | Panel Font Preset | Segoe UI / Arial / Tahoma / Calibri / Verdana / Consolas |
| `InpFontSize` | int | 8 ★ | Font Size | 6–16 |
| `InpScale` | double | 1.0 | Shape Size Scale (0.40 - 1.60) | Range 0.40–1.60 (owner uses 1.2) |
| `InpAutoFitPanel` | bool | true ★ | Auto fit panel size to chart/monitor | F-34 |
| `InpPanelX` / `InpPanelY` | int | 20 / 40 | X Start / Y Start | First-run position (owner uses 1075 / 50); then persisted |
| `InpStartHidden` | bool | false | – | |
| `InpShowPricesOnButtons` | bool | true | – | "Buy 1.10012" |
| `InpDimInvalidSide` | bool | true | – | F-33 |
| `InpSpreadUnit` | `ESpreadUnit` | `SPREAD_POINTS` | – | POINTS / PIPS |
| `InpSpreadWarnPts` | int | 0 | – | 0 = off |
| `InpStatusHoldSec` | int | 8 | – | Then idle readout |
| `InpRefreshMs` | int | 250 | – | 100–2000 |

## Colors
| Input | Default ★ | Orig label |
|---|---|---|
| `InpColorEntry` | `clrWhite` | Pending Line Color (entry line of Add Pend Line) |
| `InpColorPendOverlayEntry` | `clrLimeGreen` | Pending Overlay Entry Line Color |
| `InpColorPendOverlaySL` | `clrRed` | Pending Overlay SL Line Color |
| `InpColorPendOverlayTP` | `clrRed` | Pending Overlay TP Line Color (owner's value; `clrLimeGreen` may be more readable) |
| `InpColorSL` | `clrRed` | Stop Line Color |
| `InpColorTP` | `clrLimeGreen` | TP Line Color |
| `InpColorSlLoss` | `clrWhite` | SL Dollar Loss Color |
| `InpLineWidth` (int) | 2 | Line Width (SL/TP planning lines; dash-dot and dashed lines are always width 1) |
| `InpColorAddLine` | `C'44,64,97'` | Color Add Line |
| `InpColorDeleteLine` | `C'62,0,106'` | Color Delete Line |
| `InpColorBuy` | `C'39,130,73'` | Color Buy |
| `InpColorSell` | `C'192,55,42'` | Color Sell |
| `InpColorAddPendLine` | `C'44,64,97'` | Color Add Pend Line |
| `InpColorSetPending` | `C'211,162,31'` | Color Set Pending |
| `InpColorPendingInfo` | `clrGold` | Color Pending Info (label text) |
| `InpColorDelPending` | `C'62,0,106'` | Color Del Pending |
| `InpColorRiskFree` | `C'116,116,116'` | Color Risk Free |
| `InpColorHalfClose` | `C'0,94,94'` | Color Half Close |
| `InpColorChartClose` | `C'0,94,94'` | Color Chart Close |
| `InpColorFullClose` | `C'0,94,94'` | Color Full Close |
| `InpColorSpread` | `clrWhite` | Color Spread |
| `InpColorBg` | `clrBlack` | Color BackGround |
| `InpColorSystemBorder` | `C'136,136,136'` | Color System Border |
| `InpColorButtonBorder` | `C'136,136,136'` | Color Button Border |
| `InpColorText` | `clrWhite` | – (button and field text) |

## Account
| Input | Type | Default | Notes |
|---|---|---|---|
| `InpCentMode` | `ECentMode` | `CENT_AUTO` | AUTO / ON / OFF (BC-12) |
| `InpCentDivisor` | double | 100 | |
| `InpStaleQuoteSec` | int | 300 | BC-17 |

## Diagnostics
| Input | Type | Default |
|---|---|---|
| `InpLogLevel` | `ELogLevel` | `LOGLEVEL_INFO` (ERROR / WARN / INFO / DEBUG) |
| `InpLogToFile` | bool | true |

## Enum definitions (Domain/Types.mqh)
```cpp
enum ERiskBase           { RISKBASE_BALANCE, RISKBASE_EQUITY, RISKBASE_MIN_BAL_EQ };
enum EScopeChart         { SCOPE_ALL_ON_SYMBOL, SCOPE_TOOL_ON_SYMBOL };
enum EScopeAccount       { SCOPE_ALL_ACCOUNT, SCOPE_TOOL_ACCOUNT };
enum ERiskFreeMode       { RF_SPREAD_COMMISSION, RF_SPREAD, RF_COMMISSION, RF_EXACT };
enum EIndivisible        { INDIV_SKIP, INDIV_CLOSE_ALL };
enum EFillingOverride    { FILLPOL_AUTO, FILLPOL_FOK, FILLPOL_IOC, FILLPOL_RETURN };
enum EStopsMode          { STOPS_AUTO, STOPS_WITH_ORDER, STOPS_MODIFY_AFTER };
enum ECentMode           { CENT_AUTO, CENT_ON, CENT_OFF };
enum ESpreadUnit         { SPREAD_POINTS, SPREAD_PIPS };
enum ELogLevel           { LOGLEVEL_ERROR, LOGLEVEL_WARN, LOGLEVEL_INFO, LOGLEVEL_DEBUG };
enum EClosedTradeObjects { CTO_KEEP,   // Keep closed trade objects
                           CTO_REMOVE  // Remove closed trade objects
                         };
enum EFontPreset         { FONT_SEGOE_UI, FONT_ARIAL, FONT_TAHOMA, FONT_CALIBRI, FONT_VERDANA, FONT_CONSOLAS };
enum ETpMode             { TPMODE_NONE, TPMODE_AUTO_RR, TPMODE_MANUAL_LINE };   // derived in Settings, not an input
```
In MQL5 the `// comment` after an enum value is shown in the dropdown; use the original's wording.
