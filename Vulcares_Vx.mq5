//+------------------------------------------------------------------+
//|                                                  Vulcares_Vx.mq5 |
//|           Pyramiding / Trend-Following Layering Momentum EA       |
//|     Min $10 (USD/USC) Stop Loss Floor + Trend Layering + Trail   |
//+------------------------------------------------------------------+
#property copyright "Vulcares Quantitative Engineering"
#property version   "1.50"
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

enum ENUM_SL_MODE
{
   SL_PERCENT_OF_PRICE   = 0, // 1.0% Price Distance (Enforced Min $10 USD/USC Floor)
   SL_PERCENT_OF_BALANCE = 1, // 1.0% Balance Risk (Enforced Min $10 USD/USC Floor)
   SL_FIXED_MONEY_ONLY   = 2  // Strict Fixed Money SL ($10 USD/USC per Position)
};

enum ENUM_TRAILING_MODE
{
   TRAIL_HIGH_WATERMARK = 0, // High-Watermark Real-Time Tick Trailing
   TRAIL_STEP_BASED     = 1, // Step-Based Trailing
   TRAIL_ATR_ADAPTIVE   = 2  // Volatility/ATR Adaptive Trailing
};

enum ENUM_EA_STATE
{
   STATE_INITIALIZING = 0,
   STATE_SCANNING,
   STATE_SIGNAL_READY,
   STATE_ENTRY_PENDING,
   STATE_POSITION_ACTIVE,
   STATE_LAYERING_ACTIVE,
   STATE_BREAK_EVEN_ACTIVE,
   STATE_TRAILING_ACTIVE,
   STATE_RE_ENTRY_SCANNING,
   STATE_RISK_LOCK,
   STATE_DISCONNECTED,
   STATE_EMERGENCY_STOP
};

enum ENUM_MARKET_REGIME
{
   REGIME_DORMANT = 0,
   REGIME_LOW_VOLATILITY,
   REGIME_NORMAL_VOLATILITY,
   REGIME_HIGH_VOLATILITY,
   REGIME_EXTREME_VOLATILITY,
   REGIME_IMPULSE_BREAKOUT
};

//--- Input Parameters
input group "=== 1. GENERAL SETTINGS ==="
input bool                InpTradingEnabled       = true;                      // Trading Enabled
input bool                InpDemoOnly             = true;                      // Safety: Demo/Tester Only Mode
input ulong               InpMagicNumber          = 20260306;                  // Magic Number
input string              InpTradingSymbol        = "";                        // Trading Symbol (Empty = Current)
input ENUM_TIMEFRAMES     InpSignalTimeframe      = PERIOD_M1;                 // Signal Timeframe (M1)
input bool                InpEnableBuy            = true;                      // Enable BUY Engine
input bool                InpEnableSell           = true;                      // Enable SELL Engine
input ENUM_EXECUTION_MODE InpExecutionMode        = MODE_TREND_LAYERING;       // Execution Mode (Trend Layering)

input group "=== 2. REAL-TIME MOMENTUM & ENTRY SETTINGS ==="
input int                 InpMomentumWindowMs     = 2000;                      // Momentum Window (ms)
input double              InpTickVelocityThresh   = 15.0;                      // Min Tick Velocity (points/sec)
input double              InpAccelerationThresh   = 5.0;                       // Min Tick Acceleration (points/sec^2)
input double              InpTickConsistencyMin   = 0.65;                      // Min Directional Tick Ratio (0.0-1.0)
input int                 InpBreakoutLookbackBars = 3;                         // Micro Breakout Lookback (M1 Bars)
input double              InpBreakoutSensitivity  = 0.5;                       // Micro Breakout Offset (points)
input double              InpEntryConfidenceMin   = 70.0;                      // Min Entry Confidence Score (0-100)
input bool                InpEnableIntrabarEntry  = true;                      // Allow Intrabar Execution

