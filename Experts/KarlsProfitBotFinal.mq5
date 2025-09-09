//+------------------------------------------------------------------+
//|                                        KarlsProfitBot (Final).mq5|
//+------------------------------------------------------------------+
#property copyright "Karl Sikas"
#property link      "https://github.com/KarlSikas"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <TradeLogger.mqh>

//--- Inputs
input int    fast_ema_period      = 18;
input int    slow_ema_period      = 50;
input int    rsi_period           = 5;
input int    atr_period           = 22;
input double atr_multiplier_sl    = 4.0;
input double atr_multiplier_tp    = 2.5;
input double risk_percent         = 1.0;
input bool   enable_time_filter   = true;
input int    trade_start_hour     = 10;
input int    trade_end_hour       = 20;
input bool   enable_trailing_sl   = false;
input double trailing_start_pips  = 50.0;
input double trailing_distance_pips = 30.0;
input bool   enable_adx_filter    = true;
input int    adx_period           = 22;
input double adx_threshold        = 20.0;
input bool   enable_logging       = true;
input string log_file_name        = "KarlsProfitBot_Log.csv";
input ulong  magic_number         = 2025;

//--- Globals
CTrade      trade;
TradeLogger logger;
int         fast_ema_handle, slow_ema_handle, rsi_handle, atr_handle, adx_handle;
double      fast_ema_buffer[], slow_ema_buffer[], rsi_buffer[], atr_buffer[], adx_buffer[];
double      high_water_mark_balance;
string      high_water_mark_variable_name;

