//+------------------------------------------------------------------+
//| RiskDesk - Services/Persistence.mqh                              |
//| Layer   : Services                                               |
//| Purpose : small key=value files under MQLx/Files/RiskDesk        |
//|           (ADR-009, 02-architecture section 8):                  |
//|             ui.ini            panel x, y, hidden (global)        |
//|             acct_<login>.ini  Risk % of that account             |
//|           CKeyValueFile reads/writes one file; a missing or      |
//|           unreadable file is an empty file (callers fall back to |
//|           their defaults). Writes go to a temporary file that is |
//|           then moved over the old one, so a crash never leaves a |
//|           half-written file.                                     |
//+------------------------------------------------------------------+
#ifndef RD_SERVICES_PERSISTENCE_MQH
#define RD_SERVICES_PERSISTENCE_MQH

#include "..\Domain\Types.mqh"
#include "Logger.mqh"

#define RD_FILES_DIR   "RiskDesk"

//+------------------------------------------------------------------+
class CKeyValueFile
  {
private:
   string            m_keys[];
   string            m_values[];

   int               Find(const string key) const;

public:
   void              Clear() { ArrayResize(m_keys, 0); ArrayResize(m_values, 0); }
   int               Count() const { return ArraySize(m_keys); }
   bool              Has(const string key) const { return Find(key) >= 0; }
   bool              Load(const string path);
   bool              Save(const string path, const string header);

   string            GetString(const string key, const string fallback) const;
   double            GetDouble(const string key, const double fallback) const;
   int               GetInt(const string key, const int fallback) const;
   bool              GetBool(const string key, const bool fallback) const;

   void              SetString(const string key, const string value);
   void              SetDouble(const string key, const double value, const int decimals);
   void              SetInt(const string key, const int value) { SetString(key, IntegerToString(value)); }
   void              SetBool(const string key, const bool value) { SetString(key, value ? "true" : "false"); }
  };

int CKeyValueFile::Find(const string key) const
  {
   int n = ArraySize(m_keys);
   for(int i = 0; i < n; i++)
      if(m_keys[i] == key)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Lines "key=value"; '#' or ';' starts a comment line; blank lines |
//| and lines without '=' are ignored. False when the file is        |
//| missing or cannot be opened (the object is then empty).          |
//+------------------------------------------------------------------+
bool CKeyValueFile::Load(const string path)
  {
   Clear();
   if(!FileIsExist(path))
      return false;
   ResetLastError();
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, '\t', CP_UTF8);
   if(h == INVALID_HANDLE)
     {
      RD_LOG_WARN("Cannot read " + path + " (error " + IntegerToString(GetLastError()) + ") - using defaults");
      return false;
     }
   while(!FileIsEnding(h))
     {
      string line = RdTrim(FileReadString(h));
      if(line == "")
         continue;
      ushort first = StringGetCharacter(line, 0);
      if(first == '#' || first == ';')
         continue;
      int eq = StringFind(line, "=");
      if(eq <= 0)
         continue;
      SetString(RdTrim(StringSubstr(line, 0, eq)), RdTrim(StringSubstr(line, eq + 1)));
     }
   FileClose(h);
   return true;
  }

