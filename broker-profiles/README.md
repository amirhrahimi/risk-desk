# broker-profiles

Real data from the owner's terminals. Claude Code must check it before implementing or debugging anything broker-specific: start with `SUMMARY.md`, and for a property or symbol it lacks read only that `[symbol NAME]` section of the probe report (each probe is ~90 KB).

| File pattern | Produced by | Content |
|---|---|---|
| `SUMMARY.md` | `build/summarize-profiles.ps1` (run it after adding a report) | Per account: account line, the test-matrix symbols' properties, the probe's items to check, the latest GatewaySmoke result per symbol |
| `probe_<company>_<MT4 or MT5>_<login>_<yyyymmdd>.txt` | `BrokerProbe` script | Account, terminal and per-symbol properties, value calculations, MT5 OrderCheck results (08-testing §3) |
| `smoke_<company>_<MT4 or MT5>_<login>_<yyyymmdd>.txt` | `GatewaySmoke` script | PASS/FAIL table of real demo trade operations |
| `original-tool-errors.md` | Owner | Experts/Journal lines from the original tool at the brokers where it fails |

Expected accounts (see 08-testing §4): A1 IG MT4 · A2 IC Markets EU MT4 · A3 IC Markets EU MT5 · A4 Dukascopy MT4 · A5 Dukascopy MT5 · A6 MetaQuotes-Demo netting MT5 · A7 cent (optional).

Do not store passwords or real-account numbers here. Demo logins are fine.
