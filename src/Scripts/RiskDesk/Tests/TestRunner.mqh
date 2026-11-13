// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestRunner.mqh                 |
//| Purpose : the tiny assert helper of RiskDeskTests (08-testing    |
//|           section 2). Counts checks per named test, prints one   |
//|           line per failure, then the summary via Print and       |
//|           Alert, and writes the full report to                   |
//|           MQLx/Files/RiskDesk/tests_<platform>.txt.              |
//|           Test functions take 'CTestRunner &t'; the ASSERT_*     |
//|           macros use that name.                                  |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_RUNNER_MQH
#define RD_TESTS_RUNNER_MQH

#include "..\..\..\Include\RiskDesk\Build.mqh"
#include "..\..\..\Include\RiskDesk\Domain\Types.mqh"

#define ASSERT_TRUE(name, cond)                  t.IsTrue((name), (cond))
#define ASSERT_FALSE(name, cond)                 t.IsTrue((name), !(cond))
#define ASSERT_NEAR(name, actual, expected, eps) t.Near((name), (actual), (expected), (eps))
#define ASSERT_EQ_INT(name, actual, expected)    t.EqInt((name), (long)(actual), (long)(expected))
#define ASSERT_EQ_STR(name, actual, expected)    t.EqStr((name), (actual), (expected))
#define ASSERT_CONTAINS(name, text, part)        t.Contains((name), (text), (part))

class CTestRunner
  {
private:
   string            m_platform;
   string            m_mqlDir;
   string            m_test;
   string            m_testDetail;
   int               m_tests;
   int               m_passed;
   int               m_failed;
   int               m_testChecks;
   int               m_testFailed;
   string            m_report[];

   void              Add(const string line);
   void              CloseTest();
   void              Record(const string check, const bool ok, const string detail);

public:
   void              Start(const string platform, const string mqlDir);
   void              Begin(const string test);
   void              IsTrue(const string check, const bool cond);
   void              Near(const string check, const double actual, const double expected, const double eps);
   void              EqInt(const string check, const long actual, const long expected);
   void              EqStr(const string check, const string actual, const string expected);
   void              Contains(const string check, const string text, const string part);
   int               Passed() const { return m_passed; }
   int               Failed() const { return m_failed; }
   void              Finish();
  };

//+------------------------------------------------------------------+
void CTestRunner::Start(const string platform, const string mqlDir)
  {
   m_platform = platform;
   m_mqlDir = mqlDir;
   m_test = "";
   m_testDetail = "";
   m_tests = 0;
   m_passed = 0;
   m_failed = 0;
   m_testChecks = 0;
   m_testFailed = 0;
   ArrayResize(m_report, 0);
  }

void CTestRunner::Add(const string line)
  {
   int n = ArraySize(m_report);
   ArrayResize(m_report, n + 1);
   m_report[n] = line;
  }

// One report line per test, followed by its failures.
void CTestRunner::CloseTest()
  {
   if(m_test == "")
      return;
   string head = (m_testFailed == 0 ? "PASS  " : "FAIL  ") + m_test + "  (" + IntegerToString(m_testChecks) + " checks";
   if(m_testFailed > 0)
      head += ", " + IntegerToString(m_testFailed) + " failed";
   Add(head + ")");
   if(m_testDetail != "")
      Add(m_testDetail);
   m_test = "";
   m_testDetail = "";
  }

void CTestRunner::Begin(const string test)
  {
   CloseTest();
   m_test = test;
   m_tests++;
   m_testChecks = 0;
   m_testFailed = 0;
  }

void CTestRunner::Record(const string check, const bool ok, const string detail)
  {
   m_testChecks++;
   if(ok)
     {
      m_passed++;
      return;
     }
   m_failed++;
   m_testFailed++;
   string line = "FAIL " + m_test + " / " + check + (detail == "" ? "" : ": " + detail);
   Print(line);
   if(m_testDetail != "")
      m_testDetail += "\r\n";
   m_testDetail += "      - " + check + (detail == "" ? "" : ": " + detail);
  }

//+------------------------------------------------------------------+
void CTestRunner::IsTrue(const string check, const bool cond)
  {
   Record(check, cond, cond ? "" : "expected true");
  }

void CTestRunner::Near(const string check, const double actual, const double expected, const double eps)
  {
   bool ok = MathIsValidNumber(actual) && MathAbs(actual - expected) <= eps;
   Record(check, ok, ok ? "" : "actual " + RdNum(actual, 10) + ", expected " + RdNum(expected, 10) +
          " (tolerance " + DoubleToString(eps, 10) + ")");
  }

void CTestRunner::EqInt(const string check, const long actual, const long expected)
  {
   bool ok = (actual == expected);
   Record(check, ok, ok ? "" : "actual " + IntegerToString(actual) + ", expected " + IntegerToString(expected));
  }

void CTestRunner::EqStr(const string check, const string actual, const string expected)
  {
   bool ok = (actual == expected);
   Record(check, ok, ok ? "" : "actual \"" + actual + "\", expected \"" + expected + "\"");
  }

void CTestRunner::Contains(const string check, const string text, const string part)
  {
   bool ok = (StringFind(text, part) >= 0);
   Record(check, ok, ok ? "" : "\"" + text + "\" does not contain \"" + part + "\"");
  }

//+------------------------------------------------------------------+
//| Summary to the Experts tab and an Alert; full report to a file.  |
//+------------------------------------------------------------------+
void CTestRunner::Finish()
  {
   CloseTest();
   string summary = "RiskDeskTests: " + IntegerToString(m_passed) + " passed, " + IntegerToString(m_failed) +
                    " failed (" + m_platform + ", " + RD_PRODUCT + " " + RD_VERSION + ", " +
                    IntegerToString(m_tests) + " tests)";
   string file = "RiskDesk\\tests_" + m_platform + ".txt";
   ResetLastError();
   int h = FileOpen(file, FILE_WRITE | FILE_TXT | FILE_ANSI, '\t', CP_UTF8);
   if(h == INVALID_HANDLE)
      Print("RiskDeskTests: cannot write ", m_mqlDir, "\\Files\\", file, " (error ", GetLastError(), ")");
   else
     {
      FileWriteString(h, "RiskDeskTests " + RD_VERSION + " on " + m_platform + ", " +
                      TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + "\r\n\r\n");
      int n = ArraySize(m_report);
      for(int i = 0; i < n; i++)
         FileWriteString(h, m_report[i] + "\r\n");
      FileWriteString(h, "\r\n" + summary + "\r\n");
      FileClose(h);
      Print("RiskDeskTests: report written to ", m_mqlDir, "\\Files\\", file);
     }
   Print(summary);
   Alert(summary);
  }

#endif // RD_TESTS_RUNNER_MQH
