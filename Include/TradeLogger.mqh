//+------------------------------------------------------------------+
//|                                                  TradeLogger.mqh |
//|                        Copyright 2025, Karl Sikas & GitHub Copilot |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Karl Sikas & GitHub Copilot"
#property link      "https://github.com/KarlSikas"

class TradeLogger
{
private:
   string m_file_name;
   bool   m_is_logging_enabled;
   int    m_file_handle;

public:
   TradeLogger(void){ m_is_logging_enabled = false; m_file_handle = INVALID_HANDLE; }
   ~TradeLogger(void){ if(m_file_handle != INVALID_HANDLE) FileClose(m_file_handle); }

   void Init(string file_name, bool logging_enabled)
   {
      m_file_name = file_name;
      m_is_logging_enabled = logging_enabled;
      if(m_is_logging_enabled)
      {
         m_file_handle = FileOpen(m_file_name, FILE_READ|FILE_WRITE|FILE_CSV, ",");
         if(m_file_handle != INVALID_HANDLE)
         {
            if(FileSize(m_file_handle) == 0)
            {
               FileWrite(m_file_handle, "Aeg", "Tüüp", "Sõnum", "Detailid");
            }
            FileSeek(m_file_handle, 0, SEEK_END);
         }
         else { Print("Viga: Ei saanud logifaili avada: ", m_file_name); }
      }
   }

   void LogEvent(string event_type, string message, string details="")
   {
      if(!m_is_logging_enabled || m_file_handle == INVALID_HANDLE) return;
      FileWrite(m_file_handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), event_type, message, details);
      FileFlush(m_file_handle);
   }

   void LogError(string error_source, string error_message)
   {
      if(!m_is_logging_enabled || m_file_handle == INVALID_HANDLE) return;
      FileWrite(m_file_handle, TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS), "ERROR", error_source, error_message);
      FileFlush(m_file_handle);
      Print("LOG ERROR: ", error_source, " - ", error_message);
   }
};
