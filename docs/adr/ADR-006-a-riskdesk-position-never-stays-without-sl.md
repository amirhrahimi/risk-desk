# ADR-006 A RiskDesk position never stays without SL

- **Context:** Some servers reject SL/TP on market-execution orders; modify-after can fail.
- **Decision:** Verify SL after every open; fix with retries; close the position if it cannot be protected (`InpCloseIfStopFails=true`).
- **Consequences:** Rare forced closes with a loud message, instead of unprotected exposure.