input group "=== 3. TREND PYRAMIDING LAYERING SETTINGS ==="
input double              InpBaseLot              = 0.01;                      // Fixed Base Lot (0.01)
input bool                InpAutoLotMode          = false;                     // Auto Lot Mode (False = Fixed 0.01)
input double              InpRiskPercentPerTrade  = 1.0;                       // Risk % if AutoLotMode = true
input bool                InpEnableTrendLayering  = true;                      // Enable Pyramiding Layering (Up=BUY, Down=SELL)
input int                 InpMaxLayers            = 5;                         // Max Simultaneous Layers Per Direction
input int                 InpLayerStepPoints      = 250;                       // Min Favorable Distance to Add Layer (points)
input double              InpLayerLotMultiplier   = 1.0;                       // Layer Lot Multiplier (1.0 = Fixed 0.01 per layer)
input bool                InpRequireProfitForLayer= true;                      // Require Previous Layer in Profit

input group "=== 4. STOP LOSS (MIN $10 USD/USC) & TRAILING STOP ==="
input ENUM_SL_MODE        InpStopLossMode         = SL_PERCENT_OF_PRICE;       // Stop Loss Mode
input double              InpStopLossPercent      = 1.0;                       // Stop Loss Percentage (1.0%)
input double              InpMinStopLossMoney     = 10.0;                      // Minimum Stop Loss Floor ($10.00 USD/USC)
input int                 InpFallbackSLPoints     = 1000;                      // Fallback SL Points (1000 pts = $10 @ 0.01 lot)
input bool                InpEnableBreakEven      = true;                      // Enable Break-Even Stage
input int                 InpBreakEvenTriggerPts  = 350;                       // Break-Even Trigger (points)
input int                 InpBreakEvenOffsetPts   = 50;                        // Break-Even Lock Offset (points)
input bool                InpEnableTrailingStop   = true;                      // Enable Ultra-Responsive Trailing Stop
input ENUM_TRAILING_MODE  InpTrailingMode         = TRAIL_HIGH_WATERMARK;      // Trailing Stop Algorithm
input int                 InpTrailingStartPts     = 450;                       // Trailing Activation Profit (points)
input int                 InpTrailingDistancePts  = 400;                       // Trailing Distance from Peak (points)
input int                 InpTrailingStepPts      = 10;                        // Min SL Modification Step (points)
input bool                InpEnableAdaptiveTrail  = true;                      // Volatility-Adaptive Trailing Tightening
input bool                InpEnableFixedTP        = false;                     // Enable Fixed TP (False = Let Trailing Run)
input int                 InpFixedTPPoints        = 0;                         // Fixed TP Points (0 = Disabled)

input group "=== 5. RAPID RE-ENTRY SETTINGS ==="
input bool                InpEnableRapidReentry   = true;                      // Enable Rapid Re-Entry After Trailing Exit
input int                 InpReentryDelayMs       = 250;                       // Re-entry Cooldown (milliseconds)

input group "=== 6. SAFETY & RISK PROTECTION ==="
input int                 InpMaxSpreadPoints      = 350;                       // Max Allowed Spread (points)
input int                 InpMaxSlippagePoints    = 50;                        // Max Slippage (points)
input double              InpMaxDailyLossPercent  = 25.0;                      // Max Daily Loss (% Balance)
input double              InpMaxEquityDDPercent   = 35.0;                      // Max Equity Drawdown (% Peak)
input double              InpMaxExposureLots      = 0.10;                      // Max Total Exposure (Lots)
input double              InpMinFreeMarginPercent = 120.0;                     // Min Free Margin Level (%)
input int                 InpMaxConsecutiveLosses = 0;                         // Max Consecutive Losses (0 = Disabled)

input group "=== 7. DASHBOARD & VISUALS ==="
input bool                InpShowDashboard        = true;                      // Show Dark Professional Dashboard
input bool                InpShowTradeVisuals     = true;                      // Show Entry/Exit Arrows & SL Lines

