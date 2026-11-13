//+------------------------------------------------------------------+
//| RiskDesk - Domain/PriceMath.mqh                                  |
//| Layer   : Domain (pure: no terminal calls)                       |
//| Purpose : price and volume grid arithmetic (04-risk-engine       |
//|           section 3, BC-03, BC-04):                              |
//|           - RdNormalizePrice, RdRoundPriceUp/Down: to the TICK   |
//|             SIZE, not only to Digits                             |
//|           - RdPriceEq/Lt/Gt/Le/Ge: half-tick tolerance           |
//|           - RdDistAtLeast/RdDistMoreThan: BC-07 distances        |
//|           - RdPointsBetween, RdTicksBetween                      |
//|           - RdVolumeDigits, RdFloorVolume (never rounds up, with |
//|             the +1e-8 epsilon), RdIsValidVolume, RdVolEq/Lt/Gt   |
//| Never compare prices or volumes with ==; use these helpers.      |
//+------------------------------------------------------------------+
#ifndef RD_DOMAIN_PRICEMATH_MQH
#define RD_DOMAIN_PRICEMATH_MQH

#include "Types.mqh"

#define RD_VOL_EPS      1e-8    // volume comparisons; FloorVolume epsilon (in steps)
#define RD_VOL_MIN_EPS  1e-12   // "raw < volMin" tolerance (04 section 3)
#define RD_TICK_EPS     1e-8    // directional price rounding epsilon (in ticks)
#define RD_PCT_EPS      1e-9    // percentage caps: equality is allowed

//====================================================================
// Price grid
//====================================================================

// Tick size; the point when the broker reports 0 (BC-02 fallback).
double RdTick(const SSymbolSpec &s)
  {
   if(s.tickSize > 0.0)
      return s.tickSize;
   return s.point;
  }

// Nearest price on the tick grid (BC-03).
double RdNormalizePrice(const SSymbolSpec &s, const double price)
  {
   double tick = RdTick(s);
   if(!(tick > 0.0))
      return NormalizeDouble(price, s.digits);
   return NormalizeDouble(MathRound(price / tick) * tick, s.digits);
  }

// Smallest grid price >= price (a price already on the grid is kept).
double RdRoundPriceUp(const SSymbolSpec &s, const double price)
  {
   double tick = RdTick(s);
   if(!(tick > 0.0))
      return NormalizeDouble(price, s.digits);
   return NormalizeDouble(MathCeil(price / tick - RD_TICK_EPS) * tick, s.digits);
  }

// Largest grid price <= price (a price already on the grid is kept).
double RdRoundPriceDown(const SSymbolSpec &s, const double price)
  {
   double tick = RdTick(s);
   if(!(tick > 0.0))
      return NormalizeDouble(price, s.digits);
   return NormalizeDouble(MathFloor(price / tick + RD_TICK_EPS) * tick, s.digits);
  }

//--- comparisons. Eq, Lt and Gt are exclusive and cover every case:
//    Eq: |a - b| < tick/2,  Lt: a - b <= -tick/2,  Gt: a - b >= tick/2.
bool RdPriceEq(const SSymbolSpec &s, const double a, const double b)
  {
   return MathAbs(a - b) < RdTick(s) / 2.0;
  }

bool RdPriceLt(const SSymbolSpec &s, const double a, const double b)
  {
   return a - b <= -RdTick(s) / 2.0;
  }

bool RdPriceGt(const SSymbolSpec &s, const double a, const double b)
  {
   return a - b >= RdTick(s) / 2.0;
  }

bool RdPriceLe(const SSymbolSpec &s, const double a, const double b)
  {
   return !RdPriceGt(s, a, b);
  }

bool RdPriceGe(const SSymbolSpec &s, const double a, const double b)
  {
   return !RdPriceLt(s, a, b);
  }

//--- distances (BC-07). 'dist' is a price distance, e.g. stopsLevel x point.
// (a - b) >= dist, equality allowed ("Bid - SL >= S").
bool RdDistAtLeast(const SSymbolSpec &s, const double a, const double b, const double dist)
  {
   return (a - b) - dist > -RdTick(s) / 2.0;
  }

// (a - b) > dist by at least one tick ("Bid - SL > F" for the freeze level).
bool RdDistMoreThan(const SSymbolSpec &s, const double a, const double b, const double dist)
  {
   return (a - b) - dist >= RdTick(s) / 2.0;
  }

// |a - b| in points, rounded to the nearest point.
int RdPointsBetween(const SSymbolSpec &s, const double a, const double b)
  {
   if(!(s.point > 0.0))
      return 0;
   return (int)MathRound(MathAbs(a - b) / s.point);
  }

