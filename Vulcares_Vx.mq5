//+------------------------------------------------------------------+
//|                                                  Vulcares_Vx.mq5 |
//|        M15/M5 Swing-Trend Pullback & Basket Profit Engine        |
//|   Built for High-Spread XAUUSDm (Fixes M1 Noise & SL Bug)        |
//+------------------------------------------------------------------+
#property copyright "Vulcares Quantitative Engineering"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- Enums
enum ENUM_EXECUTION_MODE
{
   MODE_TREND_LAYERING      = 0, // Trend Pyramiding Layering (Up=BUY, Down=SELL)
   MODE_STRICT_SINGLE_ENTRY = 1  // Single Entry Only
};

enum ENUM_EA_STATE
{
   STATE_INITIALIZING = 0,
   STATE_SCANNING,
   STATE_ENTRY_PENDING,
   STATE_POSITION_ACTIVE,
   STATE_LAYERING_ACTIVE,
   STATE_TRAILING_ACTIVE,
   STATE_RISK_LOCK,
   STATE_DISCONNECTED,
   STATE_EMERGENCY_STOP
};

//--- Input Parameters
input group "=== 1. GENERAL SETTINGS ==="
input bool                InpTradingEnabled       = true;                      // Trading Enabled
input bool                InpDemoOnly             = true;                      // Safety: Demo/Tester Only Mode
input ulong               InpMagicNumber          = 20260306;                  // Magic Number
input string              InpTradingSymbol        = "";                        // Trading Symbol (Empty = Current)
input ENUM_TIMEFRAMES     InpEntryTimeframe       = PERIOD_M5;                 // Entry Confirmation Timeframe (M5 - Immune to M1 Noise)
input ENUM_TIMEFRAMES     InpTrendTimeframe       = PERIOD_M15;                // Macro Trend Filter Timeframe (M15)
input bool                InpEnableBuy            = true;                      // Enable BUY Engine
input bool                InpEnableSell           = true;                      // Enable SELL Engine
input ENUM_EXECUTION_MODE InpExecutionMode        = MODE_TREND_LAYERING;       // Execution Mode

input group "=== 2. SWING TREND & PULLBACK REJECTION FILTER ==="
input int                 InpFastEMAPeriod        = 21;                        // Fast EMA Period
input int                 InpSlowEMAPeriod        = 55;                        // Slow EMA Period
input int                 InpTrendEMAPeriod       = 200;                       // Macro Trend EMA Period (M15)
input int                 InpRSIPeriod            = 14;                        // RSI Period (M5)
input double              InpRSIBuyPullbackMax    = 58.0;                      // Max M5 RSI for BUY (Avoid Buying Overbought Tops!)
input double              InpRSIBuyPullbackMin    = 40.0;                      // Min M5 RSI for BUY (Confirm Bullish Pullback)
input double              InpRSISellPullbackMin   = 42.0;                      // Min M5 RSI for SELL (Avoid Selling Oversold Bottoms!)
input double              InpRSISellPullbackMax   = 60.0;                      // Max M5 RSI for SELL (Confirm Bearish Pullback)
input int                 InpATRPeriod            = 14;                        // ATR Period (M5)
input int                 InpMinATRPointsM5       = 250;                       // Min M5 ATR (points)
input int                 InpMaxATRPointsM5       = 4500;                      // Max M5 ATR (points - Allows Active XAUUSD!)
input int                 InpMinCooldownMinutes   = 10;                        // Min Cooldown After Exit (Minutes - Stops Overtrading)

input group "=== 3. TREND PYRAMIDING LAYERING SETTINGS ==="
input double              InpBaseLot              = 0.01;                      // Fixed Base Lot (0.01)
input bool                InpEnableTrendLayering  = true;                      // Enable Pyramiding Layering
input int                 InpMaxLayers            = 3;                         // Max Simultaneous Layers Per Direction
input int                 InpLayerStepPoints      = 750;                       // Min Favorable Distance to Add Layer (points)
input double              InpLayerLotMultiplier   = 1.0;                       // Layer Lot Multiplier (1.0 = Fixed 0.01)

input group "=== 4. STOP LOSS ($10 USD/USC) & REALISTIC GOLD TRAILING ==="
input double              InpStopLossMoney        = 10.0;                      // Stop Loss Per Position ($10.00 USD/USC)
input int                 InpFallbackSLPoints     = 1000;                      // Fallback SL Points (1000 pts = $10 @ 0.01 lot)
input bool                InpEnableTakeProfit     = true;                      // Enable Structural Take Profit Target
input double              InpRiskRewardRatio      = 2.2;                       // Take Profit R:R Ratio (2.2x SL = +$22 vs -$10)
input bool                InpEnableTrailingStop   = true;                      // Enable Wide Gold Trailing Stop
input int                 InpTrailingStartPts     = 1100;                      // Min Profit Before Trailing Starts (points = +$11)
input int                 InpTrailingDistancePts  = 800;                       // Trailing Breathing Distance (points = $8)
input int                 InpTrailingStepPts      = 50;                        // Min SL Modification Step (points)

