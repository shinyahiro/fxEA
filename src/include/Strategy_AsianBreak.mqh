//+------------------------------------------------------------------+
//|                                            Strategy_AsianBreak.mqh |
//|                                      fxEA True Range Breakout      |
//|                                                                    |
//| Entry: Price breaks a consolidated range with low volatility       |
//| Logic:                                                             |
//|   1. Detect range formation (recent N bars high/low)               |
//|   2. Confirm volatility contraction (ATR below average)            |
//|   3. Enter on H1 close beyond range                                |
//|   4. Reject if volatility is too high (trending, not ranging)      |
//+------------------------------------------------------------------+
#property strict

#include "Strategy_Base.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Global variables for range tracking                               |
//+------------------------------------------------------------------+
datetime g_lastRangeCheck = 0;      // Last range calculation time
double   g_rangeHigh = 0;           // Current range high
double   g_rangeLow = 0;            // Current range low
bool     g_rangeValid = false;      // Range is valid for trading
datetime g_lastTradeDate = 0;       // Last trade date (1 per day)

//+------------------------------------------------------------------+
//| Check if volatility is contracted (ranging market)                |
//+------------------------------------------------------------------+
bool IsVolatilityContracted()
{
   // Calculate recent ATR (14 periods)
   double recentATR = iATR(Symbol(), PERIOD_H1, 14, 1);

   // Calculate average ATR over longer period (50 bars)
   double sumATR = 0;
   for(int i = 1; i <= 50; i++)
   {
      sumATR += iATR(Symbol(), PERIOD_H1, 14, i);
   }
   double avgATR = sumATR / 50;

   // Recent ATR should be less than 80% of average (contracted)
   bool contracted = (recentATR < avgATR * 0.8);

   if(contracted)
   {
      WriteLog("VOLATILITY", "Contracted - Recent:" + DoubleToString(PriceToPips(recentATR), 1) +
               " pips, Avg:" + DoubleToString(PriceToPips(avgATR), 1) + " pips");
   }

   return contracted;
}

//+------------------------------------------------------------------+
//| Calculate range from recent N bars                                |
//+------------------------------------------------------------------+
void CalculateRange(int rangePeriod)
{
   g_rangeHigh = High[iHighest(Symbol(), PERIOD_H1, MODE_HIGH, rangePeriod, 1)];
   g_rangeLow = Low[iLowest(Symbol(), PERIOD_H1, MODE_LOW, rangePeriod, 1)];

   double rangePips = PriceToPips(g_rangeHigh - g_rangeLow);

   // Validate range size
   if(rangePips >= 30 && rangePips <= 100)
   {
      // Check volatility contraction
      if(IsVolatilityContracted())
      {
         g_rangeValid = true;
         WriteLog("RANGE", "Valid range set: " + DoubleToString(g_rangeHigh, 3) +
                  " / " + DoubleToString(g_rangeLow, 3) +
                  " (" + DoubleToString(rangePips, 0) + " pips)");
      }
      else
      {
         g_rangeValid = false;
      }
   }
   else
   {
      g_rangeValid = false;
      if(rangePips < 30)
         WriteLog("RANGE", "Range too tight: " + DoubleToString(rangePips, 0) + " pips");
      else
         WriteLog("RANGE", "Range too wide: " + DoubleToString(rangePips, 0) + " pips");
   }
}

