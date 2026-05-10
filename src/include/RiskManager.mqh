//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                                     fxEA Risk Management Module  |
//+------------------------------------------------------------------+
#property strict

#include "Utils.mqh"

//=== RiskGuard Integration ===
#define GV_TRADING_BLOCKED "RiskGuard_TradingBlocked"

//+------------------------------------------------------------------+
//| Check if trading is blocked by RiskGuard                          |
//+------------------------------------------------------------------+
bool IsTradingBlocked(bool respectRiskGuard)
{
   if(!respectRiskGuard) return(false);
   if(!GlobalVariableCheck(GV_TRADING_BLOCKED)) return(false);
   return(GlobalVariableGet(GV_TRADING_BLOCKED) > 0.5);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk percentage and SL distance       |
//| Uses HardSL distance for conservative calculation                 |
//|                                                                   |
//| Parameters:                                                       |
//|   softSLPips      - Distance to SoftSL in pips                   |
//|   hardSLBufferPips- Additional buffer for HardSL                 |
//|   spreadBufferPips- Spread safety buffer                         |
//|   riskPercent     - Risk percentage of account balance           |
//|                                                                   |
//| Returns: Lot size (0 if calculation fails or under minimum)      |
//+------------------------------------------------------------------+
double CalculateLots(double softSLPips, int hardSLBufferPips, int spreadBufferPips, double riskPercent)
{
   double pipValue = GetPipValue();
   if(pipValue <= 0) return(0);

   double hardSLPips = softSLPips + hardSLBufferPips + spreadBufferPips;
   if(hardSLPips <= 0) return(0);

   double balance = AccountBalance();
   double riskAmount = balance * riskPercent / 100.0;
   double rawLots = riskAmount / (hardSLPips * pipValue);

   return(NormalizeLots(rawLots));
}

//+------------------------------------------------------------------+
//| Calculate lot size from SL price                                  |
//+------------------------------------------------------------------+
double CalculateLotsFromPrice(double entryPrice, double softSLPrice,
                               int hardSLBufferPips, int spreadBufferPips,
                               double riskPercent)
{
   double softSLPips = PriceToPips(MathAbs(entryPrice - softSLPrice));
   return(CalculateLots(softSLPips, hardSLBufferPips, spreadBufferPips, riskPercent));
}

//+------------------------------------------------------------------+
//| Calculate HardSL price from SoftSL                                |
//+------------------------------------------------------------------+
double CalculateHardSLPrice(double entryPrice, double softSLPrice,
                            int hardSLBufferPips, int spreadBufferPips,
                            int direction)
{
   double softSLDist = MathAbs(entryPrice - softSLPrice);
   double hardSLDist = softSLDist + PipsToPrice(hardSLBufferPips + spreadBufferPips);

   if(direction == OP_BUY)
      return(entryPrice - hardSLDist);
   else
      return(entryPrice + hardSLDist);
}

//+------------------------------------------------------------------+
//| Calculate initial risk amount in account currency                 |
//+------------------------------------------------------------------+
double CalculateInitialRisk(double lots, double softSLPips,
                            int hardSLBufferPips, int spreadBufferPips)
{
   double pipValue = GetPipValue();
   double hardSLPips = softSLPips + hardSLBufferPips + spreadBufferPips;
   return(lots * hardSLPips * pipValue);
}

//+------------------------------------------------------------------+
//| Check if risk percentage exceeds maximum allowed                  |
//+------------------------------------------------------------------+
bool IsRiskExceeded(double lots, double hardSLPips, double maxRiskPercent)
{
   double pipValue = GetPipValue();
   double balance = AccountBalance();
   if(balance <= 0) return(true);

   double riskAmount = lots * hardSLPips * pipValue;
   double riskPercent = riskAmount / balance * 100.0;

   return(riskPercent > maxRiskPercent);
}

//+------------------------------------------------------------------+
//| Get risk information string for display                           |
//+------------------------------------------------------------------+
string GetRiskInfo(double lots, double softSLPips, int hardSLBufferPips, int spreadBufferPips)
{
   double pipValue = GetPipValue();
   double hardSLPips = softSLPips + hardSLBufferPips + spreadBufferPips;
   double balance = AccountBalance();
   string ccy = AccountCurrency();

   double lossHard = lots * hardSLPips * pipValue;
   double lossSoft = lots * softSLPips * pipValue;
   double pctHard = (balance > 0) ? (lossHard / balance * 100.0) : 0;
   double pctSoft = (balance > 0) ? (lossSoft / balance * 100.0) : 0;

   string info = "";
   info += "HardSL: -" + FormatNumber(lossHard, 0) + " " + ccy + " (" + DoubleToString(pctHard, 2) + "%)\n";
   info += "SoftSL: -" + FormatNumber(lossSoft, 0) + " " + ccy + " (" + DoubleToString(pctSoft, 2) + "%)";

   return(info);
}
//+------------------------------------------------------------------+
