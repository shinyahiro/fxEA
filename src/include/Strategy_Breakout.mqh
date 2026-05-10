//+------------------------------------------------------------------+
//|                                            Strategy_Breakout.mqh |
//|                                         fxEA Range Breakout      |
//|                                                                  |
//| Entry: Price breaks above/below recent N-bar high/low            |
//| Filters: Time, Volatility                                        |
//| SL/TP: ATR-based calculation                                     |
//+------------------------------------------------------------------+
#property strict

#include "Strategy_Base.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Breakout Strategy Configuration                                   |
//+------------------------------------------------------------------+
struct BreakoutConfig
{
   int            rangePeriod;      // Range lookback period (bars)
   int            breakoutBars;     // Bars to skip for range (avoid current volatility)
   double         minRangePips;     // Minimum range size to trade
   double         maxRangePips;     // Maximum range size (avoid news spikes)
   bool           useAsianRange;    // Use Asian session range
   int            asianStartHour;   // Asian session start (server time)
   int            asianEndHour;     // Asian session end (server time)
};

//+------------------------------------------------------------------+
//| Initialize Breakout Config with defaults                          |
//+------------------------------------------------------------------+
void InitBreakoutConfig(BreakoutConfig &cfg)
{
   cfg.rangePeriod = 20;        // 20 bars = 20 hours on H1
   cfg.breakoutBars = 1;        // Skip current bar
   cfg.minRangePips = 30;       // Minimum 30 pips range
   cfg.maxRangePips = 150;      // Maximum 150 pips range
   cfg.useAsianRange = false;   // Simple N-bar range by default
   cfg.asianStartHour = 0;      // Midnight server time
   cfg.asianEndHour = 6;        // 6 AM server time
}

//+------------------------------------------------------------------+
//| Calculate range high/low                                          |
//+------------------------------------------------------------------+
void GetRangeHighLow(int period, int shift, double &rangeHigh, double &rangeLow)
{
   rangeHigh = High[iHighest(Symbol(), PERIOD_H1, MODE_HIGH, period, shift)];
   rangeLow = Low[iLowest(Symbol(), PERIOD_H1, MODE_LOW, period, shift)];
}

//+------------------------------------------------------------------+
//| Check for Breakout entry signal                                   |
//+------------------------------------------------------------------+
bool Strategy_Breakout_CheckEntry(TradeSignal &signal, const StrategyConfig &config)
{
   InitTradeSignal(signal);

   //=== Time Filter ===
   if(!PassesTimeFilter(config))
      return(false);

   //=== Get Range ===
   // Use bars 2 to N+1 (skip bar 0 and 1 to avoid current volatility)
   int rangePeriod = 20;  // 20 bars lookback
   int shift = 2;         // Start from bar 2

   double rangeHigh, rangeLow;
   GetRangeHighLow(rangePeriod, shift, rangeHigh, rangeLow);

   double rangePips = PriceToPips(rangeHigh - rangeLow);

   //=== Range Size Filter ===
   if(rangePips < 30)  // Too tight, likely no momentum
   {
      return(false);
   }
   if(rangePips > 150)  // Too wide, likely news event
   {
      return(false);
   }

   //=== Check Breakout ===
   // Bar 1 (last closed bar) broke the range
   double prevClose = Close[1];
   double prevHigh = High[1];
   double prevLow = Low[1];

   // Check bar 2 was inside range (confirmation that bar 1 is the breakout bar)
   double bar2Close = Close[2];
   bool bar2WasInside = (bar2Close < rangeHigh && bar2Close > rangeLow);

   if(!bar2WasInside)
      return(false);  // Not a clean breakout

   bool breakoutUp = (prevClose > rangeHigh);
   bool breakoutDown = (prevClose < rangeLow);

   if(!breakoutUp && !breakoutDown)
      return(false);

   //=== Calculate ATR for SL/TP ===
   double atr = iATR(Symbol(), PERIOD_H1, config.atrPeriod, 1);
   if(atr <= 0)
   {
      WriteLog("ERROR", "ATR calculation failed");
      return(false);
   }

   //=== Generate Signal ===
   signal.valid = true;
   signal.strategyId = STRATEGY_BREAKOUT;
   signal.strength = 1.0;
   signal.atr = atr;

   if(breakoutUp)
   {
      signal.direction = OP_BUY;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = rangeLow - atr * 0.5;  // Below range low
      signal.tpPrice = Ask + atr * config.tpAtrMultiplier;
      signal.reason = "BreakoutUP(Range:" + DoubleToString(rangePips, 0) + "pips)";
   }
   else // breakoutDown
   {
      signal.direction = OP_SELL;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = rangeHigh + atr * 0.5;  // Above range high
      signal.tpPrice = Bid - atr * config.tpAtrMultiplier;
      signal.reason = "BreakoutDOWN(Range:" + DoubleToString(rangePips, 0) + "pips)";
   }

   WriteLog("SIGNAL", signal.reason + " High=" + DoubleToString(rangeHigh, 3) +
            " Low=" + DoubleToString(rangeLow, 3));
   return(true);
}

//+------------------------------------------------------------------+
//| Get current Breakout status for display                           |
//+------------------------------------------------------------------+
string Strategy_Breakout_GetStatus(const StrategyConfig &config)
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   double rangeHigh, rangeLow;
   GetRangeHighLow(20, 2, rangeHigh, rangeLow);

   double rangePips = PriceToPips(rangeHigh - rangeLow);
   double atr = iATR(Symbol(), PERIOD_H1, config.atrPeriod, 1);
   double currentPrice = Bid;

   string position = "";
   if(currentPrice > rangeHigh)
      position = "ABOVE RANGE";
   else if(currentPrice < rangeLow)
      position = "BELOW RANGE";
   else
      position = "INSIDE RANGE";

   string out = "";
   out += "Strategy: Range Breakout (20 bars)\n";
   out += "Range High: " + DoubleToString(rangeHigh, digits) + "\n";
   out += "Range Low:  " + DoubleToString(rangeLow, digits) + "\n";
   out += "Range Size: " + DoubleToString(rangePips, 0) + " pips\n";
   out += "Position:   " + position + "\n";
   out += "ATR: " + DoubleToString(PriceToPips(atr), 1) + " pips";

   return(out);
}
//+------------------------------------------------------------------+
