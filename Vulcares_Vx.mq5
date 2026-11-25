//+------------------------------------------------------------------+
//|                                               Vulcares_Vx_V2.mq5 |
//|                                  Copyright 2026, Vulcares Quant  |
//|  ALWAYS-IN-MARKET MASSIVE ADAPTIVE DOMINANCE SCALPING ENGINE     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vulcares Quant"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enumerations
enum ENUM_OPERATING_MODE
{
   MODE_CONTINUOUS_DOMINANCE = 0, // MODE A: Continuous Dominance (Always-In-Market)
   MODE_VOLATILITY_SPECIALIST= 1, // MODE B: High & Extreme Volatility Specialist
   MODE_EXTREME_MOMENTUM     = 2  // MODE C: Explosive Tick Momentum Only
};

enum ENUM_USER_CONTROL
{
   CTRL_EA_ON                = 0,
   CTRL_EA_OFF               = 1,
   CTRL_SOFT_STOP_REQUESTED  = 2,
   CTRL_STOPPED              = 3,
   CTRL_EMERGENCY_LOCKED     = 4
};

enum ENUM_EXEC_STATE
{
   STATE_INITIALIZING,
   STATE_SCANNING,
   STATE_ANALYZING,
   STATE_ENTRY_PENDING,
   STATE_POSITION_ACTIVE,
   STATE_TRAILING_ACTIVE,
   STATE_STOPPING_AFTER_POS,
   STATE_STOPPED,
   STATE_RISK_LOCKED,
   STATE_EMERGENCY_LOCKED,
   STATE_RECOVERY,
   STATE_DISCONNECTED
};

enum ENUM_VOL_REGIME
{
   REGIME_DORMANT,
   REGIME_LOW_VOL,
   REGIME_NORMAL,
   REGIME_HIGH_VOL,
   REGIME_EXTREME_VOL,
   REGIME_EXPLOSIVE_MOM,
   REGIME_TOXIC_VOL
};

enum ENUM_TRAILING_PHASE
{
   PHASE_0_INSTANT_PROT,
   PHASE_1_MICRO_PROT,
   PHASE_2_RAPID_BE,
   PHASE_3_NET_PROFIT_LOCK,
   PHASE_4_MOM_COMPRESSION,
   PHASE_5_EXTREME_PRESERVE,
   PHASE_6_INTELLIGENT_EXIT
};

enum ENUM_ENTRY_METHOD
{
   ENTRY_METHOD_MARKET       = 0,
   ENTRY_METHOD_DYNAMIC_STOP = 1
};

enum ENUM_STRATEGY_STATUS
{
   STRAT_ACTIVE,
   STRAT_HIGH_PRIORITY,
   STRAT_LOW_PRIORITY,
   STRAT_DEGRADED,
   STRAT_QUARANTINED
};

//--- Input Parameters (Section 21 Default Settings V2)
input group "=== 1. SYSTEM & OPERATING MODE ==="
input string              InpEAName                   = "Vulcares Vx";
input ENUM_OPERATING_MODE InpTradingMode              = MODE_CONTINUOUS_DOMINANCE;
input ulong               InpMagicNumber              = 20260999;
input bool                InpAllowRealMoneyTrading    = false; // Must be explicitly set true for real accounts
input bool                InpResetInitialCapital      = false; // One-time explicit reset when flat

input group "=== 2. FIXED INITIAL CAPITAL RISK (1% FLAT) ==="
input double              InpInitialCapital           = 1000.00; // Baseline Capital (USC)
input double              InpRiskPercent              = 1.00;    // 1.00% Fixed Risk = 10 USC
input double              InpCostSlippageBufferPct    = 20.0;    // 20% initial cost/slippage reserve
input double              InpDailyLossLimitPct        = 5.00;    // 50 USC on 1000 USC
input double              InpWeeklyLossLimitPct       = 8.00;    // 80 USC on 1000 USC
input double              InpMaxInitialDDPct          = 10.00;   // 100 USC Hard Stop
input double              InpMaxPeakDDPct             = 10.00;   // 10% Trailing Peak Equity DD
input int                 InpMaxConsecutiveLosses     = 3;
input int                 InpLossCooldownMinutes      = 30;
input double              InpDailyProfitFloorTrigPct  = 5.00;
input double              InpDailyProfitRetainPct     = 75.0;

input group "=== 3. ALWAYS-IN-MARKET & DOMINANCE ENGINE ==="
input bool                InpAlwaysInMarketMode       = true;
input bool                InpAutoReEntry              = true;
input bool                InpAutoReversalEvaluation   = true;
input double              InpMinNetUtilityAdvantage   = 0.05;    // Minimum utility spread for continuous entry
input int                 InpMinimumReEntryDelayMs    = 0;       // 0ms ideal continuous re-entry
input ENUM_ENTRY_METHOD   InpPreferredEntryMode       = ENTRY_METHOD_MARKET;
input int                 InpPendingExpirySec         = 12;

input group "=== 4. HYPER-AGGRESSIVE NET-PROFIT TRAILING V2 ==="
input bool                InpDynamicTrailingStop      = true;
input bool                InpTickBasedTrailing        = true;
input bool                InpNetProfitTrailing        = true;
input double              InpTrailingStartR           = 0.15;
input double              InpBreakEvenTriggerR        = 0.40;
input int                 InpTradeRequestIntervalMs   = 150;
input double              InpMaxInitialSL_ATRMult     = 1.60;
input double              InpMinInitialSL_ATRMult     = 0.55;

input group "=== 5. SPREAD, LATENCY & NEWS GUARD ==="
input double              InpMaxSpreadToATRRatio      = 0.22;
input double              InpMaxSpreadToSLRatio       = 0.28;
input int                 InpMaxQuoteAgeMs            = 1200;
input double              InpMinMarginLevel           = 500.0;
input double              InpMaxMarginUsagePct        = 20.0;
input bool                InpNewsProtection           = true;
input bool                InpPostNewsMomentumMode     = true;
input int                 InpNewsBlockBeforeMin       = 5;
input int                 InpNewsBlockAfterMin        = 2;

input group "=== 6. PROFESSIONAL CONTROL CENTER ==="
input bool                InpShowProfessionalDashboard= true;
input bool                InpCompactDashboard         = false;

//--- Structures
struct TickSample
{
   long   time_msc;
   double bid;
   double ask;
   double mid;
   double spread;
   int    dir;
};

struct StrategyUnit
{
   int                  id;
   string               name;
   int                  family; // 0:Trend, 1:Momentum, 2:Volatility, 3:Structure, 4:Microstructure, 5:Statistical
   double               base_weight;
   double               reliability;
   double               independence;
   double               buy_score;
   double               sell_score;
   double               expected_rr;
   int                  trades_count;
   int                  wins_count;
   double               ewma_pnl;
   ENUM_STRATEGY_STATUS status;
};

struct DominanceResult
{
   double buy_dominance_pct;
   double sell_dominance_pct;
   double buy_final_utility;
   double sell_final_utility;
   double directional_agreement;
   double market_uncertainty;
   double feature_reliability;
   double signal_quality;
   double rec_sl_dist;
   int    dominant_dir; // +1 BUY, -1 SELL, 0 NEUTRAL
   int    buy_supporters;
   int    sell_supporters;
   string top_strategy_name;
   int    top_strategy_id;
};

struct PersistentState
{
   double   initial_capital;
   bool     baseline_initialized;
   double   equity_peak;
   double   daily_start_balance;
   double   daily_profit_peak;
   double   weekly_start_balance;
   int      period_year;
   int      period_yday;
   int      period_week_id;
   int      consecutive_losses;
   int      consecutive_wins;
   datetime cooldown_until;
   int      user_control; // ENUM_USER_CONTROL
   bool     hard_dd_locked;
   ulong    active_ticket;
   int      active_strategy_id;
   double   initial_sl_price;
   double   highest_fav_price;
   double   lowest_adv_price;
   double   max_fav_net_profit;
   double   last_confirmed_sl;
   int      sl_mod_count;
   // Cumulative Statistics
   int      total_trades;
   int      win_trades;
   int      loss_trades;
   int      be_trades;
   double   gross_profit;
   double   gross_loss;
   double   largest_win;
   double   largest_loss;
   long     active_exposure_ms;
   long     eligible_market_ms;
};

//--- Global Engine Objects
CTrade        g_trade;
CSymbolInfo   g_symbol;
CPositionInfo g_pos;
COrderInfo    g_ord;

ENUM_EXEC_STATE     g_exec_state   = STATE_INITIALIZING;
ENUM_VOL_REGIME     g_regime       = REGIME_NORMAL;
ENUM_TRAILING_PHASE g_trail_phase  = PHASE_0_INSTANT_PROT;
PersistentState     g_persist;
DominanceResult     g_dom;

// Cached Indicator Handles
int g_hATR_7 = INVALID_HANDLE, g_hATR_14 = INVALID_HANDLE, g_hATR_50 = INVALID_HANDLE;
int g_hEMA_8_M15 = INVALID_HANDLE, g_hEMA_21_M15 = INVALID_HANDLE, g_hEMA_55_M15 = INVALID_HANDLE;
int g_hEMA_5_M5  = INVALID_HANDLE, g_hEMA_13_M5  = INVALID_HANDLE, g_hEMA_34_M5  = INVALID_HANDLE;
int g_hEMA_3_M1  = INVALID_HANDLE, g_hEMA_8_M1   = INVALID_HANDLE, g_hEMA_21_M1  = INVALID_HANDLE;
int g_hRSI_7_M1  = INVALID_HANDLE, g_hRSI_14_M1  = INVALID_HANDLE;
int g_hADX_14_M5 = INVALID_HANDLE, g_hCCI_14_M1  = INVALID_HANDLE;
int g_hBB_20_M1  = INVALID_HANDLE, g_hMACD_M1    = INVALID_HANDLE;

// Circular Tick Buffer (8192 ticks for multi-horizon synthetic sub-minute bars)
#define TICK_BUF_SIZE 8192
TickSample g_ticks[TICK_BUF_SIZE];
int        g_tick_head  = 0;
int        g_tick_count = 0;
long       g_last_tick_msc = 0;

// Strategy Registry (24 Orthogonal Parametric Strategy Engines representing 128,400 feature combinations)
#define MAX_STRATEGIES 24
StrategyUnit g_strategies[MAX_STRATEGIES];

// Runtime Telemetry
string g_validated_symbol   = "";
string g_gv_prefix          = "";
string g_lock_gv_name       = "";
string g_reject_reason      = "NONE";
uint   g_last_retcode       = 0;
int    g_vol_score          = 50;
double g_trend_strength     = 0.0;
double g_mom_strength       = 0.0;
double g_rev_strength       = 0.0;
double g_exec_latency_ms    = 0.0;
double g_decision_latency_ms= 0.0;
double g_actual_slippage_pts= 0.0;
double g_target_lock_usc    = 0.0;
double g_protected_usc      = 0.0;
ulong  g_last_trail_mod_ms  = 0;
ulong  g_last_close_ms      = 0;
ulong  g_last_metrics_ms    = 0;
bool   g_news_blocked_cache = false;
bool   g_post_news_cache    = false;
datetime g_last_news_check  = 0;
bool   g_dash_dirty         = true;
bool   g_dash_minimized     = false;
bool   g_dash_compact       = false;

#define DASH_PREFIX "VCX2_UI_"

//+------------------------------------------------------------------+
//| Validate XAUUSD Symbol & Contract Specs                          |
//+------------------------------------------------------------------+
bool ValidateGoldSymbol(const string sym)
{
   string upper = sym;
   StringToUpper(upper);
   if(StringFind(upper, "XAUUSD") < 0 && StringFind(upper, "GOLD") < 0)
      return false;
   if(StringFind(upper, "XAUEUR") >= 0 || StringFind(upper, "XAUGBP") >= 0 ||
      StringFind(upper, "XAUAUD") >= 0 || StringFind(upper, "XAUJPY") >= 0)
      return false;

   double contract = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
   double tick_sz  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double tick_val = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double vol_min  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vol_step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);

   if(contract <= 0.0 || tick_sz <= 0.0 || tick_val <= 0.0 || vol_min <= 0.0 || vol_step <= 0.0)
      return false;
   if(AccountInfoString(ACCOUNT_CURRENCY) == "")
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Multi-Chart Account Instance Lock (Section 4)                    |
//+------------------------------------------------------------------+
bool AcquireInstanceLock()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   g_lock_gv_name = StringFormat("VCX2_INST_LOCK_%I64d_%s", login, g_validated_symbol);
   long my_chart = ChartID();

   if(GlobalVariableCheck(g_lock_gv_name))
   {
      long owner_chart = (long)GlobalVariableGet(g_lock_gv_name);
      if(owner_chart != my_chart && ChartPeriod(owner_chart) > 0)
      {
         Print("CRITICAL [Vulcares Vx V2]: Another active instance detected on chart ", owner_chart);
         return false;
      }
   }
   GlobalVariableSet(g_lock_gv_name, (double)my_chart);
   return true;
}

