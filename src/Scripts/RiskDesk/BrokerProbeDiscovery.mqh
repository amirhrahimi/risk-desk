//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/BrokerProbeDiscovery.mqh             |
//| Layer   : diagnostics script (part of BrokerProbeCore.mqh)       |
//| Purpose : finds candidates for the test-matrix instruments       |
//|           (08-testing section 4) by currency properties or by    |
//|           keywords in symbol name/description (ADR-017).         |
//|           Diagnostic only: trading code never matches names (R3).|
//| Included by BrokerProbeCore.mqh after its helper functions.      |
//+------------------------------------------------------------------+
#ifndef RD_SCRIPTS_BROKERPROBEDISCOVERY_MQH
#define RD_SCRIPTS_BROKERPROBEDISCOVERY_MQH
//====================================================================
// Test-matrix discovery (08-testing section 4). Broker names differ,
// so instruments are found by currency properties where possible and
// by keywords in the name or description otherwise. The report lists
// what was found; nothing here is used for trading.
//====================================================================
struct SProbeCandidate
  {
   int               instrument;
   string            name;
   int               score;     // lower is better
  };

void ProbeAddCandidate(SProbeCandidate &list[], const int instrument, const string name, const int score)
  {
   int n = ArraySize(list);
   ArrayResize(list, n + 1);
   list[n].instrument = instrument;
   list[n].name = name;
   list[n].score = score;
  }

bool ProbeHasKeyword(const string upperText, const string keywordsCsv)
  {
   if(keywordsCsv == "")
      return false;
   string words[];
   int n = StringSplit(keywordsCsv, ',', words);
   for(int i = 0; i < n; i++)
      if(words[i] != "" && StringFind(upperText, words[i]) >= 0)
         return true;
   return false;
  }

// Fills 'lines' with one report line per instrument and adds the
// candidates to 'symbols'.
void ProbeFindTestSymbols(string &symbols[], string &lines[])
  {
   string labels[]   = {"EURUSD", "USDJPY", "EURGBP (cross)", "XAUUSD", "US30", "Nasdaq 100", "BTCUSD", "whole-contract CFD"};
   string bases[]    = {"EUR", "USD", "EUR", "XAU", "", "", "BTC", ""};
   string profits[]  = {"USD", "JPY", "GBP", "USD", "", "", "USD", ""};
   string keywords[] = {"", "", "", "XAU,GOLD",
                        "US30,USA30,US 30,DJ30,DJI,DOW,WALL ST,WALLST,WS30",
                        "NAS100,NAS 100,NASDAQ,US100,USTEC,USTECH,US TECH,NDX,TECH100",
                        "BTC,BITCOIN", ""};
   int count = ArraySize(labels);

   SProbeCandidate found[];

   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
     {
      string name = SymbolName(i, false);
      if(SymbolInfoInteger(name, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
         continue;
      string base = SymbolInfoString(name, SYMBOL_CURRENCY_BASE);
      string profit = SymbolInfoString(name, SYMBOL_CURRENCY_PROFIT);
      string upperName = ProbeUpper(name);
      string upperDesc = ProbeUpper(SymbolInfoString(name, SYMBOL_DESCRIPTION));
      int penalty = (ProbeInMarketWatch(name) ? 0 : 1000) + StringLen(name);

      for(int k = 0; k < count; k++)
        {
         int score = -1;
         if(k == count - 1)
           {
            // whole-contract CFD: minimum volume of at least 1, not forex
            if(SymbolInfoDouble(name, SYMBOL_VOLUME_MIN) >= 1.0 - 1e-8 && !RdIsForexCalcMode(RdSymbolCalcMode(name)))
               score = penalty;
           }
         else
           {
            if(bases[k] != "" && base == bases[k] && profit == profits[k])
               score = penalty;
            else
               if(ProbeHasKeyword(upperName, keywords[k]))
                  score = 300 + penalty;
               else
                  if(ProbeHasKeyword(upperDesc, keywords[k]))
                     score = 600 + penalty;
           }
         if(score >= 0)
            ProbeAddCandidate(found, k, name, score);
        }
     }

   //--- per instrument: the RD_PROBE_CANDIDATES best scores
   int n = ArraySize(found);
   bool used[];
   ArrayResize(used, n);
   for(int i = 0; i < n; i++)
      used[i] = false;
   for(int k = 0; k < count; k++)
     {
      string text = "";
      for(int pick = 0; pick < RD_PROBE_CANDIDATES; pick++)
        {
         int best = -1;
         for(int i = 0; i < n; i++)
            if(!used[i] && found[i].instrument == k && (best < 0 || found[i].score < found[best].score))
               best = i;
         if(best < 0)
            break;
         used[best] = true;
         string name = found[best].name;
         text = RdJoin(text, name + (ProbeInMarketWatch(name) ? " (market watch)" : " (not in market watch)"), ", ");
         ProbeAddUnique(symbols, name);
        }
      ProbeAdd(lines, RdPadRight(labels[k] + ":", RD_PROBE_KEY_WIDTH) + " " + (text == "" ? "none found" : text));
     }
  }

#endif // RD_SCRIPTS_BROKERPROBEDISCOVERY_MQH