input group "=== 5. SAFETY & RISK PROTECTION ==="
input int                 InpMaxSpreadPoints      = 350;                       // Max Allowed Spread (points)
input int                 InpMaxSlippagePoints    = 50;                        // Max Slippage (points)
input double              InpMaxDailyLossPercent  = 15.0;                      // Max Daily Loss (% Balance)
input double              InpMaxEquityDDPercent   = 25.0;                      // Max Equity Drawdown (% Peak)
input double              InpMaxExposureLots      = 0.05;                      // Max Total Exposure (Lots)
input double              InpMinFreeMarginPercent = 150.0;                     // Min Free Margin Level (%)

input group "=== 6. DASHBOARD & VISUALS ==="
input bool                InpShowDashboard        = true;                      // Show Dark Professional Dashboard
input bool                InpShowTradeVisuals     = true;                      // Show Entry/Exit Arrows & SL Lines

//--- Structs
struct PositionTracker
{
   ulong    ticket;
   int      type;
   double   open_price;
   double   volume;
   double   highest_bid;
   double   lowest_ask;
   double   current_sl;
   datetime open_time;
};

//--- Globals
CTrade             ExtTrade;
CPositionInfo      ExtPos;
CSymbolInfo        ExtSym;

string             g_symbol;
ENUM_EA_STATE      g_state = STATE_INITIALIZING;
bool               g_emergency_stop = false;
bool               g_order_pending = false;
datetime           g_last_exit_time = 0;
datetime           g_last_entry_bar_time = 0;
double             g_day_start_balance = 0.0;
double             g_peak_equity = 0.0;
int                g_current_day = -1;

// Indicator Handles
int                g_h_ema_fast_m5  = INVALID_HANDLE;
int                g_h_ema_slow_m5  = INVALID_HANDLE;
int                g_h_rsi_m5       = INVALID_HANDLE;
int                g_h_atr_m5       = INVALID_HANDLE;
int                g_h_ema_fast_m15 = INVALID_HANDLE;
int                g_h_ema_slow_m15 = INVALID_HANDLE;
int                g_h_ema_200_m15  = INVALID_HANDLE;

// Live metrics
double             g_current_atr_pts  = 0.0;
double             g_current_rsi_m5   = 50.0;
string             g_macro_bias       = "NEUTRAL";
string             g_signal_status    = "SCANNING";

// Tracked positions
PositionTracker    g_tracked[20];
int                g_tracked_count = 0;

