# ADR-010 Synchronous requests

- **Context:** `OrderSendAsync` (MT5) is faster but complicates verification, retries and status reporting; MT4 has no async API.
- **Decision:** Synchronous `OrderSend` only; one command at a time per chart (busy flag).
- **Consequences:** Simple, verifiable flows; Full Close on many positions takes a few seconds and shows progress.
