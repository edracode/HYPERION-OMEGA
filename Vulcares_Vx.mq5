//+------------------------------------------------------------------+
//|                                                  Vulcares_Vx.mq5 |
//|     Structural Trend + Pullback Momentum + Safe Trailing EA      |
//|    No Premature Break-Even | No Micro-Chasing | Basket Trailing  |
//+------------------------------------------------------------------+
#property copyright "Vulcares Quantitative Engineering"
#property version   "2.00"
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

enum ENUM_TRAILING_MODE
{
   TRAIL_HIGH_WATERMARK = 0, // High-Watermark Real-Time Trailing
   TRAIL_ATR_ADAPTIVE   = 1  // ATR Volatility-Adaptive Trailing
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

enum ENUM_MARKET_REGIME
{
   REGIME_RANGING_CHOP = 0,
   REGIME_UPTREND_CLEAN,
   REGIME_DOWNTREND_CLEAN,
   REGIME_HIGH_VOLATILITY
};

//--- Input Parameters
input group "=== 1. GENERAL SETTINGS ==="
input bool                InpTradingEnabled       = true;                      // Trading Enabled
input bool                InpDemoOnly             = true;                      // Safety: Demo/Tester Only Mode
input ulong               InpMagicNumber          = 20260306;                  // Magic Number
input string              InpTradingSymbol        = "";                        // Trading Symbol (Empty = Current)
input ENUM_TIMEFRAMES     InpSignalTimeframe      = PERIOD_M1;                 // Execution Timeframe (M1)
input ENUM_TIMEFRAMES     InpTrendTimeframe       = PERIOD_M15;                // Macro Trend Filter Timeframe (M15)
input bool                InpEnableBuy            = true;                      // Enable BUY Engine
input bool                InpEnableSell           = true;                      // Enable SELL Engine
input ENUM_EXECUTION_MODE InpExecutionMode        = MODE_TREND_LAYERING;       // Execution Mode

input group "=== 2. ANTI-CHOP STRUCTURAL TREND & ENTRY FILTER ==="
input int                 InpFastEMAPeriod        = 21;                        // Fast EMA Period (M1 & M15)
input int                 InpSlowEMAPeriod        = 55;                        // Slow EMA Period (M1 & M15)
input int                 InpTrendEMAPeriod       = 200;                       // Macro Trend EMA Period (M15)
input int                 InpATRPeriod            = 14;                        // ATR Period (M1)
input int                 InpMinATRPoints         = 120;                       // Min M1 ATR to Trade (Skip Dead Chop)
input int                 InpMaxATRPoints         = 1500;                      // Max M1 ATR (Skip News Spikes)
input double              InpMaxEMADistATR        = 1.2;                       // Max Entry Distance from Fast EMA (in ATR)
input int                 InpMomentumWindowMs     = 3000;                      // Tick Confirmation Window (ms)
input double              InpTickVelocityThresh   = 12.0;                      // Min Tick Velocity in Trend Direction (pts/s)
input int                 InpMinCooldownSeconds   = 45;                        // Min Cooldown After Exit (Prevents Churn!)

input group "=== 3. TREND PYRAMIDING LAYERING SETTINGS ==="
input double              InpBaseLot              = 0.01;                      // Fixed Base Lot (0.01)
input bool                InpEnableTrendLayering  = true;                      // Enable Pyramiding Layering
input int                 InpMaxLayers            = 4;                         // Max Simultaneous Layers Per Direction
input int                 InpLayerStepPoints      = 400;                       // Min Favorable Step Between Layers (points)
input double              InpLayerLotMultiplier   = 1.0;                       // Layer Lot Multiplier (1.0 = Fixed 0.01)

input group "=== 4. STOP LOSS ($10 FLOOR) & WIDE BREATHING TRAILING ==="
input double              InpMinStopLossMoney     = 10.0;                      // Stop Loss Per Position ($10.00 USD/USC)
input int                 InpFallbackSLPoints     = 1000;                      // Fallback SL Points (1000 pts = $10 @ 0.01 lot)
input bool                InpEnableBreakEven      = false;                     // Enable Early Break-Even (False = No Choking!)
input int                 InpBreakEvenTriggerPts  = 600;                       // Break-Even Trigger if Enabled (points)
input int                 InpBreakEvenOffsetPts   = 50;                        // Break-Even Offset (points)
input bool                InpEnableTrailingStop   = true;                      // Enable Wide Breathing Trailing Stop
input ENUM_TRAILING_MODE  InpTrailingMode         = TRAIL_ATR_ADAPTIVE;        // Trailing Algorithm (ATR Adaptive)
input int                 InpTrailingStartPts     = 650;                       // Min Profit Before Trailing Starts (points)
input int                 InpTrailingDistancePts  = 500;                       // Base Trailing Distance (points)
input double              InpTrailingATRMult      = 2.2;                       // ATR Multiplier for Trailing Breathing Room
input int                 InpTrailingStepPts      = 25;                        // Min SL Step Modification (points)

input group "=== 5. SAFETY & RISK PROTECTION ==="
input int                 InpMaxSpreadPoints      = 300;                       // Max Allowed Spread (points)
input int                 InpMaxSlippagePoints    = 50;                        // Max Slippage (points)
input double              InpMaxDailyLossPercent  = 20.0;                      // Max Daily Loss (% Balance)
input double              InpMaxEquityDDPercent   = 30.0;                      // Max Equity Drawdown (% Peak)
input double              InpMaxExposureLots      = 0.10;                      // Max Total Exposure (Lots)
input double              InpMinFreeMarginPercent = 120.0;                     // Min Free Margin Level (%)

input group "=== 6. DASHBOARD & VISUALS ==="
input bool                InpShowDashboard        = true;                      // Show Dark Professional Dashboard
input bool                InpShowTradeVisuals     = true;                      // Show Entry/Exit Arrows & SL Lines

//--- Structs
struct TickSample
{
   long   time_msc;
   double bid;
   double ask;
};

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
ENUM_MARKET_REGIME g_regime = REGIME_RANGING_CHOP;
bool               g_emergency_stop = false;
bool               g_order_pending = false;
datetime           g_last_exit_time = 0;
datetime           g_last_entry_time = 0;
double             g_day_start_balance = 0.0;
double             g_peak_equity = 0.0;
int                g_current_day = -1;

// Indicator Handles
int                g_h_ema_fast_m1  = INVALID_HANDLE;
int                g_h_ema_slow_m1  = INVALID_HANDLE;
int                g_h_atr_m1       = INVALID_HANDLE;
int                g_h_ema_fast_m15 = INVALID_HANDLE;
int                g_h_ema_slow_m15 = INVALID_HANDLE;
int                g_h_ema_200_m15  = INVALID_HANDLE;

// Live metrics
double             g_velocity_pts_sec = 0.0;
double             g_current_atr_pts  = 0.0;
string             g_macro_bias       = "NEUTRAL";
string             g_signal_status    = "WAITING";

// Tick buffer
#define MAX_TICK_BUFFER 256
TickSample         g_ticks[MAX_TICK_BUFFER];
int                g_tick_count = 0;

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

