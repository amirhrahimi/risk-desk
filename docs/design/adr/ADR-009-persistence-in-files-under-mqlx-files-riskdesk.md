# ADR-009 Persistence in files under MQLx/Files/RiskDesk

- **Context:** Terminal global variables only store doubles and are easily wiped.
- **Decision:** Small `key=value` files (`ui.ini`, `acct_<login>.ini`); chart objects keep the lines.
- **Consequences:** Human-readable, portable state; must handle missing/corrupt files gracefully (fall back to defaults).