//+------------------------------------------------------------------+
int OnInit()
{
   logger.Init(log_file_name, enable_logging);
   logger.LogEvent("Startup", "EA Initializing...");

   trade.SetExpertMagicNumber(magic_number);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(Symbol());
   trade.SetDeviationInPoints(10);

   fast_ema_handle = iMA(Symbol(), PERIOD_CURRENT, fast_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   slow_ema_handle = iMA(Symbol(), PERIOD_CURRENT, slow_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   rsi_handle      = iRSI(Symbol(), PERIOD_CURRENT, rsi_period, PRICE_CLOSE);
   atr_handle      = iATR(Symbol(), PERIOD_CURRENT, atr_period);
   adx_handle      = iADX(Symbol(), PERIOD_CURRENT, adx_period);

   if(fast_ema_handle==INVALID_HANDLE || slow_ema_handle==INVALID_HANDLE || rsi_handle==INVALID_HANDLE || atr_handle==INVALID_HANDLE || adx_handle==INVALID_HANDLE)
   {
      logger.LogError("OnInit", "Failed to create indicators. EA stopping.");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(fast_ema_buffer, true);
   ArraySetAsSeries(slow_ema_buffer, true);
   ArraySetAsSeries(rsi_buffer, true);
   ArraySetAsSeries(atr_buffer, true);
   ArraySetAsSeries(adx_buffer, true);

   high_water_mark_variable_name = "HWM_" + Symbol() + "_" + IntegerToString(magic_number);
   if(GlobalVariableCheck(high_water_mark_variable_name))
      high_water_mark_balance = GlobalVariableGet(high_water_mark_variable_name);
   else
   {
      high_water_mark_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(high_water_mark_variable_name, high_water_mark_balance);
   }
   
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(current_balance > high_water_mark_balance)
   {
      high_water_mark_balance = current_balance;
      GlobalVariableSet(high_water_mark_variable_name, high_water_mark_balance);
   }
   
   logger.LogEvent("OnInit", "High-Water Mark set to", DoubleToString(high_water_mark_balance, 2));
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   logger.LogEvent("Shutdown", "EA Deinitialized.", "Reason code: " + IntegerToString(reason));
   IndicatorRelease(fast_ema_handle);
   IndicatorRelease(slow_ema_handle);
   IndicatorRelease(rsi_handle);
   IndicatorRelease(atr_handle);
   IndicatorRelease(adx_handle);
}
//+------------------------------------------------------------------+
void OnTick()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity > high_water_mark_balance)
   {
      high_water_mark_balance = current_equity;
      GlobalVariableSet(high_water_mark_variable_name, high_water_mark_balance);
      logger.LogEvent("HWM Update", "New high-water mark", DoubleToString(high_water_mark_balance,2));
   }

   if(enable_trailing_sl)
      ManageTrailingStops();

   MqlDateTime current_time;
   TimeCurrent(current_time);
   if(enable_time_filter && (current_time.hour < trade_start_hour || current_time.hour >= trade_end_hour))
      return;

   if(PositionsTotal() > 0)
      return;

   if(CopyBuffer(fast_ema_handle, 0, 0, 3, fast_ema_buffer)<3 ||
      CopyBuffer(slow_ema_handle, 0, 0, 3, slow_ema_buffer)<3 ||
      CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer)<3 ||
      CopyBuffer(atr_handle, 0, 0, 2, atr_buffer)<2 ||
      CopyBuffer(adx_handle, 0, 0, 1, adx_buffer)<1)
   {
      return;
   }

   if(enable_adx_filter && adx_buffer[0] < adx_threshold)
      return;

   double atr_value = atr_buffer[1];
   double fast_ema_prev = fast_ema_buffer[1];
   double slow_ema_prev = slow_ema_buffer[1];
   double rsi_curr = rsi_buffer[0];
   double rsi_prev = rsi_buffer[1];

   bool isUptrend = (fast_ema_prev > slow_ema_prev);
   bool rsiBuySignal = (rsi_prev < 50 && rsi_curr >= 50);

   if(isUptrend && rsiBuySignal)
   {
      double lot_size = CalculateLotSize(risk_percent, atr_value * atr_multiplier_sl);
      if(lot_size > 0)
      {
         double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         double sl = price - (atr_value * atr_multiplier_sl);
         double tp = enable_trailing_sl ? 0 : price + (atr_value * atr_multiplier_tp);
         trade.Buy(lot_size, Symbol(), price, sl, tp, "KarlsProfitBot Buy");
         return;
      }
   }

   bool isDowntrend = (fast_ema_prev < slow_ema_prev);
   bool rsiSellSignal = (rsi_prev > 50 && rsi_curr <= 50);

   if(isDowntrend && rsiSellSignal)
   {
      double lot_size = CalculateLotSize(risk_percent, atr_value * atr_multiplier_sl);
      if(lot_size > 0)
      {
         double price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
         double sl = price + (atr_value * atr_multiplier_sl);
         double tp = enable_trailing_sl ? 0 : price - (atr_value * atr_multiplier_tp);
         trade.Sell(lot_size, Symbol(), price, sl, tp, "KarlsProfitBot Sell");
         return;
      }
   }
}
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
    // Kontrollime ainult neid tehinguid, mis on seotud meie EA-ga
    if(request.magic != magic_number)
        return;

    // Kui tehingu tulemusena lisati uus diil ajalukku
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && result.deal > 0)
    {
        // Küsime selle diili andmed ajaloo põhjal
        if(HistoryDealSelect(result.deal))
        {
            long deal_magic = HistoryDealGetInteger(result.deal, DEAL_MAGIC);
            if(deal_magic == magic_number)
            {
                string details = StringFormat("%s %.2f %s @ %.5f. SL: %.5f, TP: %.5f. P/L: %.2f",
                                              EnumToString((ENUM_DEAL_TYPE)HistoryDealGetInteger(result.deal, DEAL_TYPE)),
                                              HistoryDealGetDouble(result.deal, DEAL_VOLUME),
                                              HistoryDealGetString(result.deal, DEAL_SYMBOL),
                                              HistoryDealGetDouble(result.deal, DEAL_PRICE),
                                              HistoryDealGetDouble(result.deal, DEAL_SL),
                                              HistoryDealGetDouble(result.deal, DEAL_TP),
                                              HistoryDealGetDouble(result.deal, DEAL_PROFIT));
                logger.LogEvent("Deal Executed", "Ticket #" + (string)result.deal, details);
            }
        }
    }

    // Logime vead, kui neid esines
    if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
    {
        logger.LogError("Trade Error", "Code: " + (string)result.retcode + " - " + result.comment);
    }
}
//+------------------------------------------------------------------+
double CalculateLotSize(double riskPercent, double stopLossInPrice)
{
   double balance_for_calc = high_water_mark_balance;
   if(balance_for_calc <= 0 || stopLossInPrice <= 0)
      return 0.0;

   double riskAmount = balance_for_calc * (riskPercent / 100.0);
   string symbolName = Symbol();
   double tick_value = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_SIZE);

   if(tick_value <= 0 || tick_size <= 0)
   {
      logger.LogError("Lot Size", "Invalid tick value/size for symbol: " + symbolName);
      return 0.0;
   }

   double loss_per_lot = (stopLossInPrice / tick_size) * tick_value;
   double lotSize = (loss_per_lot > 0) ? riskAmount / loss_per_lot : 0.0;

   double lotsStep = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotsStep) * lotsStep;

   double margin_required = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbolName, lotSize, SymbolInfoDouble(symbolName, SYMBOL_ASK), margin_required))
   {
      logger.LogError("Lot Size", "OrderCalcMargin failed.");
      return 0.0;
   }

   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin_required)
   {
      logger.LogEvent("Margin", "Not enough free margin for lot " + DoubleToString(lotSize,2));
      return 0.0;
   }

   double lotsMin = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN);
   double lotsMax = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MAX);
   lotSize = fmax(lotsMin, fmin(lotSize, lotsMax));
   
   if (lotSize < lotsMin) lotSize = 0.0;

   return lotSize;
}
//+------------------------------------------------------------------+
void ManageTrailingStops()
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(Symbol()) && PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
         long position_type = PositionGetInteger(POSITION_TYPE);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         double current_price = (position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);

         if(position_type == POSITION_TYPE_BUY)
         {
            if((current_price - open_price) > trailing_start_pips * point)
            {
               double new_sl = current_price - trailing_distance_pips * point;
               if(new_sl > current_sl || current_sl == 0)
                  trade.PositionModify(Symbol(), new_sl, PositionGetDouble(POSITION_TP));
            }
         }
         else if(position_type == POSITION_TYPE_SELL)
         {
            if((open_price - current_price) > trailing_start_pips * point)
            {
               double new_sl = current_price + trailing_distance_pips * point;
               if(new_sl < current_sl || current_sl == 0)
                  trade.PositionModify(Symbol(), new_sl, PositionGetDouble(POSITION_TP));
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
