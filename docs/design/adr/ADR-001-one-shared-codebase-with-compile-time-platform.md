# ADR-001 One shared codebase with compile-time platform selection

- **Context:** MQL4 (build 600+) and MQL5 share most of the language (classes, structs, chart objects) but differ in trading, account and history APIs. Two separate code bases drift apart.
- **Decision:** One source tree. Platform-specific code only in `Platform/`, selected with `#ifdef __MQL5__`. Same class names and public methods in both implementations (no virtual interfaces needed).
- **Consequences:** Every feature is written once. Platform files carry the burden of parity; reviewers check both implementations together.
