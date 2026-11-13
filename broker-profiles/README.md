# broker-profiles

Reports from real demo accounts, produced by Risk Desk's diagnostic scripts. They are the evidence behind [docs/broker-compatibility.md](../docs/broker-compatibility.md). Start with [SUMMARY.md](SUMMARY.md); a probe report is about 90 KB, so for a property or symbol the summary lacks, search the probe for its `[symbol NAME]` section.

| File | Produced by | Content |
|---|---|---|
| `SUMMARY.md` | `build/summarize-profiles.ps1` (run it after adding a report; do not edit by hand) | Per account: account line, the test symbols' properties, the probe's items to check, the latest GatewaySmoke result per symbol |
| `probe_<company>_<MT4 or MT5>_<account>_<yyyymmdd>.txt` | `BrokerProbe` script | Account, terminal and per-symbol properties, value calculations, MT5 `OrderCheck` results. Nothing is traded |
| `smoke_<company>_<MT4 or MT5>_<account>_<yyyymmdd>.txt` | `GatewaySmoke` script (demo only) | PASS/FAIL table of real demo trade operations |

`<account>` is an account label, not a login: A1–A6 are the maintainer's demo accounts (the list in [docs/design/08-testing.md §4](../docs/design/08-testing.md#4-account-and-symbol-matrix-l4)), C1, C2 … are community reports.

## Adding a report

1. Run the script on a **demo** account ([docs/installation.md](../docs/installation.md#run-brokerprobe-optional-recommended-for-a-new-broker)). It writes to `MQL4/Files/RiskDesk/` or `MQL5/Files/RiskDesk/`, with your login in the file name and in the text.
2. Redact it. This replaces the login with the label and blanks the data path, which contains your Windows user name:
   ```
   powershell -ExecutionPolicy Bypass -File build/redact-report.ps1 -Path <report> -Label C1 -OutDir broker-profiles
   ```
3. Check the copy: no login, no `C:\Users\<name>`, no password (the scripts never write one).
4. Run `build/summarize-profiles.ps1`, or attach the redacted report to a [broker test report](https://github.com/amirhrahimi/risk-desk/issues/new?template=broker_test_report.yml) and a maintainer will add it.

Never commit an unredacted report, a live-account report with balances you consider private, or an account statement.
