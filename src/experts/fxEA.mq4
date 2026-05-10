//+------------------------------------------------------------------+
//|                                                        fxEA.mq4  |
//|                                                                  |
//|        Fully Automated FX Trading EA                             |
//|                                                                  |
//|        Based on autoEA's "Control How You Lose" philosophy       |
//|        with automated entry logic using MA Cross strategy        |
//|                                                                  |
//|        Features:                                                 |
//|        - Z-style SL (HardSL + SoftSL time-based)                |
//|        - Break-Even move (ATR-based)                            |
//|        - Partial Close (R-based)                                |
//|        - Trailing Stop (Swing-based)                            |
//|        - Time Stop                                               |
//|        - RiskGuard integration                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "fxEA"
#property version   "1.20"
#property strict

//=== Include Modules ===
#include "../include/Utils.mqh"
#include "../include/RiskManager.mqh"
#include "../include/PositionManager.mqh"
#include "../include/Strategy_Base.mqh"
#include "../include/Strategy_MACross.mqh"
#include "../include/Strategy_Breakout.mqh"
#include "../include/Strategy_AsianBreak.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+

//=== Strategy Selection ===
input int    SelectedStrategy = 4;   // Strategy (1=MA Cross, 2=Breakout, 4=Asian Break)

//=== MA Cross Strategy Settings ===
input int    FastMAPeriod     = 10;   // Fast MA Period
input int    SlowMAPeriod     = 30;   // Slow MA Period
input int    MAMethod         = 1;    // MA Type (0=SMA, 1=EMA)

//=== SL/TP Settings (ATR multiplier) ===
input double SLAtrMultiplier  = 2.0;   // SL Distance (ATR x)
input double TPAtrMultiplier  = 3.0;   // TP Distance (ATR x)
input int    AtrPeriod        = 14;    // ATR Period

//=== Money Management ===
input double RiskPercent      = 1.0;   // Risk Per Trade (%)
input double MaxRiskPercent   = 2.0;   // Max Risk Warning (%)
input int    HardSLBufferPips = 50;    // HardSL Buffer (pips)
input int    SpreadBufferPips = 3;     // Spread Buffer (pips)

//=== Soft SL ===
input int    SoftSLDurationMin = 30;   // SoftSL Duration (minutes)

//=== Position Management (inherited from autoEA) ===
input bool   UseBreakEven      = true;  // Use Break-Even
input double BreakEvenATRMult  = 1.5;   // BE Trigger (ATR x)
input int    BreakEvenPlusPips = 2;     // BE Buffer (pips)
input bool   UsePartialClose   = true;  // Use Partial Close
input double PartialCloseRatio = 0.5;   // Partial Close Ratio
input double PartialCloseAtR   = 1.0;   // Partial Close Trigger (R)
input bool   UseTrailing       = true;  // Use Trailing Stop
input int    TrailingLookback  = 20;    // Trailing Lookback Bars
input bool   UseTimeStop       = true;  // Use Time Stop
input int    TimeStopHours     = 4;     // Time Stop (hours)

//=== Filters ===
input bool   UseTimeFilter    = true;   // Use Time Filter
input int    TradeStartHour   = 2;      // Trade Start Hour (Server)
input int    TradeEndHour     = 18;     // Trade End Hour (Server)
input bool   UseTrendFilter   = true;   // Use Trend Filter
input int    TrendMAPeriod    = 100;    // Trend MA Period
input double MaxSpreadPips    = 5.0;    // Max Spread (pips)

//=== Position Limits ===
input int    MaxPositions     = 1;      // Max Positions

//=== Safety ===
input int    MagicNumber      = 20260510; // Magic Number
input bool   RespectRiskGuard = true;     // Respect RiskGuard
input int    MaxSlippage      = 5;        // Max Slippage

//=== Logging ===
input int    LogLevel         = 2;        // Log Level (1=Min, 2=Detail)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
ManagedPosition g_positions[];
StrategyConfig  g_config;
bool            g_initialized = false;
datetime        g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Initialize strategy configuration from inputs                     |
//+------------------------------------------------------------------+
void InitConfig()
{
   g_config.fastMAPeriod = FastMAPeriod;
   g_config.slowMAPeriod = SlowMAPeriod;
   g_config.maMethod = (ENUM_MA_METHOD)MAMethod;

   g_config.slAtrMultiplier = SLAtrMultiplier;
   g_config.tpAtrMultiplier = TPAtrMultiplier;
   g_config.atrPeriod = AtrPeriod;

   g_config.useTimeFilter = UseTimeFilter;
   g_config.startHour = TradeStartHour;
   g_config.endHour = TradeEndHour;
   g_config.useTrendFilter = UseTrendFilter;
   g_config.trendMAPeriod = TrendMAPeriod;
   g_config.maxSpreadPips = MaxSpreadPips;

   g_config.maxPositions = MaxPositions;
}

