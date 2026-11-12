//+------------------------------------------------------------------+
//| RiskDesk - Services/Logger.mqh                                   |
//| Layer   : Services                                               |
//| Purpose : one logging entry point for every layer except Domain. |
//|           Writes to the Experts tab and, when enabled, mirrors   |
//|           each line to MQLx/Files/RiskDesk/Logs/                 |
//|           RiskDesk_<yyyymmdd>.log (F-32; rotation comes in P7).  |
//|                                                                  |
//| The logger configuration (level, file flag, tag) is held in      |
//| static members, set once by Configure() in OnInit/OnStart. It is |
//| the only static state outside App/State.mqh (ADR-016).           |
//|                                                                  |
//| Use the macros: RD_LOG_ERROR(msg), RD_LOG_WARN(msg),             |
//| RD_LOG_INFO(msg), RD_LOG_DEBUG(msg).                             |
//+------------------------------------------------------------------+
#ifndef RD_SERVICES_LOGGER_MQH
#define RD_SERVICES_LOGGER_MQH

#include "..\Build.mqh"
#include "..\Domain\Types.mqh"

#define RD_LOG_DIR       "RiskDesk\\Logs"

#define RD_LOG_ERROR(msg) CLogger::Write(LOGLEVEL_ERROR, (msg))
#define RD_LOG_WARN(msg)  CLogger::Write(LOGLEVEL_WARN, (msg))
#define RD_LOG_INFO(msg)  CLogger::Write(LOGLEVEL_INFO, (msg))
#define RD_LOG_DEBUG(msg) CLogger::Write(LOGLEVEL_DEBUG, (msg))

class CLogger
  {
private:
   static ELogLevel  s_level;
   static bool       s_toFile;
   static string     s_tag;
   static bool       s_fileFailed;

   static string     LevelText(const ELogLevel level);
   static void       WriteFile(const string line);

public:
   static void       Configure(const ELogLevel level, const bool toFile, const string tag);
   static bool       Enabled(const ELogLevel level) { return level <= s_level; }
   static void       Write(const ELogLevel level, const string message);
   static string     TodayFile();
  };

ELogLevel CLogger::s_level      = LOGLEVEL_INFO;
bool      CLogger::s_toFile     = false;
string    CLogger::s_tag        = RD_PRODUCT;
bool      CLogger::s_fileFailed = false;

//+------------------------------------------------------------------+
void CLogger::Configure(const ELogLevel level, const bool toFile, const string tag)
  {
   s_level = level;
   s_toFile = toFile;
   s_tag = tag;
   s_fileFailed = false;
  }

//+------------------------------------------------------------------+
string CLogger::LevelText(const ELogLevel level)
  {
   switch(level)
     {
      case LOGLEVEL_ERROR:
         return "ERROR";
      case LOGLEVEL_WARN:
         return "WARN ";
      case LOGLEVEL_INFO:
         return "INFO ";
      default:
         return "DEBUG";
     }
  }

//+------------------------------------------------------------------+
//| Relative to MQLx/Files: RiskDesk\Logs\RiskDesk_<yyyymmdd>.log     |
//+------------------------------------------------------------------+
string CLogger::TodayFile()
  {
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);
   return StringFormat("%s\\%s_%04d%02d%02d.log", RD_LOG_DIR, RD_PRODUCT, dt.year, dt.mon, dt.day);
  }

//+------------------------------------------------------------------+
void CLogger::Write(const ELogLevel level, const string message)
  {
   if(level > s_level)
      return;
   string text = LevelText(level) + " | " + message;
   Print(text);
   if(s_toFile)
      WriteFile(TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS) + " " + s_tag + " " + text);
  }

//+------------------------------------------------------------------+
//| Open, append, close: several charts may write the same file.     |
//+------------------------------------------------------------------+
void CLogger::WriteFile(const string line)
  {
   if(s_fileFailed)
      return;
   string name = TodayFile();
   ResetLastError();
   int handle = FileOpen(name, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE, '\t', CP_UTF8);
   if(handle == INVALID_HANDLE)
     {
      s_fileFailed = true;
      Print("WARN  | log file ", name, " cannot be opened (error ", IntegerToString(GetLastError()),
            "); logging continues in the Experts tab only");
      return;
     }
   if(!FileSeek(handle, 0, SEEK_END))
     {
      FileClose(handle);
      return;
     }
   FileWriteString(handle, line + "\r\n");
   FileClose(handle);
  }

#endif // RD_SERVICES_LOGGER_MQH
