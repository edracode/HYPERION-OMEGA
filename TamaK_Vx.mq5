//+------------------------------------------------------------------+
//|                                                      TamaK_Vx.mq5|
//|                        TamaK Vx — Extreme Profit Maximization EA |
//|                     Autonomous Quantitative Trading Engine (MT5) |
//+------------------------------------------------------------------+
#property copyright "TamaK Vx Quantitative Architecture"
#property version   "1.00"
#property strict
#property description "Ultra-Aggressive Multi-Strategy Tick Scalping & Adaptive Compounding Engine"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//--- ENUMERATIONS
enum ENUM_AGGRESSIVENESS
  {
   AGGR_L1_AGGRESSIVE         = 1, // Level 1: Aggressive
   AGGR_L2_VERY_AGGRESSIVE    = 2, // Level 2: Very Aggressive
   AGGR_L3_SUPER_AGGRESSIVE   = 3, // Level 3: Super Aggressive
   AGGR_L4_EXTREME_AGGRESSIVE = 4, // Level 4: Extreme Aggressive
   AGGR_L5_ULTRA_EXTREME      = 5, // Level 5: Ultra Extreme
   AGGR_L6_HYPER_AGGRESSIVE   = 6, // Level 6: Hyper Aggressive
   AGGR_L7_MAX_PROFIT_ASSAULT = 7, // Level 7: Maximum Profit Assault
   AGGR_L8_UNRESTRICTED_RES   = 8  // Level 8: Unrestricted Research Mode
  };

enum ENUM_EXEC_MODE
  {
   EXEC_LIVE_PRODUCTION = 0, // Live / Standard Execution
   EXEC_TESTER_RESEARCH = 1  // Strategy Tester / Demo Research
  };

enum ENUM_LOT_MODE
  {
   LOT_FIXED              = 0, // Fixed Lot
   LOT_BALANCE_BASED      = 1, // Balance-Based Lot
   LOT_EQUITY_BASED       = 2, // Equity-Based Lot
   LOT_FREE_MARGIN_BASED  = 3, // Free-Margin-Based Lot
   LOT_DYNAMIC_CONFIDENCE = 4, // Dynamic Confidence + Volatility Lot
   LOT_EXP_COMPOUNDING    = 5, // Exponential Compounding Lot
   LOT_MAX_MARGIN_UTIL    = 6  // Maximum Margin Utilization Mode
  };

enum ENUM_TP_MODE
  {
   TP_FIXED_POINTS    = 0, // Fixed Points
   TP_ATR_DYNAMIC     = 1, // ATR + Momentum Dynamic
   TP_TICK_VELOCITY   = 2, // Tick-Based Micro Target
   TP_MONEY_TARGET    = 3  // Money-Based Target per Position
  };

enum ENUM_SL_MODE
  {
   SL_NONE            = 0, // Disabled (Managed by Exit/Basket Engine)
   SL_FIXED_POINTS    = 1, // Fixed Points
   SL_ATR_DYNAMIC     = 2  // ATR Structural Stop
  };

enum ENUM_RISK_PROFILE
  {
   RISK_PROFILE_A_AGGRESSIVE   = 0, // PROFILE A: Aggressive (Bounded)
   RISK_PROFILE_B_EXTREME      = 1, // PROFILE B: Extreme Profit (Loose Limits)
   RISK_PROFILE_C_UNRESTRICTED = 2  // PROFILE C: Unrestricted Research (No Financial Caps)
  };

enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN = 0,
   REGIME_STRONG_BULL,
   REGIME_WEAK_BULL,
   REGIME_STRONG_BEAR,
   REGIME_WEAK_BEAR,
   REGIME_SIDEWAYS_NARROW,
   REGIME_SIDEWAYS_WIDE,
   REGIME_HIGH_VOLATILITY,
   REGIME_EXTREME_VOLATILITY,
   REGIME_MOMENTUM_BURST,
   REGIME_EXHAUSTION,
   REGIME_COMPRESSION
  };

enum ENUM_ENGINE_STATE
  {
   STATE_INITIALIZING = 0,
   STATE_READY,
   STATE_SCANNING,
   STATE_SIGNAL_VALIDATED,
   STATE_ENTRY_REQUESTED,
   STATE_POSITION_ACTIVE,
   STATE_EXIT_REQUESTED,
   STATE_RECONCILIATION,
   STATE_MARKET_UNAVAILABLE,
   STATE_EXECUTION_ERROR,
   STATE_MANUAL_PAUSE
  };

enum ENUM_DIAG_STATUS
  {
   DIAG_OK = 0,
   DIAG_WAITING_DATA,
   DIAG_WAITING_SIGNAL,
   DIAG_SIGNAL_BELOW_THRESHOLD,
   DIAG_SPREAD_TOO_HIGH,
   DIAG_INVALID_VOLUME,
   DIAG_INSUFFICIENT_MARGIN,
   DIAG_MARKET_CLOSED,
   DIAG_AUTO_TRADING_DISABLED,
   DIAG_ORDER_REJECTED,
   DIAG_MAX_POSITIONS_REACHED,
   DIAG_RISK_LIMIT_HIT,
   DIAG_USER_PAUSED,
   DIAG_COOLDOWN_ACTIVE
  };

//--- INPUT PARAMETERS
input group "=== GENERAL SETTINGS ==="
input string              EA_Name                      = "TamaK Vx";               // Engine Identity
input ulong               MagicNumber                  = 88990011;                 // Primary Magic Number
input bool                TradingEnabled               = true;                     // Master Trading Switch
input bool                AllowBuy                     = true;                     // Allow Long Entries
input bool                AllowSell                    = true;                     // Allow Short Entries
input bool                MultiSymbolEnabled           = false;                    // Enable Multi-Symbol Scanning
input string              SymbolList                   = "XAUUSD,EURUSD,GBPUSD";   // Comma-Separated Symbols
input ENUM_EXEC_MODE      ExecutionMode                = EXEC_LIVE_PRODUCTION;     // Execution Environment Mode
input ENUM_AGGRESSIVENESS AggressivenessLevel          = AGGR_L5_ULTRA_EXTREME;    // Aggressiveness Level (1-8)

input group "=== SCALPING SETTINGS ==="
input bool                TickScalpingEnabled          = true;                     // Enable Tick-by-Tick Scalping
input bool                IntrabarEntryEnabled         = true;                     // Allow Intrabar Signal Entries
input bool                RapidReentryEnabled          = true;                     // Enable Rapid Re-entry After Close
input double              EntrySensitivity             = 1.25;                     // Entry Sensitivity Multiplier
input double              MomentumSensitivity          = 1.30;                     // Momentum Burst Sensitivity
input double              MinimumSignalConfidence      = 52.0;                     // Min Confidence Score (0-100)
input uint                ReentryDelayMilliseconds     = 50;                       // Re-entry Cooldown (ms, 0=Zero)
input int                 MaximumHoldingSeconds        = 0;                        // Max Hold Time (sec, 0=Unlimited)
input bool                AllowSameCandleMultipleEntries = true;                   // Multiple Entries in Same Bar

input group "=== POSITION SETTINGS ==="
input ENUM_LOT_MODE       LotMode                      = LOT_EXP_COMPOUNDING;      // Position Sizing Mode
input double              BaseLot                      = 0.05;                     // Base Lot Size
input double              LotMultiplier                = 1.20;                     // Aggressiveness Lot Multiplier
input bool                CompoundingEnabled           = true;                     // Enable Exponential Compounding
input double              CompoundingExponent          = 1.35;                     // Compounding Exponent (1.0-2.0+)
input double              MaximumLot                   = 0.0;                      // Max Lot Cap (0=Broker Max)
input int                 MaximumPositions             = 25;                       // Max Total Positions (0=Unlimited)
input int                 MaximumPositionsPerSymbol    = 15;                       // Max Positions per Symbol
input bool                MultiEntryEnabled            = true;                     // Allow Parallel Multi-Entry
input bool                PyramidingEnabled            = true;                     // Enable Profit Pyramiding
input double              PyramidingMultiplier         = 1.15;                     // Pyramiding Volume Multiplier
input double              MarginUtilizationPercent     = 75.0;                     // Target Max Margin Utilization (%)

input group "=== PROFIT SETTINGS ==="
input ENUM_TP_MODE        TakeProfitMode               = TP_ATR_DYNAMIC;           // Take Profit Mode
input int                 TakeProfitPoints             = 180;                      // Fixed TP (Points)
input double              TakeProfitMoney              = 15.0;                     // Money TP per Position (Account Ccy)
input bool                DynamicTakeProfitEnabled     = true;                     // Extend TP on Strong Momentum
input bool                BasketTakeProfitEnabled      = true;                     // Enable Collective Basket TP
input double              BasketTakeProfitMoney        = 45.0;                     // Net Basket TP Target (Account Ccy)
input bool                PartialCloseEnabled          = true;                     // Enable Partial Profit Realization
input bool                ProfitLockEnabled            = true;                     // Enable Peak Profit Lock
input bool                TrailingEnabled              = true;                     // Enable Dynamic Trailing
input int                 TrailingStartPoints          = 80;                       // Trailing Activation (Points)
input int                 TrailingDistancePoints       = 45;                       // Trailing Distance (Points)
input int                 TrailingStepPoints           = 10;                       // Trailing Step (Points)
input bool                VirtualTrailingEnabled       = true;                     // Internal Virtual Trailing (Sub-StopLevel)

input group "=== RISK SETTINGS ==="
input ENUM_RISK_PROFILE   RiskProfile                  = RISK_PROFILE_B_EXTREME;   // Financial Risk Policy Profile
input bool                EnableDailyLossLimit         = false;                    // Enforce Daily Loss Limit
input double              DailyLossLimitPercent        = 25.0;                     // Max Daily Loss (%)
input bool                EnableDrawdownLimit          = false;                    // Enforce Equity Drawdown Limit
input double              MaximumDrawdownPercent       = 50.0;                     // Max Equity Drawdown (%)
input bool                EnableStopLoss               = false;                    // Attach Hard Stop Loss
input ENUM_SL_MODE        StopLossMode                 = SL_ATR_DYNAMIC;           // Hard Stop Loss Mode
input int                 StopLossPoints               = 350;                      // Fixed Stop Loss (Points)
input int                 MaximumTradesPerDay          = 0;                        // Max Trades/Day (0=Unlimited)
input bool                EmergencyStopEnabled         = false;                    // Emergency Stop on Margin < 30%
input bool                LiveTradingExplicitlyAllowed = false;                    // Explicit Consent for Live Extreme Mode