//--- Structs
struct TickSample
{
   long   time_msc;
   double bid;
   double ask;
   long   volume;
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
ENUM_MARKET_REGIME g_regime = REGIME_NORMAL_VOLATILITY;
bool               g_emergency_stop = false;
bool               g_order_pending = false;
long               g_last_exit_time_msc = 0;
long               g_last_entry_time_msc = 0;
double             g_day_start_balance = 0.0;
double             g_peak_equity = 0.0;
int                g_current_day = -1;
int                g_consec_losses = 0;

// Momentum metrics
double             g_velocity_pts_sec = 0.0;
double             g_accel_pts_sec2   = 0.0;
double             g_tick_consistency = 0.0;
double             g_buy_confidence   = 0.0;
double             g_sell_confidence  = 0.0;
string             g_momentum_dir     = "NEUTRAL";

// Tick ring buffer
#define MAX_TICK_BUFFER 512
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

   EventSetMillisecondTimer(100);
   if(g_state != STATE_RISK_LOCK)
      g_state = STATE_SCANNING;

   Print("[Vulcares Vx] Initialized v1.50 | Min SL Floor: ", InpMinStopLossMoney, " ", AccountInfoString(ACCOUNT_CURRENCY));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
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

   AnalyzeMarketRegime();
   ComputeTickMomentum(tick.time_msc);

   ReconcilePositions();

   if(g_tracked_count > 0)
      ManageOpenPositions(tick);

   if(!InpTradingEnabled || g_state == STATE_RISK_LOCK || g_order_pending)
      return;

   if(g_last_exit_time_msc > 0 && (tick.time_msc - g_last_exit_time_msc) < InpReentryDelayMs)
      return;

   if(g_last_entry_time_msc > 0 && (tick.time_msc - g_last_entry_time_msc) < InpReentryDelayMs)
      return;

   EvaluateEntryAndLayering(tick);

   if(InpShowDashboard && MQLInfoInteger(MQL_VISUAL_MODE))
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Convert Currency Amount ($10 USD/USC) to Points for Given Lot    |
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
//| Calculate Dynamic Stop Loss with Strict Min $10 (USD/USC) Floor  |
//+------------------------------------------------------------------+
int ComputeDynamicSLPoints(double reference_price, double lot)
{
   double point = ExtSym.Point();
   if(point <= 0.0) return InpFallbackSLPoints;

   long stops_level   = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int min_broker_pts = (int)(stops_level + 25);

   // Strict $10.00 (USD or USC) minimum stop loss floor in points
   int min_money_sl_pts = (InpMinStopLossMoney > 0.0) ? MoneyToPoints(InpMinStopLossMoney, lot) : 0;

   int mode_sl_pts = min_money_sl_pts;

   if(InpStopLossMode == SL_PERCENT_OF_PRICE)
   {
      double sl_price_dist = reference_price * (InpStopLossPercent / 100.0);
      mode_sl_pts = (int)MathRound(sl_price_dist / point);
   }
   else if(InpStopLossMode == SL_PERCENT_OF_BALANCE)
   {
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_money = balance * (InpStopLossPercent / 100.0);
      mode_sl_pts = MoneyToPoints(risk_money, lot);
   }
   else if(InpStopLossMode == SL_FIXED_MONEY_ONLY)
   {
      mode_sl_pts = min_money_sl_pts;
   }

   // Enforce that SL distance is NEVER smaller than $10 (USD/USC) equivalent or broker stops_level
   int final_sl_pts = MathMax(mode_sl_pts, min_money_sl_pts);
   return MathMax(min_broker_pts, final_sl_pts);
}

//+------------------------------------------------------------------+
//| Evaluate Initial Entry & Trend-Following Pyramiding Layering     |
//+------------------------------------------------------------------+
void EvaluateEntryAndLayering(const MqlTick &tick)
{
   double point = ExtSym.Point();
   long spread_pts = (long)MathRound((tick.ask - tick.bid) / point);
   if(spread_pts > InpMaxSpreadPoints)
      return;

   long stops_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);

