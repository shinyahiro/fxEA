//+------------------------------------------------------------------+
//|                                              PositionManager.mqh |
//|                                    fxEA Position Management Module|
//|                                                                  |
//| Implements Z-style SL, Break-Even, Partial Close, Trailing Stop  |
//+------------------------------------------------------------------+
#property strict

#include "Utils.mqh"
#include "RiskManager.mqh"

//=== Position State ===
enum POSITION_STATE
{
   STATE_NONE,
   STATE_ACTIVE_PRE_BE,      // Active, before break-even
   STATE_ACTIVE_POST_BE,     // Active, after break-even moved
   STATE_ACTIVE_TRAILING,    // Active, trailing after partial close
   STATE_CLOSED              // Closed
};

//=== Managed Position Structure ===
struct ManagedPosition
{
   // === Core Fields ===
   int            ticket;              // Order ticket
   double         entryPrice;          // Entry price
   double         initialRisk;         // Initial risk amount (account currency)
   double         initialLots;         // Initial lot size
   double         currentLots;         // Current lot size (after partial close)
   double         softSLPrice;         // Soft SL price
   double         hardSLPrice;         // Hard SL price (broker)
   double         tpPrice;             // Take Profit price
   datetime       entryTime;           // Entry time
   datetime       softSLBreachStart;   // SoftSL breach start time (0=not breaching)
   bool           breakEvenMoved;      // Break-even moved flag
   bool           partialClosed;       // Partial close done flag
   int            direction;           // OP_BUY or OP_SELL
   POSITION_STATE state;               // Current state

   // === fxEA Extension Fields ===
   int            strategyId;          // Strategy that created this position
   string         entryReason;         // Entry reason for logging
   double         atrAtEntry;          // ATR at entry time
};

//+------------------------------------------------------------------+
//| Check if position is still alive                                  |
//+------------------------------------------------------------------+
bool IsPositionAlive(ManagedPosition &pos)
{
   if(!OrderSelect(pos.ticket, SELECT_BY_TICKET)) return(false);
   return(OrderCloseTime() == 0);
}

//+------------------------------------------------------------------+
//| Check Soft SL condition (time-based)                              |
//| Returns true if position should be closed                         |
//+------------------------------------------------------------------+
bool CheckSoftSL(ManagedPosition &pos, int softSLDurationMin)
{
   // SoftSL is only active before BE move
   if(pos.breakEvenMoved) return(false);

   double currentPrice = (pos.direction == OP_BUY) ? Bid : Ask;
   bool breaching = false;

   if(pos.direction == OP_BUY)
      breaching = (currentPrice <= pos.softSLPrice);
   else
      breaching = (currentPrice >= pos.softSLPrice);

   if(breaching)
   {
      if(pos.softSLBreachStart == 0)
         pos.softSLBreachStart = TimeCurrent();

      int elapsedMin = (int)(TimeCurrent() - pos.softSLBreachStart) / 60;
      if(elapsedMin >= softSLDurationMin)
         return(true);
   }
   else
   {
      // Reset if price moves back
      pos.softSLBreachStart = 0;
   }

   return(false);
}