input group "=== STRATEGY SETTINGS ==="
input bool                TrendStrategyEnabled         = true;                     // S1: Multi-MA & Supertrend Slope
input bool                MomentumStrategyEnabled      = true;                     // S2: Intrabar RSI/MACD Burst
input bool                ReversalStrategyEnabled      = true;                     // S3: Exhaustion & Liquidity Sweep
input bool                BreakoutStrategyEnabled      = true;                     // S4: Volatility & Range Breakout
input bool                RangeStrategyEnabled         = true;                     // S5: Micro-Channel Range Scalping
input bool                MeanReversionEnabled         = true;                     // S6: Z-Score & Bollinger Snapback
input bool                MicrostructureStrategyEnabled= true;                     // S7: Tick Velocity & Imbalance
input bool                StatisticalStrategyEnabled   = true;                     // S8: Kalman Filter & Autocorrelation
input bool                RecoveryStrategyEnabled      = true;                     // S9: Trend-Reassessed Basket Recovery
input bool                AdaptiveLearningEnabled      = true;                     // Online UCB/Bayesian Strategy Weighting

input group "=== EXECUTION SETTINGS ==="
input int                 MaximumDeviationPoints       = 30;                       // Max Slippage Deviation (Points)
input int                 MaximumSpreadPoints          = 60;                       // Max Spread Filter (Points, 0=Off)
input bool                AsyncExecutionEnabled        = false;                    // Use OrderSendAsync (Live Only)
input int                 RetryLimit                   = 3;                        // Bounded Order Retry Limit
input uint                RetryDelayMilliseconds       = 25;                       // Retry Delay (ms)
input int                 MaximumRequestsPerSecond     = 20;                       // Anti-Flood Rate Limit (Req/sec)

input group "=== DASHBOARD SETTINGS ==="
input bool                ShowDashboard                = true;                     // Display Chart Dashboard
input ENUM_BASE_CORNER    DashboardCorner              = CORNER_LEFT_UPPER;        // Panel Anchor Corner
input int                 DashboardX                   = 14;                       // Panel X Offset
input int                 DashboardY                   = 24;                       // Panel Y Offset
input int                 DashboardWidth               = 310;                      // Panel Width (px)
input int                 DashboardFontSize            = 8;                        // Base Font Size
input uint                DashboardUpdateMilliseconds  = 250;                      // UI Refresh Interval (ms)
input bool                ShowTradeButtons             = true;                     // Show Interactive Control Buttons

input group "=== DEBUG SETTINGS ==="
input bool                EnableDebugLog               = false;                    // Verbose Diagnostic Logging
input bool                EnableSignalLog              = false;                    // Log Accepted Signals
input bool                EnableExecutionLog           = true;                     // Log Order Execution & Rejections
input bool                EnableTesterDiagnostics      = true;                     // Print End-of-Test Summary

//--- CONSTANTS & MACROS
#define TOTAL_STRATEGIES 9
#define TICK_BUFFER_SIZE 1024
#define UI_PREFIX        "TMKVX_"

//--- DATA STRUCTURES
struct TickNode
  {
   double bid;
   double ask;
   double mid;
   double spread_pts;
   long   time_msc;
   int    dir; // +1 up, -1 down, 0 flat
  };

struct StrategyStats
  {
   string name;
   int    id;
   bool   enabled;
   int    trades;
   int    wins;
   int    losses;
   double gross_profit;
   double gross_loss;
   double net_profit;
   double weight;
   double ucb_score;
   double ewma_reward;
  };

struct SignalCandidate
  {
   bool   valid;
   int    strategy_id;
   int    direction;       // +1 BUY, -1 SELL
   double confidence;      // 0..100
   double momentum_score;
   double expected_move_pts;
   double net_edge_money;
   string reason;
  };

struct VirtualPosTracker
  {
   ulong  ticket;
   double peak_profit_money;
   double peak_price;
   bool   partial_done;
  };

//--- GLOBAL ENGINE STATE
CTrade         g_trade;
CSymbolInfo    g_sym;
CPositionInfo  g_pos;
CAccountInfo   g_acc;

bool           g_engine_paused       = false;
bool           g_live_consent_ok     = true;
ENUM_ENGINE_STATE g_engine_state     = STATE_INITIALIZING;
ENUM_DIAG_STATUS  g_diag_status      = DIAG_WAITING_DATA;
ENUM_MARKET_REGIME g_current_regime  = REGIME_UNKNOWN;

//--- TICK RING BUFFER
TickNode       g_ticks[TICK_BUFFER_SIZE];
int            g_tick_head           = 0;
int            g_tick_count          = 0;

//--- INDICATOR HANDLES (CACHED)
int            g_h_ema_fast          = INVALID_HANDLE;
int            g_h_ema_mid           = INVALID_HANDLE;
int            g_h_ema_slow          = INVALID_HANDLE;
int            g_h_ema_h1            = INVALID_HANDLE;
int            g_h_rsi               = INVALID_HANDLE;
int            g_h_macd              = INVALID_HANDLE;
int            g_h_atr               = INVALID_HANDLE;
int            g_h_bb                = INVALID_HANDLE;
int            g_h_adx               = INVALID_HANDLE;

//--- KALMAN FILTER STATE
double         g_kalman_x            = 0.0;
double         g_kalman_p            = 1.0;
bool           g_kalman_init         = false;

//--- STRATEGY & PERFORMANCE TRACKING
StrategyStats  g_strategies[TOTAL_STRATEGIES];
double         g_reference_equity    = 0.0;
double         g_peak_equity         = 0.0;
double         g_max_drawdown_pct    = 0.0;
double         g_day_start_balance   = 0.0;
int            g_current_day_of_year = -1;
ulong          g_last_entry_msc      = 0;
ulong          g_last_ui_update_msc  = 0;
ulong          g_last_context_msc    = 0;

//--- RATE LIMITER
uint           g_req_second_stamp    = 0;
int            g_req_count_in_sec    = 0;

//--- DIAGNOSTIC COUNTERS
ulong          g_cnt_ticks           = 0;
ulong          g_cnt_cycles          = 0;
ulong          g_cnt_candidates      = 0;
ulong          g_cnt_accepted        = 0;
ulong          g_cnt_rejected        = 0;
ulong          g_cnt_entry_attempts  = 0;
ulong          g_cnt_entry_success   = 0;
ulong          g_cnt_entry_failed    = 0;
uint           g_last_retcode        = 0;
string         g_last_reject_reason  = "None";

//--- VIRTUAL TRAILING TRACKER
VirtualPosTracker g_vtrack[];

//--- CACHED ACCOUNT / STATS SNAPSHOT
int            g_stat_total_trades   = 0;
int            g_stat_wins           = 0;
int            g_stat_losses         = 0;
double         g_stat_gross_profit   = 0.0;
double         g_stat_gross_loss     = 0.0;
double         g_stat_net_profit     = 0.0;
double         g_stat_today_profit   = 0.0;
double         g_last_signal_conf    = 0.0;
int            g_last_signal_dir     = 0;

//+------------------------------------------------------------------+
//| Helper: Map Aggressiveness Level to Dynamic Multipliers          |
//+------------------------------------------------------------------+
double GetAggrConfidenceOffset()
  {
   switch(AggressivenessLevel)
     {
      case AGGR_L1_AGGRESSIVE:         return +12.0;
      case AGGR_L2_VERY_AGGRESSIVE:    return +6.0;
      case AGGR_L3_SUPER_AGGRESSIVE:   return 0.0;
      case AGGR_L4_EXTREME_AGGRESSIVE: return -5.0;
      case AGGR_L5_ULTRA_EXTREME:      return -10.0;
      case AGGR_L6_HYPER_AGGRESSIVE:   return -15.0;
      case AGGR_L7_MAX_PROFIT_ASSAULT: return -20.0;
      case AGGR_L8_UNRESTRICTED_RES:   return -25.0;
     }
   return 0.0;
  }

double GetAggrLotScale()
  {
   return 0.65 + (0.20 * (int)AggressivenessLevel);
  }