string             g_prefix = "VULCARES_VX_";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = (InpTradingSymbol == "") ? _Symbol : InpTradingSymbol;
   if(!ExtSym.Name(g_symbol))
      return(INIT_FAILED);
   ExtSym.RefreshRates();

   ENUM_ACCOUNT_TRADE_MODE acc_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(InpDemoOnly && acc_mode == ACCOUNT_TRADE_MODE_REAL && !MQLInfoInteger(MQL_TESTER))
   {
      Alert("[Vulcares Vx] SAFETY LOCK: InpDemoOnly=true blocks LIVE accounts.");
      g_state = STATE_RISK_LOCK;
   }

   g_h_ema_fast_m5  = iMA(g_symbol, InpEntryTimeframe, InpFastEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_slow_m5  = iMA(g_symbol, InpEntryTimeframe, InpSlowEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_rsi_m5       = iRSI(g_symbol, InpEntryTimeframe, InpRSIPeriod, PRICE_CLOSE);
   g_h_atr_m5       = iATR(g_symbol, InpEntryTimeframe, InpATRPeriod);
   g_h_ema_fast_m15 = iMA(g_symbol, InpTrendTimeframe, InpFastEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_slow_m15 = iMA(g_symbol, InpTrendTimeframe, InpSlowEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_200_m15  = iMA(g_symbol, InpTrendTimeframe, InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(g_h_ema_fast_m5 == INVALID_HANDLE || g_h_ema_slow_m5 == INVALID_HANDLE || g_h_rsi_m5 == INVALID_HANDLE ||
      g_h_atr_m5 == INVALID_HANDLE || g_h_ema_fast_m15 == INVALID_HANDLE || g_h_ema_slow_m15 == INVALID_HANDLE ||
      g_h_ema_200_m15 == INVALID_HANDLE)
   {
      Print("[Vulcares Vx] Failed to create indicator handles.");
      return(INIT_FAILED);
   }

   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(InpMaxSlippagePoints);
   ExtTrade.SetTypeFillingBySymbol(g_symbol);
   ExtTrade.SetAsyncMode(false);

   g_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_peak_equity       = AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime dt;
   TimeCurrent(dt);
   g_current_day = dt.day_of_year;

   ReconcilePositions();

   if(InpShowDashboard)
      CreateDashboard();

   EventSetMillisecondTimer(250);
   if(g_state != STATE_RISK_LOCK)
      g_state = STATE_SCANNING;

   int calc_sl = MoneyToPoints(InpStopLossMoney, InpBaseLot);
   Print("[Vulcares Vx] v3.00 Initialized | Symbol: ", g_symbol, " | SL ($", InpStopLossMoney, "): ", calc_sl, " pts");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(g_h_ema_fast_m5);
   IndicatorRelease(g_h_ema_slow_m5);
   IndicatorRelease(g_h_rsi_m5);
   IndicatorRelease(g_h_atr_m5);
   IndicatorRelease(g_h_ema_fast_m15);
   IndicatorRelease(g_h_ema_slow_m15);
   IndicatorRelease(g_h_ema_200_m15);
   ObjectsDeleteAll(0, g_prefix);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) && !MQLInfoInteger(MQL_TESTER))
      g_state = STATE_DISCONNECTED;
   else if(g_state == STATE_DISCONNECTED)
   {
      ReconcilePositions();
      g_state = STATE_SCANNING;
   }

   if(InpShowDashboard)
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Main Tick Execution Engine                                       |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_emergency_stop)
   {
      g_state = STATE_EMERGENCY_STOP;
      return;
   }

   if(!ExtSym.RefreshRates())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(g_symbol, tick))
      return;

   if(tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
      return;

   CheckDailyReset();
   if(!CheckRiskGuards())
   {
      g_state = STATE_RISK_LOCK;
      return;
   }
   else if(g_state == STATE_RISK_LOCK && !g_emergency_stop)
   {
      g_state = STATE_SCANNING;
   }

   ReconcilePositions();

   // 1. Manage Open Positions with Wide Gold Trailing Stop
   if(g_tracked_count > 0)
      ManageOpenPositions(tick);

   if(!InpTradingEnabled || g_state == STATE_RISK_LOCK || g_order_pending)
      return;

   // 2. Evaluate M15/M5 Closed-Candle Pullback Confirmation
   EvaluateSwingPullbackEntry(tick);

   if(InpShowDashboard && MQLInfoInteger(MQL_VISUAL_MODE))
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Helper to Read Single Indicator Value                            |
//+------------------------------------------------------------------+
double GetIndVal(int handle, int shift)
{
   double buf[1];
   if(CopyBuffer(handle, 0, shift, 1, buf) <= 0)
      return 0.0;
   return buf[0];
}

//+------------------------------------------------------------------+
//| Convert $10 USD/USC to Points With Exact Broker Safeguard        |
//+------------------------------------------------------------------+
int MoneyToPoints(double money_amount, double lot)
{
   double point     = ExtSym.Point();
   double tick_val  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_val <= 0.0)
      tick_val = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz   = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   double contract  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   int pts = InpFallbackSLPoints;

   if(point > 0.0 && tick_val > 0.0 && tick_sz > 0.0 && lot > 0.0)
   {
      double pt_val_per_lot = tick_val * (point / tick_sz);
      double cost_per_point = pt_val_per_lot * lot;
      if(cost_per_point > 0.0)
         pts = (int)MathCeil(money_amount / cost_per_point);
   }

   // Sanity guard: if broker tester reports corrupt tick_value causing > 5000 pts for $10 on 0.01 lot,
   // compute directly from Contract Size (for XAUUSD 100 oz * 0.01 lot = $1 per $1 move = $0.001/pt -> 10,000 pts if 3-digit, 1,000 pts if 2-digit)
   if(contract > 0.0 && point > 0.0 && lot > 0.0)
   {
      double direct_cost_per_pt = contract * point * lot;
      if(direct_cost_per_pt > 0.0)
      {
         int direct_pts = (int)MathCeil(money_amount / direct_cost_per_pt);
         if(pts > direct_pts * 2 || pts < direct_pts / 2)
            pts = direct_pts;
      }
   }

   return MathMax(200, pts);
}

//+------------------------------------------------------------------+
//| M15 Macro Trend + M5 Closed-Candle Pullback Confirmation Engine  |
//+------------------------------------------------------------------+
void EvaluateSwingPullbackEntry(const MqlTick &tick)
{
   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long spread_pts = (long)MathRound((tick.ask - tick.bid) / point);
   if(spread_pts > InpMaxSpreadPoints)
   {
      g_signal_status = "HIGH SPREAD (" + IntegerToString(spread_pts) + ")";
      return;
   }

   // Read M15 Macro Trend & M5 Confirmed Closed Bar [1] Indicators
   double ema21_m15 = GetIndVal(g_h_ema_fast_m15, 1);
   double ema55_m15 = GetIndVal(g_h_ema_slow_m15, 1);
   double ema200_m15= GetIndVal(g_h_ema_200_m15, 1);

   double ema21_m5  = GetIndVal(g_h_ema_fast_m5, 1);
   double ema55_m5  = GetIndVal(g_h_ema_slow_m5, 1);
   double rsi_m5    = GetIndVal(g_h_rsi_m5, 1);
   double atr_m5    = GetIndVal(g_h_atr_m5, 1);

   if(ema21_m15 == 0.0 || ema200_m15 == 0.0 || ema21_m5 == 0.0 || atr_m5 == 0.0)
      return;

   g_current_atr_pts = atr_m5 / point;
   g_current_rsi_m5  = rsi_m5;

   if(g_current_atr_pts < InpMinATRPointsM5)
   {
      g_signal_status = "DEAD MARKET";
      return;
   }
   if(g_current_atr_pts > InpMaxATRPointsM5)
   {
      g_signal_status = "EXTREME SPIKE";
      return;
   }

   // Strict Multi-Timeframe Structural Alignment
   bool bull_trend = (tick.bid > ema200_m15) && (ema21_m15 > ema55_m15) && (ema21_m5 > ema55_m5);
   bool bear_trend = (tick.bid < ema200_m15) && (ema21_m15 < ema55_m15) && (ema21_m5 < ema55_m5);

   if(bull_trend)
      g_macro_bias = "UPTREND (M15/M5)";
   else if(bear_trend)
      g_macro_bias = "DOWNTREND (M15/M5)";
   else
   {
      g_macro_bias = "SIDEWAYS / MIXED";
      g_signal_status = "WAIT TREND ALIGN";
      return;
   }

   // Count active layers
   int buy_layers = 0, sell_layers = 0;
   double highest_buy_entry = -DBL_MAX;
   double lowest_sell_entry = DBL_MAX;

   for(int i = 0; i < g_tracked_count; i++)
   {
      if(g_tracked[i].type == POSITION_TYPE_BUY)
      {
         buy_layers++;
         if(g_tracked[i].open_price > highest_buy_entry)
            highest_buy_entry = g_tracked[i].open_price;
      }
      else if(g_tracked[i].type == POSITION_TYPE_SELL)
      {
         sell_layers++;
         if(g_tracked[i].open_price < lowest_sell_entry)
            lowest_sell_entry = g_tracked[i].open_price;
      }
   }

   // Cooldown after exit to prevent revenge/churn trading
   datetime now = TimeCurrent();
   if(buy_layers == 0 && sell_layers == 0 && g_last_exit_time > 0)
   {
      long elapsed_sec = (long)(now - g_last_exit_time);
      long req_sec     = InpMinCooldownMinutes * 60;
      if(elapsed_sec < req_sec)
      {
         g_signal_status = "COOLDOWN " + IntegerToString((req_sec - elapsed_sec) / 60 + 1) + "m";
         return;
      }
   }

   // M5 Closed Candle [1] Price Action (Pullback Rejection Pattern)
   datetime bar1_time = iTime(g_symbol, InpEntryTimeframe, 1);
   double open1  = iOpen(g_symbol, InpEntryTimeframe, 1);
   double close1 = iClose(g_symbol, InpEntryTimeframe, 1);
   double low1   = iLow(g_symbol, InpEntryTimeframe, 1);
   double high1  = iHigh(g_symbol, InpEntryTimeframe, 1);

   bool allow_layering = (InpExecutionMode == MODE_TREND_LAYERING && InpEnableTrendLayering);
   int max_allowed = allow_layering ? MathMax(1, InpMaxLayers) : 1;
   long stops_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);

   // =================================================================
   // BUY ENGINE: Uptrend + Pullback to M5 EMA21 + Bullish Candle Close
   // =================================================================
   if(InpEnableBuy && bull_trend && sell_layers == 0 && buy_layers < max_allowed)
   {
      if(buy_layers == 0)
      {
         bool touched_ema_zone = (low1 <= ema21_m5 + atr_m5 * 0.35) && (close1 > ema21_m5);
         bool bullish_candle   = (close1 > open1) && ((close1 - open1) >= atr_m5 * 0.15);
         bool rsi_pullback_ok  = (rsi_m5 >= InpRSIBuyPullbackMin && rsi_m5 <= InpRSIBuyPullbackMax);

         if(bar1_time != g_last_entry_bar_time && touched_ema_zone && bullish_candle && rsi_pullback_ok)
         {
            double lot = CalculateLayerLot(0);
            int sl_pts = (int)MathMax((double)(stops_level + 30), (double)MoneyToPoints(InpStopLossMoney, lot));
            double sl  = NormalizePrice(tick.ask - sl_pts * point);
            double tp  = InpEnableTakeProfit ? NormalizePrice(tick.ask + (sl_pts * InpRiskRewardRatio) * point) : 0.0;

            g_signal_status = "BUY PULLBACK OK";
            if(ExecuteMarketOrder(ORDER_TYPE_BUY, lot, tick.ask, sl, tp, "VulcaresVx_BUY_L1"))
            {
               g_last_entry_bar_time = bar1_time;
               g_state = STATE_ENTRY_PENDING;
            }
         }
         else
         {
            g_signal_status = !rsi_pullback_ok ? "RSI OVERBOUGHT" : "WAIT M5 PULLBACK";
         }
      }
      else if(allow_layering)
      {
         double step_pts = (tick.ask - highest_buy_entry) / point;
         if(step_pts >= InpLayerStepPoints && close1 > open1 && bar1_time != g_last_entry_bar_time)
         {
            double lot = CalculateLayerLot(buy_layers);
            int sl_pts = (int)MathMax((double)(stops_level + 30), (double)MoneyToPoints(InpStopLossMoney, lot));
            double sl  = NormalizePrice(tick.ask - sl_pts * point);
            double tp  = InpEnableTakeProfit ? NormalizePrice(tick.ask + (sl_pts * InpRiskRewardRatio) * point) : 0.0;

            string cmt = "VulcaresVx_BUY_L" + IntegerToString(buy_layers + 1);
            if(ExecuteMarketOrder(ORDER_TYPE_BUY, lot, tick.ask, sl, tp, cmt))
            {
               g_last_entry_bar_time = bar1_time;
               g_state = STATE_LAYERING_ACTIVE;
            }
         }
      }
   }

   // =================================================================
   // SELL ENGINE: Downtrend + Pullback to M5 EMA21 + Bearish Candle Close
   // =================================================================
   if(InpEnableSell && bear_trend && buy_layers == 0 && sell_layers < max_allowed)
   {
      if(sell_layers == 0)
      {
         bool touched_ema_zone = (high1 >= ema21_m5 - atr_m5 * 0.35) && (close1 < ema21_m5);
         bool bearish_candle   = (close1 < open1) && ((open1 - close1) >= atr_m5 * 0.15);
         bool rsi_pullback_ok  = (rsi_m5 >= InpRSISellPullbackMin && rsi_m5 <= InpRSISellPullbackMax);

         if(bar1_time != g_last_entry_bar_time && touched_ema_zone && bearish_candle && rsi_pullback_ok)
         {
            double lot = CalculateLayerLot(0);
            int sl_pts = (int)MathMax((double)(stops_level + 30), (double)MoneyToPoints(InpStopLossMoney, lot));
            double sl  = NormalizePrice(tick.bid + sl_pts * point);
            double tp  = InpEnableTakeProfit ? NormalizePrice(tick.bid - (sl_pts * InpRiskRewardRatio) * point) : 0.0;

            g_signal_status = "SELL PULLBACK OK";
            if(ExecuteMarketOrder(ORDER_TYPE_SELL, lot, tick.bid, sl, tp, "VulcaresVx_SELL_L1"))
            {
               g_last_entry_bar_time = bar1_time;
               g_state = STATE_ENTRY_PENDING;
            }
         }
         else
         {
            g_signal_status = !rsi_pullback_ok ? "RSI OVERSOLD" : "WAIT M5 PULLBACK";
         }
      }
      else if(allow_layering)
      {
         double step_pts = (lowest_sell_entry - tick.bid) / point;
         if(step_pts >= InpLayerStepPoints && close1 < open1 && bar1_time != g_last_entry_bar_time)
         {
            double lot = CalculateLayerLot(sell_layers);
            int sl_pts = (int)MathMax((double)(stops_level + 30), (double)MoneyToPoints(InpStopLossMoney, lot));
            double sl  = NormalizePrice(tick.bid + sl_pts * point);
            double tp  = InpEnableTakeProfit ? NormalizePrice(tick.bid - (sl_pts * InpRiskRewardRatio) * point) : 0.0;

            string cmt = "VulcaresVx_SELL_L" + IntegerToString(sell_layers + 1);
            if(ExecuteMarketOrder(ORDER_TYPE_SELL, lot, tick.bid, sl, tp, cmt))
            {
               g_last_entry_bar_time = bar1_time;
               g_state = STATE_LAYERING_ACTIVE;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Wide Gold Trailing Stop Engine                                   |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlTick &tick)
{
   if(!InpEnableTrailingStop)
      return;

   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long stops_level  = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_stop_dist = MathMax((double)stops_level, 20.0) * point;
   double freeze_dist   = (double)freeze_level * point;

   for(int i = 0; i < g_tracked_count; i++)
   {
      ulong ticket = g_tracked[i].ticket;
      if(!PositionSelectByTicket(ticket))
         continue;

      int    pos_type   = (int)PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);

      if(pos_type == POSITION_TYPE_BUY)
      {
         if(tick.bid > g_tracked[i].highest_bid)
            g_tracked[i].highest_bid = tick.bid;

         double peak_profit_pts = (g_tracked[i].highest_bid - open_price) / point;
         if(peak_profit_pts >= InpTrailingStartPts)
         {
            double trail_sl = NormalizePrice(g_tracked[i].highest_bid - InpTrailingDistancePts * point);
            if(trail_sl > open_price && (current_sl == 0.0 || trail_sl >= current_sl + InpTrailingStepPts * point))
            {
               if((tick.bid - trail_sl) >= min_stop_dist &&
                  (current_sl == 0.0 || MathAbs(tick.bid - current_sl) > freeze_dist))
               {
                  if(ModifyPositionSL(ticket, trail_sl, current_tp))
                  {
                     g_tracked[i].current_sl = trail_sl;
                     g_state = STATE_TRAILING_ACTIVE;
                     if(InpShowTradeVisuals)
                        DrawTrailingLine(ticket, trail_sl);
                  }
               }
            }
         }
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         if(tick.ask < g_tracked[i].lowest_ask || g_tracked[i].lowest_ask == 0.0)
            g_tracked[i].lowest_ask = tick.ask;

         double peak_profit_pts = (open_price - g_tracked[i].lowest_ask) / point;
         if(peak_profit_pts >= InpTrailingStartPts)
         {
            double trail_sl = NormalizePrice(g_tracked[i].lowest_ask + InpTrailingDistancePts * point);
            if(trail_sl < open_price && (current_sl == 0.0 || trail_sl <= current_sl - InpTrailingStepPts * point))
            {
               if((trail_sl - tick.ask) >= min_stop_dist &&
                  (current_sl == 0.0 || MathAbs(current_sl - tick.ask) > freeze_dist))
               {
                  if(ModifyPositionSL(ticket, trail_sl, current_tp))
                  {
                     g_tracked[i].current_sl = trail_sl;
                     g_state = STATE_TRAILING_ACTIVE;
                     if(InpShowTradeVisuals)
                        DrawTrailingLine(ticket, trail_sl);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Reconciliation                                 |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.symbol != g_symbol)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      g_order_pending = false;
      if(HistoryDealSelect(trans.deal))
      {
         long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         if(magic == (long)InpMagicNumber)
         {
            long entry_type = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            double price    = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            long deal_type  = HistoryDealGetInteger(trans.deal, DEAL_TYPE);

            if(entry_type == DEAL_ENTRY_OUT || entry_type == DEAL_ENTRY_INOUT)
            {
               double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                               HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                               HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
               g_last_exit_time = TimeCurrent();
               g_state = STATE_SCANNING;

               if(InpShowTradeVisuals)
                  DrawExitMarker(trans.deal, price, profit);
            }
            else if(entry_type == DEAL_ENTRY_IN)
            {
               g_state = STATE_POSITION_ACTIVE;
               if(InpShowTradeVisuals)
                  DrawEntryMarker(trans.deal, price, (int)deal_type);
            }
         }
      }
      ReconcilePositions();
   }
   else if(trans.type == TRADE_TRANSACTION_REQUEST)
   {
      if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
         g_order_pending = false;
   }
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Emergency Stop & Reset Button)              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == g_prefix + "BTN_ESTOP")
      {
         g_emergency_stop = !g_emergency_stop;
         if(g_emergency_stop)
         {
            CloseAllEA_Positions("Emergency Stop Triggered");
            g_state = STATE_EMERGENCY_STOP;
         }
         else
         {
            g_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            g_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
            g_state = STATE_SCANNING;
         }
         UpdateDashboard();
      }
   }
}

void ReconcilePositions()
{
   PositionTracker updated[20];
   int count = 0;

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      if(count < 20)
      {
         updated[count].ticket      = ticket;
         updated[count].type        = (int)PositionGetInteger(POSITION_TYPE);
         updated[count].open_price  = PositionGetDouble(POSITION_PRICE_OPEN);
         updated[count].volume      = PositionGetDouble(POSITION_VOLUME);
         updated[count].current_sl  = PositionGetDouble(POSITION_SL);
         updated[count].open_time   = (datetime)PositionGetInteger(POSITION_TIME);

         updated[count].highest_bid = updated[count].open_price;
         updated[count].lowest_ask  = updated[count].open_price;
         for(int j = 0; j < g_tracked_count; j++)
         {
            if(g_tracked[j].ticket == ticket)
            {
               updated[count].highest_bid = g_tracked[j].highest_bid;
               updated[count].lowest_ask  = g_tracked[j].lowest_ask;
               break;
            }
         }
         count++;
      }
   }

   g_tracked_count = count;
   for(int k = 0; k < count; k++)
      g_tracked[k] = updated[k];
}

bool ExecuteMarketOrder(ENUM_ORDER_TYPE order_type, double lot, double price, double sl, double tp, string comment)
{
   double cur_exposure = 0.0;
   for(int i = 0; i < g_tracked_count; i++)
      cur_exposure += g_tracked[i].volume;

   if(cur_exposure + lot > InpMaxExposureLots + 1e-6)
      return false;

   double margin_req = 0.0;
   if(!OrderCalcMargin(order_type, g_symbol, lot, price, margin_req))
      return false;

   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(free_margin <= margin_req)
      return false;

   g_order_pending = true;
   bool res = false;
   if(order_type == ORDER_TYPE_BUY)
      res = ExtTrade.Buy(lot, g_symbol, price, sl, tp, comment);
   else if(order_type == ORDER_TYPE_SELL)
      res = ExtTrade.Sell(lot, g_symbol, price, sl, tp, comment);

   if(!res)
   {
      g_order_pending = false;
      Print("[Vulcares Vx] Order rejected. Retcode: ", ExtTrade.ResultRetcode(), " - ", ExtTrade.ResultRetcodeDescription());
      return false;
   }
   return true;
}

bool ModifyPositionSL(ulong ticket, double new_sl, double tp)
{
   if(!ExtTrade.PositionModify(ticket, new_sl, tp))
   {
      uint rc = ExtTrade.ResultRetcode();
      if(rc != TRADE_RETCODE_NO_CHANGES)
         Print("[Vulcares Vx] SL Modify failed ticket ", ticket, " Retcode: ", rc);
      return false;
   }
   return true;
}

void CheckDailyReset()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != g_current_day)
   {
      g_current_day = dt.day_of_year;
      g_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_peak_equity       = AccountInfoDouble(ACCOUNT_EQUITY);
      if(g_state == STATE_RISK_LOCK && !g_emergency_stop)
         g_state = STATE_SCANNING;
   }
}

bool CheckRiskGuards()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > g_peak_equity)
      g_peak_equity = equity;

   if(InpMaxDailyLossPercent > 0.0 && g_day_start_balance > 0.0)
   {
      double daily_dd_pct = ((g_day_start_balance - equity) / g_day_start_balance) * 100.0;
      if(daily_dd_pct >= InpMaxDailyLossPercent)
         return false;
   }

   if(InpMaxEquityDDPercent > 0.0 && g_peak_equity > 0.0)
   {
      double eq_dd_pct = ((g_peak_equity - equity) / g_peak_equity) * 100.0;
      if(eq_dd_pct >= InpMaxEquityDDPercent)
         return false;
   }

   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin > 0.0)
   {
      double margin_level = (equity / margin) * 100.0;
      if(margin_level < InpMinFreeMarginPercent)
         return false;
   }

   return true;
}

