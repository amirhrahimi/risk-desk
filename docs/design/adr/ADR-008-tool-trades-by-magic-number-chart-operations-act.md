# ADR-008 Tool trades by magic number; chart operations act on all trades of the symbol by default

- **Context:** The original's risk cap applies to its own trades only, but its Chart/Half/Risk-Free buttons act on "all trades on the chart".
- **Decision:** Magic number identifies tool trades for the risk budget. Chart-scope and account-scope operations default to all trades (parity) and can be limited to tool trades by setting.
- **Consequences:** Same behaviour as the original out of the box; users mixing other EAs can restrict scope.
