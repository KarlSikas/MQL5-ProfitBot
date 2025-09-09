//+------------------------------------------------------------------+
//|                                        KarlsProfitBot (Final).mq5|
//|                        Copyright 2025, Karl Sikas & GitHub Copilot |
//|                                     https://github.com/KarlSikas |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Karl Sikas & GitHub Copilot"
#property link      "https://github.com/KarlSikas"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <TradeLogger.mqh>

//--- EA seadistused
input group           "Strateegia parameetrid"
input int             fast_ema_period = 18;      // Kiire EMA periood
input int             slow_ema_period = 50;      // Aeglane EMA periood
input int             rsi_period      = 5;       // RSI periood

input group           "SL/TP Seaded"
input int             atr_period = 22;           // ATR indikaatori periood
input double          atr_multiplier_sl = 4.0;   // Mitu korda ATR väärtus SL jaoks
input double          atr_multiplier_tp = 2.5;   // Mitu korda ATR väärtus TP jaoks

input group           "Riskijuhtimine"
input double          risk_percent    = 1.0;     // Risk protsentides

input group           "Kellaajafilter"
input bool            enable_time_filter = true; // Lülita ajafilter sisse/välja
input int             trade_start_hour   = 10;   // Kauplemise algusaeg
input int             trade_end_hour     = 20;   // Kauplemise lõpuaeg

input group           "Trailing Stop Loss"
input bool            enable_trailing_sl = false; // Lülita Trailing SL sisse/välja
input double          trailing_start_pips = 50.0;
input double          trailing_distance_pips = 30.0;

input group           "Trendi filter (ADX)"
input bool            enable_adx_filter = true;   // Lülita ADX filter sisse/välja
input int             adx_period = 22;            // ADX indikaatori periood
input double          adx_threshold = 20.0;       // Minimaalne ADX väärtus tehinguks

input group           "Logimine"
input bool            enable_logging      = true;  // Lülita logimine CSV faili sisse/välja
input string          log_file_name       = "KarlsProfitBot_Log.csv"; // Logifaili nimi

input group           "EA Sätted"
input ulong           magic_number    = 2025;    // Unikaalne number

//--- Globaalsed muutujad
CTrade      trade;
TradeLogger logger;
int fast_ema_handle, slow_ema_handle, rsi_handle, atr_handle, adx_handle;
double fast_ema_buffer[], slow_ema_buffer[], rsi_buffer[], atr_buffer[], adx_buffer[];
double high_water_mark_balance;
string high_water_mark_variable_name;