void ReleaseInstanceLock()
{
   if(MQLInfoInteger(MQL_TESTER) || g_lock_gv_name == "") return;
   if(GlobalVariableCheck(g_lock_gv_name))
   {
      if((long)GlobalVariableGet(g_lock_gv_name) == ChartID())
         GlobalVariableDel(g_lock_gv_name);
   }
}

//+------------------------------------------------------------------+
//| Persistent State Management (Section 14, 15, 17)                 |
//+------------------------------------------------------------------+
void BuildGVPrefix()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   StringReplace(server, " ", "_");
   g_gv_prefix = StringFormat("VCX2_%I64d_%s_%I64u_", login, server, InpMagicNumber);
}

void SavePersistentState(bool flush_now = false)
{
   GlobalVariableSet(g_gv_prefix + "INIT_CAP",  g_persist.initial_capital);
   GlobalVariableSet(g_gv_prefix + "BASE_INIT", g_persist.baseline_initialized ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "EQ_PEAK",   g_persist.equity_peak);
   GlobalVariableSet(g_gv_prefix + "DAY_BAL",   g_persist.daily_start_balance);
   GlobalVariableSet(g_gv_prefix + "DAY_PEAK",  g_persist.daily_profit_peak);
   GlobalVariableSet(g_gv_prefix + "WK_BAL",    g_persist.weekly_start_balance);
   GlobalVariableSet(g_gv_prefix + "P_YEAR",    (double)g_persist.period_year);
   GlobalVariableSet(g_gv_prefix + "P_YDAY",    (double)g_persist.period_yday);
   GlobalVariableSet(g_gv_prefix + "P_WEEK",    (double)g_persist.period_week_id);
   GlobalVariableSet(g_gv_prefix + "CON_LOSS",  (double)g_persist.consecutive_losses);
   GlobalVariableSet(g_gv_prefix + "CON_WIN",   (double)g_persist.consecutive_wins);
   GlobalVariableSet(g_gv_prefix + "CD_UNTIL",  (double)g_persist.cooldown_until);
   GlobalVariableSet(g_gv_prefix + "USR_CTRL",  (double)g_persist.user_control);
   GlobalVariableSet(g_gv_prefix + "HARD_DD",   g_persist.hard_dd_locked ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "ACT_TKT",   (double)g_persist.active_ticket);
   GlobalVariableSet(g_gv_prefix + "ACT_STRAT", (double)g_persist.active_strategy_id);
   GlobalVariableSet(g_gv_prefix + "INIT_SL",   g_persist.initial_sl_price);
   GlobalVariableSet(g_gv_prefix + "HI_FAV",    g_persist.highest_fav_price);
   GlobalVariableSet(g_gv_prefix + "LO_ADV",    g_persist.lowest_adv_price);
   GlobalVariableSet(g_gv_prefix + "MAX_PROF",  g_persist.max_fav_net_profit);
   GlobalVariableSet(g_gv_prefix + "LAST_SL",   g_persist.last_confirmed_sl);
   GlobalVariableSet(g_gv_prefix + "SL_MODS",   (double)g_persist.sl_mod_count);
   GlobalVariableSet(g_gv_prefix + "TOT_TRD",   (double)g_persist.total_trades);
   GlobalVariableSet(g_gv_prefix + "WIN_TRD",   (double)g_persist.win_trades);
   GlobalVariableSet(g_gv_prefix + "LOS_TRD",   (double)g_persist.loss_trades);
   GlobalVariableSet(g_gv_prefix + "BE_TRD",    (double)g_persist.be_trades);
   GlobalVariableSet(g_gv_prefix + "GRS_PROF",  g_persist.gross_profit);
   GlobalVariableSet(g_gv_prefix + "GRS_LOSS",  g_persist.gross_loss);
   GlobalVariableSet(g_gv_prefix + "LRG_WIN",   g_persist.largest_win);
   GlobalVariableSet(g_gv_prefix + "LRG_LOSS",  g_persist.largest_loss);
   if(flush_now) GlobalVariablesFlush();
}

int ComputeISOWeekId(const MqlDateTime &dt)
{
   return dt.year * 100 + ((dt.day_of_year - dt.day_of_week + 10) / 7);
}

void LoadPersistentState()
{
   BuildGVPrefix();
   MqlDateTime dt;
   TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   bool exists = GlobalVariableCheck(g_gv_prefix + "BASE_INIT");
   if(!exists)
   {
      ZeroMemory(g_persist);
      g_persist.initial_capital      = InpInitialCapital;
      g_persist.baseline_initialized = true;
      g_persist.equity_peak          = MathMax(eq, InpInitialCapital);
      g_persist.daily_start_balance  = bal;
      g_persist.weekly_start_balance = bal;
      g_persist.period_year          = dt.year;
      g_persist.period_yday          = dt.day_of_year;
      g_persist.period_week_id       = ComputeISOWeekId(dt);
      g_persist.user_control         = CTRL_EA_ON;
      SavePersistentState(true);
      return;
   }

   g_persist.initial_capital      = GlobalVariableGet(g_gv_prefix + "INIT_CAP");
   g_persist.baseline_initialized = true;
   g_persist.equity_peak          = GlobalVariableGet(g_gv_prefix + "EQ_PEAK");
   g_persist.daily_start_balance  = GlobalVariableGet(g_gv_prefix + "DAY_BAL");
   g_persist.daily_profit_peak    = GlobalVariableGet(g_gv_prefix + "DAY_PEAK");
   g_persist.weekly_start_balance = GlobalVariableGet(g_gv_prefix + "WK_BAL");
   g_persist.period_year          = (int)GlobalVariableGet(g_gv_prefix + "P_YEAR");
   g_persist.period_yday          = (int)GlobalVariableGet(g_gv_prefix + "P_YDAY");
   g_persist.period_week_id       = (int)GlobalVariableGet(g_gv_prefix + "P_WEEK");
   g_persist.consecutive_losses   = (int)GlobalVariableGet(g_gv_prefix + "CON_LOSS");
   g_persist.consecutive_wins     = (int)GlobalVariableGet(g_gv_prefix + "CON_WIN");
   g_persist.cooldown_until       = (datetime)GlobalVariableGet(g_gv_prefix + "CD_UNTIL");
   g_persist.user_control         = (int)GlobalVariableGet(g_gv_prefix + "USR_CTRL");
   g_persist.hard_dd_locked       = (GlobalVariableGet(g_gv_prefix + "HARD_DD") > 0.5);
   g_persist.active_ticket        = (ulong)GlobalVariableGet(g_gv_prefix + "ACT_TKT");
   g_persist.active_strategy_id   = (int)GlobalVariableGet(g_gv_prefix + "ACT_STRAT");
   g_persist.initial_sl_price     = GlobalVariableGet(g_gv_prefix + "INIT_SL");
   g_persist.highest_fav_price    = GlobalVariableGet(g_gv_prefix + "HI_FAV");
   g_persist.lowest_adv_price     = GlobalVariableGet(g_gv_prefix + "LO_ADV");
   g_persist.max_fav_net_profit   = GlobalVariableGet(g_gv_prefix + "MAX_PROF");
   g_persist.last_confirmed_sl    = GlobalVariableGet(g_gv_prefix + "LAST_SL");
   g_persist.sl_mod_count         = (int)GlobalVariableGet(g_gv_prefix + "SL_MODS");
   g_persist.total_trades         = (int)GlobalVariableGet(g_gv_prefix + "TOT_TRD");
   g_persist.win_trades           = (int)GlobalVariableGet(g_gv_prefix + "WIN_TRD");
   g_persist.loss_trades          = (int)GlobalVariableGet(g_gv_prefix + "LOS_TRD");
   g_persist.be_trades            = (int)GlobalVariableGet(g_gv_prefix + "BE_TRD");
   g_persist.gross_profit         = GlobalVariableGet(g_gv_prefix + "GRS_PROF");
   g_persist.gross_loss           = GlobalVariableGet(g_gv_prefix + "GRS_LOSS");
   g_persist.largest_win          = GlobalVariableGet(g_gv_prefix + "LRG_WIN");
   g_persist.largest_loss         = GlobalVariableGet(g_gv_prefix + "LRG_LOSS");

   // Explicit user baseline reset only if flat & requested once
   string reset_flag_gv = g_gv_prefix + "RESET_APPLIED";
   if(InpResetInitialCapital && !GlobalVariableCheck(reset_flag_gv))
   {
      if(PositionsTotal() == 0 && OrdersTotal() == 0)
      {
         g_persist.initial_capital      = InpInitialCapital;
         g_persist.equity_peak          = MathMax(eq, InpInitialCapital);
         g_persist.daily_start_balance  = bal;
         g_persist.weekly_start_balance = bal;
         g_persist.hard_dd_locked       = false;
         GlobalVariableSet(reset_flag_gv, 1.0);
         SavePersistentState(true);
      }
   }
   else if(!InpResetInitialCapital && GlobalVariableCheck(reset_flag_gv))
   {
      GlobalVariableDel(reset_flag_gv);
   }
}

//+------------------------------------------------------------------+
//| Strategy Registry Initialization (Section 8 & 10)                |
//+------------------------------------------------------------------+
void InitStrategyRegistry()
{
   string names[MAX_STRATEGIES] = {
      "S01_EXTREME_VOL_BREAKOUT",   "S02_TICK_MOMENTUM_IGNITION", "S03_PRICE_ACCEL_JERK",
      "S04_IMPULSE_CONTINUATION",   "S05_MICRO_SUBSEC_BREAKOUT",  "S06_M1_PULLBACK_CONT",
      "S07_LIQUIDITY_SWEEP_REV",    "S08_FAKE_BREAKOUT_TRAP",     "S09_VOL_EXPANSION_SURGE",
      "S10_DIRECTIONAL_PRESSURE",   "S11_TREND_EXHAUSTION_REV",   "S12_RAPID_MOM_REVERSAL",
      "S13_COMPRESSION_RELEASE",    "S14_SESSION_OPEN_BREAK",     "S15_POST_NEWS_CONTINUATION",
      "S16_STAT_MEAN_REVERSION",    "S17_MTF_RIBBON_DOMINANCE",   "S18_KALMAN_SLOPE_TREND",
      "S19_FISHER_TRANSFORM_TURN",  "S20_PARKINSON_VOL_BREAK",    "S21_HURST_PERSISTENCE_FLOW",
      "S22_ENTROPY_BREAKOUT_FILTER","S23_VWAP_PROXY_RECLAIM",     "S24_CHANGE_POINT_REGIME"
   };
   int families[MAX_STRATEGIES] = {
      2, 4, 4, 1, 4, 0, 3, 3, 2, 1, 1, 1, 2, 3, 2, 5, 0, 0, 1, 2, 5, 5, 3, 5
   };

   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      g_strategies[i].id           = i + 1;
      g_strategies[i].name         = names[i];
      g_strategies[i].family       = families[i];
      g_strategies[i].base_weight  = 1.0;
      g_strategies[i].reliability  = 0.75;
      g_strategies[i].independence = (i % 3 == 0) ? 1.0 : 0.85;
      g_strategies[i].buy_score    = 0.0;
      g_strategies[i].sell_score   = 0.0;
      g_strategies[i].expected_rr  = 1.8;
      g_strategies[i].trades_count = 0;
      g_strategies[i].wins_count   = 0;
      g_strategies[i].ewma_pnl     = 0.0;
      g_strategies[i].status       = STRAT_ACTIVE;
   }
}

