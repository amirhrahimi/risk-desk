# ADR-002 No MT5 Standard Library (CTrade, Controls)

- **Context:** `CTrade` hides filling-policy handling and retcodes; `Controls/` dialogs differ between MT4 and MT5 and are heavy.
- **Decision:** Own `CTradeGateway` with raw `MqlTradeRequest`/`OrderSend`; own lightweight widgets over chart objects.
- **Consequences:** Full control over BC-06/BC-11/BC-14 and identical UI on both platforms; more code to write and test (GatewaySmoke covers it).
