# ADR-023 Two-column panel for short charts

- **Context:** The owner's T-24 screenshots (2026-11-12) showed the panel on a short chart window. RiskDesk's log shows that both were taken at 125 % (DPI 120). Auto-fit had shrunk the one tall column to scale 0.59 (chart 430 px tall). There the fonts stop at 6–7 pt while the geometry keeps shrinking, so the proportions change. The Pending Info field cut "Buy Stop · 0.27 lot" to "Buy Stop · 0.27", and the status wrapped "Open risk 0.00 / % / 10 %". Higher Windows scaling or a lower screen resolution has the same effect: fewer chart pixels for the same panel. The owner suggested a two-column layout with a setting, and left the design to Claude Code.
- **Decision:**
  - [NEW] `InpPanelColumns` = `Auto` (default) / `One` / `Two` (07, 05 §1).
  - **Layout:** the width is 2 × 160 − 8 px. The left column holds Risk %, Lots and Add Line…Set Pending (the original order). The right column holds Pending Info and Del Pending…Full Close, on the left column's rows. The title row and the status area span both columns. The handle and the camera stay centred.
  - **Auto rule:**
    - With auto-fit on, the panel uses one column unless one column would have to shrink below 85 % of Shape Size Scale to fit the chart. It then uses two columns if they reach a larger scale, or the same scale (0.40) with more of the panel in view.
    - With auto-fit off, it uses two columns when one column is taller than the chart and two columns fit its width.
    - The rule is evaluated on every chart resize together with the scale, and the log line says which layout was chosen. The 85 % threshold keeps a slightly shrunk single column (e.g. 0.94 on a 664 px chart) instead of a panel twice as wide.
  - **A hidden panel keeps its two-column width,** so the show/hide button stays where it was clicked.
  - **Text fitting:** the read-only fields (Lots, Pending Info) get a smaller font instead of a cut text, like the buttons. The status wrap keeps a unit (`%`, `pts`, `pips`, `lot`, `lots`) with its number.
- **Consequences:**
  - On A1's 429 px test chart, Auto shows two columns at scale 0.92; one column fitted only at 0.59.
  - At 125 % and Shape Size Scale 1.0, one column is kept from about 600 px of chart height upward.
  - The panel self-test now checks both layouts, at scales 0.40 / 1.00 / 1.60: widgets inside the panel, none overlapping, rows level, every text fitting. It also checks the fit arithmetic per layout and the Auto rule for 26 chart sizes.
  - T-24 itself (Windows scaling 150 % / 200 %, terminal restarted) stays with the owner.
