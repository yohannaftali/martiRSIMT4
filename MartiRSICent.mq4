//+---------------------------------------------------------------------------+
//|                                                     Martingle RSI EURUSDc |
//|                                             Copyright 2024, Yohan Naftali |
//+---------------------------------------------------------------------------+
#property copyright   "Copyright 2024, Yohan Naftali"
#property description "Martingle RSI EURUSDc"
#property link        "https://github.com/yohannaftali"
#property version     "240.513"

#define EA_MAGIC 240513

// Input

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input double baseVolume = 0.01;       // Base Volume Size (Lot)
input double multiplierVolume = 1.2;  // Size Multiplier
input int maximumStep = 50;           // Maximum Step

input double targetProfitPerLot = 0.002; // Target Profit USD/lot

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
input double rsiOversold = 30;      // RSI(14) M1 Oversold Threshold
input double rsiOverbought = 70;    // RSI(14) M1 Overbought Threshold
input double deviationStep = 0.01;  // Minimum Price Deviation Step (%)
input double multiplierStep = 0.8;  // Step Multipiler

// Variables
double stepVolume = 0.0;
int digitVolume = 0;
int currentStepLong = 0;
int currentStepShort = 0;
double minimumAskPrice = 0;
double maximumBidPrice = 0;
double nextOpenVolumeLong = 0;
double nextOpenVolumeShort = 0;
double nextSumVolumeLong = 0;
double nextSumVolumeShort = 0;
double takeProfitPriceLong = 0;
double takeProfitPriceShort = 0;
int positionLastLong = 0;
int positionLastShort = 0;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit()
{
  Comment("Initializing");
  stepVolume = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
  digitVolume = getDigit(stepVolume);

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
  Print("- step Volume: " + DoubleToString(stepVolume, digitVolume));
  Print("- digit Volume: " + DoubleToString(digitVolume, 0));

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
  double bid = MarketInfo(Symbol(), MODE_BID);

  double currentRsi = iRSI(Symbol(), PERIOD_M1, 14, PRICE_CLOSE, 0);

  bool isLong = openLong(ask, currentRsi);
  bool isShort = openShort(bid, currentRsi);

  if(!(isLong || isShort)) {
    return;
  }
  Print("! -------------------------------------");
  if(isLong) {
    string msgLong = "! Buy step Long #" + IntegerToString(currentStepLong+1);
    double tpLong = NormalizeDouble(ask + (nextSumVolumeLong * targetProfitPerLot), Digits());
    bool buy = OrderSend(Symbol(), OP_BUY, nextOpenVolumeLong, Ask, 0.0, 0.0, tpLong, msgLong, EA_MAGIC, 0, clrGreen);
    if(!buy) {
      Print(GetLastError());
    }
  }

  if(isShort) {
    string msgShort = "! Buy step Short #" + IntegerToString(currentStepShort+1);
    double tpShort = NormalizeDouble(bid - (nextSumVolumeShort * targetProfitPerLot), Digits());
    bool sell = OrderSend(Symbol(), OP_SELL, nextOpenVolumeShort, Bid, 0.0, 0.0, tpShort, msgShort, EA_MAGIC, 0, clrGreen);
    if(!sell) {
      Print(GetLastError());
    }
  }
// Calculate Position
  calculatePosition();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool openLong(double ask, double currentRsi)
{
// Exit if current step over than safety order count
  if(currentStepLong >= maximumStep) {
    return false;
  }
// If current step > 0
  if(currentStepLong > 0) {
    // Exit if current ask Price is greater than minimum ask Price
    if(ask > minimumAskPrice) {
      return false;
    }
    Print("! Ask price below minimum ask price ");
  }

  if(currentStepLong == 0) {
    // Exit if RSI is greater than RSI Oversold threshold

    if(currentRsi > rsiOversold) {
      return false;
    }

    Print("! Current RSI " + DoubleToStr(currentRsi, 2));
    Print("* RSI oversold detected");

    double lastOpen = Open[1];
    double lastClose = Close[1];

    if(lastClose < lastOpen) {
      Print("! Abort open position: last bar is red");
      return false;
    }

    double lastHigh = High[1];
    double lastLow = Low[1];
    double lastHead = MathAbs(lastHigh - lastClose);
    double lastTail = MathAbs(lastOpen - lastLow);
    double lastBody = MathAbs(lastClose - lastOpen);
    double lastHeadOrTail = MathMax(lastHead, lastTail);

    // Check if last bar green head or tail and body
    if(lastHeadOrTail > lastBody) {
      Print("! Last bar head or tail longer than body");
      return false;
    }
  }

  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool openShort(double bid, double currentRsi)
{
// Exit if current step over than safety order count
  if(currentStepShort >= maximumStep) {
    return false;
  }
// If current step > 0
  if(currentStepShort > 0) {
    // Exit if current bid Price is lower than maximum bid Price
    if(bid < maximumBidPrice) {
      return false;
    }
    Print("! Bid price above maximum bid price ");
  }

  if(currentStepShort == 0) {
    // Exit if RSI is lower than RSI Overbought threshold

    if(currentRsi < rsiOverbought) {
      return false;
    }

    Print("! Current RSI " + DoubleToStr(currentRsi, 2));
    Print("* RSI overbought detected");

    double lastOpen = Open[1];
    double lastClose = Close[1];

    if(lastClose > lastOpen) {
      Print("! Abort open position: last bar is green");
      return false;
    }

    double lastHigh = High[1];
    double lastLow = Low[1];
    double lastHead = MathAbs(lastHigh - lastClose);
    double lastTail = MathAbs(lastOpen - lastLow);
    double lastBody = MathAbs(lastClose - lastOpen);
    double lastHeadOrTail = MathMax(lastHead, lastTail);

    // Check if last bar green head or tail and body
    if(lastHeadOrTail > lastBody) {
      Print("! Last bar head or tail longer than body");
      return false;
    }
  }

  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade()
{
  int posLong = 0;
  int posShort = 0;
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(OrderSelect(i, SELECT_BY_POS) == false) {
      continue;
    }
    int orderType = OrderType();
    if(orderType == OP_BUY) {
      posLong++;
      continue;
    }
    if(orderType == OP_SELL) {
      posShort ++;
      continue;
    }
  }
  if(positionLastLong == posLong && positionLastShort == posShort) {
    return;
  }

  positionLastLong = posLong;
  positionLastShort = posShort;

  if(positionLastLong > 0 && positionLastShort > 0) {
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
  Print("! Deinit");
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void showAccountInfo()
{
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
  Print("- Total Position Long: " + IntegerToString(positionLastLong));
  Print("- Total Position Short: " + IntegerToString(positionLastShort));
}
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculatePosition()
{
  showAccountInfo();

// Reset Current Step
  currentStepLong = 0;
  currentStepShort = 0;
  double sumVolumeLong = 0;
  double sumVolumeShort = 0;
  double sumVolumePriceLong = 0;
  double sumVolumePriceShort = 0;
  double sumProfitLong = 0;
  double sumProfitShort = 0;
  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(OrderSelect(i, SELECT_BY_POS) == false) {
      continue;
    }
    double volume = OrderLots();
    double price = OrderOpenPrice();
    double volumePrice = volume * price;
    double currentProfit = OrderProfit();
    int orderType = OrderType();
    if(orderType == OP_BUY) {
      sumVolumeLong += volume;
      sumVolumePriceLong += volumePrice;
      sumProfitLong += currentProfit;
      currentStepLong++;
    }
    if(orderType == OP_SELL) {
      sumVolumeShort += volume;
      sumVolumePriceShort += volumePrice;
      sumProfitShort += currentProfit;
      currentStepShort++;
    }
  }

  double averagePriceLong = sumVolumeLong > 0.0 ? sumVolumePriceLong/sumVolumeLong : 0.0;
  double averagePriceShort = sumVolumeShort > 0.0 ? sumVolumePriceShort/sumVolumeShort: 0.0;

// Calculate Next open volume
  nextOpenVolumeLong = currentStepLong < maximumStep ? NormalizeDouble(baseVolume + (baseVolume * currentStepLong * multiplierVolume), digitVolume) : 0.0;
  nextSumVolumeLong = currentStepLong < maximumStep ? sumVolumeLong + nextOpenVolumeLong : 0.0;

  nextOpenVolumeShort = currentStepShort < maximumStep ? NormalizeDouble(baseVolume + (baseVolume * currentStepShort * multiplierVolume), digitVolume) : 0.0;
  nextSumVolumeShort = currentStepShort < maximumStep ? sumVolumeShort + nextOpenVolumeShort : 0.0;

  Print("- Long");
  Print("  > Current Step: " + IntegerToString(currentStepLong));
  Print("  > Sum Volume: " + DoubleToString(sumVolumeLong, 2));
  Print("  > Sum (Volume x Price): " + DoubleToString(sumVolumePriceLong, Digits()));
  Print("  > Average Price: " + DoubleToString(averagePriceLong, Digits()));
  Print("  > Sum Profit: " + DoubleToString(sumProfitLong, 2));
  Print("  > Next Open Volume: " + DoubleToString(nextOpenVolumeLong, digitVolume) + " lot");
  Print("  > Next Sum Volume: " + DoubleToString(nextSumVolumeLong, digitVolume) + " lot");
  Print("- Short");
  Print("  > Current Step: " + IntegerToString(currentStepShort));
  Print("  > Sum Volume: " + DoubleToString(sumVolumeShort, 2));
  Print("  > Sum (Volume x Price): " + DoubleToString(sumVolumePriceShort, Digits()));
  Print("  > Average Price: " + DoubleToString(averagePriceShort, Digits()));
  Print("  > Sum Profit: " + DoubleToString(sumProfitShort, 2));
  Print("  > Next Open Volume: " + DoubleToString(nextOpenVolumeShort, digitVolume) + " lot");
  Print("  > Next Sum Volume: " + DoubleToString(nextSumVolumeShort, digitVolume) + " lot");

  if(sumVolumeLong <= 0 && sumVolumeShort <= 0) {
  Comment("No position");
    minimumAskPrice = 0.0;
    maximumBidPrice = 0.0;
    takeProfitPriceLong = 0.0;
    takeProfitPriceShort = 0.0;
    return;
  }

  double distancePercentageLong = (deviationStep + ((currentStepLong-1) * deviationStep * multiplierStep));
  double distancePriceLong = averagePriceLong * distancePercentageLong / 100;
  minimumAskPrice = NormalizeDouble(averagePriceLong - distancePriceLong, Digits());
  double expectedProfitLong = targetProfitPerLot * sumVolumeLong;
  takeProfitPriceLong = NormalizeDouble(averagePriceLong + expectedProfitLong, Digits());

  double distancePercentageShort = (deviationStep + ((currentStepShort-1) * deviationStep * multiplierStep));
  double distancePriceShort = averagePriceShort * distancePercentageShort / 100;
  maximumBidPrice = NormalizeDouble(averagePriceShort + distancePriceShort, Digits());
  double expectedProfitShort = targetProfitPerLot * sumVolumeShort;
  takeProfitPriceShort = NormalizeDouble(averagePriceShort - expectedProfitShort, Digits());

  Print("- Long");
  Print("  > Expected Profit: " + DoubleToString(expectedProfitLong, Digits()));
  Print("  > Take Profit Price: " + DoubleToString(takeProfitPriceLong, Digits()));
  Print("  > Distance to Open New Trade: " + DoubleToString(distancePercentageLong, Digits()) + "% = " + DoubleToString(distancePriceLong, 2));
  Print("  > Minimum Ask Price to Open New Trade: " + DoubleToString(minimumAskPrice, Digits()));

  Print("- Short");
  Print("  > Expected Profit: " + DoubleToString(expectedProfitShort, Digits()));
  Print("  > Take Profit Price: " + DoubleToString(takeProfitPriceShort, Digits()));
  Print("  > Distance to Open New Trade: " + DoubleToString(distancePercentageShort, Digits()) + "% = " + DoubleToString(distancePriceShort, 2));
  Print("  > Minimum Ask Price to Open New Trade: " + DoubleToString(minimumAskPrice, Digits()));
  adjustTakeProfit();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void adjustTakeProfit()
{
  Print("# Adjust Take Profit");
  Print("- Current Take Profit Long: " + DoubleToString(takeProfitPriceLong, 2));
  Print("- Current Take Profit Short: " + DoubleToString(takeProfitPriceShort, 2));

  double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
  double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
  if(takeProfitPriceLong < ask) {
    Print("! Warning: Current Take Profit Long < Ask: " + DoubleToString(ask, Digits()));
    takeProfitPriceLong = NormalizeDouble(ask + (nextSumVolumeLong * targetProfitPerLot), Digits());
    Print("  - New Take Profit Long: " + DoubleToString(takeProfitPriceLong, Digits()));
  }

  if(takeProfitPriceShort > bid) {
    Print("! Warning: Current Take Profit Short > Bid: " + DoubleToString(bid, Digits()));
    takeProfitPriceShort = NormalizeDouble(bid - (nextSumVolumeShort * targetProfitPerLot), Digits());
    Print("  - New Take Profit Short: " + DoubleToString(takeProfitPriceShort, Digits()));
  }

  for(int i = (OrdersTotal() - 1); i >= 0; i--) {
    if(OrderSelect(i, SELECT_BY_POS) == false) {
      continue;
    }
    int ticket = OrderTicket();
    double currentTakeProfit = OrderTakeProfit();
    int orderType = OrderType();
    if(orderType == OP_BUY) {
      if(currentTakeProfit == takeProfitPriceLong) {
        continue;
      }
      if(OrderModify(ticket, OrderOpenPrice(), 0.0, takeProfitPriceLong, 0, clrBlue)) {
        Print("> Ticket #" + IntegerToString(ticket));
        Print("  - New Take Profit Price Long: " + DoubleToString(takeProfitPriceLong));
      }
    }
    if(orderType == OP_SELL) {
      if(currentTakeProfit == takeProfitPriceShort) {
        continue;
      }
      if(OrderModify(ticket, OrderOpenPrice(), 0.0, takeProfitPriceShort, 0, clrBlue)) {
        Print("> Ticket #" + IntegerToString(ticket));
        Print("  - New Take Profit Price Short: " + DoubleToString(takeProfitPriceShort));
      }
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
int getDigit(double num)
{
  int d = 0;
  double p = 1;
  while (MathRound(num * p) / p != num) {
    p = MathPow(10, ++d);
  }
  return d;
}
//+------------------------------------------------------------------+
