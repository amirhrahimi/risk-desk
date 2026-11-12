# ADR-024 Line labels keep clear of the panel

- **Context:** In the owner's T-24 screenshots the SL and ENTRY labels ran underneath the panel. The labels sit right of the current candle (05 §5), which is where a panel near the price scale, or one dragged over the chart, usually is. The panel is drawn on top (ADR-022), so the risk in money on the SL label was hidden. The two-column panel (ADR-023) is wider and covers more. The owner chose to draw such a label to the left of the panel.
- **Decision:**
  - On every refresh, `CLines` receives the panel's shown rectangle (anchor to camera, or to the title row when hidden). It measures each label's box (`ChartTimePriceToXY` + `TextGetSize` in the label's font).
  - **Where a label goes:**
    - If the panel would cover the label, it is right-aligned on the last bar that keeps it 6 px (× DPI/96) left of the panel.
    - Without room on the left, it is left-aligned right of the panel, if it then ends before the price scale.
    - Otherwise it stays where it was (covered, as before).
  - **Pixel to time:** bars are evenly spaced on the chart, also right of the current bar, so a pixel x becomes a time from bar 0's x and the bar spacing (`iTime` for past bars, `t0 + n × period` for future ones). The label then lands on a bar boundary, up to one bar width further from the panel.
  - The labels stay `OBJ_TEXT` at the line's price, so a vertical scroll still moves them with their lines. Only their time and anchor change, and only when the computed values differ.
- **Consequences:**
  - A label follows the panel when it is dragged, and the chart when it is scrolled or zoomed, within one refresh (250 ms).
  - The trade self-test moves the panel over the SL label in T-03 and checks that the label ends up beside the panel, not under it. The runner takes a real window capture of that state.
  - `ChartScreenShot` re-renders the chart at the size it is given. A size other than the window's (the self-test's chart + 100 × chart + 40, or F-19's plotting-area size, which then also holds the price and time scales) shifts time/price-anchored objects against pixel-anchored ones. In a screenshot, a label can therefore appear a few dozen pixels closer to, or under, the panel although it is clear of it on screen. MQL gives no property for the scale widths, so F-19 keeps its size. Cosmetic: the trade data in the image is unaffected.