int GetEffectiveMaxPositions()
  {
   if(RiskProfile == RISK_PROFILE_C_UNRESTRICTED || AggressivenessLevel == AGGR_L8_UNRESTRICTED_RES)
      return (MaximumPositions <= 0) ? 200 : MaximumPositions;
   if(MaximumPositions <= 0) return 100;
   return MaximumPositions;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_engine_state = STATE_INITIALIZING;

   if(!g_sym.Name(_Symbol))
     {
      Print("[TamaK Vx FATAL] Failed to bind symbol info for ", _Symbol);
      return(INIT_FAILED);
     }
   g_sym.Refresh();
   g_sym.RefreshRates();

   // Live mode explicit consent check for Extreme/Unrestricted profiles
   bool is_live = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL);
   if(is_live && !MQLInfoInteger(MQL_TESTER))
     {
      if((RiskProfile == RISK_PROFILE_C_UNRESTRICTED || AggressivenessLevel >= AGGR_L6_HYPER_AGGRESSIVE) && !LiveTradingExplicitlyAllowed)
        {
         g_live_consent_ok = false;
         g_engine_paused   = true;
         Print("[TamaK Vx WARNING] Live Extreme/Unrestricted mode requires LiveTradingExplicitlyAllowed=true. Engine started in PAUSED safety state.");
        }
     }

   // Configure CTrade
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetDeviationInPoints(MaximumDeviationPoints);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(AsyncExecutionEnabled && !MQLInfoInteger(MQL_TESTER));

   // Initialize Indicator Handles (Tier 2 & 3 Cache)
   g_h_ema_fast = iMA(_Symbol, PERIOD_M1, 8, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_mid  = iMA(_Symbol, PERIOD_M1, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_slow = iMA(_Symbol, PERIOD_M1, 55, 0, MODE_EMA, PRICE_CLOSE);
   g_h_ema_h1   = iMA(_Symbol, PERIOD_H1, 34, 0, MODE_EMA, PRICE_CLOSE);
   g_h_rsi      = iRSI(_Symbol, PERIOD_M1, 7, PRICE_CLOSE);
   g_h_macd     = iMACD(_Symbol, PERIOD_M1, 6, 13, 4, PRICE_CLOSE);
   g_h_atr      = iATR(_Symbol, PERIOD_M1, 14);
   g_h_bb       = iBands(_Symbol, PERIOD_M1, 20, 0, 2.0, PRICE_CLOSE);
   g_h_adx      = iADX(_Symbol, PERIOD_M1, 14);

   // Non-fatal fallback check: warn if any handle invalid, never abort Strategy Tester needlessly
   if(g_h_ema_fast == INVALID_HANDLE || g_h_atr == INVALID_HANDLE)
      Print("[TamaK Vx WARN] Primary indicator handles warming up; tick microstructure layer active.");

   // Initialize Strategies
   InitStrategies();

   // Initialize Equity & Accounting Anchors
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_reference_equity  = (eq > 0.0) ? eq : bal;
   g_peak_equity       = g_reference_equity;
   g_day_start_balance = bal;

   MqlDateTime dt;
   TimeCurrent(dt);
   g_current_day_of_year = dt.day_of_year;

   RecalculateClosedHistoryStats();

   if(ShowDashboard)
      CreateDashboard();

   EventSetMillisecondTimer(250);
   g_engine_state = g_engine_paused ? STATE_MANUAL_PAUSE : STATE_READY;

   PrintFormat("[TamaK Vx] Initialized on %s | Level: %d | RiskProfile: %d | Equity: %.2f",
               _Symbol, AggressivenessLevel, RiskProfile, g_reference_equity);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   if(g_h_ema_fast != INVALID_HANDLE) IndicatorRelease(g_h_ema_fast);
   if(g_h_ema_mid  != INVALID_HANDLE) IndicatorRelease(g_h_ema_mid);
   if(g_h_ema_slow != INVALID_HANDLE) IndicatorRelease(g_h_ema_slow);
   if(g_h_ema_h1   != INVALID_HANDLE) IndicatorRelease(g_h_ema_h1);
   if(g_h_rsi      != INVALID_HANDLE) IndicatorRelease(g_h_rsi);
   if(g_h_macd     != INVALID_HANDLE) IndicatorRelease(g_h_macd);
   if(g_h_atr      != INVALID_HANDLE) IndicatorRelease(g_h_atr);
   if(g_h_bb       != INVALID_HANDLE) IndicatorRelease(g_h_bb);
   if(g_h_adx      != INVALID_HANDLE) IndicatorRelease(g_h_adx);

   DestroyDashboard();

   if(EnableTesterDiagnostics)
     {
      PrintFormat("[TamaK Vx SUMMARY] Ticks:%I64u | Cycles:%I64u | Signals(Acc/Tot):%I64u/%I64u | Entries(OK/Fail):%I64u/%I64u | NetProfit:%.2f | WinRate:%.1f%% | MaxDD:%.2f%%",
                  g_cnt_ticks, g_cnt_cycles, g_cnt_accepted, g_cnt_candidates,
                  g_cnt_entry_success, g_cnt_entry_failed, g_stat_net_profit,
                  (g_stat_total_trades > 0 ? (100.0 * g_stat_wins / g_stat_total_trades) : 0.0),
                  g_max_drawdown_pct);
     }
  }

//+------------------------------------------------------------------+
//| Initialize Strategy Registry                                     |
//+------------------------------------------------------------------+
void InitStrategies()
  {
   string names[TOTAL_STRATEGIES] =
     {
      "S1_MultiTrend",
      "S2_MomentumBurst",
      "S3_LiquidityReversal",
      "S4_VolBreakout",
      "S5_MicroRange",
      "S6_MeanReversion",
      "S7_TickMicrostructure",
      "S8_KalmanStatArb",
      "S9_BasketRecovery"
     };
   bool flags[TOTAL_STRATEGIES] =
     {
      TrendStrategyEnabled,
      MomentumStrategyEnabled,
      ReversalStrategyEnabled,
      BreakoutStrategyEnabled,
      RangeStrategyEnabled,
      MeanReversionEnabled,
      MicrostructureStrategyEnabled,
      StatisticalStrategyEnabled,
      RecoveryStrategyEnabled
     };

   for(int i = 0; i < TOTAL_STRATEGIES; i++)
     {
      g_strategies[i].id           = i;
      g_strategies[i].name         = names[i];
      g_strategies[i].enabled      = flags[i];
      g_strategies[i].trades       = 0;
      g_strategies[i].wins         = 0;
      g_strategies[i].losses       = 0;
      g_strategies[i].gross_profit = 0.0;
      g_strategies[i].gross_loss   = 0.0;
      g_strategies[i].net_profit   = 0.0;
      g_strategies[i].weight       = 1.0;
      g_strategies[i].ucb_score    = 1.5;
      g_strategies[i].ewma_reward  = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| Tier 1: Tick Ring Buffer Ingestion & Kalman State Update         |
//+------------------------------------------------------------------+
bool RecordCurrentTick()
  {
   MqlTick tk;
   if(!SymbolInfoTick(_Symbol, tk))
      return false;
   if(tk.bid <= 0.0 || tk.ask <= 0.0 || tk.ask < tk.bid)
      return false;

   double mid = 0.5 * (tk.bid + tk.ask);
   double pt  = g_sym.Point();
   if(pt <= 0.0) pt = _Point;
   double spr_pts = (tk.ask - tk.bid) / pt;

   int dir = 0;
   if(g_tick_count > 0)
     {
      int prev_idx = (g_tick_head - 1 + TICK_BUFFER_SIZE) % TICK_BUFFER_SIZE;
      if(mid > g_ticks[prev_idx].mid) dir = 1;
      else if(mid < g_ticks[prev_idx].mid) dir = -1;
     }

   g_ticks[g_tick_head].bid        = tk.bid;
   g_ticks[g_tick_head].ask        = tk.ask;
   g_ticks[g_tick_head].mid        = mid;
   g_ticks[g_tick_head].spread_pts = spr_pts;
   g_ticks[g_tick_head].time_msc   = tk.time_msc;
   g_ticks[g_tick_head].dir        = dir;

   g_tick_head = (g_tick_head + 1) % TICK_BUFFER_SIZE;
   if(g_tick_count < TICK_BUFFER_SIZE) g_tick_count++;

   // 1D Scalar Kalman Filter Update on Mid-Price
   if(!g_kalman_init)
     {
      g_kalman_x    = mid;
      g_kalman_p    = pt * 10.0;
      g_kalman_init = true;
     }
   else
     {
      double q = pt * pt * 0.5;  // Process noise
      double r = pt * pt * 4.0;  // Measurement noise
      g_kalman_p += q;
      double k = g_kalman_p / (g_kalman_p + r);
      g_kalman_x = g_kalman_x + k * (mid - g_kalman_x);
      g_kalman_p = (1.0 - k) * g_kalman_p;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Helper: Query Tick Microstructure Metrics over N Ticks           |
//+------------------------------------------------------------------+
void GetTickWindowStats(int window, double &net_move_pts, double &velocity_pts_sec, double &dir_consistency, double &avg_spread_pts)
  {
   net_move_pts     = 0.0;
   velocity_pts_sec = 0.0;
   dir_consistency  = 0.0;
   avg_spread_pts   = 0.0;

   int n = MathMin(window, g_tick_count);
   if(n < 2) return;

   double pt = g_sym.Point();
   if(pt <= 0.0) pt = _Point;

   int newest = (g_tick_head - 1 + TICK_BUFFER_SIZE) % TICK_BUFFER_SIZE;
   int oldest = (g_tick_head - n + TICK_BUFFER_SIZE) % TICK_BUFFER_SIZE;

   net_move_pts = (g_ticks[newest].mid - g_ticks[oldest].mid) / pt;

   long dt_msc = g_ticks[newest].time_msc - g_ticks[oldest].time_msc;
   if(dt_msc <= 0) dt_msc = 50; // Fallback for synthetic tester ticks
   velocity_pts_sec = net_move_pts / (dt_msc / 1000.0);

   int up = 0, dn = 0;
   double spr_sum = 0.0;
   for(int i = 0; i < n; i++)
     {
      int idx = (oldest + i) % TICK_BUFFER_SIZE;
      if(g_ticks[idx].dir > 0) up++;
      else if(g_ticks[idx].dir < 0) dn++;
      spr_sum += g_ticks[idx].spread_pts;
     }
   avg_spread_pts  = spr_sum / n;
   dir_consistency = (double)(up - dn) / (double)n; // -1.0 to +1.0
  }

//+------------------------------------------------------------------+
//| Main Tick Handler (Tier 1 & Tier 2 Execution Pipeline)           |
//+------------------------------------------------------------------+
void OnTick()
  {
   g_cnt_ticks++;

   if(!g_sym.RefreshRates())
     {
      g_diag_status = DIAG_WAITING_DATA;
      return;
     }

   if(!RecordCurrentTick())
     {
      g_diag_status = DIAG_WAITING_DATA;
      return;
     }

   // Update Equity High-Water Mark & Drawdown
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(eq > g_peak_equity) g_peak_equity = eq;
   if(g_peak_equity > 0.0)
     {
      double dd = ((g_peak_equity - eq) / g_peak_equity) * 100.0;
      if(dd > g_max_drawdown_pct) g_max_drawdown_pct = dd;
     }

   // Day Rollover Reset
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != g_current_day_of_year)
     {
      g_current_day_of_year = dt.day_of_year;
      g_day_start_balance   = bal;
     }

   // Tier 1: Ultra-Fast Position Management (Virtual Trailing, Basket TP, Profit Lock)
   ManageOpenPositions();

   // Check Global Pause / Trading Switches
   if(g_engine_paused || !TradingEnabled)
     {
      g_engine_state = STATE_MANUAL_PAUSE;
      g_diag_status  = DIAG_USER_PAUSED;
      return;
     }

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_diag_status = DIAG_AUTO_TRADING_DISABLED;
      return;
     }

   // Risk Policy Guardrails (Configurable; Bypassed in Profile C / Unrestricted)
   if(!CheckRiskPolicy(eq, bal))
      return;

   // Spread Guard
   double cur_spread_pts = (g_sym.Ask() - g_sym.Bid()) / g_sym.Point();
   if(MaximumSpreadPoints > 0 && cur_spread_pts > MaximumSpreadPoints)
     {
      g_diag_status = DIAG_SPREAD_TOO_HIGH;
      return;
     }

   // Cooldown Check (Millisecond precision)
   ulong now_msc = GetTickCount64();
   if(ReentryDelayMilliseconds > 0 && (now_msc - g_last_entry_msc) < ReentryDelayMilliseconds)
     {
      g_diag_status = DIAG_COOLDOWN_ACTIVE;
      return;
     }

   // Tier 3: Periodic Market Regime Classification (every 500ms)
   if(now_msc - g_last_context_msc >= 500)
     {
      ClassifyMarketRegime();
      g_last_context_msc = now_msc;
     }

   // Tier 2: Multi-Strategy Parallel Signal Evaluation
   g_cnt_cycles++;
   g_engine_state = STATE_SCANNING;
   EvaluateAndExecuteStrategies(cur_spread_pts);
  }

//+------------------------------------------------------------------+
//| Timer Handler (Tier 5 Presentation & Background Reconciliation)  |
//+------------------------------------------------------------------+
void OnTimer()
  {
   ulong now_msc = GetTickCount64();
   if(ShowDashboard && (now_msc - g_last_ui_update_msc >= DashboardUpdateMilliseconds))
     {
      UpdateDashboard();
      g_last_ui_update_msc = now_msc;
     }
  }

//+------------------------------------------------------------------+
//| Trade Transaction Handler (Online Strategy Learning & Stats)     |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      ulong deal_ticket = trans.deal;
      if(deal_ticket > 0 && HistoryDealSelect(deal_ticket))
        {
         long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
         long entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
         if(magic == (long)MagicNumber && (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT))
           {
            double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                          + HistoryDealGetDouble(deal_ticket, DEAL_SWAP)
                          + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
            string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
            int strat_id = ExtractStrategyIdFromComment(comment);

            if(strat_id >= 0 && strat_id < TOTAL_STRATEGIES)
               UpdateStrategyPerformance(strat_id, profit);

            RecalculateClosedHistoryStats();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Extract Strategy ID embedded in order comment ("TMKVX_S2")      |
//+------------------------------------------------------------------+
int ExtractStrategyIdFromComment(string cmt)
  {
   int pos = StringFind(cmt, "TMKVX_S");
   if(pos < 0) return -1;
   string sub = StringSubstr(cmt, pos + 7, 1);
   int id = (int)StringToInteger(sub);
   return (id >= 0 && id < TOTAL_STRATEGIES) ? id : -1;
  }

//+------------------------------------------------------------------+
//| Tier 4: Online Bayesian / UCB Strategy Performance Updater       |
//+------------------------------------------------------------------+
void UpdateStrategyPerformance(int id, double net_pnl)
  {
   g_strategies[id].trades++;
   g_strategies[id].net_profit += net_pnl;
   if(net_pnl >= 0.0)
     {
      g_strategies[id].wins++;
      g_strategies[id].gross_profit += net_pnl;
     }
   else
     {
      g_strategies[id].losses++;
      g_strategies[id].gross_loss += MathAbs(net_pnl);
     }

   if(!AdaptiveLearningEnabled) return;

   // Exponential Weighted Moving Average of Normalized Reward
   double reward = MathMax(-2.0, MathMin(3.0, net_pnl / MathMax(1.0, TakeProfitMoney)));
   g_strategies[id].ewma_reward = 0.85 * g_strategies[id].ewma_reward + 0.15 * reward;

   int total_all = 1;
   for(int i = 0; i < TOTAL_STRATEGIES; i++) total_all += g_strategies[i].trades;

   for(int i = 0; i < TOTAL_STRATEGIES; i++)
     {
      double n_i = (double)MathMax(1, g_strategies[i].trades);
      double exploration = MathSqrt(1.5 * MathLog((double)total_all) / n_i);
      g_strategies[i].ucb_score = g_strategies[i].ewma_reward + exploration;
      g_strategies[i].weight    = MathMax(0.25, MathMin(2.50, 1.0 + 0.35 * g_strategies[i].ucb_score));
     }
  }

//+------------------------------------------------------------------+
//| Tier 3: Market Regime Classification                             |
//+------------------------------------------------------------------+
void ClassifyMarketRegime()
  {
   double ema_f[3], ema_m[3], ema_s[3], atr[3], adx[2], bb_u[2], bb_l[2];
   if(CopyBuffer(g_h_ema_fast, 0, 0, 3, ema_f) < 3 ||
      CopyBuffer(g_h_ema_mid,  0, 0, 3, ema_m) < 3 ||
      CopyBuffer(g_h_ema_slow, 0, 0, 3, ema_s) < 3 ||
      CopyBuffer(g_h_atr,      0, 0, 3, atr)   < 3 ||
      CopyBuffer(g_h_adx,      0, 0, 2, adx)   < 2 ||
      CopyBuffer(g_h_bb,       1, 0, 2, bb_u)  < 2 ||
      CopyBuffer(g_h_bb,       2, 0, 2, bb_l)  < 2)
     {
      g_current_regime = REGIME_UNKNOWN;
      return;
     }

   double pt = g_sym.Point();
   double atr_pts = atr[0] / pt;
   double bb_width_pts = (bb_u[0] - bb_l[0]) / pt;

   double net20, vel20, cons20, spr20;
   GetTickWindowStats(20, net20, vel20, cons20, spr20);

   if(MathAbs(vel20) > atr_pts * 0.35 && MathAbs(cons20) > 0.45)
     {
      g_current_regime = REGIME_MOMENTUM_BURST;
      return;
     }
   if(atr_pts > 0 && bb_width_pts > atr_pts * 5.5)
     {
      g_current_regime = REGIME_EXTREME_VOLATILITY;
      return;
     }
   if(atr_pts > 0 && bb_width_pts < atr_pts * 1.6)
     {
      g_current_regime = REGIME_COMPRESSION;
      return;
     }

   bool bull_stack = (ema_f[0] > ema_m[0] && ema_m[0] > ema_s[0]);
   bool bear_stack = (ema_f[0] < ema_m[0] && ema_m[0] < ema_s[0]);

   if(bull_stack)
      g_current_regime = (adx[0] >= 25.0) ? REGIME_STRONG_BULL : REGIME_WEAK_BULL;
   else if(bear_stack)
      g_current_regime = (adx[0] >= 25.0) ? REGIME_STRONG_BEAR : REGIME_WEAK_BEAR;
   else
      g_current_regime = (bb_width_pts < atr_pts * 2.5) ? REGIME_SIDEWAYS_NARROW : REGIME_SIDEWAYS_WIDE;
  }

//+------------------------------------------------------------------+
//| Tier 2: Multi-Strategy Parallel Evaluation & Execution           |
//+------------------------------------------------------------------+
void EvaluateAndExecuteStrategies(double cur_spread_pts)
  {
   int open_total = 0, open_buy = 0, open_sell = 0;
   double total_buy_lot = 0.0, total_sell_lot = 0.0, net_floating = 0.0;
   double last_buy_price = 0.0, last_sell_price = 0.0;

   ScanActivePositions(open_total, open_buy, open_sell, total_buy_lot, total_sell_lot, net_floating, last_buy_price, last_sell_price);

   int max_pos = GetEffectiveMaxPositions();
   if(open_total >= max_pos || open_total >= MaximumPositionsPerSymbol)
     {
      g_diag_status = DIAG_MAX_POSITIONS_REACHED;
      return;
     }

   // Shared Indicator Cache Read (Once per Tick Cycle)
   double ema_f[2], ema_m[2], ema_s[2], ema_h1[2], rsi[2], macd_m[2], macd_s[2], atr[2], bb_u[2], bb_m[2], bb_l[2];
   bool ind_ok = (CopyBuffer(g_h_ema_fast, 0, 0, 2, ema_f)  == 2 &&
                  CopyBuffer(g_h_ema_mid,  0, 0, 2, ema_m)  == 2 &&
                  CopyBuffer(g_h_ema_slow, 0, 0, 2, ema_s)  == 2 &&
                  CopyBuffer(g_h_ema_h1,   0, 0, 2, ema_h1) == 2 &&
                  CopyBuffer(g_h_rsi,      0, 0, 2, rsi)    == 2 &&
                  CopyBuffer(g_h_macd,     0, 0, 2, macd_m) == 2 &&
                  CopyBuffer(g_h_macd,     1, 0, 2, macd_s) == 2 &&
                  CopyBuffer(g_h_atr,      0, 0, 2, atr)    == 2 &&
                  CopyBuffer(g_h_bb,       0, 0, 2, bb_m)   == 2 &&
                  CopyBuffer(g_h_bb,       1, 0, 2, bb_u)   == 2 &&
                  CopyBuffer(g_h_bb,       2, 0, 2, bb_l)   == 2);

   double bid = g_sym.Bid();
   double ask = g_sym.Ask();
   double mid = 0.5 * (bid + ask);
   double pt  = g_sym.Point();

   double net10, vel10, cons10, spr10;
   double net50, vel50, cons50, spr50;
   GetTickWindowStats(10, net10, vel10, cons10, spr10);
   GetTickWindowStats(50, net50, vel50, cons50, spr50);

   SignalCandidate cands[TOTAL_STRATEGIES];
   for(int i = 0; i < TOTAL_STRATEGIES; i++) cands[i].valid = false;

   // --- S1: Multi-MA & H1 Context Trend Continuation ---
   if(g_strategies[0].enabled && ind_ok)
     {
      double slope_f = (ema_f[0] - ema_f[1]) / pt;
      if(ema_f[0] > ema_m[0] && ema_m[0] > ema_s[0] && slope_f > 1.5 && mid > ema_f[0])
        {
         cands[0].valid = true; cands[0].strategy_id = 0; cands[0].direction = 1;
         cands[0].confidence = MathMin(95.0, (55.0 + MathAbs(slope_f) * 1.5 + (mid > ema_h1[0] ? 8.0 : 0.0)) * EntrySensitivity);
         cands[0].expected_move_pts = MathMax(cur_spread_pts * 2.5, (atr[0] / pt) * 0.45);
        }
      else if(ema_f[0] < ema_m[0] && ema_m[0] < ema_s[0] && slope_f < -1.5 && mid < ema_f[0])
        {
         cands[0].valid = true; cands[0].strategy_id = 0; cands[0].direction = -1;
         cands[0].confidence = MathMin(95.0, (55.0 + MathAbs(slope_f) * 1.5 + (mid < ema_h1[0] ? 8.0 : 0.0)) * EntrySensitivity);
         cands[0].expected_move_pts = MathMax(cur_spread_pts * 2.5, (atr[0] / pt) * 0.45);
        }
     }

   // --- S2: Intrabar Momentum Burst (RSI + MACD + Tick Velocity) ---
   if(g_strategies[1].enabled && ind_ok)
     {
      double macd_hist = macd_m[0] - macd_s[0];
      double macd_prev = macd_m[1] - macd_s[1];
      if(rsi[0] > 58.0 && rsi[0] < 84.0 && macd_hist > macd_prev && vel10 > 2.0)
        {
         cands[1].valid = true; cands[1].strategy_id = 1; cands[1].direction = 1;
         cands[1].confidence = MathMin(96.0, (54.0 + (rsi[0] - 50.0) * 0.6 + MathAbs(vel10) * 0.8) * MomentumSensitivity);
         cands[1].expected_move_pts = MathMax(cur_spread_pts * 2.2, (atr[0] / pt) * 0.40);
        }
      else if(rsi[0] < 42.0 && rsi[0] > 16.0 && macd_hist < macd_prev && vel10 < -2.0)
        {
         cands[1].valid = true; cands[1].strategy_id = 1; cands[1].direction = -1;
         cands[1].confidence = MathMin(96.0, (54.0 + (50.0 - rsi[0]) * 0.6 + MathAbs(vel10) * 0.8) * MomentumSensitivity);
         cands[1].expected_move_pts = MathMax(cur_spread_pts * 2.2, (atr[0] / pt) * 0.40);
        }
     }

   // --- S3: Liquidity Sweep & Exhaustion Reversal ---
   if(g_strategies[2].enabled && ind_ok)
     {
      if(rsi[0] > 78.0 && mid > bb_u[0] && net10 < -1.0)
        {
         cands[2].valid = true; cands[2].strategy_id = 2; cands[2].direction = -1;
         cands[2].confidence = MathMin(92.0, (56.0 + (rsi[0] - 75.0) * 1.4) * EntrySensitivity);
         cands[2].expected_move_pts = MathMax(cur_spread_pts * 2.4, (mid - bb_m[0]) / pt * 0.5);
        }
      else if(rsi[0] < 22.0 && mid < bb_l[0] && net10 > 1.0)
        {
         cands[2].valid = true; cands[2].strategy_id = 2; cands[2].direction = 1;
         cands[2].confidence = MathMin(92.0, (56.0 + (25.0 - rsi[0]) * 1.4) * EntrySensitivity);
         cands[2].expected_move_pts = MathMax(cur_spread_pts * 2.4, (bb_m[0] - mid) / pt * 0.5);
        }
     }

   // --- S4: Volatility & Range Breakout ---
   if(g_strategies[3].enabled && ind_ok)
     {
      double hi = iHigh(_Symbol, PERIOD_M1, 1);
      double lo = iLow(_Symbol, PERIOD_M1, 1);
      if(bid > hi && vel10 > 1.5 && cons10 > 0.35)
        {
         cands[3].valid = true; cands[3].strategy_id = 3; cands[3].direction = 1;
         cands[3].confidence = MathMin(94.0, (58.0 + cons10 * 25.0) * EntrySensitivity);
         cands[3].expected_move_pts = MathMax(cur_spread_pts * 2.5, (atr[0] / pt) * 0.50);
        }
      else if(ask < lo && vel10 < -1.5 && cons10 < -0.35)
        {
         cands[3].valid = true; cands[3].strategy_id = 3; cands[3].direction = -1;
         cands[3].confidence = MathMin(94.0, (58.0 + MathAbs(cons10) * 25.0) * EntrySensitivity);
         cands[3].expected_move_pts = MathMax(cur_spread_pts * 2.5, (atr[0] / pt) * 0.50);
        }
     }

   // --- S5: Micro-Channel Range Scalping ---
   if(g_strategies[4].enabled && ind_ok && (g_current_regime == REGIME_SIDEWAYS_NARROW || g_current_regime == REGIME_SIDEWAYS_WIDE))
     {
      double band_span = (bb_u[0] - bb_l[0]);
      if(band_span > 0.0)
        {
         double pos_in_band = (mid - bb_l[0]) / band_span;
         if(pos_in_band < 0.18 && cons10 >= 0.0)
           {
            cands[4].valid = true; cands[4].strategy_id = 4; cands[4].direction = 1;
            cands[4].confidence = MathMin(90.0, (54.0 + (0.25 - pos_in_band) * 80.0) * EntrySensitivity);
            cands[4].expected_move_pts = MathMax(cur_spread_pts * 2.0, (bb_m[0] - mid) / pt);
           }
         else if(pos_in_band > 0.82 && cons10 <= 0.0)
           {
            cands[4].valid = true; cands[4].strategy_id = 4; cands[4].direction = -1;
            cands[4].confidence = MathMin(90.0, (54.0 + (pos_in_band - 0.75) * 80.0) * EntrySensitivity);
            cands[4].expected_move_pts = MathMax(cur_spread_pts * 2.0, (mid - bb_m[0]) / pt);
           }
        }
     }

   // --- S6: Z-Score Statistical Mean Reversion ---
   if(g_strategies[5].enabled && ind_ok)
     {
      double std_est = (bb_u[0] - bb_m[0]) / 2.0;
      if(std_est > pt)
        {
         double z = (mid - bb_m[0]) / std_est;
         if(z <= -2.1 && net10 > 0.0)
           {
            cands[5].valid = true; cands[5].strategy_id = 5; cands[5].direction = 1;
            cands[5].confidence = MathMin(92.0, (52.0 + MathAbs(z) * 10.0) * EntrySensitivity);
            cands[5].expected_move_pts = MathMax(cur_spread_pts * 2.2, MathAbs(mid - bb_m[0]) / pt * 0.45);
           }
         else if(z >= 2.1 && net10 < 0.0)
           {
            cands[5].valid = true; cands[5].strategy_id = 5; cands[5].direction = -1;
            cands[5].confidence = MathMin(92.0, (52.0 + MathAbs(z) * 10.0) * EntrySensitivity);
            cands[5].expected_move_pts = MathMax(cur_spread_pts * 2.2, MathAbs(mid - bb_m[0]) / pt * 0.45);
           }
        }
     }

   // --- S7: Ultra-Fast Tick Microstructure Imbalance (No Indicator Lag) ---
   if(g_strategies[6].enabled && TickScalpingEnabled && g_tick_count >= 15)
     {
      double min_tick_impulse = MathMax(3.0, cur_spread_pts * 0.85);
      if(net10 >= min_tick_impulse && cons10 >= 0.45 && vel10 > 3.0)
        {
         cands[6].valid = true; cands[6].strategy_id = 6; cands[6].direction = 1;
         cands[6].confidence = MathMin(97.0, (55.0 + cons10 * 30.0 + MathMin(15.0, vel10 * 0.5)) * MomentumSensitivity);
         cands[6].expected_move_pts = MathMax(cur_spread_pts * 2.2, net10 * 1.4);
        }
      else if(net10 <= -min_tick_impulse && cons10 <= -0.45 && vel10 < -3.0)
        {
         cands[6].valid = true; cands[6].strategy_id = 6; cands[6].direction = -1;
         cands[6].confidence = MathMin(97.0, (55.0 + MathAbs(cons10) * 30.0 + MathMin(15.0, MathAbs(vel10) * 0.5)) * MomentumSensitivity);
         cands[6].expected_move_pts = MathMax(cur_spread_pts * 2.2, MathAbs(net10) * 1.4);
        }
     }

   // --- S8: Kalman Filter Innovation & Autocorrelation Edge ---
   if(g_strategies[7].enabled && g_kalman_init && ind_ok)
     {
      double innovation_pts = (mid - g_kalman_x) / pt;
      double atr_pts = MathMax(10.0, atr[0] / pt);
      if(innovation_pts > atr_pts * 0.12 && net50 > 0.0)
        {
         cands[7].valid = true; cands[7].strategy_id = 7; cands[7].direction = 1;
         cands[7].confidence = MathMin(91.0, (53.0 + (innovation_pts / atr_pts) * 45.0) * EntrySensitivity);
         cands[7].expected_move_pts = MathMax(cur_spread_pts * 2.2, atr_pts * 0.35);
        }
      else if(innovation_pts < -atr_pts * 0.12 && net50 < 0.0)
        {
         cands[7].valid = true; cands[7].strategy_id = 7; cands[7].direction = -1;
         cands[7].confidence = MathMin(91.0, (53.0 + (MathAbs(innovation_pts) / atr_pts) * 45.0) * EntrySensitivity);
         cands[7].expected_move_pts = MathMax(cur_spread_pts * 2.2, atr_pts * 0.35);
        }
     }

   // --- S9: Trend-Reassessed Basket Recovery / Profit Pyramiding ---
   if(g_strategies[8].enabled && PyramidingEnabled && open_total > 0 && net_floating > 0.0)
     {
      double min_step = MathMax(cur_spread_pts * 1.5, 25.0) * pt;
      if(open_buy > 0 && open_sell == 0 && (bid - last_buy_price) >= min_step && cons10 > 0.30)
        {
         cands[8].valid = true; cands[8].strategy_id = 8; cands[8].direction = 1;
         cands[8].confidence = MathMin(95.0, 62.0 + cons10 * 25.0);
         cands[8].expected_move_pts = MathMax(cur_spread_pts * 2.2, min_step / pt);
        }
      else if(open_sell > 0 && open_buy == 0 && (last_sell_price - ask) >= min_step && cons10 < -0.30)
        {
         cands[8].valid = true; cands[8].strategy_id = 8; cands[8].direction = -1;
         cands[8].confidence = MathMin(95.0, 62.0 + MathAbs(cons10) * 25.0);
         cands[8].expected_move_pts = MathMax(cur_spread_pts * 2.2, min_step / pt);
        }
     }

   // Evaluate & Dispatch Qualifying Candidates (Parallel Multi-Strategy Execution)
   double effective_threshold = MathMax(25.0, MinimumSignalConfidence + GetAggrConfidenceOffset());
   bool any_candidate = false;

   for(int i = 0; i < TOTAL_STRATEGIES; i++)
     {
      if(!cands[i].valid) continue;
      any_candidate = true;
      g_cnt_candidates++;

      if(cands[i].direction == 1 && !AllowBuy)  { g_cnt_rejected++; continue; }
      if(cands[i].direction == -1 && !AllowSell) { g_cnt_rejected++; continue; }

      // Weighted Confidence Score
      double weighted_conf = MathMin(99.0, cands[i].confidence * g_strategies[i].weight);

      // Transaction Cost Edge Filter: Expected move must exceed spread + slippage buffer
      double min_required_move = cur_spread_pts * 1.35;
      if(cands[i].expected_move_pts < min_required_move)
        {
         g_cnt_rejected++;
         g_diag_status = DIAG_SPREAD_TOO_HIGH;
         continue;
        }

      if(weighted_conf < effective_threshold)
        {
         g_cnt_rejected++;
         g_diag_status = DIAG_SIGNAL_BELOW_THRESHOLD;
         continue;
        }

      // Multi-Entry Distance Check (Prevent duplicate stacked orders at identical tick price)
      if(open_total > 0)
        {
         if(!MultiEntryEnabled && cands[i].strategy_id != 8)
           {
            g_cnt_rejected++;
            continue;
           }
         double min_grid_gap = MathMax(cur_spread_pts * 0.8, 12.0) * pt;
         if(cands[i].direction == 1 && last_buy_price > 0.0 && MathAbs(ask - last_buy_price) < min_grid_gap)
           {
            g_cnt_rejected++;
            continue;
           }
         if(cands[i].direction == -1 && last_sell_price > 0.0 && MathAbs(bid - last_sell_price) < min_grid_gap)
           {
            g_cnt_rejected++;
            continue;
           }
        }

      // Signal Accepted!
      g_cnt_accepted++;
      g_last_signal_conf = weighted_conf;
      g_last_signal_dir  = cands[i].direction;
      g_diag_status      = DIAG_OK;

      double lot = CalculatePositionLot(cands[i].direction, weighted_conf, (cands[i].strategy_id == 8));
      if(lot <= 0.0)
        {
         g_diag_status = DIAG_INSUFFICIENT_MARGIN;
         continue;
        }

      if(ExecuteMarketOrder(cands[i].direction, lot, cands[i].strategy_id, weighted_conf))
        {
         open_total++;
         if(open_total >= max_pos || open_total >= MaximumPositionsPerSymbol)
            break;
        }
     }

   if(!any_candidate && g_diag_status == DIAG_OK)
      g_diag_status = DIAG_WAITING_SIGNAL;
  }

//+------------------------------------------------------------------+
//| Extreme Position Sizing & Exponential Compounding Engine         |
//+------------------------------------------------------------------+
double CalculatePositionLot(int direction, double confidence, bool is_pyramid)
  {
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double fm  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(fm <= 0.0) return 0.0;

   double min_lot  = g_sym.LotsMin();
   double max_lot  = g_sym.LotsMax();
   double step_lot = g_sym.LotsStep();
   if(min_lot <= 0.0)  min_lot  = 0.01;
   if(step_lot <= 0.0) step_lot = 0.01;
   if(MaximumLot > 0.0 && MaximumLot < max_lot) max_lot = MaximumLot;

   // Exponential Equity Growth Factor: (Current Equity / Reference Equity) ^ CompoundingExponent
   double growth_factor = 1.0;
   if(CompoundingEnabled && g_reference_equity > 0.0 && eq > 0.0)
     {
      double ratio = MathMax(0.25, eq / g_reference_equity);
      growth_factor = MathPow(ratio, CompoundingExponent);
     }

   double conf_factor = 0.75 + (confidence / 100.0) * 0.65;
   double aggr_factor = LotMultiplier * GetAggrLotScale();
   double pyr_factor  = is_pyramid ? PyramidingMultiplier : 1.0;

   double raw_lot = BaseLot;

   switch(LotMode)
     {
      case LOT_FIXED:
         raw_lot = BaseLot * pyr_factor;
         break;
      case LOT_BALANCE_BASED:
         raw_lot = (bal / 1000.0) * BaseLot * aggr_factor * pyr_factor;
         break;
      case LOT_EQUITY_BASED:
         raw_lot = (eq / 1000.0) * BaseLot * aggr_factor * pyr_factor;
         break;
      case LOT_FREE_MARGIN_BASED:
         raw_lot = (fm / 1000.0) * BaseLot * aggr_factor * pyr_factor;
         break;
      case LOT_DYNAMIC_CONFIDENCE:
         raw_lot = BaseLot * conf_factor * aggr_factor * pyr_factor;
         break;
      case LOT_EXP_COMPOUNDING:
         raw_lot = BaseLot * growth_factor * conf_factor * aggr_factor * pyr_factor;
         break;
      case LOT_MAX_MARGIN_UTIL:
        {
         double margin_per_lot = 0.0;
         ENUM_ORDER_TYPE otype = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double price = (direction == 1) ? g_sym.Ask() : g_sym.Bid();
         if(OrderCalcMargin(otype, _Symbol, 1.0, price, margin_per_lot) && margin_per_lot > 0.0)
           {
            double target_margin = fm * (MarginUtilizationPercent / 100.0) * 0.25; // Per-position slice
            raw_lot = (target_margin / margin_per_lot) * conf_factor;
           }
         break;
        }
     }

   // Normalize to broker step
   double norm_lot = MathFloor(raw_lot / step_lot) * step_lot;
   norm_lot = MathMax(min_lot, MathMin(max_lot, norm_lot));

   // Verify Free Margin & Margin Utilization Ceiling
   double req_margin = 0.0;
   ENUM_ORDER_TYPE otype = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double price = (direction == 1) ? g_sym.Ask() : g_sym.Bid();

   if(OrderCalcMargin(otype, _Symbol, norm_lot, price, req_margin))
     {
      double max_allowed_margin = fm * (MarginUtilizationPercent / 100.0);
      if(req_margin > max_allowed_margin && req_margin > 0.0)
        {
         double scaled = norm_lot * (max_allowed_margin / req_margin);
         norm_lot = MathFloor(scaled / step_lot) * step_lot;
        }
     }

   if(norm_lot < min_lot)
      return 0.0;

   return NormalizeDouble(norm_lot, 2);
  }

//+------------------------------------------------------------------+
//| Rate-Limited Order Execution with State Integrity                |
//+------------------------------------------------------------------+
bool ExecuteMarketOrder(int direction, double lot, int strategy_id, double confidence)
  {
   // Rate Limiter check
   uint sec_now = (uint)TimeCurrent();
   if(sec_now != g_req_second_stamp)
     {
      g_req_second_stamp = sec_now;
      g_req_count_in_sec = 0;
     }
   if(g_req_count_in_sec >= MaximumRequestsPerSecond)
      return false;

   g_sym.RefreshRates();
   double pt     = g_sym.Point();
   int    digits = g_sym.Digits();
   double price  = (direction == 1) ? g_sym.Ask() : g_sym.Bid();

   // Calculate TP / SL
   double tp = 0.0, sl = 0.0;
   double tp_pts = (double)TakeProfitPoints;

   if(TakeProfitMode == TP_ATR_DYNAMIC)
     {
      double atr[1];
      if(CopyBuffer(g_h_atr, 0, 0, 1, atr) == 1 && atr[0] > 0.0)
         tp_pts = MathMax((double)TakeProfitPoints * 0.5, (atr[0] / pt) * 0.55);
     }
   else if(TakeProfitMode == TP_TICK_VELOCITY)
     {
      double spr_pts = (g_sym.Ask() - g_sym.Bid()) / pt;
      tp_pts = MathMax(25.0, spr_pts * 2.2);
     }

   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(tp_pts < (double)stops_level + 5.0) tp_pts = (double)stops_level + 10.0;

   if(TakeProfitMode != TP_MONEY_TARGET)
     {
      tp = (direction == 1) ? NormalizeDouble(price + tp_pts * pt, digits)
                            : NormalizeDouble(price - tp_pts * pt, digits);
     }

   if(EnableStopLoss && StopLossMode != SL_NONE)
     {
      double sl_pts = (double)StopLossPoints;
      if(StopLossMode == SL_ATR_DYNAMIC)
        {
         double atr[1];
         if(CopyBuffer(g_h_atr, 0, 0, 1, atr) == 1 && atr[0] > 0.0)
            sl_pts = MathMax((double)StopLossPoints * 0.6, (atr[0] / pt) * 1.4);
        }
      if(sl_pts < (double)stops_level + 5.0) sl_pts = (double)stops_level + 10.0;
      sl = (direction == 1) ? NormalizeDouble(price - sl_pts * pt, digits)
                            : NormalizeDouble(price + sl_pts * pt, digits);
     }

   string comment = StringFormat("TMKVX_S%d_C%.0f", strategy_id, confidence);

   g_engine_state = STATE_ENTRY_REQUESTED;
   g_cnt_entry_attempts++;
   g_req_count_in_sec++;

   bool sent = false;
   for(int attempt = 0; attempt < MathMax(1, RetryLimit); attempt++)
     {
      g_sym.RefreshRates();
      price = (direction == 1) ? g_sym.Ask() : g_sym.Bid();

      if(direction == 1)
         sent = g_trade.Buy(lot, _Symbol, price, sl, tp, comment);
      else
         sent = g_trade.Sell(lot, _Symbol, price, sl, tp, comment);

      g_last_retcode = g_trade.ResultRetcode();

      if(sent && (g_last_retcode == TRADE_RETCODE_DONE || g_last_retcode == TRADE_RETCODE_PLACED || g_last_retcode == TRADE_RETCODE_DONE_PARTIAL))
        {
         g_cnt_entry_success++;
         g_last_entry_msc = GetTickCount64();
         g_engine_state   = STATE_POSITION_ACTIVE;
         if(EnableSignalLog)
            PrintFormat("[TamaK Vx ENTRY] %s %.2f lots @ %.5f | Strat:S%d | Conf:%.1f",
                        (direction == 1 ? "BUY" : "SELL"), lot, price, strategy_id, confidence);
         return true;
        }

      // Non-retryable fatal codes
      if(g_last_retcode == TRADE_RETCODE_NO_MONEY || g_last_retcode == TRADE_RETCODE_INVALID_VOLUME ||
         g_last_retcode == TRADE_RETCODE_MARKET_CLOSED || g_last_retcode == TRADE_RETCODE_TRADE_DISABLED)
         break;
     }

   g_cnt_entry_failed++;
   g_last_reject_reason = StringFormat("Retcode %u: %s", g_last_retcode, g_trade.ResultRetcodeDescription());
   g_diag_status        = DIAG_ORDER_REJECTED;
   g_engine_state       = STATE_SCANNING;

   if(EnableExecutionLog)
      PrintFormat("[TamaK Vx REJECT] %s %.2f lots | %s", (direction == 1 ? "BUY" : "SELL"), lot, g_last_reject_reason);

   return false;
  }

//+------------------------------------------------------------------+
//| Tier 1: Ultra-Responsive Exit, Basket TP & Virtual Trailing      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   int total = PositionsTotal();
   if(total == 0) return;

   double net_basket_pnl = 0.0;
   int    ea_pos_count   = 0;
   double pt             = g_sym.Point();
   int    digits         = g_sym.Digits();
   long   stops_level    = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   ulong  now_sec        = (ulong)TimeCurrent();

   for(int i = total - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() != MagicNumber || g_pos.Symbol() != _Symbol) continue;

      ulong  ticket = g_pos.Ticket();
      double pnl    = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      double open_p = g_pos.PriceOpen();
      double cur_p  = g_pos.PriceCurrent();
      double vol    = g_pos.Volume();
      long   ptype  = g_pos.PositionType();
      ulong  open_t = (ulong)g_pos.Time();

      net_basket_pnl += pnl;
      ea_pos_count++;

      // 1. Time-Based Max Holding Exit
      if(MaximumHoldingSeconds > 0 && (now_sec - open_t) >= (ulong)MaximumHoldingSeconds)
        {
         g_trade.PositionClose(ticket, MaximumDeviationPoints);
         continue;
        }

      // 2. Money-Based Individual Take Profit
      if(TakeProfitMode == TP_MONEY_TARGET && TakeProfitMoney > 0.0 && pnl >= TakeProfitMoney)
        {
         g_trade.PositionClose(ticket, MaximumDeviationPoints);
         continue;
        }

      // 3. Partial Profit Realization at 65% of Money TP
      int vidx = GetOrCreateVirtualTracker(ticket, pnl, cur_p);
      if(PartialCloseEnabled && !g_vtrack[vidx].partial_done && TakeProfitMoney > 0.0 && pnl >= TakeProfitMoney * 0.65)
        {
         double step_lot = g_sym.LotsStep();
         double min_lot  = g_sym.LotsMin();
         double half_vol = MathFloor((vol * 0.5) / step_lot) * step_lot;
         if(half_vol >= min_lot && (vol - half_vol) >= min_lot)
           {
            if(g_trade.PositionClosePartial(ticket, half_vol, MaximumDeviationPoints))
               g_vtrack[vidx].partial_done = true;
           }
        }

      // 4. Peak Profit Tracking & Virtual Trailing (Sub-StopLevel Ultra-Fast Lock)
      if(pnl > g_vtrack[vidx].peak_profit_money)
        {
         g_vtrack[vidx].peak_profit_money = pnl;
         g_vtrack[vidx].peak_price        = cur_p;
        }

      double profit_pts = (ptype == POSITION_TYPE_BUY) ? ((cur_p - open_p) / pt) : ((open_p - cur_p) / pt);
      double peak_pts   = (ptype == POSITION_TYPE_BUY) ? ((g_vtrack[vidx].peak_price - open_p) / pt)
                                                       : ((open_p - g_vtrack[vidx].peak_price) / pt);

      if(TrailingEnabled && peak_pts >= (double)TrailingStartPoints)
        {
         if(VirtualTrailingEnabled)
           {
            double retrace_pts = peak_pts - profit_pts;
            if(retrace_pts >= (double)TrailingDistancePoints && pnl > 0.0)
              {
               g_trade.PositionClose(ticket, MaximumDeviationPoints);
               continue;
              }
           }
         else
           {
            double min_dist = MathMax((double)TrailingDistancePoints, (double)stops_level + 5.0);
            if(ptype == POSITION_TYPE_BUY)
              {
               double new_sl = NormalizeDouble(cur_p - min_dist * pt, digits);
               if(new_sl > open_p && (g_pos.StopLoss() == 0.0 || new_sl - g_pos.StopLoss() >= TrailingStepPoints * pt))
                  g_trade.PositionModify(ticket, new_sl, g_pos.TakeProfit());
              }
            else
              {
               double new_sl = NormalizeDouble(cur_p + min_dist * pt, digits);
               if(new_sl < open_p && (g_pos.StopLoss() == 0.0 || g_pos.StopLoss() - new_sl >= TrailingStepPoints * pt))
                  g_trade.PositionModify(ticket, new_sl, g_pos.TakeProfit());
              }
           }
        }
     }

   // 5. Collective Basket Take Profit
   if(BasketTakeProfitEnabled && ea_pos_count > 0 && BasketTakeProfitMoney > 0.0 && net_basket_pnl >= BasketTakeProfitMoney)
     {
      ClosePositionsByFilter(0); // Close all EA positions on symbol
     }
  }

//+------------------------------------------------------------------+
//| Virtual Tracker Registry Helper                                  |
//+------------------------------------------------------------------+
int GetOrCreateVirtualTracker(ulong ticket, double cur_pnl, double cur_price)
  {
   int sz = ArraySize(g_vtrack);
   for(int i = 0; i < sz; i++)
     {
      if(g_vtrack[i].ticket == ticket)
         return i;
     }
   ArrayResize(g_vtrack, sz + 1);
   g_vtrack[sz].ticket            = ticket;
   g_vtrack[sz].peak_profit_money = cur_pnl;
   g_vtrack[sz].peak_price        = cur_price;
   g_vtrack[sz].partial_done      = false;
   return sz;
  }

//+------------------------------------------------------------------+
//| Configurable Financial Risk Guardrails                           |
//+------------------------------------------------------------------+
bool CheckRiskPolicy(double eq, double bal)
  {
   if(RiskProfile == RISK_PROFILE_C_UNRESTRICTED || AggressivenessLevel == AGGR_L8_UNRESTRICTED_RES)
      return true;

   if(EmergencyStopEnabled)
     {
      double m_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(m_level > 0.0 && m_level < 30.0)
        {
         g_diag_status = DIAG_INSUFFICIENT_MARGIN;
         return false;
        }
     }

   if(EnableDailyLossLimit && g_day_start_balance > 0.0)
     {
      double day_loss_pct = ((g_day_start_balance - eq) / g_day_start_balance) * 100.0;
      if(day_loss_pct >= DailyLossLimitPercent)
        {
         g_diag_status = DIAG_RISK_LIMIT_HIT;
         return false;
        }
     }

   if(EnableDrawdownLimit && g_peak_equity > 0.0)
     {
      double dd_pct = ((g_peak_equity - eq) / g_peak_equity) * 100.0;
      if(dd_pct >= MaximumDrawdownPercent)
        {
         g_diag_status = DIAG_RISK_LIMIT_HIT;
         return false;
        }
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Scan Active EA Positions                                         |
//+------------------------------------------------------------------+
void ScanActivePositions(int &total, int &buy_cnt, int &sell_cnt, double &buy_lot, double &sell_lot,
                         double &net_flt, double &last_buy_p, double &last_sell_p)
  {
   total = 0; buy_cnt = 0; sell_cnt = 0;
   buy_lot = 0.0; sell_lot = 0.0; net_flt = 0.0;
   last_buy_p = 0.0; last_sell_p = 0.0;
   ulong latest_buy_t = 0, latest_sell_t = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() != MagicNumber || g_pos.Symbol() != _Symbol) continue;

      total++;
      double pnl = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      net_flt += pnl;

      if(g_pos.PositionType() == POSITION_TYPE_BUY)
        {
         buy_cnt++;
         buy_lot += g_pos.Volume();
         if((ulong)g_pos.TimeMsc() >= latest_buy_t)
           {
            latest_buy_t = (ulong)g_pos.TimeMsc();
            last_buy_p   = g_pos.PriceOpen();
           }
        }
      else
        {
         sell_cnt++;
         sell_lot += g_pos.Volume();
         if((ulong)g_pos.TimeMsc() >= latest_sell_t)
           {
            latest_sell_t = (ulong)g_pos.TimeMsc();
            last_sell_p   = g_pos.PriceOpen();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Close EA Positions by Filter (0=All, 1=Profit, 2=Loss, 3=Buy, 4=Sell) |
//+------------------------------------------------------------------+
void ClosePositionsByFilter(int filter_mode)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic() != MagicNumber || g_pos.Symbol() != _Symbol) continue;

      double pnl = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      long   pt  = g_pos.PositionType();

      bool match = false;
      if(filter_mode == 0) match = true;
      else if(filter_mode == 1 && pnl > 0.0) match = true;
      else if(filter_mode == 2 && pnl < 0.0) match = true;
      else if(filter_mode == 3 && pt == POSITION_TYPE_BUY) match = true;
      else if(filter_mode == 4 && pt == POSITION_TYPE_SELL) match = true;

      if(match)
         g_trade.PositionClose(g_pos.Ticket(), MaximumDeviationPoints);
     }
  }

//+------------------------------------------------------------------+
//| Accurate Closed Deal History Aggregation                         |
//+------------------------------------------------------------------+
void RecalculateClosedHistoryStats()
  {
   g_stat_total_trades = 0;
   g_stat_wins         = 0;
   g_stat_losses       = 0;
   g_stat_gross_profit = 0.0;
   g_stat_gross_loss   = 0.0;
   g_stat_net_profit   = 0.0;
   g_stat_today_profit = 0.0;

   if(!HistorySelect(0, TimeCurrent())) return;

   MqlDateTime dt_now;
   TimeCurrent(dt_now);

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
     {
      ulong d_ticket = HistoryDealGetTicket(i);
      if(d_ticket == 0) continue;

      long magic = HistoryDealGetInteger(d_ticket, DEAL_MAGIC);
      long dtype = HistoryDealGetInteger(d_ticket, DEAL_TYPE);
      long entry = HistoryDealGetInteger(d_ticket, DEAL_ENTRY);

      // Ignore deposits/withdrawals/balance ops
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL) continue;
      if(magic != (long)MagicNumber) continue;
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;

      double net = HistoryDealGetDouble(d_ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(d_ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(d_ticket, DEAL_COMMISSION);

      g_stat_total_trades++;
      g_stat_net_profit += net;
      if(net >= 0.0)
        {
         g_stat_wins++;
         g_stat_gross_profit += net;
        }
      else
        {
         g_stat_losses++;
         g_stat_gross_loss += MathAbs(net);
        }

      datetime d_time = (datetime)HistoryDealGetInteger(d_ticket, DEAL_TIME);
      MqlDateTime dt_d;
      TimeToStruct(d_time, dt_d);
      if(dt_d.year == dt_now.year && dt_d.day_of_year == dt_now.day_of_year)
         g_stat_today_profit += net;
     }
  }

//+------------------------------------------------------------------+
//| Simple Professional Dark-Theme Dashboard                         |
//+------------------------------------------------------------------+
void CreateDashboard()
  {
   int x = DashboardX;
   int y = DashboardY;
   int w = DashboardWidth;
   int h = ShowTradeButtons ? 395 : 325;

   CreateRect(UI_PREFIX + "BG", x, y, w, h, C'18,22,30', C'48,58,78');
   CreateLabel(UI_PREFIX + "TITLE", x + 12, y + 8, "TamaK Vx", DashboardFontSize + 3, clrWhite, true);
   CreateLabel(UI_PREFIX + "SUB", x + 12, y + 26, "EXTREME PROFIT ENGINE", DashboardFontSize - 1, clrDeepSkyBlue, true);

   string rows[16] =
     {
      "ACC_BAL", "ACC_EQ", "ACC_FLT", "ACC_DAY", "ACC_TOT", "ACC_MRG",
      "PERF_WR", "PERF_TR", "PERF_PF", "PERF_DD",
      "ACT_POS", "ACT_LOT", "ACT_SPR", "ACT_REG", "ACT_CNF", "ACT_STS"
     };

   int ry = y + 48;
   for(int i = 0; i < 16; i++)
     {
      if(i == 6 || i == 10) ry += 8; // Section spacing
      CreateLabel(UI_PREFIX + rows[i] + "_L", x + 12, ry, "", DashboardFontSize, clrSilver, false);
      CreateLabel(UI_PREFIX + rows[i] + "_V", x + 155, ry, "", DashboardFontSize, clrWhite, true);
      ry += 16;
     }

   if(ShowTradeButtons)
     {
      int by = y + 322;
      int bw = (w - 30) / 2;
      CreateButton(UI_PREFIX + "BTN_TOGGLE", x + 10, by, bw, 20, "START / PAUSE", C'30,110,180');
      CreateButton(UI_PREFIX + "BTN_CLOSE_ALL", x + 20 + bw, by, bw, 20, "CLOSE ALL", C'180,45,55');
      by += 24;
      CreateButton(UI_PREFIX + "BTN_CLOSE_PROF", x + 10, by, bw, 20, "CLOSE PROFIT", C'35,140,80');
      CreateButton(UI_PREFIX + "BTN_CLOSE_LOSS", x + 20 + bw, by, bw, 20, "CLOSE LOSS", C'160,95,30');
      by += 24;
      CreateButton(UI_PREFIX + "BTN_CLOSE_BUY", x + 10, by, bw, 20, "CLOSE BUY", C'55,65,85');
      CreateButton(UI_PREFIX + "BTN_CLOSE_SELL", x + 20 + bw, by, bw, 20, "CLOSE SELL", C'55,65,85');
     }

   UpdateDashboard();
  }

void UpdateDashboard()
  {
   if(!ShowDashboard) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double ml  = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);

   int tot_p = 0, buy_p = 0, sell_p = 0;
   double buy_l = 0.0, sell_l = 0.0, flt = 0.0, lb = 0.0, ls = 0.0;
   ScanActivePositions(tot_p, buy_p, sell_p, buy_l, sell_l, flt, lb, ls);

   double cur_dd = (g_peak_equity > 0.0) ? ((g_peak_equity - eq) / g_peak_equity * 100.0) : 0.0;
   string wr_str = (g_stat_total_trades > 0) ? StringFormat("%.1f%%", 100.0 * g_stat_wins / g_stat_total_trades) : "N/A";
   string pf_str = (g_stat_gross_loss > 0.0) ? StringFormat("%.2f", g_stat_gross_profit / g_stat_gross_loss)
                                             : (g_stat_gross_profit > 0.0 ? "INF" : "N/A");

   double spr = (g_sym.Ask() - g_sym.Bid()) / g_sym.Point();

   SetRow("ACC_BAL", "Balance:", StringFormat("%.2f", bal), clrWhite);
   SetRow("ACC_EQ",  "Equity:", StringFormat("%.2f", eq), clrWhite);
   SetRow("ACC_FLT", "Floating P/L:", StringFormat("%+.2f", flt), flt >= 0 ? clrLimeGreen : clrTomato);
   SetRow("ACC_DAY", "Today P/L:", StringFormat("%+.2f", g_stat_today_profit), g_stat_today_profit >= 0 ? clrLimeGreen : clrTomato);
   SetRow("ACC_TOT", "Total EA P/L:", StringFormat("%+.2f", g_stat_net_profit), g_stat_net_profit >= 0 ? clrLimeGreen : clrTomato);
   SetRow("ACC_MRG", "FreeMrg / Lvl:", StringFormat("%.0f (%.0f%%)", fm, ml), clrDeepSkyBlue);

   SetRow("PERF_WR", "Win Rate:", wr_str, clrWhite);
   SetRow("PERF_TR", "Trades (W/L):", StringFormat("%d (%d/%d)", g_stat_total_trades, g_stat_wins, g_stat_losses), clrWhite);
   SetRow("PERF_PF", "Profit Factor:", pf_str, clrWhite);
   SetRow("PERF_DD", "DD (Cur/Max):", StringFormat("%.1f%% / %.1f%%", cur_dd, g_max_drawdown_pct), cur_dd > 15.0 ? clrGold : clrSilver);

   SetRow("ACT_POS", "Positions (B/S):", StringFormat("%d (%d / %d)", tot_p, buy_p, sell_p), clrDeepSkyBlue);
   SetRow("ACT_LOT", "Total Lot:", StringFormat("%.2f", buy_l + sell_l), clrWhite);
   SetRow("ACT_SPR", "Spread (pts):", StringFormat("%.1f", spr), clrWhite);
   SetRow("ACT_REG", "Regime:", EnumToString(g_current_regime), clrGold);
   SetRow("ACT_CNF", "Signal Conf:", StringFormat("%.1f%% (%s)", g_last_signal_conf, (g_last_signal_dir > 0 ? "BUY" : (g_last_signal_dir < 0 ? "SELL" : "-"))), clrDeepSkyBlue);
   SetRow("ACT_STS", "Status / Lvl:", StringFormat("L%d | %s", AggressivenessLevel, (g_engine_paused ? "PAUSED" : "ACTIVE")), g_engine_paused ? clrGold : clrLimeGreen);

   ChartRedraw(0);
  }

void SetRow(string key, string lbl, string val, color val_clr)
  {
   ObjectSetString(0, UI_PREFIX + key + "_L", OBJPROP_TEXT, lbl);
   ObjectSetString(0, UI_PREFIX + key + "_V", OBJPROP_TEXT, val);
   ObjectSetInteger(0, UI_PREFIX + key + "_V", OBJPROP_COLOR, val_clr);
  }

void CreateRect(string name, int x, int y, int w, int h, color bg, color brd)
  {
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, DashboardCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, brd);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
  }

void CreateLabel(string name, int x, int y, string text, int sz, color clr, bool bold)
  {
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, DashboardCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
  }

void CreateButton(string name, int x, int y, int w, int h, string text, color bg)
  {
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, DashboardCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, DashboardFontSize - 1);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
  }

void DestroyDashboard()
  {
   ObjectsDeleteAll(0, UI_PREFIX);
  }

//+------------------------------------------------------------------+
//| Interactive Dashboard Button Events                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == UI_PREFIX + "BTN_TOGGLE")
     {
      g_engine_paused = !g_engine_paused;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      UpdateDashboard();
     }
   else if(sparam == UI_PREFIX + "BTN_CLOSE_ALL")
     {
      ClosePositionsByFilter(0);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
     }
   else if(sparam == UI_PREFIX + "BTN_CLOSE_PROF")
     {
      ClosePositionsByFilter(1);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
     }
   else if(sparam == UI_PREFIX + "BTN_CLOSE_LOSS")
     {
      ClosePositionsByFilter(2);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
     }
   else if(sparam == UI_PREFIX + "BTN_CLOSE_BUY")
     {
      ClosePositionsByFilter(3);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
     }
   else if(sparam == UI_PREFIX + "BTN_CLOSE_SELL")
     {
      ClosePositionsByFilter(4);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
     }
  }
//+------------------------------------------------------------------+
