//+------------------------------------------------------------------+
//|                                               Vulcares_Vx_V3.mq5 |
//|                                  Copyright 2026, Vulcares Quant  |
//|   ANTI-MARTINGALE ADAPTIVE DOMINANCE & PRECISION SCALPING ENGINE |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vulcares Quant"
#property link      "https://www.mql5.com"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enumerations
enum ENUM_OPERATING_MODE
{
   MODE_ADAPTIVE_PRECISION   = 0, // MODE A: Quality-Gated Adaptive Dominance (Recommended)
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
   PHASE_1_BREATHING_PROT,
   PHASE_2_COST_BE,
   PHASE_3_NET_PROFIT_LOCK,
   PHASE_4_MOM_COMPRESSION,
   PHASE_5_EXTREME_PRESERVE,
   PHASE_6_INTELLIGENT_EXIT
};

//--- Input Parameters
input group "=== 1. SYSTEM & OPERATING MODE ==="
input string              InpEAName                   = "Vulcares Vx V3";
input ENUM_OPERATING_MODE InpTradingMode              = MODE_ADAPTIVE_PRECISION;
input ulong               InpMagicNumber              = 20260333;
input bool                InpAllowRealMoneyTrading    = false; // Set true explicitly for Live Real Account
input bool                InpResetBaselineOnInit      = false; // Reset capital & locks once on startup

input group "=== 2. BASE CAPITAL & ANTI-MARTINGALE ENGINE ==="
input double              InpInitialCapital           = 1000.00; // Baseline Capital (USD / USC)
input double              InpBaseRiskPercent          = 1.00;    // Base Risk % = 10.00 on 1000
input bool                InpEnableAntiMartingale     = true;    // Scale up risk on winning streaks!
input double              InpAntiMartingaleStepMult   = 0.50;    // +0.50x risk per consecutive win (1.0x -> 1.5x -> 2.0x -> 2.5x)
input double              InpAntiMartingaleMaxMult    = 2.50;    // Maximum Anti-Martingale multiplier cap (2.5% max risk)
input int                 InpAntiMartingaleMaxStreak  = 3;       // Reset back to 1.0x after N consecutive wins to bank gains
input double              InpLossDefendMult           = 0.75;    // Reduce risk to 0.75x after 2 consecutive losses
input double              InpCostSlippageBufferPct    = 15.0;    // Cost & slippage reserve %

input group "=== 3. CAPITAL SURVIVAL GUARDRAILS ==="
input double              InpDailyLossLimitPct        = 5.00;    // Max 5% daily loss (50 on 1000)
input double              InpWeeklyLossLimitPct       = 10.00;   // Max 10% weekly loss (100 on 1000)
input double              InpMaxInitialDDPct          = 15.00;   // Max 15% initial capital drawdown
input double              InpMaxPeakDDPct             = 15.00;   // Max 15% peak equity drawdown
input int                 InpMaxConsecutiveLosses     = 4;
input int                 InpLossCooldownMinutes      = 15;

input group "=== 4. PRECISION DOMINANCE & ANTI-CHOP FILTERS ==="
input double              InpMinDominanceAdvantage    = 0.45;    // Minimum net utility gap to prevent whipsaw entries
input double              InpMinDirectionalAgreement  = 0.28;    // Minimum consensus across strategy families
input double              InpMinEfficiencyRatio       = 0.45;    // Anti-chop filter (0.0 = pure noise, 1.0 = straight trend)
input int                 InpPostCloseCooldownSec     = 8;       // Cooldown after exit to avoid immediate noise re-entry
input bool                InpRequireMTFAlignment      = true;    // Align M1/M5 momentum with M15 structure

input group "=== 5. BREATHING DYNAMIC TRAILING & R:R ENGINE ==="
input bool                InpDynamicTrailingStop      = true;
input bool                InpNetProfitTrailing        = true;
input double              InpInitialSL_ATRMult        = 1.65;    // Wider structural SL to survive M1 gold wicks
input double              InpInitialTP_RMultiple      = 3.50;    // Server-side safety TP at 3.5R (0 = disabled)
input double              InpTrailingStartR           = 0.65;    // Let trade breathe until +0.65R before trailing
input double              InpBreakEvenTriggerR        = 0.90;    // Move to cost-adjusted BE at +0.90R
input int                 InpTradeRequestIntervalMs   = 200;

input group "=== 6. SPREAD & NEWS PROTECTION ==="
input double              InpMaxSpreadToATRRatio      = 0.25;
input double              InpMaxSpreadToSLRatio       = 0.25;
input double              InpMinMarginLevel           = 300.0;
input double              InpMaxMarginUsagePct        = 25.0;
input bool                InpNewsProtection           = true;
input int                 InpNewsBlockBeforeMin       = 5;
input int                 InpNewsBlockAfterMin        = 2;

input group "=== 7. PROFESSIONAL CONTROL CENTER ==="
input bool                InpShowProfessionalDashboard= true;

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
   int    id;
   string name;
   int    family;
   double base_weight;
   double reliability;
   double buy_score;
   double sell_score;
   int    trades_count;
   int    wins_count;
};

struct DominanceResult
{
   double buy_dominance_pct;
   double sell_dominance_pct;
   double buy_final_utility;
   double sell_final_utility;
   double directional_agreement;
   double efficiency_ratio;
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
   double   weekly_start_balance;
   int      period_year;
   int      period_yday;
   int      period_week_id;
   int      consecutive_losses;
   int      consecutive_wins;
   double   anti_mart_mult;
   datetime cooldown_until;
   int      user_control;
   bool     hard_dd_locked;
   ulong    active_ticket;
   int      active_strategy_id;
   double   highest_fav_price;
   double   max_fav_net_profit;
   double   last_confirmed_sl;
   int      sl_mod_count;
   int      total_trades;
   int      win_trades;
   int      loss_trades;
   double   gross_profit;
   double   gross_loss;
};

//--- Global Objects
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
int g_hEMA_5_M1  = INVALID_HANDLE, g_hEMA_13_M1  = INVALID_HANDLE, g_hEMA_34_M1  = INVALID_HANDLE;
int g_hRSI_14_M1 = INVALID_HANDLE, g_hADX_14_M5  = INVALID_HANDLE, g_hMACD_M1    = INVALID_HANDLE;
int g_hBB_20_M1  = INVALID_HANDLE;

// Circular Tick Buffer
#define TICK_BUF_SIZE 4096
TickSample g_ticks[TICK_BUF_SIZE];
int        g_tick_head  = 0;
int        g_tick_count = 0;

#define MAX_STRATEGIES 16
StrategyUnit g_strategies[MAX_STRATEGIES];

// Runtime Telemetry
string   g_validated_symbol   = "";
string   g_gv_prefix          = "";
string   g_lock_gv_name       = "";
string   g_reject_reason      = "NONE";
uint     g_last_retcode       = 0;
int      g_vol_score          = 50;
double   g_exec_latency_ms    = 0.0;
double   g_decision_latency_ms= 0.0;
double   g_target_lock_val    = 0.0;
double   g_protected_val      = 0.0;
ulong    g_last_trail_mod_ms  = 0;
datetime g_last_close_time    = 0;
bool     g_news_blocked_cache = false;
datetime g_last_news_check    = 0;
bool     g_dash_dirty         = true;
bool     g_dash_minimized     = false;

#define DASH_PREFIX "VCX3_UI_"

//+------------------------------------------------------------------+
//| Validate XAUUSD Symbol & Contract Specs                          |
//+------------------------------------------------------------------+
bool ValidateGoldSymbol(const string sym)
{
   string upper = sym;
   StringToUpper(upper);
   if(StringFind(upper, "XAUUSD") < 0 && StringFind(upper, "GOLD") < 0) return false;
   if(StringFind(upper, "XAUEUR") >= 0 || StringFind(upper, "XAUGBP") >= 0 ||
      StringFind(upper, "XAUAUD") >= 0 || StringFind(upper, "XAUJPY") >= 0) return false;

   return (SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE) > 0.0 &&
           SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE) > 0.0 &&
           SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE) > 0.0 &&
           SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN) > 0.0);
}

//+------------------------------------------------------------------+
//| Multi-Chart Account Instance Lock                                |
//+------------------------------------------------------------------+
bool AcquireInstanceLock()
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   g_lock_gv_name = StringFormat("VCX3_LOCK_%I64d_%s", login, g_validated_symbol);
   long my_chart = ChartID();

   if(GlobalVariableCheck(g_lock_gv_name))
   {
      long owner = (long)GlobalVariableGet(g_lock_gv_name);
      if(owner != my_chart && ChartPeriod(owner) > 0) return false;
   }
   GlobalVariableSet(g_lock_gv_name, (double)my_chart);
   return true;
}

