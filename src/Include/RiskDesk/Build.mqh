//+------------------------------------------------------------------+
//| RiskDesk - Build.mqh                                             |
//| Layer   : build configuration. Included first by every entry     |
//|           file (EAs and scripts).                                |
//| Purpose : product name, version, release/debug switch.           |
//|                                                                  |
//| Version : SemVer in RD_VERSION. Bump it at the end of each phase |
//|           together with CHANGELOG.md. '#property version' is not |
//|           set before 1.0.0: MetaEditor warns (68) on any major   |
//|           version 0, and builds must have 0 warnings (ADR-015).  |
//| Debug   : MetaEditor has no command-line define switch, so       |
//|           'build.ps1 -Debug' un-comments the test-hooks define   |
//|           at the end of this file for the duration of the build  |
//|           and restores the file afterwards. A release build      |
//|           refuses to start while the define is active.           |
//+------------------------------------------------------------------+
#ifndef RD_BUILD_MQH
#define RD_BUILD_MQH

#define RD_PRODUCT     "RiskDesk"
#define RD_VERSION     "0.0.1"
#define RD_COPYRIGHT   "RiskDesk"

//#define RD_TEST_HOOKS

#endif // RD_BUILD_MQH