//+------------------------------------------------------------------+
//| Check and execute Break-Even move                                 |
//| Returns true if BE was moved                                      |
//+------------------------------------------------------------------+
bool CheckBreakEven(ManagedPosition &pos, bool useBreakEven,
                    double breakEvenATRMult, int breakEvenPlusPips)
{
   if(!useBreakEven || pos.breakEvenMoved) return(false);

   double atr = iATR(Symbol(), PERIOD_CURRENT, 14, 0);
   double threshold = atr * breakEvenATRMult;
   double currentPrice = (pos.direction == OP_BUY) ? Bid : Ask;
   double profit = (pos.direction == OP_BUY)
      ? (currentPrice - pos.entryPrice)
      : (pos.entryPrice - currentPrice);

   if(profit >= threshold)
   {
      double pipSize = GetPipSize();
      double newSL = (pos.direction == OP_BUY)
         ? pos.entryPrice + breakEvenPlusPips * pipSize
         : pos.entryPrice - breakEvenPlusPips * pipSize;

      if(OrderSelect(pos.ticket, SELECT_BY_TICKET))
      {
         if(OrderModify(pos.ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0))
         {
            pos.hardSLPrice = newSL;
            pos.breakEvenMoved = true;
            pos.state = STATE_ACTIVE_POST_BE;
            WriteLog("BE_MOVED", "Ticket=" + IntegerToString(pos.ticket) +
                     " NewSL=" + DoubleToString(newSL, (int)MarketInfo(Symbol(), MODE_DIGITS)));
            return(true);
         }
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Check and execute Partial Close                                   |
//| Returns true if partial close was executed                        |
//+------------------------------------------------------------------+
bool CheckPartialClose(ManagedPosition &pos, bool usePartialClose,
                       double partialCloseRatio, double partialCloseAtR,
                       int maxSlippage)
{
   if(!usePartialClose || pos.partialClosed) return(false);

   double currentPrice = (pos.direction == OP_BUY) ? Bid : Ask;
   double profitPips = (pos.direction == OP_BUY)
      ? (currentPrice - pos.entryPrice) / GetPipSize()
      : (pos.entryPrice - currentPrice) / GetPipSize();

   double currentProfit = profitPips * GetPipValue() * pos.currentLots;

   if(currentProfit >= pos.initialRisk * partialCloseAtR)
   {
      double closeLots = NormalizeDouble(pos.initialLots * partialCloseRatio, 2);
      double minLot = MarketInfo(Symbol(), MODE_MINLOT);
      if(closeLots < minLot) closeLots = minLot;
      if(closeLots > pos.currentLots) closeLots = pos.currentLots;

      double closePrice = (pos.direction == OP_BUY) ? Bid : Ask;

      if(OrderSelect(pos.ticket, SELECT_BY_TICKET))
      {
         if(OrderClose(pos.ticket, closeLots, closePrice, maxSlippage))
         {
            pos.currentLots -= closeLots;
            pos.partialClosed = true;
            pos.state = STATE_ACTIVE_TRAILING;
            WriteLog("PARTIAL", "Ticket=" + IntegerToString(pos.ticket) +
                     " Closed=" + DoubleToString(closeLots, 2));
            return(true);
         }
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Update Trailing Stop                                              |
//| Returns true if SL was updated                                    |
//+------------------------------------------------------------------+
bool UpdateTrailing(ManagedPosition &pos, bool useTrailing,
                    int trailingLookback, int spreadBufferPips)
{
   if(!useTrailing || !pos.partialClosed) return(false);

   double pipSize = GetPipSize();
   double newSL;

   if(pos.direction == OP_BUY)
   {
      int lowestBar = iLowest(Symbol(), PERIOD_CURRENT, MODE_LOW, trailingLookback, 0);
      newSL = Low[lowestBar] - spreadBufferPips * pipSize;
      if(newSL <= pos.hardSLPrice) return(false);  // Only move SL in our favor
   }
   else
   {
      int highestBar = iHighest(Symbol(), PERIOD_CURRENT, MODE_HIGH, trailingLookback, 0);
      newSL = High[highestBar] + spreadBufferPips * pipSize;
      if(newSL >= pos.hardSLPrice) return(false);  // Only move SL in our favor
   }

   if(OrderSelect(pos.ticket, SELECT_BY_TICKET))
   {
      if(OrderModify(pos.ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0))
      {
         pos.hardSLPrice = newSL;
         WriteLog("TRAILING", "Ticket=" + IntegerToString(pos.ticket) +
                  " NewSL=" + DoubleToString(newSL, (int)MarketInfo(Symbol(), MODE_DIGITS)));
         return(true);
      }
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Check Time Stop condition                                         |
//| Returns true if position should be closed                         |
//+------------------------------------------------------------------+
bool CheckTimeStop(ManagedPosition &pos, bool useTimeStop, int timeStopHours)
{
   if(!useTimeStop) return(false);

   int elapsedHours = (int)(TimeCurrent() - pos.entryTime) / 3600;
   if(elapsedHours < timeStopHours) return(false);

   if(OrderSelect(pos.ticket, SELECT_BY_TICKET))
   {
      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit <= 0)
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Close position                                                    |
//+------------------------------------------------------------------+
bool ClosePosition(ManagedPosition &pos, string reason, int maxSlippage)
{
   if(!OrderSelect(pos.ticket, SELECT_BY_TICKET)) return(false);
   if(OrderCloseTime() > 0) { pos.state = STATE_CLOSED; return(true); }

   double closePrice = (pos.direction == OP_BUY) ? Bid : Ask;
   if(OrderClose(pos.ticket, pos.currentLots, closePrice, maxSlippage))
   {
      pos.state = STATE_CLOSED;
      WriteLog("CLOSE", "Ticket=" + IntegerToString(pos.ticket) + " Reason=" + reason);
      return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| Get position state as string                                      |
//+------------------------------------------------------------------+
string GetPositionStateString(POSITION_STATE state)
{
   switch(state)
   {
      case STATE_ACTIVE_PRE_BE:   return("BE");
      case STATE_ACTIVE_POST_BE:  return("BE");
      case STATE_ACTIVE_TRAILING: return("Trailing");
      case STATE_CLOSED:          return("Closed");
      default:                    return("None");
   }
}

//+------------------------------------------------------------------+
//| Get position info for display                                     |
//+------------------------------------------------------------------+
string GetPositionDisplay(ManagedPosition &pos, int softSLDurationMin)
{
   if(!OrderSelect(pos.ticket, SELECT_BY_TICKET)) return("");

   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   string ccy = AccountCurrency();
   string dirStr = (pos.direction == OP_BUY) ? "BUY" : "SELL";

   string stateStr = "";
   switch(pos.state)
   {
      case STATE_ACTIVE_PRE_BE:   stateStr = "BE"; break;
      case STATE_ACTIVE_POST_BE:  stateStr = "BE"; break;
      case STATE_ACTIVE_TRAILING: stateStr = "Trailing"; break;
      default: stateStr = ""; break;
   }

   double profit = OrderProfit() + OrderSwap() + OrderCommission();
   double currentPrice = (pos.direction == OP_BUY) ? Bid : Ask;

   string out = "";
   out += "  " + dirStr + " " + DoubleToString(pos.currentLots, 2) + " lots (" + stateStr + ")\n";
   out += "  Entry: " + DoubleToString(pos.entryPrice, digits) + "\n";
   out += "  Current: " + DoubleToString(currentPrice, digits) + "\n";
   out += "  P/L: " + (profit >= 0 ? "+" : "") + FormatNumber(profit, 0) + " " + ccy + "\n";

   out += "  SoftSL: " + DoubleToString(pos.softSLPrice, digits);
   if(pos.softSLBreachStart > 0)
   {
      int elapsed = (int)(TimeCurrent() - pos.softSLBreachStart) / 60;
      out += " (breach " + IntegerToString(elapsed) + "/" + IntegerToString(softSLDurationMin) + "min)";
   }
   out += "\n";
   out += "  HardSL: " + DoubleToString(pos.hardSLPrice, digits) + "\n";
   out += "  BE: " + (pos.breakEvenMoved ? "Done" : "Pending");
   out += " | Partial: " + (pos.partialClosed ? "Done" : "Pending") + "\n";

   return(out);
}
//+------------------------------------------------------------------+
