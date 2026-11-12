//+------------------------------------------------------------------+
//| RiskDesk - UI/PanelObjects.mqh                                   |
//| Layer   : UI                                                     |
//| Purpose : CPanel's object tables (02-architecture section 11):   |
//|           chart object name and type of every panel item, button |
//|           captions, name lookups. Part of CPanel; included at    |
//|           the end of UI/Panel.mqh (split to stay near ~600 lines,|
//|           ADR-021).                                              |
//+------------------------------------------------------------------+
#ifndef RD_UI_PANELOBJECTS_MQH
#define RD_UI_PANELOBJECTS_MQH

//+------------------------------------------------------------------+
//| Chart object names (02-architecture section 11).                 |
//+------------------------------------------------------------------+
string CPanel::ItemName(const EPanelItem i)
  {
   switch(i)
     {
      case PI_BG:
         return "RD_P_BG";
      case PI_HANDLE:
         return "RD_P_HANDLE";
      case PI_TITLE:
         return "RD_P_TITLE";
      case PI_TITLE2:
         return "RD_P_TITLE2";
      case PI_HIDE:
         return "RD_P_HIDE";
      case PI_RISK_CAP:
         return "RD_L_RISK";
      case PI_RISK:
         return "RD_E_RISK";
      case PI_LOTS_CAP:
         return "RD_L_LOTS";
      case PI_LOTS:
         return "RD_E_LOTS";
      case PI_ADDLINE:
         return "RD_B_ADDLINE";
      case PI_DELLINE:
         return "RD_B_DELLINE";
      case PI_BUY:
         return "RD_B_BUY";
      case PI_SELL:
         return "RD_B_SELL";
      case PI_ADDPEND:
         return "RD_B_ADDPEND";
      case PI_SETPEND:
         return "RD_B_SETPEND";
      case PI_PINFO_CAP:
         return "RD_L_PINFO";
      case PI_PINFO:
         return "RD_E_PINFO";
      case PI_DELPEND:
         return "RD_B_DELPEND";
      case PI_RISKFREE:
         return "RD_B_RISKFREE";
      case PI_HALF:
         return "RD_B_HALF";
      case PI_CHARTCLOSE:
         return "RD_B_CHARTCLOSE";
      case PI_FULLCLOSE:
         return "RD_B_FULLCLOSE";
      case PI_SPREAD:
         return "RD_L_SPREAD";
      case PI_STATUS1:
         return "RD_L_STATUS1";
      case PI_STATUS2:
         return "RD_L_STATUS2";
      case PI_STATUS3:
         return "RD_L_STATUS3";
      default:
         return "RD_B_SHOT";
     }
  }

// The move handle is a small button: it has its own background, so it
// is visible on any chart colour (05 section 1 allows a label or a button).
ENUM_OBJECT CPanel::ItemType(const EPanelItem i)
  {
   switch(i)
     {
      case PI_BG:
         return OBJ_RECTANGLE_LABEL;
      case PI_TITLE:
      case PI_TITLE2:
      case PI_RISK_CAP:
      case PI_LOTS_CAP:
      case PI_PINFO_CAP:
      case PI_SPREAD:
      case PI_STATUS1:
      case PI_STATUS2:
      case PI_STATUS3:
         return OBJ_LABEL;
      case PI_RISK:
      case PI_LOTS:
      case PI_PINFO:
         return OBJ_EDIT;
      default:
         return OBJ_BUTTON;
     }
  }

string CPanel::ButtonCaption(const EPanelButton b)
  {
   switch(b)
     {
      case PB_ADDLINE:
         return "Add Line";
      case PB_DELLINE:
         return "Delete Line";
      case PB_BUY:
         return "Buy";
      case PB_SELL:
         return "Sell";
      case PB_ADDPEND:
         return "Add Pend Line";
      case PB_SETPEND:
         return "Set Pending";
      case PB_DELPEND:
         return "Del Pending";
      case PB_RISKFREE:
         return "Risk Free";
      case PB_HALF:
         return "Half Close";
      case PB_CHARTCLOSE:
         return "Chart Close";
      case PB_FULLCLOSE:
         return "Full Close";
      default:
         return "Screenshot";
     }
  }

bool CPanel::ButtonOf(const string name, EPanelButton &b)
  {
   for(int i = 0; i < PB_COUNT; i++)
      if(name == ButtonName((EPanelButton)i))
        {
         b = (EPanelButton)i;
         return true;
        }
   return false;
  }

bool CPanel::IsPanelObject(const string name)
  {
   for(int i = 0; i < PI_COUNT; i++)
      if(name == ItemName((EPanelItem)i))
         return true;
   return false;
  }

#endif // RD_UI_PANELOBJECTS_MQH