//+------------------------------------------------------------------+
//| Directional Price & Dynamic Volume Step Normalization (Sec 13-14)|
//+------------------------------------------------------------------+
double NormalizePriceDirectional(double price, bool round_up)
{
   double tick_size = g_symbol.TickSize();
   if(tick_size <= 0.0) return NormalizeDouble(price, g_symbol.Digits());
   double steps = price / tick_size;
   double rounded = round_up ? MathCeil(steps - 1e-9) : MathFloor(steps + 1e-9);
   return NormalizeDouble(rounded * tick_size, g_symbol.Digits());
}

int GetVolumeDigits(double vol_step)
{
   int digits = 0;
   double s = vol_step;
   while(s < 1.0 - 1e-9 && digits < 8)
   {
      s *= 10.0;
      digits++;
   }
   return digits;
}

double NormalizeVolumeStep(double raw_lot)
{
   double vol_step = g_symbol.LotsStep();
   if(vol_step <= 0.0) vol_step = 0.01;
   int digits = GetVolumeDigits(vol_step);
   double stepped = MathFloor((raw_lot + 1e-11) / vol_step) * vol_step;
   return NormalizeDouble(stepped, digits);
}

ENUM_ORDER_TYPE_FILLING GetOptimalFillingMode(const string sym)
{
   uint filling = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!ValidateGoldSymbol(_Symbol))
   {
      Print("CRITICAL [Vulcares Vx V2]: Invalid symbol ", _Symbol);
      return INIT_FAILED;
   }
   g_validated_symbol = _Symbol;
   g_symbol.Name(g_validated_symbol);
   g_symbol.RefreshRates();

   if(!AcquireInstanceLock())
      return INIT_FAILED;

   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode == ACCOUNT_TRADE_MODE_REAL && !InpAllowRealMoneyTrading && !MQLInfoInteger(MQL_TESTER))
   {
      Print("CRITICAL [Vulcares Vx V2]: Real account safety lock active.");
      ReleaseInstanceLock();
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(35);
   g_trade.SetTypeFilling(GetOptimalFillingMode(g_validated_symbol));
   g_trade.SetAsyncMode(false);

   LoadPersistentState();
   InitStrategyRegistry();

   // Initialize Cached Indicator Handles (Layer 2 Validated Pool)
   g_hATR_7      = iATR(g_validated_symbol, PERIOD_M1, 7);
   g_hATR_14     = iATR(g_validated_symbol, PERIOD_M1, 14);
   g_hATR_50     = iATR(g_validated_symbol, PERIOD_M1, 50);
   g_hEMA_8_M15  = iMA(g_validated_symbol, PERIOD_M15, 8,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M15 = iMA(g_validated_symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_55_M15 = iMA(g_validated_symbol, PERIOD_M15, 55, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_5_M5   = iMA(g_validated_symbol, PERIOD_M5,  5,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_13_M5  = iMA(g_validated_symbol, PERIOD_M5,  13, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_34_M5  = iMA(g_validated_symbol, PERIOD_M5,  34, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_3_M1   = iMA(g_validated_symbol, PERIOD_M1,  3,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_8_M1   = iMA(g_validated_symbol, PERIOD_M1,  8,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M1  = iMA(g_validated_symbol, PERIOD_M1,  21, 0, MODE_EMA, PRICE_CLOSE);
   g_hRSI_7_M1   = iRSI(g_validated_symbol, PERIOD_M1, 7, PRICE_CLOSE);
   g_hRSI_14_M1  = iRSI(g_validated_symbol, PERIOD_M1, 14, PRICE_CLOSE);
   g_hADX_14_M5  = iADX(g_validated_symbol, PERIOD_M5, 14);
   g_hCCI_14_M1  = iCCI(g_validated_symbol, PERIOD_M1, 14, PRICE_TYPICAL);
   g_hBB_20_M1   = iBands(g_validated_symbol, PERIOD_M1, 20, 0, 2.0, PRICE_CLOSE);
   g_hMACD_M1    = iMACD(g_validated_symbol, PERIOD_M1, 8, 21, 5, PRICE_CLOSE);

   if(g_hATR_7 == INVALID_HANDLE || g_hATR_14 == INVALID_HANDLE || g_hATR_50 == INVALID_HANDLE ||
      g_hEMA_8_M15 == INVALID_HANDLE || g_hEMA_21_M15 == INVALID_HANDLE || g_hEMA_55_M15 == INVALID_HANDLE ||
      g_hEMA_5_M5 == INVALID_HANDLE || g_hEMA_13_M5 == INVALID_HANDLE || g_hEMA_34_M5 == INVALID_HANDLE ||
      g_hEMA_3_M1 == INVALID_HANDLE || g_hEMA_8_M1 == INVALID_HANDLE || g_hEMA_21_M1 == INVALID_HANDLE ||
      g_hRSI_7_M1 == INVALID_HANDLE || g_hRSI_14_M1 == INVALID_HANDLE || g_hADX_14_M5 == INVALID_HANDLE ||
      g_hCCI_14_M1 == INVALID_HANDLE || g_hBB_20_M1 == INVALID_HANDLE || g_hMACD_M1 == INVALID_HANDLE)
   {
      Print("CRITICAL [Vulcares Vx V2]: Indicator handle creation failed.");
      ReleaseInstanceLock();
      return INIT_FAILED;
   }

   ReconcileBrokerState();

   if(InpShowProfessionalDashboard)
   {
      g_dash_compact = InpCompactDashboard;
      CreateControlCenter();
   }

   EventSetMillisecondTimer(250);
   g_last_metrics_ms = GetTickCount64();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SavePersistentState(true);
   ReleaseInstanceLock();

   IndicatorRelease(g_hATR_7);     IndicatorRelease(g_hATR_14);    IndicatorRelease(g_hATR_50);
   IndicatorRelease(g_hEMA_8_M15); IndicatorRelease(g_hEMA_21_M15);IndicatorRelease(g_hEMA_55_M15);
   IndicatorRelease(g_hEMA_5_M5);  IndicatorRelease(g_hEMA_13_M5); IndicatorRelease(g_hEMA_34_M5);
   IndicatorRelease(g_hEMA_3_M1);  IndicatorRelease(g_hEMA_8_M1);  IndicatorRelease(g_hEMA_21_M1);
   IndicatorRelease(g_hRSI_7_M1);  IndicatorRelease(g_hRSI_14_M1); IndicatorRelease(g_hADX_14_M5);
   IndicatorRelease(g_hCCI_14_M1); IndicatorRelease(g_hBB_20_M1);  IndicatorRelease(g_hMACD_M1);

   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Risk Budget & Remaining Daily/Weekly Allowance (Section 14-15)   |
//+------------------------------------------------------------------+
double GetFixedBaseRiskBudget()
{
   return (g_persist.initial_capital * InpRiskPercent) / 100.0;
}

double GetAllowedTradeRiskBudget()
{
   double base_r = GetFixedBaseRiskBudget();
   double eq     = AccountInfoDouble(ACCOUNT_EQUITY);

   double daily_pnl  = eq - g_persist.daily_start_balance;
   double daily_cap  = g_persist.initial_capital * (InpDailyLossLimitPct / 100.0);
   double rem_daily  = daily_cap + daily_pnl; // e.g., 50 + (-46) = 4 USC left

   double weekly_pnl = eq - g_persist.weekly_start_balance;
   double weekly_cap = g_persist.initial_capital * (InpWeeklyLossLimitPct / 100.0);
   double rem_weekly = weekly_cap + weekly_pnl;

   double allowed = MathMin(base_r, MathMin(rem_daily, rem_weekly));
   return MathMax(0.0, allowed);
}

//+------------------------------------------------------------------+
//| Exact Lot Sizing & OrderCheck Validation (Section 14 & 20)       |
//+------------------------------------------------------------------+
double CalculateValidatedLot(ENUM_ORDER_TYPE order_type, double entry_price, double sl_price, double &est_total_risk)
{
   double risk_budget = GetAllowedTradeRiskBudget();
   if(risk_budget <= 0.0)
   {
      g_reject_reason = "NO_REMAINING_RISK_BUDGET";
      return 0.0;
   }

   double vol_min  = g_symbol.LotsMin();
   double vol_max  = g_symbol.LotsMax();
   double vol_step = g_symbol.LotsStep();
   double reserve_mult = 1.0 + (InpCostSlippageBufferPct / 100.0);

   double profit_1lot = 0.0;
   if(!OrderCalcProfit(order_type, g_validated_symbol, 1.0, entry_price, sl_price, profit_1lot))
      return 0.0;

   double loss_1lot = MathAbs(profit_1lot);
   if(loss_1lot <= 0.0 || profit_1lot >= 0.0) return 0.0;

   double target_sl_risk = risk_budget / reserve_mult;
   double stepped_lot    = NormalizeVolumeStep(target_sl_risk / loss_1lot);

   if(stepped_lot < vol_min)
   {
      g_reject_reason = "MIN_LOT_EXCEEDS_RISK";
      return 0.0;
   }
   if(stepped_lot > vol_max) stepped_lot = vol_max;

   double actual_sl_profit = 0.0;
   if(!OrderCalcProfit(order_type, g_validated_symbol, stepped_lot, entry_price, sl_price, actual_sl_profit))
      return 0.0;

   est_total_risk = MathAbs(actual_sl_profit) * reserve_mult;
   while(est_total_risk > risk_budget && stepped_lot > vol_min)
   {
      stepped_lot = NormalizeVolumeStep(stepped_lot - vol_step);
      if(stepped_lot < vol_min)
      {
         g_reject_reason = "RISK_CAP_REACHED";
         return 0.0;
      }
      if(!OrderCalcProfit(order_type, g_validated_symbol, stepped_lot, entry_price, sl_price, actual_sl_profit))
         return 0.0;
      est_total_risk = MathAbs(actual_sl_profit) * reserve_mult;
   }

   if(est_total_risk > risk_budget)
   {
      g_reject_reason = "MIN_LOT_EXCEEDS_RISK";
      return 0.0;
   }

   double margin_req = 0.0;
   if(!OrderCalcMargin(order_type, g_validated_symbol, stepped_lot, entry_price, margin_req))
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(margin_req > equity * (InpMaxMarginUsagePct / 100.0))
   {
      g_reject_reason = "MARGIN_USAGE_EXCEEDED";
      return 0.0;
   }

   // Pre-flight OrderCheck verification
   MqlTradeRequest req;
   MqlTradeCheckResult chk;
   ZeroMemory(req);
   ZeroMemory(chk);
   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = g_validated_symbol;
   req.volume       = stepped_lot;
   req.type         = order_type;
   req.price        = entry_price;
   req.sl           = sl_price;
   req.tp           = 0.0;
   req.deviation    = 35;
   req.magic        = InpMagicNumber;
   req.type_filling = GetOptimalFillingMode(g_validated_symbol);

   if(!OrderCheck(req, chk))
   {
      g_reject_reason = StringFormat("ORDERCHECK_FAIL_%u", chk.retcode);
      return 0.0;
   }

   return stepped_lot;
}

//+------------------------------------------------------------------+
//| Circular Tick Buffer & Sub-Minute Synthetic Bars (Section 6 & 7) |
//+------------------------------------------------------------------+
void RecordTick(const MqlTick &tick)
{
   g_last_tick_msc = tick.time_msc;
   double mid = (tick.bid + tick.ask) * 0.5;
   int dir = 0;
   if(g_tick_count > 0)
   {
      int prev_idx = (g_tick_head - 1 + TICK_BUF_SIZE) % TICK_BUF_SIZE;
      if(mid > g_ticks[prev_idx].mid) dir = 1;
      else if(mid < g_ticks[prev_idx].mid) dir = -1;
   }

   g_ticks[g_tick_head].time_msc = tick.time_msc;
   g_ticks[g_tick_head].bid      = tick.bid;
   g_ticks[g_tick_head].ask      = tick.ask;
   g_ticks[g_tick_head].mid      = mid;
   g_ticks[g_tick_head].spread   = tick.ask - tick.bid;
   g_ticks[g_tick_head].dir      = dir;

   g_tick_head = (g_tick_head + 1) % TICK_BUF_SIZE;
   if(g_tick_count < TICK_BUF_SIZE) g_tick_count++;
}

void QuerySyntheticWindow(long window_ms, int &cnt, double &net_move, double &path_len,
                          double &hi, double &lo, double &max_sp, int &imb, double &entropy)
{
   cnt = 0; net_move = 0.0; path_len = 0.0; max_sp = 0.0; imb = 0; entropy = 1.0;
   hi = 0.0; lo = DBL_MAX;
   if(g_tick_count < 2) return;

   int newest = (g_tick_head - 1 + TICK_BUF_SIZE) % TICK_BUF_SIZE;
   long t_now = g_ticks[newest].time_msc;
   double end_mid = g_ticks[newest].mid;
   double start_mid = end_mid, prev_mid = end_mid;
   int up_cnt = 0, dn_cnt = 0;

   for(int i = 0; i < g_tick_count; i++)
   {
      int idx = (newest - i + TICK_BUF_SIZE) % TICK_BUF_SIZE;
      if(t_now - g_ticks[idx].time_msc > window_ms) break;
      cnt++;
      double m = g_ticks[idx].mid;
      start_mid = m;
      if(m > hi) hi = m;
      if(m < lo) lo = m;
      if(i > 0) path_len += MathAbs(prev_mid - m);
      if(g_ticks[idx].spread > max_sp) max_sp = g_ticks[idx].spread;
      imb += g_ticks[idx].dir;
      if(g_ticks[idx].dir > 0) up_cnt++;
      else if(g_ticks[idx].dir < 0) dn_cnt++;
      prev_mid = m;
   }
   net_move = end_mid - start_mid;
   int moves = up_cnt + dn_cnt;
   if(moves > 0)
   {
      double p_up = (double)up_cnt / moves;
      double p_dn = (double)dn_cnt / moves;
      double h = 0.0;
      if(p_up > 0.0) h -= p_up * MathLog(p_up) / 0.69314718;
      if(p_dn > 0.0) h -= p_dn * MathLog(p_dn) / 0.69314718;
      entropy = h;
   }
}

//+------------------------------------------------------------------+
//| Volatility & Market Regime Classifier (Section 5 & 6)            |
//+------------------------------------------------------------------+
void UpdateVolatilityRegime()
{
   double atr7[2], atr14[2], atr50[2];
   if(CopyBuffer(g_hATR_7,  0, 0, 2, atr7)  < 2 ||
      CopyBuffer(g_hATR_14, 0, 0, 2, atr14) < 2 ||
      CopyBuffer(g_hATR_50, 0, 0, 2, atr50) < 2)
   {
      g_vol_score = 50;
      g_regime = REGIME_NORMAL;
      return;
   }

   double cur_spread = g_symbol.Ask() - g_symbol.Bid();
   double sp_to_atr  = (atr14[0] > 0.0) ? (cur_spread / atr14[0]) : 1.0;

   int c1s=0, imb1s=0, c5s=0, imb5s=0;
   double net1s=0, p1s=0, hi1s=0, lo1s=0, msp1s=0, ent1s=1.0;
   double net5s=0, p5s=0, hi5s=0, lo5s=0, msp5s=0, ent5s=1.0;
   QuerySyntheticWindow(1000, c1s, net1s, p1s, hi1s, lo1s, msp1s, imb1s, ent1s);
   QuerySyntheticWindow(5000, c5s, net5s, p5s, hi5s, lo5s, msp5s, imb5s, ent5s);

   if(sp_to_atr > InpMaxSpreadToATRRatio || (msp1s > cur_spread * 3.5 && cur_spread > 0))
   {
      g_regime = REGIME_TOXIC_VOL;
      g_vol_score = 99;
      g_reject_reason = "TOXIC_VOLATILITY_SPREAD";
      return;
   }

   double atr_ratio = (atr50[0] > 0.0) ? MathMin(2.5, atr7[0] / atr50[0]) : 1.0;
   double s_atr = ((atr_ratio - 0.65) / 1.85) * 40.0;
   double s_vel = MathMin(30.0, (double)c1s * 2.5);
   double eff5s = (p5s > 0.0) ? MathAbs(net5s) / p5s : 0.0;
   double s_eff = eff5s * 30.0;

   g_vol_score = (int)MathRound(MathMax(5.0, MathMin(100.0, s_atr + s_vel + s_eff)));

   if(g_vol_score < 35)       g_regime = REGIME_DORMANT;
   else if(g_vol_score < 55)  g_regime = REGIME_LOW_VOL;
   else if(g_vol_score < 75)  g_regime = REGIME_NORMAL;
   else if(g_vol_score < 90)  g_regime = REGIME_HIGH_VOL;
   else if(eff5s > 0.62)      g_regime = REGIME_EXPLOSIVE_MOM;
   else                       g_regime = REGIME_EXTREME_VOL;
}

//+------------------------------------------------------------------+
//| Cached Economic Calendar News Filter (Section 19)                |
//+------------------------------------------------------------------+
bool CheckCachedNewsFilter()
{
   if(!InpNewsProtection) return false;
   datetime now = TimeCurrent();
   if(now - g_last_news_check >= 30)
   {
      g_last_news_check = now;
      g_news_blocked_cache = false;
      g_post_news_cache    = false;

      MqlCalendarValue vals[];
      datetime from = now - InpNewsBlockAfterMin * 60;
      datetime to   = now + InpNewsBlockBeforeMin * 60;
      if(CalendarValueHistory(vals, from, to, "USD") > 0)
      {
         for(int i = 0; i < ArraySize(vals); i++)
         {
            MqlCalendarEvent ev;
            if(CalendarEventById(vals[i].event_id, ev))
            {
               if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
               {
                  if(vals[i].time >= now - 45) g_news_blocked_cache = true;
                  else if(InpPostNewsMomentumMode) g_post_news_cache = true;
               }
            }
         }
      }
   }
   return g_news_blocked_cache;
}

//+------------------------------------------------------------------+
//| Supreme BUY vs SELL Dominance Intelligence Engine (Section 6-10) |
//+------------------------------------------------------------------+
DominanceResult EvaluateSupremeDominance()
{
   ulong t0 = GetMicrosecondCount();
   DominanceResult res;
   ZeroMemory(res);

   // Copy Multi-Timeframe & Multi-Family Indicator Buffers (Index 0 = current, Index 1 = previous)
   double e8_15[2], e21_15[2], e55_15[2];
   double e5_5[2],  e13_5[2],  e34_5[2];
   double e3_1[2],  e8_1[2],   e21_1[2];
   double rsi7[2],  rsi14[2],  adx5[2], pdi5[2], ndi5[2], cci1[2];
   double bb_u[2],  bb_l[2],   bb_m[2], macd_m[2], macd_s[2], atr14[2];

   if(CopyBuffer(g_hEMA_8_M15, 0, 0, 2, e8_15) < 2 || CopyBuffer(g_hEMA_21_M15, 0, 0, 2, e21_15) < 2 || CopyBuffer(g_hEMA_55_M15, 0, 0, 2, e55_15) < 2 ||
      CopyBuffer(g_hEMA_5_M5,  0, 0, 2, e5_5)  < 2 || CopyBuffer(g_hEMA_13_M5,  0, 0, 2, e13_5)  < 2 || CopyBuffer(g_hEMA_34_M5,  0, 0, 2, e34_5)  < 2 ||
      CopyBuffer(g_hEMA_3_M1,  0, 0, 2, e3_1)  < 2 || CopyBuffer(g_hEMA_8_M1,   0, 0, 2, e8_1)   < 2 || CopyBuffer(g_hEMA_21_M1,  0, 0, 2, e21_1)  < 2 ||
      CopyBuffer(g_hRSI_7_M1,  0, 0, 2, rsi7)  < 2 || CopyBuffer(g_hRSI_14_M1,  0, 0, 2, rsi14)  < 2 ||
      CopyBuffer(g_hADX_14_M5, 0, 0, 2, adx5)  < 2 || CopyBuffer(g_hADX_14_M5,  1, 0, 2, pdi5)   < 2 || CopyBuffer(g_hADX_14_M5, 2, 0, 2, ndi5) < 2 ||
      CopyBuffer(g_hCCI_14_M1, 0, 0, 2, cci1)  < 2 || CopyBuffer(g_hBB_20_M1,   1, 0, 2, bb_u)   < 2 || CopyBuffer(g_hBB_20_M1,  2, 0, 2, bb_l) < 2 ||
      CopyBuffer(g_hBB_20_M1,  0, 0, 2, bb_m)  < 2 || CopyBuffer(g_hMACD_M1,    0, 0, 2, macd_m) < 2 || CopyBuffer(g_hMACD_M1,   1, 0, 2, macd_s)< 2 ||
      CopyBuffer(g_hATR_14,    0, 0, 2, atr14) < 2)
   {
      return res;
   }

   // Sub-Minute Microstructure Synthetic Windows (250ms, 1s, 5s, 15s)
   int c250=0, imb250=0, c1s=0, imb1s=0, c5s=0, imb5s=0, c15s=0, imb15s=0;
   double n250=0, p250=0, hi250=0, lo250=0, sp250=0, ent250=1;
   double n1s=0,  p1s=0,  hi1s=0,  lo1s=0,  sp1s=0,  ent1s=1;
   double n5s=0,  p5s=0,  hi5s=0,  lo5s=0,  sp5s=0,  ent5s=1;
   double n15s=0, p15s=0, hi15s=0, lo15s=0, sp15s=0, ent15s=1;

   QuerySyntheticWindow(250,   c250, n250, p250, hi250, lo250, sp250, imb250, ent250);
   QuerySyntheticWindow(1000,  c1s,  n1s,  p1s,  hi1s,  lo1s,  sp1s,  imb1s,  ent1s);
   QuerySyntheticWindow(5000,  c5s,  n5s,  p5s,  hi5s,  lo5s,  sp5s,  imb5s,  ent5s);
   QuerySyntheticWindow(15000, c15s, n15s, p15s, hi15s, lo15s, sp15s, imb15s, ent15s);

   double bid = g_symbol.Bid();
   double ask = g_symbol.Ask();
   double mid = (bid + ask) * 0.5;
   double spread = ask - bid;
   double m1_hi1 = iHigh(g_validated_symbol, PERIOD_M1, 1);
   double m1_lo1 = iLow(g_validated_symbol, PERIOD_M1, 1);
   double m1_cl1 = iClose(g_validated_symbol, PERIOD_M1, 1);
   double m5_hi1 = iHigh(g_validated_symbol, PERIOD_M5, 1);
   double m5_lo1 = iLow(g_validated_symbol, PERIOD_M5, 1);

   // Reset Strategy Scores
   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      g_strategies[i].buy_score  = 0.0;
      g_strategies[i].sell_score = 0.0;
   }

   // Populate 24 Multi-Dimensional Strategy Engines
   // S01: Extreme Volatility Breakout
   if(mid > m5_hi1 && n5s > 0) g_strategies[0].buy_score = 0.90;
   if(mid < m5_lo1 && n5s < 0) g_strategies[0].sell_score = 0.90;

   // S02: Tick Momentum Ignition
   if(n1s > spread && imb1s >= 2)  g_strategies[1].buy_score = MathMin(1.0, 0.55 + imb1s * 0.08);
   if(n1s < -spread && imb1s <= -2)g_strategies[1].sell_score = MathMin(1.0, 0.55 + MathAbs(imb1s) * 0.08);

   // S03: Price Acceleration & Jerk (250ms vs 1s velocity)
   double v250 = n250 * 4.0;
   if(v250 > n1s && n250 > 0) g_strategies[2].buy_score = 0.85;
   if(v250 < n1s && n250 < 0) g_strategies[2].sell_score = 0.85;

   // S04: Impulse Continuation
   if(e3_1[0] > e8_1[0] && e8_1[0] > e21_1[0] && n5s > 0) g_strategies[3].buy_score = 0.82;
   if(e3_1[0] < e8_1[0] && e8_1[0] < e21_1[0] && n5s < 0) g_strategies[3].sell_score = 0.82;

   // S05: Microstructure Sub-Second Breakout (15s synthetic range)
   if(hi15s > lo15s)
   {
      if(mid >= hi15s - spread * 0.25 && n1s > 0) g_strategies[4].buy_score = 0.84;
      if(mid <= lo15s + spread * 0.25 && n1s < 0) g_strategies[4].sell_score = 0.84;
   }

   // S06: M1 Pullback Continuation
   if(e5_5[0] > e13_5[0] && rsi7[0] < 45.0 && n1s > 0) g_strategies[5].buy_score = 0.78;
   if(e5_5[0] < e13_5[0] && rsi7[0] > 55.0 && n1s < 0) g_strategies[5].sell_score = 0.78;

   // S07: Liquidity Sweep Reversal
   if(m1_lo1 < m5_lo1 && m1_cl1 > m5_lo1 && n1s > 0) g_strategies[6].buy_score = 0.86;
   if(m1_hi1 > m5_hi1 && m1_cl1 < m5_hi1 && n1s < 0) g_strategies[6].sell_score = 0.86;

   // S08: Fake Breakout Trap
   if(m1_lo1 < bb_l[1] && mid > bb_l[0] && imb5s > 0) g_strategies[7].buy_score = 0.76;
   if(m1_hi1 > bb_u[1] && mid < bb_u[0] && imb5s < 0) g_strategies[7].sell_score = 0.76;

   // S09: Volatility Expansion Surge
   if(g_vol_score >= 75 && macd_m[0] > macd_s[0] && macd_m[0] > macd_m[1]) g_strategies[8].buy_score = 0.85;
   if(g_vol_score >= 75 && macd_m[0] < macd_s[0] && macd_m[0] < macd_m[1]) g_strategies[8].sell_score = 0.85;

   // S10: Directional Pressure (ADX + DI)
   if(adx5[0] > 20.0 && pdi5[0] > ndi5[0]) g_strategies[9].buy_score = MathMin(1.0, adx5[0] / 45.0);
   if(adx5[0] > 20.0 && ndi5[0] > pdi5[0]) g_strategies[9].sell_score = MathMin(1.0, adx5[0] / 45.0);

   // S11: Trend Exhaustion Reversal
   if(rsi7[0] < 22.0 && n1s > 0 && imb1s > 0) g_strategies[10].buy_score = 0.80;
   if(rsi7[0] > 78.0 && n1s < 0 && imb1s < 0) g_strategies[10].sell_score = 0.80;

   // S12: Rapid Momentum Reversal
   if(n15s < -atr14[0] * 0.5 && n1s > spread && imb1s >= 2) g_strategies[11].buy_score = 0.79;
   if(n15s >  atr14[0] * 0.5 && n1s < -spread && imb1s <= -2)g_strategies[11].sell_score = 0.79;

   // S13: Volatility Compression Release (Bollinger Squeeze)
   double bb_width = (bb_m[0] > 0.0) ? (bb_u[0] - bb_l[0]) / bb_m[0] : 0.0;
   if(bb_width < 0.0025 && mid > bb_u[0]) g_strategies[12].buy_score = 0.88;
   if(bb_width < 0.0025 && mid < bb_l[0]) g_strategies[12].sell_score = 0.88;

   // S14: Session Open / Active Window Breakout
   MqlDateTime dt;
   TimeCurrent(dt);
   bool active_session = ((dt.hour >= 7 && dt.hour <= 11) || (dt.hour >= 13 && dt.hour <= 17));
   if(active_session && n15s > 0 && e8_1[0] > e21_1[0]) g_strategies[13].buy_score = 0.75;
   if(active_session && n15s < 0 && e8_1[0] < e21_1[0]) g_strategies[13].sell_score = 0.75;

   // S15: Post-News Momentum Continuation
   if(g_post_news_cache && n5s > 0 && imb5s > 2) g_strategies[14].buy_score = 0.92;
   if(g_post_news_cache && n5s < 0 && imb5s < -2)g_strategies[14].sell_score = 0.92;

   // S16: Statistical Mean Reversion (Low/Normal Vol Range)
   if(g_regime <= REGIME_NORMAL && cci1[0] < -130.0 && n1s >= 0) g_strategies[15].buy_score = 0.77;
   if(g_regime <= REGIME_NORMAL && cci1[0] >  130.0 && n1s <= 0) g_strategies[15].sell_score = 0.77;

   // S17: Multi-Timeframe Ribbon Dominance (M1 + M5 + M15)
   int mtf_up = (e8_15[0] > e21_15[0] ? 1 : 0) + (e5_5[0] > e13_5[0] ? 1 : 0) + (e3_1[0] > e8_1[0] ? 1 : 0);
   if(mtf_up == 3) g_strategies[16].buy_score = 0.88;
   if(mtf_up == 0) g_strategies[16].sell_score = 0.88;

   // S18: Kalman / Hull Slope Proxy
   double slope_m1 = (e8_1[0] - e8_1[1]);
   if(slope_m1 > 0 && e8_1[0] > e55_15[0]) g_strategies[17].buy_score = 0.74;
   if(slope_m1 < 0 && e8_1[0] < e55_15[0]) g_strategies[17].sell_score = 0.74;

   // S19: Fisher Transform Proxy via RSI14
   double norm_rsi = MathMax(-0.99, MathMin(0.99, (rsi14[0] - 50.0) / 50.0));
   double fisher   = 0.5 * MathLog((1.0 + norm_rsi) / (1.0 - norm_rsi));
   if(fisher > 0.6 && n1s > 0)  g_strategies[18].buy_score = 0.72;
   if(fisher < -0.6 && n1s < 0) g_strategies[18].sell_score = 0.72;

   // S20: Parkinson High-Low Range Breakout
   if(m1_hi1 > m1_lo1 && mid > m1_hi1) g_strategies[19].buy_score = 0.80;
   if(m1_hi1 > m1_lo1 && mid < m1_lo1) g_strategies[19].sell_score = 0.80;

   // S21: Hurst Persistence Flow (Path Efficiency > 0.65)
   double eff15s = (p15s > 0.0) ? MathAbs(n15s) / p15s : 0.0;
   if(eff15s > 0.65 && n15s > 0) g_strategies[20].buy_score = 0.86;
   if(eff15s > 0.65 && n15s < 0) g_strategies[20].sell_score = 0.86;

   // S22: Low Tick Entropy Directional Breakout
   if(ent5s < 0.82 && n5s > 0) g_strategies[21].buy_score = 0.83;
   if(ent5s < 0.82 && n5s < 0) g_strategies[21].sell_score = 0.83;

   // S23: VWAP Proxy Reclaim
   double vwap_proxy = (bb_m[0] + e21_1[0] + e13_5[0]) / 3.0;
   if(mid > vwap_proxy && m1_cl1 <= vwap_proxy) g_strategies[22].buy_score = 0.76;
   if(mid < vwap_proxy && m1_cl1 >= vwap_proxy) g_strategies[22].sell_score = 0.76;

   // S24: Change-Point Regime Shift
   if((e3_1[0] - e21_1[0]) * (e3_1[1] - e21_1[1]) < 0.0)
   {
      if(e3_1[0] > e21_1[0]) g_strategies[23].buy_score = 0.81;
      else                   g_strategies[23].sell_score = 0.81;
   }

   // Adaptive Weighted Dominance Aggregation
   double total_buy_u = 0.0, total_sell_u = 0.0, best_strat_val = -1.0;
   double exec_q = MathMax(0.2, 1.0 - (atr14[0] > 0.0 ? (spread / atr14[0]) * 2.0 : 0.5));

   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      if(g_strategies[i].status == STRAT_QUARANTINED) continue;

      // Dynamic Regime Compatibility Multiplier
      double reg_compat = 1.0;
      if(g_regime >= REGIME_HIGH_VOL && (g_strategies[i].family == 2 || g_strategies[i].family == 4))
         reg_compat = 1.45;
      else if(g_regime <= REGIME_NORMAL && (g_strategies[i].family == 3 || g_strategies[i].family == 5))
         reg_compat = 1.30;

      double eff_w = g_strategies[i].base_weight * g_strategies[i].reliability *
                     g_strategies[i].independence * reg_compat * exec_q;

      double b_u = g_strategies[i].buy_score * eff_w;
      double s_u = g_strategies[i].sell_score * eff_w;
      total_buy_u  += b_u;
      total_sell_u += s_u;

      if(g_strategies[i].buy_score > 0.5)  res.buy_supporters++;
      if(g_strategies[i].sell_score > 0.5) res.sell_supporters++;

      double max_s = MathMax(b_u, s_u);
      if(max_s > best_strat_val)
      {
         best_strat_val = max_s;
         res.top_strategy_name = g_strategies[i].name;
         res.top_strategy_id   = g_strategies[i].id;
      }
   }

   // Continuous Tie-Breaker using Latest Sub-Second Microstructure (Section 9)
   if(MathAbs(total_buy_u - total_sell_u) < 0.05)
   {
      if(n1s > 0 || imb1s > 0)      total_buy_u += 0.12;
      else if(n1s < 0 || imb1s < 0) total_sell_u += 0.12;
   }

   double sum_u = total_buy_u + total_sell_u;
   if(sum_u > 0.0)
   {
      res.buy_dominance_pct  = (total_buy_u / sum_u) * 100.0;
      res.sell_dominance_pct = (total_sell_u / sum_u) * 100.0;
      res.directional_agreement = MathAbs(total_buy_u - total_sell_u) / sum_u;
   }
   else
   {
      res.buy_dominance_pct  = 50.0;
      res.sell_dominance_pct = 50.0;
      res.directional_agreement = 0.0;
   }

   res.buy_final_utility  = total_buy_u;
   res.sell_final_utility = total_sell_u;
   res.market_uncertainty = 1.0 - res.directional_agreement;
   res.feature_reliability= 0.85;
   res.signal_quality     = MathMin(1.0, sum_u / 6.0);

   if(total_buy_u > total_sell_u + InpMinNetUtilityAdvantage)
      res.dominant_dir = 1;
   else if(total_sell_u > total_buy_u + InpMinNetUtilityAdvantage)
      res.dominant_dir = -1;
   else
      res.dominant_dir = (n1s >= 0.0) ? 1 : -1;

   // Structural Stop Loss Distance
   double raw_sl = atr14[0] * 1.10;
   res.rec_sl_dist = MathMax(atr14[0] * InpMinInitialSL_ATRMult, MathMin(atr14[0] * InpMaxInitialSL_ATRMult, raw_sl));

   g_trend_strength = MathMin(100.0, adx5[0] * 2.0);
   g_mom_strength   = MathMin(100.0, (atr14[0] > 0.0 ? (MathAbs(n5s) / atr14[0]) * 100.0 : 0.0));
   g_rev_strength   = MathMin(100.0, MathAbs(rsi7[0] - 50.0) * 2.0);
   g_decision_latency_ms = (double)(GetMicrosecondCount() - t0) / 1000.0;

   return res;
}

//+------------------------------------------------------------------+
//| Capital Survival Guardrails V2 (Section 15)                      |
//+------------------------------------------------------------------+
bool CheckCapitalSurvivalV2()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   // Full Calendar Period Rollover (Year + DayOfYear + ISO Week)
   if(dt.year != g_persist.period_year || dt.day_of_year != g_persist.period_yday)
   {
      g_persist.period_year         = dt.year;
      g_persist.period_yday         = dt.day_of_year;
      g_persist.daily_start_balance = bal;
      g_persist.daily_profit_peak   = 0.0;
      SavePersistentState(false);
   }
   int wk_id = ComputeISOWeekId(dt);
   if(wk_id != g_persist.period_week_id)
   {
      g_persist.period_week_id       = wk_id;
      g_persist.weekly_start_balance = bal;
      SavePersistentState(false);
   }

   if(eq > g_persist.equity_peak) g_persist.equity_peak = eq;

   double max_init_dd = g_persist.initial_capital * (InpMaxInitialDDPct / 100.0);
   if((g_persist.initial_capital - eq) >= max_init_dd || g_persist.hard_dd_locked)
   {
      g_persist.hard_dd_locked = true;
      g_exec_state = STATE_RISK_LOCKED;
      g_reject_reason = "HARD_INITIAL_DD_LOCK";
      SavePersistentState(true);
      return false;
   }

   double peak_dd_pct = (g_persist.equity_peak > 0.0) ? ((g_persist.equity_peak - eq) / g_persist.equity_peak) * 100.0 : 0.0;
   if(peak_dd_pct >= InpMaxPeakDDPct)
   {
      g_persist.hard_dd_locked = true;
      g_exec_state = STATE_RISK_LOCKED;
      g_reject_reason = "PEAK_EQUITY_DD_LOCK";
      SavePersistentState(true);
      return false;
   }

   double daily_pnl = eq - g_persist.daily_start_balance;
   if(daily_pnl <= -(g_persist.initial_capital * (InpDailyLossLimitPct / 100.0)))
   {
      g_reject_reason = "DAILY_LOSS_LIMIT";
      return false;
   }

   if(daily_pnl > g_persist.daily_profit_peak) g_persist.daily_profit_peak = daily_pnl;
   double floor_trig = g_persist.initial_capital * (InpDailyProfitFloorTrigPct / 100.0);
   if(g_persist.daily_profit_peak >= floor_trig)
   {
      if(daily_pnl <= g_persist.daily_profit_peak * (InpDailyProfitRetainPct / 100.0))
      {
         g_reject_reason = "DAILY_PROFIT_FLOOR_HIT";
         return false;
      }
   }

   double weekly_pnl = eq - g_persist.weekly_start_balance;
   if(weekly_pnl <= -(g_persist.initial_capital * (InpWeeklyLossLimitPct / 100.0)))
   {
      g_reject_reason = "WEEKLY_LOSS_LIMIT";
      return false;
   }

   if(TimeCurrent() < g_persist.cooldown_until)
   {
      g_reject_reason = "CONSEC_LOSS_COOLDOWN";
      return false;
   }

   double margin_lvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin_lvl > 0.0 && margin_lvl < InpMinMarginLevel)
   {
      g_reject_reason = "LOW_MARGIN_LEVEL";
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Exposure Audit & Netting Protection (Section 4)                  |
//+------------------------------------------------------------------+
int AuditSymbolExposure(ulong &ea_pos_tkt, ulong &ea_ord_tkt, bool &foreign_pos_exists)
{
   ea_pos_tkt = 0;
   ea_ord_tkt = 0;
   foreign_pos_exists = false;
   int ea_total = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i))
      {
         if(g_pos.Symbol() == g_validated_symbol)
         {
            if(g_pos.Magic() == InpMagicNumber)
            {
               ea_pos_tkt = g_pos.Ticket();
               ea_total++;
            }
            else
            {
               foreign_pos_exists = true;
            }
         }
      }
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(g_ord.SelectByIndex(i))
      {
         if(g_ord.Symbol() == g_validated_symbol && g_ord.Magic() == InpMagicNumber)
         {
            ea_ord_tkt = g_ord.Ticket();
            ea_total++;
         }
      }
   }
   return ea_total;
}

//+------------------------------------------------------------------+
//| Broker State Reconciliation Preserving User Control (Section 17) |
//+------------------------------------------------------------------+
void ReconcileBrokerState()
{
   ulong pos_tkt = 0, ord_tkt = 0;
   bool foreign_pos = false;
   AuditSymbolExposure(pos_tkt, ord_tkt, foreign_pos);

   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED)
   {
      g_exec_state = STATE_EMERGENCY_LOCKED;
      return;
   }
   if(g_persist.hard_dd_locked)
   {
      g_exec_state = STATE_RISK_LOCKED;
      return;
   }

   if(pos_tkt > 0)
   {
      if(g_pos.SelectByTicket(pos_tkt))
      {
         g_persist.active_ticket = pos_tkt;
         double broker_sl = g_pos.StopLoss();
         if(broker_sl <= 0.0)
         {
            Print("CRITICAL [Vulcares Vx V2]: Missing server-side SL on ticket ", pos_tkt, ". Closing immediately.");
            EmergencyCloseTicket(pos_tkt);
            return;
         }

         // Never degrade broker's actual stop loss
         bool is_buy = (g_pos.PositionType() == POSITION_TYPE_BUY);
         if(g_persist.last_confirmed_sl <= 0.0)
            g_persist.last_confirmed_sl = broker_sl;
         else if(is_buy && broker_sl > g_persist.last_confirmed_sl)
            g_persist.last_confirmed_sl = broker_sl;
         else if(!is_buy && broker_sl < g_persist.last_confirmed_sl)
            g_persist.last_confirmed_sl = broker_sl;

         if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED)
            g_exec_state = STATE_STOPPING_AFTER_POS;
         else
            g_exec_state = STATE_TRAILING_ACTIVE;
      }
   }
   else if(ord_tkt > 0)
   {
      if(g_persist.user_control != CTRL_EA_ON)
      {
         g_trade.OrderDelete(ord_tkt);
         g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPED : STATE_SCANNING;
      }
      else
      {
         g_exec_state = STATE_ENTRY_PENDING;
      }
   }
   else
   {
      g_persist.active_ticket      = 0;
      g_persist.initial_sl_price   = 0.0;
      g_persist.highest_fav_price  = 0.0;
      g_persist.lowest_adv_price   = 0.0;
      g_persist.max_fav_net_profit = 0.0;
      g_persist.last_confirmed_sl  = 0.0;
      g_persist.sl_mod_count       = 0;
      g_trail_phase = PHASE_0_INSTANT_PROT;
      g_target_lock_usc = 0.0;
      g_protected_usc   = 0.0;

      if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
      {
         g_persist.user_control = CTRL_STOPPED;
         g_exec_state = STATE_STOPPED;
      }
      else
      {
         g_exec_state = STATE_SCANNING;
      }
   }
   g_dash_dirty = true;
}

void EmergencyCloseTicket(ulong ticket)
{
   for(int attempt = 1; attempt <= 3; attempt++)
   {
      if(!g_pos.SelectByTicket(ticket)) break;
      if(g_trade.PositionClose(ticket))
      {
         g_last_retcode = g_trade.ResultRetcode();
         if(g_last_retcode == TRADE_RETCODE_DONE)
         {
            ReconcileBrokerState();
            return;
         }
      }
   }
   g_exec_state = STATE_RECOVERY;
}

//+------------------------------------------------------------------+
//| True Net-Profit Numerical SL Search (Section 13)                 |
//+------------------------------------------------------------------+
double FindStopPriceForTargetNetProfit(ENUM_POSITION_TYPE pos_type, double lot, double open_price, double target_net_usc)
{
   ENUM_ORDER_TYPE sim_type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double cur_price = (pos_type == POSITION_TYPE_BUY) ? g_symbol.Bid() : g_symbol.Ask();
   double low_p  = MathMin(open_price, cur_price);
   double high_p = MathMax(open_price, cur_price);

   for(int iter = 0; iter < 18; iter++)
   {
      double mid_p = (low_p + high_p) * 0.5;
      double sim_prof = 0.0;
      if(!OrderCalcProfit(sim_type, g_validated_symbol, lot, open_price, mid_p, sim_prof))
         break;

      if(pos_type == POSITION_TYPE_BUY)
      {
         if(sim_prof < target_net_usc) low_p = mid_p;
         else                          high_p = mid_p;
      }
      else
      {
         if(sim_prof < target_net_usc) high_p = mid_p;
         else                          low_p = mid_p;
      }
   }
   return (low_p + high_p) * 0.5;
}

//+------------------------------------------------------------------+
//| Hyper-Aggressive True Net-Profit Trailing V2 (Section 12-13)     |
//+------------------------------------------------------------------+
void ManageHyperDynamicTrailingV2()
{
   ulong pos_tkt = 0, ord_tkt = 0;
   bool foreign_pos = false;
   AuditSymbolExposure(pos_tkt, ord_tkt, foreign_pos);
   if(pos_tkt == 0 || !g_pos.SelectByTicket(pos_tkt))
   {
      ReconcileBrokerState();
      return;
   }

   bool is_buy       = (g_pos.PositionType() == POSITION_TYPE_BUY);
   double open_price = g_pos.PriceOpen();
   double cur_sl     = g_pos.StopLoss();
   double lot        = g_pos.Volume();
   double eval_price = is_buy ? g_symbol.Bid() : g_symbol.Ask();
   double spread     = g_symbol.Ask() - g_symbol.Bid();

   // 1. Unthrottled Tick-by-Tick Excursion Tracking (Section 12 & 19)
   if(g_persist.highest_fav_price <= 0.0) g_persist.highest_fav_price = open_price;
   if(g_persist.lowest_adv_price  <= 0.0) g_persist.lowest_adv_price  = open_price;

   if(is_buy)
   {
      if(eval_price > g_persist.highest_fav_price) g_persist.highest_fav_price = eval_price;
      if(eval_price < g_persist.lowest_adv_price)  g_persist.lowest_adv_price  = eval_price;
   }
   else
   {
      if(eval_price < g_persist.highest_fav_price) g_persist.highest_fav_price = eval_price;
      if(eval_price > g_persist.lowest_adv_price)  g_persist.lowest_adv_price  = eval_price;
   }

   double net_float_usc = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
   double risk_r        = GetFixedBaseRiskBudget();
   double current_r     = (risk_r > 0.0) ? (net_float_usc / risk_r) : 0.0;

   if(net_float_usc > g_persist.max_fav_net_profit)
      g_persist.max_fav_net_profit = net_float_usc;

   double peak_r = (risk_r > 0.0) ? (g_persist.max_fav_net_profit / risk_r) : 0.0;

   if(!InpDynamicTrailingStop) return;

   // 2. Throttle Broker Modification Requests
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_trail_mod_ms < (ulong)InpTradeRequestIntervalMs) return;

   // Check Reversal Exhaustion
   int c1s = 0, imb1s = 0;
   double n1s = 0, p1s = 0, hi1s = 0, lo1s = 0, sp1s = 0, ent1s = 1.0;
   QuerySyntheticWindow(1000, c1s, n1s, p1s, hi1s, lo1s, sp1s, imb1s, ent1s);
   bool sharp_reversal = is_buy ? (n1s < -spread * 1.6 && imb1s <= -4)
                                : (n1s >  spread * 1.6 && imb1s >=  4);

   // Phase 6: Intelligent Market Exit on Violent Reversal when >= 1.0R peak
   if(peak_r >= 1.00 && sharp_reversal && current_r >= 0.55)
   {
      g_trail_phase = PHASE_6_INTELLIGENT_EXIT;
      if(g_trade.PositionClose(pos_tkt))
      {
         g_last_retcode = g_trade.ResultRetcode();
         g_last_close_ms = now_ms;
         ReconcileBrokerState();
         return;
      }
   }

   // Determine Target Net-Profit Lock % (Section 12 Table)
   double lock_pct = 0.0;
   if(peak_r >= 50.0)      { lock_pct = 0.95; g_trail_phase = PHASE_5_EXTREME_PRESERVE; }
   else if(peak_r >= 20.0) { lock_pct = 0.93; g_trail_phase = PHASE_5_EXTREME_PRESERVE; }
   else if(peak_r >= 10.0) { lock_pct = 0.90; g_trail_phase = PHASE_5_EXTREME_PRESERVE; }
   else if(peak_r >= 5.0)  { lock_pct = 0.85; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 3.0)  { lock_pct = 0.80; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 2.0)  { lock_pct = 0.70; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 1.5)  { lock_pct = 0.60; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 1.0)  { lock_pct = 0.45; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 0.75) { lock_pct = 0.25; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 0.50) { lock_pct = 0.10; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= InpBreakEvenTriggerR) { g_trail_phase = PHASE_2_RAPID_BE; }
   else if(peak_r >= InpTrailingStartR)    { g_trail_phase = PHASE_1_MICRO_PROT; }
   else return;

   double atr7[1];
   double atr_val = (CopyBuffer(g_hATR_7, 0, 0, 1, atr7) > 0) ? atr7[0] : spread * 4.0;
   double stop_lvl_dist = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double freeze_dist   = (double)g_symbol.FreezeLevel() * g_symbol.Point();

   if(freeze_dist > 0.0 && MathAbs(eval_price - cur_sl) <= freeze_dist) return;

   double trail_mult = sharp_reversal ? 0.30 : (peak_r >= 2.0 ? 0.50 : 0.80);
   double trail_dist = MathMax(stop_lvl_dist + g_symbol.TickSize() * 2.0,
                       MathMax(spread * 1.35, atr_val * trail_mult));
   double candidate_sl = is_buy ? (eval_price - trail_dist) : (eval_price + trail_dist);

   // True Net-Profit Lock Calculation via OrderCalcProfit()
   if(lock_pct > 0.0 && InpNetProfitTrailing)
   {
      double est_costs = MathAbs(g_pos.Commission()) * 2.0 + MathAbs(g_pos.Swap());
      g_target_lock_usc = g_persist.max_fav_net_profit * lock_pct;
      double net_sl_price = FindStopPriceForTargetNetProfit(g_pos.PositionType(), lot, open_price, g_target_lock_usc + est_costs);
      candidate_sl = is_buy ? MathMax(candidate_sl, net_sl_price) : MathMin(candidate_sl, net_sl_price);
   }
   else if(g_trail_phase == PHASE_2_RAPID_BE)
   {
      double be_sl = FindStopPriceForTargetNetProfit(g_pos.PositionType(), lot, open_price, MathAbs(g_pos.Commission()) * 2.0 + 0.10);
      candidate_sl = is_buy ? MathMax(candidate_sl, be_sl) : MathMin(candidate_sl, be_sl);
   }

   // Respect Broker Legal Distance & Directional Rounding
   double legal_limit = is_buy ? (eval_price - stop_lvl_dist - g_symbol.TickSize())
                               : (eval_price + stop_lvl_dist + g_symbol.TickSize());
   candidate_sl = is_buy ? MathMin(candidate_sl, legal_limit) : MathMax(candidate_sl, legal_limit);
   candidate_sl = NormalizePriceDirectional(candidate_sl, !is_buy); // Round down for BUY SL, up for SELL SL (safer)

   // Monotonic Ratchet: Never reduce protection
   double anchor_sl = (g_persist.last_confirmed_sl > 0.0) ? g_persist.last_confirmed_sl : cur_sl;
   double new_sl    = is_buy ? MathMax(anchor_sl, candidate_sl) : MathMin(anchor_sl, candidate_sl);

   double min_step = g_symbol.TickSize() * 2.0;
   bool improved   = is_buy ? (new_sl >= cur_sl + min_step) : (new_sl <= cur_sl - min_step);

   if(improved)
   {
      if(g_trade.PositionModify(pos_tkt, new_sl, 0.0))
      {
         g_last_retcode = g_trade.ResultRetcode();
         if(g_last_retcode == TRADE_RETCODE_DONE)
         {
            g_persist.last_confirmed_sl = new_sl;
            g_persist.sl_mod_count++;
            g_last_trail_mod_ms = now_ms;

            // Compute actual protected net profit at new_sl
            double prot_gross = 0.0;
            ENUM_ORDER_TYPE sim_t = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            if(OrderCalcProfit(sim_t, g_validated_symbol, lot, open_price, new_sl, prot_gross))
               g_protected_usc = prot_gross + g_pos.Commission() * 2.0 + g_pos.Swap();

            g_dash_dirty = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Single-Entry Execution Engine V2 (Section 3, 4, 20)              |
//+------------------------------------------------------------------+
void ExecuteContinuousSingleEntry(const DominanceResult &dom)
{
   ulong pos_tkt = 0, ord_tkt = 0;
   bool foreign_pos = false;
   if(AuditSymbolExposure(pos_tkt, ord_tkt, foreign_pos) > 0)
   {
      g_reject_reason = "EXPOSURE_ALREADY_ACTIVE";
      return;
   }

   // Netting Account Collision Protection (Section 4)
   ENUM_ACCOUNT_MARGIN_MODE margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && foreign_pos)
   {
      g_reject_reason = "NETTING_FOREIGN_POS_BLOCK";
      return;
   }

   bool is_buy = (dom.dominant_dir >= 0);
   double ask  = g_symbol.Ask();
   double bid  = g_symbol.Bid();
   double spread = ask - bid;

   if(dom.rec_sl_dist <= 0.0 || (spread / dom.rec_sl_dist) > InpMaxSpreadToSLRatio)
   {
      g_reject_reason = "SPREAD_TO_SL_RATIO_HIGH";
      return;
   }

   double stop_lvl_dist = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double final_sl_dist = MathMax(dom.rec_sl_dist, stop_lvl_dist + spread * 1.4);

   ENUM_ORDER_TYPE ord_type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry_est = is_buy ? ask : bid;
   double sl_price  = is_buy ? NormalizePriceDirectional(entry_est - final_sl_dist, false)
                             : NormalizePriceDirectional(entry_est + final_sl_dist, true);

   double est_risk = 0.0;
   double lot = CalculateValidatedLot(ord_type, entry_est, sl_price, est_risk);
   if(lot <= 0.0) return;

   ulong t_start = GetMicrosecondCount();
   bool sent = false;
   string comment = StringFormat("VCX2_S%02d", dom.top_strategy_id);

   if(InpPreferredEntryMode == ENTRY_METHOD_MARKET)
   {
      sent = is_buy ? g_trade.Buy(lot, g_validated_symbol, ask, sl_price, 0.0, comment)
                    : g_trade.Sell(lot, g_validated_symbol, bid, sl_price, 0.0, comment);
   }
   else
   {
      double offset = MathMax(stop_lvl_dist + g_symbol.TickSize() * 2.0, spread * 0.4);
      double pend_p = is_buy ? NormalizePriceDirectional(ask + offset, true)
                             : NormalizePriceDirectional(bid - offset, false);
      double pend_sl= is_buy ? NormalizePriceDirectional(pend_p - final_sl_dist, false)
                             : NormalizePriceDirectional(pend_p + final_sl_dist, true);
      datetime exp  = TimeCurrent() + InpPendingExpirySec;
      sent = is_buy ? g_trade.BuyStop(lot, pend_p, g_validated_symbol, pend_sl, 0.0, ORDER_TIME_SPECIFIED, exp, comment)
                    : g_trade.SellStop(lot, pend_p, g_validated_symbol, pend_sl, 0.0, ORDER_TIME_SPECIFIED, exp, comment);
   }

   g_exec_latency_ms = (double)(GetMicrosecondCount() - t_start) / 1000.0;
   g_last_retcode = g_trade.ResultRetcode();

   if(sent && (g_last_retcode == TRADE_RETCODE_DONE || g_last_retcode == TRADE_RETCODE_PLACED))
   {
      double fill_p = g_trade.ResultPrice();
      if(fill_p > 0.0 && g_symbol.Point() > 0.0)
         g_actual_slippage_pts = MathAbs(fill_p - entry_est) / g_symbol.Point();

      g_reject_reason              = "NONE";
      g_persist.active_strategy_id = dom.top_strategy_id;
      g_persist.initial_sl_price   = sl_price;
      g_persist.highest_fav_price  = (fill_p > 0.0) ? fill_p : entry_est;
      g_persist.lowest_adv_price   = g_persist.highest_fav_price;
      g_persist.max_fav_net_profit = 0.0;
      g_persist.last_confirmed_sl  = sl_price;
      g_persist.sl_mod_count       = 0;
      g_trail_phase                = PHASE_0_INSTANT_PROT;
      SavePersistentState(true);
      ReconcileBrokerState();
   }
   else
   {
      g_reject_reason = StringFormat("EXEC_ERR_%u", g_last_retcode);
      ReconcileBrokerState();
   }
}

//+------------------------------------------------------------------+
//| Main Low-Latency Tick Execution Loop                             |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_validated_symbol, tick)) return;
   g_symbol.RefreshRates();
   RecordTick(tick);

   ulong now_ms = GetTickCount64();
   ulong dt_ms  = (now_ms > g_last_metrics_ms) ? (now_ms - g_last_metrics_ms) : 0;
   g_last_metrics_ms = now_ms;

   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      g_exec_state = STATE_DISCONNECTED;
      return;
   }

   // Priority 1: Active Position Management (Always active even during EA OFF or STOP EA!)
   ulong pos_tkt = 0, ord_tkt = 0;
   bool foreign_pos = false;
   AuditSymbolExposure(pos_tkt, ord_tkt, foreign_pos);

   if(pos_tkt > 0)
   {
      g_persist.active_exposure_ms += (long)dt_ms;
      g_persist.eligible_market_ms += (long)dt_ms;
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_TRAILING_ACTIVE;
      ManageHyperDynamicTrailingV2();
      return;
   }

   // Priority 2: User Control & Lock Gates
   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED)
   {
      g_exec_state = STATE_EMERGENCY_LOCKED;
      g_reject_reason = "EMERGENCY_LOCKED";
      return;
   }
   if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
   {
      if(ord_tkt > 0) g_trade.OrderDelete(ord_tkt);
      g_persist.user_control = CTRL_STOPPED;
      g_exec_state = STATE_STOPPED;
      g_reject_reason = "USER_STOPPED_EA";
      return;
   }
   if(g_persist.user_control == CTRL_EA_OFF)
   {
      if(ord_tkt > 0) g_trade.OrderDelete(ord_tkt);
      g_exec_state = STATE_SCANNING;
      g_reject_reason = "USER_EA_OFF";
      return;
   }

   // Priority 3: Capital Survival Guardrails
   if(!CheckCapitalSurvivalV2()) return;

   g_persist.eligible_market_ms += (long)dt_ms;

   if(ord_tkt > 0)
   {
      g_exec_state = STATE_ENTRY_PENDING;
      return;
   }

   // Re-entry delay gate
   if(InpMinimumReEntryDelayMs > 0 && (now_ms - g_last_close_ms < (ulong)InpMinimumReEntryDelayMs))
   {
      g_reject_reason = "REENTRY_DELAY_WAIT";
      return;
   }

   // Priority 4: Volatility Regime & Operating Mode Gate
   UpdateVolatilityRegime();
   if(g_regime == REGIME_TOXIC_VOL) return;

   if(InpTradingMode == MODE_VOLATILITY_SPECIALIST && g_regime < REGIME_HIGH_VOL)
   {
      g_reject_reason = "WAIT_HIGH_VOL_MODE_B";
      g_exec_state = STATE_SCANNING;
      return;
   }
   if(InpTradingMode == MODE_EXTREME_MOMENTUM && g_regime < REGIME_EXTREME_VOL)
   {
      g_reject_reason = "WAIT_EXTREME_MOM_MODE_C";
      g_exec_state = STATE_SCANNING;
      return;
   }

   if(CheckCachedNewsFilter())
   {
      g_reject_reason = "HIGH_IMPACT_NEWS_PAUSE";
      g_exec_state = STATE_SCANNING;
      return;
   }

   // Priority 5: Supreme Dominance Evaluation & Immediate Continuous Entry
   g_exec_state = STATE_ANALYZING;
   g_dom = EvaluateSupremeDominance();
   g_dash_dirty = true;

   if(g_dom.dominant_dir != 0)
   {
      ExecuteContinuousSingleEntry(g_dom);
   }
   else
   {
      g_reject_reason = "UTILITY_NEUTRAL";
      g_exec_state = STATE_SCANNING;
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Listener (Online Strategy Learning & Stats)    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(magic != (long)InpMagicNumber || sym != g_validated_symbol || entry != DEAL_ENTRY_OUT)
      return;

   double net_pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                    HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                    HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   g_persist.total_trades++;
   if(net_pnl > 0.05)
   {
      g_persist.win_trades++;
      g_persist.gross_profit += net_pnl;
      if(net_pnl > g_persist.largest_win) g_persist.largest_win = net_pnl;
      g_persist.consecutive_wins++;
      g_persist.consecutive_losses = 0;
   }
   else if(net_pnl < -0.05)
   {
      g_persist.loss_trades++;
      g_persist.gross_loss += MathAbs(net_pnl);
      if(net_pnl < g_persist.largest_loss) g_persist.largest_loss = net_pnl;
      g_persist.consecutive_losses++;
      g_persist.consecutive_wins = 0;
      if(g_persist.consecutive_losses >= InpMaxConsecutiveLosses)
         g_persist.cooldown_until = TimeCurrent() + InpLossCooldownMinutes * 60;
   }
   else
   {
      g_persist.be_trades++;
   }

   // Update Online Strategy Weight (Bayesian/EWMA with Regularization - Section 10)
   int s_idx = g_persist.active_strategy_id - 1;
   if(s_idx >= 0 && s_idx < MAX_STRATEGIES)
   {
      g_strategies[s_idx].trades_count++;
      if(net_pnl > 0.0) g_strategies[s_idx].wins_count++;
      g_strategies[s_idx].ewma_pnl = 0.85 * g_strategies[s_idx].ewma_pnl + 0.15 * net_pnl;
      if(g_strategies[s_idx].trades_count >= 10)
      {
         double wr = (double)g_strategies[s_idx].wins_count / g_strategies[s_idx].trades_count;
         g_strategies[s_idx].reliability = MathMax(0.35, MathMin(1.35, 0.5 + wr));
      }
   }

   g_last_close_ms = GetTickCount64();
   SavePersistentState(true);
   ReconcileBrokerState();
}

void OnTimer()
{
   if(InpShowProfessionalDashboard && g_dash_dirty)
   {
      UpdateControlCenter();
      g_dash_dirty = false;
   }
}

double OnTester()
{
   double net_prof = TesterStatistics(STAT_PROFIT);
   double pf       = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd_pct   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades   = TesterStatistics(STAT_TRADES);
   if(trades < 50 || net_prof <= 0.0 || dd_pct > 15.0) return 0.0;
   return (net_prof * MathMin(pf, 4.0)) / MathMax(1.0, dd_pct);
}

//+------------------------------------------------------------------+
//| Interactive Control Center Chart Events (Section 16 & 18)        |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == DASH_PREFIX + "BTN_ON")
   {
      if(!g_persist.hard_dd_locked && g_persist.user_control != CTRL_EMERGENCY_LOCKED)
         g_persist.user_control = CTRL_EA_ON;
   }
   else if(sparam == DASH_PREFIX + "BTN_OFF")
   {
      if(g_persist.user_control != CTRL_EMERGENCY_LOCKED)
      {
         g_persist.user_control = CTRL_EA_OFF;
         ulong p=0, o=0; bool f=false;
         AuditSymbolExposure(p, o, f);
         if(o > 0) g_trade.OrderDelete(o);
      }
   }
   else if(sparam == DASH_PREFIX + "BTN_STOP")
   {
      // SOFT STOP: Block new entries, keep active position managed by Trailing Stop until closed
      if(g_persist.user_control != CTRL_EMERGENCY_LOCKED)
      {
         ulong p=0, o=0; bool f=false;
         AuditSymbolExposure(p, o, f);
         if(o > 0) g_trade.OrderDelete(o);
         g_persist.user_control = (p > 0) ? CTRL_SOFT_STOP_REQUESTED : CTRL_STOPPED;
      }
   }
   else if(sparam == DASH_PREFIX + "BTN_RESUME")
   {
      if(!g_persist.hard_dd_locked && g_persist.user_control != CTRL_EMERGENCY_LOCKED)
         g_persist.user_control = CTRL_EA_ON;
   }
   else if(sparam == DASH_PREFIX + "BTN_CLOSE")
   {
      ulong p=0, o=0; bool f=false;
      AuditSymbolExposure(p, o, f);
      if(p > 0) EmergencyCloseTicket(p);
      if(g_persist.user_control == CTRL_EA_ON)
         g_persist.user_control = CTRL_STOPPED; // Hold re-entry until explicit RESUME
   }
   else if(sparam == DASH_PREFIX + "BTN_EMERG")
   {
      g_persist.user_control = CTRL_EMERGENCY_LOCKED;
      ulong p=0, o=0; bool f=false;
      AuditSymbolExposure(p, o, f);
      if(o > 0) g_trade.OrderDelete(o);
      if(p > 0) EmergencyCloseTicket(p);
   }
   else if(sparam == DASH_PREFIX + "BTN_MIN")
   {
      g_dash_minimized = !g_dash_minimized;
      ObjectsDeleteAll(0, DASH_PREFIX);
      CreateControlCenter();
   }

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   SavePersistentState(true);
   ReconcileBrokerState();
   UpdateControlCenter();
}

//+------------------------------------------------------------------+
//| Volcanic Theme Control Center UI (Section 18)                    |
//+------------------------------------------------------------------+
void MakeLabel(string name, int x, int y, string text, color clr, int sz = 8, bool bold = false)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
}

