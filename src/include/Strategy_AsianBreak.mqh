//+------------------------------------------------------------------+
//|                                            Strategy_AsianBreak.mqh |
//|                                         fxEA Asian Range Breakout  |
//|                                                                    |
//| Entry: Price breaks Asian session range during London/NY session   |
//| Logic:                                                             |
//|   1. Calculate range during Asian session (default 0:00-8:00)      |
//|   2. Wait for breakout during London session (8:00-18:00)          |
//|   3. Entry on close above/below range                              |
//|   4. One trade per day maximum                                     |
//+------------------------------------------------------------------+
#property strict

#include "Strategy_Base.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Asian Breakout Configuration                                      |
//+------------------------------------------------------------------+
struct AsianBreakConfig
{
   int      asianStartHour;     // Asian session start (server time)
   int      asianEndHour;       // Asian session end (server time)
   int      entryEndHour;       // Entry window end (server time)
   double   minRangePips;       // Minimum range to trade
   double   maxRangePips;       // Maximum range to trade
   double   breakoutBuffer;     // Buffer pips beyond range for entry
};

//+------------------------------------------------------------------+
//| Global variables for daily tracking                               |
//+------------------------------------------------------------------+
datetime g_asianDate = 0;           // Current Asian session date
double   g_asianHigh = 0;           // Asian session high
double   g_asianLow = 0;            // Asian session low
bool     g_asianRangeSet = false;   // Range calculated flag
bool     g_asianTradeTaken = false; // Already traded today flag

//+------------------------------------------------------------------+
//| Initialize Asian Breakout Config with defaults                    |
//+------------------------------------------------------------------+
void InitAsianBreakConfig(AsianBreakConfig &cfg)
{
   cfg.asianStartHour = 0;      // Midnight server time
   cfg.asianEndHour = 8;        // 8 AM server time
   cfg.entryEndHour = 18;       // 6 PM server time (end entry window)
   cfg.minRangePips = 20;       // Minimum 20 pips range
   cfg.maxRangePips = 80;       // Maximum 80 pips range
   cfg.breakoutBuffer = 3;      // 3 pips buffer for breakout confirmation
}

//+------------------------------------------------------------------+
//| Get today's date (midnight)                                       |
//+------------------------------------------------------------------+
datetime GetTodayDate()
{
   datetime now = TimeCurrent();
   return(now - (now % 86400));  // Remove time portion
}

//+------------------------------------------------------------------+
//| Calculate Asian session range for today                           |
//+------------------------------------------------------------------+
void CalculateAsianRange(int asianStart, int asianEnd)
{
   datetime today = GetTodayDate();

   // Reset if new day
   if(g_asianDate != today)
   {
      g_asianDate = today;
      g_asianHigh = 0;
      g_asianLow = 999999;
      g_asianRangeSet = false;
      g_asianTradeTaken = false;
   }

   // Already set for today
   if(g_asianRangeSet) return;

   int currentHour = TimeHour(TimeCurrent());

   // Still in Asian session - don't set range yet
   if(currentHour >= asianStart && currentHour < asianEnd)
   {
      // Update running high/low
      for(int i = 0; i < Bars; i++)
      {
         datetime barTime = Time[i];
         if(TimeDay(barTime) != TimeDay(today)) break;

         int barHour = TimeHour(barTime);
         if(barHour >= asianStart && barHour < asianEnd)
         {
            if(High[i] > g_asianHigh) g_asianHigh = High[i];
            if(Low[i] < g_asianLow) g_asianLow = Low[i];
         }
      }
      return;
   }

   // Asian session ended - calculate final range
   if(currentHour >= asianEnd && !g_asianRangeSet)
   {
      g_asianHigh = 0;
      g_asianLow = 999999;

      for(int i = 0; i < Bars; i++)
      {
         datetime barTime = Time[i];
         if(TimeDay(barTime) != TimeDay(today)) break;

         int barHour = TimeHour(barTime);
         if(barHour >= asianStart && barHour < asianEnd)
         {
            if(High[i] > g_asianHigh) g_asianHigh = High[i];
            if(Low[i] < g_asianLow) g_asianLow = Low[i];
         }
      }

      if(g_asianHigh > 0 && g_asianLow < 999999)
      {
         g_asianRangeSet = true;
         WriteLog("ASIAN", "Range set: " + DoubleToString(g_asianHigh, 3) +
                  " / " + DoubleToString(g_asianLow, 3) +
                  " (" + DoubleToString(PriceToPips(g_asianHigh - g_asianLow), 0) + " pips)");
      }
   }
}

