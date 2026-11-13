# ADR-028 The EA sits in the Experts root, without a RiskDesk sub-folder

- **Context:** Since P0 the EA lived in `src/Experts/RiskDesk/RiskDesk.mq4/.mq5`, linked into each terminal as the folder junction `MQLx\Experts\RiskDesk`. The Navigator therefore showed Expert Advisors > RiskDesk (folder) > RiskDesk (EA), which the owner did not want: the EA should appear directly under Expert Advisors. A folder junction cannot put a single file in the Experts root. A hard link cannot cross drives (the repo is on D:, the data folders on C:), and a file symlink needs administrator rights or Windows Developer Mode.
- **Decision:**
  - The entry files move to `src/Experts/RiskDesk.mq4` and `src/Experts/RiskDesk.mq5`; their includes become `..\Include\RiskDesk\...`.
  - `build/build.ps1` compiles them in the repo as before and, when a file compiles with 0 errors and 0 warnings, copies `RiskDesk.ex4/.ex5` into `MQLx\Experts\` of every terminal of that platform in `paths.local.ps1` (a failed copy fails the build).
  - `build/install-junctions.ps1` links only `Scripts\RiskDesk` and `Include\RiskDesk`, and removes a former `Experts\RiskDesk` junction that points into this repository.
  - `build/run-uitest.ps1` starts the EA as `Expert=RiskDesk`.
  - The scripts (BrokerProbe, GatewaySmoke, RiskDeskTests) stay in `Scripts\RiskDesk`: three files grouped in one folder.
- **Consequences:** The terminals hold only the compiled EA, not its source; open `src/Experts/RiskDesk.mq5` from the repo to edit it. A compile started by hand (MetaEditor, F7) writes the `.ex4/.ex5` next to the source in the repo and does not install it: run `build.ps1`. Charts and profiles that had the EA attached as `RiskDesk\RiskDesk` need it attached again from the Experts root. Verified: both targets build clean, and the MT5 panel self-test started from the new path passed (66 passed, 0 failed).
