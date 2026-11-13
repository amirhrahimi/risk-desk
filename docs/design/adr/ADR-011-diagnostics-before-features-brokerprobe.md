# ADR-011 Diagnostics before features (BrokerProbe, GatewaySmoke)

- **Context:** A risk panel that does nothing on some brokers, without a message, is the failure RiskDesk must avoid (R8); guessing the cause of a broker difference wastes time. _(Wording changed for publication, ADR-029.)_
- **Decision:** Build the probe in P0 and the gateway smoke test in P2, before any UI.
- **Consequences:** Broker issues are found in isolation, with data committed to the repo for future debugging.