//+------------------------------------------------------------------+
//| Check for Asian Breakout entry signal                             |
//+------------------------------------------------------------------+
bool Strategy_AsianBreak_CheckEntry(TradeSignal &signal, const StrategyConfig &config)
{
   InitTradeSignal(signal);

   // Configuration
   int asianStart = 0;    // Midnight
   int asianEnd = 8;      // 8 AM
   int entryEnd = 18;     // 6 PM
   double minRange = 20;  // Minimum range pips
   double maxRange = 80;  // Maximum range pips
   double buffer = 3;     // Breakout buffer pips

   // Calculate Asian range
   CalculateAsianRange(asianStart, asianEnd);

   // Check if range is set
   if(!g_asianRangeSet)
      return(false);

   // Already traded today
   if(g_asianTradeTaken)
      return(false);

   // Check if within entry window
   int currentHour = TimeHour(TimeCurrent());
   if(currentHour < asianEnd || currentHour >= entryEnd)
      return(false);

   // Validate range size
   double rangePips = PriceToPips(g_asianHigh - g_asianLow);
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

   // Check breakout on last closed bar
   double prevClose = Close[1];
   double prevHigh = High[1];
   double prevLow = Low[1];

   // Confirm bar[2] was inside range (clean breakout)
   double bar2Close = Close[2];
   bool bar2WasInside = (bar2Close <= g_asianHigh && bar2Close >= g_asianLow);

   if(!bar2WasInside)
      return(false);  // Not a clean breakout

   // Bullish breakout
   if(prevClose > g_asianHigh + bufferPrice)
   {
      signal.valid = true;
      signal.strategyId = STRATEGY_ASIAN_BREAK;
      signal.direction = OP_BUY;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = g_asianLow - atr * 0.3;  // Below Asian low
      signal.tpPrice = Ask + atr * config.tpAtrMultiplier;
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "AsianBreakUP(Range:" + DoubleToString(rangePips, 0) + "pips)";

      g_asianTradeTaken = true;
      WriteLog("SIGNAL", signal.reason);
      return(true);
   }

   // Bearish breakout
   if(prevClose < g_asianLow - bufferPrice)
   {
      signal.valid = true;
      signal.strategyId = STRATEGY_ASIAN_BREAK;
      signal.direction = OP_SELL;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = g_asianHigh + atr * 0.3;  // Above Asian high
      signal.tpPrice = Bid - atr * config.tpAtrMultiplier;
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "AsianBreakDOWN(Range:" + DoubleToString(rangePips, 0) + "pips)";

      g_asianTradeTaken = true;
      WriteLog("SIGNAL", signal.reason);
      return(true);
   }

   return(false);
}

//+------------------------------------------------------------------+
//| Get current Asian Breakout status for display                     |
//+------------------------------------------------------------------+
string Strategy_AsianBreak_GetStatus(const StrategyConfig &config)
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   int currentHour = TimeHour(TimeCurrent());

   string sessionStatus = "";
   if(currentHour >= 0 && currentHour < 8)
      sessionStatus = "ASIAN SESSION (Building Range)";
   else if(currentHour >= 8 && currentHour < 18)
      sessionStatus = "ENTRY WINDOW";
   else
      sessionStatus = "CLOSED";

   string out = "";
   out += "Strategy: Asian Range Breakout\n";
   out += "Session: " + sessionStatus + "\n";

   if(g_asianRangeSet)
   {
      double rangePips = PriceToPips(g_asianHigh - g_asianLow);
      double currentPrice = Bid;

      string position = "";
      if(currentPrice > g_asianHigh)
         position = "ABOVE RANGE";
      else if(currentPrice < g_asianLow)
         position = "BELOW RANGE";
      else
         position = "INSIDE RANGE";

      out += "Asian High: " + DoubleToString(g_asianHigh, digits) + "\n";
      out += "Asian Low:  " + DoubleToString(g_asianLow, digits) + "\n";
      out += "Range: " + DoubleToString(rangePips, 0) + " pips\n";
      out += "Price: " + position + "\n";
      out += "Traded Today: " + (g_asianTradeTaken ? "YES" : "NO");
   }
   else
   {
      if(currentHour >= 0 && currentHour < 8)
      {
         double tempRange = PriceToPips(g_asianHigh - g_asianLow);
         out += "Building... H:" + DoubleToString(g_asianHigh, digits) +
                " L:" + DoubleToString(g_asianLow, digits) +
                " (" + DoubleToString(tempRange, 0) + " pips)";
      }
      else
      {
         out += "Range not set (waiting for Asian session)";
      }
   }

   return(out);
}
//+------------------------------------------------------------------+