void CloseAllEA_Positions(string reason)
{
   Print("[Vulcares Vx] Closing all EA positions: ", reason);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         if(PositionGetString(POSITION_SYMBOL) == g_symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
         {
            ExtTrade.PositionClose(ticket, InpMaxSlippagePoints);
         }
      }
   }
}

double CalculateLayerLot(int layer_index)
{
   double mult = MathPow(MathMax(0.1, InpLayerLotMultiplier), layer_index);
   return NormalizeLot(InpBaseLot * mult);
}

double NormalizeLot(double lot)
{
   double min_lot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(step_lot <= 0.0) step_lot = 0.01;
   double norm = MathFloor((lot + 1e-9) / step_lot) * step_lot;
   norm = MathMax(min_lot, MathMin(max_lot, norm));
   return NormalizeDouble(norm, 2);
}

double NormalizePrice(double price)
{
   double tick_size = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);
   if(tick_size > 0.0)
      return NormalizeDouble(MathRound(price / tick_size) * tick_size, digits);
   return NormalizeDouble(price, digits);
}

void DrawEntryMarker(ulong deal, double price, int deal_type)
{
   string name = g_prefix + "ENT_" + IntegerToString(deal);
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (deal_type == DEAL_TYPE_BUY) ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (deal_type == DEAL_TYPE_BUY) ? clrDodgerBlue : clrTomato);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void DrawExitMarker(ulong deal, double price, double profit)
{
   string name = g_prefix + "EXT_" + IntegerToString(deal);
   ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 251);
   ObjectSetInteger(0, name, OBJPROP_COLOR, (profit >= 0.0) ? clrLimeGreen : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}