//+------------------------------------------------------------------+
//| Check strategy signal based on selected strategy                  |
//+------------------------------------------------------------------+
bool CheckStrategySignal(TradeSignal &signal)
{
   switch(SelectedStrategy)
   {
      case STRATEGY_MA_CROSS:
         return Strategy_MACross_CheckEntry(signal, g_config);

      case STRATEGY_BREAKOUT:
         return Strategy_Breakout_CheckEntry(signal, g_config);

      case STRATEGY_ASIAN_BREAK:
         return Strategy_AsianBreak_CheckEntry(signal, g_config);

      default:
         return false;
   }
}

//+------------------------------------------------------------------+
//| Check if we can open a new position                               |
//+------------------------------------------------------------------+
bool CanOpenNewPosition()
{
   // RiskGuard check
   if(IsTradingBlocked(RespectRiskGuard))
   {
      if(LogLevel >= 2) WriteLog("BLOCKED", "Trading blocked by RiskGuard");
      return false;
   }

   // Position limit check
   if(ArraySize(g_positions) >= MaxPositions)
   {
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Execute entry based on signal                                     |
//+------------------------------------------------------------------+
bool ExecuteEntry(TradeSignal &signal)
{
   if(!signal.valid) return false;

   // Calculate lots
   double softSLPips = PriceToPips(MathAbs(signal.softSLPrice -
      (signal.direction == OP_BUY ? Bid : Ask)));
   double lots = CalculateLots(softSLPips, HardSLBufferPips, SpreadBufferPips, RiskPercent);

   if(lots <= 0)
   {
      WriteLog("ERROR", "Lot calculation failed");
      return false;
   }

   // Calculate HardSL
   double entryPrice = (signal.direction == OP_BUY) ? Ask : Bid;
   double hardSLPrice = CalculateHardSLPrice(entryPrice, signal.softSLPrice,
                                              HardSLBufferPips, SpreadBufferPips,
                                              signal.direction);

   // Send order
   int ticket = OrderSend(
      Symbol(),
      signal.direction,
      lots,
      entryPrice,
      MaxSlippage,
      hardSLPrice,
      signal.tpPrice,
      "fxEA:" + signal.reason,
      MagicNumber,
      0,
      (signal.direction == OP_BUY) ? clrBlue : clrRed
   );

   if(ticket < 0)
   {
      int err = GetLastError();
      WriteLog("ERROR", "Order failed #" + IntegerToString(err));
      return false;
   }

   // Register position
   int idx = ArraySize(g_positions);
   ArrayResize(g_positions, idx + 1);

   g_positions[idx].ticket = ticket;
   g_positions[idx].entryPrice = entryPrice;
   g_positions[idx].initialRisk = CalculateInitialRisk(lots, softSLPips,
                                                        HardSLBufferPips, SpreadBufferPips);
   g_positions[idx].initialLots = lots;
   g_positions[idx].currentLots = lots;
   g_positions[idx].softSLPrice = signal.softSLPrice;
   g_positions[idx].hardSLPrice = hardSLPrice;
   g_positions[idx].tpPrice = signal.tpPrice;
   g_positions[idx].entryTime = TimeCurrent();
   g_positions[idx].softSLBreachStart = 0;
   g_positions[idx].breakEvenMoved = false;
   g_positions[idx].partialClosed = false;
   g_positions[idx].direction = signal.direction;
   g_positions[idx].state = STATE_ACTIVE_PRE_BE;
   g_positions[idx].strategyId = signal.strategyId;
   g_positions[idx].entryReason = signal.reason;
   g_positions[idx].atrAtEntry = signal.atr;

   WriteLog("ENTRY", "Ticket=" + IntegerToString(ticket) +
            " " + (signal.direction == OP_BUY ? "BUY" : "SELL") +
            " Lots=" + DoubleToString(lots, 2) +
            " " + signal.reason);

   return true;
}

//+------------------------------------------------------------------+
//| Remove position from array                                        |
//+------------------------------------------------------------------+
void RemovePosition(int index)
{
   int size = ArraySize(g_positions);
   for(int j = index; j < size - 1; j++)
      g_positions[j] = g_positions[j + 1];
   ArrayResize(g_positions, size - 1);
}

//+------------------------------------------------------------------+
//| Load existing positions on init                                   |
//+------------------------------------------------------------------+
void LoadExistingPositions()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderMagicNumber() == MagicNumber && OrderSymbol() == Symbol())
         {
            int idx = ArraySize(g_positions);
            ArrayResize(g_positions, idx + 1);

            g_positions[idx].ticket = OrderTicket();
            g_positions[idx].entryPrice = OrderOpenPrice();
            g_positions[idx].currentLots = OrderLots();
            g_positions[idx].initialLots = OrderLots();
            g_positions[idx].hardSLPrice = OrderStopLoss();
            g_positions[idx].tpPrice = OrderTakeProfit();
            g_positions[idx].entryTime = OrderOpenTime();
            g_positions[idx].direction = OrderType();

            // Estimate softSL from hardSL
            double pipSize = GetPipSize();
            double offset = (HardSLBufferPips + SpreadBufferPips) * pipSize;
            if(OrderType() == OP_BUY)
               g_positions[idx].softSLPrice = OrderStopLoss() + offset;
            else
               g_positions[idx].softSLPrice = OrderStopLoss() - offset;

            g_positions[idx].softSLBreachStart = 0;
            g_positions[idx].breakEvenMoved = false;
            g_positions[idx].partialClosed = false;
            g_positions[idx].state = STATE_ACTIVE_PRE_BE;
            g_positions[idx].strategyId = SelectedStrategy;
            g_positions[idx].entryReason = "Loaded";

            // Estimate initial risk
            double hardSLPips = PriceToPips(MathAbs(g_positions[idx].entryPrice - g_positions[idx].hardSLPrice));
            g_positions[idx].initialRisk = g_positions[idx].currentLots * hardSLPips * GetPipValue();
            g_positions[idx].atrAtEntry = iATR(Symbol(), PERIOD_H1, AtrPeriod, 1);

            WriteLog("INIT", "Loaded position #" + IntegerToString(OrderTicket()));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get display string                                                |
//+------------------------------------------------------------------+
string GetStatusDisplay()
{
   string out = "";
   out += "========================================\n";
   out += "  fxEA v1.20 - " + GetStrategyName(SelectedStrategy) + "\n";
   out += "========================================\n\n";

   // Trading status
   if(IsTradingBlocked(RespectRiskGuard))
      out += "  STATUS: BLOCKED (RiskGuard)\n\n";
   else if(ArraySize(g_positions) >= MaxPositions)
      out += "  STATUS: MAX POSITIONS REACHED\n\n";
   else if(!PassesTimeFilter(g_config))
      out += "  STATUS: OUTSIDE TRADING HOURS\n\n";
   else
      out += "  STATUS: WAITING FOR SIGNAL\n\n";

   // Strategy info
   if(SelectedStrategy == STRATEGY_MA_CROSS)
      out += Strategy_MACross_GetStatus(g_config) + "\n\n";
   else if(SelectedStrategy == STRATEGY_BREAKOUT)
      out += Strategy_Breakout_GetStatus(g_config) + "\n\n";
   else if(SelectedStrategy == STRATEGY_ASIAN_BREAK)
      out += Strategy_AsianBreak_GetStatus(g_config) + "\n\n";

   // Position info
   if(ArraySize(g_positions) > 0)
   {
      out += "----------------------------------------\n";
      out += "  ACTIVE POSITIONS: " + IntegerToString(ArraySize(g_positions)) + "\n";
      out += "----------------------------------------\n";
      for(int i = 0; i < ArraySize(g_positions); i++)
      {
         out += GetPositionDisplay(g_positions[i], SoftSLDurationMin);
      }
   }

   out += "\n========================================";
   return out;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize config
   InitConfig();

   // Load existing positions
   ArrayResize(g_positions, 0);
   LoadExistingPositions();

   g_initialized = true;
   g_lastBarTime = Time[0];

   WriteLog("INIT", "fxEA initialized. Strategy=" + GetStrategyName(SelectedStrategy) +
            " Positions=" + IntegerToString(ArraySize(g_positions)));

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   WriteLog("DEINIT", "Reason=" + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;

   //=== 1. New Bar Detection ===
   bool isNewBar = (Time[0] != g_lastBarTime);
   if(isNewBar) g_lastBarTime = Time[0];

   //=== 2. Position Management (every tick) ===
   for(int i = ArraySize(g_positions) - 1; i >= 0; i--)
   {
      // Check if position still exists
      if(!IsPositionAlive(g_positions[i]))
      {
         g_positions[i].state = STATE_CLOSED;
         WriteLog("CLOSED_EXT", "External close detected #" + IntegerToString(g_positions[i].ticket));
         RemovePosition(i);
         continue;
      }

      // Soft SL check (before BE only)
      if(!g_positions[i].breakEvenMoved && CheckSoftSL(g_positions[i], SoftSLDurationMin))
      {
         ClosePosition(g_positions[i], "SoftSL", MaxSlippage);
         RemovePosition(i);
         continue;
      }

      // Break-Even
      CheckBreakEven(g_positions[i], UseBreakEven, BreakEvenATRMult, BreakEvenPlusPips);

      // Partial Close
      CheckPartialClose(g_positions[i], UsePartialClose, PartialCloseRatio,
                        PartialCloseAtR, MaxSlippage);

      // Trailing Stop
      if(g_positions[i].partialClosed)
         UpdateTrailing(g_positions[i], UseTrailing, TrailingLookback, SpreadBufferPips);

      // Time Stop
      if(CheckTimeStop(g_positions[i], UseTimeStop, TimeStopHours))
      {
         ClosePosition(g_positions[i], "TimeStop", MaxSlippage);
         RemovePosition(i);
         continue;
      }
   }

   //=== 3. New Entry Check (new bar only) ===
   if(isNewBar && CanOpenNewPosition())
   {
      TradeSignal signal;
      if(CheckStrategySignal(signal))
      {
         if(ValidateSignal(signal, g_config))
         {
            ExecuteEntry(signal);
         }
      }
   }

   //=== 4. Display Update ===
   Comment(GetStatusDisplay());
}
//+------------------------------------------------------------------+
