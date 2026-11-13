# Notice and attribution

## Credit

Risk Desk is inspired by **Map Manager**, a capital-management tool for MetaTrader by **Mohammad Ali Poursamadi and his team**, published at [poursamadi.com](https://poursamadi.com/en/) ([product page](https://poursamadi.com/en/mapexpert/)). Its one-click, risk-based workflow is the basis of this project, and we thank its authors for designing it and describing it publicly.

Risk Desk is an independent project. It is **not affiliated with, endorsed by or supported by** Mohammad Ali Poursamadi, his team or poursamadi.com. Please do not contact them about Risk Desk. Questions about Risk Desk go to this repository's [issues](https://github.com/amirhrahimi/risk-desk/issues).

## What was taken from the original, and what was not

Risk Desk is a clean-room reimplementation. Its code was written from a description of the original's *behaviour*. Nobody on this project has seen, decompiled or inspected the original's code or binaries.

**Inspired by the original:**

- the workflow and feature set, as described in its public user guide and changelog (risk %, a stop-loss line on the chart, market and pending orders, Risk Free, Half Close, Chart Close, Full Close, spread display, take-profit modes, closed-trade objects, candle time, screenshots, pending-order overlay, cent accounts);
- the names of the panel buttons and fields: *Risk, Lots, Add Line, Delete Line, Buy, Sell, Add Pend Line, Set Pending, Pending Info, Del Pending, Risk Free, Half Close, Chart Close, Full Close, Spread*;
- the labels of these inputs, shown in the terminal's properties dialog: *Trade with TP Line; Manual TP Line - It doesn't work if Trade with TP Line is False; R/R | Only Active When Trade with TP Line is True; Closed Trade History Objects (Keep closed trade objects / Remove closed trade objects); Candle Time; Candle Time Font Size; SL Dollar Loss Font Size; Automatic Screenshot After Actions; Panel Font Preset; Font Size; Shape Size Scale (0.40 - 1.60); Auto fit panel size to chart/monitor; X Start; Y Start;* and the colour inputs *Pending Line Color, Pending Overlay Entry/SL/TP Line Color, Stop Line Color, TP Line Color, SL Dollar Loss Color, Line Width, Color Add Line, Color Delete Line, Color Buy, Color Sell, Color Add Pend Line, Color Set Pending, Color Pending Info, Color Del Pending, Color Risk Free, Color Half Close, Color Chart Close, Color Full Close, Color Spread, Color BackGround, Color System Border, Color Button Border*;
- the default values of those inputs, so that users of the original find familiar settings ([ADR-012](docs/design/adr/ADR-012-mirror-the-originals-inputs-and-defaults-where.md)).

**Written for this project:**

- all source code, the risk engine and its rounding rules, the broker-compatibility layer (filling-policy and expiration fallbacks, tick-size normalization, volume grids, currency conversion, netting accounts), the status bar, confirmations, risk caps, margin pre-check, commission-aware sizing, open-risk readout, logging, BrokerProbe and GatewaySmoke, the tests and all documentation.

**Not used:** the original's code, binaries, graphics, logo, screenshots or documentation text.

The original's website states: *"Map Manager has been tested only on demo and live accounts of the broker introduced in the 'Trusted broker' section."* Risk Desk has been tested on the demo accounts of several brokers; see [docs/broker-compatibility.md](docs/broker-compatibility.md).

## Trademarks

MetaTrader, MetaTrader 4, MetaTrader 5, MQL4, MQL5 and MetaEditor are trademarks of MetaQuotes Ltd. IC Markets, Dukascopy and IG are trademarks of their owners. They are named only to describe the platforms and test environments. This project is not affiliated with or endorsed by any of them.

## Licence

Copyright (c) 2026 Amir Rahimi. Risk Desk is released under the [MIT License](LICENSE). The licence covers this project's own code and documents only. No third-party code is included.
