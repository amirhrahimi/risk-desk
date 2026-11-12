# ADR-004 Lots always rounded down; refuse below min lot by default

- **Context:** Rounding up or sending the min lot silently can exceed the user's risk.
- **Decision:** `FloorVolume` with epsilon; below min → refuse with numbers; opt-in `InpAllowMinLotOverRisk`.
- **Consequences:** Risk is never exceeded silently; some small-risk trades on whole-contract CFDs are refused with a clear reason.