//+------------------------------------------------------------------+
//| Check for True Range Breakout entry signal                        |
//+------------------------------------------------------------------+
bool Strategy_AsianBreak_CheckEntry(TradeSignal &signal, const StrategyConfig &config)
{
   InitTradeSignal(signal);

   // Configuration
   int rangePeriod = 24;    // Look at recent 24 bars (24 hours on H1)
   double buffer = 5;       // Breakout buffer pips

   // Calculate range every hour
   datetime currentBarTime = Time[0];
   if(g_lastRangeCheck != currentBarTime)
   {
      CalculateRange(rangePeriod);
      g_lastRangeCheck = currentBarTime;
   }

   // Check if range is valid
   if(!g_rangeValid)
      return(false);

   // Check if already traded today
   datetime today = TimeCurrent() - (TimeCurrent() % 86400);
   if(g_lastTradeDate == today)
      return(false);

   // Get ATR for SL/TP calculation
   double atr = iATR(Symbol(), PERIOD_H1, config.atrPeriod, 1);
   if(atr <= 0)
   {
      WriteLog("ERROR", "ATR calculation failed");
      return(false);
   }

   // Buffer in price
   double bufferPrice = buffer * GetPipSize();

   // Check breakout on last closed bar (bar[1])
   double prevClose = Close[1];

   // Confirm bar[2] was inside range (clean breakout)
   double bar2Close = Close[2];
   bool bar2WasInside = (bar2Close <= g_rangeHigh && bar2Close >= g_rangeLow);

   if(!bar2WasInside)
      return(false);  // Not a clean breakout

   double rangePips = PriceToPips(g_rangeHigh - g_rangeLow);

   // Bullish breakout
   if(prevClose > g_rangeHigh + bufferPrice)
   {
      signal.valid = true;
      signal.strategyId = STRATEGY_ASIAN_BREAK;
      signal.direction = OP_BUY;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = g_rangeLow - atr * 0.5;  // Below range low
      signal.tpPrice = Ask + atr * config.tpAtrMultiplier;
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "RangeBreakUP(R:" + DoubleToString(rangePips, 0) + "pips)";

      g_lastTradeDate = today;
      g_rangeValid = false;  // Invalidate range after trade
      WriteLog("SIGNAL", signal.reason);
      return(true);
   }

   // Bearish breakout
   if(prevClose < g_rangeLow - bufferPrice)
   {
      signal.valid = true;
      signal.strategyId = STRATEGY_ASIAN_BREAK;
      signal.direction = OP_SELL;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = g_rangeHigh + atr * 0.5;  // Above range high
      signal.tpPrice = Bid - atr * config.tpAtrMultiplier;
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "RangeBreakDOWN(R:" + DoubleToString(rangePips, 0) + "pips)";

      g_lastTradeDate = today;
      g_rangeValid = false;  // Invalidate range after trade
      WriteLog("SIGNAL", signal.reason);
      return(true);
   }

   return(false);
}

//+------------------------------------------------------------------+
//| Get current Range Breakout status for display                     |
//+------------------------------------------------------------------+
string Strategy_AsianBreak_GetStatus(const StrategyConfig &config)
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   string out = "";
   out += "Strategy: True Range Breakout (24H)\n";

   if(g_rangeValid)
   {
      double rangePips = PriceToPips(g_rangeHigh - g_rangeLow);
      double currentPrice = Bid;

      string position = "";
      if(currentPrice > g_rangeHigh)
         position = "ABOVE RANGE";
      else if(currentPrice < g_rangeLow)
         position = "BELOW RANGE";
      else
         position = "INSIDE RANGE";

      // Calculate ATR ratio
      double recentATR = iATR(Symbol(), PERIOD_H1, 14, 1);
      double sumATR = 0;
      for(int i = 1; i <= 50; i++)
         sumATR += iATR(Symbol(), PERIOD_H1, 14, i);
      double avgATR = sumATR / 50;
      double atrRatio = (recentATR / avgATR) * 100;

      out += "Range High: " + DoubleToString(g_rangeHigh, digits) + "\n";
      out += "Range Low:  " + DoubleToString(g_rangeLow, digits) + "\n";
      out += "Range: " + DoubleToString(rangePips, 0) + " pips\n";
      out += "Price: " + position + "\n";
      out += "ATR: " + DoubleToString(atrRatio, 0) + "% of avg (contracted)";
   }
   else
   {
      out += "Status: No valid range detected\n";
      out += "Waiting for:\n";
      out += "- Range 30-100 pips\n";
      out += "- ATR < 80% of average";
   }

   return(out);
}
//+------------------------------------------------------------------+
