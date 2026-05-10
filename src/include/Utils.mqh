//+------------------------------------------------------------------+
//|                                                        Utils.mqh |
//|                                           fxEA Utility Functions |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| pipSize calculation                                               |
//| Returns the size of 1 pip in price units                         |
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   if(digits == 3 || digits == 5)
      return(Point * 10);
   return(Point);
}

//+------------------------------------------------------------------+
//| pip value calculation                                             |
//| Returns the value of 1 pip per 1 lot in account currency         |
//+------------------------------------------------------------------+
double GetPipValue()
{
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickSize <= 0) tickSize = Point;
   double pipSize = GetPipSize();
   return(tickValue * (pipSize / tickSize));
}

//+------------------------------------------------------------------+
//| Format number with thousand separators                            |
//+------------------------------------------------------------------+
string FormatNumber(double value, int decimals = 0)
{
   string s = DoubleToString(value, decimals);
   bool neg = (StringFind(s, "-") == 0);
   if(neg) s = StringSubstr(s, 1);
   int dotPos = StringFind(s, ".");
   string intPart = (dotPos < 0) ? s : StringSubstr(s, 0, dotPos);
   string decPart = (dotPos < 0) ? "" : StringSubstr(s, dotPos);
   string out = "";
   int len = StringLen(intPart);
   for(int i = 0; i < len; i++)
   {
      if(i > 0 && (len - i) % 3 == 0) out += ",";
      out += StringSubstr(intPart, i, 1);
   }
   out += decPart;
   if(neg) out = "-" + out;
   return(out);
}

//+------------------------------------------------------------------+
//| Log output with prefix                                            |
//+------------------------------------------------------------------+
void WriteLog(string event, string detail = "")
{
   Print("[fxEA] ", event, " ", detail);
}

//+------------------------------------------------------------------+
//| Convert pips to price distance                                    |
//+------------------------------------------------------------------+
double PipsToPrice(double pips)
{
   return(pips * GetPipSize());
}

//+------------------------------------------------------------------+
//| Convert price distance to pips                                    |
//+------------------------------------------------------------------+
double PriceToPips(double priceDistance)
{
   double pipSize = GetPipSize();
   if(pipSize <= 0) return(0);
   return(priceDistance / pipSize);
}

//+------------------------------------------------------------------+
//| Get current spread in pips                                        |
//+------------------------------------------------------------------+
double GetSpreadPips()
{
   return(PriceToPips(Ask - Bid));
}

//+------------------------------------------------------------------+
//| Normalize lot size according to broker requirements               |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0) lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = 0;
   if(lots > maxLot) lots = maxLot;

   return(lots);
}
//+------------------------------------------------------------------+
