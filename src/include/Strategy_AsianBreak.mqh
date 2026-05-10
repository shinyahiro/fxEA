//+------------------------------------------------------------------+
//|                                            Strategy_AsianBreak.mqh |
//|                                    fxEA Previous Day Breakout      |
//|                                                                    |
//| Entry: Price breaks previous day's high/low                        |
//| Logic:                                                             |
//|   1. Calculate previous day (D1) high/low                          |
//|   2. Wait for H1 close above/below previous day range              |
//|   3. One trade per day maximum                                     |
//|   4. If price returns to range, consider it false breakout         |
//+------------------------------------------------------------------+
#property strict

#include "Strategy_Base.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Global variables for daily tracking                               |
//+------------------------------------------------------------------+
datetime g_prevDayDate = 0;         // Previous day date
double   g_prevDayHigh = 0;         // Previous day high
double   g_prevDayLow = 0;          // Previous day low
bool     g_prevDayRangeSet = false; // Range calculated flag
bool     g_tradeTakenToday = false; // Already traded today flag
datetime g_todayDate = 0;           // Today's date

//+------------------------------------------------------------------+
//| Get today's date (midnight)                                       |
//+------------------------------------------------------------------+
datetime GetTodayDate()
{
   datetime now = TimeCurrent();
   return(now - (now % 86400));  // Remove time portion
}

//+------------------------------------------------------------------+
//| Calculate previous day high/low                                   |
//+------------------------------------------------------------------+
void CalculatePreviousDayRange()
{
   datetime today = GetTodayDate();

   // Reset daily flag if new day
   if(g_todayDate != today)
   {
      g_todayDate = today;
      g_tradeTakenToday = false;
      g_prevDayRangeSet = false;
   }

   // Already calculated for today
   if(g_prevDayRangeSet) return;

   // Calculate previous day (yesterday)
   datetime yesterday = today - 86400;  // 24 hours ago

   g_prevDayHigh = 0;
   g_prevDayLow = 999999;

   // Scan all H1 bars from yesterday
   for(int i = 1; i < Bars; i++)
   {
      datetime barTime = Time[i];
      datetime barDay = barTime - (barTime % 86400);

      if(barDay == yesterday)
      {
         if(High[i] > g_prevDayHigh) g_prevDayHigh = High[i];
         if(Low[i] < g_prevDayLow) g_prevDayLow = Low[i];
      }
      else if(barDay < yesterday)
      {
         break;  // Passed yesterday
      }
   }

   if(g_prevDayHigh > 0 && g_prevDayLow < 999999)
   {
      g_prevDayRangeSet = true;
      g_prevDayDate = yesterday;

      double rangePips = PriceToPips(g_prevDayHigh - g_prevDayLow);
      WriteLog("PREVDAY", "Range set: " + DoubleToString(g_prevDayHigh, 3) +
               " / " + DoubleToString(g_prevDayLow, 3) +
               " (" + DoubleToString(rangePips, 0) + " pips)");
   }
}

//+------------------------------------------------------------------+
//| Check for Previous Day Breakout entry signal                      |
//+------------------------------------------------------------------+
bool Strategy_AsianBreak_CheckEntry(TradeSignal &signal, const StrategyConfig &config)
{
   InitTradeSignal(signal);

   // Configuration
   double minRange = 40;   // Minimum 40 pips range
   double maxRange = 150;  // Maximum 150 pips range
   double buffer = 5;      // Breakout buffer pips

   // Calculate previous day range
   CalculatePreviousDayRange();

   // Check if range is set
   if(!g_prevDayRangeSet)
      return(false);

   // Already traded today
   if(g_tradeTakenToday)
      return(false);

   // Validate range size
   double rangePips = PriceToPips(g_prevDayHigh - g_prevDayLow);
   if(rangePips < minRange)
   {
      return(false);  // Range too tight
   }
   if(rangePips > maxRange)
   {
      return(false);  // Range too wide (news day?)
   }

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
   double prevHigh = High[1];
   double prevLow = Low[1];

   // Confirm bar[2] was inside or at range (clean breakout)
   double bar2Close = Close[2];
   bool bar2WasInsideOrAt = (bar2Close <= g_prevDayHigh + bufferPrice &&
                             bar2Close >= g_prevDayLow - bufferPrice);

   if(!bar2WasInsideOrAt)
      return(false);  // Not a clean breakout

   // Bullish breakout
   if(prevClose > g_prevDayHigh + bufferPrice)
   {
      signal.valid = true;
      signal.strategyId = STRATEGY_ASIAN_BREAK;
      signal.direction = OP_BUY;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = g_prevDayLow - atr * 0.3;  // Below previous day low
      signal.tpPrice = Ask + atr * config.tpAtrMultiplier;
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "PrevDayBreakUP(Range:" + DoubleToString(rangePips, 0) + "pips)";

      g_tradeTakenToday = true;
      WriteLog("SIGNAL", signal.reason);
      return(true);
   }

   // Bearish breakout
   if(prevClose < g_prevDayLow - bufferPrice)
   {
      signal.valid = true;
      signal.strategyId = STRATEGY_ASIAN_BREAK;
      signal.direction = OP_SELL;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = g_prevDayHigh + atr * 0.3;  // Above previous day high
      signal.tpPrice = Bid - atr * config.tpAtrMultiplier;
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "PrevDayBreakDOWN(Range:" + DoubleToString(rangePips, 0) + "pips)";

      g_tradeTakenToday = true;
      WriteLog("SIGNAL", signal.reason);
      return(true);
   }

   return(false);
}

//+------------------------------------------------------------------+
//| Get current Previous Day Breakout status for display              |
//+------------------------------------------------------------------+
string Strategy_AsianBreak_GetStatus(const StrategyConfig &config)
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   string out = "";
   out += "Strategy: Previous Day Breakout\n";

   if(g_prevDayRangeSet)
   {
      double rangePips = PriceToPips(g_prevDayHigh - g_prevDayLow);
      double currentPrice = Bid;

      string position = "";
      if(currentPrice > g_prevDayHigh)
         position = "ABOVE RANGE";
      else if(currentPrice < g_prevDayLow)
         position = "BELOW RANGE";
      else
         position = "INSIDE RANGE";

      out += "Prev Day High: " + DoubleToString(g_prevDayHigh, digits) + "\n";
      out += "Prev Day Low:  " + DoubleToString(g_prevDayLow, digits) + "\n";
      out += "Range: " + DoubleToString(rangePips, 0) + " pips\n";
      out += "Price: " + position + "\n";
      out += "Traded Today: " + (g_tradeTakenToday ? "YES" : "NO");
   }
   else
   {
      out += "Calculating previous day range...";
   }

   return(out);
}
//+------------------------------------------------------------------+
