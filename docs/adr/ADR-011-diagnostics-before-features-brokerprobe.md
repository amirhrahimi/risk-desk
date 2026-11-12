# ADR-011 Diagnostics before features (BrokerProbe, GatewaySmoke)

- **Context:** The original fails silently on two of the owner's brokers; guessing the cause wastes time.
- **Decision:** Build the probe in P0 and the gateway smoke test in P2, before any UI.
- **Consequences:** Broker issues are found in isolation, with data committed to the repo for future debugging.
