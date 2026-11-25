//+------------------------------------------------------------------+
//|                                                  Vulcares_Vx.mq5 |
//|                                  Copyright 2026, Vulcares Quant  |
//|         EXTREME VOLATILITY ADAPTIVE SINGLE-ENTRY SCALPING ENGINE |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vulcares Quant"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enumerations
enum ENUM_EA_STATE
{
   STATE_INITIALIZING,
   STATE_SCANNING,
   STATE_SIGNAL_READY,
   STATE_ENTRY_PENDING,
   STATE_POSITION_ACTIVE,
   STATE_TRAILING_ACTIVE,
   STATE_EXIT_PENDING,
   STATE_RECONCILIATION,
   STATE_COOLDOWN,
   STATE_RECOVERY,
   STATE_RISK_LOCK,
   STATE_EMERGENCY_STOP,
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
   PHASE_0_INITIAL_PROT,
   PHASE_1_EARLY_PROT,
   PHASE_2_BREAKEVEN,
   PHASE_3_PROGRESSIVE_LOCK,
   PHASE_4_HYPERTIGHT_EXIT,
   PHASE_5_MAX_PRESERVE
};

enum ENUM_ENTRY_MODE
{
   ENTRY_MODE_MARKET,
   ENTRY_MODE_DYNAMIC_STOP
};

//--- Input Parameters (Section 18 Default Configuration)
input group "=== 1. GENERAL & SYMBOL CONFIGURATION ==="
input string   InpEAName                     = "Vulcares Vx";
input ulong    InpMagicNumber                = 20260888;
input bool     InpAllowRealMoneyTrading      = false; // SAFETY LOCK: Must be explicitly enabled
input bool     InpResetInitialCapital        = false; // Explicit user baseline reset

input group "=== 2. FIXED INITIAL CAPITAL RISK ENGINE ==="
input double   InpInitialCapital             = 1000.00; // Baseline Capital (USC)
input double   InpRiskPercent                = 1.00;    // Fixed Risk % of Initial Capital
input double   InpCostSlippageBufferPct      = 20.0;    // Initial reserve % for commission/slippage
input double   InpDailyLossLimitPct          = 5.00;    // 50 USC on 1000 USC
input double   InpWeeklyLossLimitPct         = 8.00;    // 80 USC on 1000 USC
input double   InpMaxInitialDDPct            = 10.00;   // 100 USC Hard Stop
input double   InpMaxPeakDDPct               = 10.00;   // 10% Trailing Equity Peak DD
input int      InpMaxConsecutiveLosses       = 3;
input int      InpLossCooldownMinutes        = 30;
input double   InpDailyProfitFloorTriggerPct = 5.00;    // Activate daily profit floor after +5%
input double   InpDailyProfitRetainPct       = 70.0;    // Retain 70% of daily peak profit

input group "=== 3. VOLATILITY & MICROSTRUCTURE ENGINE ==="
input bool     InpVolatilityFilter           = true;
input bool     InpExtremeVolatilityMode      = true;
input bool     InpToxicVolatilityProtection  = true;
input int      InpMinVolScoreEntry           = 75;      // 75-89 High Vol, 90-100 Extreme Vol
input int      InpATRFastPeriod              = 7;
input int      InpATRMedPeriod               = 14;
input int      InpATRSlowPeriod              = 50;

input group "=== 4. STRATEGY & EXECUTION SETTINGS ==="
input ENUM_ENTRY_MODE InpPreferredEntryMode  = ENTRY_MODE_MARKET;
input double   InpMinConfidence              = 0.72;
input int      InpPendingExpirySec           = 15;
input bool     InpAutoReEntry                = true;
input bool     InpAutoReversalEvaluation     = true;
input int      InpWinReEntryCooldownMs       = 1500;
input int      InpMaxTradeRetries            = 3;
input int      InpTradeRequestIntervalMs     = 150;

input group "=== 5. HYPER-AGGRESSIVE DYNAMIC TRAILING ==="
input bool     InpDynamicTrailingStop        = true;
input bool     InpTickBasedTrailing          = true;
input double   InpTrailingStartR             = 0.25;
input double   InpBreakEvenTriggerR          = 0.60;
input double   InpMaxInitialSL_ATRMult       = 1.80;
input double   InpMinInitialSL_ATRMult       = 0.65;

input group "=== 6. SPREAD, EXECUTION & NEWS PROTECTION ==="
input double   InpMaxSpreadToATRRatio        = 0.20;
input double   InpMaxSpreadToSLRatio         = 0.25;
input int      InpMaxQuoteAgeMs              = 1000;
input double   InpMinMarginLevel             = 500.0;
input double   InpMaxMarginUsagePct          = 20.0;
input bool     InpNewsProtection             = true;
input bool     InpPostNewsMomentumMode       = true;
input int      InpNewsBlockBeforeMin         = 5;
input int      InpNewsBlockAfterMin          = 3;

input group "=== 7. DASHBOARD ==="
input bool     InpShowDashboard              = true;

//--- Tick Ring Buffer Structure
struct TickSample
{
   long     time_msc;
   double   bid;
   double   ask;
   double   mid;
   double   spread;
   int      dir; // +1 up, -1 down, 0 flat
};

//--- Strategy Signal Structure
struct StrategySignal
{
   double   buy_conf;
   double   sell_conf;
   double   sl_dist_price;
   double   momentum_strength;
   double   expected_move;
   string   source_name;
};

//--- Persistent Risk & State Structure
struct PersistentState
{
   double   initial_capital;
   double   equity_peak;
   double   daily_start_balance;
   double   daily_profit_peak;
   double   weekly_start_balance;
   int      day_of_year;
   int      week_of_year;
   int      consecutive_losses;
   datetime cooldown_until;
   bool     emergency_stopped;
   bool     hard_dd_locked;
   ulong    active_ticket;
   double   highest_fav_price;
   double   max_fav_net_profit;
   double   last_confirmed_sl;
};

//--- Global Objects & Variables
CTrade         g_trade;
CSymbolInfo    g_symbol;
CPositionInfo  g_pos;
COrderInfo     g_ord;

ENUM_EA_STATE        g_state          = STATE_INITIALIZING;
ENUM_VOL_REGIME      g_regime         = REGIME_DORMANT;
ENUM_TRAILING_PHASE  g_trail_phase    = PHASE_0_INITIAL_PROT;
PersistentState      g_persist;

// Indicator Handles
int            g_hATR_Fast = INVALID_HANDLE;
int            g_hATR_Med  = INVALID_HANDLE;
int            g_hATR_Slow = INVALID_HANDLE;
int            g_hEMA_M15_F= INVALID_HANDLE;
int            g_hEMA_M15_S= INVALID_HANDLE;
int            g_hEMA_M5_F = INVALID_HANDLE;
int            g_hEMA_M5_S = INVALID_HANDLE;

// Circular Tick Buffer (Capacity 4096 ticks)
#define TICK_BUF_SIZE 4096
TickSample     g_ticks[TICK_BUF_SIZE];
int            g_tick_head  = 0;
int            g_tick_count = 0;

// Runtime Metrics
string         g_validated_symbol   = "";
string         g_gv_prefix          = "";
string         g_reject_reason      = "NONE";
bool           g_user_paused        = false;
bool           g_broker_compatible  = true;
int            g_vol_score          = 0;
double         g_buy_conf           = 0.0;
double         g_sell_conf          = 0.0;
double         g_cur_lot            = 0.0;
double         g_cur_sl             = 0.0;
double         g_exec_latency_ms    = 0.0;
ulong          g_last_trail_mod_ms  = 0;
ulong          g_last_reentry_ms    = 0;
double         g_calibrated_slip_usc= 0.0;

