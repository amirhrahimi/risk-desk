# ADR-032 Development on macOS and Linux: the build scripts run MetaTrader under Wine

- **Context:** The owner wants Risk Desk to be developable on macOS and Linux as well as Windows (2026-11-14). The MQL sources need no change, since MetaEditor compiles the same files wherever it runs. The tooling in `build/` assumed Windows: Windows PowerShell, backslash paths in `Join-Path`, `$env:TEMP`, directory junctions, MetaEditor and the terminals started as native programs, a running terminal found by its program path and closed with `CloseMainWindow`, window captures through `user32.dll`, and `origin.txt` in every data folder. On macOS and Linux MetaTrader runs only under Wine. MetaQuotes ships a macOS app with its own Wine (prefix `~/Library/Application Support/net.metaquotes.wine.metatrader5`) and a Linux installer `mt5linux.sh` (prefix `~/.mt5`). In both, the data folder is the install folder `drive_c/Program Files/MetaTrader 5`, with no `origin.txt`.
- **Decision:**
  - **One set of scripts.** The PowerShell scripts stay the only build tooling. They run on Windows PowerShell 5.1 and on PowerShell 7 under Windows, macOS and Linux. There is no second set of shell scripts to keep in step.
  - **`build/host.ps1`** holds everything that differs between Windows and Wine, dot-sourced by the scripts:
    - **Paths:** forward slashes in `Join-Path`; `~` expands to the home folder. `Join-RdPath` matches the existing parts of a terminal path without regard to case on macOS and Linux, because a Wine install created `Config` where Windows has `config`. `Find-RdFile` and `Resolve-RdFile` do the same for program names (`MetaEditor64.exe`).
    - **Wine and prefix:** Wine comes from `$Wine4`/`$Wine5` in `paths.local.ps1` (or a terminal's own `Wine` entry), else the Wine inside `/Applications/MetaTrader 4.app` or `MetaTrader 5.app`, else `wine`/`wine64` on the `PATH`. The prefix is the folder above `drive_c` in the program's path, so MetaEditor and each terminal run in their own prefix.
    - **Starting a program:** `<wine> C:\...\program.exe <arguments>` with `WINEPREFIX` set and `WINEDEBUG=-all` (unless `WINEDEBUG` is already set). A path argument becomes `C:\...` inside the prefix's `drive_c` and `Z:\...` elsewhere, without the quotes that Windows uses (Wine quotes an argument that contains a space itself). The repository should therefore sit in a path without spaces; `build.ps1` warns when it does not. Wine's output goes to a pipe that the script drains, not to the script's own output. The wineserver that Wine starts inherits that output and outlives the program, and it kept `| tail` (and potentially a CI step) waiting.
    - **Finding the terminal:** without `origin.txt` the data folder is the install folder. This also covers `/portable` on Windows.
    - **A running terminal** is found by program name (`terminal.exe`, `terminal64.exe`) in the process list, in any prefix. It is closed with Wine's `taskkill /IM` (WM_CLOSE, like `CloseMainWindow`), and stopped with `taskkill /F` only when it does not close. As a result the runners refuse to start while any terminal of the same kind runs under Wine.
  - **`install-junctions.ps1`** creates symbolic links on macOS and Linux. Wine shows them to MetaTrader as ordinary folders.
  - **`run-uitest.ps1`** answers the self-test's window-capture requests on macOS and Linux without a capture, because `PrintWindow` is Win32-only. The self-test goes on, and the runner prints a NOTE.
  - **`package-release.ps1`** writes the zip with .NET's zip API and `/` in every entry name. `Compress-Archive` of Windows PowerShell 5.1 wrote `\`, which would unpack into wrongly named files on macOS and Linux. Released zips were not affected, because CI packs with PowerShell 7.
  - **Checks:** `build/test-build-scripts.ps1` checks the scripts without MetaTrader (parsing, version, `SUMMARY.md`, the path helpers, linking a made-up data folder, `build.ps1` without MetaEditor, the zip layout). The `scripts` workflow runs it on Linux, macOS and Windows, with PowerShell 7 and Windows PowerShell 5.1. Release builds moved to a Linux runner under Wine as well (ADR-033).
  - **Rule for later changes (CLAUDE.md §6):** build scripts use forward slashes, `Get-RdTempDir` instead of `$env:TEMP`, and the `host.ps1` helpers to start, find and close programs.
- **Consequences:**
  - **Verified 2026-11-14 on Linux** in an Ubuntu 24.04 container: PowerShell 7.4, WineHQ Wine 11.21 with the prefix set to Windows 11, and MT5 installed by `mt5setup.exe /auto` into `~/.mt5`.
    - `install-junctions.ps1` created the symbolic links, kept them on a second run, and removed them.
    - `build.ps1 -Target mt5` compiled the four MT5 targets with 0 errors and 0 warnings (the EA in 18 s, as on Windows) and installed the EA.
    - A compile error was reported with its path relative to the repository.
    - `run-tests.ps1` ran RiskDeskTests headless in the Wine terminal: 842 passed, 0 failed, and the terminal closed itself.
    - The terminal and MetaEditor closed on Wine's `taskkill`.
    - `test-build-scripts.ps1` passed (19 checks), as it does on Windows with PowerShell 5.1 and 7 (12 checks).
  - **MetaTrader refuses some Wine versions.** Its anti-debugging check depends on the Wine version and on the prefix's Windows version. In the same container, Ubuntu's own Wine 9.0 and WineHQ's Wine 10.0 stopped the terminal and MetaEditor with "A debugger has been found running in your system". WineHQ 11.21 after `winecfg -v win11` ran both. Forum reports differ by version and date. The scripts cannot fix this: MetaEditor waits behind the dialog until the build's timeout, so CONTRIBUTING.md names the symptom and the setting.
  - **Wine's own first-run prompts block an unattended start.** When a prefix is created or updated, Wine may ask to install Mono or Gecko. The developer starts the terminal and MetaEditor once by hand after installing or updating Wine. Alternatively, `build/install-metatrader-wine.sh` (ADR-033) sets up a prefix with both prompts switched off.
  - **MT4 under Wine:** `install-metatrader-wine.sh` installed MT4 and compiled its four targets with 0 errors and 0 warnings (ADR-033).
  - **Not verified yet:**
    - MT4's `run-tests.ps1` under Wine.
    - MetaQuotes' macOS app, where the Wine path `/Applications/MetaTrader 5.app/Contents/SharedSupport/wine/bin/wine64` comes from forum reports (`$Wine5` overrides it).
    - `run-script.ps1` and `run-uitest.ps1` against a logged-in demo account under Wine.

    ROADMAP.md lists these checks.
  - How the panel looks under Wine (fonts, DPI) is a product question (NFR-01), not part of this decision.
