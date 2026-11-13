// Risk Desk - risk-based position sizing and trade management for MetaTrader 4/5
// SPDX-License-Identifier: MIT

//+------------------------------------------------------------------+
//| RiskDesk - Scripts/RiskDesk/Tests/TestFixtures.mqh               |
//| Purpose : builders for the plain Domain structs used by the test |
//|           vectors. The numbers are test data from 04-risk-engine |
//|           section 12, not broker assumptions.                    |
//+------------------------------------------------------------------+
#ifndef RD_TESTS_FIXTURES_MQH
#define RD_TESTS_FIXTURES_MQH

#include "..\..\..\Include\RiskDesk\Domain\Types.mqh"

void TfSpec(SSymbolSpec &s, const string name, const int digits, const double point, const double tick,
            const double tickValue, const double volMin, const double volStep, const double volMax)
  {
   s.Reset();
   s.name = name;
   s.digits = digits;
   s.point = point;
   s.tickSize = tick;
   s.tickValue = tickValue;
   s.tickValueProfit = tickValue;
   s.tickValueLoss = tickValue;
   s.contractSize = 1.0;
   s.volMin = volMin;
   s.volStep = volStep;
   s.volMax = volMax;
  }

// EURUSD-like: 5 digits, tick 0.00001 worth 1.00 per lot, lots 0.01/0.01/100.
void TfFx(SSymbolSpec &s)
  {
   TfSpec(s, "EURUSD", 5, 0.00001, 0.00001, 1.0, 0.01, 0.01, 100.0);
  }

void TfAccount(SAccountSpec &a, const string ccy, const double balance)
  {
   a.Reset();
   a.currency = ccy;
   a.balance = balance;
   a.equity = balance;
   a.digitsCcy = 2;
  }

void TfQuote(SQuote &q, const double bid, const double ask)
  {
   q.Reset();
   q.bid = bid;
   q.ask = ask;
  }

void TfLines(SLines &l, const ELineMode mode, const double entry, const double sl, const double tp)
  {
   l.Reset();
   l.mode = mode;
   l.entry = entry;
   l.sl = sl;
   l.tp = tp;
   l.hasTp = (tp > 0.0);
  }

void TfAddPosition(SPosition &arr[], const ulong ticket, const string symbol, const ESide side, const double volume,
                   const double open, const double sl, const long magic, const double lossToSl)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].ticket = ticket;
   arr[n].symbol = symbol;
   arr[n].side = side;
   arr[n].volume = volume;
   arr[n].open = open;
   arr[n].sl = sl;
   arr[n].tp = 0.0;
   arr[n].profit = 0.0;
   arr[n].magic = magic;
   arr[n].lossToSl = lossToSl;
  }

void TfOrder(SOrder &o, const ulong ticket, const string symbol, const ESide side, const EOrderKind kind,
             const double volume, const double price, const double sl, const double tp, const long magic,
             const double lossToSl)
  {
   o.ticket = ticket;
   o.symbol = symbol;
   o.side = side;
   o.kind = kind;
   o.volume = volume;
   o.price = price;
   o.sl = sl;
   o.tp = tp;
   o.magic = magic;
   o.lossToSl = lossToSl;
  }

void TfAddOrder(SOrder &arr[], const ulong ticket, const string symbol, const ESide side, const EOrderKind kind,
                const double price, const double sl, const long magic, const double lossToSl)
  {
   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].ticket = ticket;
   arr[n].symbol = symbol;
   arr[n].side = side;
   arr[n].kind = kind;
   arr[n].volume = 0.1;
   arr[n].price = price;
   arr[n].sl = sl;
   arr[n].tp = 0.0;
   arr[n].magic = magic;
   arr[n].lossToSl = lossToSl;
   arr[n].expiration = 0;
  }

#endif // RD_TESTS_FIXTURES_MQH
