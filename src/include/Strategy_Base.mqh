//+------------------------------------------------------------------+
//|                                                 Strategy_Base.mqh|
//|                                    fxEA Strategy Interface Module |
//|                                                                  |
//| Defines base structures and interfaces for trading strategies    |
//+------------------------------------------------------------------+
#property strict

//=== Strategy IDs ===
#define STRATEGY_NONE        0
#define STRATEGY_MA_CROSS    1
#define STRATEGY_BREAKOUT    2
#define STRATEGY_RSI_MEAN    3
#define STRATEGY_ASIAN_BREAK 4

//=== Trade Signal Structure ===
// Output from strategy indicating an entry opportunity
struct TradeSignal
{
   bool           valid;          // Signal validity flag
   int            direction;      // OP_BUY or OP_SELL
   double         entryPrice;     // Recommended entry price (0 for market order)
   double         softSLPrice;    // Soft SL price
   double         tpPrice;        // Take Profit price
   string         reason;         // Signal reason for logging
   int            strategyId;     // Strategy ID that generated this signal
   double         strength;       // Signal strength (0.0-1.0, for future use)
   double         atr;            // ATR value at signal generation
};

//=== Strategy Configuration ===
// Shared configuration for all strategies
struct StrategyConfig
{
   // === MA Cross Strategy Parameters ===
   int            fastMAPeriod;     // Fast MA period
   int            slowMAPeriod;     // Slow MA period
   ENUM_MA_METHOD maMethod;         // MA calculation method

   // === SL/TP Settings ===
   double         slAtrMultiplier;  // SL = ATR x this value
   double         tpAtrMultiplier;  // TP = ATR x this value
   int            atrPeriod;        // ATR calculation period

   // === Filters ===
   bool           useTimeFilter;    // Use time filter
   int            startHour;        // Trading start hour (server time)
   int            endHour;          // Trading end hour (server time)
   bool           useTrendFilter;   // Use trend filter
   int            trendMAPeriod;    // Trend MA period
   double         maxSpreadPips;    // Maximum allowed spread

   // === Position Limits ===
   int            maxPositions;     // Maximum concurrent positions
};

//+------------------------------------------------------------------+
//| Initialize TradeSignal with default values                        |
//+------------------------------------------------------------------+
void InitTradeSignal(TradeSignal &signal)
{
   signal.valid = false;
   signal.direction = -1;
   signal.entryPrice = 0;
   signal.softSLPrice = 0;
   signal.tpPrice = 0;
   signal.reason = "";
   signal.strategyId = STRATEGY_NONE;
   signal.strength = 0;
   signal.atr = 0;
}

//+------------------------------------------------------------------+
//| Initialize StrategyConfig with default values                     |
//+------------------------------------------------------------------+
void InitStrategyConfig(StrategyConfig &config)
{
   // MA Cross defaults
   config.fastMAPeriod = 10;
   config.slowMAPeriod = 30;
   config.maMethod = MODE_EMA;

   // SL/TP defaults
   config.slAtrMultiplier = 2.0;
   config.tpAtrMultiplier = 3.0;
   config.atrPeriod = 14;

   // Filter defaults
   config.useTimeFilter = true;
   config.startHour = 2;
   config.endHour = 18;
   config.useTrendFilter = true;
   config.trendMAPeriod = 100;
   config.maxSpreadPips = 5.0;

   // Position limits
   config.maxPositions = 1;
}

//+------------------------------------------------------------------+
//| Get strategy name by ID                                           |
//+------------------------------------------------------------------+
string GetStrategyName(int strategyId)
{
   switch(strategyId)
   {
      case STRATEGY_MA_CROSS:    return("MA Cross");
      case STRATEGY_BREAKOUT:    return("Breakout");
      case STRATEGY_RSI_MEAN:    return("RSI Mean Reversion");
      case STRATEGY_ASIAN_BREAK: return("True Range Breakout");
      default: return("Unknown");
   }
}

//+------------------------------------------------------------------+
//| Validate trade signal                                             |
//+------------------------------------------------------------------+
bool ValidateSignal(const TradeSignal &signal, const StrategyConfig &config)
{
   if(!signal.valid) return(false);

   // Check spread
   double spreadPips = (Ask - Bid) / GetPipSize();
   if(spreadPips > config.maxSpreadPips)
   {
      WriteLog("FILTER", "Spread too high: " + DoubleToString(spreadPips, 1) + " pips");
      return(false);
   }

   // Check SL distance (minimum 5 pips)
   double slDistPips = MathAbs(signal.softSLPrice - (signal.direction == OP_BUY ? Bid : Ask)) / GetPipSize();
   if(slDistPips < 5)
   {
      WriteLog("FILTER", "SL too close: " + DoubleToString(slDistPips, 1) + " pips");
      return(false);
   }

   // Check TP distance (minimum 5 pips)
   double tpDistPips = MathAbs(signal.tpPrice - (signal.direction == OP_BUY ? Ask : Bid)) / GetPipSize();
   if(tpDistPips < 5)
   {
      WriteLog("FILTER", "TP too close: " + DoubleToString(tpDistPips, 1) + " pips");
      return(false);
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Check time filter                                                 |
//+------------------------------------------------------------------+
bool PassesTimeFilter(const StrategyConfig &config)
{
   if(!config.useTimeFilter) return(true);

   int hour = TimeHour(TimeCurrent());

   if(config.startHour < config.endHour)
   {
      // Normal case: e.g., 2-18
      return(hour >= config.startHour && hour < config.endHour);
   }
   else
   {
      // Overnight case: e.g., 18-6 (next day)
      return(hour >= config.startHour || hour < config.endHour);
   }
}

//+------------------------------------------------------------------+
//| Signal info for display                                           |
//+------------------------------------------------------------------+
string GetSignalDisplay(const TradeSignal &signal)
{
   if(!signal.valid) return("No signal");

   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   string dirStr = (signal.direction == OP_BUY) ? "BUY" : "SELL";

   string out = "";
   out += "Signal: " + dirStr + " [" + GetStrategyName(signal.strategyId) + "]\n";
   out += "Entry: " + (signal.entryPrice > 0 ? DoubleToString(signal.entryPrice, digits) : "Market") + "\n";
   out += "SL: " + DoubleToString(signal.softSLPrice, digits) + "\n";
   out += "TP: " + DoubleToString(signal.tpPrice, digits) + "\n";
   out += "Reason: " + signal.reason;

   return(out);
}
//+------------------------------------------------------------------+
