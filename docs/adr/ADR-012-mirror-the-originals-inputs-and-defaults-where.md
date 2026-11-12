# ADR-012 Mirror the original's inputs and defaults where known

- **Context:** The owner shared the original's settings dialog (v2.0.1). Familiar names and colours make the switch painless, and the inputs reveal features the guide does not describe (closed-trade objects, pending overlay, auto-fit, manual TP line).
- **Decision:** Where the original has an equivalent input, RiskDesk uses the same label (as the input's display comment), the same meaning and the owner's current value as default. Our own extra inputs keep their names. Unknown semantics (Q15–Q18) get a configurable assumption, never a guess baked into code.
- **Consequences:** Side-by-side parity can be checked (T-38). Our earlier "history overlay" idea moved to the backlog.