void ReleaseInstanceLock()
{
   if(MQLInfoInteger(MQL_TESTER) || g_lock_gv_name == "") return;
   if(GlobalVariableCheck(g_lock_gv_name) && (long)GlobalVariableGet(g_lock_gv_name) == ChartID())
      GlobalVariableDel(g_lock_gv_name);
}

//+------------------------------------------------------------------+
//| Persistent State Management                                      |
//+------------------------------------------------------------------+
void BuildGVPrefix()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   StringReplace(server, " ", "_");
   g_gv_prefix = StringFormat("VCX3_%I64d_%s_%I64u_", login, server, InpMagicNumber);
}

int ComputeISOWeekId(const MqlDateTime &dt)
{
   return dt.year * 100 + ((dt.day_of_year - dt.day_of_week + 10) / 7);
}

void SavePersistentState(bool flush_now = false)
{
   GlobalVariableSet(g_gv_prefix + "INIT_CAP",  g_persist.initial_capital);
   GlobalVariableSet(g_gv_prefix + "BASE_INIT", 1.0);
   GlobalVariableSet(g_gv_prefix + "EQ_PEAK",   g_persist.equity_peak);
   GlobalVariableSet(g_gv_prefix + "DAY_BAL",   g_persist.daily_start_balance);
   GlobalVariableSet(g_gv_prefix + "WK_BAL",    g_persist.weekly_start_balance);
   GlobalVariableSet(g_gv_prefix + "P_YEAR",    (double)g_persist.period_year);
   GlobalVariableSet(g_gv_prefix + "P_YDAY",    (double)g_persist.period_yday);
   GlobalVariableSet(g_gv_prefix + "P_WEEK",    (double)g_persist.period_week_id);
   GlobalVariableSet(g_gv_prefix + "CON_LOSS",  (double)g_persist.consecutive_losses);
   GlobalVariableSet(g_gv_prefix + "CON_WIN",   (double)g_persist.consecutive_wins);
   GlobalVariableSet(g_gv_prefix + "AM_MULT",   g_persist.anti_mart_mult);
   GlobalVariableSet(g_gv_prefix + "CD_UNTIL",  (double)g_persist.cooldown_until);
   GlobalVariableSet(g_gv_prefix + "USR_CTRL",  (double)g_persist.user_control);
   GlobalVariableSet(g_gv_prefix + "HARD_DD",   g_persist.hard_dd_locked ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "ACT_TKT",   (double)g_persist.active_ticket);
   GlobalVariableSet(g_gv_prefix + "ACT_STRAT", (double)g_persist.active_strategy_id);
   GlobalVariableSet(g_gv_prefix + "HI_FAV",    g_persist.highest_fav_price);
   GlobalVariableSet(g_gv_prefix + "MAX_PROF",  g_persist.max_fav_net_profit);
   GlobalVariableSet(g_gv_prefix + "LAST_SL",   g_persist.last_confirmed_sl);
   GlobalVariableSet(g_gv_prefix + "SL_MODS",   (double)g_persist.sl_mod_count);
   GlobalVariableSet(g_gv_prefix + "TOT_TRD",   (double)g_persist.total_trades);
   GlobalVariableSet(g_gv_prefix + "WIN_TRD",   (double)g_persist.win_trades);
   GlobalVariableSet(g_gv_prefix + "LOS_TRD",   (double)g_persist.loss_trades);
   GlobalVariableSet(g_gv_prefix + "GRS_PROF",  g_persist.gross_profit);
   GlobalVariableSet(g_gv_prefix + "GRS_LOSS",  g_persist.gross_loss);
   if(flush_now) GlobalVariablesFlush();
}

void ResetBaselineToCurrentAccount()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   g_persist.initial_capital      = (InpInitialCapital > 0.0) ? InpInitialCapital : bal;
   g_persist.baseline_initialized = true;
   g_persist.equity_peak          = MathMax(eq, g_persist.initial_capital);
   g_persist.daily_start_balance  = bal;
   g_persist.weekly_start_balance = bal;
   g_persist.period_year          = dt.year;
   g_persist.period_yday          = dt.day_of_year;
   g_persist.period_week_id       = ComputeISOWeekId(dt);
   g_persist.consecutive_losses   = 0;
   g_persist.consecutive_wins     = 0;
   g_persist.anti_mart_mult       = 1.0;
   g_persist.cooldown_until       = 0;
   g_persist.hard_dd_locked       = false;
   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED)
      g_persist.user_control = CTRL_EA_ON;
   SavePersistentState(true);
}

void LoadPersistentState()
{
   BuildGVPrefix();
   if(!GlobalVariableCheck(g_gv_prefix + "BASE_INIT") || MQLInfoInteger(MQL_TESTER) || InpResetBaselineOnInit)
   {
      ZeroMemory(g_persist);
      g_persist.user_control = CTRL_EA_ON;
      ResetBaselineToCurrentAccount();
      return;
   }

   g_persist.initial_capital      = GlobalVariableGet(g_gv_prefix + "INIT_CAP");
   g_persist.baseline_initialized = true;
   g_persist.equity_peak          = GlobalVariableGet(g_gv_prefix + "EQ_PEAK");
   g_persist.daily_start_balance  = GlobalVariableGet(g_gv_prefix + "DAY_BAL");
   g_persist.weekly_start_balance = GlobalVariableGet(g_gv_prefix + "WK_BAL");
   g_persist.period_year          = (int)GlobalVariableGet(g_gv_prefix + "P_YEAR");
   g_persist.period_yday          = (int)GlobalVariableGet(g_gv_prefix + "P_YDAY");
   g_persist.period_week_id       = (int)GlobalVariableGet(g_gv_prefix + "P_WEEK");
   g_persist.consecutive_losses   = (int)GlobalVariableGet(g_gv_prefix + "CON_LOSS");
   g_persist.consecutive_wins     = (int)GlobalVariableGet(g_gv_prefix + "CON_WIN");
   g_persist.anti_mart_mult       = GlobalVariableGet(g_gv_prefix + "AM_MULT");
   if(g_persist.anti_mart_mult <= 0.0) g_persist.anti_mart_mult = 1.0;
   g_persist.cooldown_until       = (datetime)GlobalVariableGet(g_gv_prefix + "CD_UNTIL");
   g_persist.user_control         = (int)GlobalVariableGet(g_gv_prefix + "USR_CTRL");
   g_persist.hard_dd_locked       = (GlobalVariableGet(g_gv_prefix + "HARD_DD") > 0.5);
   g_persist.active_ticket        = (ulong)GlobalVariableGet(g_gv_prefix + "ACT_TKT");
   g_persist.active_strategy_id   = (int)GlobalVariableGet(g_gv_prefix + "ACT_STRAT");
   g_persist.highest_fav_price    = GlobalVariableGet(g_gv_prefix + "HI_FAV");
   g_persist.max_fav_net_profit   = GlobalVariableGet(g_gv_prefix + "MAX_PROF");
   g_persist.last_confirmed_sl    = GlobalVariableGet(g_gv_prefix + "LAST_SL");
   g_persist.sl_mod_count         = (int)GlobalVariableGet(g_gv_prefix + "SL_MODS");
   g_persist.total_trades         = (int)GlobalVariableGet(g_gv_prefix + "TOT_TRD");
   g_persist.win_trades           = (int)GlobalVariableGet(g_gv_prefix + "WIN_TRD");
   g_persist.loss_trades          = (int)GlobalVariableGet(g_gv_prefix + "LOS_TRD");
   g_persist.gross_profit         = GlobalVariableGet(g_gv_prefix + "GRS_PROF");
   g_persist.gross_loss           = GlobalVariableGet(g_gv_prefix + "GRS_LOSS");

   // Auto-reconcile if user deposited funds (like +990 USD top-up) while flat
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(PositionsTotal() == 0 && MathAbs(bal - g_persist.daily_start_balance) > g_persist.initial_capital * 0.25 && g_persist.total_trades == 0)
   {
      g_persist.daily_start_balance  = bal;
      g_persist.weekly_start_balance = bal;
      g_persist.equity_peak          = MathMax(g_persist.equity_peak, bal);
      SavePersistentState(true);
   }
}

