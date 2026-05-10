//+------------------------------------------------------------------+
//|                                                  Strategy_Grid.mqh |
//|                                           fxEA Grid Martingale    |
//|                                                                    |
//| Entry: Grid-based counter-trend entries (buy dips, sell rallies)  |
//| Logic:                                                             |
//|   1. First entry at current price                                  |
//|   2. Add positions every 25 pips against the trend (martingale)    |
//|   3. Close all positions when average profit reaches +30 pips      |
//|   4. Maximum 7 positions (safety limit)                            |
//|   5. Time stop: 48 hours from first entry                          |
//+------------------------------------------------------------------+
#property strict

#include "Strategy_Base.mqh"
#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Grid Strategy Configuration                                       |
//+------------------------------------------------------------------+
struct GridConfig
{
   int      gridSpacingPips;    // Distance between grid levels (pips)
   int      maxPositions;       // Maximum positions in grid
   double   targetProfitPips;   // Target profit for all positions (pips)
   int      gridDirection;      // 0=Buy grid, 1=Sell grid, 2=Auto (RSI)
   double   fixedLotSize;       // Fixed lot size for all positions
};

//+------------------------------------------------------------------+
//| Global grid state                                                 |
//+------------------------------------------------------------------+
datetime g_gridStartTime = 0;       // First entry time
double   g_lastGridLevel = 0;       // Last entry price level
int      g_gridPositionCount = 0;   // Current grid position count
int      g_activeGridDirection = -1; // -1=none, OP_BUY, OP_SELL

//+------------------------------------------------------------------+
//| Initialize Grid Config with defaults                              |
//+------------------------------------------------------------------+
void InitGridConfig(GridConfig &cfg)
{
   cfg.gridSpacingPips = 25;      // 25 pips between entries
   cfg.maxPositions = 7;           // Maximum 7 positions
   cfg.targetProfitPips = 30;      // Close all at +30 pips average
   cfg.gridDirection = 2;          // Auto-detect with RSI
   cfg.fixedLotSize = 0.01;        // Fixed 0.01 lot
}

//+------------------------------------------------------------------+
//| Determine grid direction using RSI                                |
//+------------------------------------------------------------------+
int DetermineGridDirection()
{
   double rsi = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 1);

   // RSI < 40: Oversold, start buy grid
   // RSI > 60: Overbought, start sell grid
   if(rsi < 40)
   {
      WriteLog("GRID", "RSI=" + DoubleToString(rsi, 1) + " - Starting BUY grid");
      return OP_BUY;
   }
   else if(rsi > 60)
   {
      WriteLog("GRID", "RSI=" + DoubleToString(rsi, 1) + " - Starting SELL grid");
      return OP_SELL;
   }

   return -1;  // No grid start
}