   g_h_ema_fast_m1  = iMA(g_symbol, InpSignalTimeframe, InpFastEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_slow_m1  = iMA(g_symbol, InpSignalTimeframe, InpSlowEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_atr_m1       = iATR(g_symbol, InpSignalTimeframe, InpATRPeriod);
   g_h_ema_fast_m15 = iMA(g_symbol, InpTrendTimeframe,  InpFastEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_slow_m15 = iMA(g_symbol, InpTrendTimeframe,  InpSlowEMAPeriod,  0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_200_m15  = iMA(g_symbol, InpTrendTimeframe,  InpTrendEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);

   if(g_h_ema_fast_m1 == INVALID_HANDLE || g_h_ema_slow_m1 == INVALID_HANDLE || g_h_atr_m1 == INVALID_HANDLE ||
      g_h_ema_fast_m15 == INVALID_HANDLE || g_h_ema_slow_m15 == INVALID_HANDLE || g_h_ema_200_m15 == INVALID_HANDLE)
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

   EventSetMillisecondTimer(150);
   if(g_state != STATE_RISK_LOCK)
      g_state = STATE_SCANNING;

   Print("[Vulcares Vx] v2.00 Structural Trend + Pullback Momentum Initialized on ", g_symbol);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(g_h_ema_fast_m1);
   IndicatorRelease(g_h_ema_slow_m1);
   IndicatorRelease(g_h_atr_m1);
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

   PushTick(tick);

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

   ComputeTickVelocity(tick.time_msc);
   ReconcilePositions();

   // 1. Manage Open Positions with Wide Breathing Trailing Stop
   if(g_tracked_count > 0)
      ManageOpenPositions(tick);

   if(!InpTradingEnabled || g_state == STATE_RISK_LOCK || g_order_pending)
      return;

   // 2. Evaluate Structural Trend + Pullback Momentum Entry & Layering
   EvaluateStructuralEntryAndLayering(tick);

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
//| Convert $10 USD/USC to Points Using Safe FixedTickValue          |
//+------------------------------------------------------------------+
int MoneyToPoints(double money_amount, double lot)
{
   double point    = ExtSym.Point();
   double tick_val = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_sz  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);

   if(point > 0.0 && tick_val > 0.0 && tick_sz > 0.0 && lot > 0.0)
   {
      double pt_val_per_lot = tick_val * (point / tick_sz);
      double cost_per_point = pt_val_per_lot * lot;
      if(cost_per_point > 0.0)
         return (int)MathCeil(money_amount / cost_per_point);
   }
   return InpFallbackSLPoints;
}

//+------------------------------------------------------------------+
//| Structural Multi-Timeframe Trend & Pullback Entry Engine         |
//+------------------------------------------------------------------+
void EvaluateStructuralEntryAndLayering(const MqlTick &tick)
{
   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long spread_pts = (long)MathRound((tick.ask - tick.bid) / point);
   if(spread_pts > InpMaxSpreadPoints)
   {
      g_signal_status = "HIGH SPREAD";
      return;
   }

   // Read Multi-Timeframe Indicators
   double ema21_m1  = GetIndVal(g_h_ema_fast_m1, 0);
   double ema55_m1  = GetIndVal(g_h_ema_slow_m1, 0);
   double atr_m1    = GetIndVal(g_h_atr_m1, 1);

   double ema21_m15 = GetIndVal(g_h_ema_fast_m15, 0);
   double ema55_m15 = GetIndVal(g_h_ema_slow_m15, 0);
   double ema200_m15= GetIndVal(g_h_ema_200_m15, 0);

   if(ema21_m1 == 0.0 || ema55_m1 == 0.0 || atr_m1 == 0.0 || ema21_m15 == 0.0 || ema200_m15 == 0.0)
      return;

   g_current_atr_pts = atr_m1 / point;

   // Volatility Filter: Skip dead sideways chop AND extreme news spikes
   if(g_current_atr_pts < InpMinATRPoints)
   {
      g_regime = REGIME_RANGING_CHOP;
      g_signal_status = "LOW ATR CHOP";
      return;
   }
   if(g_current_atr_pts > InpMaxATRPoints)
   {
      g_regime = REGIME_HIGH_VOLATILITY;
      g_signal_status = "EXTREME SPIKE";
      return;
   }

   // Macro + Micro Trend Alignment
   bool macro_bull = (tick.bid > ema200_m15) && (ema21_m15 > ema55_m15);
   bool macro_bear = (tick.bid < ema200_m15) && (ema21_m15 < ema55_m15);

   bool micro_bull = (ema21_m1 > ema55_m1) && (tick.bid > ema21_m1);
   bool micro_bear = (ema21_m1 < ema55_m1) && (tick.bid < ema21_m1);

   if(macro_bull && micro_bull)
   {
      g_macro_bias = "STRONG BULL";
      g_regime = REGIME_UPTREND_CLEAN;
   }
   else if(macro_bear && micro_bear)
   {
      g_macro_bias = "STRONG BEAR";
      g_regime = REGIME_DOWNTREND_CLEAN;
   }
   else
   {
      g_macro_bias = "CHOP / MIXED";
      g_regime = REGIME_RANGING_CHOP;
      g_signal_status = "NO ALIGNMENT";
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

   // Anti-Churn Cooldown when flat
   datetime now = TimeCurrent();
   if(buy_layers == 0 && sell_layers == 0 && g_last_exit_time > 0)
   {
      if((now - g_last_exit_time) < InpMinCooldownSeconds)
      {
         g_signal_status = "COOLDOWN (" + IntegerToString((int)(InpMinCooldownSeconds - (now - g_last_exit_time))) + "s)";
         return;
      }
   }

   bool allow_layering = (InpExecutionMode == MODE_TREND_LAYERING && InpEnableTrendLayering);
   int max_allowed = allow_layering ? MathMax(1, InpMaxLayers) : 1;

   // Distance from Fast EMA (Anti-Chasing Overextension Filter)
   double dist_from_ema21 = MathAbs(tick.bid - ema21_m1);
   bool not_overextended = (dist_from_ema21 <= atr_m1 * InpMaxEMADistATR);

   // M1 Running Candle Confirmation
   double open0  = iOpen(g_symbol, InpSignalTimeframe, 0);
   double low0   = iLow(g_symbol, InpSignalTimeframe, 0);
   double high0  = iHigh(g_symbol, InpSignalTimeframe, 0);

   long stops_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);

   // =================================================================
   // BULLISH ENTRY & PYRAMIDING LAYERING (Trend Up + Pullback Bounce)
   // =================================================================
   if(InpEnableBuy && macro_bull && micro_bull && sell_layers == 0 && buy_layers < max_allowed)
   {
      bool candle_bullish = (tick.bid > open0) && (low0 <= ema21_m1 + atr_m1 * 0.5);
      bool tick_impulse   = (g_velocity_pts_sec >= InpTickVelocityThresh);

      if(buy_layers == 0)
      {
         if(not_overextended && candle_bullish && tick_impulse)
         {
            double lot = CalculateLayerLot(0);
            int sl_pts = (int)MathMax((double)(stops_level + 25), (double)MoneyToPoints(InpMinStopLossMoney, lot));
            double sl  = NormalizePrice(tick.ask - sl_pts * point);

            g_signal_status = "BUY TRIGGER";
            if(ExecuteMarketOrder(ORDER_TYPE_BUY, lot, tick.ask, sl, 0.0, "VulcaresVx_BUY_L1"))
            {
               g_last_entry_time = now;
               g_state = STATE_ENTRY_PENDING;
            }
         }
         else
         {
            g_signal_status = not_overextended ? "WAIT BOUNCE" : "OVEREXTENDED";
         }
      }
      else if(allow_layering)
      {
         double step_pts = (tick.ask - highest_buy_entry) / point;
         if(step_pts >= InpLayerStepPoints && tick_impulse && (now - g_last_entry_time) >= 15)
         {
            double lot = CalculateLayerLot(buy_layers);
            int sl_pts = (int)MathMax((double)(stops_level + 25), (double)MoneyToPoints(InpMinStopLossMoney, lot));
            double sl  = NormalizePrice(tick.ask - sl_pts * point);

            string cmt = "VulcaresVx_BUY_L" + IntegerToString(buy_layers + 1);
            if(ExecuteMarketOrder(ORDER_TYPE_BUY, lot, tick.ask, sl, 0.0, cmt))
            {
               g_last_entry_time = now;
               g_state = STATE_LAYERING_ACTIVE;
            }
         }
      }
   }

   // =================================================================
   // BEARISH ENTRY & PYRAMIDING LAYERING (Trend Down + Pullback Drop)
   // =================================================================
   if(InpEnableSell && macro_bear && micro_bear && buy_layers == 0 && sell_layers < max_allowed)
   {
      bool candle_bearish = (tick.bid < open0) && (high0 >= ema21_m1 - atr_m1 * 0.5);
      bool tick_impulse   = (-g_velocity_pts_sec >= InpTickVelocityThresh);

      if(sell_layers == 0)
      {
         if(not_overextended && candle_bearish && tick_impulse)
         {
            double lot = CalculateLayerLot(0);
            int sl_pts = (int)MathMax((double)(stops_level + 25), (double)MoneyToPoints(InpMinStopLossMoney, lot));
            double sl  = NormalizePrice(tick.bid + sl_pts * point);

            g_signal_status = "SELL TRIGGER";
            if(ExecuteMarketOrder(ORDER_TYPE_SELL, lot, tick.bid, sl, 0.0, "VulcaresVx_SELL_L1"))
            {
               g_last_entry_time = now;
               g_state = STATE_ENTRY_PENDING;
            }
         }
         else
         {
            g_signal_status = not_overextended ? "WAIT PULLBACK" : "OVEREXTENDED";
         }
      }
      else if(allow_layering)
      {
         double step_pts = (lowest_sell_entry - tick.bid) / point;
         if(step_pts >= InpLayerStepPoints && tick_impulse && (now - g_last_entry_time) >= 15)
         {
            double lot = CalculateLayerLot(sell_layers);
            int sl_pts = (int)MathMax((double)(stops_level + 25), (double)MoneyToPoints(InpMinStopLossMoney, lot));
            double sl  = NormalizePrice(tick.bid + sl_pts * point);

            string cmt = "VulcaresVx_SELL_L" + IntegerToString(sell_layers + 1);
            if(ExecuteMarketOrder(ORDER_TYPE_SELL, lot, tick.bid, sl, 0.0, cmt))
            {
               g_last_entry_time = now;
               g_state = STATE_LAYERING_ACTIVE;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Wide Breathing Trailing Stop Engine (Lets Winners Run!)          |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlTick &tick)
{
   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long stops_level  = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_stop_dist = MathMax((double)stops_level, 15.0) * point;
   double freeze_dist   = (double)freeze_level * point;

   double trail_dist_pts = (double)InpTrailingDistancePts;
   if(InpTrailingMode == TRAIL_ATR_ADAPTIVE && g_current_atr_pts > 0.0)
   {
      trail_dist_pts = MathMax((double)InpTrailingDistancePts, g_current_atr_pts * InpTrailingATRMult);
   }

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
         double candidate_sl    = current_sl;

         if(InpEnableBreakEven && peak_profit_pts >= InpBreakEvenTriggerPts)
         {
            double be_sl = NormalizePrice(open_price + InpBreakEvenOffsetPts * point);
            if(candidate_sl == 0.0 || be_sl > candidate_sl)
               candidate_sl = be_sl;
         }

         if(InpEnableTrailingStop && peak_profit_pts >= InpTrailingStartPts)
         {
            double trail_sl = NormalizePrice(g_tracked[i].highest_bid - trail_dist_pts * point);
            if(candidate_sl == 0.0 || trail_sl > candidate_sl)
            {
               candidate_sl = trail_sl;
               g_state = STATE_TRAILING_ACTIVE;
            }
         }

         bool sl_improved = (current_sl == 0.0 && candidate_sl > 0.0) ||
                            (candidate_sl >= current_sl + InpTrailingStepPts * point);

         if(sl_improved && candidate_sl > 0.0)
         {
            if((tick.bid - candidate_sl) >= min_stop_dist &&
               (current_sl == 0.0 || MathAbs(tick.bid - current_sl) > freeze_dist))
            {
               if(ModifyPositionSL(ticket, candidate_sl, current_tp))
               {
                  g_tracked[i].current_sl = candidate_sl;
                  if(InpShowTradeVisuals)
                     DrawTrailingLine(ticket, candidate_sl);
               }
            }
         }
      }
      else if(pos_type == POSITION_TYPE_SELL)
      {
         if(tick.ask < g_tracked[i].lowest_ask || g_tracked[i].lowest_ask == 0.0)
            g_tracked[i].lowest_ask = tick.ask;

         double peak_profit_pts = (open_price - g_tracked[i].lowest_ask) / point;
         double candidate_sl    = current_sl;

         if(InpEnableBreakEven && peak_profit_pts >= InpBreakEvenTriggerPts)
         {
            double be_sl = NormalizePrice(open_price - InpBreakEvenOffsetPts * point);
            if(candidate_sl == 0.0 || be_sl < candidate_sl)
               candidate_sl = be_sl;
         }

         if(InpEnableTrailingStop && peak_profit_pts >= InpTrailingStartPts)
         {
            double trail_sl = NormalizePrice(g_tracked[i].lowest_ask + trail_dist_pts * point);
            if(candidate_sl == 0.0 || trail_sl < candidate_sl)
            {
               candidate_sl = trail_sl;
               g_state = STATE_TRAILING_ACTIVE;
            }
         }

         bool sl_improved = (current_sl == 0.0 && candidate_sl > 0.0) ||
                            (candidate_sl <= current_sl - InpTrailingStepPts * point);

         if(sl_improved && candidate_sl > 0.0)
         {
            if((candidate_sl - tick.ask) >= min_stop_dist &&
               (current_sl == 0.0 || MathAbs(current_sl - tick.ask) > freeze_dist))
            {
               if(ModifyPositionSL(ticket, candidate_sl, current_tp))
               {
                  g_tracked[i].current_sl = candidate_sl;
                  if(InpShowTradeVisuals)
                     DrawTrailingLine(ticket, candidate_sl);
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

//+------------------------------------------------------------------+
//| Push Tick & Compute Net Velocity                                 |
//+------------------------------------------------------------------+
void PushTick(const MqlTick &tick)
{
   if(g_tick_count < MAX_TICK_BUFFER)
   {
      g_ticks[g_tick_count].time_msc = tick.time_msc;
      g_ticks[g_tick_count].bid      = tick.bid;
      g_ticks[g_tick_count].ask      = tick.ask;
      g_tick_count++;
   }
   else
   {
      for(int i = 1; i < MAX_TICK_BUFFER; i++)
         g_ticks[i - 1] = g_ticks[i];

      g_ticks[MAX_TICK_BUFFER - 1].time_msc = tick.time_msc;
      g_ticks[MAX_TICK_BUFFER - 1].bid      = tick.bid;
      g_ticks[MAX_TICK_BUFFER - 1].ask      = tick.ask;
   }
}

void ComputeTickVelocity(long now_msc)
{
   g_velocity_pts_sec = 0.0;
   if(g_tick_count < 3) return;

   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long window_start = now_msc - InpMomentumWindowMs;
   int first_idx = -1;
   int last_idx  = g_tick_count - 1;

   for(int i = 0; i < g_tick_count; i++)
   {
      if(g_ticks[i].time_msc >= window_start)
      {
         first_idx = i;
         break;
      }
   }

   if(first_idx == -1 || first_idx >= last_idx) return;

   double dt = (double)(g_ticks[last_idx].time_msc - g_ticks[first_idx].time_msc) / 1000.0;
   if(dt <= 0.05) dt = 0.05;

   g_velocity_pts_sec = ((g_ticks[last_idx].bid - g_ticks[first_idx].bid) / point) / dt;
}

//+------------------------------------------------------------------+
//| Reconcile Active Positions                                       |
//+------------------------------------------------------------------+
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

   CreateLabel("TITLE", x + 12, y + 10, "VULCARES VX v2.0  |  STRUCTURAL", clrGold, 10, true);
   CreateLabel("SUB",   x + 12, y + 28, "MTF EMA Trend + Pullback + Wide Trail", clrDarkGray, 8, false);

   string keys[] = {
      "EA Status:", "Market Regime:", "Macro M15 Bias:", "Signal Gate:",
      "Tick Velocity:", "M1 ATR (Pts):", "Active Layers:", "Total Active Lot:",
      "SL ($10 Floor):", "Floating P/L:", "Trailing Status:", "Tightest SL:",
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

   int sl_pts_10   = MoneyToPoints(InpMinStopLossMoney, InpBaseLot);
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
   string reg_str = EnumToString(g_regime);
   StringReplace(reg_str, "REGIME_", "");

   SetVal(0, state_str, (g_state == STATE_RISK_LOCK || g_state == STATE_EMERGENCY_STOP) ? clrRed : clrLimeGreen);
   SetVal(1, reg_str, clrDeepSkyBlue);
   SetVal(2, g_macro_bias, (g_macro_bias == "STRONG BULL") ? clrLime : (g_macro_bias == "STRONG BEAR" ? clrTomato : clrGray));
   SetVal(3, g_signal_status, clrGold);
   SetVal(4, DoubleToString(g_velocity_pts_sec, 1) + " pts/s", clrWhite);
   SetVal(5, DoubleToString(g_current_atr_pts, 0) + " pts", clrSilver);
   SetVal(6, IntegerToString(g_tracked_count) + " / " + IntegerToString(InpMaxLayers), clrWhite);
   SetVal(7, DoubleToString(total_lot, 2) + " lot", clrWhite);
   SetVal(8, DoubleToString(InpMinStopLossMoney, 0) + " " + AccountInfoString(ACCOUNT_CURRENCY) + " (" + IntegerToString(sl_pts_10) + " pts)", clrGold);
   SetVal(9, DoubleToString(float_pl, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY), (float_pl >= 0.0) ? clrLime : clrTomato);
   SetVal(10, (g_state == STATE_TRAILING_ACTIVE) ? "ATR TRAILING" : ((g_tracked_count > 0) ? "ARMED" : "IDLE"), clrGold);
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