//+------------------------------------------------------------------+
//| Strategy Registry Initialization                                 |
//+------------------------------------------------------------------+
void InitStrategyRegistry()
{
   string names[MAX_STRATEGIES] = {
      "S01_EXTREME_VOL_BREAK", "S02_TICK_IGNITION",     "S03_ACCEL_JERK_FLOW",
      "S04_IMPULSE_CONT",      "S05_SUBSEC_BREAKOUT",   "S06_M1_PULLBACK_TREND",
      "S07_LIQ_SWEEP_REV",     "S08_BB_TRAP_RECLAIM",   "S09_MACD_SURGE_EXP",
      "S10_ADX_DI_PRESSURE",   "S11_EXHAUSTION_SNAP",   "S12_SQUEEZE_RELEASE",
      "S13_SESSION_MOMENTUM",  "S14_MTF_EMA_RIBBON",    "S15_HURST_FLOW_PERSIST",
      "S16_VWAP_PROXY_BOUNCE"
   };
   int families[MAX_STRATEGIES] = { 2, 4, 4, 1, 4, 0, 3, 3, 2, 1, 1, 2, 3, 0, 5, 3 };

   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      g_strategies[i].id           = i + 1;
      g_strategies[i].name         = names[i];
      g_strategies[i].family       = families[i];
      g_strategies[i].base_weight  = 1.0;
      g_strategies[i].reliability  = 0.80;
      g_strategies[i].buy_score    = 0.0;
      g_strategies[i].sell_score   = 0.0;
      g_strategies[i].trades_count = 0;
      g_strategies[i].wins_count   = 0;
   }
}

