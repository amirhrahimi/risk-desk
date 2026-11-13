# RiskDesk — specification pack

This folder is the starting point of a repository. It contains everything Claude Code needs to build **RiskDesk**, a risk-based trade panel for MetaTrader 4 and 5 that reproduces the workflow of the "Map Manager" freeware (Risk %, Add Line, Buy/Sell, pending orders, Risk Free, Half/Chart/Full Close, spread) and is built to work on every broker, specifically IC Markets EU, Dukascopy and IG.

```
riskdesk/
├─ CLAUDE.md                 rules for Claude Code (read automatically at session start)
├─ README.md                 this file (for you)
├─ CHANGELOG.md
├─ .gitignore
├─ broker-profiles/          BrokerProbe reports from your terminals go here
└─ docs/
   ├─ 01-product-requirements.md   what: features F-01..F-33 with acceptance criteria
   ├─ 02-architecture.md           how: layers, folders, MT4/MT5 mapping, event flow
   ├─ 03-broker-compatibility.md   why it fails at some brokers and the rules that fix it
   ├─ 04-risk-engine.md            formulas + test vectors
   ├─ 05-ui-spec.md                panel, lines, labels
   ├─ 06-trade-operations.md       algorithm for every button
   ├─ 07-settings.md               all inputs and defaults
   ├─ 08-testing.md                unit tests, BrokerProbe, demo test matrix
   ├─ 09-roadmap-and-prompts.md    phases P0–P8 with copy-paste prompts
   ├─ 10-decisions.md              index of the architecture decision records
   ├─ 11-open-questions.md         answer these before P3
   ├─ adr/                         one file per architecture decision record
   └─ history/                     implementation log (history only)
```

## Before you start (15 minutes)

1. **See why the original fails.** On IC Markets and Dukascopy, open the Toolbox (Ctrl+T), click Buy with the original tool, and copy the last lines of the **Experts** and **Journal** tabs into a new file `broker-profiles/original-tool-errors.md`. `docs/03-broker-compatibility.md` §1 explains what each message means.
2. **Answer the open questions** in `docs/11-open-questions.md` (or leave the defaults).
3. **Requirements:** a Windows PC with your terminals installed (one per broker/platform), each logged into a **demo** account; Git; Claude Code.

## Setup

1. Put this folder somewhere without spaces in the path, e.g. `D:\dev\riskdesk`, then:
   ```
   cd D:\dev\riskdesk
   git init
   git add -A
   git commit -m "spec"
   ```
2. In each terminal, note two paths:
   - **Data folder:** File → Open Data Folder (contains `MQL4` or `MQL5`).
   - **MetaEditor:** the terminal's install folder, `metaeditor.exe` (MT4) or `metaeditor64.exe` (MT5).
3. Start Claude Code in the folder (`claude`) and paste the **P0 prompt** from `docs/09-roadmap-and-prompts.md`.
4. When P0 is done:
   - copy `build\paths.example.ps1` to `build\paths.local.ps1` and fill in the paths from step 2;
   - run `powershell -ExecutionPolicy Bypass -File build\install-junctions.ps1` (links the scripts and includes into every terminal; `build\build.ps1` copies the compiled EA into each terminal's `Experts` folder, so one build serves all of them);
   - in each terminal refresh the Navigator, drag **BrokerProbe** onto any chart, then copy the report from `MQL4\Files\RiskDesk\` or `MQL5\Files\RiskDesk\` into `broker-profiles\`;
   - commit.
5. Continue with P1 … P8, one phase per Claude Code session. After each phase: run the tests Claude lists, paste back results/log lines, commit.

## Rules of thumb
- Test only on demo accounts until P8's checklist is green.
- Paste real log lines when something fails; use the template in `docs/08-testing.md` §6.
- If a broker behaves strangely, run BrokerProbe again and commit the new report before asking for a fix.

## Renaming
"RiskDesk" is a code name. To rename, tell Claude Code: "Rename the product to X: title, file names, `RD_` object prefix stays/changes to Y, folder names, docs". Do this before P3 if you can.

## Clean-room note
The docs describe the original tool's **behaviour** from its public user guide. Do not decompile the original `.ex4/.ex5`, and do not reuse its name, logo or texts. Ideas and workflows are fine to reimplement; code, branding and documents belong to their author.

## Disclaimer
Trading tools can lose money through bugs as well as through markets. RiskDesk is a manual-trading aid; verify every result on demo, and keep the original risk limits in place.