int OnInit()
{
   logger.Init(log_file_name, enable_logging);
   logger.LogEvent("Käivitamine", "Karl's Profit Bot Final alustab tööd.");
   trade.SetExpertMagicNumber(magic_number);
   trade.SetMarginMode();
   trade.SetTypeFillingBySymbol(Symbol());
   trade.SetDeviationInPoints(10);
   fast_ema_handle = iMA(Symbol(), PERIOD_CURRENT, fast_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   slow_ema_handle = iMA(Symbol(), PERIOD_CURRENT, slow_ema_period, 0, MODE_EMA, PRICE_CLOSE);
   rsi_handle = iRSI(Symbol(), PERIOD_CURRENT, rsi_period, PRICE_CLOSE);
   atr_handle = iATR(Symbol(), PERIOD_CURRENT, atr_period);
   adx_handle = iADX(Symbol(), PERIOD_CURRENT, adx_period);
   if(fast_ema_handle==INVALID_HANDLE || slow_ema_handle==INVALID_HANDLE || rsi_handle==INVALID_HANDLE || atr_handle==INVALID_HANDLE || adx_handle==INVALID_HANDLE)
   {
      logger.LogError("OnInit", "Viga indikaatorite loomisel. EA peatub.");
      return(INIT_FAILED);
   }
   ArraySetAsSeries(fast_ema_buffer, true);
   ArraySetAsSeries(slow_ema_buffer, true);
   ArraySetAsSeries(rsi_buffer, true);
   ArraySetAsSeries(atr_buffer, true);
   ArraySetAsSeries(adx_buffer, true);
   high_water_mark_variable_name = "HWM_" + Symbol() + "_" + IntegerToString(magic_number);
   if(GlobalVariableCheck(high_water_mark_variable_name)) { high_water_mark_balance = GlobalVariableGet(high_water_mark_variable_name); }
   else { high_water_mark_balance = AccountInfoDouble(ACCOUNT_BALANCE); GlobalVariableSet(high_water_mark_variable_name, high_water_mark_balance); }
   double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(current_balance > high_water_mark_balance) { high_water_mark_balance = current_balance; GlobalVariableSet(high_water_mark_variable_name, high_water_mark_balance); }
   logger.LogEvent("OnInit", "Kõrgeim konto seis (High-Water Mark)", DoubleToString(high_water_mark_balance, 2));
   return(INIT_SUCCEEDED);
}
void OnDeinit(const int reason)
{
   logger.LogEvent("Peatamine", "Karl's Profit Bot on peatatud.", "Põhjus kood: " + IntegerToString(reason));
   IndicatorRelease(fast_ema_handle); IndicatorRelease(slow_ema_handle); IndicatorRelease(rsi_handle); IndicatorRelease(atr_handle); IndicatorRelease(adx_handle);
}
void OnTick()
{
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity > high_water_mark_balance) { high_water_mark_balance = current_equity; GlobalVariableSet(high_water_mark_variable_name, high_water_mark_balance); logger.LogEvent("HWM Uuendus", "Uus high-water mark saavutatud", DoubleToString(high_water_mark_balance,2)); }
   if(enable_trailing_sl) ManageTrailingStops();
   MqlDateTime current_time; TimeCurrent(current_time);
   if(enable_time_filter && (current_time.hour < trade_start_hour || current_time.hour >= trade_end_hour)) return;
   if(PositionsTotal() > 0) return;
   if(CopyBuffer(fast_ema_handle, 0, 0, 3, fast_ema_buffer)<3 || CopyBuffer(slow_ema_handle, 0, 0, 3, slow_ema_buffer)<3 || CopyBuffer(rsi_handle, 0, 0, 3, rsi_buffer)<3 || CopyBuffer(atr_handle, 0, 0, 2, atr_buffer)<2 || CopyBuffer(adx_handle, 0, 1, 1, adx_buffer)<1)
   { static datetime last_error_time = 0; if(TimeCurrent() - last_error_time > 60) { logger.LogError("OnTick", "Viga indikaatorite andmete kopeerimisel."); last_error_time = TimeCurrent(); } return; }
   if(enable_adx_filter && adx_buffer[0] < adx_threshold) return;
   double atr_value = atr_buffer[1], fast_ema_prev = fast_ema_buffer[1], slow_ema_prev = slow_ema_buffer[1], rsi_curr = rsi_buffer[0], rsi_prev = rsi_buffer[1];
   bool isUptrend = (fast_ema_prev > slow_ema_prev), rsiBuySignal = (rsi_prev < 50 && rsi_curr >= 50);
   if(isUptrend && rsiBuySignal)
   {
      double lot_size = CalculateLotSize(risk_percent, atr_value * atr_multiplier_sl); 
      if(lot_size > 0)
      {
         double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK), sl = price - (atr_value * atr_multiplier_sl), tp = enable_trailing_sl ? 0 : price + (atr_value * atr_multiplier_tp);
         trade.Buy(lot_size, Symbol(), price, sl, tp, "KarlsProfitBot Buy"); return;
      }
   }
   bool isDowntrend = (fast_ema_prev < slow_ema_prev), rsiSellSignal = (rsi_prev > 50 && rsi_curr <= 50);
   if(isDowntrend && rsiSellSignal)
   {
      double lot_size = CalculateLotSize(risk_percent, atr_value * atr_multiplier_sl);
      if(lot_size > 0)
      {
         double price = SymbolInfoDouble(Symbol(), SYMBOL_BID), sl = price + (atr_value * atr_multiplier_sl), tp = enable_trailing_sl ? 0 : price - (atr_value * atr_multiplier_tp);
         trade.Sell(lot_size, Symbol(), price, sl, tp, "KarlsProfitBot Sell"); return;
      }
   }
}
void OnTradeTransaction(const CTradeTransaction &trans, const CTradeRequest &request, const CTradeResult &result)
{
   if(trans.magic != magic_number) return;
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      string details = StringFormat("%s %.2f %s @ %.5f. SL: %.5f, TP: %.5f. P/L: %.2f", EnumToString((ENUM_DEAL_TYPE)trans.deal_type), trans.volume, trans.symbol, trans.price, trans.price_sl, trans.price_tp, trans.profit);
      logger.LogEvent("Tehing sooritatud", "Pilet #" + (string)trans.deal, details);
   }
   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED) { logger.LogError("Tehingu viga", "Kood: " + (string)result.retcode + " - " + result.comment); }
}
double CalculateLotSize(double riskPercent, double stopLossInPrice)
{
   double balance_for_calc = high_water_mark_balance;
   if(balance_for_calc <= 0 || stopLossInPrice <= 0) return 0.0;
   double riskAmount = balance_for_calc * (riskPercent / 100.0);
   string symbolName = Symbol();
   double tick_value = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE), tick_size = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_SIZE);
   if(tick_value <= 0 || tick_size <= 0) { logger.LogError("Lot Size", "Ei saanud kätte sümboli tick value/size: " + symbolName); return 0.0; }
   double loss_per_lot = (stopLossInPrice / tick_size) * tick_value;
   double lotSize = (loss_per_lot > 0) ? riskAmount / loss_per_lot : 0.0;
   double lotsStep = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
   lotSize = MathFloor(lotSize / lotsStep) * lotsStep;
   double margin_required = 0;
   if(!OrderCalcMargin(ORDER_TYPE_BUY, symbolName, lotSize, SymbolInfoDouble(symbolName, SYMBOL_ASK), margin_required)) { logger.LogError("Lot Size", "Marginaali arvutamine ebaõnnestus."); return 0.0; }
   if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin_required) { logger.LogEvent("Märkus", "Ei piisa vaba marginaali " + DoubleToString(lotSize,2) + " loti jaoks.", StringFormat("Vaja: %.2f, Vaba: %.2f", margin_required, AccountInfoDouble(ACCOUNT_MARGIN_FREE))); return 0.0; }
   double lotsMin = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MIN), lotsMax = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_MAX);
   if(lotSize < lotsMin) lotSize = 0.0; if(lotSize > lotsMax) lotSize = lotsMax;
   return lotSize;
}
void ManageTrailingStops()
{
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionSelect(Symbol()) && PositionGetInteger(POSITION_MAGIC) == magic_number)
      {
         long position_type = PositionGetInteger(POSITION_TYPE);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN), current_sl = PositionGetDouble(POSITION_SL);
         double current_price = (position_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK);
         if(position_type == POSITION_TYPE_BUY)
         {
            if((current_price - open_price) > trailing_start_pips * point)
            {
               double new_sl = current_price - trailing_distance_pips * point;
               if(new_sl > current_sl || current_sl == 0) { trade.PositionModify(Symbol(), new_sl, PositionGetDouble(POSITION_TP)); }
            }
         }
         else if(position_type == POSITION_TYPE_SELL)
         {
            if((open_price - current_price) > trailing_start_pips * point)
            {
               double new_sl = current_price + trailing_distance_pips * point;
               if(new_sl < current_sl || current_sl == 0) { trade.PositionModify(Symbol(), new_sl, PositionGetDouble(POSITION_TP)); }
            }
         }
      }
   }
}
