//+---------------------------------------------------------------------------+
//|                                                     Martingle RSI EURUSDc |
//|                                             Copyright 2024, Yohan Naftali |
//+---------------------------------------------------------------------------+
#property copyright "Copyright 2024, Yohan Naftali"
#property description "Martingle RSI EURUSDc"
#property link      "https://github.com/yohannaftali"
#property version   "240.501"

#define EA_MAGIC 240501

// Input

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input double baseVolume = 0.01;       // Base Volume Size (Lot)
input double multiplierVolume = 1.6;  // Size Multiplier
input int maximumStep = 40;           // Maximum Step

input double targetProfitPerLot = 0.002; // Target Profit USD/lot

input double rsiOversold = 15;      // RSI M1 Oversold Threshold than
input double deviationStep = 0.002;  // Minimum Price Deviation Step (%)
input double multiplierStep = 1.2;  // Step Multipiler

// Variables
int currentStep = 0;
double minimumAskPrice = 0;
double nextOpenVolume = 0;
double nextSumVolume = 0;
double takeProfitPrice = 0;
int historyLast = 0;
int positionLast = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   datetime current = TimeCurrent();
   datetime gmt = TimeGMT();
   datetime local = TimeLocal();

   Print("# ----------------------------------");
   Print("# Symbol Specification Info");
   Print("- Symbol: " + Symbol());
   Print("- Minimum Lot: " + DoubleToString(minLot, Digits()));
   Print("- Maximum Lot: " + DoubleToString(maxLot, Digits()));

   Print("# Time Info");
   Print("- Current Time: " + TimeToString(current));
   Print("- GMT Time: " + TimeToString(gmt));
   Print("- Local Time: " + TimeToString(local));

   Print("# Risk Management Info");
   Print("- Base Order Size: " + DoubleToString(baseVolume, 2) + " lot");
   Print("- Order Size Multiplier: " + DoubleToString(multiplierVolume, 2));
   Print("- Maximum Step: " + IntegerToString(maximumStep));
   Print("- Maximum Volume:" + DoubleToString(maximumVolume(), 2) + " lot");

   calculatePosition();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick()
{
   OnTrade();
   double ask = MarketInfo(Symbol(), MODE_ASK);

// Exit if current step over than safety order count
   if(currentStep >= maximumStep) {
      return;
   }
// If current step > 0
   if(currentStep > 0) {
      // Exit if current ask Price is greater than minimum ask Price
      if(ask > minimumAskPrice) {
         return;
      }
      Print("! Ask price below minimum ask price ");
   }

   if(currentStep == 0) {
      // Exit if RSI is greater than lower RSI Oversold threshold
      double currentRsi = iRSI(Symbol(), PERIOD_M1, 7, PRICE_CLOSE, 0);
      if(currentRsi > rsiOversold) {
         return;
      }
      Print("! Current RSI " + DoubleToStr(currentRsi, 2));
      Print("* RSI oversold detected");
   }

// Open New trade
   Print("! -------------------------------------");
   string msg = "! Buy step #" + IntegerToString(currentStep+1);
   double tp = NormalizeDouble(ask + (nextSumVolume * targetProfitPerLot), Digits());
   bool buy = OrderSend(Symbol(), OP_BUY, nextOpenVolume, Ask, 0.0, 0.0, tp, msg, EA_MAGIC, 0, clrGreen);
   if(!buy) {
      Print(GetLastError());
   }

// Calculate Position
   calculatePosition();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
{
   int pos = OrdersTotal();
   if(positionLast == pos) {
      return;
   }
   positionLast = pos;
   if(pos > 0) {
      return;
   }
   Print("* Take Profit Event");
   Print("# Recalculate Position");
   calculatePosition();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculatePosition()
{
   double sumVolume = 0;
   double sumProfit = 0;
   double sumVolumePrice = 0;

   double balance = AccountBalance();
   double equity = AccountEquity();
   double margin = AccountMargin();
   double freeMargin = AccountFreeMargin();
   Print("# Account Info");
   Print("- Balance: " + DoubleToString(balance, 2));
   Print("- Equity: " + DoubleToString(equity, 2));
   Print("- Margin: " + DoubleToString(margin, 2));
   Print("- Free Margin: " + DoubleToString(freeMargin, 2));

   Print("# Position Info");
   Print("- Total Position: " + IntegerToString(OrdersTotal()));

// Reset Current Step
   currentStep = 0;
   for(int i = 0; i < OrdersTotal(); i++) {
      if(OrderSelect(i, SELECT_BY_POS) == false) {
         continue;
      }
      int ticket = OrderTicket();
      double currentStopLoss = OrderStopLoss();
      double currentTakeProfit = OrderTakeProfit();
      double volume = OrderLots();
      sumVolume += volume;
      double price = OrderOpenPrice();
      double volumePrice = volume * price;
      sumVolumePrice += volumePrice;
      double currentProfit = OrderProfit();
      sumProfit += currentProfit;
      currentStep++;
   }

   double averagePrice = sumVolume > 0 ? sumVolumePrice/sumVolume : 0;

// Calculate Next open volume
   nextOpenVolume = currentStep < maximumStep ? NormalizeDouble(baseVolume + (baseVolume * currentStep * multiplierVolume), Digits()) : 0.0;
   nextSumVolume = currentStep < maximumStep ? sumVolume + nextOpenVolume : 0;

   Print("- Current Step: " + IntegerToString(currentStep));
   Print("- Sum Volume: " + DoubleToString(sumVolume, 2));
   Print("- Sum (Volume x Price): " + DoubleToString(sumVolumePrice, Digits()));
   Print("- Average Price: " + DoubleToString(averagePrice, Digits()));
   Print("- Sum Profit: " + DoubleToString(sumProfit, 2));
   Print("- Next Open Volume: " + DoubleToString(nextOpenVolume, 2) + " lot");
   Print("- Next Sum Volume: " + DoubleToString(nextSumVolume, 2) + " lot");

   if(sumVolume <= 0) {
      minimumAskPrice = 0.0;
      takeProfitPrice = 0.0;
      return;
   }

   double minimumDistancePercentage = (deviationStep + ((currentStep-1) * deviationStep * multiplierStep));
   double minimumDistancePrice = averagePrice * minimumDistancePercentage / 100;
   minimumAskPrice = NormalizeDouble(averagePrice - minimumDistancePrice, Digits());
   double expectedProfit = targetProfitPerLot * sumVolume;
   takeProfitPrice = NormalizeDouble(averagePrice + expectedProfit, Digits());

   Print("- Expected Profit: " + DoubleToString(expectedProfit, Digits()));
   Print("- Take Profit Price: " + DoubleToString(takeProfitPrice, Digits()));
   Print("- Minimum Distance to Open New Trade: " + DoubleToString(minimumDistancePercentage, Digits()) + "% = " + DoubleToString(minimumDistancePrice, 2));
   Print("- Minimum Ask Price to Open New Trade: " + DoubleToString(minimumAskPrice, Digits()));

   adjustTakeProfit();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void adjustTakeProfit()
{
   Print("# Adjust Take Profit");
   Print("- Current Take Profit: " + DoubleToString(takeProfitPrice, 2));

   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   if(takeProfitPrice < ask) {
      Print("! Warning: Current Take Profit < Ask: " + DoubleToString(ask, Digits()));
      takeProfitPrice = NormalizeDouble(ask + (nextSumVolume * targetProfitPerLot), Digits());
      Print("  - New Take Profit: " + DoubleToString(takeProfitPrice, Digits()));
   }

   for(int i = (OrdersTotal() - 1); i >= 0; i--) {
      if(OrderSelect(i, SELECT_BY_POS) == false) {
         continue;
      }
      int ticket = OrderTicket();
      double currentTakeProfit = OrderTakeProfit();
      if(currentTakeProfit == takeProfitPrice) {
         continue;
      }
      if(OrderModify(ticket, OrderOpenPrice(), 0.0, takeProfitPrice, 0, clrBlue)) {
         Print("> Ticket #" + IntegerToString(ticket));
         Print("  - New Take Profit Price: " + DoubleToString(takeProfitPrice));
      }
   }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double maximumVolume()
{
   double totalVolume = 0;
   for(int i = 0; i < maximumStep; i++) {
      double volume = baseVolume * (i * multiplierVolume);
      totalVolume += volume;
   }
   return totalVolume;
}
//+------------------------------------------------------------------+
