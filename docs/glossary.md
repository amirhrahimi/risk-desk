# Glossary

| Term | Meaning |
|---|---|
| **Ask / Bid** | The price you buy at / sell at. A buy opens at the Ask and its stop-loss triggers when the Bid reaches it; a sell is the mirror case. |
| **Break-even** | A stop-loss at (or slightly beyond) the open price, so that a stop-out loses nothing apart from costs. *Risk Free* moves the SL there. |
| **Cent account** | An account whose currency is a hundredth of a standard currency (e.g. USC). Risk Desk shows both units. |
| **Commission** | A broker fee per lot. Set `InpCommissionPerLot` to the round-turn amount so that lot sizes and break-even include it. |
| **Contract size** | The quantity one lot represents (e.g. 100,000 units of EUR for EURUSD, or 1 or 10 for an index CFD, depending on the broker). |
| **EA (Expert Advisor)** | A program attached to a MetaTrader chart. Risk Desk is an EA that acts only on your clicks. |
| **Filling policy** (MT5) | How the server fills a market order: *Fill or Kill*, *Immediate or Cancel* or *Return*. Each server accepts only some; Risk Desk reads them from the symbol. |
| **Freeze level** | A distance from the price inside which the broker does not allow an order to be modified or deleted. |
| **Hedging / netting** (MT5) | Hedging: every trade is a separate position. Netting: one position per symbol; new orders add to, reduce or reverse it. MT4 behaves like hedging. |
| **Lot / volume** | Trade size. Each symbol has a minimum, a maximum and a step (e.g. 0.01, or whole lots on some index CFDs). |
| **Magic number** | A number stored with each order to identify the program that placed it. Risk Desk's default is 772211. |
| **Open risk** | The money Risk Desk's open positions (and, by default, pending orders) would lose if every SL were hit. Capped by `InpMaxTotalRiskPct`. |
| **Pending order** | An order placed at a price away from the market: *Buy Stop* / *Sell Stop* (entry beyond the price, in the trade's direction), *Buy Limit* / *Sell Limit* (entry better than the price). |
| **Point / pip** | A point is the smallest price digit of the symbol. A pip is traditionally 10 points on 5-digit FX quotes. Risk Desk works in points. |
| **Requote** | The server refuses the order price because the market moved, and offers a new one. Risk Desk retries with a fresh price, up to `InpMaxRetries` times. |
| **Risk %** | The planned loss at the stop-loss, as a share of the balance (or equity). |
| **R/R (reward/risk)** | Distance to the take-profit divided by distance to the stop-loss. R/R 2 = the TP is twice as far from the entry as the SL. |
| **Slippage** | The difference between the requested price and the fill. It also happens at stop-losses, so a loss can exceed the planned risk. |
| **Spread** | Ask minus Bid. |
| **Stops level** | The broker's minimum distance between the current price and an SL, TP or pending entry. |
| **Tick size / tick value** | The smallest price step of the symbol, and the money value of one tick for one lot. Some brokers report tick values in a currency other than the account's; Risk Desk cross-checks them. |