//+------------------------------------------------------------------+
//| Write <path>.tmp, then move it over <path>.                      |
//+------------------------------------------------------------------+
bool CKeyValueFile::Save(const string path, const string header)
  {
   string tmp = path + ".tmp";
   ResetLastError();
   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI, '\t', CP_UTF8);
   if(h == INVALID_HANDLE)
     {
      RD_LOG_WARN("Cannot write " + tmp + " (error " + IntegerToString(GetLastError()) + ")");
      return false;
     }
   if(header != "")
      FileWriteString(h, "# " + header + "\r\n");
   int n = ArraySize(m_keys);
   for(int i = 0; i < n; i++)
      FileWriteString(h, m_keys[i] + "=" + m_values[i] + "\r\n");
   FileClose(h);
   ResetLastError();
   if(!FileMove(tmp, 0, path, FILE_REWRITE))
     {
      RD_LOG_WARN("Cannot replace " + path + " (error " + IntegerToString(GetLastError()) + ")");
      FileDelete(tmp);
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
string CKeyValueFile::GetString(const string key, const string fallback) const
  {
   int i = Find(key);
   return (i < 0) ? fallback : m_values[i];
  }

double CKeyValueFile::GetDouble(const string key, const double fallback) const
  {
   int i = Find(key);
   if(i < 0 || m_values[i] == "")
      return fallback;
   double v = StringToDouble(m_values[i]);
   return MathIsValidNumber(v) ? v : fallback;
  }

int CKeyValueFile::GetInt(const string key, const int fallback) const
  {
   int i = Find(key);
   if(i < 0 || m_values[i] == "")
      return fallback;
   return (int)StringToInteger(m_values[i]);
  }

bool CKeyValueFile::GetBool(const string key, const bool fallback) const
  {
   int i = Find(key);
   if(i < 0)
      return fallback;
   string v = m_values[i];
   StringToLower(v);
   if(v == "true" || v == "1" || v == "yes")
      return true;
   if(v == "false" || v == "0" || v == "no")
      return false;
   return fallback;
  }

void CKeyValueFile::SetString(const string key, const string value)
  {
   int i = Find(key);
   if(i < 0)
     {
      i = ArraySize(m_keys);
      ArrayResize(m_keys, i + 1);
      ArrayResize(m_values, i + 1);
      m_keys[i] = key;
     }
   m_values[i] = value;
  }

void CKeyValueFile::SetDouble(const string key, const double value, const int decimals)
  {
   SetString(key, DoubleToString(value, decimals));
  }

//+------------------------------------------------------------------+
//| The panel state kept between sessions (ui.ini).                  |
//| inputX/inputY: X Start / Y Start when the position was saved, so |
//| an edited X/Y Start input wins over the saved position (D15).    |
//+------------------------------------------------------------------+
struct SUiPersist
  {
   bool              found;
   int               x;
   int               y;
   bool              hidden;
   int               inputX;
   int               inputY;

   void              Reset() { found = false; x = 0; y = 0; hidden = false; inputX = -1; inputY = -1; }
  };

//+------------------------------------------------------------------+
class CPersistence
  {
private:
   bool              m_enabled;   // false in the Strategy Tester
   string            m_dir;       // RiskDesk; a sandbox folder during the debug self-test

public:
                     CPersistence() { m_enabled = true; m_dir = RD_FILES_DIR; }
   void              Enable(const bool on) { m_enabled = on; }
   bool              Enabled() const { return m_enabled; }
   void              SetDir(const string dir) { m_dir = dir; }
   string            Dir() const { return m_dir; }

   string            UiPath() const { return m_dir + "\\ui.ini"; }
   string            AccountPath(const long login) const { return m_dir + "\\acct_" + IntegerToString(login) + ".ini"; }

   bool              LoadUi(SUiPersist &ui);
   bool              SaveUi(const SUiPersist &ui);
   bool              LoadRisk(const long login, double &pct);
   bool              SaveRisk(const long login, const double pct);
  };

//+------------------------------------------------------------------+
bool CPersistence::LoadUi(SUiPersist &ui)
  {
   ui.Reset();
   if(!m_enabled)
      return false;
   CKeyValueFile f;
   if(!f.Load(UiPath()) || !f.Has("panel_x") || !f.Has("panel_y"))
      return false;
   ui.found  = true;
   ui.x      = f.GetInt("panel_x", 0);
   ui.y      = f.GetInt("panel_y", 0);
   ui.hidden = f.GetBool("hidden", false);
   ui.inputX = f.GetInt("input_x", -1);
   ui.inputY = f.GetInt("input_y", -1);
   return true;
  }

bool CPersistence::SaveUi(const SUiPersist &ui)
  {
   if(!m_enabled)
      return false;
   CKeyValueFile f;
   f.SetInt("panel_x", ui.x);
   f.SetInt("panel_y", ui.y);
   f.SetBool("hidden", ui.hidden);
   f.SetInt("input_x", ui.inputX);
   f.SetInt("input_y", ui.inputY);
   return f.Save(UiPath(), "RiskDesk panel state (shared by every chart and account)");
  }

//+------------------------------------------------------------------+
//| False when the account has no saved value (first start).         |
//+------------------------------------------------------------------+
bool CPersistence::LoadRisk(const long login, double &pct)
  {
   pct = 0.0;
   if(!m_enabled || login <= 0)
      return false;
   CKeyValueFile f;
   if(!f.Load(AccountPath(login)) || !f.Has("risk_pct"))
      return false;
   pct = f.GetDouble("risk_pct", 0.0);
   return true;
  }

bool CPersistence::SaveRisk(const long login, const double pct)
  {
   if(!m_enabled || login <= 0)
      return false;
   CKeyValueFile f;
   f.Load(AccountPath(login));   // keep keys added by later phases
   f.SetDouble("risk_pct", pct, 2);
   return f.Save(AccountPath(login), "RiskDesk settings of account " + IntegerToString(login));
  }

#endif // RD_SERVICES_PERSISTENCE_MQH