//+------------------------------------------------------------------+
//| Helpers: Price & Volume Step Normalization                       |
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
   while(s < 1.0 - 1e-9 && digits < 8) { s *= 10.0; digits++; }
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
   if(!ValidateGoldSymbol(_Symbol)) return INIT_FAILED;
   g_validated_symbol = _Symbol;
   g_symbol.Name(g_validated_symbol);
   g_symbol.RefreshRates();

   if(!AcquireInstanceLock()) return INIT_FAILED;

   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode == ACCOUNT_TRADE_MODE_REAL && !InpAllowRealMoneyTrading && !MQLInfoInteger(MQL_TESTER))
   {
      Print("CRITICAL [Vulcares Vx V3]: Real account blocked. Set InpAllowRealMoneyTrading=true to run on live real account.");
      ReleaseInstanceLock();
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(35);
   g_trade.SetTypeFilling(GetOptimalFillingMode(g_validated_symbol));
   g_trade.SetAsyncMode(false);

   LoadPersistentState();
   InitStrategyRegistry();

   g_hATR_7      = iATR(g_validated_symbol, PERIOD_M1, 7);
   g_hATR_14     = iATR(g_validated_symbol, PERIOD_M1, 14);
   g_hATR_50     = iATR(g_validated_symbol, PERIOD_M1, 50);
   g_hEMA_8_M15  = iMA(g_validated_symbol, PERIOD_M15, 8,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M15 = iMA(g_validated_symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_55_M15 = iMA(g_validated_symbol, PERIOD_M15, 55, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_5_M5   = iMA(g_validated_symbol, PERIOD_M5,  5,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_13_M5  = iMA(g_validated_symbol, PERIOD_M5,  13, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_34_M5  = iMA(g_validated_symbol, PERIOD_M5,  34, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_5_M1   = iMA(g_validated_symbol, PERIOD_M1,  5,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_13_M1  = iMA(g_validated_symbol, PERIOD_M1,  13, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_34_M1  = iMA(g_validated_symbol, PERIOD_M1,  34, 0, MODE_EMA, PRICE_CLOSE);
   g_hRSI_14_M1  = iRSI(g_validated_symbol, PERIOD_M1, 14, PRICE_CLOSE);
   g_hADX_14_M5  = iADX(g_validated_symbol, PERIOD_M5, 14);
   g_hMACD_M1    = iMACD(g_validated_symbol, PERIOD_M1, 8, 21, 5, PRICE_CLOSE);
   g_hBB_20_M1   = iBands(g_validated_symbol, PERIOD_M1, 20, 0, 2.0, PRICE_CLOSE);

   if(g_hATR_7 == INVALID_HANDLE || g_hATR_14 == INVALID_HANDLE || g_hATR_50 == INVALID_HANDLE ||
      g_hEMA_8_M15 == INVALID_HANDLE || g_hEMA_21_M15 == INVALID_HANDLE || g_hEMA_55_M15 == INVALID_HANDLE ||
      g_hEMA_5_M5 == INVALID_HANDLE || g_hEMA_13_M5 == INVALID_HANDLE || g_hEMA_34_M5 == INVALID_HANDLE ||
      g_hEMA_5_M1 == INVALID_HANDLE || g_hEMA_13_M1 == INVALID_HANDLE || g_hEMA_34_M1 == INVALID_HANDLE ||
      g_hRSI_14_M1 == INVALID_HANDLE || g_hADX_14_M5 == INVALID_HANDLE || g_hMACD_M1 == INVALID_HANDLE ||
      g_hBB_20_M1 == INVALID_HANDLE)
   {
      ReleaseInstanceLock();
      return INIT_FAILED;
   }

   ReconcileBrokerState();
   if(InpShowProfessionalDashboard) CreateControlCenter();
   EventSetMillisecondTimer(250);
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
   IndicatorRelease(g_hEMA_5_M1);  IndicatorRelease(g_hEMA_13_M1); IndicatorRelease(g_hEMA_34_M1);
   IndicatorRelease(g_hRSI_14_M1); IndicatorRelease(g_hADX_14_M5); IndicatorRelease(g_hMACD_M1);
   IndicatorRelease(g_hBB_20_M1);

   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Anti-Martingale Dynamic Risk Budget Engine                       |
//+------------------------------------------------------------------+
double GetCurrentAntiMartingaleRiskBudget()
{
   double base_risk = (g_persist.initial_capital * InpBaseRiskPercent) / 100.0;
   double mult = InpEnableAntiMartingale ? g_persist.anti_mart_mult : 1.0;
   double target_risk = base_risk * mult;

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double daily_pnl  = eq - g_persist.daily_start_balance;
   double rem_daily  = (g_persist.initial_capital * (InpDailyLossLimitPct / 100.0)) + daily_pnl;

   double weekly_pnl = eq - g_persist.weekly_start_balance;
   double rem_weekly = (g_persist.initial_capital * (InpWeeklyLossLimitPct / 100.0)) + weekly_pnl;

   return MathMax(0.0, MathMin(target_risk, MathMin(rem_daily, rem_weekly)));
}

double CalculateValidatedLot(ENUM_ORDER_TYPE order_type, double entry_price, double sl_price, double &est_total_risk)
{
   double risk_budget = GetCurrentAntiMartingaleRiskBudget();
   if(risk_budget <= 0.0) { g_reject_reason = "RISK_BUDGET_DEPLETED"; return 0.0; }

   double vol_min  = g_symbol.LotsMin();
   double vol_max  = g_symbol.LotsMax();
   double vol_step = g_symbol.LotsStep();
   double reserve_mult = 1.0 + (InpCostSlippageBufferPct / 100.0);

   double profit_1lot = 0.0;
   if(!OrderCalcProfit(order_type, g_validated_symbol, 1.0, entry_price, sl_price, profit_1lot))
      return 0.0;

   double loss_1lot = MathAbs(profit_1lot);
   if(loss_1lot <= 0.0 || profit_1lot >= 0.0) return 0.0;

   double stepped_lot = NormalizeVolumeStep((risk_budget / reserve_mult) / loss_1lot);
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
      if(stepped_lot < vol_min) { g_reject_reason = "RISK_CAP_REACHED"; return 0.0; }
      if(!OrderCalcProfit(order_type, g_validated_symbol, stepped_lot, entry_price, sl_price, actual_sl_profit))
         return 0.0;
      est_total_risk = MathAbs(actual_sl_profit) * reserve_mult;
   }

   if(est_total_risk > risk_budget) { g_reject_reason = "MIN_LOT_EXCEEDS_RISK"; return 0.0; }

   double margin_req = 0.0;
   if(!OrderCalcMargin(order_type, g_validated_symbol, stepped_lot, entry_price, margin_req))
      return 0.0;
   if(margin_req > AccountInfoDouble(ACCOUNT_EQUITY) * (InpMaxMarginUsagePct / 100.0))
   {
      g_reject_reason = "MARGIN_USAGE_LIMIT";
      return 0.0;
   }

   MqlTradeRequest req;
   MqlTradeCheckResult chk;
   ZeroMemory(req); ZeroMemory(chk);
   req.action = TRADE_ACTION_DEAL; req.symbol = g_validated_symbol;
   req.volume = stepped_lot; req.type = order_type; req.price = entry_price;
   req.sl = sl_price; req.tp = 0.0; req.deviation = 35;
   req.magic = InpMagicNumber; req.type_filling = GetOptimalFillingMode(g_validated_symbol);

   if(!OrderCheck(req, chk))
   {
      g_reject_reason = StringFormat("ORDERCHECK_%u", chk.retcode);
      return 0.0;
   }
   return stepped_lot;
}

//+------------------------------------------------------------------+
//| Circular Tick Buffer & Synthetic Windows                         |
//+------------------------------------------------------------------+
void RecordTick(const MqlTick &tick)
{
   double mid = (tick.bid + tick.ask) * 0.5;
   int dir = 0;
   if(g_tick_count > 0)
   {
      int prev = (g_tick_head - 1 + TICK_BUF_SIZE) % TICK_BUF_SIZE;
      if(mid > g_ticks[prev].mid) dir = 1;
      else if(mid < g_ticks[prev].mid) dir = -1;
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
                          double &hi, double &lo, double &max_sp, int &imb)
{
   cnt = 0; net_move = 0.0; path_len = 0.0; max_sp = 0.0; imb = 0;
   hi = 0.0; lo = DBL_MAX;
   if(g_tick_count < 2) return;

   int newest = (g_tick_head - 1 + TICK_BUF_SIZE) % TICK_BUF_SIZE;
   long t_now = g_ticks[newest].time_msc;
   double end_mid = g_ticks[newest].mid;
   double start_mid = end_mid, prev_mid = end_mid;

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
      prev_mid = m;
   }
   net_move = end_mid - start_mid;
}

//+------------------------------------------------------------------+
//| Volatility & Market Regime Classifier                            |
//+------------------------------------------------------------------+
void UpdateVolatilityRegime()
{
   double atr7[2], atr14[2], atr50[2];
   if(CopyBuffer(g_hATR_7, 0, 0, 2, atr7) < 2 || CopyBuffer(g_hATR_14, 0, 0, 2, atr14) < 2 || CopyBuffer(g_hATR_50, 0, 0, 2, atr50) < 2)
   {
      g_vol_score = 50; g_regime = REGIME_NORMAL; return;
   }

   double cur_spread = g_symbol.Ask() - g_symbol.Bid();
   double sp_to_atr  = (atr14[0] > 0.0) ? (cur_spread / atr14[0]) : 1.0;

   int c1s=0, imb1s=0, c5s=0, imb5s=0;
   double n1s=0, p1s=0, hi1s=0, lo1s=0, msp1s=0;
   double n5s=0, p5s=0, hi5s=0, lo5s=0, msp5s=0;
   QuerySyntheticWindow(1000, c1s, n1s, p1s, hi1s, lo1s, msp1s, imb1s);
   QuerySyntheticWindow(5000, c5s, n5s, p5s, hi5s, lo5s, msp5s, imb5s);

   if(sp_to_atr > InpMaxSpreadToATRRatio || (msp1s > cur_spread * 3.5 && cur_spread > 0))
   {
      g_regime = REGIME_TOXIC_VOL; g_vol_score = 99; g_reject_reason = "TOXIC_SPREAD"; return;
   }

   double atr_ratio = (atr50[0] > 0.0) ? MathMin(2.5, atr7[0] / atr50[0]) : 1.0;
   double s_atr = ((atr_ratio - 0.65) / 1.85) * 40.0;
   double s_vel = MathMin(30.0, (double)c1s * 2.5);
   double eff5s = (p5s > 0.0) ? MathAbs(n5s) / p5s : 0.0;
   double s_eff = eff5s * 30.0;

   g_vol_score = (int)MathRound(MathMax(5.0, MathMin(100.0, s_atr + s_vel + s_eff)));

   if(g_vol_score < 35)       g_regime = REGIME_DORMANT;
   else if(g_vol_score < 55)  g_regime = REGIME_LOW_VOL;
   else if(g_vol_score < 75)  g_regime = REGIME_NORMAL;
   else if(g_vol_score < 90)  g_regime = REGIME_HIGH_VOL;
   else if(eff5s > 0.60)      g_regime = REGIME_EXPLOSIVE_MOM;
   else                       g_regime = REGIME_EXTREME_VOL;
}

bool CheckCachedNewsFilter()
{
   if(!InpNewsProtection) return false;
   datetime now = TimeCurrent();
   if(now - g_last_news_check >= 30)
   {
      g_last_news_check = now;
      g_news_blocked_cache = false;
      MqlCalendarValue vals[];
      if(CalendarValueHistory(vals, now - InpNewsBlockAfterMin * 60, now + InpNewsBlockBeforeMin * 60, "USD") > 0)
      {
         for(int i = 0; i < ArraySize(vals); i++)
         {
            MqlCalendarEvent ev;
            if(CalendarEventById(vals[i].event_id, ev) && ev.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               if(vals[i].time >= now - 45) g_news_blocked_cache = true;
            }
         }
      }
   }
   return g_news_blocked_cache;
}

//+------------------------------------------------------------------+
//| Quality-Gated Dominance Intelligence Engine (Anti-Chop V3)       |
//+------------------------------------------------------------------+
DominanceResult EvaluatePrecisionDominance()
{
   ulong t0 = GetMicrosecondCount();
   DominanceResult res;
   ZeroMemory(res);

   double e8_15[2], e21_15[2], e55_15[2];
   double e5_5[2],  e13_5[2],  e34_5[2];
   double e5_1[2],  e13_1[2],  e34_1[2];
   double rsi14[2], adx5[2], pdi5[2], ndi5[2];
   double bb_u[2],  bb_l[2], bb_m[2], macd_m[2], macd_s[2], atr14[2];

   if(CopyBuffer(g_hEMA_8_M15, 0, 0, 2, e8_15) < 2 || CopyBuffer(g_hEMA_21_M15, 0, 0, 2, e21_15) < 2 || CopyBuffer(g_hEMA_55_M15, 0, 0, 2, e55_15) < 2 ||
      CopyBuffer(g_hEMA_5_M5,  0, 0, 2, e5_5)  < 2 || CopyBuffer(g_hEMA_13_M5,  0, 0, 2, e13_5)  < 2 || CopyBuffer(g_hEMA_34_M5,  0, 0, 2, e34_5)  < 2 ||
      CopyBuffer(g_hEMA_5_M1,  0, 0, 2, e5_1)  < 2 || CopyBuffer(g_hEMA_13_M1,  0, 0, 2, e13_1)  < 2 || CopyBuffer(g_hEMA_34_M1,  0, 0, 2, e34_1)  < 2 ||
      CopyBuffer(g_hRSI_14_M1, 0, 0, 2, rsi14) < 2 || CopyBuffer(g_hADX_14_M5,  0, 0, 2, adx5)   < 2 ||
      CopyBuffer(g_hADX_14_M5, 1, 0, 2, pdi5)  < 2 || CopyBuffer(g_hADX_14_M5,  2, 0, 2, ndi5)   < 2 ||
      CopyBuffer(g_hBB_20_M1,  1, 0, 2, bb_u)  < 2 || CopyBuffer(g_hBB_20_M1,   2, 0, 2, bb_l)   < 2 ||
      CopyBuffer(g_hBB_20_M1,  0, 0, 2, bb_m)  < 2 || CopyBuffer(g_hMACD_M1,    0, 0, 2, macd_m) < 2 ||
      CopyBuffer(g_hMACD_M1,   1, 0, 2, macd_s)< 2 || CopyBuffer(g_hATR_14,     0, 0, 2, atr14)  < 2)
      return res;

   int c250=0, imb250=0, c1s=0, imb1s=0, c5s=0, imb5s=0, c15s=0, imb15s=0;
   double n250=0, p250=0, hi250=0, lo250=0, sp250=0;
   double n1s=0,  p1s=0,  hi1s=0,  lo1s=0,  sp1s=0;
   double n5s=0,  p5s=0,  hi5s=0,  lo5s=0,  sp5s=0;
   double n15s=0, p15s=0, hi15s=0, lo15s=0, sp15s=0;

   QuerySyntheticWindow(250,   c250, n250, p250, hi250, lo250, sp250, imb250);
   QuerySyntheticWindow(1000,  c1s,  n1s,  p1s,  hi1s,  lo1s,  sp1s,  imb1s);
   QuerySyntheticWindow(5000,  c5s,  n5s,  p5s,  hi5s,  lo5s,  sp5s,  imb5s);
   QuerySyntheticWindow(15000, c15s, n15s, p15s, hi15s, lo15s, sp15s, imb15s);

   double bid = g_symbol.Bid(), ask = g_symbol.Ask();
   double mid = (bid + ask) * 0.5, spread = ask - bid;
   double m1_hi1 = iHigh(g_validated_symbol, PERIOD_M1, 1);
   double m1_lo1 = iLow(g_validated_symbol, PERIOD_M1, 1);
   double m1_cl1 = iClose(g_validated_symbol, PERIOD_M1, 1);
   double m5_hi1 = iHigh(g_validated_symbol, PERIOD_M5, 1);
   double m5_lo1 = iLow(g_validated_symbol, PERIOD_M5, 1);

   // Efficiency Ratio across 15s tick window & M1 bars to filter out choppy sideways markets
   double eff15s = (p15s > 0.0) ? MathAbs(n15s) / p15s : 0.0;
   res.efficiency_ratio = eff15s;

   for(int i = 0; i < MAX_STRATEGIES; i++) { g_strategies[i].buy_score = 0.0; g_strategies[i].sell_score = 0.0; }

   // Macro Trend Bias (M15 & M5)
   bool macro_bull = (e8_15[0] > e21_15[0] && e5_5[0] > e13_5[0]);
   bool macro_bear = (e8_15[0] < e21_15[0] && e5_5[0] < e13_5[0]);

   // S01: Extreme Volatility Breakout
   if(mid > m5_hi1 && n5s > spread && macro_bull) g_strategies[0].buy_score = 0.95;
   if(mid < m5_lo1 && n5s < -spread && macro_bear) g_strategies[0].sell_score = 0.95;

   // S02: Tick Momentum Ignition
   if(n1s > spread * 1.2 && imb1s >= 3)  g_strategies[1].buy_score = 0.85;
   if(n1s < -spread * 1.2 && imb1s <= -3)g_strategies[1].sell_score = 0.85;

   // S03: Acceleration & Jerk Flow
   if(n250 * 4.0 > n1s && n250 > 0 && n5s > 0) g_strategies[2].buy_score = 0.82;
   if(n250 * 4.0 < n1s && n250 < 0 && n5s < 0) g_strategies[2].sell_score = 0.82;

   // S04: M1 Impulse Continuation
   if(e5_1[0] > e13_1[0] && e13_1[0] > e34_1[0] && n5s > 0) g_strategies[3].buy_score = 0.88;
   if(e5_1[0] < e13_1[0] && e13_1[0] < e34_1[0] && n5s < 0) g_strategies[3].sell_score = 0.88;

   // S05: 15s Sub-Second Breakout
   if(hi15s > lo15s)
   {
      if(mid >= hi15s && n1s > 0) g_strategies[4].buy_score = 0.80;
      if(mid <= lo15s && n1s < 0) g_strategies[4].sell_score = 0.80;
   }

   // S06: M1 Trend Pullback Entry (High Win-Rate Structural Setup)
   if(macro_bull && m1_lo1 <= e13_1[1] && m1_cl1 > e5_1[0] && n1s > 0) g_strategies[5].buy_score = 0.92;
   if(macro_bear && m1_hi1 >= e13_1[1] && m1_cl1 < e5_1[0] && n1s < 0) g_strategies[5].sell_score = 0.92;

   // S07: Liquidity Sweep Reversal
   if(m1_lo1 < m5_lo1 && m1_cl1 > m5_lo1 && n5s > spread) g_strategies[6].buy_score = 0.86;
   if(m1_hi1 > m5_hi1 && m1_cl1 < m5_hi1 && n5s < -spread) g_strategies[6].sell_score = 0.86;

   // S08: Bollinger Band Trap Reclaim
   if(m1_lo1 < bb_l[1] && mid > bb_l[0] && imb5s >= 2) g_strategies[7].buy_score = 0.78;
   if(m1_hi1 > bb_u[1] && mid < bb_u[0] && imb5s <= -2) g_strategies[7].sell_score = 0.78;

   // S09: MACD Momentum Expansion
   if(macd_m[0] > macd_s[0] && macd_m[0] > macd_m[1] && n5s > 0) g_strategies[8].buy_score = 0.82;
   if(macd_m[0] < macd_s[0] && macd_m[0] < macd_m[1] && n5s < 0) g_strategies[8].sell_score = 0.82;

   // S10: ADX + Directional Index Trend Strength
   if(adx5[0] > 22.0 && pdi5[0] > ndi5[0]) g_strategies[9].buy_score = MathMin(1.0, adx5[0] / 40.0);
   if(adx5[0] > 22.0 && ndi5[0] > pdi5[0]) g_strategies[9].sell_score = MathMin(1.0, adx5[0] / 40.0);

   // S11: Oversold/Overbought Snap with Tick Confirmation
   if(rsi14[0] < 28.0 && n5s > spread && imb5s >= 3) g_strategies[10].buy_score = 0.76;
   if(rsi14[0] > 72.0 && n5s < -spread && imb5s <= -3) g_strategies[10].sell_score = 0.76;

   // S12: Bollinger Volatility Squeeze Breakout
   double bb_w = (bb_m[0] > 0.0) ? (bb_u[0] - bb_l[0]) / bb_m[0] : 0.0;
   if(bb_w < 0.0022 && mid > bb_u[0] && n1s > 0) g_strategies[11].buy_score = 0.90;
   if(bb_w < 0.0022 && mid < bb_l[0] && n1s < 0) g_strategies[11].sell_score = 0.90;

   // S13: London / NY Active Liquidity Session Flow
   MqlDateTime dt; TimeCurrent(dt);
   if((dt.hour >= 7 && dt.hour <= 11) || (dt.hour >= 13 && dt.hour <= 17))
   {
      if(macro_bull && n15s > 0) g_strategies[12].buy_score = 0.78;
      if(macro_bear && n15s < 0) g_strategies[12].sell_score = 0.78;
   }

   // S14: Full MTF EMA Alignment (M1 + M5 + M15)
   if(macro_bull && e5_1[0] > e13_1[0] && mid > e5_1[0]) g_strategies[13].buy_score = 0.94;
   if(macro_bear && e5_1[0] < e13_1[0] && mid < e5_1[0]) g_strategies[13].sell_score = 0.94;

   // S15: Hurst Directional Persistence
   if(eff15s >= InpMinEfficiencyRatio && n15s > 0) g_strategies[14].buy_score = 0.88;
   if(eff15s >= InpMinEfficiencyRatio && n15s < 0) g_strategies[14].sell_score = 0.88;

   // S16: Dynamic VWAP Proxy Bounce
   double vwap_p = (bb_m[0] + e13_1[0] + e13_5[0]) / 3.0;
   if(mid > vwap_p && m1_cl1 <= vwap_p && n1s > 0) g_strategies[15].buy_score = 0.80;
   if(mid < vwap_p && m1_cl1 >= vwap_p && n1s < 0) g_strategies[15].sell_score = 0.80;

   double total_buy_u = 0.0, total_sell_u = 0.0, best_val = -1.0;
   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      double w = g_strategies[i].base_weight * g_strategies[i].reliability;
      double b_u = g_strategies[i].buy_score * w;
      double s_u = g_strategies[i].sell_score * w;
      total_buy_u  += b_u;
      total_sell_u += s_u;
      if(g_strategies[i].buy_score > 0.5)  res.buy_supporters++;
      if(g_strategies[i].sell_score > 0.5) res.sell_supporters++;

      double m = MathMax(b_u, s_u);
      if(m > best_val) { best_val = m; res.top_strategy_name = g_strategies[i].name; res.top_strategy_id = g_strategies[i].id; }
   }

   double sum_u = total_buy_u + total_sell_u;
   if(sum_u > 0.0)
   {
      res.buy_dominance_pct     = (total_buy_u / sum_u) * 100.0;
      res.sell_dominance_pct    = (total_sell_u / sum_u) * 100.0;
      res.directional_agreement = MathAbs(total_buy_u - total_sell_u) / sum_u;
   }
   else
   {
      res.buy_dominance_pct = 50.0; res.sell_dominance_pct = 50.0; res.directional_agreement = 0.0;
   }

   res.buy_final_utility  = total_buy_u;
   res.sell_final_utility = total_sell_u;

   // Anti-Chop Quality Gates (Prevents bleeding in sideways noise)
   bool eff_ok   = (eff15s >= InpMinEfficiencyRatio);
   bool agree_ok = (res.directional_agreement >= InpMinDirectionalAgreement);

   if(eff_ok && agree_ok)
   {
      if(total_buy_u > total_sell_u + InpMinDominanceAdvantage && (!InpRequireMTFAlignment || e8_15[0] >= e21_15[0]))
         res.dominant_dir = 1;
      else if(total_sell_u > total_buy_u + InpMinDominanceAdvantage && (!InpRequireMTFAlignment || e8_15[0] <= e21_15[0]))
         res.dominant_dir = -1;
   }

   res.rec_sl_dist = MathMax(atr14[0] * 0.85, atr14[0] * InpInitialSL_ATRMult);
   g_decision_latency_ms = (double)(GetMicrosecondCount() - t0) / 1000.0;
   return res;
}

//+------------------------------------------------------------------+
//| Capital Survival Guardrails                                      |
//+------------------------------------------------------------------+
bool CheckCapitalSurvival()
{
   MqlDateTime dt; TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(dt.year != g_persist.period_year || dt.day_of_year != g_persist.period_yday)
   {
      g_persist.period_year = dt.year; g_persist.period_yday = dt.day_of_year;
      g_persist.daily_start_balance = bal;
      SavePersistentState(false);
   }
   int wk_id = ComputeISOWeekId(dt);
   if(wk_id != g_persist.period_week_id)
   {
      g_persist.period_week_id = wk_id; g_persist.weekly_start_balance = bal;
      SavePersistentState(false);
   }

   if(eq > g_persist.equity_peak) g_persist.equity_peak = eq;

   double max_init_dd = g_persist.initial_capital * (InpMaxInitialDDPct / 100.0);
   if((g_persist.initial_capital - eq) >= max_init_dd || g_persist.hard_dd_locked)
   {
      g_persist.hard_dd_locked = true; g_exec_state = STATE_RISK_LOCKED; g_reject_reason = "HARD_DD_LOCKED";
      SavePersistentState(true);
      return false;
   }

   double peak_dd_pct = (g_persist.equity_peak > 0.0) ? ((g_persist.equity_peak - eq) / g_persist.equity_peak) * 100.0 : 0.0;
   if(peak_dd_pct >= InpMaxPeakDDPct)
   {
      g_persist.hard_dd_locked = true; g_exec_state = STATE_RISK_LOCKED; g_reject_reason = "PEAK_DD_LOCKED";
      SavePersistentState(true);
      return false;
   }

   if((eq - g_persist.daily_start_balance) <= -(g_persist.initial_capital * (InpDailyLossLimitPct / 100.0)))
   {
      g_reject_reason = "DAILY_LOSS_LIMIT"; return false;
   }

   if((eq - g_persist.weekly_start_balance) <= -(g_persist.initial_capital * (InpWeeklyLossLimitPct / 100.0)))
   {
      g_reject_reason = "WEEKLY_LOSS_LIMIT"; return false;
   }

   if(TimeCurrent() < g_persist.cooldown_until)
   {
      g_reject_reason = "LOSS_COOLDOWN"; return false;
   }

   double margin_lvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin_lvl > 0.0 && margin_lvl < InpMinMarginLevel)
   {
      g_reject_reason = "LOW_MARGIN_LEVEL"; return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Single-Position Audit & Reconciliation                           |
//+------------------------------------------------------------------+
int AuditSymbolExposure(ulong &ea_pos_tkt, ulong &ea_ord_tkt, bool &foreign_pos)
{
   ea_pos_tkt = 0; ea_ord_tkt = 0; foreign_pos = false;
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == g_validated_symbol)
      {
         if(g_pos.Magic() == InpMagicNumber) { ea_pos_tkt = g_pos.Ticket(); cnt++; }
         else foreign_pos = true;
      }
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(g_ord.SelectByIndex(i) && g_ord.Symbol() == g_validated_symbol && g_ord.Magic() == InpMagicNumber)
      {
         ea_ord_tkt = g_ord.Ticket(); cnt++;
      }
   }
   return cnt;
}

void ReconcileBrokerState()
{
   ulong pos_tkt = 0, ord_tkt = 0; bool foreign = false;
   AuditSymbolExposure(pos_tkt, ord_tkt, foreign);

   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED) { g_exec_state = STATE_EMERGENCY_LOCKED; return; }
   if(g_persist.hard_dd_locked) { g_exec_state = STATE_RISK_LOCKED; return; }

   if(pos_tkt > 0 && g_pos.SelectByTicket(pos_tkt))
   {
      g_persist.active_ticket = pos_tkt;
      double b_sl = g_pos.StopLoss();
      if(b_sl <= 0.0) { EmergencyCloseTicket(pos_tkt); return; }
      if(g_persist.last_confirmed_sl <= 0.0) g_persist.last_confirmed_sl = b_sl;
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_TRAILING_ACTIVE;
   }
   else
   {
      g_persist.active_ticket = 0; g_persist.highest_fav_price = 0.0;
      g_persist.max_fav_net_profit = 0.0; g_persist.last_confirmed_sl = 0.0; g_persist.sl_mod_count = 0;
      g_trail_phase = PHASE_0_INSTANT_PROT; g_target_lock_val = 0.0; g_protected_val = 0.0;

      if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
      {
         g_persist.user_control = CTRL_STOPPED;
         g_exec_state = STATE_STOPPED;
      }
      else g_exec_state = STATE_SCANNING;
   }
   g_dash_dirty = true;
}

void EmergencyCloseTicket(ulong ticket)
{
   for(int i = 0; i < 3; i++)
   {
      if(!g_pos.SelectByTicket(ticket)) break;
      if(g_trade.PositionClose(ticket) && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
      {
         ReconcileBrokerState(); return;
      }
   }
}

//+------------------------------------------------------------------+
//| True Net-Profit Trailing Stop (Breathing Structural Mode)        |
//+------------------------------------------------------------------+
double FindStopPriceForTargetNetProfit(ENUM_POSITION_TYPE pos_type, double lot, double open_price, double target_net)
{
   ENUM_ORDER_TYPE sim_type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double cur_p = (pos_type == POSITION_TYPE_BUY) ? g_symbol.Bid() : g_symbol.Ask();
   double lo = MathMin(open_price, cur_p), hi = MathMax(open_price, cur_p);

   for(int iter = 0; iter < 16; iter++)
   {
      double mid = (lo + hi) * 0.5;
      double prof = 0.0;
      if(!OrderCalcProfit(sim_type, g_validated_symbol, lot, open_price, mid, prof)) break;
      if(pos_type == POSITION_TYPE_BUY) { if(prof < target_net) lo = mid; else hi = mid; }
      else                              { if(prof < target_net) hi = mid; else lo = mid; }
   }
   return (lo + hi) * 0.5;
}

void ManageBreathingTrailingStop()
{
   ulong pos_tkt = 0, ord_tkt = 0; bool foreign = false;
   AuditSymbolExposure(pos_tkt, ord_tkt, foreign);
   if(pos_tkt == 0 || !g_pos.SelectByTicket(pos_tkt)) { ReconcileBrokerState(); return; }

   bool is_buy       = (g_pos.PositionType() == POSITION_TYPE_BUY);
   double open_price = g_pos.PriceOpen();
   double cur_sl     = g_pos.StopLoss();
   double lot        = g_pos.Volume();
   double eval_price = is_buy ? g_symbol.Bid() : g_symbol.Ask();
   double spread     = g_symbol.Ask() - g_symbol.Bid();

   if(g_persist.highest_fav_price <= 0.0) g_persist.highest_fav_price = open_price;
   if(is_buy && eval_price > g_persist.highest_fav_price) g_persist.highest_fav_price = eval_price;
   if(!is_buy && eval_price < g_persist.highest_fav_price) g_persist.highest_fav_price = eval_price;

   double net_float = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
   double base_r    = (g_persist.initial_capital * InpBaseRiskPercent) / 100.0;
   if(net_float > g_persist.max_fav_net_profit) g_persist.max_fav_net_profit = net_float;
   double peak_r    = (base_r > 0.0) ? (g_persist.max_fav_net_profit / base_r) : 0.0;

   if(!InpDynamicTrailingStop) return;
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_trail_mod_ms < (ulong)InpTradeRequestIntervalMs) return;

   double lock_pct = 0.0;
   if(peak_r >= 5.0)       { lock_pct = 0.85; g_trail_phase = PHASE_5_EXTREME_PRESERVE; }
   else if(peak_r >= 3.0)  { lock_pct = 0.75; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 2.0)  { lock_pct = 0.65; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 1.5)  { lock_pct = 0.50; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= 1.15) { lock_pct = 0.30; g_trail_phase = PHASE_3_NET_PROFIT_LOCK; }
   else if(peak_r >= InpBreakEvenTriggerR) { g_trail_phase = PHASE_2_COST_BE; }
   else if(peak_r >= InpTrailingStartR)    { g_trail_phase = PHASE_1_BREATHING_PROT; }
   else return;

   double atr14[1];
   double atr_val = (CopyBuffer(g_hATR_14, 0, 0, 1, atr14) > 0) ? atr14[0] : spread * 5.0;
   double stop_lvl = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double trail_dist = MathMax(stop_lvl + g_symbol.TickSize() * 2.0, MathMax(spread * 2.0, atr_val * 1.10));
   double candidate_sl = is_buy ? (eval_price - trail_dist) : (eval_price + trail_dist);

   if(lock_pct > 0.0 && InpNetProfitTrailing)
   {
      double est_costs = MathAbs(g_pos.Commission()) * 2.0 + MathAbs(g_pos.Swap());
      g_target_lock_val = g_persist.max_fav_net_profit * lock_pct;
      double net_sl = FindStopPriceForTargetNetProfit(g_pos.PositionType(), lot, open_price, g_target_lock_val + est_costs);
      candidate_sl = is_buy ? MathMax(candidate_sl, net_sl) : MathMin(candidate_sl, net_sl);
   }
   else if(g_trail_phase == PHASE_2_COST_BE)
   {
      double be_sl = FindStopPriceForTargetNetProfit(g_pos.PositionType(), lot, open_price, MathAbs(g_pos.Commission()) * 2.0 + 0.05);
      candidate_sl = is_buy ? MathMax(candidate_sl, be_sl) : MathMin(candidate_sl, be_sl);
   }

   double legal_limit = is_buy ? (eval_price - stop_lvl - g_symbol.TickSize()) : (eval_price + stop_lvl + g_symbol.TickSize());
   candidate_sl = is_buy ? MathMin(candidate_sl, legal_limit) : MathMax(candidate_sl, legal_limit);
   candidate_sl = NormalizePriceDirectional(candidate_sl, !is_buy);

   double anchor_sl = (g_persist.last_confirmed_sl > 0.0) ? g_persist.last_confirmed_sl : cur_sl;
   double new_sl    = is_buy ? MathMax(anchor_sl, candidate_sl) : MathMin(anchor_sl, candidate_sl);
   double min_step  = g_symbol.TickSize() * 3.0;

   if((is_buy && new_sl >= cur_sl + min_step) || (!is_buy && new_sl <= cur_sl - min_step))
   {
      if(g_trade.PositionModify(pos_tkt, new_sl, g_pos.TakeProfit()) && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
      {
         g_persist.last_confirmed_sl = new_sl;
         g_persist.sl_mod_count++;
         g_last_trail_mod_ms = now_ms;
         double prot_g = 0.0;
         if(OrderCalcProfit(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, g_validated_symbol, lot, open_price, new_sl, prot_g))
            g_protected_val = prot_g + g_pos.Commission() * 2.0 + g_pos.Swap();
         g_dash_dirty = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Precision Single-Entry Execution                                 |
//+------------------------------------------------------------------+
void ExecutePrecisionEntry(const DominanceResult &dom)
{
   ulong p=0, o=0; bool foreign=false;
   if(AuditSymbolExposure(p, o, foreign) > 0) return;

   ENUM_ACCOUNT_MARGIN_MODE mm = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && foreign) { g_reject_reason = "NETTING_POS_LOCK"; return; }

   bool is_buy = (dom.dominant_dir > 0);
   double ask = g_symbol.Ask(), bid = g_symbol.Bid(), spread = ask - bid;
   if(dom.rec_sl_dist <= 0.0 || (spread / dom.rec_sl_dist) > InpMaxSpreadToSLRatio)
   {
      g_reject_reason = "SPREAD_TOO_WIDE"; return;
   }

   double stop_lvl = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double sl_dist  = MathMax(dom.rec_sl_dist, stop_lvl + spread * 1.5);
   double entry_p  = is_buy ? ask : bid;
   double sl_price = is_buy ? NormalizePriceDirectional(entry_p - sl_dist, false)
                            : NormalizePriceDirectional(entry_p + sl_dist, true);
   double tp_price = 0.0;
   if(InpInitialTP_RMultiple > 0.0)
   {
      tp_price = is_buy ? NormalizePriceDirectional(entry_p + sl_dist * InpInitialTP_RMultiple, true)
                        : NormalizePriceDirectional(entry_p - sl_dist * InpInitialTP_RMultiple, false);
   }

   double est_risk = 0.0;
   double lot = CalculateValidatedLot(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, entry_p, sl_price, est_risk);
   if(lot <= 0.0) return;

   ulong t0 = GetMicrosecondCount();
   string cmt = StringFormat("VCX3_AM%.1fx_S%02d", g_persist.anti_mart_mult, dom.top_strategy_id);
   bool sent = is_buy ? g_trade.Buy(lot, g_validated_symbol, ask, sl_price, tp_price, cmt)
                      : g_trade.Sell(lot, g_validated_symbol, bid, sl_price, tp_price, cmt);

   g_exec_latency_ms = (double)(GetMicrosecondCount() - t0) / 1000.0;
   g_last_retcode = g_trade.ResultRetcode();

   if(sent && g_last_retcode == TRADE_RETCODE_DONE)
   {
      double fill_p = g_trade.ResultPrice();
      g_reject_reason              = "NONE";
      g_persist.active_strategy_id = dom.top_strategy_id;
      g_persist.highest_fav_price  = (fill_p > 0.0) ? fill_p : entry_p;
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
   }
}

//+------------------------------------------------------------------+
//| Main Tick Handler                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_validated_symbol, tick)) return;
   g_symbol.RefreshRates();
   RecordTick(tick);

   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { g_exec_state = STATE_DISCONNECTED; return; }

   ulong pos_tkt = 0, ord_tkt = 0; bool foreign = false;
   AuditSymbolExposure(pos_tkt, ord_tkt, foreign);

   if(pos_tkt > 0)
   {
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_TRAILING_ACTIVE;
      ManageBreathingTrailingStop();
      return;
   }

   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED) { g_exec_state = STATE_EMERGENCY_LOCKED; g_reject_reason = "EMERGENCY_LOCKED"; return; }
   if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
   {
      g_persist.user_control = CTRL_STOPPED; g_exec_state = STATE_STOPPED; g_reject_reason = "USER_STOPPED"; return;
   }
   if(g_persist.user_control == CTRL_EA_OFF) { g_exec_state = STATE_SCANNING; g_reject_reason = "USER_EA_OFF"; return; }

   if(!CheckCapitalSurvival()) return;

   if(TimeCurrent() - g_last_close_time < InpPostCloseCooldownSec)
   {
      g_reject_reason = "ANTI_CHOP_COOLDOWN"; return;
   }

   UpdateVolatilityRegime();
   if(g_regime == REGIME_TOXIC_VOL || g_regime == REGIME_DORMANT)
   {
      g_reject_reason = (g_regime == REGIME_DORMANT) ? "DORMANT_MARKET" : "TOXIC_VOLATILITY";
      return;
   }

   if(InpTradingMode == MODE_VOLATILITY_SPECIALIST && g_regime < REGIME_HIGH_VOL) { g_reject_reason = "WAIT_HIGH_VOL"; return; }
   if(InpTradingMode == MODE_EXTREME_MOMENTUM && g_regime < REGIME_EXTREME_VOL)  { g_reject_reason = "WAIT_EXTREME_MOM"; return; }
   if(CheckCachedNewsFilter()) { g_reject_reason = "NEWS_WINDOW_PAUSE"; return; }

   g_exec_state = STATE_ANALYZING;
   g_dom = EvaluatePrecisionDominance();
   g_dash_dirty = true;

   if(g_dom.dominant_dir != 0) ExecutePrecisionEntry(g_dom);
   else { g_reject_reason = "FILTER_LOW_EFF_OR_CHOP"; g_exec_state = STATE_SCANNING; }
}

//+------------------------------------------------------------------+
//| Trade Transaction Listener (Anti-Martingale & Deposit Isolation) |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   ENUM_DEAL_TYPE d_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   // Isolate Deposits/Withdrawals (e.g. +990 USD top-up) from PnL & Profit Floor!
   if(d_type == DEAL_TYPE_BALANCE || d_type == DEAL_TYPE_CREDIT || d_type == DEAL_TYPE_BONUS)
   {
      double amount = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      g_persist.daily_start_balance  += amount;
      g_persist.weekly_start_balance += amount;
      if(amount > 0.0) g_persist.equity_peak += amount;
      SavePersistentState(true);
      g_dash_dirty = true;
      return;
   }

   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

   if(magic != (long)InpMagicNumber || sym != g_validated_symbol || entry != DEAL_ENTRY_OUT) return;

   double net_pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                    HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                    HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   g_persist.total_trades++;
   if(net_pnl > 0.05)
   {
      g_persist.win_trades++;
      g_persist.gross_profit += net_pnl;
      g_persist.consecutive_wins++;
      g_persist.consecutive_losses = 0;

      // ANTI-MARTINGALE PROGRESSION: Scale up risk on winning streaks!
      if(InpEnableAntiMartingale)
      {
         if(g_persist.consecutive_wins >= InpAntiMartingaleMaxStreak)
            g_persist.anti_mart_mult = 1.0; // Bank profits & reset cycle
         else
            g_persist.anti_mart_mult = MathMin(InpAntiMartingaleMaxMult, 1.0 + g_persist.consecutive_wins * InpAntiMartingaleStepMult);
      }
   }
   else if(net_pnl < -0.05)
   {
      g_persist.loss_trades++;
      g_persist.gross_loss += MathAbs(net_pnl);
      g_persist.consecutive_losses++;
      g_persist.consecutive_wins = 0;

      // ANTI-MARTINGALE RESET: Immediately drop back to base/defensive risk on any loss!
      g_persist.anti_mart_mult = (g_persist.consecutive_losses >= 2) ? InpLossDefendMult : 1.0;

      if(g_persist.consecutive_losses >= InpMaxConsecutiveLosses)
         g_persist.cooldown_until = TimeCurrent() + InpLossCooldownMinutes * 60;
   }

   g_last_close_time = TimeCurrent();
   SavePersistentState(true);
   ReconcileBrokerState();
}

void OnTimer()
{
   if(InpShowProfessionalDashboard && g_dash_dirty) { UpdateControlCenter(); g_dash_dirty = false; }
}

double OnTester()
{
   double net_prof = TesterStatistics(STAT_PROFIT);
   double pf       = TesterStatistics(STAT_PROFIT_FACTOR);
   double dd_pct   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades   = TesterStatistics(STAT_TRADES);
   if(trades < 30 || net_prof <= 0.0 || dd_pct > 20.0) return 0.0;
   return (net_prof * MathMin(pf, 4.0)) / MathMax(1.0, dd_pct);
}

//+------------------------------------------------------------------+
//| Interactive Control Center Chart Events (With Lock Reset Fix)    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == DASH_PREFIX + "BTN_ON" || sparam == DASH_PREFIX + "BTN_RESUME")
   {
      // Explicit user activation clears Emergency & Drawdown locks and syncs daily balance
      g_persist.hard_dd_locked = false;
      g_persist.user_control   = CTRL_EA_ON;
      g_persist.cooldown_until = 0;
      g_persist.daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_reject_reason = "NONE";
   }
   else if(sparam == DASH_PREFIX + "BTN_OFF")
   {
      g_persist.user_control = CTRL_EA_OFF;
   }
   else if(sparam == DASH_PREFIX + "BTN_STOP")
   {
      ulong p=0, o=0; bool f=false;
      AuditSymbolExposure(p, o, f);
      g_persist.user_control = (p > 0) ? CTRL_SOFT_STOP_REQUESTED : CTRL_STOPPED;
   }
   else if(sparam == DASH_PREFIX + "BTN_CLOSE")
   {
      ulong p=0, o=0; bool f=false;
      AuditSymbolExposure(p, o, f);
      if(p > 0) EmergencyCloseTicket(p);
      g_persist.user_control = CTRL_STOPPED;
   }
   else if(sparam == DASH_PREFIX + "BTN_EMERG")
   {
      g_persist.user_control = CTRL_EMERGENCY_LOCKED;
      ulong p=0, o=0; bool f=false;
      AuditSymbolExposure(p, o, f);
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
//| Volcanic Theme Control Center UI                                 |
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
   int panel_h = g_dash_minimized ? 40 : 450;
   ObjectCreate(0, DASH_PREFIX + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_YSIZE, panel_h);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_BGCOLOR, C'16,16,20');
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_BORDER_COLOR, C'225,55,20');
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_WIDTH, 2);

   MakeLabel(DASH_PREFIX + "HDR", 20, 25, "VULCARES Vx V3.00  |  ANTI-MARTINGALE ENGINE", C'255,190,35', 9, true);
   MakeButton(DASH_PREFIX + "BTN_MIN", 395, 22, 36, 20, g_dash_minimized ? "+" : "_", C'45,45,55', clrWhite);

   if(g_dash_minimized) { ChartRedraw(0); return; }

   MakeButton(DASH_PREFIX + "BTN_ON",     20,  48, 62, 24, "EA ON",   C'30,140,65',  clrWhite);
   MakeButton(DASH_PREFIX + "BTN_OFF",    86,  48, 62, 24, "EA OFF",  C'90,90,100',  clrWhite);
   MakeButton(DASH_PREFIX + "BTN_STOP",   152, 48, 68, 24, "STOP EA", C'215,115,20', clrWhite);
   MakeButton(DASH_PREFIX + "BTN_RESUME", 224, 48, 66, 24, "RESUME",  C'35,115,185', clrWhite);
   MakeButton(DASH_PREFIX + "BTN_CLOSE",  294, 48, 64, 24, "CLOSE",   C'175,65,25',  clrWhite);
   MakeButton(DASH_PREFIX + "BTN_EMERG",  362, 48, 68, 24, "EMERG",   C'195,20,20',  clrWhite);

   for(int i = 0; i < 20; i++)
   {
      color c = (i % 4 == 0) ? C'255,185,40' : C'210,210,215';
      MakeLabel(StringFormat("%sL%02d", DASH_PREFIX, i), 20, 82 + i * 18, "...", c, 8, (i % 4 == 0));
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
   double net_p= g_persist.gross_profit - g_persist.gross_loss;
   double pf   = (g_persist.gross_loss > 0.0) ? (g_persist.gross_profit / g_persist.gross_loss) : g_persist.gross_profit;
   double wr   = (g_persist.total_trades > 0) ? ((double)g_persist.win_trades / g_persist.total_trades) * 100.0 : 0.0;
   string dir_str = (g_dom.dominant_dir > 0) ? "BUY" : (g_dom.dominant_dir < 0 ? "SELL" : "WAIT");

   string lines[20];
   lines[0]  = StringFormat("[CTRL] %s | EXEC: %s", EnumToString((ENUM_USER_CONTROL)g_persist.user_control), EnumToString(g_exec_state));
   lines[1]  = StringFormat("SYM: %s | STATUS/GATE: %s", g_validated_symbol, g_reject_reason);
   lines[2]  = "------------------------------------------------------------";
   lines[3]  = StringFormat("[ANTI-MARTINGALE] MULT: %.2fx (WIN STREAK: %d | LOSS: %d)", g_persist.anti_mart_mult, g_persist.consecutive_wins, g_persist.consecutive_losses);
   lines[4]  = StringFormat("INIT CAP: %.0f %s | ACTIVE RISK BUDGET: %.2f %s", g_persist.initial_capital, curr, GetCurrentAntiMartingaleRiskBudget(), curr);
   lines[5]  = StringFormat("BAL: %.2f | EQ: %.2f | DAY PNL: %+.2f %s", bal, eq, d_pnl, curr);
   lines[6]  = "------------------------------------------------------------";
   lines[7]  = StringFormat("[STATS] TRADES: %d (W:%d L:%d) | WR: %.1f%% | PF: %.2f", g_persist.total_trades, g_persist.win_trades, g_persist.loss_trades, wr, pf);
   lines[8]  = StringFormat("NET PROFIT: %+.2f %s | EFF RATIO: %.2f", net_p, curr, g_dom.efficiency_ratio);
   lines[9]  = "------------------------------------------------------------";
   lines[10] = StringFormat("[DOMINANCE] BUY %.1f%% vs SELL %.1f%% -> %s", g_dom.buy_dominance_pct, g_dom.sell_dominance_pct, dir_str);
   lines[11] = StringFormat("REGIME: %s (VOL %d) | TOP: %s", EnumToString(g_regime), g_vol_score, g_dom.top_strategy_name);
   lines[12] = "------------------------------------------------------------";

   ulong p_tkt = 0, o_tkt = 0; bool f_pos = false;
   AuditSymbolExposure(p_tkt, o_tkt, f_pos);
   if(p_tkt > 0 && g_pos.SelectByTicket(p_tkt))
   {
      double flt = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      lines[13] = StringFormat("[POSITION] #%I64u %s %.2f LOT @ %.2f", p_tkt, (g_pos.PositionType()==POSITION_TYPE_BUY?"BUY":"SELL"), g_pos.Volume(), g_pos.PriceOpen());
      lines[14] = StringFormat("FLOAT: %+.2f | PEAK: %.2f | SL: %.2f (%d MODS)", flt, g_persist.max_fav_net_profit, g_pos.StopLoss(), g_persist.sl_mod_count);
      lines[15] = StringFormat("TRAIL: %s | LOCK TARGET: %.2f | PROT: %.2f", EnumToString(g_trail_phase), g_target_lock_val, g_protected_val);
   }
   else
   {
      lines[13] = "[POSITION] NONE (SCANNING PRECISION SETUPS)";
      lines[14] = "FLOAT: 0.00 | PEAK: 0.00 | SL: 0.00";
      lines[15] = "TRAIL: STANDBY | LOCK TARGET: 0.00 | PROT: 0.00";
   }
   lines[16] = "------------------------------------------------------------";
   lines[17] = StringFormat("SPREAD: %I64d pts | DEC LAT: %.2f ms | EXEC LAT: %.2f ms", SymbolInfoInteger(g_validated_symbol, SYMBOL_SPREAD), g_decision_latency_ms, g_exec_latency_ms);
   lines[18] = "VULCARES Vx V3.00 — ANTI-MARTINGALE | SINGLE-ENTRY | SERVER SL";
   lines[19] = "TIP: CLICK 'EA ON' TO CLEAR ANY PREVIOUS EMERGENCY LOCK";

   for(int i = 0; i < 20; i++)
      ObjectSetString(0, StringFormat("%sL%02d", DASH_PREFIX, i), OBJPROP_TEXT, lines[i]);
   ChartRedraw(0);
}
