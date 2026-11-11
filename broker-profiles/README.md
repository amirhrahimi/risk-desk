# broker-profiles

Real data from the owner's terminals. Claude Code must read these before implementing or debugging anything broker-specific.

| File pattern | Produced by | Content |
|---|---|---|
| `probe_<company>_<MT4 or MT5>_<login>_<yyyymmdd>.txt` | `BrokerProbe` script | Account, terminal and per-symbol properties, value calculations, MT5 OrderCheck results (08-testing §3) |
| `smoke_<company>_<MT4 or MT5>_<login>_<yyyymmdd>.txt` | `GatewaySmoke` script | PASS/FAIL table of real demo trade operations |
| `original-tool-errors.md` | Owner | Experts/Journal lines from the original tool at the brokers where it fails |

Expected accounts (see 08-testing §4): A1 IG MT4 · A2 IC Markets EU MT4 · A3 IC Markets EU MT5 · A4 Dukascopy MT4 · A5 Dukascopy MT5 · A6 MetaQuotes-Demo netting MT5 · A7 cent (optional).

Do not store passwords or real-account numbers here. Demo logins are fine.
