# ADR-014 Placed pending orders are drawn by RiskDesk and moved by dragging

- **Context:** The owner's test (Q18) showed that the original draws placed pending orders itself in the "Pending Overlay" colours and that dragging those lines changes the order. CLAUDE.md §1 said RiskDesk acts only on clicks, and the first spec kept the overlay display-only.
- **Decision:** Overlay lines are selectable `OBJ_HLINE`s. Dropping one is a deliberate user action, handled as command OP-16: validate the new price (order type, side, BC-07), check the risk caps with the lot unchanged (04 §5), send `G-08 ModifyPending` through `CTradeGateway`, report the result; a refused or failed move snaps the line back. Deleting an overlay object never deletes the order. CLAUDE.md §1 now names this as the only non-click action.
- **Consequences:** Parity with the original; one more gateway primitive (G-08) and GatewaySmoke step; test T-39. The backlog item "draggable pending overlay lines" is done in v1 (P5).