   int buy_layers = 0, sell_layers = 0;
   double highest_buy_entry = -DBL_MAX;
   double lowest_sell_entry = DBL_MAX;
   double lowest_buy_sl     = DBL_MAX;
   double highest_sell_sl   = 0.0;

   for(int i = 0; i < g_tracked_count; i++)
   {
      if(g_tracked[i].type == POSITION_TYPE_BUY)
      {
         buy_layers++;
         if(g_tracked[i].open_price > highest_buy_entry)
            highest_buy_entry = g_tracked[i].open_price;
         if(g_tracked[i].current_sl > 0.0 && g_tracked[i].current_sl < lowest_buy_sl)
            lowest_buy_sl = g_tracked[i].current_sl;
      }
      else if(g_tracked[i].type == POSITION_TYPE_SELL)
      {
         sell_layers++;
         if(g_tracked[i].open_price < lowest_sell_entry)
            lowest_sell_entry = g_tracked[i].open_price;
         if(g_tracked[i].current_sl > highest_sell_sl)
            highest_sell_sl = g_tracked[i].current_sl;
      }
   }

   bool allow_layering = (InpExecutionMode == MODE_TREND_LAYERING && InpEnableTrendLayering);
   int max_allowed = allow_layering ? MathMax(1, InpMaxLayers) : 1;

   // --- BULLISH MOMENTUM (NAIK -> OPEN BUY / LAYER BUY) ---
   if(InpEnableBuy && sell_layers == 0 && buy_layers < max_allowed)
   {
      bool bullish_signal = (g_buy_confidence >= InpEntryConfidenceMin && g_velocity_pts_sec >= InpTickVelocityThresh);
      if(bullish_signal)
      {
         if(buy_layers == 0)
         {
            double lot    = CalculateLayerLot(0);
            int sl_pts    = ComputeDynamicSLPoints(tick.ask, lot);
            double sl     = (sl_pts > 0) ? NormalizePrice(tick.ask - sl_pts * point) : 0.0;
            double tp     = (InpEnableFixedTP && InpFixedTPPoints > 0) ? NormalizePrice(tick.ask + InpFixedTPPoints * point) : 0.0;

            if(ExecuteMarketOrder(ORDER_TYPE_BUY, lot, tick.ask, sl, tp, "VulcaresVx_BUY_L1"))
            {
               g_last_entry_time_msc = tick.time_msc;
               g_state = STATE_ENTRY_PENDING;
            }
         }
         else if(allow_layering)
         {
            double step_dist_pts = (tick.ask - highest_buy_entry) / point;
            bool profit_ok = (!InpRequireProfitForLayer) || (tick.bid > highest_buy_entry);

            if(step_dist_pts >= InpLayerStepPoints && profit_ok)
            {
               double lot    = CalculateLayerLot(buy_layers);
               int sl_pts    = ComputeDynamicSLPoints(tick.ask, lot);
               double sl     = (sl_pts > 0) ? NormalizePrice(tick.ask - sl_pts * point) : 0.0;
               if(lowest_buy_sl < DBL_MAX && lowest_buy_sl > sl && (tick.bid - lowest_buy_sl) >= (stops_level + 15) * point)
                  sl = lowest_buy_sl;

               string cmt = "VulcaresVx_BUY_L" + IntegerToString(buy_layers + 1);
               if(ExecuteMarketOrder(ORDER_TYPE_BUY, lot, tick.ask, sl, 0.0, cmt))
               {
                  g_last_entry_time_msc = tick.time_msc;
                  g_state = STATE_LAYERING_ACTIVE;
               }
            }
         }
      }
   }

