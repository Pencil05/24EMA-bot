//+------------------------------------------------------------------+
//|                                           [TwoByFour(24)EMA Bot] | 
//|                 Created by Poowadech Homhuan                     | 
//|                                                                  | 
//+------------------------------------------------------------------+ \

//+------------------------------------------------------------------+
//Settings
//set Deposit = 3000
//leverage = 1:200
//Symbol: EUR/USD , M30
//Medelling: Every tick
//Date Lastyear
//+------------------------------------------------------------------+

input double Lotsize = 0.3; // Lot size for both buy and sell 
input double DistancePips = 60; // Distance for opening additional orders 
input double TP_Pips = 30; // Take Profit in pips 
input int MagicNumber = 123456; // Magic number for orders 
double PointPips; // Point value in pips 
double lastOrderPrice = 0; // Last order price for alternating orders 
int lastOrderType = 0; // Last order type (1 for BUY, 2 for SELL) 
double AccumulatedProfit = 0; // Accumulated savings of profits 
double ProfitThreshold = 4.0; // Profit threshold for saving 
double SavedProfit = 0; // Track total saved profit 

//+------------------------------------------------------------------+ 
//| Expert initialization function                                   | 
//+------------------------------------------------------------------+ 
int OnInit() 
{ 
    double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT); 
    PointPips = Point * 10; 
    Print("Initialization complete. Point value: ", Point, ", PointPips: ", PointPips); 
    return(INIT_SUCCEEDED); 
} 

//+------------------------------------------------------------------+ 
//| Expert tick function                                             | 
//+------------------------------------------------------------------+ 
void OnTick() 
{ 
    double AskPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK); 
    double BidPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID); 
    
    Print("OnTick called. AskPrice: ", AskPrice, ", BidPrice: ", BidPrice); 

    // Determine the trend using EMA 
    double ema200 = iMA(NULL, PERIOD_M30, 200, 0, MODE_EMA, PRICE_CLOSE); 
    double ema50 = iMA(NULL, PERIOD_M30, 50, 0, MODE_EMA, PRICE_CLOSE); 
    double ema9 = iMA(NULL, PERIOD_M30, 9, 0, MODE_EMA, PRICE_CLOSE); 

    // Check if no positions are open 
    if (PositionsTotal() == 0) 
    { 
        // Decide whether to buy or sell based on EMAs 
        if (ema50 > ema9 && BidPrice > ema200) // Buy condition 
        { 
            Print("Conditions met for BUY order."); 
            PlaceTrade(ORDER_TYPE_BUY, Lotsize, AskPrice, TP_Pips); 
            lastOrderType = 1; 
            lastOrderPrice = AskPrice; 
        } 
        else if (ema50 < ema9 && BidPrice < ema200) // Sell condition 
        { 
            Print("Conditions met for SELL order."); 
            PlaceTrade(ORDER_TYPE_SELL, Lotsize, BidPrice, TP_Pips); 
            lastOrderType = 2; 
            lastOrderPrice = BidPrice; 
        } 
    } 

    // Manage existing trades and alternate orders 
    ManageTrades(BidPrice, AskPrice); 
} 

//+------------------------------------------------------------------+ 
//| Place a market trade                                             | 
//+------------------------------------------------------------------+ 
void PlaceTrade(int type, double lots, double price, double tp_pips) 
{ 
    double tp = (type == ORDER_TYPE_BUY) ? price + tp_pips * PointPips : price - tp_pips * PointPips; 

    MqlTradeRequest request; 
    MqlTradeResult result; 
    ZeroMemory(request); 
    ZeroMemory(result); 

    request.action = TRADE_ACTION_DEAL; 
    request.symbol = Symbol(); 
    request.volume = lots; 
    request.type = ENUM_ORDER_TYPE(type); 
    request.price = price; 
    request.tp = tp; 
    request.deviation = 10; 
    request.magic = MagicNumber; 

    Print("Attempting to open order. Type: ", type, ", Lot: ", lots, ", Price: ", price, ", TP: ", tp); 

    if (!OrderSend(request, result)) 
    { 
        Print("Error opening order: ", result.retcode); 
    } 
    else 
    { 
        Print("Order opened successfully. Ticket: ", result.order); 
    } 
} 

//+------------------------------------------------------------------+ 
//| Manage existing trades and scenarios                             | 
//+------------------------------------------------------------------+ 
void ManageTrades(double BidPrice, double AskPrice) 
{ 
    for (int i = PositionsTotal() - 1; i >= 0; i--) 
    { 
        ulong ticket = PositionGetTicket(i); 
        if (PositionSelectByTicket(ticket)) 
        { 
            // Close the last order and open an opposite one 
            if (PositionGetInteger(POSITION_MAGIC) == MagicNumber) 
            { 
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN); 
                int positionType = PositionGetInteger(POSITION_TYPE); 

                // Check if price has moved enough to open the opposite order 
                if ((positionType == POSITION_TYPE_BUY && BidPrice >= openPrice + DistancePips * PointPips) || 
                    (positionType == POSITION_TYPE_SELL && BidPrice <= openPrice - DistancePips * PointPips)) 
                { 
                    MqlTradeRequest closeRequest; 
                    MqlTradeResult closeResult; 
                    ZeroMemory(closeRequest); 
                    ZeroMemory(closeResult); 

                    closeRequest.action = TRADE_ACTION_DEAL; 
                    closeRequest.symbol = Symbol(); 
                    closeRequest.volume = PositionGetDouble(POSITION_VOLUME); 
                    closeRequest.type = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY; 
                    closeRequest.deviation = 10; 

                    if (OrderSend(closeRequest, closeResult)) 
                    { 
                        Print("Closed position and opened opposite order."); 

                        // Track profit and save portion if over threshold 
                        double profit = PositionGetDouble(POSITION_PROFIT); 
                        if (profit >= ProfitThreshold) // Check if profit threshold is met 
                        { 
                            double toSave = 1.0; // Save 1 USD 
                            SavedProfit += toSave; // Save the profit 
                            Print("Saved ", toSave, " USD. Total saved profit: ", SavedProfit); // Print saved profit 

                            // Reset the accumulated profit to keep only the remainder 
                            double remainder = profit - toSave; 
                            if (remainder < 0) remainder = 0; // Ensure no negative remainder 
                            
                            // Update the profit tracking for the next round 
                            if (remainder > 0) 
                            { 
                                // Handle any remaining profit for trading 
                                Print("Remaining profit for trading: ", remainder); 
                            } 
                        } 

                        // Alternate order logic 
                        if (lastOrderType == 1) // Last was BUY, now sell 
                        { 
                            PlaceTrade(ORDER_TYPE_SELL, Lotsize, BidPrice, TP_Pips); 
                            lastOrderType = 2; 
                        } 
                        else // Last was SELL, now buy 
                        { 
                            PlaceTrade(ORDER_TYPE_BUY, Lotsize, AskPrice, TP_Pips); 
                            lastOrderType = 1; 
                        } 
                    } 
                    else 
                    { 
                        Print("Error closing position: ", closeResult.retcode); 
                    } 
                } 
            } 
        } 
    } 
} 