//+------------------------------------------------------------------+
//| Check if we need to add a new grid position                       |
//+------------------------------------------------------------------+
bool ShouldAddGridPosition(int gridDirection, double lastLevel, int spacingPips)
{
   if(g_gridPositionCount >= 7)
      return false;  // Max positions reached

   double currentPrice = (gridDirection == OP_BUY) ? Ask : Bid;
   double spacingPrice = spacingPips * GetPipSize();

   if(gridDirection == OP_BUY)
   {
      // Add buy position if price dropped 25 pips from last level
      if(currentPrice <= lastLevel - spacingPrice)
         return true;
   }
   else // OP_SELL
   {
      // Add sell position if price rose 25 pips from last level
      if(currentPrice >= lastLevel + spacingPrice)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Check for Grid entry signal                                       |
//+------------------------------------------------------------------+
bool Strategy_Grid_CheckEntry(TradeSignal &signal, const StrategyConfig &config)
{
   InitTradeSignal(signal);

   GridConfig gridCfg;
   InitGridConfig(gridCfg);

   // Check if we have an active grid
   if(g_activeGridDirection == -1)
   {
      // No active grid - check if we should start one
      int direction = DetermineGridDirection();

      if(direction == -1)
         return false;  // Conditions not met

      // Start new grid
      g_activeGridDirection = direction;
      g_gridStartTime = TimeCurrent();
      g_gridPositionCount = 0;
      g_lastGridLevel = (direction == OP_BUY) ? Ask : Bid;

      // Generate first entry signal
      double atr = iATR(Symbol(), PERIOD_H1, config.atrPeriod, 1);

      signal.valid = true;
      signal.strategyId = STRATEGY_GRID;
      signal.direction = direction;
      signal.entryPrice = 0;  // Market order
      signal.softSLPrice = 0; // No individual SL for grid
      signal.tpPrice = 0;     // No individual TP for grid
      signal.strength = 1.0;
      signal.atr = atr;
      signal.reason = "GridStart(" + (direction == OP_BUY ? "BUY" : "SELL") + ")";

      WriteLog("GRID", "Starting " + (direction == OP_BUY ? "BUY" : "SELL") +
               " grid at " + DoubleToString(g_lastGridLevel, 3));

      return true;
   }
   else
   {
      // Active grid - check if we need to add position
      if(ShouldAddGridPosition(g_activeGridDirection, g_lastGridLevel, gridCfg.gridSpacingPips))
      {
         double currentPrice = (g_activeGridDirection == OP_BUY) ? Ask : Bid;
         g_lastGridLevel = currentPrice;

         double atr = iATR(Symbol(), PERIOD_H1, config.atrPeriod, 1);

         signal.valid = true;
         signal.strategyId = STRATEGY_GRID;
         signal.direction = g_activeGridDirection;
         signal.entryPrice = 0;  // Market order
         signal.softSLPrice = 0; // No individual SL
         signal.tpPrice = 0;     // No individual TP
         signal.strength = 1.0;
         signal.atr = atr;
         signal.reason = "GridAdd#" + IntegerToString(g_gridPositionCount + 1);

         WriteLog("GRID", "Adding position #" + IntegerToString(g_gridPositionCount + 1) +
                  " at " + DoubleToString(currentPrice, 3));

         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Reset grid state (called after grid is closed)                    |
//+------------------------------------------------------------------+
void ResetGridState()
{
   g_gridStartTime = 0;
   g_lastGridLevel = 0;
   g_gridPositionCount = 0;
   g_activeGridDirection = -1;
   WriteLog("GRID", "Grid reset - ready for new grid");
}

//+------------------------------------------------------------------+
//| Update grid position count (called from main EA)                  |
//+------------------------------------------------------------------+
void UpdateGridPositionCount(int count)
{
   g_gridPositionCount = count;
}

//+------------------------------------------------------------------+
//| Get current Grid status for display                               |
//+------------------------------------------------------------------+
string Strategy_Grid_GetStatus(const StrategyConfig &config)
{
   string out = "";
   out += "Strategy: Grid Martingale (Counter-Trend)\n";

   if(g_activeGridDirection != -1)
   {
      string dirStr = (g_activeGridDirection == OP_BUY) ? "BUY" : "SELL";
      int elapsedHours = (int)((TimeCurrent() - g_gridStartTime) / 3600);

      out += "Active Grid: " + dirStr + "\n";
      out += "Positions: " + IntegerToString(g_gridPositionCount) + "/7\n";
      out += "Last Level: " + DoubleToString(g_lastGridLevel, 3) + "\n";
      out += "Elapsed: " + IntegerToString(elapsedHours) + " hours\n";
      out += "Target: +30 pips average profit";
   }
   else
   {
      double rsi = iRSI(Symbol(), PERIOD_H1, 14, PRICE_CLOSE, 1);
      out += "Status: Waiting for entry condition\n";
      out += "RSI: " + DoubleToString(rsi, 1) + "\n";
      out += "Entry: RSI<40 (buy grid) or RSI>60 (sell grid)";
   }

   return out;
}
//+------------------------------------------------------------------+