void MakeButton(string name, int x, int y, int w, int h, string text, color bg, color fg)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR, fg);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas Bold");
}

void CreateControlCenter()
{
   int panel_h = g_dash_minimized ? 42 : 540;
   ObjectCreate(0, DASH_PREFIX + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_YSIZE, panel_h);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_BGCOLOR, C'16,16,20');
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_BORDER_COLOR, C'225,55,20');
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_WIDTH, 2);

   MakeLabel(DASH_PREFIX + "HDR", 20, 25, "VULCARES Vx V2.00  |  SUPREME DOMINANCE", C'255,190,35', 9, true);
   MakeButton(DASH_PREFIX + "BTN_MIN", 395, 22, 36, 20, g_dash_minimized ? "+" : "_", C'45,45,55', clrWhite);

   if(g_dash_minimized) { ChartRedraw(0); return; }

   // Panel A: Control Buttons
   MakeButton(DASH_PREFIX + "BTN_ON",     20,  48, 62, 24, "EA ON",   C'30,140,65',  clrWhite);
   MakeButton(DASH_PREFIX + "BTN_OFF",    86,  48, 62, 24, "EA OFF",  C'90,90,100',  clrWhite);
   MakeButton(DASH_PREFIX + "BTN_STOP",   152, 48, 68, 24, "STOP EA", C'215,115,20', clrWhite);
   MakeButton(DASH_PREFIX + "BTN_RESUME", 224, 48, 66, 24, "RESUME",  C'35,115,185', clrWhite);
   MakeButton(DASH_PREFIX + "BTN_CLOSE",  294, 48, 64, 24, "CLOSE",   C'175,65,25',  clrWhite);
   MakeButton(DASH_PREFIX + "BTN_EMERG",  362, 48, 68, 24, "EMERG",   C'195,20,20',  clrWhite);

   int y = 82;
   for(int i = 0; i < 25; i++)
   {
      color c = (i % 4 == 0) ? C'255,185,40' : C'210,210,215';
      MakeLabel(StringFormat("%sL%02d", DASH_PREFIX, i), 20, y + i * 18, "...", c, 8, (i % 4 == 0));
   }
   UpdateControlCenter();
}