void DrawTrailingLine(ulong ticket, double sl_price)
{
   string name = g_prefix + "TSL_" + IntegerToString(ticket);
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, sl_price);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrCrimson);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASHDOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
   else
   {
      ObjectSetDouble(0, name, OBJPROP_PRICE, sl_price);
   }
}

void CreateDashboard()
{
   int x = 14, y = 24, w = 295, h = 415;

   string bg = g_prefix + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'14,17,22');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_COLOR, C'48,54,61');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);

   CreateLabel("TITLE", x + 12, y + 10, "VULCARES VX v3.0  |  M15/M5 SWING", clrGold, 10, true);
   CreateLabel("SUB",   x + 12, y + 28, "M5 Pullback + RSI + 1:2.2 R:R Target", clrDarkGray, 8, false);

   string keys[] = {
      "EA Status:", "Trend (M15/M5):", "Signal Gate:", "M5 RSI (14):",
      "M5 ATR (Pts):", "Active Layers:", "Total Active Lot:", "Fixed SL ($10):",
      "Target TP (R:R):", "Floating P/L:", "Trailing Status:", "Tightest SL:",
      "Locked Profit:", "Current Spread:", "Daily P/L:", "Actual Win Rate:"
   };

   for(int i = 0; i < ArraySize(keys); i++)
   {
      int row_y = y + 52 + i * 19;
      CreateLabel("K_" + IntegerToString(i), x + 12,  row_y, keys[i], clrSilver, 8, false);
      CreateLabel("V_" + IntegerToString(i), x + 150, row_y, "--",    clrWhite,  8, true);
   }

   string btn = g_prefix + "BTN_ESTOP";
   ObjectCreate(0, btn, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, btn, OBJPROP_XDISTANCE, x + 12);
   ObjectSetInteger(0, btn, OBJPROP_YDISTANCE, y + h - 34);
   ObjectSetInteger(0, btn, OBJPROP_XSIZE, w - 24);
   ObjectSetInteger(0, btn, OBJPROP_YSIZE, 24);
   ObjectSetString(0, btn, OBJPROP_TEXT, "EMERGENCY STOP");
   ObjectSetInteger(0, btn, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, btn, OBJPROP_BGCOLOR, C'180,35,35');
   ObjectSetInteger(0, btn, OBJPROP_FONTSIZE, 8);
}

