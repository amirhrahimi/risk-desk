# Security policy

## Supported versions

| Version | Supported |
|---|---|
| 1.8.0 | yes |
| 1.8.0 release candidates and 1.7.x (pre-releases) | no |
| internal builds before 1.7.0 | no |

Only the latest release receives fixes.

## What counts as a security issue

Risk Desk runs inside MetaTrader, has no network access of its own and loads no DLLs. A security issue is, for example:

- Risk Desk opening, modifying or closing an order **without a click** by the user (or a drop of a dragged pending-order line);
- a way to make Risk Desk send an order with a different volume, symbol, stop-loss or price than the panel shows;
- Risk Desk reading or writing files outside `MQL4/Files/RiskDesk/` or `MQL5/Files/RiskDesk/`;
- the published code, release zips or documentation leaking credentials or personal data.

**Not** security issues: trading losses, slippage, requotes, broker rejections, gaps, wrong expectations about market behaviour, or a lot size you disagree with. Report wrong lot sizes or refused orders as a [bug](https://github.com/amirhrahimi/risk-desk/issues/new?template=bug_report.yml).

## How to report

Open an [issue](https://github.com/amirhrahimi/risk-desk/issues/new) titled **"Security: <short summary>"**.

- **Do not** include account numbers, passwords, statements or unredacted logs.
- If the details would let someone else cause harm before a fix exists, describe only the effect in the issue (for example "an order can be sent without a click") and say that you have details. The maintainer will arrange a private way to receive them.

You can expect a first reply within a reasonable time. Fixes for confirmed issues are released as a patch version and noted in [CHANGELOG.md](CHANGELOG.md).

## Using Risk Desk safely

- Test every new version and every new broker on a **demo** account first.
- Download releases only from this repository's [Releases page](https://github.com/amirhrahimi/risk-desk/releases) and compare the zip with its `.sha256.txt`. Prefer a numbered release; the *Development build* there is untested. Do not run `.ex4`/`.ex5` files from other sources that claim to be Risk Desk.
- Never share your trading password. Risk Desk never asks for it.
