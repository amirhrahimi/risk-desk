# 10 — Architecture Decision Records

Format: Context → Decision → Consequences. One file per ADR in `docs/design/adr/` (`ADR-NNN-<slug>.md`). Add a new ADR as the next number in its own file and a row at the end of this index; never rewrite accepted ones (supersede them instead).

Read only the ADRs a task names or touches; the titles below say what each one decides.

| ADR | Decision |
|---|---|
| [ADR-001](adr/ADR-001-one-shared-codebase-with-compile-time-platform.md) | One shared codebase with compile-time platform selection |
| [ADR-002](adr/ADR-002-no-mt5-standard-library-ctrade-controls.md) | No MT5 Standard Library (CTrade, Controls) |
| [ADR-003](adr/ADR-003-money-value-ordercalcprofit-on-mt5-tick-value.md) | Money value: OrderCalcProfit on MT5, tick value + cross-check on MT4 |
| [ADR-004](adr/ADR-004-lots-always-rounded-down-refuse-below-min-lot-by.md) | Lots always rounded down; refuse below min lot by default |
| [ADR-005](adr/ADR-005-filling-policy-and-expiration-fallback-ladders.md) | Filling-policy and expiration fallback ladders |
| [ADR-006](adr/ADR-006-a-riskdesk-position-never-stays-without-sl.md) | A RiskDesk position never stays without SL |
| [ADR-007](adr/ADR-007-ui-from-standard-chart-objects-not-ccanvas.md) | UI from standard chart objects, not CCanvas |
| [ADR-008](adr/ADR-008-tool-trades-by-magic-number-chart-operations-act.md) | Tool trades by magic number; chart operations act on all trades of the symbol by default |
| [ADR-009](adr/ADR-009-persistence-in-files-under-mqlx-files-riskdesk.md) | Persistence in files under MQLx/Files/RiskDesk |
| [ADR-010](adr/ADR-010-synchronous-requests.md) | Synchronous requests |
| [ADR-011](adr/ADR-011-diagnostics-before-features-brokerprobe.md) | Diagnostics before features (BrokerProbe, GatewaySmoke) |
| [ADR-012](adr/ADR-012-mirror-the-originals-inputs-and-defaults-where.md) | Mirror the original's inputs and defaults where known |
| [ADR-013](adr/ADR-013-tp-modes-derived-from-the-originals-full-input.md) | TP modes derived from the original's full input labels |
| [ADR-014](adr/ADR-014-placed-pending-orders-are-drawn-by-riskdesk-and.md) | Placed pending orders are drawn by RiskDesk and moved by dragging |
| [ADR-015](adr/ADR-015-build-configuration-file-and-version-numbering.md) | Build configuration file and version numbering before 1.0.0 |
| [ADR-016](adr/ADR-016-logger-configuration-is-static.md) | Logger configuration is static |
| [ADR-017](adr/ADR-017-brokerprobe-structure-and-early-platform-building.md) | BrokerProbe structure and early Platform building blocks |
| [ADR-018](adr/ADR-018-domain-api-shape-phase-p1.md) | Domain API shape (phase P1) |
| [ADR-019](adr/ADR-019-trade-gateway-structure-and-the-decisions-taken-in.md) | Trade gateway structure and the decisions taken in phase P2 |
| [ADR-020](adr/ADR-020-unattended-diagnostic-runs-and-what-the-first-real.md) | Unattended diagnostic runs, and what the first real runs changed |
| [ADR-021](adr/ADR-021-panel-ui-shell-phase-p3-structure-and-what-the.md) | Panel UI shell (phase P3): structure, and what the first runs on the owner's terminals changed |
| [ADR-022](adr/ADR-022-market-orders-phase-p4-structure-and-what-the-spec.md) | Market orders (phase P4): structure, and what the spec left open |
| [ADR-023](adr/ADR-023-two-column-panel-for-short-charts.md) | Two-column panel for short charts |
| [ADR-024](adr/ADR-024-line-labels-keep-clear-of-the-panel.md) | Line labels keep clear of the panel |
| [ADR-025](adr/ADR-025-pending-orders-phase-p5-set-pending-del-pending.md) | Pending orders (phase P5): Set Pending, Del Pending, the overlay and moving an order by its line |
| [ADR-026](adr/ADR-026-trade-management-phase-p6.md) | Trade management (phase P6): Risk Free, Half Close, Chart Close, Full Close |
| [ADR-027](adr/ADR-027-chart-extras-phase-p7.md) | Chart extras (phase P7): candle time, closed-trade objects, cent display, log retention |
| [ADR-028](adr/ADR-028-ea-in-the-experts-root.md) | The EA sits in the Experts root, without a RiskDesk sub-folder |
| [ADR-029](adr/ADR-029-open-source-publication.md) | Open-source publication: MIT licence, attribution, docs layout, redacted reports, version 1.7.0 |
| [ADR-030](adr/ADR-030-releases-from-ci.md) | Releases are built and published by CI: MT4+MT5 build on every pull request and push, versioned release or development build on `main` |
| [ADR-031](adr/ADR-031-fault-injection-for-the-safety-paths.md) | Fault injection for the safety paths (T-29, T-35, BC-06 fallback) driven by the `safety` self-test suite; BC-14 ignores trades that existed before the request |
