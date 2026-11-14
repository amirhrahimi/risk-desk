# ADR-034 Release builds on Windows, a second build on Linux under Wine

- **Context:** ADR-033 moved the only CI build to `ubuntu-latest`, with MetaEditor under Wine. It works: the pull request that introduced it and its merge to `main` compiled 8 of 8 targets with 0 errors and 0 warnings on GitHub's Ubuntu 24.04 image in about 3.5 minutes (2026-11-14). A review the same day found three weak points. All three concern being able to release, not the correctness of the files:
  - **MetaTrader is not pinned, Wine is.** Every run installs whatever MetaTrader build MetaQuotes' installers deliver that day, and it has to run under one pinned Wine version. MetaTrader already refused Wine 9.0 and 10.0 ("A debugger has been found running in your system", ADR-033). A new MetaTrader build that refuses 11.21 would block every release, including an urgent safety fix, with nothing wrong in the code. The fallback was the Windows job of ADR-030, recovered from git history.
  - **`ubuntu-latest` moves on GitHub's schedule.** The WineHQ package and its i386 dependencies belong to one Ubuntu release.
  - **The released files are used for real-money trading.** MetaQuotes makes MetaEditor for Windows.

  On the other hand, the Linux build is the only check that keeps the Wine path of ADR-032 working for macOS and Linux contributors.
- **Decision:** the owner chose to build on both and publish the Windows build (2026-11-14).
  - **Two jobs, in parallel, on every pull request and push** (`.github/workflows/build.yml`):
    - `windows` on `windows-latest` is the release build. It checks the version and stamps the build metadata (ADR-030). It installs MetaTrader 4 and 5 with `mt4setup.exe /auto` and `mt5setup.exe /auto`, as under ADR-030. It writes a paths file with the two MetaEditor paths and no terminal, compiles with `build.ps1` and packages with `package-release.ps1 -SkipBuild`. It uploads the package to the run and the release files for the `release` job.
    - `linux` on `ubuntu-24.04` is the job of ADR-033: `install-metatrader-wine.sh`, then `build.ps1` under `xvfb-run`, then `package-release.ps1` to check the script on Linux. It uploads nothing and does not stamp the version.
  - **`release` waits for `windows` only.** If `linux` fails, the run shows as failed, but the release or the development build is still published.
  - **The Linux runner is pinned to `ubuntu-24.04`**, the image ADR-033 was verified on. Moving to a newer Ubuntu is a deliberate change, made after the `WINE_VERSION` check of ADR-033 has passed on that release. `windows-latest` stays unpinned: no package of ours is tied to a Windows image.
  - **Both jobs compile with `build.ps1`.** The compile loop that ADR-030 wrote into the workflow does not come back.
- **Consequences:**
  - Released files come from Windows again, as under ADR-030. Wine-built files no longer reach users.
  - When Wine and MetaTrader stop working together, the next pull request or push shows a red `linux` job, and releases are not affected. To fix it, find a Wine version that compiles all eight targets (the check of ADR-033) and update `WINE_VERSION`.
  - If the Windows build breaks, for example because MetaQuotes' installer changes, there are two fallbacks: move the version and upload steps to `linux` and point `release` at it, or build and package locally (ADR-030).
  - Each run uses about 2 minutes of Windows time and about 3.5 minutes of Linux time, which runs in parallel. A pull request waits about 3.5 minutes; a release is published about 2 minutes after the push. Standard runners cost nothing for a public repository.
  - Neither job is a required check. The `protect-main` ruleset only blocks deleting `main` and force-pushing to it. Requiring both jobs before a merge is a repository setting, outside this decision.
  - **Verified 2026-11-14:** the `linux` job is ADR-033's job, which passed on GitHub that day; it only stops stamping the version and uploading. The Windows install steps are those of ADR-030, first verified 2026-11-13. Run locally on Windows, `build.ps1` with a paths file that names the two MetaEditors and no terminal compiled 8 of 8 targets with 0 errors and 0 warnings and copied the EA nowhere. Not yet verified: `build.ps1` on a GitHub Windows runner, which happens on the first pull request with this workflow. A pull request publishes nothing.
