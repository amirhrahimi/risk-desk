// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Build.mqh                                             |
//| Layer   : build configuration. Included first by every entry     |
//|           file (EAs and scripts).                                |
//| Purpose : product name, version, copyright, release/debug switch.|
//|                                                                  |
//| Version : SemVer in RD_VERSION. Bump it together with            |
//|           CHANGELOG.md. RD_VERSION_PROP is the same version in   |
//|           the 'x.yz' form that '#property version' accepts       |
//|           without warning 68 (major.minor patch: 1.7.0 = "1.70");|
//|           every entry file sets '#property version' from it      |
//|           (ADR-015, ADR-029). CI builds that are not a release   |
//|           get the commit appended on the runner only, for        |
//|           example "1.7.0+dev.abc1234" (ADR-030).                 |
//|           build/check-version.ps1 fails the build when the two   |
//|           version values differ.                                 |
//| Debug   : MetaEditor has no command-line define switch, so       |
//|           'build.ps1 -Debug' un-comments the test-hooks define   |
//|           at the end of this file for the duration of the build  |
//|           and restores the file afterwards. A release build      |
//|           refuses to start while the define is active.           |
//+------------------------------------------------------------------+
#ifndef RD_BUILD_MQH
#define RD_BUILD_MQH

#define RD_PRODUCT       "RiskDesk"
#define RD_VERSION       "1.8.0-rc.1"
#define RD_VERSION_PROP  "1.80"
#define RD_COPYRIGHT     "Copyright 2026, Amir Rahimi (MIT licence)"
#define RD_LINK          "https://github.com/amirhrahimi/risk-desk"

//#define RD_TEST_HOOKS

#endif // RD_BUILD_MQH