// Dashboard Constants
#define DASH_PREFIX "VCX_DASH_"

//+------------------------------------------------------------------+
//| Validate XAUUSD Symbol Variations (Section 2 & 3)                |
//+------------------------------------------------------------------+
bool ValidateGoldSymbol(const string sym)
{
   string upper = sym;
   StringToUpper(upper);
   
   // Check core gold identifiers
   bool has_gold = (StringFind(upper, "XAUUSD") >= 0 || StringFind(upper, "GOLD") >= 0);
   if(!has_gold) return false;
   
   // Reject non-USD crosses like XAUEUR, XAUGBP, XAUAUD
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
      
   string acc_curr = AccountInfoString(ACCOUNT_CURRENCY);
   if(acc_curr == "") return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Persistent State Management via GlobalVariables (Section 4 & 16) |
//+------------------------------------------------------------------+
void BuildGVPrefix()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string server = AccountInfoString(ACCOUNT_SERVER);
   StringReplace(server, " ", "_");
   g_gv_prefix = StringFormat("VCX_%I64d_%s_%I64u_", login, server, InpMagicNumber);
}

void SavePersistentState()
{
   GlobalVariableSet(g_gv_prefix + "INIT_CAP",   g_persist.initial_capital);
   GlobalVariableSet(g_gv_prefix + "EQ_PEAK",    g_persist.equity_peak);
   GlobalVariableSet(g_gv_prefix + "DAY_BAL",    g_persist.daily_start_balance);
   GlobalVariableSet(g_gv_prefix + "DAY_PEAK",   g_persist.daily_profit_peak);
   GlobalVariableSet(g_gv_prefix + "WK_BAL",     g_persist.weekly_start_balance);
   GlobalVariableSet(g_gv_prefix + "DAY_NUM",    (double)g_persist.day_of_year);
   GlobalVariableSet(g_gv_prefix + "WK_NUM",     (double)g_persist.week_of_year);
   GlobalVariableSet(g_gv_prefix + "CON_LOSS",   (double)g_persist.consecutive_losses);
   GlobalVariableSet(g_gv_prefix + "CD_UNTIL",   (double)g_persist.cooldown_until);
   GlobalVariableSet(g_gv_prefix + "EMERG",      g_persist.emergency_stopped ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "HARD_DD",    g_persist.hard_dd_locked ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "ACT_TKT",    (double)g_persist.active_ticket);
   GlobalVariableSet(g_gv_prefix + "HI_FAV",     g_persist.highest_fav_price);
   GlobalVariableSet(g_gv_prefix + "MAX_PROFIT", g_persist.max_fav_net_profit);
   GlobalVariableSet(g_gv_prefix + "LAST_SL",    g_persist.last_confirmed_sl);
   GlobalVariablesFlush();
}

void LoadPersistentState()
{
   BuildGVPrefix();
   MqlDateTime dt;
   TimeCurrent(dt);
   int cur_day  = dt.day_of_year;
   int cur_week = dt.day_of_year / 7;
   double bal   = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq    = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!GlobalVariableCheck(g_gv_prefix + "INIT_CAP") || InpResetInitialCapital)
   {
      g_persist.initial_capital      = InpInitialCapital;
      g_persist.equity_peak          = MathMax(eq, InpInitialCapital);
      g_persist.daily_start_balance  = bal;
      g_persist.daily_profit_peak    = 0.0;
      g_persist.weekly_start_balance = bal;
      g_persist.day_of_year          = cur_day;
      g_persist.week_of_year         = cur_week;
      g_persist.consecutive_losses   = 0;
      g_persist.cooldown_until       = 0;
      g_persist.emergency_stopped    = false;
      g_persist.hard_dd_locked       = false;
      g_persist.active_ticket        = 0;
      g_persist.highest_fav_price    = 0.0;
      g_persist.max_fav_net_profit   = 0.0;
      g_persist.last_confirmed_sl    = 0.0;
      SavePersistentState();
      return;
   }

   g_persist.initial_capital      = GlobalVariableGet(g_gv_prefix + "INIT_CAP");
   g_persist.equity_peak          = GlobalVariableGet(g_gv_prefix + "EQ_PEAK");
   g_persist.daily_start_balance  = GlobalVariableGet(g_gv_prefix + "DAY_BAL");
   g_persist.daily_profit_peak    = GlobalVariableGet(g_gv_prefix + "DAY_PEAK");
   g_persist.weekly_start_balance = GlobalVariableGet(g_gv_prefix + "WK_BAL");
   g_persist.day_of_year          = (int)GlobalVariableGet(g_gv_prefix + "DAY_NUM");
   g_persist.week_of_year         = (int)GlobalVariableGet(g_gv_prefix + "WK_NUM");
   g_persist.consecutive_losses   = (int)GlobalVariableGet(g_gv_prefix + "CON_LOSS");
   g_persist.cooldown_until       = (datetime)GlobalVariableGet(g_gv_prefix + "CD_UNTIL");
   g_persist.emergency_stopped    = (GlobalVariableGet(g_gv_prefix + "EMERG") > 0.5);
   g_persist.hard_dd_locked       = (GlobalVariableGet(g_gv_prefix + "HARD_DD") > 0.5);
   g_persist.active_ticket        = (ulong)GlobalVariableGet(g_gv_prefix + "ACT_TKT");
   g_persist.highest_fav_price    = GlobalVariableGet(g_gv_prefix + "HI_FAV");
   g_persist.max_fav_net_profit   = GlobalVariableGet(g_gv_prefix + "MAX_PROFIT");
   g_persist.last_confirmed_sl    = GlobalVariableGet(g_gv_prefix + "LAST_SL");
}

//+------------------------------------------------------------------+
//| Helper: Normalize Price to Exact Symbol Tick Size (Section 10)   |
//+------------------------------------------------------------------+
double NormalizeTickPrice(double price)
{
   double tick_size = g_symbol.TickSize();
   if(tick_size <= 0.0) return NormalizeDouble(price, g_symbol.Digits());
   return NormalizeDouble(MathRound(price / tick_size) * tick_size, g_symbol.Digits());
}

