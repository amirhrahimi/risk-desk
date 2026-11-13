# ADR-016 Logger configuration is static

- **Context:** Platform, Services, App and the scripts all log (rule R8), and BrokerProbe has no `CApp` to own a logger. Threading a logger instance through every static Platform helper adds noise. CLAUDE.md §6 allows no global mutable state outside `App/State.mqh`.
- **Decision:** `CLogger` keeps its configuration (level, file mirror on/off, tag) in static members set once by `Configure()` in `OnInit`/`OnStart`; code logs through `RD_LOG_ERROR/WARN/INFO/DEBUG`. This is the only static state outside `App/State.mqh`, and it holds configuration, never application state.
- **Consequences:** One configuration line per entry point. Each EA instance has its own copy (MQL programs share no memory). The daily file is opened, appended and closed per line so several charts can write it.