void CreateLabel(string suffix, int x, int y, string text, color clr, int font_size, bool bold)
{
   string name = g_prefix + suffix;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
}

void UpdateDashboard()
{
   double float_pl = 0.0, total_lot = 0.0, tight_sl = 0.0, locked_pl = 0.0;
   double point = ExtSym.Point();
   int digits = (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS);

   for(int i = 0; i < g_tracked_count; i++)
   {
      if(PositionSelectByTicket(g_tracked[i].ticket))
      {
         float_pl  += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         total_lot += g_tracked[i].volume;
         double sl  = PositionGetDouble(POSITION_SL);
         double op  = PositionGetDouble(POSITION_PRICE_OPEN);
         int ptype  = (int)PositionGetInteger(POSITION_TYPE);

         if(sl > 0.0)
         {
            if(tight_sl == 0.0) tight_sl = sl;
            else if(ptype == POSITION_TYPE_BUY && sl > tight_sl) tight_sl = sl;
            else if(ptype == POSITION_TYPE_SELL && sl < tight_sl) tight_sl = sl;

            if(point > 0.0)
            {
               if(ptype == POSITION_TYPE_BUY && sl > op) locked_pl += (sl - op) / point;
               else if(ptype == POSITION_TYPE_SELL && sl < op) locked_pl += (op - sl) / point;
            }
         }
      }
   }

   int sl_pts_10   = MoneyToPoints(InpStopLossMoney, InpBaseLot);
   int tp_pts      = (int)MathRound(sl_pts_10 * InpRiskRewardRatio);
   double daily_pl = AccountInfoDouble(ACCOUNT_EQUITY) - g_day_start_balance;
   long spread_pts = (point > 0.0) ? (long)MathRound((ExtSym.Ask() - ExtSym.Bid()) / point) : 0;

   int wins = 0, total_closed = 0;
   if(HistorySelect(0, TimeCurrent()))
   {
      int deals = HistoryDealsTotal();
      for(int d = 0; d < deals; d++)
      {
         ulong dticket = HistoryDealGetTicket(d);
         if(HistoryDealGetInteger(dticket, DEAL_MAGIC) == (long)InpMagicNumber &&
            HistoryDealGetInteger(dticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            total_closed++;
            if(HistoryDealGetDouble(dticket, DEAL_PROFIT) > 0.0) wins++;
         }
      }
   }
   double wr = (total_closed > 0) ? (100.0 * wins / total_closed) : 0.0;

   string state_str = EnumToString(g_state);
   StringReplace(state_str, "STATE_", "");

   SetVal(0, state_str, (g_state == STATE_RISK_LOCK || g_state == STATE_EMERGENCY_STOP) ? clrRed : clrLimeGreen);
   SetVal(1, g_macro_bias, (g_macro_bias == "UPTREND (M15/M5)") ? clrLime : (g_macro_bias == "DOWNTREND (M15/M5)" ? clrTomato : clrGray));
   SetVal(2, g_signal_status, clrGold);
   SetVal(3, DoubleToString(g_current_rsi_m5, 1), clrWhite);
   SetVal(4, DoubleToString(g_current_atr_pts, 0) + " pts", clrSilver);
   SetVal(5, IntegerToString(g_tracked_count) + " / " + IntegerToString(InpMaxLayers), clrWhite);
   SetVal(6, DoubleToString(total_lot, 2) + " lot", clrWhite);
   SetVal(7, DoubleToString(InpStopLossMoney, 0) + " " + AccountInfoString(ACCOUNT_CURRENCY) + " (" + IntegerToString(sl_pts_10) + " pts)", clrGold);
   SetVal(8, InpEnableTakeProfit ? (IntegerToString(tp_pts) + " pts (1:" + DoubleToString(InpRiskRewardRatio, 1) + ")") : "TRAILING ONLY", clrAqua);
   SetVal(9, DoubleToString(float_pl, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), (float_pl >= 0.0) ? clrLime : clrTomato);
   SetVal(10, (g_state == STATE_TRAILING_ACTIVE) ? "TRAILING LOCK" : ((g_tracked_count > 0) ? "ARMED" : "IDLE"), clrGold);
   SetVal(11, (tight_sl > 0.0) ? DoubleToString(tight_sl, digits) : "NONE", clrCrimson);
   SetVal(12, "+" + DoubleToString(locked_pl, 0) + " pts", (locked_pl > 0.0) ? clrLime : clrGray);
   SetVal(13, IntegerToString(spread_pts) + " pts", (spread_pts <= InpMaxSpreadPoints) ? clrSilver : clrRed);
   SetVal(14, DoubleToString(daily_pl, 2), (daily_pl >= 0.0) ? clrLime : clrTomato);
   SetVal(15, DoubleToString(wr, 1) + "% (" + IntegerToString(wins) + "/" + IntegerToString(total_closed) + ")", clrAqua);

   ChartRedraw(0);
}

void SetVal(int idx, string text, color clr)
{
   string name = g_prefix + "V_" + IntegerToString(idx);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}
//+------------------------------------------------------------------+
