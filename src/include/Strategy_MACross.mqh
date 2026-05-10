//+------------------------------------------------------------------+
//|                                              Strategy_MACross.mqh|
//|                                      fxEA Moving Average Cross   |
//|                                                                  |
//| Entry: Golden Cross (BUY) / Dead Cross (SELL)                    |
//| Filters: Trend MA, Time                                          |
//| SL/TP: ATR-based calculation                                     |
//+------------------------------------------------------------------+
#property strict

#include "Strategy_Base.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Check for MA Cross entry signal                                   |
//|                                                                   |
//| Entry Logic:                                                      |
//| - BUY:  Fast MA crosses above Slow MA (Golden Cross)             |
//| - SELL: Fast MA crosses below Slow MA (Dead Cross)               |
//|                                                                   |
//| Filters:                                                          |
//| - Trend Filter: Price above/below Trend MA                       |
//| - Time Filter: Trading hours restriction                         |
//+------------------------------------------------------------------+
bool Strategy_MACross_CheckEntry(TradeSignal &signal, const StrategyConfig &config)
{
   InitTradeSignal(signal);

   //=== Time Filter ===
   if(!PassesTimeFilter(config))
      return(false);

   //=== Calculate MAs ===
   // Use H1 timeframe for consistency
   int tf = PERIOD_H1;

   double fastMA_curr = iMA(Symbol(), tf, config.fastMAPeriod, 0, config.maMethod, PRICE_CLOSE, 1);
   double fastMA_prev = iMA(Symbol(), tf, config.fastMAPeriod, 0, config.maMethod, PRICE_CLOSE, 2);
   double slowMA_curr = iMA(Symbol(), tf, config.slowMAPeriod, 0, config.maMethod, PRICE_CLOSE, 1);
   double slowMA_prev = iMA(Symbol(), tf, config.slowMAPeriod, 0, config.maMethod, PRICE_CLOSE, 2);

   //=== Detect Cross ===
   bool goldenCross = (fastMA_prev <= slowMA_prev) && (fastMA_curr > slowMA_curr);
   bool deadCross   = (fastMA_prev >= slowMA_prev) && (fastMA_curr < slowMA_curr);

   // No cross, no signal
   if(!goldenCross && !deadCross)
      return(false);

   //=== Trend Filter ===
   if(config.useTrendFilter)
   {
      double trendMA = iMA(Symbol(), tf, config.trendMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
      double currentPrice = iClose(Symbol(), tf, 1);

      // BUY only above trend MA, SELL only below
      if(goldenCross && currentPrice < trendMA)
      {
         WriteLog("FILTER", "Golden Cross rejected: price below trend MA");
         return(false);
      }
      if(deadCross && currentPrice > trendMA)
      {
         WriteLog("FILTER", "Dead Cross rejected: price above trend MA");
         return(false);
      }
   }

   //=== Calculate ATR for SL/TP ===
   double atr = iATR(Symbol(), tf, config.atrPeriod, 1);
   if(atr <= 0)
   {
      WriteLog("ERROR", "ATR calculation failed");
      return(false);
   }

   //=== Generate Signal ===
   signal.valid = true;
   signal.strategyId = STRATEGY_MA_CROSS;
   signal.strength = 1.0;
   signal.atr = atr;

   if(goldenCross)
   {
      signal.direction = OP_BUY;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = Bid - atr * config.slAtrMultiplier;
      signal.tpPrice = Bid + atr * config.tpAtrMultiplier;
      signal.reason = "GoldenCross(EMA" + IntegerToString(config.fastMAPeriod) +
                      "/EMA" + IntegerToString(config.slowMAPeriod) + ")";
   }
   else // deadCross
   {
      signal.direction = OP_SELL;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = Ask + atr * config.slAtrMultiplier;
      signal.tpPrice = Ask - atr * config.tpAtrMultiplier;
      signal.reason = "DeadCross(EMA" + IntegerToString(config.fastMAPeriod) +
                      "/EMA" + IntegerToString(config.slowMAPeriod) + ")";
   }

   WriteLog("SIGNAL", signal.reason + " ATR=" + DoubleToString(atr * 10000, 1) + "pips");
   return(true);
}

//+------------------------------------------------------------------+
//| Get current MA Cross status for display                           |
//+------------------------------------------------------------------+
string Strategy_MACross_GetStatus(const StrategyConfig &config)
{
   int tf = PERIOD_H1;
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   double fastMA = iMA(Symbol(), tf, config.fastMAPeriod, 0, config.maMethod, PRICE_CLOSE, 1);
   double slowMA = iMA(Symbol(), tf, config.slowMAPeriod, 0, config.maMethod, PRICE_CLOSE, 1);
   double trendMA = iMA(Symbol(), tf, config.trendMAPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
   double atr = iATR(Symbol(), tf, config.atrPeriod, 1);

   string trend = "";
   if(config.useTrendFilter)
   {
      double price = iClose(Symbol(), tf, 1);
      trend = (price > trendMA) ? "UP" : "DOWN";
   }

   string maPos = (fastMA > slowMA) ? "Fast > Slow" : "Fast < Slow";

   string out = "";
   out += "Strategy: MA Cross (EMA" + IntegerToString(config.fastMAPeriod) +
          "/" + IntegerToString(config.slowMAPeriod) + ")\n";
   out += "FastMA: " + DoubleToString(fastMA, digits) + "\n";
   out += "SlowMA: " + DoubleToString(slowMA, digits) + "\n";
   out += "Position: " + maPos + "\n";
   if(config.useTrendFilter)
      out += "Trend: " + trend + " (MA" + IntegerToString(config.trendMAPeriod) + ")\n";
   out += "ATR: " + DoubleToString(PriceToPips(atr), 1) + " pips";

   return(out);
}

//+------------------------------------------------------------------+
//| Check if MA Cross is aligned (for additional confirmation)       |
//+------------------------------------------------------------------+
int Strategy_MACross_GetBias(const StrategyConfig &config)
{
   int tf = PERIOD_H1;

   double fastMA = iMA(Symbol(), tf, config.fastMAPeriod, 0, config.maMethod, PRICE_CLOSE, 1);
   double slowMA = iMA(Symbol(), tf, config.slowMAPeriod, 0, config.maMethod, PRICE_CLOSE, 1);

   if(fastMA > slowMA) return(OP_BUY);
   if(fastMA < slowMA) return(OP_SELL);
   return(-1);
}
//+------------------------------------------------------------------+
