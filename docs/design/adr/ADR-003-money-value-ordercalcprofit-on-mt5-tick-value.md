# ADR-003 Money value: OrderCalcProfit on MT5, tick value + cross-check on MT4

- **Context:** Wrong tick values are a common cause of wrong lot sizes on CFDs and non-USD accounts.
- **Decision:** MT5 uses `OrderCalcProfit` (terminal does conversion). MT4 uses tick value, cross-checked against contract size × conversion rate; on mismatch take the more conservative value and warn.
- **Consequences:** Correct lots on cross-currency accounts; occasional conservative under-sizing on MT4 with an explicit warning.