// |a - b| in ticks. Snapped to a whole number when it is one up to float
// noise (normalized prices); otherwise the exact quotient, so a distance
// is never rounded down (rule R5).
double RdTicksBetween(const SSymbolSpec &s, const double a, const double b)
  {
   double tick = RdTick(s);
   if(!(tick > 0.0))
      return 0.0;
   double ticks = MathAbs(a - b) / tick;
   double whole = MathRound(ticks);
   if(MathAbs(ticks - whole) < 1e-6)
      return whole;
   return ticks;
  }

//====================================================================
// Volume grid (BC-04)
//====================================================================

// Decimals of a volume step: 1 -> 0, 0.1 -> 1, 0.01 -> 2, 0.5 -> 1.
int RdVolumeDigits(const double step)
  {
   if(!MathIsValidNumber(step) || step <= 0.0)
      return 0;
   for(int d = 0; d <= 8; d++)
     {
      double scaled = step * MathPow(10.0, d);
      if(MathAbs(scaled - MathRound(scaled)) < RD_VOL_EPS)
         return d;
     }
   return 8;
  }

// Decimals needed to show any volume of the symbol's grid (min + k x step).
int RdLotDigits(const double volMin, const double volStep)
  {
   int a = RdVolumeDigits(volStep);
   int b = RdVolumeDigits(volMin);
   return (a > b) ? a : b;
  }

int RdLotDigits(const SSymbolSpec &s)
  {
   return RdLotDigits(s.volMin, s.volStep);
  }

// Largest grid volume volMin + k x volStep that is <= raw (never rounds
// up, rule R5). False when raw is below volMin ("NONE" in 04 section 3)
// or the grid is invalid. The +1e-8 keeps 0.57 at 0.57: in doubles
// (0.57 - 0.01) / 0.01 = 55.99999999999999.
bool RdFloorVolume(const double raw, const double volMin, const double volStep, double &lots)
  {
   lots = 0.0;
   if(!MathIsValidNumber(raw) || !MathIsValidNumber(volMin) || !MathIsValidNumber(volStep))
      return false;
   if(volStep <= 0.0 || volMin <= 0.0)
      return false;
   if(raw < volMin - RD_VOL_MIN_EPS)
      return false;
   double k = MathFloor((raw - volMin) / volStep + RD_VOL_EPS);
   if(k < 0.0)
      k = 0.0;
   lots = NormalizeDouble(volMin + k * volStep, RdLotDigits(volMin, volStep));
   return true;
  }

bool RdFloorVolume(const SSymbolSpec &s, const double raw, double &lots)
  {
   return RdFloorVolume(raw, s.volMin, s.volStep, lots);
  }

// Grid volume volMin + k x volStep nearest to raw, a tie rounding DOWN (Half
// Close closes the smaller part, so the larger part stays: 04 section 10,
// Q23). Below volMin the choice is nothing or volMin: false when nothing is
// nearer or as near (or the grid is invalid). The -1e-8 (in steps) keeps
// 0.125 at step 0.01 a tie whichever way the doubles round (11.5 - 0.5).
bool RdNearestVolume(const double raw, const double volMin, const double volStep, double &lots)
  {
   lots = 0.0;
   if(!MathIsValidNumber(raw) || !MathIsValidNumber(volMin) || !MathIsValidNumber(volStep))
      return false;
   if(volStep <= 0.0 || volMin <= 0.0 || raw <= 0.0)
      return false;
   int digits = RdLotDigits(volMin, volStep);
   if(raw < volMin - RD_VOL_MIN_EPS)
     {
      if(raw / volMin - RD_VOL_EPS <= 0.5)
         return false;
      lots = NormalizeDouble(volMin, digits);
      return true;
     }
   double k = MathCeil((raw - volMin) / volStep - 0.5 - RD_VOL_EPS);
   if(k < 0.0)
      k = 0.0;
   lots = NormalizeDouble(volMin + k * volStep, digits);
   return true;
  }

bool RdNearestVolume(const SSymbolSpec &s, const double raw, double &lots)
  {
   return RdNearestVolume(raw, s.volMin, s.volStep, lots);
  }

//--- volume comparisons with 1e-8 tolerance
bool RdVolEq(const double a, const double b)
  {
   return MathAbs(a - b) < RD_VOL_EPS;
  }

bool RdVolLt(const double a, const double b)
  {
   return a < b - RD_VOL_EPS;
  }

bool RdVolGt(const double a, const double b)
  {
   return a > b + RD_VOL_EPS;
  }

// On the grid volMin + k x volStep and within [volMin, volMax].
bool RdIsValidVolume(const SSymbolSpec &s, const double volume)
  {
   if(!MathIsValidNumber(volume) || !(s.volStep > 0.0))
      return false;
   if(RdVolLt(volume, s.volMin) || RdVolGt(volume, s.volMax))
      return false;
   double k = (volume - s.volMin) / s.volStep;
   return MathAbs(k - MathRound(k)) * s.volStep < RD_VOL_EPS;
  }

#endif // RD_DOMAIN_PRICEMATH_MQH