//+------------------------------------------------------------------+
//| Helper: Select Appropriate Filling Mode                          |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetOptimalFillingMode(const string sym)
{
   uint filling = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Expert Initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Validate Symbol
   if(!ValidateGoldSymbol(_Symbol))
   {
      Print("CRITICAL [Vulcares Vx]: Invalid symbol ", _Symbol, ". Exclusive to validated XAUUSD/GOLD.");
      g_broker_compatible = false;
      return INIT_FAILED;
   }
   g_validated_symbol = _Symbol;
   g_symbol.Name(g_validated_symbol);
   g_symbol.RefreshRates();

   // 2. Real Money Account Safety Lock (Section 2)
   ENUM_ACCOUNT_TRADE_MODE trade_mode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(trade_mode == ACCOUNT_TRADE_MODE_REAL && !InpAllowRealMoneyTrading && !MQLInfoInteger(MQL_TESTER))
   {
      Print("CRITICAL [Vulcares Vx]: Real account detected while AllowRealMoneyTrading=false. Blocking initialization.");
      Alert("Vulcares Vx: Real Account blocked by safety lock. Set AllowRealMoneyTrading=true after demo validation.");
      return INIT_FAILED;
   }

   // 3. Configure Trade Execution Object
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(30);
   g_trade.SetTypeFilling(GetOptimalFillingMode(g_validated_symbol));
   g_trade.SetAsyncMode(false);

   // 4. Load Persistent Risk State
   LoadPersistentState();

   // 5. Initialize Cached Indicator Handles (Section 15)
   g_hATR_Fast  = iATR(g_validated_symbol, PERIOD_M1, InpATRFastPeriod);
   g_hATR_Med   = iATR(g_validated_symbol, PERIOD_M1, InpATRMedPeriod);
   g_hATR_Slow  = iATR(g_validated_symbol, PERIOD_M1, InpATRSlowPeriod);
   g_hEMA_M15_F = iMA(g_validated_symbol, PERIOD_M15, 8, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_M15_S = iMA(g_validated_symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_M5_F  = iMA(g_validated_symbol, PERIOD_M5, 5, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_M5_S  = iMA(g_validated_symbol, PERIOD_M5, 13, 0, MODE_EMA, PRICE_CLOSE);

   if(g_hATR_Fast == INVALID_HANDLE || g_hATR_Med == INVALID_HANDLE || g_hATR_Slow == INVALID_HANDLE ||
      g_hEMA_M15_F == INVALID_HANDLE || g_hEMA_M15_S == INVALID_HANDLE ||
      g_hEMA_M5_F == INVALID_HANDLE || g_hEMA_M5_S == INVALID_HANDLE)
   {
      Print("CRITICAL [Vulcares Vx]: Failed to initialize indicator handles.");
      return INIT_FAILED;
   }

   // 6. Broker Reconciliation on Startup (Section 16)
   ReconcileBrokerState();

   // 7. Create Dashboard & Start Millisecond Timer
   if(InpShowDashboard)
      CreateDashboard();

   EventSetMillisecondTimer(250);
   PrintFormat("[Vulcares Vx] Initialized on %s | Currency: %s | InitialCap: %.2f | FixedRisk: %.2f",
               g_validated_symbol, AccountInfoString(ACCOUNT_CURRENCY),
               g_persist.initial_capital, GetFixedRiskBudget());
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   SavePersistentState();
   
   IndicatorRelease(g_hATR_Fast);
   IndicatorRelease(g_hATR_Med);
   IndicatorRelease(g_hATR_Slow);
   IndicatorRelease(g_hEMA_M15_F);
   IndicatorRelease(g_hEMA_M15_S);
   IndicatorRelease(g_hEMA_M5_F);
   IndicatorRelease(g_hEMA_M5_S);

   ObjectsDeleteAll(0, DASH_PREFIX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Fixed Initial Capital Risk Budget (Section 4)                    |
//+------------------------------------------------------------------+
double GetFixedRiskBudget()
{
   // Strictly based on InitialCapital (e.g., 1000 USC * 1.0% = 10.00 USC), never compounds upward
   return (g_persist.initial_capital * InpRiskPercent) / 100.0;
}

//+------------------------------------------------------------------+
//| Exact Risk & Dynamic Lot Sizing via OrderCalcProfit() (Section 4)|
//+------------------------------------------------------------------+
double CalculateValidatedLot(ENUM_ORDER_TYPE order_type, double entry_price, double sl_price, double &est_total_risk)
{
   double risk_budget = GetFixedRiskBudget();
   double vol_min     = g_symbol.LotsMin();
   double vol_max     = g_symbol.LotsMax();
   double vol_step    = g_symbol.LotsStep();

   // Estimate commission & slippage reserve
   double reserve_factor = 1.0 + (InpCostSlippageBufferPct / 100.0);
   double target_sl_risk = (risk_budget - g_calibrated_slip_usc) / reserve_factor;
   if(target_sl_risk <= 0.0) return 0.0;

   // Compute loss for 1.0 lot using native OrderCalcProfit() in actual account currency
   double profit_1lot = 0.0;
   if(!OrderCalcProfit(order_type, g_validated_symbol, 1.0, entry_price, sl_price, profit_1lot))
      return 0.0;

   double loss_1lot = MathAbs(profit_1lot);
   if(loss_1lot <= 0.0 || profit_1lot >= 0.0) return 0.0; // Invalid SL direction

   double raw_lot = target_sl_risk / loss_1lot;
   double stepped_lot = MathFloor(raw_lot / vol_step) * vol_step;
   stepped_lot = NormalizeDouble(stepped_lot, 2);

   // Section 2 & 4: Never exceed risk budget due to broker minimum lot
   if(stepped_lot < vol_min)
   {
      g_reject_reason = "MIN_LOT_EXCEEDS_RISK";
      return 0.0;
   }
   if(stepped_lot > vol_max) stepped_lot = vol_max;

   // Final verification of exact risk at stepped_lot
   double actual_sl_profit = 0.0;
   if(!OrderCalcProfit(order_type, g_validated_symbol, stepped_lot, entry_price, sl_price, actual_sl_profit))
      return 0.0;

   est_total_risk = MathAbs(actual_sl_profit) * reserve_factor + g_calibrated_slip_usc;
   if(est_total_risk > risk_budget)
   {
      stepped_lot = NormalizeDouble(stepped_lot - vol_step, 2);
      if(stepped_lot < vol_min)
      {
         g_reject_reason = "RISK_BUDGET_CAP";
         return 0.0;
      }
      OrderCalcProfit(order_type, g_validated_symbol, stepped_lot, entry_price, sl_price, actual_sl_profit);
      est_total_risk = MathAbs(actual_sl_profit) * reserve_factor + g_calibrated_slip_usc;
   }

   // Margin Check (Section 12)
   double margin_req = 0.0;
   if(!OrderCalcMargin(order_type, g_validated_symbol, stepped_lot, entry_price, margin_req))
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(margin_req > equity * (InpMaxMarginUsagePct / 100.0))
   {
      g_reject_reason = "MARGIN_USAGE_LIMIT";
      return 0.0;
   }

   return stepped_lot;
}

//+------------------------------------------------------------------+
//| Circular Tick Buffer Recorder (Section 6)                        |
//+------------------------------------------------------------------+
void RecordTick(const MqlTick &tick)
{
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

//+------------------------------------------------------------------+
//| Rolling Microstructure Window Query (250ms - 30s) (Section 6)    |
//+------------------------------------------------------------------+
void AnalyzeTickWindow(long window_ms, int &tick_cnt, double &net_move, double &path_len, double &max_spread, int &dir_imbalance)
{
   tick_cnt = 0;
   net_move = 0.0;
   path_len = 0.0;
   max_spread = 0.0;
   dir_imbalance = 0;
   if(g_tick_count < 2) return;

   int newest_idx = (g_tick_head - 1 + TICK_BUF_SIZE) % TICK_BUF_SIZE;
   long now_msc   = g_ticks[newest_idx].time_msc;
   double end_mid = g_ticks[newest_idx].mid;
   double start_mid = end_mid;
   double prev_mid  = end_mid;

   for(int i = 0; i < g_tick_count; i++)
   {
      int idx = (newest_idx - i + TICK_BUF_SIZE) % TICK_BUF_SIZE;
      if(now_msc - g_ticks[idx].time_msc > window_ms) break;

      tick_cnt++;
      start_mid = g_ticks[idx].mid;
      if(i > 0) path_len += MathAbs(prev_mid - g_ticks[idx].mid);
      if(g_ticks[idx].spread > max_spread) max_spread = g_ticks[idx].spread;
      dir_imbalance += g_ticks[idx].dir;
      prev_mid = g_ticks[idx].mid;
   }
   net_move = end_mid - start_mid;
}

//+------------------------------------------------------------------+
//| Extreme Volatility & Market Regime Engine (Section 5)            |
//+------------------------------------------------------------------+
void UpdateVolatilityIntelligence()
{
   double atr_f[2], atr_m[2], atr_s[2];
   if(CopyBuffer(g_hATR_Fast, 0, 0, 2, atr_f) < 2 ||
      CopyBuffer(g_hATR_Med,  0, 0, 2, atr_m) < 2 ||
      CopyBuffer(g_hATR_Slow, 0, 0, 2, atr_s) < 2)
   {
      g_vol_score = 0;
      g_regime = REGIME_DORMANT;
      return;
   }

   double cur_spread = g_symbol.Ask() - g_symbol.Bid();
   double spread_to_atr = (atr_m[0] > 0.0) ? (cur_spread / atr_m[0]) : 1.0;

   // Rolling tick metrics across 1s and 5s windows
   int cnt_1s = 0, imb_1s = 0, cnt_5s = 0, imb_5s = 0;
   double net_1s = 0, path_1s = 0, max_sp_1s = 0;
   double net_5s = 0, path_5s = 0, max_sp_5s = 0;
   AnalyzeTickWindow(1000, cnt_1s, net_1s, path_1s, max_sp_1s, imb_1s);
   AnalyzeTickWindow(5000, cnt_5s, net_5s, path_5s, max_sp_5s, imb_5s);

   // Toxic Volatility Check (Section 5 & 12)
   long quote_age_ms = (long)(TimeCurrent() * 1000) - (long)g_symbol.TimeMsc();
   if(InpToxicVolatilityProtection)
   {
      if(spread_to_atr > InpMaxSpreadToATRRatio || (max_sp_1s > cur_spread * 3.0 && cur_spread > 0))
      {
         g_regime = REGIME_TOXIC_VOL;
         g_vol_score = 99;
         g_reject_reason = "TOXIC_SPREAD_SPIKE";
         return;
      }
   }

   // Score Components (0 - 100)
   double atr_expansion = (atr_s[0] > 0.0) ? MathMin(2.5, atr_f[0] / atr_s[0]) : 1.0;
   double score_atr     = ((atr_expansion - 0.7) / 1.8) * 35.0; // Max 35 pts

   double tick_velocity = MathMin(25.0, (double)cnt_1s * 2.5);   // Max 25 pts (10+ ticks/sec)
   double eff_ratio_5s  = (path_5s > 0.0) ? MathAbs(net_5s) / path_5s : 0.0;
   double score_eff     = eff_ratio_5s * 25.0;                   // Max 25 pts

   double range_m1      = iHigh(g_validated_symbol, PERIOD_M1, 0) - iLow(g_validated_symbol, PERIOD_M1, 0);
   double score_range   = (atr_m[0] > 0.0) ? MathMin(15.0, (range_m1 / atr_m[0]) * 10.0) : 0.0;

   int raw_score = (int)MathRound(MathMax(0.0, MathMin(100.0, score_atr + tick_velocity + score_eff + score_range)));
   g_vol_score = raw_score;

   if(g_vol_score < 40)       g_regime = REGIME_DORMANT;
   else if(g_vol_score < 60)  g_regime = REGIME_LOW_VOL;
   else if(g_vol_score < 75)  g_regime = REGIME_NORMAL;
   else if(g_vol_score < 90)  g_regime = REGIME_HIGH_VOL;
   else if(eff_ratio_5s > 0.65) g_regime = REGIME_EXPLOSIVE_MOM;
   else                       g_regime = REGIME_EXTREME_VOL;
}

//+------------------------------------------------------------------+
//| Economic Calendar & News Volatility Engine (Section 13)          |
//+------------------------------------------------------------------+
bool IsHighImpactNewsWindow(bool &is_post_news)
{
   is_post_news = false;
   if(!InpNewsProtection) return false;

   MqlCalendarValue values[];
   datetime now = TimeCurrent();
   datetime from = now - InpNewsBlockAfterMin * 60;
   datetime to   = now + InpNewsBlockBeforeMin * 60;

   // Query USD macro events (NFP, CPI, FOMC, PPI, PCE, GDP, Claims)
   if(CalendarValueHistory(values, from, to, "USD") > 0)
   {
      for(int i = 0; i < ArraySize(values); i++)
      {
         MqlCalendarEvent ev;
         if(CalendarEventById(values[i].event_id, ev))
         {
            if(ev.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               if(values[i].time >= now - 60) // Active release window
                  return true;
               else if(InpPostNewsMomentumMode)
                  is_post_news = true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Multi-Timeframe & Strategy Ensemble Engine (Section 6 & 7)       |
//+------------------------------------------------------------------+
StrategySignal EvaluateAdaptiveEnsemble()
{
   StrategySignal sig;
   sig.buy_conf = 0.0;
   sig.sell_conf = 0.0;
   sig.sl_dist_price = 0.0;
   sig.momentum_strength = 0.0;
   sig.expected_move = 0.0;
   sig.source_name = "NONE";

   double ema15_f[2], ema15_s[2], ema5_f[2], ema5_s[2], atr_m[2];
   if(CopyBuffer(g_hEMA_M15_F, 0, 0, 2, ema15_f) < 2 || CopyBuffer(g_hEMA_M15_S, 0, 0, 2, ema15_s) < 2 ||
      CopyBuffer(g_hEMA_M5_F,  0, 0, 2, ema5_f)  < 2 || CopyBuffer(g_hEMA_M5_S,  0, 0, 2, ema5_s)  < 2 ||
      CopyBuffer(g_hATR_Med,   0, 0, 2, atr_m)   < 2)
      return sig;

   // Layer 1: M15 Macro Trend
   int m15_bias = (ema15_f[0] > ema15_s[0]) ? 1 : -1;

   // Layer 2: M5 Dominant Breakout Direction
   int m5_bias  = (ema5_f[0] > ema5_s[0]) ? 1 : -1;
   double m5_hi = iHigh(g_validated_symbol, PERIOD_M5, 1);
   double m5_lo = iLow(g_validated_symbol, PERIOD_M5, 1);

   // Layer 3: M1 Setup & Structure
   double bid = g_symbol.Bid();
   double ask = g_symbol.Ask();
   double m1_open = iOpen(g_validated_symbol, PERIOD_M1, 0);

   // Layer 4: Tick Velocity & Acceleration (250ms, 1s, 5s)
   int c250 = 0, imb250 = 0, c1s = 0, imb1s = 0, c5s = 0, imb5s = 0;
   double net250 = 0, p250 = 0, sp250 = 0;
   double net1s  = 0, p1s  = 0, sp1s  = 0;
   double net5s  = 0, p5s  = 0, sp5s  = 0;
   AnalyzeTickWindow(250,  c250, net250, p250, sp250, imb250);
   AnalyzeTickWindow(1000, c1s,  net1s,  p1s,  sp1s,  imb1s);
   AnalyzeTickWindow(5000, c5s,  net5s,  p5s,  sp5s,  imb5s);

   double velocity_1s = MathAbs(net1s);
   double velocity_250= MathAbs(net250) * 4.0;
   bool accelerating  = (velocity_250 > velocity_1s * 1.15) && (net250 * net1s > 0);

   // Strategy 1: Extreme Volatility Breakout + Tick Ignition
   double buy_score = 0.0, sell_score = 0.0;
   if(net1s > 0 && imb1s >= 3 && bid > m1_open)
   {
      buy_score += 0.35;
      if(accelerating) buy_score += 0.20;
      if(bid > m5_hi)  { buy_score += 0.20; sig.source_name = "VOL_BREAKOUT_IGNITION"; }
      if(m5_bias == 1) buy_score += 0.15;
      if(m15_bias == 1) buy_score += 0.10;
   }
   if(net1s < 0 && imb1s <= -3 && ask < m1_open)
   {
      sell_score += 0.35;
      if(accelerating) sell_score += 0.20;
      if(ask < m5_lo)  { sell_score += 0.20; sig.source_name = "VOL_BREAKOUT_IGNITION"; }
      if(m5_bias == -1) sell_score += 0.15;
      if(m15_bias == -1) sell_score += 0.10;
   }

   // Strategy 2: Liquidity Sweep / Exhaustion Reversal
   double m1_hi1 = iHigh(g_validated_symbol, PERIOD_M1, 1);
   double m1_lo1 = iLow(g_validated_symbol, PERIOD_M1, 1);
   double m1_cl1 = iClose(g_validated_symbol, PERIOD_M1, 1);
   if(m1_lo1 < m5_lo && m1_cl1 > m5_lo && net1s > 0 && imb1s >= 2)
   {
      buy_score = MathMax(buy_score, 0.78);
      sig.source_name = "LIQUIDITY_SWEEP_REV";
   }
   if(m1_hi1 > m5_hi && m1_cl1 < m5_hi && net1s < 0 && imb1s <= -2)
   {
      sell_score = MathMax(sell_score, 0.78);
      sig.source_name = "LIQUIDITY_SWEEP_REV";
   }

   sig.buy_conf  = MathMin(1.0, buy_score);
   sig.sell_conf = MathMin(1.0, sell_score);

   // Structural Stop Loss Distance bounded by ATR
   double raw_sl = atr_m[0] * 1.15;
   sig.sl_dist_price = MathMax(atr_m[0] * InpMinInitialSL_ATRMult, MathMin(atr_m[0] * InpMaxInitialSL_ATRMult, raw_sl));
   sig.expected_move = atr_m[0] * 2.2;
   sig.momentum_strength = velocity_1s;

   return sig;
}

//+------------------------------------------------------------------+
//| Capital Survival & Risk Guardrails (Section 14)                  |
//+------------------------------------------------------------------+
bool CheckCapitalSurvival()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   // Daily & Weekly Rollover
   if(dt.day_of_year != g_persist.day_of_year)
   {
      g_persist.day_of_year = dt.day_of_year;
      g_persist.daily_start_balance = bal;
      g_persist.daily_profit_peak = 0.0;
      SavePersistentState();
   }
   int cur_wk = dt.day_of_year / 7;
   if(cur_wk != g_persist.week_of_year)
   {
      g_persist.week_of_year = cur_wk;
      g_persist.weekly_start_balance = bal;
      SavePersistentState();
   }

   if(eq > g_persist.equity_peak)
   {
      g_persist.equity_peak = eq;
   }

   // 1. Initial Capital Hard Drawdown Check (e.g., 100 USC loss from 1000 USC)
   double max_init_dd = g_persist.initial_capital * (InpMaxInitialDDPct / 100.0);
   if((g_persist.initial_capital - eq) >= max_init_dd || g_persist.hard_dd_locked)
   {
      g_persist.hard_dd_locked = true;
      g_state = STATE_RISK_LOCK;
      g_reject_reason = "HARD_INITIAL_DD_LOCK";
      SavePersistentState();
      return false;
   }

   // 2. Equity Peak Drawdown Check
   double peak_dd_pct = (g_persist.equity_peak > 0.0) ? ((g_persist.equity_peak - eq) / g_persist.equity_peak) * 100.0 : 0.0;
   if(peak_dd_pct >= InpMaxPeakDDPct)
   {
      g_persist.hard_dd_locked = true;
      g_state = STATE_RISK_LOCK;
      g_reject_reason = "PEAK_DD_LOCK";
      SavePersistentState();
      return false;
   }

   // 3. Daily Net Loss Limit (includes floating)
   double daily_pnl = eq - g_persist.daily_start_balance;
   double max_daily_loss = g_persist.initial_capital * (InpDailyLossLimitPct / 100.0);
   if(daily_pnl <= -max_daily_loss)
   {
      g_reject_reason = "DAILY_LOSS_LIMIT";
      return false;
   }

   // 4. Daily Profit Floor Protection
   if(daily_pnl > g_persist.daily_profit_peak)
      g_persist.daily_profit_peak = daily_pnl;
   double floor_trigger = g_persist.initial_capital * (InpDailyProfitFloorTriggerPct / 100.0);
   if(g_persist.daily_profit_peak >= floor_trigger)
   {
      double min_retained = g_persist.daily_profit_peak * (InpDailyProfitRetainPct / 100.0);
      if(daily_pnl <= min_retained)
      {
         g_reject_reason = "DAILY_PROFIT_FLOOR_HIT";
         return false;
      }
   }

   // 5. Weekly Net Loss Limit
   double weekly_pnl = eq - g_persist.weekly_start_balance;
   double max_weekly_loss = g_persist.initial_capital * (InpWeeklyLossLimitPct / 100.0);
   if(weekly_pnl <= -max_weekly_loss)
   {
      g_reject_reason = "WEEKLY_LOSS_LIMIT";
      return false;
   }

   // 6. Consecutive Losses Cooldown
   if(TimeCurrent() < g_persist.cooldown_until)
   {
      g_reject_reason = "LOSS_COOLDOWN_ACTIVE";
      return false;
   }

   // 7. Margin Level Check
   double margin_lvl = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(margin_lvl > 0.0 && margin_lvl < InpMinMarginLevel)
   {
      g_reject_reason = "LOW_MARGIN_LEVEL";
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Count Active Positions & Pending Orders for Magic Number         |
//+------------------------------------------------------------------+
int CountEAOrdersAndPositions(ulong &pos_ticket, ulong &ord_ticket)
{
   pos_ticket = 0;
   ord_ticket = 0;
   int total_count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i))
      {
         if(g_pos.Symbol() == g_validated_symbol && g_pos.Magic() == InpMagicNumber)
         {
            pos_ticket = g_pos.Ticket();
            total_count++;
         }
      }
   }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(g_ord.SelectByIndex(i))
      {
         if(g_ord.Symbol() == g_validated_symbol && g_ord.Magic() == InpMagicNumber)
         {
            ord_ticket = g_ord.Ticket();
            total_count++;
         }
      }
   }
   return total_count;
}

//+------------------------------------------------------------------+
//| Broker State Reconciliation (Section 15 & 16)                    |
//+------------------------------------------------------------------+
void ReconcileBrokerState()
{
   ulong pos_tkt = 0, ord_tkt = 0;
   CountEAOrdersAndPositions(pos_tkt, ord_tkt);

   if(g_persist.emergency_stopped)
   {
      g_state = STATE_EMERGENCY_STOP;
      return;
   }
   if(g_persist.hard_dd_locked)
   {
      g_state = STATE_RISK_LOCK;
      return;
   }

   if(pos_tkt > 0)
   {
      if(g_pos.SelectByTicket(pos_tkt))
      {
         g_persist.active_ticket = pos_tkt;
         g_cur_lot = g_pos.Volume();
         g_cur_sl  = g_pos.StopLoss();

         // Verify Server-Side SL exists (Phase 0 Emergency Check - Section 9)
         if(g_cur_sl <= 0.0)
         {
            Print("CRITICAL [Vulcares Vx]: Position ", pos_tkt, " has NO server-side SL! Executing Emergency Close.");
            EmergencyClosePosition(pos_tkt);
            return;
         }
         if(g_persist.last_confirmed_sl <= 0.0)
            g_persist.last_confirmed_sl = g_cur_sl;

         g_state = STATE_TRAILING_ACTIVE;
      }
   }
   else if(ord_tkt > 0)
   {
      g_state = STATE_ENTRY_PENDING;
   }
   else
   {
      g_persist.active_ticket      = 0;
      g_persist.highest_fav_price  = 0.0;
      g_persist.max_fav_net_profit = 0.0;
      g_persist.last_confirmed_sl  = 0.0;
      g_cur_lot = 0.0;
      g_cur_sl  = 0.0;
      g_trail_phase = PHASE_0_INITIAL_PROT;
      g_state = STATE_SCANNING;
   }
   SavePersistentState();
}

//+------------------------------------------------------------------+
//| Emergency Close Single EA Position with Retry (Section 9 & 17)   |
//+------------------------------------------------------------------+
void EmergencyClosePosition(ulong ticket)
{
   for(int attempt = 1; attempt <= InpMaxTradeRetries; attempt++)
   {
      if(!g_pos.SelectByTicket(ticket)) break;
      if(g_trade.PositionClose(ticket))
      {
         if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            g_state = STATE_RECONCILIATION;
            return;
         }
      }
      Sleep(50);
   }
   g_state = STATE_RECOVERY;
}

//+------------------------------------------------------------------+
//| Single-Entry Execution Engine (Section 8)                        |
//+------------------------------------------------------------------+
void ExecuteSingleEntry(const StrategySignal &sig)
{
   // Strict Single Position & Single Pending Order Enforcement (Section 2)
   ulong existing_pos = 0, existing_ord = 0;
   if(CountEAOrdersAndPositions(existing_pos, existing_ord) > 0)
   {
      g_reject_reason = "SINGLE_POSITION_LOCK";
      return;
   }

   bool is_buy = (sig.buy_conf >= sig.sell_conf);
   double ask = g_symbol.Ask();
   double bid = g_symbol.Bid();
   double spread = ask - bid;

   // Spread vs SL Filter (Section 12)
   if(sig.sl_dist_price <= 0.0 || (spread / sig.sl_dist_price) > InpMaxSpreadToSLRatio)
   {
      g_reject_reason = "SPREAD_TO_SL_HIGH";
      return;
   }

   // Respect Broker Stop Level
   double stop_level_price = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double min_sl_dist = MathMax(sig.sl_dist_price, stop_level_price + spread * 1.5);

   ENUM_ORDER_TYPE ord_type = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry_est = is_buy ? ask : bid;
   double sl_price  = is_buy ? NormalizeTickPrice(entry_est - min_sl_dist)
                             : NormalizeTickPrice(entry_est + min_sl_dist);

   double est_risk = 0.0;
   double lot = CalculateValidatedLot(ord_type, entry_est, sl_price, est_risk);
   if(lot <= 0.0) return;

   ulong t_start = GetMicrosecondCount();
   bool sent = false;

   if(InpPreferredEntryMode == ENTRY_MODE_MARKET)
   {
      sent = is_buy ? g_trade.Buy(lot, g_validated_symbol, ask, sl_price, 0.0, "VCX_MKT_" + sig.source_name)
                    : g_trade.Sell(lot, g_validated_symbol, bid, sl_price, 0.0, "VCX_MKT_" + sig.source_name);
   }
   else
   {
      double stop_offset = MathMax(stop_level_price + g_symbol.TickSize() * 2.0, spread * 0.5);
      double pend_price  = is_buy ? NormalizeTickPrice(ask + stop_offset) : NormalizeTickPrice(bid - stop_offset);
      double pend_sl     = is_buy ? NormalizeTickPrice(pend_price - min_sl_dist) : NormalizeTickPrice(pend_price + min_sl_dist);
      datetime exp_time  = TimeCurrent() + InpPendingExpirySec;

      sent = is_buy ? g_trade.BuyStop(lot, pend_price, g_validated_symbol, pend_sl, 0.0, ORDER_TIME_SPECIFIED, exp_time, "VCX_STP")
                    : g_trade.SellStop(lot, pend_price, g_validated_symbol, pend_sl, 0.0, ORDER_TIME_SPECIFIED, exp_time, "VCX_STP");
   }

   g_exec_latency_ms = (double)(GetMicrosecondCount() - t_start) / 1000.0;

   uint ret = g_trade.ResultRetcode();
   if(sent && (ret == TRADE_RETCODE_DONE || ret == TRADE_RETCODE_PLACED))
   {
      g_reject_reason = "NONE";
      g_persist.highest_fav_price  = entry_est;
      g_persist.max_fav_net_profit = 0.0;
      g_persist.last_confirmed_sl  = sl_price;
      g_trail_phase = PHASE_0_INITIAL_PROT;
      g_state = (ret == TRADE_RETCODE_DONE) ? STATE_POSITION_ACTIVE : STATE_ENTRY_PENDING;
      SavePersistentState();
   }
   else
   {
      g_reject_reason = StringFormat("EXEC_ERR_%u", ret);
      g_state = STATE_RECONCILIATION;
   }
}

//+------------------------------------------------------------------+
//| Hyper-Aggressive 5-Phase Dynamic Trailing Stop Engine (Sec 9-10) |
//+------------------------------------------------------------------+
void ManageHyperDynamicTrailing()
{
   ulong pos_tkt = 0, ord_tkt = 0;
   CountEAOrdersAndPositions(pos_tkt, ord_tkt);
   if(pos_tkt == 0 || !g_pos.SelectByTicket(pos_tkt))
   {
      g_state = STATE_RECONCILIATION;
      return;
   }

   if(!InpDynamicTrailingStop) return;

   // Throttle modification requests (Section 10)
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_trail_mod_ms < (ulong)InpTradeRequestIntervalMs) return;

   bool is_buy       = (g_pos.PositionType() == POSITION_TYPE_BUY);
   double open_price = g_pos.PriceOpen();
   double cur_sl     = g_pos.StopLoss();
   double eval_price = is_buy ? g_symbol.Bid() : g_symbol.Ask();
   double spread     = g_symbol.Ask() - g_symbol.Bid();
   double lot        = g_pos.Volume();

   // Track Peak Favorable Price
   if(g_persist.highest_fav_price <= 0.0) g_persist.highest_fav_price = open_price;
   if(is_buy && eval_price > g_persist.highest_fav_price)
      g_persist.highest_fav_price = eval_price;
   else if(!is_buy && eval_price < g_persist.highest_fav_price)
      g_persist.highest_fav_price = eval_price;

   // Calculate Net Floating Profit & Peak Net Profit in R multiples
   double net_float_profit = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
   double risk_budget_r    = GetFixedRiskBudget();
   double current_r        = (risk_budget_r > 0.0) ? (net_float_profit / risk_budget_r) : 0.0;

   if(net_float_profit > g_persist.max_fav_net_profit)
      g_persist.max_fav_net_profit = net_float_profit;

   double peak_r = (risk_budget_r > 0.0) ? (g_persist.max_fav_net_profit / risk_budget_r) : 0.0;

   // Check Reversal / Momentum Exhaustion (Phase 4 Hyper-Tight Exit)
   int c1s = 0, imb1s = 0;
   double net1s = 0, p1s = 0, sp1s = 0;
   AnalyzeTickWindow(1000, c1s, net1s, p1s, sp1s, imb1s);
   bool momentum_reversing = is_buy ? (net1s < -spread * 1.5 && imb1s <= -4)
                                    : (net1s >  spread * 1.5 && imb1s >=  4);

   // Immediate Market Exit on Violent Reversal if in solid profit (>= 1.2R)
   if(peak_r >= 1.20 && momentum_reversing && current_r >= 0.70)
   {
      g_trail_phase = PHASE_4_HYPERTIGHT_EXIT;
      if(g_trade.PositionClose(pos_tkt))
      {
         g_last_reentry_ms = GetTickCount64();
         g_state = STATE_RECONCILIATION;
         return;
      }
   }

   // Determine Progressive Profit Lock Target (Section 9 Table)
   double lock_pct = 0.0;
   if(peak_r >= 10.0)     { lock_pct = 0.90; g_trail_phase = PHASE_5_MAX_PRESERVE; }
   else if(peak_r >= 5.0) { lock_pct = 0.85; g_trail_phase = PHASE_3_PROGRESSIVE_LOCK; }
   else if(peak_r >= 3.0) { lock_pct = 0.75; g_trail_phase = PHASE_3_PROGRESSIVE_LOCK; }
   else if(peak_r >= 2.0) { lock_pct = 0.65; g_trail_phase = PHASE_3_PROGRESSIVE_LOCK; }
   else if(peak_r >= 1.5) { lock_pct = 0.50; g_trail_phase = PHASE_3_PROGRESSIVE_LOCK; }
   else if(peak_r >= 1.0) { lock_pct = 0.35; g_trail_phase = PHASE_3_PROGRESSIVE_LOCK; }
   else if(peak_r >= InpBreakEvenTriggerR) { g_trail_phase = PHASE_2_BREAKEVEN; }
   else if(peak_r >= InpTrailingStartR)    { g_trail_phase = PHASE_1_EARLY_PROT; }
   else return;

   double atr_f[1];
   double atr_val = (CopyBuffer(g_hATR_Fast, 0, 0, 1, atr_f) > 0) ? atr_f[0] : spread * 4.0;
   double stop_level_dist = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double freeze_dist     = (double)g_symbol.FreezeLevel() * g_symbol.Point();

   // Check Freeze Level
   if(freeze_dist > 0.0 && MathAbs(eval_price - cur_sl) <= freeze_dist) return;

   // Compute Adaptive Trailing Distance (Section 10)
   double mult = momentum_reversing ? 0.35 : (peak_r >= 2.0 ? 0.55 : 0.85);
   double trail_dist = MathMax(stop_level_dist + g_symbol.TickSize() * 2.0,
                       MathMax(spread * 1.4, atr_val * mult));

   double candidate_sl = is_buy ? (eval_price - trail_dist) : (eval_price + trail_dist);

   // Enforce Progressive Profit Lock Floor
   double max_price_excursion = MathAbs(g_persist.highest_fav_price - open_price);
   if(lock_pct > 0.0 && max_price_excursion > 0.0)
   {
      double locked_price_move = max_price_excursion * lock_pct;
      double lock_floor_sl = is_buy ? (open_price + locked_price_move) : (open_price - locked_price_move);
      candidate_sl = is_buy ? MathMax(candidate_sl, lock_floor_sl) : MathMin(candidate_sl, lock_floor_sl);
   }
   else if(g_trail_phase == PHASE_2_BREAKEVEN)
   {
      // Cost-adjusted break-even buffer
      double be_buffer = spread * 0.5 + g_symbol.TickSize() * 3.0;
      double be_sl = is_buy ? (open_price + be_buffer) : (open_price - be_buffer);
      candidate_sl = is_buy ? MathMax(candidate_sl, be_sl) : MathMin(candidate_sl, be_sl);
   }

   // Respect Broker Legal Distance from Current Market Price
   double max_legal_sl = is_buy ? (eval_price - stop_level_dist - g_symbol.TickSize())
                                : (eval_price + stop_level_dist + g_symbol.TickSize());
   candidate_sl = is_buy ? MathMin(candidate_sl, max_legal_sl) : MathMax(candidate_sl, max_legal_sl);
   candidate_sl = NormalizeTickPrice(candidate_sl);

   // Ratchet Monotonically: SL NEVER moves backward (Section 2 & 10)
   double confirmed_floor = (g_persist.last_confirmed_sl > 0.0) ? g_persist.last_confirmed_sl : cur_sl;
   double new_sl = is_buy ? MathMax(confirmed_floor, candidate_sl)
                          : MathMin(confirmed_floor, candidate_sl);

   double min_step = g_symbol.TickSize() * 2.0;
   bool improved = is_buy ? (new_sl >= cur_sl + min_step) : (new_sl <= cur_sl - min_step);

   if(improved)
   {
      if(g_trade.PositionModify(pos_tkt, new_sl, 0.0))
      {
         if(g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            g_persist.last_confirmed_sl = new_sl;
            g_cur_sl = new_sl;
            g_last_trail_mod_ms = now_ms;
            SavePersistentState();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Main Tick Handler (Low-Latency Event Loop)                       |
//+------------------------------------------------------------------+
void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(g_validated_symbol, tick)) return;
   g_symbol.RefreshRates();
   RecordTick(tick);

   // Connection & State Guards
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      g_state = STATE_DISCONNECTED;
      return;
   }
   if(g_persist.emergency_stopped)
   {
      g_state = STATE_EMERGENCY_STOP;
      return;
   }

   // Active Position Management takes highest priority
   ulong pos_tkt = 0, ord_tkt = 0;
   int active_cnt = CountEAOrdersAndPositions(pos_tkt, ord_tkt);
   if(pos_tkt > 0)
   {
      g_state = STATE_TRAILING_ACTIVE;
      ManageHyperDynamicTrailing();
      return;
   }
   if(ord_tkt > 0)
   {
      g_state = STATE_ENTRY_PENDING;
      return;
   }

   // Capital Survival Check
   if(!CheckCapitalSurvival()) return;

   if(g_user_paused)
   {
      g_reject_reason = "USER_PAUSED";
      return;
   }

   // Rapid Re-Entry Cooldown after Profitable Close
   if(GetTickCount64() - g_last_reentry_ms < (ulong)InpWinReEntryCooldownMs)
   {
      g_reject_reason = "REENTRY_COOLDOWN";
      return;
   }

   // Volatility & Regime Classification
   UpdateVolatilityIntelligence();
   if(g_regime == REGIME_TOXIC_VOL) return;
   if(InpVolatilityFilter && g_vol_score < InpMinVolScoreEntry)
   {
      g_reject_reason = "LOW_VOL_SCORE";
      g_state = STATE_SCANNING;
      return;
   }

   // News Protection Check
   bool is_post_news = false;
   if(IsHighImpactNewsWindow(is_post_news))
   {
      g_reject_reason = "HIGH_IMPACT_NEWS_BLOCK";
      g_state = STATE_SCANNING;
      return;
   }

   // Evaluate Multi-Timeframe & Tick Ensemble
   StrategySignal sig = EvaluateAdaptiveEnsemble();
   g_buy_conf  = sig.buy_conf;
   g_sell_conf = sig.sell_conf;

   double best_conf = MathMax(sig.buy_conf, sig.sell_conf);
   if(best_conf >= InpMinConfidence)
   {
      g_state = STATE_SIGNAL_READY;
      ExecuteSingleEntry(sig);
   }
   else
   {
      g_reject_reason = "CONFIDENCE_BELOW_MIN";
      g_state = STATE_SCANNING;
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction Listener (Deal Close & Cooldown Tracking)      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         string sym = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
         long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

         if(magic == (long)InpMagicNumber && sym == g_validated_symbol && entry == DEAL_ENTRY_OUT)
         {
            double net_pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                             HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                             HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

            if(net_pnl < 0.0)
            {
               g_persist.consecutive_losses++;
               if(g_persist.consecutive_losses >= InpMaxConsecutiveLosses)
               {
                  g_persist.cooldown_until = TimeCurrent() + InpLossCooldownMinutes * 60;
                  PrintFormat("[Vulcares Vx] %d consecutive losses reached. Cooldown active for %d mins.",
                              g_persist.consecutive_losses, InpLossCooldownMinutes);
               }
            }
            else if(net_pnl > 0.0)
            {
               g_persist.consecutive_losses = 0;
               g_last_reentry_ms = GetTickCount64();
            }

            g_persist.active_ticket      = 0;
            g_persist.highest_fav_price  = 0.0;
            g_persist.max_fav_net_profit = 0.0;
            g_persist.last_confirmed_sl  = 0.0;
            SavePersistentState();
            ReconcileBrokerState();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Timer Handler (Dashboard Refresh & Periodic Reconciliation)      |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(InpShowDashboard) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Custom Optimization Criterion (OnTester - Section 20)            |
//+------------------------------------------------------------------+
double OnTester()
{
   double net_profit = TesterStatistics(STAT_PROFIT);
   double pf         = TesterStatistics(STAT_PROFIT_FACTOR);
   double max_dd_pct = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double trades     = TesterStatistics(STAT_TRADES);

   if(trades < 50 || net_profit <= 0.0 || max_dd_pct > 15.0) return 0.0;
   return (net_profit * MathMin(pf, 4.0)) / MathMax(1.0, max_dd_pct);
}

//+------------------------------------------------------------------+
//| Chart Event Handler (Interactive Dashboard Buttons - Section 17) |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == DASH_PREFIX + "BTN_START")
   {
      g_user_paused = false;
      if(!g_persist.hard_dd_locked && !g_persist.emergency_stopped)
         g_state = STATE_SCANNING;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == DASH_PREFIX + "BTN_PAUSE")
   {
      g_user_paused = true;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == DASH_PREFIX + "BTN_CLOSE")
   {
      ulong pos_tkt = 0, ord_tkt = 0;
      CountEAOrdersAndPositions(pos_tkt, ord_tkt);
      if(pos_tkt > 0) EmergencyClosePosition(pos_tkt);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   else if(sparam == DASH_PREFIX + "BTN_EMERG")
   {
      g_persist.emergency_stopped = true;
      SavePersistentState();
      ulong pos_tkt = 0, ord_tkt = 0;
      CountEAOrdersAndPositions(pos_tkt, ord_tkt);
      if(ord_tkt > 0) g_trade.OrderDelete(ord_tkt);
      if(pos_tkt > 0) EmergencyClosePosition(pos_tkt);
      g_state = STATE_EMERGENCY_STOP;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Professional Volcanic Theme Dashboard (Section 17)               |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int font_size = 9, bool bold = false)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Consolas Bold" : "Consolas");
}

void CreateButton(string name, int x, int y, int w, int h, string text, color bg_clr, color txt_clr)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg_clr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txt_clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas Bold");
}

void CreateDashboard()
{
   // Volcanic Black Panel Background
   ObjectCreate(0, DASH_PREFIX + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_YDISTANCE, 22);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_XSIZE, 360);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_YSIZE, 430);
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_BGCOLOR, C'18,18,22');
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_BORDER_COLOR, C'220,50,20');
   ObjectSetInteger(0, DASH_PREFIX + "BG", OBJPROP_WIDTH, 2);

   CreateLabel(DASH_PREFIX + "TITLE", 24, 30, "VULCARES Vx  |  EXTREME SCALPING ENGINE", C'255,185,30', 10, true);
   CreateLabel(DASH_PREFIX + "LINE1", 24, 52, "STATUS / REGIME :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE2", 24, 70, "INITIAL / BAL   :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE3", 24, 88, "EQUITY / RISK   :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE4", 24, 106,"DAILY / WEEKLY  :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE5", 24, 124,"VOL SCORE       :", C'255,110,30');
   CreateLabel(DASH_PREFIX + "LINE6", 24, 142,"BUY / SELL CONF :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE7", 24, 160,"SPREAD / LAT    :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE8", 24, 178,"LOT / TRAIL PH  :", C'255,185,30');
   CreateLabel(DASH_PREFIX + "LINE9", 24, 196,"MAX FLOAT / SL  :", C'200,200,200');
   CreateLabel(DASH_PREFIX + "LINE10",24, 214,"FILTER / REASON :", C'255,80,60');

   // Control Buttons
   CreateButton(DASH_PREFIX + "BTN_START", 24,  250, 155, 28, "START ENGINE",    C'35,130,60',  clrWhite);
   CreateButton(DASH_PREFIX + "BTN_PAUSE", 190, 250, 165, 28, "PAUSE ENTRY",     C'210,120,20', clrWhite);
   CreateButton(DASH_PREFIX + "BTN_CLOSE", 24,  286, 155, 28, "CLOSE EA POS",    C'180,60,20',  clrWhite);
   CreateButton(DASH_PREFIX + "BTN_EMERG", 190, 286, 165, 28, "EMERGENCY STOP",  C'190,20,20',  clrWhite);

   CreateLabel(DASH_PREFIX + "FOOTER", 24, 330, "SINGLE-ENTRY | NO MARTINGALE | SERVER SL", C'140,140,150', 8);
   ChartRedraw(0);
}

void UpdateDashboard()
{
   string curr = AccountInfoString(ACCOUNT_CURRENCY);
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double daily_pnl  = eq - g_persist.daily_start_balance;
   double weekly_pnl = eq - g_persist.weekly_start_balance;
   double spread_pts = (double)SymbolInfoInteger(g_validated_symbol, SYMBOL_SPREAD);

   ObjectSetString(0, DASH_PREFIX + "LINE1", OBJPROP_TEXT, StringFormat("STATE: %s | %s", EnumToString(g_state), EnumToString(g_regime)));
   ObjectSetString(0, DASH_PREFIX + "LINE2", OBJPROP_TEXT, StringFormat("INIT : %.0f %s | BAL: %.2f %s", g_persist.initial_capital, curr, bal, curr));
   ObjectSetString(0, DASH_PREFIX + "LINE3", OBJPROP_TEXT, StringFormat("EQ   : %.2f %s | RISK: %.2f %s", eq, curr, GetFixedRiskBudget(), curr));
   ObjectSetString(0, DASH_PREFIX + "LINE4", OBJPROP_TEXT, StringFormat("DAY  : %+.2f | WK: %+.2f %s", daily_pnl, weekly_pnl, curr));
   ObjectSetString(0, DASH_PREFIX + "LINE5", OBJPROP_TEXT, StringFormat("VOLATILITY SCORE : %d / 100", g_vol_score));
   ObjectSetString(0, DASH_PREFIX + "LINE6", OBJPROP_TEXT, StringFormat("CONFIDENCE       : B %.2f | S %.2f", g_buy_conf, g_sell_conf));
   ObjectSetString(0, DASH_PREFIX + "LINE7", OBJPROP_TEXT, StringFormat("SPREAD: %.0f pts | LAT: %.2f ms", spread_pts, g_exec_latency_ms));
   ObjectSetString(0, DASH_PREFIX + "LINE8", OBJPROP_TEXT, StringFormat("LOT: %.2f | PH: %s", g_cur_lot, EnumToString(g_trail_phase)));
   ObjectSetString(0, DASH_PREFIX + "LINE9", OBJPROP_TEXT, StringFormat("PEAK FLT: %.2f %s | SL: %.2f", g_persist.max_fav_net_profit, curr, g_cur_sl));
   ObjectSetString(0, DASH_PREFIX + "LINE10",OBJPROP_TEXT, StringFormat("STATUS/BLOCK: %s", g_reject_reason));
   ChartRedraw(0);
}