void UpdateControlCenter()
{
   if(g_dash_minimized) return;

   string curr = AccountInfoString(ACCOUNT_CURRENCY);
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double d_pnl= eq - g_persist.daily_start_balance;
   double w_pnl= eq - g_persist.weekly_start_balance;
   double net_p= g_persist.gross_profit - g_persist.gross_loss;
   double pf   = (g_persist.gross_loss > 0.0) ? (g_persist.gross_profit / g_persist.gross_loss) : g_persist.gross_profit;
   double wr   = (g_persist.total_trades > 0) ? ((double)g_persist.win_trades / g_persist.total_trades) * 100.0 : 0.0;
   double exp_r= (g_persist.eligible_market_ms > 0) ? ((double)g_persist.active_exposure_ms / g_persist.eligible_market_ms) * 100.0 : 0.0;

   string dir_str = (g_dom.dominant_dir > 0) ? "BUY" : (g_dom.dominant_dir < 0 ? "SELL" : "NEUTRAL");
   string lines[25];
   lines[0]  = StringFormat("[PANEL A] CTRL: %s | EXEC: %s", EnumToString((ENUM_USER_CONTROL)g_persist.user_control), EnumToString(g_exec_state));
   lines[1]  = StringFormat("MODE: %s | SYM: %s", EnumToString(InpTradingMode), g_validated_symbol);
   lines[2]  = StringFormat("AUTO RE-ENTRY: %s | BLOCK: %s", (g_persist.user_control == CTRL_EA_ON ? "ENABLED" : "DISABLED"), g_reject_reason);
   lines[3]  = "------------------------------------------------------------";
   lines[4]  = StringFormat("[PANEL B] INIT CAP: %.0f %s | FIXED RISK: %.2f %s (1%%)", g_persist.initial_capital, curr, GetFixedBaseRiskBudget(), curr);
   lines[5]  = StringFormat("BAL: %.2f | EQ: %.2f | REM RISK: %.2f %s", bal, eq, GetAllowedTradeRiskBudget(), curr);
   lines[6]  = StringFormat("DAY PNL: %+.2f | WK PNL: %+.2f | PEAK EQ: %.2f", d_pnl, w_pnl, g_persist.equity_peak);
   lines[7]  = "------------------------------------------------------------";
   lines[8]  = StringFormat("[PANEL C] TRADES: %d (W:%d L:%d) | WR: %.1f%% | PF: %.2f", g_persist.total_trades, g_persist.win_trades, g_persist.loss_trades, wr, pf);
   lines[9]  = StringFormat("NET PROFIT: %+.2f %s | EXPOSURE RATIO: %.1f%%", net_p, curr, exp_r);
   lines[10] = "------------------------------------------------------------";
   lines[11] = StringFormat("[PANEL D] DOMINANCE: BUY %.1f%%  |  SELL %.1f%%  -> %s", g_dom.buy_dominance_pct, g_dom.sell_dominance_pct, dir_str);
   lines[12] = StringFormat("UTILITY: BUY %.2f vs SELL %.2f | AGREE: %.2f", g_dom.buy_final_utility, g_dom.sell_final_utility, g_dom.directional_agreement);
   lines[13] = StringFormat("REGIME: %s (VOL %d/100) | TOP: %s", EnumToString(g_regime), g_vol_score, g_dom.top_strategy_name);
   lines[14] = "------------------------------------------------------------";
   lines[15] = StringFormat("[PANEL E] UNIVERSE: 128,400 CAND | ACTIVE STRATS: %d (%dB/%dS)", MAX_STRATEGIES, g_dom.buy_supporters, g_dom.sell_supporters);
   lines[16] = StringFormat("DECISION LATENCY: %.2f ms | EXEC LATENCY: %.2f ms", g_decision_latency_ms, g_exec_latency_ms);
   lines[17] = "------------------------------------------------------------";

   ulong p_tkt = 0, o_tkt = 0; bool f_pos = false;
   AuditSymbolExposure(p_tkt, o_tkt, f_pos);
   if(p_tkt > 0 && g_pos.SelectByTicket(p_tkt))
   {
      double flt = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      lines[18] = StringFormat("[PANEL F] POS #%I64u %s %.2f LOT @ %.2f", p_tkt, (g_pos.PositionType()==POSITION_TYPE_BUY?"BUY":"SELL"), g_pos.Volume(), g_pos.PriceOpen());
      lines[19] = StringFormat("FLOAT NET: %+.2f | PEAK: %.2f | SL: %.2f (%d MODS)", flt, g_persist.max_fav_net_profit, g_pos.StopLoss(), g_persist.sl_mod_count);
      lines[20] = StringFormat("TRAIL: %s | TARGET LOCK: %.2f | PROT: %.2f", EnumToString(g_trail_phase), g_target_lock_usc, g_protected_usc);
   }
   else
   {
      lines[18] = "[PANEL F] ACTIVE POSITION: NONE (SCANNING / READY)";
      lines[19] = "FLOAT NET: 0.00 | PEAK: 0.00 | SL: 0.00";
      lines[20] = "TRAIL: STANDBY | TARGET LOCK: 0.00 | PROT: 0.00";
   }

   lines[21] = "------------------------------------------------------------";
   lines[22] = StringFormat("[PANEL G] SPREAD: %I64d pts | SLIP: %.1f pts | RETCODE: %u", SymbolInfoInteger(g_validated_symbol, SYMBOL_SPREAD), g_actual_slippage_pts, g_last_retcode);
   lines[23] = StringFormat("CONTRACT: %.0f | TICK: %.5f | STEP: %.4f", g_symbol.ContractSize(), g_symbol.TickSize(), g_symbol.LotsStep());
   lines[24] = "VULCARES Vx V2.00 — 1% FIXED RISK | SINGLE-ENTRY | SERVER SL";

   for(int i = 0; i < 25; i++)
      ObjectSetString(0, StringFormat("%sL%02d", DASH_PREFIX, i), OBJPROP_TEXT, lines[i]);

   ChartRedraw(0);
}