   // --- BEARISH MOMENTUM (TURUN -> OPEN SELL / LAYER SELL) ---
   if(InpEnableSell && buy_layers == 0 && sell_layers < max_allowed)
   {
      bool bearish_signal = (g_sell_confidence >= InpEntryConfidenceMin && -g_velocity_pts_sec >= InpTickVelocityThresh);
      if(bearish_signal)
      {
         if(sell_layers == 0)
         {
            double lot    = CalculateLayerLot(0);
            int sl_pts    = ComputeDynamicSLPoints(tick.bid, lot);
            double sl     = (sl_pts > 0) ? NormalizePrice(tick.bid + sl_pts * point) : 0.0;
            double tp     = (InpEnableFixedTP && InpFixedTPPoints > 0) ? NormalizePrice(tick.bid - InpFixedTPPoints * point) : 0.0;

            if(ExecuteMarketOrder(ORDER_TYPE_SELL, lot, tick.bid, sl, tp, "VulcaresVx_SELL_L1"))
            {
               g_last_entry_time_msc = tick.time_msc;
               g_state = STATE_ENTRY_PENDING;
            }
         }
         else if(allow_layering)
         {
            double step_dist_pts = (lowest_sell_entry - tick.bid) / point;
            bool profit_ok = (!InpRequireProfitForLayer) || (tick.ask < lowest_sell_entry);

            if(step_dist_pts >= InpLayerStepPoints && profit_ok)
            {
               double lot    = CalculateLayerLot(sell_layers);
               int sl_pts    = ComputeDynamicSLPoints(tick.bid, lot);
               double sl     = (sl_pts > 0) ? NormalizePrice(tick.bid + sl_pts * point) : 0.0;
               if(highest_sell_sl > 0.0 && highest_sell_sl < sl && (highest_sell_sl - tick.ask) >= (stops_level + 15) * point)
                  sl = highest_sell_sl;

               string cmt = "VulcaresVx_SELL_L" + IntegerToString(sell_layers + 1);
               if(ExecuteMarketOrder(ORDER_TYPE_SELL, lot, tick.bid, sl, 0.0, cmt))
               {
                  g_last_entry_time_msc = tick.time_msc;
                  g_state = STATE_LAYERING_ACTIVE;
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
               if(profit < 0.0)
                  g_consec_losses++;
               else if(profit > 0.0)
                  g_consec_losses = 0;

               g_last_exit_time_msc = (long)TimeCurrent() * 1000;
               g_state = STATE_RE_ENTRY_SCANNING;

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
            g_consec_losses = 0;
            g_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
            g_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
            g_state = STATE_SCANNING;
         }
         UpdateDashboard();
      }
   }
}

//+------------------------------------------------------------------+
//| Push Tick into Circular Buffer                                   |
//+------------------------------------------------------------------+
void PushTick(const MqlTick &tick)
{
   if(g_tick_count < MAX_TICK_BUFFER)
   {
      g_ticks[g_tick_count].time_msc = tick.time_msc;
      g_ticks[g_tick_count].bid      = tick.bid;
      g_ticks[g_tick_count].ask      = tick.ask;
      g_ticks[g_tick_count].volume   = (long)tick.volume;
      g_tick_count++;
   }
   else
   {
      for(int i = 1; i < MAX_TICK_BUFFER; i++)
         g_ticks[i - 1] = g_ticks[i];

      g_ticks[MAX_TICK_BUFFER - 1].time_msc = tick.time_msc;
      g_ticks[MAX_TICK_BUFFER - 1].bid      = tick.bid;
      g_ticks[MAX_TICK_BUFFER - 1].ask      = tick.ask;
      g_ticks[MAX_TICK_BUFFER - 1].volume   = (long)tick.volume;
   }
}

//+------------------------------------------------------------------+
//| Real-Time Multi-Window Tick Momentum & Confidence Engine         |
//+------------------------------------------------------------------+
void ComputeTickMomentum(long now_msc)
{
   g_velocity_pts_sec = 0.0;
   g_accel_pts_sec2   = 0.0;
   g_tick_consistency = 0.0;
   g_buy_confidence   = 0.0;
   g_sell_confidence  = 0.0;

   if(g_tick_count < 4)
      return;

   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long window_start = now_msc - InpMomentumWindowMs;
   long half_window  = now_msc - (InpMomentumWindowMs / 2);

   int first_idx = -1;
   int mid_idx   = -1;
   int last_idx  = g_tick_count - 1;

   int up_ticks = 0;
   int down_ticks = 0;

   for(int i = 0; i < g_tick_count; i++)
   {
      if(g_ticks[i].time_msc >= window_start)
      {
         if(first_idx == -1) first_idx = i;
         if(mid_idx == -1 && g_ticks[i].time_msc >= half_window) mid_idx = i;

         if(i > first_idx)
         {
            double diff = g_ticks[i].bid - g_ticks[i - 1].bid;
            if(diff > 0.0) up_ticks++;
            else if(diff < 0.0) down_ticks++;
         }
      }
   }

   if(first_idx == -1 || first_idx >= last_idx)
      return;

   double dt_total = (double)(g_ticks[last_idx].time_msc - g_ticks[first_idx].time_msc) / 1000.0;
   if(dt_total <= 0.05) dt_total = 0.05;

   double net_pts = (g_ticks[last_idx].bid - g_ticks[first_idx].bid) / point;
   g_velocity_pts_sec = net_pts / dt_total;

   if(mid_idx > first_idx && mid_idx < last_idx)
   {
      double dt1 = MathMax(0.025, (double)(g_ticks[mid_idx].time_msc - g_ticks[first_idx].time_msc) / 1000.0);
      double dt2 = MathMax(0.025, (double)(g_ticks[last_idx].time_msc - g_ticks[mid_idx].time_msc) / 1000.0);
      double v1  = ((g_ticks[mid_idx].bid - g_ticks[first_idx].bid) / point) / dt1;
      double v2  = ((g_ticks[last_idx].bid - g_ticks[mid_idx].bid) / point) / dt2;
      g_accel_pts_sec2 = (v2 - v1) / ((dt1 + dt2) * 0.5);
   }

   int total_moves = up_ticks + down_ticks;
   double bull_ratio = (total_moves > 0) ? (double)up_ticks / total_moves : 0.0;
   double bear_ratio = (total_moves > 0) ? (double)down_ticks / total_moves : 0.0;

   double open0  = iOpen(g_symbol, InpSignalTimeframe, 0);
   double close0 = g_ticks[last_idx].bid;

   double highest_prev = -DBL_MAX;
   double lowest_prev  = DBL_MAX;
   for(int b = 1; b <= InpBreakoutLookbackBars; b++)
   {
      highest_prev = MathMax(highest_prev, iHigh(g_symbol, InpSignalTimeframe, b));
      lowest_prev  = MathMin(lowest_prev,  iLow(g_symbol, InpSignalTimeframe, b));
   }

   // BUY Confidence Calculation (0 - 100)
   double buy_score = 0.0;
   if(g_velocity_pts_sec >= InpTickVelocityThresh)
      buy_score += MathMin(35.0, (g_velocity_pts_sec / InpTickVelocityThresh) * 20.0);
   if(g_accel_pts_sec2 >= InpAccelerationThresh)
      buy_score += MathMin(20.0, (g_accel_pts_sec2 / MathMax(1.0, InpAccelerationThresh)) * 12.0);
   if(bull_ratio >= InpTickConsistencyMin)
      buy_score += 20.0 * bull_ratio;
   if(close0 > open0)
      buy_score += 10.0;
   if(close0 > highest_prev - InpBreakoutSensitivity * point)
      buy_score += 15.0;

   // SELL Confidence Calculation (0 - 100)
   double sell_score = 0.0;
   if(-g_velocity_pts_sec >= InpTickVelocityThresh)
      sell_score += MathMin(35.0, (-g_velocity_pts_sec / InpTickVelocityThresh) * 20.0);
   if(-g_accel_pts_sec2 >= InpAccelerationThresh)
      sell_score += MathMin(20.0, (-g_accel_pts_sec2 / MathMax(1.0, InpAccelerationThresh)) * 12.0);
   if(bear_ratio >= InpTickConsistencyMin)
      sell_score += 20.0 * bear_ratio;
   if(close0 < open0)
      sell_score += 10.0;
   if(close0 < lowest_prev + InpBreakoutSensitivity * point)
      sell_score += 15.0;

   g_buy_confidence  = MathMin(100.0, buy_score);
   g_sell_confidence = MathMin(100.0, sell_score);

   if(g_buy_confidence > g_sell_confidence && g_buy_confidence >= 40.0)
   {
      g_momentum_dir = "BULLISH";
      g_tick_consistency = bull_ratio;
   }
   else if(g_sell_confidence > g_buy_confidence && g_sell_confidence >= 40.0)
   {
      g_momentum_dir = "BEARISH";
      g_tick_consistency = bear_ratio;
   }
   else
   {
      g_momentum_dir = "NEUTRAL";
      g_tick_consistency = MathMax(bull_ratio, bear_ratio);
   }
}

//+------------------------------------------------------------------+
//| Market Volatility Classification                                 |
//+------------------------------------------------------------------+
void AnalyzeMarketRegime()
{
   double point = ExtSym.Point();
   if(point <= 0.0) return;

   double r0 = (iHigh(g_symbol, InpSignalTimeframe, 0) - iLow(g_symbol, InpSignalTimeframe, 0)) / point;
   double r1 = (iHigh(g_symbol, InpSignalTimeframe, 1) - iLow(g_symbol, InpSignalTimeframe, 1)) / point;
   double r2 = (iHigh(g_symbol, InpSignalTimeframe, 2) - iLow(g_symbol, InpSignalTimeframe, 2)) / point;
   double avg_range = (r1 + r2) * 0.5;

   if(avg_range < 50.0 && r0 < 40.0)
      g_regime = REGIME_DORMANT;
   else if(avg_range < 150.0)
      g_regime = REGIME_LOW_VOLATILITY;
   else if(r0 > avg_range * 2.2)
      g_regime = REGIME_IMPULSE_BREAKOUT;
   else if(avg_range > 800.0)
      g_regime = REGIME_EXTREME_VOLATILITY;
   else if(avg_range > 400.0)
      g_regime = REGIME_HIGH_VOLATILITY;
   else
      g_regime = REGIME_NORMAL_VOLATILITY;
}

//+------------------------------------------------------------------+
//| Ultra-Responsive Multi-Stage Trailing Stop Engine                |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlTick &tick)
{
   double point = ExtSym.Point();
   if(point <= 0.0) return;

   long stops_level  = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_stop_dist = MathMax((double)stops_level, 10.0) * point;
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
         double candidate_sl    = current_sl;

         if(InpEnableBreakEven && peak_profit_pts >= InpBreakEvenTriggerPts)
         {
            double be_sl = NormalizePrice(open_price + InpBreakEvenOffsetPts * point);
            if(candidate_sl == 0.0 || be_sl > candidate_sl)
            {
               candidate_sl = be_sl;
               g_state = STATE_BREAK_EVEN_ACTIVE;
            }
         }

         if(InpEnableTrailingStop && peak_profit_pts >= InpTrailingStartPts)
         {
            double eff_trail_dist = ComputeEffectiveTrailingDistance(peak_profit_pts) * point;
            double trail_sl = NormalizePrice(g_tracked[i].highest_bid - eff_trail_dist);

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
            {
               candidate_sl = be_sl;
               g_state = STATE_BREAK_EVEN_ACTIVE;
            }
         }

         if(InpEnableTrailingStop && peak_profit_pts >= InpTrailingStartPts)
         {
            double eff_trail_dist = ComputeEffectiveTrailingDistance(peak_profit_pts) * point;
            double trail_sl = NormalizePrice(g_tracked[i].lowest_ask + eff_trail_dist);

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

double ComputeEffectiveTrailingDistance(double peak_profit_pts)
{
   double dist = (double)InpTrailingDistancePts;

   if(InpTrailingMode == TRAIL_ATR_ADAPTIVE)
   {
      double r1 = (iHigh(g_symbol, InpSignalTimeframe, 1) - iLow(g_symbol, InpSignalTimeframe, 1)) / ExtSym.Point();
      if(r1 > 0.0)
         dist = MathMax(50.0, MathMin(1500.0, r1 * 0.65));
   }

   if(InpEnableAdaptiveTrail && peak_profit_pts > InpTrailingDistancePts * 2.5)
      dist *= 0.75;

   return MathMax(50.0, dist);
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
      g_consec_losses     = 0;
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

   if(InpMaxConsecutiveLosses > 0 && g_consec_losses >= InpMaxConsecutiveLosses)
      return false;

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
   double base = InpBaseLot;

   if(InpAutoLotMode && InpRiskPercentPerTrade > 0.0)
   {
      double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_money = MathMax(InpMinStopLossMoney, balance * (InpRiskPercentPerTrade / 100.0));
      double tick_val   = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_sz    = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
      double point      = ExtSym.Point();
      int sl_pts        = ComputeDynamicSLPoints(ExtSym.Bid(), InpBaseLot);

      if(tick_val > 0.0 && tick_sz > 0.0 && point > 0.0 && sl_pts > 0)
      {
         double pt_val = tick_val * (point / tick_sz);
         base = risk_money / (sl_pts * pt_val);
      }
   }

   double mult = MathPow(MathMax(0.1, InpLayerLotMultiplier), layer_index);
   return NormalizeLot(base * mult);
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

   CreateLabel("TITLE", x + 12, y + 10, "VULCARES VX  |  TREND LAYERING", clrGold, 10, true);
   CreateLabel("SUB",   x + 12, y + 28, "Min SL $10 (USD/USC) + Layering + Trail", clrDarkGray, 8, false);

   string keys[] = {
      "EA Status:", "Market Regime:", "Momentum Dir:", "Tick Velocity:",
      "BUY Confidence:", "SELL Confidence:", "Active Layers:", "Total Active Lot:",
      "SL Floor ($10):", "Floating P/L:", "Trailing Status:", "Tightest SL:",
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

   int cur_sl_pts  = ComputeDynamicSLPoints(ExtSym.Bid(), InpBaseLot);
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
   SetVal(2, g_momentum_dir, (g_momentum_dir == "BULLISH") ? clrLime : (g_momentum_dir == "BEARISH" ? clrTomato : clrGray));
   SetVal(3, DoubleToString(g_velocity_pts_sec, 1) + " pts/s", clrWhite);
   SetVal(4, DoubleToString(g_buy_confidence, 1) + "%", (g_buy_confidence >= InpEntryConfidenceMin) ? clrLime : clrSilver);
   SetVal(5, DoubleToString(g_sell_confidence, 1) + "%", (g_sell_confidence >= InpEntryConfidenceMin) ? clrTomato : clrSilver);
   SetVal(6, IntegerToString(g_tracked_count) + " / " + IntegerToString(InpMaxLayers), clrWhite);
   SetVal(7, DoubleToString(total_lot, 2) + " lot", clrWhite);
   SetVal(8, "Min " + DoubleToString(InpMinStopLossMoney, 0) + " " + AccountInfoString(ACCOUNT_CURRENCY) + " (" + IntegerToString(cur_sl_pts) + " pts)", clrGold);
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
