//+------------------------------------------------------------------+
//| Midas_Vx_Quantitative_SuperAggressive_v8_1.mq5                      |
//| MIDAS VX Quantitative Research                                    |
//| V8.2 revision of V8.1. Strategies A0-A5 and equity compounding.    |
//+------------------------------------------------------------------+
#property copyright "MIDAS VX Quantitative Research"
#property version "8.20"
#property description "MIDAS VX V8.2 | A0-A5, verified execution and persistent equity guards"
#property strict

enum ENUM_RISK_MODE
{
   RISK_MODE_AGGRESSIVE = 0,
   RISK_MODE_SUPER_AGGRESSIVE = 1,
   RISK_MODE_EXTREME_RESEARCH = 2
};

enum ENUM_STRATEGY_ID
{
   STRAT_A0_MOMENTUM, STRAT_A1_LIQ_SWEEP, STRAT_A2_MEAN_REV,
   STRAT_A3_VOL_EXPL, STRAT_A4_TREND_IMP, STRAT_A5_INST_PULLBACK, STRAT_COUNT
};

input group "1. Capital and equity guards"
input ENUM_RISK_MODE InpRiskMode = RISK_MODE_SUPER_AGGRESSIVE;
input double InpCustomRiskPct = 0.0;
input double InpMaxDailyLossPct = 0.0;
input double InpMaxCycleDDPct = 0.0;
input int    InpDDCooldownMinutes = 30;  // Minimum pause before an explicit cycle reset
input int    InpCycleResetToken = 0;     // Increase after a cycle breach, once MVX positions are flat
input double InpMaxCumulativeRiskPct = 5.5; // Per exact broker symbol + magic
input double InpMaxPortfolioRiskPct = 10.0; // Account-level SL exposure cap; 0 disables it
input int    InpMaxOpenSignalsSymbol = 3;
input int    InpMaxTranchesPerSignal = 5;
input double InpMinMarginLevelPct = 220.0;
input bool   InpAllowMinLotFloor = false; // Minimum lot still must fit the budget
input bool   InpUseEquityCompounding = true;

input group "2. V8.1 strategies"
input bool InpEnableStratA0_Momentum = true;
input bool InpEnableStratA1_LiqSweep = true;
input bool InpEnableStratA2_MeanRev = true;
input bool InpEnableStratA3_VolExpl = true;
input bool InpEnableStratA4_TrendImp = true;
input bool InpEnableStratA5_Pullback = true;

input group "3. Tick data and costs"
input int    InpTickWindow = 20;
input double InpMinTickVelocity = 0.25;
input double InpMinExpectancyR = 0.05;
input double InpCommissionPerLot = 0.0; // Round turn in deposit currency; 0 learns from history
input double InpBaseSlippagePips = 0.30; // Per-side slippage allowance
input double InpMaxSpreadPips = 0.0;    // 0 uses spread/ATR only
input double InpMaxSpreadATR_Ratio = 0.45;
input int    InpMaxTickAgeSeconds = 5;

input group "4. Multi-timeframe indicators"
input int    InpM1_FastEMA = 8;
input int    InpM1_SlowEMA = 21;
input int    InpM1_ATR_Period = 14;
input int    InpM1_RSI_Period = 7;
input int    InpM1_BB_Period = 20;
input double InpM1_BB_Deviation = 2.0;
input int    InpM5_FastEMA = 13;
input int    InpM5_SlowEMA = 34;
input int    InpM5_ATR_Period = 14;
input int    InpM5_ADX_Period = 14;
input int    InpM15_SwingLookback = 16;
input int    InpH1_FastEMA = 34;
input int    InpH1_SlowEMA = 100;
input int    InpH1_ADX_Period = 14;

input group "5. Exits and re-entry"
input double InpSL_ATR_Multiplier = 1.35;
input double InpTP_ATR_Multiplier = 2.20;
input bool   InpUseEarlyBreakeven = true;
input double InpBreakevenRR = 0.60;
input bool   InpUsePartialClose = true;
input double InpPartialCloseRR = 1.00;
input double InpPartialClosePct = 40.0;
input bool   InpUseTrailingStop = true;
input double InpTrailActivationRR = 0.90;
input double InpTrailStepATR = 0.55;
input bool   InpUseMomentumExit = true;
input int    InpMaxHoldSeconds = 1500;
input int    InpReEntryCooldownSec = 10;

input group "6. Adaptive calibration and testing"
input bool   InpUseAdaptiveSelfOpt = true;
input bool   InpAllowAdaptiveRiskIncrease = false;
input int    InpRollingWindowTrades = 25;
input int    InpMinTradesForAdapt = 10;
input double InpSuspendExpectancyFloor = -0.35;
input int    InpSuspendCooldownMinutes = 15;
input int    InpHistoryDays = 14;
input int    InpTesterMinTrades = 50;

input group "7. Broker, session and dashboard"
input bool  InpUseSessionFilter = false;
input int   InpSessionStartHour = 2;
input int   InpSessionEndHour = 22;
input bool  InpAvoidGoldRollover = true;
input ulong InpMagicNumber = 20260810;
input ulong InpSlippageDeviation = 35;
input bool  InpShowDashboardPanel = true;
input int   InpPanelX = 14;
input int   InpPanelY = 24;
input bool  InpDiagnosticLog = false;
input bool  InpAllowRealAccount = false;
input int   InpExecutionRecoveryToken = 0; // Increase only after reconciling an ambiguous request

#define MVX_PREFIX "MVX82"
#define HUD_PREFIX "MVX82_"
#define TICK_CAPACITY 64

struct Signal
{
   int side;
   int strategy;
   double sl_dist;
   double tp_dist;
   double prior;
   double boost;
   double score;
   double exp_r;
};

struct ClosedPosition
{
   ulong id;
   int strategy;
   long time_msc;
   double pnl;
   double risk;
   double fees;
   double volume;
};

struct OpenPosition
{
   ulong id;
   double distance;
   bool had_exit;
   bool uncertain_partial;
   bool ready;
};

struct StrategyStats
{
   int count;
   int total;
   int losing_streak;
   datetime last_exit;
   double pnl;
   double mean_r;
};

struct HistoryRecord
{
   bool owned;
   int strategy;
   double initial_dist;
   double risk;
   double pnl;
   double fees;
   double volume;
   double exit_volume;
   long exit_msc;
};

int g_ema1_fast = INVALID_HANDLE, g_ema1_slow = INVALID_HANDLE;
int g_atr1 = INVALID_HANDLE, g_rsi1 = INVALID_HANDLE, g_bands = INVALID_HANDLE;
int g_ema5_fast = INVALID_HANDLE, g_ema5_slow = INVALID_HANDLE;
int g_atr5 = INVALID_HANDLE, g_adx5 = INVALID_HANDLE;
int g_emaH_fast = INVALID_HANDLE, g_emaH_slow = INVALID_HANDLE, g_adxH = INVALID_HANDLE;
datetime g_bar = 0, g_swing_bar = 0, g_m5_bar = 0, g_h1_bar = 0;
double g_fast[3], g_slow[3], g_atr[3], g_rsi[3], g_upper[3], g_middle[3], g_lower[3];
MqlRates g_m1[3];
double g_swing_high = 0, g_swing_low = 0, g_adx = 0, g_vol_ratio = 1.0;
int g_trend5 = 0, g_trendH = 0;
double g_h1_adx_value = 0;
bool g_has_swing = false;
bool g_trending = false, g_ranging = false;

int g_tick_count = 0;
long g_tick_time[TICK_CAPACITY];
double g_tick_mid[TICK_CAPACITY];
double g_ticks_per_sec = 0, g_velocity = 0, g_imbalance = 0;
long g_latest_quote_msc = 0;
uint g_tick_repeats = 0;

string g_account_key, g_scope_key;
bool g_scope_owner = false, g_lock_held = false, g_initialized = false, g_use_hud = false, g_paused = false;
double g_day_equity = 0, g_cycle_anchor = 0;
bool g_day_locked = false, g_cycle_locked = false, g_liquidating = false;
bool g_local_close = false;
double g_risk_pct, g_daily_limit, g_cycle_limit;
ENUM_RISK_MODE g_risk_mode;
datetime g_breach_at = 0;
string g_status = "INITIALIZING", g_last_log = "";
datetime g_last_log_time = 0;
ulong g_last_hud_ms = 0, g_close_confirm_ms = 0;
bool g_enabled[STRAT_COUNT];
string g_signal_state[STRAT_COUNT];
ClosedPosition g_closed[];
OpenPosition g_open[];
ulong g_dirty_ids[];
StrategyStats g_stats[STRAT_COUNT];
bool g_stats_ready = false;
double g_commission = 0, g_slippage = 0;
ulong g_cached_pending = 0;
datetime g_last_stats_day = 0;
datetime g_last_diagnostic_bar = 0;

// Tester global variables are emulated by the tester agent.
bool PutState(const string key, const double value)
{
   if(GlobalVariableSet(key, value) != 0)
      return true;
   PrintFormat("MIDAS VX: cannot persist %s (%d)", key, GetLastError());
   return false;
}

double State(const string key)
{
   double value = 0.0;
   GlobalVariableGet(key, value);
   return value;
}

uint TextHash(const string value)
{
   uint hash = 2166136261;
   for(int i = 0; i < StringLen(value); ++i)
      hash = (uint)((hash ^ (uint)StringGetCharacter(value, i)) * 16777619);
   return hash;
}

bool LockAccount()
{
   if(g_lock_held)
      return false;
   string key = g_account_key + ".lock";
   if(!GlobalVariableCheck(key))
      GlobalVariableTemp(key);
   g_lock_held = GlobalVariableSetOnCondition(key, 1.0, 0.0);
   return g_lock_held;
}

void UnlockAccount()
{
   if(g_lock_held)
   {
      GlobalVariableSetOnCondition(g_account_key + ".lock", 0.0, 1.0);
      g_lock_held = false;
   }
}

datetime ServerNow()
{
   if(MQLInfoInteger(MQL_TESTER))
      return TimeCurrent();
   datetime server_time = TimeTradeServer();
   return server_time > 0 ? server_time : TimeCurrent();
}

int DateKey(datetime when)
{
   MqlDateTime date;
   if(!TimeToStruct(when, date))
      return 0;
   return date.year * 10000 + date.mon * 100 + date.day;
}

string StrategyCode(int id)
{
   return id >= 0 && id < STRAT_COUNT ? "A" + IntegerToString(id) : "?";
}

int ParseStrategy(const string note)
{
   bool revision = StringFind(note, "MVX82|A") == 0;
   bool original = StringFind(note, "MVX81|A") == 0;
   if((!revision && !original) || StringLen(note) < 8)
      return -1;
   int id = (int)StringGetCharacter(note, 7) - 48;
   return id >= 0 && id < STRAT_COUNT ? id : -1;
}

string SignalTag(const int strategy, const datetime bar)
{
   return MVX_PREFIX + "|" + StrategyCode(strategy) + "|" + IntegerToString((long)bar);
}

bool OwnPosition()
{
   return PositionGetString(POSITION_SYMBOL) == _Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber;
}

bool OwnOrder()
{
   return OrderGetString(ORDER_SYMBOL) == _Symbol &&
          (ulong)OrderGetInteger(ORDER_MAGIC) == InpMagicNumber;
}

bool PositionById(const ulong id)
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
      if(PositionGetTicket(i) > 0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER) == id)
         return true;
   return false;
}

int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
      if(PositionGetTicket(i) > 0 && OwnPosition())
         ++count;
   return count;
}

int CountSignals()
{
   string tags[];
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(PositionGetTicket(i) == 0 || !OwnPosition())
         continue;
      string tag = PositionGetString(POSITION_COMMENT);
      int tranche_separator = StringFind(tag, "|", 9);
      if(StringFind(tag, "MVX82|A") == 0 && tranche_separator > 9)
      {
         tag = StringSubstr(tag, 0, tranche_separator);
         bool seen = false;
         for(int j = 0; j < ArraySize(tags); ++j)
         {
            if(tags[j] == tag)
            {
               seen = true;
               break;
            }
         }
         if(seen)
            continue;
         int size = ArraySize(tags);
         ArrayResize(tags, size + 1);
         tags[size] = tag;
      }
      ++count;
   }
   return count;
}

bool HasScopedOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
      if(OrderGetTicket(i) > 0 && OwnOrder())
         return true;
   return false;
}

bool HasMidasExposure()
{
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(PositionGetTicket(i) == 0)
         continue;
      if(ParseStrategy(PositionGetString(POSITION_COMMENT)) >= 0 ||
         (ulong)PositionGetInteger(POSITION_MAGIC) == 20260810 || OwnPosition())
         return true;
   }
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      if(OrderGetTicket(i) == 0)
         continue;
      if(ParseStrategy(OrderGetString(ORDER_COMMENT)) >= 0 ||
         (ulong)OrderGetInteger(ORDER_MAGIC) == 20260810 || OwnOrder())
         return true;
   }
   return false;
}

void Status(const string message)
{
   g_status = message;
   datetime now = TimeCurrent();
   if(InpDiagnosticLog && (message != g_last_log || now - g_last_log_time >= 60))
   {
      PrintFormat("MIDAS VX [%s]: %s", _Symbol, message);
      g_last_log = message;
      g_last_log_time = now;
   }
}

void ApplyRiskMode(ENUM_RISK_MODE mode)
{
   g_risk_mode = mode;
   double risk[3] = {1.15, 1.85, 2.65};
   double day[3] = {8.0, 10.0, 12.0};
   double cycle[3] = {24.0, 28.0, 32.0};
   int index = (int)mode;
   g_risk_pct = InpCustomRiskPct > 0 ? InpCustomRiskPct : risk[index];
   g_daily_limit = InpMaxDailyLossPct > 0 ? InpMaxDailyLossPct : day[index];
   g_cycle_limit = InpMaxCycleDDPct > 0 ? InpMaxCycleDDPct : cycle[index];
}

// The day baseline and daily latch have separate, dated keys. The cycle latch
// persists across midnight, restarts and risk-mode changes.
bool UpdateGuards(const datetime now)
{
   int day = DateKey(now);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(day == 0 || !MathIsValidNumber(equity))
      return false;

   string day_key = g_account_key + ".day" + IntegerToString(day);
   if(!GlobalVariableCheck(day_key))
   {
      if(equity <= 0.0 || !PutState(day_key, equity))
         return false;
   }
   g_day_equity = State(day_key);
   g_day_locked = State(day_key + ".hit") > 0.0;

   string cycle_key = g_account_key + ".peak";
   if(!GlobalVariableCheck(cycle_key))
   {
      if(equity <= 0.0 || !PutState(cycle_key, equity))
         return false;
   }
   g_cycle_anchor = State(cycle_key);
   datetime cycle_hit = (datetime)State(g_account_key + ".cycle");
   if(cycle_hit > 0 &&
      InpCycleResetToken > (int)State(g_account_key + ".reset") &&
      now - cycle_hit >= InpDDCooldownMinutes * 60 &&
      equity > 0.0 && State(g_scope_key + ".flight") == 0.0 && !HasMidasExposure())
   {
      if(!PutState(cycle_key, equity) ||
         !PutState(g_account_key + ".reset", InpCycleResetToken) ||
         !PutState(g_account_key + ".cycle", 0.0))
         return false;
      cycle_hit = 0;
      g_cycle_anchor = equity;
      GlobalVariablesFlush();
      Print("MIDAS VX: cycle reset while flat; daily baseline preserved");
   }

   if(cycle_hit == 0 && InpCycleResetToken > (int)State(g_account_key + ".reset"))
   {
      if(!PutState(g_account_key + ".reset", InpCycleResetToken))
         return false;
      GlobalVariablesFlush();
   }

   if(cycle_hit == 0 && equity > g_cycle_anchor)
   {
      if(!PutState(cycle_key, equity))
         return false;
      g_cycle_anchor = equity;
   }

   bool daily_breach = !g_day_locked && g_day_equity > 0.0 &&
      100.0 * (g_day_equity - equity) / g_day_equity >= g_daily_limit;
   bool cycle_breach = cycle_hit == 0 && g_cycle_anchor > 0.0 &&
      100.0 * (g_cycle_anchor - equity) / g_cycle_anchor >= g_cycle_limit;

   if(daily_breach || cycle_breach)
   {
      if(!PutState(g_account_key + ".breach", (double)now))
         return false;
      if(daily_breach && !PutState(day_key + ".hit", 1.0))
         return false;
      if(cycle_breach && !PutState(g_account_key + ".cycle", (double)now))
         return false;
      GlobalVariablesFlush();
      PrintFormat("MIDAS VX: equity guard | daily=%d cycle=%d equity=%.2f",
                  (int)daily_breach, (int)cycle_breach, equity);
   }
   g_day_locked = g_day_locked || daily_breach;
   g_cycle_locked = cycle_hit > 0 || cycle_breach;
   g_breach_at = (datetime)State(g_account_key + ".breach");
   return g_day_equity > 0.0 && g_cycle_anchor > 0.0;
}

bool TradesAllowed()
{
   if(!InpAllowRealAccount && AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL &&
      !MQLInfoInteger(MQL_TESTER))
      return false;
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}

double PipScale()
{
   return (_Digits == 3 || _Digits == 5) ? 10.0 : 1.0;
}

double TickSize()
{
   return SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
}

double RoundPrice(double price, const bool up)
{
   double tick_size = TickSize();
   if(tick_size <= 0)
      return 0;
   double ticks = price / tick_size;
   return NormalizeDouble((up ? MathCeil(ticks - 1e-8) : MathFloor(ticks + 1e-8)) * tick_size, _Digits);
}

int VolumeDigits(double step)
{
   for(int digits = 0; digits <= 8; ++digits)
      if(MathAbs(NormalizeDouble(step, digits) - step) <= 1e-10)
         return digits;
   return 8;
}

double RoundVolume(const double volume)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(volume <= 0.0 || step <= 0.0)
      return 0.0;
   return NormalizeDouble(MathFloor(volume / step + 1e-8) * step, VolumeDigits(step));
}

bool CalcCash(const ENUM_ORDER_TYPE side, const string symbol, const double volume,
              const double from, const double to, double &pnl)
{
   if(volume <= 0.0 || from <= 0.0 || to <= 0.0)
      return false;
   return OrderCalcProfit(side, symbol, volume, from, to, pnl) && MathIsValidNumber(pnl);
}

bool ReadHistory(const ulong id, HistoryRecord &record)
{
   ZeroMemory(record);
   record.strategy = -1;
   if(!HistorySelectByPosition(id))
      return false;

   double distance_sum = 0.0;
   bool valid_risk = true;
   int count = HistoryDealsTotal();
   for(int i = 0; i < count; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         return false;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      if(entry == DEAL_ENTRY_IN)
      {
         if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber)
            continue;
         record.owned = true;
         ulong order = (ulong)HistoryDealGetInteger(deal, DEAL_ORDER);
         int strategy = ParseStrategy(HistoryDealGetString(deal, DEAL_COMMENT));
         if(strategy < 0 && order > 0)
            strategy = ParseStrategy(HistoryOrderGetString(order, ORDER_COMMENT));
         if(record.strategy < 0)
            record.strategy = strategy;

         double origin = HistoryDealGetDouble(deal, DEAL_PRICE);
         double stop = HistoryDealGetDouble(deal, DEAL_SL);
         if(stop <= 0.0 && order > 0)
            stop = HistoryOrderGetDouble(order, ORDER_SL);
         ENUM_ORDER_TYPE side = HistoryDealGetInteger(deal, DEAL_TYPE) == DEAL_TYPE_BUY ?
                                ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double loss = 0.0;
         bool stop_on_loss_side = side == ORDER_TYPE_BUY ? stop < origin : stop > origin;
         if(stop_on_loss_side && CalcCash(side, _Symbol, volume, origin, stop, loss) && loss < 0.0)
         {
            record.risk -= loss;
            distance_sum += MathAbs(origin - stop) * volume;
         }
         else
            valid_risk = false;
         record.volume += volume;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      {
         record.exit_volume += volume;
         long exit_msc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(exit_msc > record.exit_msc)
            record.exit_msc = exit_msc;
      }
      else
         continue;

      double costs = HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
      record.pnl += HistoryDealGetDouble(deal, DEAL_PROFIT) + HistoryDealGetDouble(deal, DEAL_SWAP) + costs;
      record.fees -= costs;
   }

   if(valid_risk && record.volume > 0.0)
   {
      record.initial_dist = distance_sum / record.volume;
      string key = g_scope_key + ".r" + IntegerToString((long)id);
      double saved_risk = State(key);
      if(saved_risk > 0.0 && MathAbs(State(key + ".v") - record.volume) < 1e-8)
         record.risk = saved_risk;
      else if(record.exit_volume < record.volume && record.risk > 0.0)
      {
         // Freeze the deposit-currency conversion while the entry is live.
         if(PutState(key + ".v", 0.0) && PutState(key, record.risk) &&
            PutState(key + ".v", record.volume))
            GlobalVariablesFlush();
      }
   }
   else
      record.risk = 0.0;
   return true;
}

int OpenIndex(const ulong id)
{
   for(int i = 0; i < ArraySize(g_open); ++i)
      if(g_open[i].id == id)
         return i;
   return -1;
}

void RefreshOpenRecord(const int index)
{
   HistoryRecord record;
   if(!ReadHistory(g_open[index].id, record) || !record.owned || record.volume <= 0)
      return;
   g_open[index].distance = record.initial_dist;
   g_open[index].had_exit = record.exit_volume > 0;
   g_open[index].ready = true;
}

int LoadOpenRecord(const ulong id)
{
   int index = OpenIndex(id);
   if(index < 0)
   {
      index = ArraySize(g_open);
      if(ArrayResize(g_open, index + 1, 32) != index + 1)
         return -1;
      OpenPosition item;
      ZeroMemory(item);
      item.id = id;
      item.uncertain_partial = State(g_scope_key + ".p" + IntegerToString((long)id)) > 0;
      g_open[index] = item;
   }
   if(!g_open[index].ready)
      RefreshOpenRecord(index);
   return index;
}

void AppendClosed(const ulong id, const HistoryRecord &record)
{
   if(!record.owned || record.strategy < 0 || record.exit_msc <= 0 ||
      record.volume <= 0.0 || record.exit_volume + 1e-8 < record.volume)
      return;
   int size = ArraySize(g_closed);
   for(int i = size - 1; i >= 0; --i)
      if(g_closed[i].id == id)
         return;
   if(ArrayResize(g_closed, size + 1, 256) != size + 1)
      return;
   int destination = size;
   while(destination > 0 && g_closed[destination - 1].time_msc > record.exit_msc)
   {
      g_closed[destination] = g_closed[destination - 1];
      --destination;
   }
   g_closed[destination].id = id;
   g_closed[destination].strategy = record.strategy;
   g_closed[destination].time_msc = record.exit_msc;
   g_closed[destination].pnl = record.pnl;
   g_closed[destination].risk = record.risk;
   g_closed[destination].fees = record.fees;
   g_closed[destination].volume = record.volume;
}

void RecalculateStats(const datetime now)
{
   long from_msc = ((long)now - InpHistoryDays * 86400) * 1000;
   int old = 0;
   while(old < ArraySize(g_closed) && g_closed[old].time_msc < from_msc)
      ++old;
   if(old > 0)
      ArrayRemove(g_closed, 0, (uint)old);

   double r_sum[STRAT_COUNT];
   ArrayInitialize(r_sum, 0.0);
   int fee_samples = 0;
   double fee_sum = 0, fee_volume = 0;
   for(int s = 0; s < STRAT_COUNT; ++s)
      ZeroMemory(g_stats[s]);

   for(int i = ArraySize(g_closed) - 1; i >= 0; --i)
   {
      if(g_closed[i].time_msc < from_msc)
         break;
      int s = g_closed[i].strategy;
      ++g_stats[s].total;
      g_stats[s].pnl += g_closed[i].pnl;
      if(fee_samples < InpRollingWindowTrades)
      {
         fee_sum += MathMax(0.0, g_closed[i].fees);
         fee_volume += g_closed[i].volume;
         ++fee_samples;
      }
      if(g_stats[s].count >= InpRollingWindowTrades || g_closed[i].risk <= 0.0)
         continue;
      double realized_r = g_closed[i].pnl / g_closed[i].risk;
      if(g_stats[s].count == 0)
         g_stats[s].last_exit = (datetime)(g_closed[i].time_msc / 1000);
      if(g_stats[s].losing_streak == g_stats[s].count && realized_r < 0)
         ++g_stats[s].losing_streak;
      ++g_stats[s].count;
      r_sum[s] += realized_r;
   }

   for(int s = 0; s < STRAT_COUNT; ++s)
      if(g_stats[s].count > 0)
         g_stats[s].mean_r = r_sum[s] / g_stats[s].count;
   g_commission = InpCommissionPerLot > 0 ? InpCommissionPerLot : (fee_volume > 0 ? fee_sum / fee_volume : 0);
}

bool BootstrapStats(const datetime now)
{
   if(!HistorySelect(now - InpHistoryDays * 86400, now + 60))
      return false;
   // Snapshot and deduplicate first. HistorySelectByPosition changes the selected list.
   ulong ids[];
   int length = HistoryDealsTotal();
   for(int i = 0; i < length; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
         continue;
      int count = ArraySize(ids);
      if(ArrayResize(ids, count + 1, 256) != count + 1)
         return false;
      ids[count] = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
   }
   ArraySort(ids);
   ArrayResize(g_closed, 0);
   for(int i = 0; i < ArraySize(ids); ++i)
   {
      if(ids[i] == 0 || (i > 0 && ids[i] == ids[i - 1]) || PositionById(ids[i]))
         continue;
      HistoryRecord record;
      if(!ReadHistory(ids[i], record))
         return false;
      AppendClosed(ids[i], record);
   }
   RecalculateStats(now);
   return true;
}

void QueuePosition(const ulong id)
{
   if(id == 0)
      return;
   int count = ArraySize(g_dirty_ids);
   for(int i = 0; i < count; ++i)
      if(g_dirty_ids[i] == id)
         return;
   if(ArrayResize(g_dirty_ids, count + 1, 32) == count + 1)
      g_dirty_ids[count] = id;
}

void ProcessPositionChanges(const datetime now)
{
   int count = ArraySize(g_dirty_ids);
   int keep = 0;
   bool changed = false;
   for(int i = 0; i < count; ++i)
   {
      ulong id = g_dirty_ids[i];
      if(PositionById(id))
      {
         int index = OpenIndex(id);
         if(index >= 0 && OwnPosition())
            RefreshOpenRecord(index);
         continue;
      }
      HistoryRecord record;
      if(!ReadHistory(id, record) || (record.owned && record.exit_volume + 1e-8 < record.volume))
      {
         g_dirty_ids[keep++] = id;
         continue;
      }
      if(record.owned && record.exit_msc > 0)
      {
         AppendClosed(id, record);
         changed = true;
         int index = OpenIndex(id);
         if(index >= 0)
         {
            int last = ArraySize(g_open) - 1;
            g_open[index] = g_open[last];
            ArrayResize(g_open, last);
         }
         GlobalVariableDel(g_scope_key + ".p" + IntegerToString((long)id));
      }
   }
   ArrayResize(g_dirty_ids, keep);
   if(changed || DateKey(now) != DateKey(g_last_stats_day))
   {
      RecalculateStats(now);
      g_last_stats_day = now;
   }
}

bool ReadSeries(const int handle, const int buffer, const int count, double &out[])
{
   double values[];
   if(CopyBuffer(handle, buffer, 1, count, values) != count)
      return false;
   for(int i = 0; i < count; ++i)
      if(!MathIsValidNumber(values[i]) || values[i] == EMPTY_VALUE)
         return false;
   for(int i = 0; i < count; ++i)
      out[i] = values[count - 1 - i];
   return true;
}

bool UpdateSwing(const datetime signal_start)
{
   int shift = iBarShift(_Symbol, PERIOD_M15, signal_start, false);
   if(shift < 0)
      return false;
   int first = shift + 1; // Exclude the M15 bar containing the M1 signal.
   datetime reference = iTime(_Symbol, PERIOD_M15, first);
   if(reference <= 0)
      return false;
   if(reference == g_swing_bar)
      return true;
   MqlRates bars[];
   if(CopyRates(_Symbol, PERIOD_M15, first, InpM15_SwingLookback, bars) != InpM15_SwingLookback)
      return false;
   g_swing_high = bars[0].high;
   g_swing_low = bars[0].low;
   for(int i = 1; i < InpM15_SwingLookback; ++i)
   {
      g_swing_high = MathMax(g_swing_high, bars[i].high);
      g_swing_low = MathMin(g_swing_low, bars[i].low);
   }
   g_swing_bar = reference;
   return true;
}

bool UpdateMtf()
{
   datetime h1_bar = iTime(_Symbol, PERIOD_H1, 0);
   datetime m5_bar = iTime(_Symbol, PERIOD_M5, 0);
   datetime m1_bar = iTime(_Symbol, PERIOD_M1, 0);
   if(h1_bar <= 0 || m5_bar <= 0 || m1_bar <= 0)
      return false;

   double fast[1], slow[1], adx[1];
   if(h1_bar != g_h1_bar)
   {
      if(!ReadSeries(g_emaH_fast, 0, 1, fast) || !ReadSeries(g_emaH_slow, 0, 1, slow) ||
         !ReadSeries(g_adxH, 0, 1, adx))
         return false;
      g_trendH = fast[0] > slow[0] ? 1 : (fast[0] < slow[0] ? -1 : 0);
      g_h1_adx_value = adx[0];
      g_h1_bar = h1_bar;
   }
   if(m5_bar != g_m5_bar)
   {
      double atr5[20];
      if(!ReadSeries(g_ema5_fast, 0, 1, fast) || !ReadSeries(g_ema5_slow, 0, 1, slow) ||
         !ReadSeries(g_adx5, 0, 1, adx) || !ReadSeries(g_atr5, 0, 20, atr5))
         return false;
      double sum = 0.0;
      for(int i = 0; i < 20; ++i)
         sum += atr5[i];
      g_vol_ratio = sum > 0 ? atr5[0] / (sum / 20.0) : 1.0;
      g_adx = adx[0];
      g_trend5 = fast[0] > slow[0] ? 1 : (fast[0] < slow[0] ? -1 : 0);
      g_m5_bar = m5_bar;
   }
   if(m1_bar != g_bar)
   {
      MqlRates bars[3];
      if(CopyRates(_Symbol, PERIOD_M1, 1, 3, bars) != 3 ||
         !ReadSeries(g_ema1_fast, 0, 3, g_fast) || !ReadSeries(g_ema1_slow, 0, 3, g_slow) ||
         !ReadSeries(g_atr1, 0, 3, g_atr) || !ReadSeries(g_rsi1, 0, 3, g_rsi) ||
         !ReadSeries(g_bands, 0, 3, g_middle) || !ReadSeries(g_bands, 1, 3, g_upper) ||
         !ReadSeries(g_bands, 2, 3, g_lower))
         return false;
      for(int i = 0; i < 3; ++i)
         g_m1[i] = bars[2 - i];
      g_bar = m1_bar;
   }
   g_has_swing = !g_enabled[STRAT_A1_LIQ_SWEEP] || UpdateSwing(g_m1[0].time);
   bool compression = g_vol_ratio < 0.78 && g_adx < 20;
   g_trending = !compression && g_h1_adx_value >= 22 && g_trendH != 0;
   g_ranging = !compression && !g_trending;
   return g_atr[0] > 0.0;
}

// Recover intervening quote ticks instead of counting one sample per OnTick event.
bool UpdateMicro(const MqlTick &latest)
{
   if(latest.time_msc <= 0 || latest.ask <= 0.0 || latest.bid <= 0.0 || latest.ask < latest.bid)
      return false;
   MqlTick ticks[];
   uint count_request = TICK_CAPACITY * 2;
   int previous_count = 0;
   bool reset = g_latest_quote_msc == 0 || latest.time_msc < g_latest_quote_msc ||
                latest.time_msc - g_latest_quote_msc > (long)InpMaxTickAgeSeconds * 1000;
   if(reset)
   {
      g_tick_count = 0;
      g_latest_quote_msc = 0;
      g_tick_repeats = 0;
   }
   uint batch = count_request + g_tick_repeats;
   int count = CopyTicks(_Symbol, ticks, COPY_TICKS_INFO, (ulong)g_latest_quote_msc, batch);
   if(count <= 0)
      return false;
   if(!reset && count == (int)batch)
   {
      count = CopyTicks(_Symbol, ticks, COPY_TICKS_INFO, 0, count_request);
      if(count <= 0)
         return false;
      g_latest_quote_msc = 0;
      g_tick_repeats = 0;
      g_tick_count = 0;
   }
   long previous = g_latest_quote_msc;
   const uint previously_read = g_tick_repeats;
   for(int i = 0; i < count; ++i)
   {
      long msc = ticks[i].time_msc;
      if(msc < previous || msc > latest.time_msc)
         continue;
      if(msc == previous && previous_count++ < (int)previously_read)
         continue;
      if(msc != g_latest_quote_msc)
      {
         g_latest_quote_msc = msc;
         g_tick_repeats = 0;
      }
      ++g_tick_repeats;
      if(ticks[i].ask <= 0 || ticks[i].bid <= 0 || ticks[i].ask < ticks[i].bid)
         continue;
      int idx = g_tick_count % TICK_CAPACITY;
      g_tick_time[idx] = msc;
      g_tick_mid[idx] = (ticks[i].ask + ticks[i].bid) / 2.0;
      ++g_tick_count;
   }

   int length = (int)MathMin(g_tick_count, InpTickWindow);
   while(length > 0 && latest.time_msc - g_tick_time[(g_tick_count - length) % TICK_CAPACITY] >
                       (long)InpMaxTickAgeSeconds * 1000)
      --length;
   if(length < 5)
      return false;
   int oldest = (g_tick_count - length) % TICK_CAPACITY;
   int newest = (g_tick_count - 1) % TICK_CAPACITY;
   double seconds = MathMax(0.25, (g_tick_time[newest] - g_tick_time[oldest]) / 1000.0);
   g_ticks_per_sec = (length - 1) / seconds;
   g_velocity = (g_tick_mid[newest] - g_tick_mid[oldest]) / _Point / seconds;
   int up = 0, down = 0;
   for(int i = 1; i < length; ++i)
   {
      int index = (oldest + i) % TICK_CAPACITY;
      int prev = (index + TICK_CAPACITY - 1) % TICK_CAPACITY;
      if(g_tick_mid[index] > g_tick_mid[prev]) ++up;
      if(g_tick_mid[index] < g_tick_mid[prev]) ++down;
   }
   g_imbalance = up + down > 0 ? (double)(up - down) / (up + down) : 0.0;
   return true;
}

bool BuildStops(const Signal &signal, const MqlTick &quote, double &price, double &sl, double &tp)
{
   double tick_size = TickSize();
   if(tick_size <= 0.0 || quote.bid <= 0.0 || quote.ask < quote.bid)
      return false;
   double broker_dist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point + tick_size;
   double spread = quote.ask - quote.bid;
   double stop_dist = MathMax(signal.sl_dist, MathMax(broker_dist + spread, spread * 2.0));
   double take_dist = MathMax(signal.tp_dist, stop_dist * 1.25);
   if(signal.side > 0)
   {
      price = quote.ask;
      sl = RoundPrice(MathMin(price - stop_dist, quote.bid - broker_dist), false);
      tp = RoundPrice(MathMax(price + take_dist, quote.bid + broker_dist), true);
   }
   else
   {
      price = quote.bid;
      sl = RoundPrice(MathMax(price + stop_dist, quote.ask + broker_dist), true);
      tp = RoundPrice(MathMin(price - take_dist, quote.ask - broker_dist), false);
   }
   return price > 0 && sl > 0 && tp > 0;
}

ENUM_ORDER_TYPE SignalOrderType(const int side)
{
   return side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
}

bool IsSuspended(const int strategy, const datetime now)
{
   return InpUseAdaptiveSelfOpt && g_stats[strategy].count >= InpMinTradesForAdapt &&
      (g_stats[strategy].mean_r < InpSuspendExpectancyFloor || g_stats[strategy].losing_streak >= 4) &&
      now - g_stats[strategy].last_exit < InpSuspendCooldownMinutes * 60;
}

// The V8.1 prior only ranks signals while observations are scarce. The empirical
// component uses realized net R and includes the impact of V8.1's early exits.
bool RateSignal(Signal &candidate, const MqlTick &quote, const double session_weight)
{
   double price, sl, tp, loss, reward;
   if(!BuildStops(candidate, quote, price, sl, tp))
      return false;
   ENUM_ORDER_TYPE side = SignalOrderType(candidate.side);
   double sample_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(!CalcCash(side, _Symbol, sample_lot, price, sl, loss) || loss >= 0 ||
      !CalcCash(side, _Symbol, sample_lot, price, tp, reward) || reward <= 0)
      return false;

   // Bid/Ask already set executable prices. Spread is separately constrained
   // by the environment filter. Charge commission and both slippage legs here.
   double slip_loss = 0.0;
   if(g_slippage > 0 &&
      !CalcCash(side, _Symbol, sample_lot, price, price - candidate.side * g_slippage, slip_loss))
      return false;
   double cost = g_commission * sample_lot + 2.0 * MathMax(0.0, -slip_loss);
   double model_r = (candidate.prior * reward + (1.0 - candidate.prior) * loss - cost) / (-loss);
   int strategy = candidate.strategy;
   candidate.exp_r = model_r;
   if(InpUseAdaptiveSelfOpt && g_stats[strategy].count >= InpMinTradesForAdapt)
   {
      double weight = MathMin(0.80, (double)g_stats[strategy].count / InpRollingWindowTrades);
      candidate.exp_r = (1.0 - weight) * model_r + weight * g_stats[strategy].mean_r;
   }
   if(candidate.exp_r < InpMinExpectancyR)
      return false;

   candidate.score = candidate.exp_r * session_weight * candidate.boost * (1.0 + 0.25 * MathAbs(g_imbalance));
   return true;
}

void Offer(Signal &best, const int strategy, const int side, const double sl, const double tp,
           const double prior, const double boost, const double session_weight, const MqlTick &quote)
{
   Signal candidate;
   ZeroMemory(candidate);
   candidate.strategy = strategy;
   candidate.side = side;
   candidate.sl_dist = sl;
   candidate.tp_dist = tp;
   candidate.prior = prior;
   candidate.boost = boost;
   if(!RateSignal(candidate, quote, session_weight))
   {
      g_signal_state[strategy] = "COST/EXPECTANCY";
      return;
   }
   g_signal_state[strategy] = "PASS";
   if(best.side == 0 || candidate.score > best.score)
      best = candidate;
}

void BestSignal(const MqlTick &quote, const datetime now, Signal &best)
{
   ZeroMemory(best);
   double atr = g_atr[0];
   double base_sl = atr * InpSL_ATR_Multiplier;
   double base_tp = atr * InpTP_ATR_Multiplier;
   MqlDateTime dt;
   TimeToStruct(now, dt);
   double session_weight = 0.92;
   if((dt.hour >= 8 && dt.hour <= 11) || (dt.hour >= 13 && dt.hour <= 18))
      session_weight = 1.18;
   else if(dt.hour >= 19 && dt.hour <= 21)
      session_weight = 1.02;

   bool fast_ticks = g_ticks_per_sec >= InpMinTickVelocity;
   bool up = g_fast[0] > g_slow[0];
   bool down = g_fast[0] < g_slow[0];
   bool bull = g_m1[0].close > g_m1[0].open;
   bool bear = g_m1[0].close < g_m1[0].open;

   for(int s = 0; s < STRAT_COUNT; ++s)
   {
      if(!g_enabled[s] || IsSuspended(s, now))
      {
         g_signal_state[s] = g_enabled[s] ? "SUSPENDED" : "OFF";
         continue;
      }
      g_signal_state[s] = "NO SETUP";
      switch(s)
      {
         case STRAT_A0_MOMENTUM:
         {
            if(!fast_ticks)
            {
               g_signal_state[s] = "LOW TICK RATE";
               break;
            }
            double probability = 0.58 + MathMin(0.10, MathAbs(g_imbalance) * 0.12);
            double boost = g_trending ? 1.15 : 1.0;
            if(up && quote.ask > g_fast[0] && g_trend5 > 0 && g_trendH >= 0 &&
               g_imbalance >= 0.22 && g_velocity > 0 && g_rsi[0] > 52 && g_rsi[0] < 78)
               Offer(best, s, 1, base_sl, base_tp, probability, boost, session_weight, quote);
            else if(down && quote.bid < g_fast[0] && g_trend5 < 0 && g_trendH <= 0 &&
                    g_imbalance <= -0.22 && g_velocity < 0 && g_rsi[0] < 48 && g_rsi[0] > 22)
               Offer(best, s, -1, base_sl, base_tp, probability, boost, session_weight, quote);
            break;
         }
         case STRAT_A1_LIQ_SWEEP:
         {
            if(!g_has_swing)
            {
               g_signal_state[s] = "WAIT M15 HISTORY";
               break;
            }
            double boost = g_ranging ? 1.18 : 1.04;
            if(g_m1[0].low < g_swing_low && bull && g_m1[0].close - g_m1[0].low > atr * 0.65 && g_imbalance >= 0.20)
            {
               double wick_sl = MathMax(atr * 1.25, quote.ask - g_m1[0].low + atr * 0.25);
               Offer(best, s, 1, wick_sl, wick_sl * 1.85, 0.60, boost, session_weight, quote);
            }
            else if(g_m1[0].high > g_swing_high && bear && g_m1[0].high - g_m1[0].close > atr * 0.65 && g_imbalance <= -0.20)
            {
               double wick_sl = MathMax(atr * 1.25, g_m1[0].high - quote.bid + atr * 0.25);
               Offer(best, s, -1, wick_sl, wick_sl * 1.85, 0.60, boost, session_weight, quote);
            }
            break;
         }
         case STRAT_A2_MEAN_REV:
         {
            double boost = g_ranging ? 1.18 : 1.0;
            double stop = atr * 1.30;
            if(g_m1[0].low <= g_lower[0] && g_m1[0].close > g_lower[0] && g_rsi[0] < 32 && g_imbalance >= 0.14)
               Offer(best, s, 1, stop, MathMax(stop * 1.65, g_middle[0] - quote.ask), 0.61, boost, session_weight, quote);
            else if(g_m1[0].high >= g_upper[0] && g_m1[0].close < g_upper[0] && g_rsi[0] > 68 && g_imbalance <= -0.14)
               Offer(best, s, -1, stop, MathMax(stop * 1.65, quote.bid - g_middle[0]), 0.61, boost, session_weight, quote);
            break;
         }
         case STRAT_A3_VOL_EXPL:
         {
            if(!fast_ticks || g_atr[0] <= g_atr[1] * 1.03 || g_m1[0].high - g_m1[0].low <= atr * 1.20)
               break;
            if(g_m1[0].close > g_upper[0] && g_m1[1].close <= g_upper[1] && g_imbalance >= 0.22)
               Offer(best, s, 1, atr * 1.40, atr * 2.35, 0.57, 1.12, session_weight, quote);
            else if(g_m1[0].close < g_lower[0] && g_m1[1].close >= g_lower[1] && g_imbalance <= -0.22)
               Offer(best, s, -1, atr * 1.40, atr * 2.35, 0.57, 1.12, session_weight, quote);
            break;
         }
         case STRAT_A4_TREND_IMP:
         {
            if(up && g_m1[1].low <= g_fast[1] && g_m1[0].close > g_fast[0] && bull && g_imbalance >= 0.16)
               Offer(best, s, 1, base_sl, base_tp, 0.59, 1.08, session_weight, quote);
            else if(down && g_m1[1].high >= g_fast[1] && g_m1[0].close < g_fast[0] && bear && g_imbalance <= -0.16)
               Offer(best, s, -1, base_sl, base_tp, 0.59, 1.08, session_weight, quote);
            break;
         }
         case STRAT_A5_INST_PULLBACK:
         {
            if(!fast_ticks || g_adx < 17)
               break;
            if(g_trend5 > 0 && up && g_m1[0].low <= g_slow[0] && g_m1[0].close > g_slow[0] &&
               g_rsi[0] >= 42 && g_rsi[0] <= 66 && g_imbalance >= 0.18 && g_velocity > 0)
            {
               double stop = MathMax(atr * 1.25, quote.ask - g_m1[0].low + atr * 0.25);
               Offer(best, s, 1, stop, stop * 1.95, 0.61, 1.18, session_weight, quote);
            }
            else if(g_trend5 < 0 && down && g_m1[0].high >= g_slow[0] && g_m1[0].close < g_slow[0] &&
                    g_rsi[0] >= 34 && g_rsi[0] <= 58 && g_imbalance <= -0.18 && g_velocity < 0)
            {
               double stop = MathMax(atr * 1.25, g_m1[0].high - quote.bid + atr * 0.25);
               Offer(best, s, -1, stop, stop * 1.95, 0.61, 1.18, session_weight, quote);
            }
            break;
         }
      }
   }
}

bool QuoteIsFresh(const MqlTick &quote, const datetime now)
{
   return quote.bid > 0.0 && quote.ask >= quote.bid && quote.time > 0 &&
      now - quote.time <= InpMaxTickAgeSeconds;
}

bool EntryEnvironment(const MqlTick &quote, const datetime now)
{
   if(!TradesAllowed())
   {
      Status("ALGO TRADING DISABLED / REAL ACCOUNT LOCKED");
      return false;
   }
   if(!QuoteIsFresh(quote, now))
   {
      Status("STALE OR INVALID QUOTE");
      return false;
   }
   MqlDateTime dt;
   TimeToStruct(now, dt);
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   if(InpAvoidGoldRollover && base == "XAU" &&
      ((dt.hour == 23 && dt.min >= 55) || dt.hour == 0 || (dt.hour == 1 && dt.min <= 5)))
   {
      Status("GOLD ROLLOVER");
      return false;
   }
   if(InpUseSessionFilter)
   {
      bool allowed = InpSessionStartHour <= InpSessionEndHour ?
                     dt.hour >= InpSessionStartHour && dt.hour <= InpSessionEndHour :
                     dt.hour >= InpSessionStartHour || dt.hour <= InpSessionEndHour;
      if(!allowed)
      {
         Status("OUTSIDE SERVER SESSION");
         return false;
      }
   }
   double spread = quote.ask - quote.bid;
   if((InpMaxSpreadPips > 0 && spread / (_Point * PipScale()) > InpMaxSpreadPips) ||
      spread / g_atr[0] > InpMaxSpreadATR_Ratio)
   {
      Status(StringFormat("SPREAD FILTER | %.2f ATR", spread / g_atr[0]));
      return false;
   }
   return true;
}

bool CalculateExposure(double &local, double &portfolio)
{
   local = 0.0;
   portfolio = 0.0;
   const bool account_cap = InpMaxPortfolioRiskPct > 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(PositionGetTicket(i) == 0)
         return false;
      bool own = OwnPosition();
      if(!own && !account_cap)
         continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      double stop = PositionGetDouble(POSITION_SL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double current = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_ORDER_TYPE side = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double pnl;
      if(!CalcCash(side, symbol, volume, current, stop, pnl))
         return false;
      double risk = MathMax(0.0, -pnl);
      if(own)
         local += risk;
      portfolio += risk;
   }

   if(!account_cap)
      return true;
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      if(OrderGetTicket(i) == 0)
         return false;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      ENUM_ORDER_TYPE side = ORDER_TYPE_BUY;
      if(type == ORDER_TYPE_SELL || type == ORDER_TYPE_SELL_LIMIT ||
         type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_STOP_LIMIT)
         side = ORDER_TYPE_SELL;
      else if(type != ORDER_TYPE_BUY && type != ORDER_TYPE_BUY_LIMIT &&
              type != ORDER_TYPE_BUY_STOP && type != ORDER_TYPE_BUY_STOP_LIMIT)
         return false;
      double price = OrderGetDouble(ORDER_PRICE_OPEN);
      if(type == ORDER_TYPE_BUY_STOP_LIMIT || type == ORDER_TYPE_SELL_STOP_LIMIT)
         price = side == ORDER_TYPE_BUY ? MathMax(price, OrderGetDouble(ORDER_PRICE_STOPLIMIT)) :
                                         MathMin(price, OrderGetDouble(ORDER_PRICE_STOPLIMIT));
      double pnl;
      if(!CalcCash(side, OrderGetString(ORDER_SYMBOL), OrderGetDouble(ORDER_VOLUME_CURRENT),
                   price, OrderGetDouble(ORDER_SL), pnl))
         return false;
      portfolio += MathMax(0.0, -pnl);
   }
   return true;
}

double AdaptiveRisk(const int strategy)
{
   if(!InpUseAdaptiveSelfOpt || g_stats[strategy].count < InpMinTradesForAdapt)
      return 1.0;
   if(g_stats[strategy].mean_r < -0.10)
      return 0.72;
   if(InpAllowAdaptiveRiskIncrease)
   {
      if(g_stats[strategy].mean_r > 0.25) return 1.22;
      if(g_stats[strategy].mean_r > 0.10) return 1.10;
   }
   return 1.0;
}

double DirectionalVolumeRoom(const ENUM_ORDER_TYPE side)
{
   double limit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(limit <= 0)
      return DBL_MAX;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!PositionGetTicket(i) || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if(buy == (side == ORDER_TYPE_BUY))
         limit -= PositionGetDouble(POSITION_VOLUME);
   }
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      if(!OrderGetTicket(i) || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      bool buy = type == ORDER_TYPE_BUY || type == ORDER_TYPE_BUY_LIMIT ||
                 type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_STOP_LIMIT;
      if(buy == (side == ORDER_TYPE_BUY))
         limit -= OrderGetDouble(ORDER_VOLUME_CURRENT);
   }
   return MathMax(0.0, limit);
}

bool SetFilling(MqlTradeRequest &request)
{
   long execution = SymbolInfoInteger(request.symbol, SYMBOL_TRADE_EXEMODE);
   long modes = SymbolInfoInteger(request.symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_IOC) != 0)
      request.type_filling = ORDER_FILLING_IOC;
   else if((modes & SYMBOL_FILLING_FOK) != 0 ||
           execution == SYMBOL_TRADE_EXECUTION_INSTANT || execution == SYMBOL_TRADE_EXECUTION_REQUEST)
      request.type_filling = ORDER_FILLING_FOK;
   else if(execution != SYMBOL_TRADE_EXECUTION_MARKET)
      request.type_filling = ORDER_FILLING_RETURN;
   else
      return false;
   return true;
}

bool IsAccepted(const uint retcode)
{
   return retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL || retcode == TRADE_RETCODE_PLACED;
}

bool IsAmbiguous(const uint retcode)
{
   return retcode == 0 || retcode == TRADE_RETCODE_TIMEOUT ||
          retcode == TRADE_RETCODE_CONNECTION || retcode == TRADE_RETCODE_ERROR;
}

void TradeLog(const string action, const MqlTradeResult &result)
{
   PrintFormat("MIDAS VX [%s] %s | ret=%u order=%I64u deal=%I64u vol=%.8f %s",
               _Symbol, action, result.retcode, result.order, result.deal, result.volume, result.comment);
}

void RecordSlippage(const int side, const double requested, const double filled)
{
   if(requested <= 0.0 || filled <= 0.0)
      return;
   double adverse = MathMax(0.0, side * (filled - requested));
   g_slippage = MathMax(InpBaseSlippagePips * PipScale() * _Point, 0.85 * g_slippage + 0.15 * adverse);
}

bool ClearPending()
{
   if(!PutState(g_scope_key + ".flight", 0.0))
      return false;
   g_cached_pending = 0;
   GlobalVariablesFlush();
   return true;
}

bool FinalOrderState(const long state)
{
   return state == ORDER_STATE_FILLED || state == ORDER_STATE_CANCELED ||
          state == ORDER_STATE_REJECTED || state == ORDER_STATE_EXPIRED;
}

bool RestoreFlight(const datetime now)
{
   datetime bar = (datetime)State(g_scope_key + ".flight");
   if(bar <= 0)
      return true;
   if(HasScopedOrders())
      return false;
   // An accepted order with a stable ticket can be reconciled across callbacks.
   // After a restart, use the scoped signal tag to find this exact order.
   bool settled = g_cached_pending > 0 && HistoryOrderSelect(g_cached_pending) &&
                  FinalOrderState(HistoryOrderGetInteger(g_cached_pending, ORDER_STATE));
   if(!settled && HistorySelect(bar, now + 60))
   {
      string tag = SignalTag((int)State(g_scope_key + ".strategy"), bar);
      int sequence = (int)State(g_scope_key + ".slice");
      tag += "|" + IntegerToString(sequence);
      int size = HistoryOrdersTotal();
      for(int i = size - 1; i >= 0; --i)
      {
         ulong order = HistoryOrderGetTicket(i);
         if(order > 0 && HistoryOrderGetString(order, ORDER_SYMBOL) == _Symbol &&
            (ulong)HistoryOrderGetInteger(order, ORDER_MAGIC) == InpMagicNumber &&
            HistoryOrderGetString(order, ORDER_COMMENT) == tag &&
            FinalOrderState(HistoryOrderGetInteger(order, ORDER_STATE)))
         {
            settled = true;
            break;
         }
      }
   }
   if(settled)
      return ClearPending();
   if(InpExecutionRecoveryToken > (int)State(g_scope_key + ".recovery") && now > bar + 60)
   {
      if(!PutState(g_scope_key + ".recovery", InpExecutionRecoveryToken))
         return false;
      Print("MIDAS VX: unresolved execution lock manually reset");
      return ClearPending();
   }
   return false;
}

bool MeetsMarginFloor(const MqlTradeCheckResult &check)
{
   return (check.retcode == 0 || check.retcode == TRADE_RETCODE_DONE) &&
          check.equity > 0.0 && check.margin_free >= 0.0 &&
          (check.margin <= 0.0 || check.margin_level >= InpMinMarginLevelPct);
}

// Per-tranche quote, budget, stop, filling and projected margin validation.
bool PrepareEntry(const Signal &signal, const datetime now, const double remaining,
                  MqlTradeRequest &request, double &reserved)
{
   ZeroMemory(request);
   reserved = 0.0;
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol, quote) || !EntryEnvironment(quote, now))
      return false;
   if(!BuildStops(signal, quote, request.price, request.sl, request.tp))
   {
      Status("BROKER STOP GRID UNAVAILABLE");
      return false;
   }

   request.action = TRADE_ACTION_DEAL;
   request.magic = InpMagicNumber;
   request.symbol = _Symbol;
   request.type = SignalOrderType(signal.side);
   request.deviation = InpSlippageDeviation;
   if(!SetFilling(request))
   {
      Status("NO BROKER FILLING MODE");
      return false;
   }

   double local, portfolio;
   if(!CalculateExposure(local, portfolio))
   {
      Status("OPEN RISK UNPRICEABLE OR MISSING SL");
      return false;
   }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double budget = MathMin(remaining, equity * InpMaxCumulativeRiskPct / 100.0 - local);
   if(InpMaxPortfolioRiskPct > 0)
      budget = MathMin(budget, equity * InpMaxPortfolioRiskPct / 100.0 - portfolio);
   double daily_room = equity - g_day_equity * (1.0 - g_daily_limit / 100.0);
   double cycle_room = equity - g_cycle_anchor * (1.0 - g_cycle_limit / 100.0);
   budget = MathMin(budget, MathMin(daily_room, cycle_room) - portfolio);
   if(budget <= 0)
   {
      Status("OPEN RISK CAP");
      return false;
   }

   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double entry_allowance = MathMax(g_slippage, InpSlippageDeviation * _Point);
   double worst_entry = request.price + signal.side * entry_allowance;
   double worst_exit = request.sl - signal.side * g_slippage;
   double loss;
   if(!CalcCash(request.type, _Symbol, min_volume, worst_entry, worst_exit, loss) || loss >= 0.0)
   {
      Status("CANNOT PRICE RISK AT SL");
      return false;
   }
   double loss_per_lot = -loss / min_volume + g_commission;
   double directional_room = DirectionalVolumeRoom(request.type);
   double raw = MathMin(budget / loss_per_lot, MathMin(max_volume, directional_room));
   double wanted = RoundVolume(raw);
   if(wanted < min_volume && InpAllowMinLotFloor &&
      min_volume <= max_volume && min_volume <= directional_room &&
      min_volume * loss_per_lot <= budget)
      wanted = min_volume; // Only for rounding at broker minimum.

   if(wanted < min_volume || wanted * loss_per_lot > budget + 1e-8)
   {
      Status(StringFormat("MIN LOT BLOCK | risk %.2f / budget %.2f", min_volume * loss_per_lot, budget));
      return false;
   }

   double margin_used = AccountInfoDouble(ACCOUNT_MARGIN);
   if(margin_used > 0 && 100.0 * equity / margin_used < InpMinMarginLevelPct)
   {
      Status("CURRENT MARGIN LEVEL BELOW FLOOR");
      return false;
   }

   // OrderCheck uses the actual request. If needed, search for an affordable
   // broker volume; every probe is rounded down on the symbol's volume grid.
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      return false;
   MqlTradeCheckResult check = {};
   request.volume = wanted;
   if(OrderCheck(request, check) && MeetsMarginFloor(check))
   {
      reserved = request.volume * loss_per_lot;
      return true;
   }
   if(check.retcode != 0 && check.retcode != TRADE_RETCODE_NO_MONEY && check.retcode != TRADE_RETCODE_DONE)
   {
      Status(StringFormat("ORDER CHECK %u %s", check.retcode, check.comment));
      return false;
   }
   long low = (long)MathCeil(min_volume / step - 1e-8);
   long high = (long)MathFloor((wanted - step) / step + 1e-8);
   long best = 0;
   while(low <= high)
   {
      long mid = low + (high - low) / 2;
      request.volume = RoundVolume((double)mid * step);
      ZeroMemory(check);
      if(OrderCheck(request, check) && MeetsMarginFloor(check))
      {
         best = mid;
         low = mid + 1;
      }
      else if(check.retcode == 0 || check.retcode == TRADE_RETCODE_NO_MONEY || check.retcode == TRADE_RETCODE_DONE)
         high = mid - 1;
      else
         break;
   }
   if(best == 0)
   {
      Status(StringFormat("PROJECTED MARGIN BLOCK | %u %s", check.retcode, check.comment));
      return false;
   }
   request.volume = RoundVolume((double)best * step);
   reserved = request.volume * loss_per_lot;
   return true;
}

bool StartFlight(const int strategy, const int slice)
{
   if(!PutState(g_scope_key + ".bar", (double)g_bar) ||
      !PutState(g_scope_key + ".entry", (double)ServerNow()) ||
      !PutState(g_scope_key + ".strategy", strategy) ||
      !PutState(g_scope_key + ".slice", slice) ||
      !PutState(g_scope_key + ".flight", (double)g_bar))
      return false;
   GlobalVariablesFlush();
   return true;
}

void ExecuteSignal(const Signal &signal)
{
   if(!LockAccount())
   {
      Status("ACCOUNT EXECUTION BUSY");
      return;
   }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double capital = InpUseEquityCompounding ? equity : MathMin(equity, AccountInfoDouble(ACCOUNT_BALANCE));
   double remaining = capital * MathMin(4.0, g_risk_pct * AdaptiveRisk(signal.strategy)) / 100.0;
   for(int tranche = 1; tranche <= InpMaxTranchesPerSignal && remaining > 0; ++tranche)
   {
      datetime instant = ServerNow();
      if(!UpdateGuards(instant) || g_day_locked || g_cycle_locked || HasScopedOrders() ||
         !RestoreFlight(instant) || iTime(_Symbol, PERIOD_M1, 0) != g_bar)
         break;
      if(tranche == 1 &&
         ((datetime)State(g_scope_key + ".bar") == g_bar ||
          instant - (datetime)State(g_scope_key + ".entry") < InpReEntryCooldownSec ||
          CountSignals() >= InpMaxOpenSignalsSymbol))
         break;

      MqlTradeRequest request;
      double reserved;
      if(!PrepareEntry(signal, instant, remaining, request, reserved))
         break;
      request.comment = SignalTag(signal.strategy, g_bar) + "|" + IntegerToString(tranche);
      if(!StartFlight(signal.strategy, tranche))
      {
         Status("CANNOT PERSIST EXECUTION INTENT");
         break;
      }
      MqlTradeResult result = {};
      bool sent = OrderSend(request, result);
      TradeLog("ENTRY " + request.comment, result);
      if(IsAmbiguous(result.retcode) || result.retcode == TRADE_RETCODE_PLACED)
      {
         g_cached_pending = result.order;
         Status("AWAITING ORDER RECONCILIATION");
         break;
      }
      if(!sent || !IsAccepted(result.retcode))
      {
         ClearPending();
         Status(StringFormat("ENTRY REJECTED %u %s", result.retcode, result.comment));
         break;
      }
      if(result.retcode == TRADE_RETCODE_DONE_PARTIAL && HasScopedOrders())
      {
         g_cached_pending = result.order;
         Status("PARTIAL FILL | CHECKING REMAINDER");
         break;
      }
      if(result.deal == 0 || !HistoryDealSelect(result.deal))
      {
         g_cached_pending = result.order;
         Status("AWAITING FILL HISTORY");
         break;
      }
      double actual_volume = HistoryDealGetDouble(result.deal, DEAL_VOLUME);
      double filled = HistoryDealGetDouble(result.deal, DEAL_PRICE);
      RecordSlippage(signal.side, request.price, filled);
      ulong id = (ulong)HistoryDealGetInteger(result.deal, DEAL_POSITION_ID);
      if(id > 0 && PositionById(id))
         LoadOpenRecord(id);
      QueuePosition(id);
      Status(StringFormat("FILL %s tranche %d | deal %.8f | score %.2fR",
                         StrategyCode(signal.strategy), tranche, actual_volume, signal.exp_r));
      if(!ClearPending())
         break;
      // Reserve the entire submitted tranche. An IOC partial is never topped up.
      remaining -= reserved;
      if(result.retcode == TRADE_RETCODE_DONE_PARTIAL)
         break;
      // A smaller slice may be the broker's margin limit. Only continue after
      // a max-size fill, with a new quote and all caps recalculated.
      if(request.volume + 1e-8 < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX))
         break;
   }
   UnlockAccount();
}

bool CloseVolume(const ulong ticket, const double volume, const MqlTick &quote, MqlTradeResult &result)
{
   ZeroMemory(result);
   if(!PositionSelectByTicket(ticket) || !OwnPosition())
      return false;

   MqlTradeRequest request = {};
   request.action = TRADE_ACTION_DEAL;
   request.magic = InpMagicNumber;
   request.position = ticket;
   request.symbol = _Symbol;
   bool buy_position = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   request.type = buy_position ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = buy_position ? quote.bid : quote.ask;
   request.volume = MathMin(volume, PositionGetDouble(POSITION_VOLUME));
   request.deviation = InpSlippageDeviation;
   request.comment = "MVX82 exit";
   if(!SetFilling(request) || request.volume <= 0.0)
   {
      result.retcode = TRADE_RETCODE_INVALID_FILL;
      return false;
   }

   bool sent = OrderSend(request, result);
   TradeLog("EXIT", result);
   if(IsAccepted(result.retcode) && result.deal > 0 && HistoryDealSelect(result.deal))
   {
      RecordSlippage(buy_position ? -1 : 1, request.price, HistoryDealGetDouble(result.deal, DEAL_PRICE));
      QueuePosition((ulong)HistoryDealGetInteger(result.deal, DEAL_POSITION_ID));
   }
   return sent && IsAccepted(result.retcode);
}

void CancelEntryOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; --i)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OwnOrder())
         continue;
      long order_type = OrderGetInteger(ORDER_TYPE);
      ulong position_id = (ulong)OrderGetInteger(ORDER_POSITION_ID);
      if((order_type == ORDER_TYPE_BUY || order_type == ORDER_TYPE_SELL) &&
         position_id > 0 && PositionById(position_id))
      {
         bool is_buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
         if(is_buy != (order_type == ORDER_TYPE_BUY))
            continue; // Leave an in-flight close request alone.
      }

      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_REMOVE;
      request.magic = InpMagicNumber;
      request.order = ticket;
      request.symbol = _Symbol;
      if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
         TradeLog("CANCEL RETRY", result);
   }
}

datetime g_last_liquidation = 0;
datetime g_last_time_exit = 0;

bool SaveLiquidation(const bool active)
{
   if(!PutState(g_scope_key + ".flat", active ? 1.0 : 0.0))
      return false;
   GlobalVariablesFlush();
   return true;
}

bool RunGuards(const datetime now, const MqlTick &quote, const bool reconcile)
{
   if(!LockAccount())
      return false;
   bool good = UpdateGuards(now);
   if(good)
   {
      bool needs_flat = State(g_scope_key + ".flat") > 0;
      if(!needs_flat && g_breach_at > 0)
      {
         // Pick up exposure left on a chart that was offline at the breach.
         for(int i = PositionsTotal() - 1; i >= 0; --i)
            if(PositionGetTicket(i) > 0 && OwnPosition() &&
               PositionGetInteger(POSITION_TIME) <= (long)g_breach_at)
               needs_flat = true;
         for(int i = OrdersTotal() - 1; i >= 0; --i)
            if(OrderGetTicket(i) > 0 && OwnOrder() &&
               OrderGetInteger(ORDER_TIME_SETUP) <= (long)g_breach_at)
               needs_flat = true;
      }
      bool scoped_exposure = CountPositions() > 0 || HasScopedOrders();
      if((g_day_locked || g_cycle_locked || g_local_close) && scoped_exposure)
         needs_flat = true;

      g_liquidating = needs_flat && scoped_exposure;
      if(g_liquidating && State(g_scope_key + ".flat") == 0)
         good = SaveLiquidation(true);
      if(!scoped_exposure)
      {
         g_local_close = false;
         if(State(g_scope_key + ".flat") > 0)
            good = SaveLiquidation(false);
      }

      if(g_liquidating && TradesAllowed() && now != g_last_liquidation)
      {
         g_last_liquidation = now;
         CancelEntryOrders();
         if(!HasScopedOrders() && QuoteIsFresh(quote, now))
         {
            for(int i = PositionsTotal() - 1; i >= 0; --i)
            {
               ulong ticket = PositionGetTicket(i);
               if(ticket == 0 || !OwnPosition())
                  continue;
               MqlTradeResult result;
               CloseVolume(ticket, PositionGetDouble(POSITION_VOLUME), quote, result);
               if(HasScopedOrders() || IsAmbiguous(result.retcode))
                  break;
            }
         }
      }
   }
   if(reconcile && State(g_scope_key + ".flight") > 0.0)
      RestoreFlight(now);
   UnlockAccount();
   if(!good)
      Status("EQUITY STATE UNAVAILABLE");
   else if(g_liquidating)
      Status("LIQUIDATION PENDING | RETRY UNTIL FLAT");
   else if(g_day_locked)
      Status("DAILY LOSS LOCK | NEXT SERVER DAY");
   else if(g_cycle_locked)
      Status("CYCLE DD LOCK | FLATTEN + RESET TOKEN");
   return good && !g_liquidating && !g_day_locked && !g_cycle_locked;
}

bool ModifyStop(const ulong ticket, const double new_sl, const double current_tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   request.action = TRADE_ACTION_SLTP;
   request.magic = InpMagicNumber;
   request.position = ticket;
   request.symbol = _Symbol;
   request.sl = new_sl;
   request.tp = current_tp;
   bool sent = OrderSend(request, result);
   if(!sent || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_NO_CHANGES))
   {
      TradeLog("SL MODIFY REJECTED", result);
      return false;
   }
   return PositionSelectByTicket(ticket) &&
          MathAbs(PositionGetDouble(POSITION_SL) - new_sl) < TickSize() * 0.5;
}

void ManagePositions(const MqlTick &quote, const datetime now, const bool dynamic_exit, const bool timed_exit)
{
   if(!TradesAllowed() || !QuoteIsFresh(quote, now) || HasScopedOrders())
      return;
   double tick_size = TickSize();
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double broker_dist = MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point + tick_size;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !OwnPosition())
         continue;
      ulong id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double price = buy ? quote.bid : quote.ask;
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);

      if(timed_exit && (sl <= 0.0 || (InpMaxHoldSeconds > 0 && now - opened >= InpMaxHoldSeconds)))
      {
         MqlTradeResult result;
         CloseVolume(ticket, volume, quote, result);
         if(HasScopedOrders() || IsAmbiguous(result.retcode))
            break;
         continue;
      }
      if(!dynamic_exit || sl <= 0.0 || tick_size <= 0.0)
         continue;

      int index = LoadOpenRecord(id);
      if(index < 0 || g_open[index].distance <= 0)
         continue;
      double rr = (buy ? price - entry : entry - price) / g_open[index].distance;
      bool reversal = buy ? g_imbalance <= -0.58 && g_velocity < 0.0 :
                            g_imbalance >= 0.58 && g_velocity > 0.0;
      if(InpUseMomentumExit && rr >= 0.55 && reversal)
      {
         MqlTradeResult result;
         CloseVolume(ticket, volume, quote, result);
         if(HasScopedOrders() || IsAmbiguous(result.retcode))
            break;
         continue;
      }

      double desired_sl = sl;
      if(InpUseEarlyBreakeven && rr >= InpBreakevenRR)
      {
         double buffer = MathMax(2.0 * _Point, (quote.ask - quote.bid) * 0.25);
         double be_sl = RoundPrice(buy ? entry + buffer : entry - buffer, buy);
         bool valid = buy ? price - be_sl >= broker_dist : be_sl - price >= broker_dist;
         if(valid)
            desired_sl = buy ? MathMax(desired_sl, be_sl) : MathMin(desired_sl, be_sl);
      }
      if(InpUseTrailingStop && rr >= InpTrailActivationRR)
      {
         double distance = MathMax(broker_dist, g_atr[0] * InpTrailStepATR);
         double trail_sl = RoundPrice(buy ? price - distance : price + distance, !buy);
         desired_sl = buy ? MathMax(desired_sl, trail_sl) : MathMin(desired_sl, trail_sl);
      }
      if(desired_sl > 0.0 && (buy ? desired_sl - sl : sl - desired_sl) >= tick_size * 0.5)
         ModifyStop(ticket, desired_sl, tp);

      if(!InpUsePartialClose || rr < InpPartialCloseRR || g_open[index].had_exit ||
         g_open[index].uncertain_partial)
         continue;
      double close_volume = RoundVolume(volume * InpPartialClosePct / 100.0);
      if(close_volume < min_volume || volume - close_volume + 1e-8 < min_volume)
         continue;
      string key = g_scope_key + ".p" + IntegerToString((long)id);
      if(!PutState(key, 1.0))
         continue;
      GlobalVariablesFlush();
      g_open[index].uncertain_partial = true;
      MqlTradeResult result;
      CloseVolume(ticket, close_volume, quote, result);
      if(IsAccepted(result.retcode))
      {
         if(PositionSelectByTicket(ticket) && PositionGetDouble(POSITION_VOLUME) < volume - 1e-8)
            g_open[index].had_exit = true;
         if(HasScopedOrders() || result.retcode == TRADE_RETCODE_PLACED)
            break;
      }
      else if(IsAmbiguous(result.retcode))
         break;
      else if(GlobalVariableDel(key))
         g_open[index].uncertain_partial = false;
   }
}

void Label(const string name, const int x, const int y, const string caption, const color ink, const int font_size)
{
   string object = HUD_PREFIX + name;
   if(ObjectFind(0, object) < 0)
   {
      if(!ObjectCreate(0, object, OBJ_LABEL, 0, 0, 0))
         return;
      ObjectSetInteger(0, object, OBJPROP_XDISTANCE, InpPanelX + x);
      ObjectSetInteger(0, object, OBJPROP_YDISTANCE, InpPanelY + y);
      ObjectSetInteger(0, object, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, object, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, object, OBJPROP_FONTSIZE, font_size);
   }
   ObjectSetInteger(0, object, OBJPROP_COLOR, ink);
   ObjectSetString(0, object, OBJPROP_TEXT, caption);
}

void Button(const string name, const int x, const int y, const int width, const string caption, const color background)
{
   string object = HUD_PREFIX + name;
   if(ObjectFind(0, object) < 0)
   {
      if(!ObjectCreate(0, object, OBJ_BUTTON, 0, 0, 0))
         return;
      ObjectSetInteger(0, object, OBJPROP_XDISTANCE, InpPanelX + x);
      ObjectSetInteger(0, object, OBJPROP_YDISTANCE, InpPanelY + y);
      ObjectSetInteger(0, object, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, object, OBJPROP_YSIZE, 21);
      ObjectSetInteger(0, object, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, object, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, object, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, object, OBJPROP_FONT, "Consolas");
   }
   ObjectSetInteger(0, object, OBJPROP_BGCOLOR, background);
   ObjectSetString(0, object, OBJPROP_TEXT, caption);
}

void DrawHud(const bool force = false)
{
   if(!g_use_hud)
      return;
   ulong now_ms = GetTickCount64();
   if(!force && now_ms - g_last_hud_ms < 250)
      return;
   g_last_hud_ms = now_ms;

   string background = HUD_PREFIX + "background";
   if(ObjectFind(0, background) < 0)
   {
      ObjectCreate(0, background, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, background, OBJPROP_XDISTANCE, InpPanelX);
      ObjectSetInteger(0, background, OBJPROP_YDISTANCE, InpPanelY);
      ObjectSetInteger(0, background, OBJPROP_XSIZE, 426);
      ObjectSetInteger(0, background, OBJPROP_YSIZE, 270);
      ObjectSetInteger(0, background, OBJPROP_BGCOLOR, C'11,15,22');
      ObjectSetInteger(0, background, OBJPROP_SELECTABLE, false);
   }
   color cyan = C'0,212,255';
   color neutral = C'241,245,249';
   color off = C'28,36,51';
   Label("title", 10, 8, "MIDAS VX V8.2 | " + _Symbol, cyan, 11);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double day_dd = g_day_equity > 0 ? 100.0 * (g_day_equity - equity) / g_day_equity : 0;
   double cycle_dd = g_cycle_anchor > 0 ? 100.0 * (g_cycle_anchor - equity) / g_cycle_anchor : 0;
   Label("risk", 10, 30, StringFormat("Equity %.2f %s | risk %.2f%% | signals %d/%d", equity,
         AccountInfoString(ACCOUNT_CURRENCY), g_risk_pct, CountSignals(), InpMaxOpenSignalsSymbol), neutral, 8);
   Label("dd", 10, 47, StringFormat("Day DD %.2f/%.1f%% | cycle DD %.2f/%.1f%%",
         MathMax(0.0, day_dd), g_daily_limit, MathMax(0.0, cycle_dd), g_cycle_limit), neutral, 8);
   string regime = g_trending ? "TREND" : (g_ranging ? "RANGE" : "COMPRESSION");
   Label("micro", 10, 64, StringFormat("%s | ticks %.1f/s | imbalance %+.2f", regime, g_ticks_per_sec, g_imbalance), neutral, 8);
   string modes[3] = {"AGGRESSIVE", "SUPER AGGR", "EXTREME"};
   for(int m = 0; m < 3; ++m)
   {
      Button("mode" + IntegerToString(m), 10 + m * 137, 83, 132, modes[m],
             (int)g_risk_mode == m ? C'14,109,132' : off);
   }
   for(int s = 0; s < STRAT_COUNT; ++s)
   {
      int y = 111 + s * 18;
      string id = IntegerToString(s);
      Button("s" + id, 10, y, 42, StrategyCode(s), g_enabled[s] ? C'14,109,95' : off);
      Label("data" + id, 64, y + 2, StringFormat("%3d  %+.2f  %+.2fR  %s", g_stats[s].total,
            g_stats[s].pnl, g_stats[s].mean_r, g_enabled[s] ? g_signal_state[s] : "OFF"), neutral, 8);
   }
   Label("status", 10, 224, StringSubstr(g_status, 0, 62), g_liquidating || g_day_locked || g_cycle_locked ? clrOrange : cyan, 8);
   Button("pause", 10, 242, 132, g_paused ? "RESUME" : "PAUSE ENTRIES", off);
   Button("close", 152, 242, 260, now_ms < g_close_confirm_ms ? "CONFIRM CLOSE THIS PAIR" : "CLOSE THIS PAIR", C'111,35,48');
   ChartRedraw(0);
}

void HandleClick(const string object)
{
   if(!g_use_hud || StringFind(object, HUD_PREFIX) != 0)
      return;
   ObjectSetInteger(0, object, OBJPROP_STATE, false);
   for(int i = 0; i < 3; ++i)
      if(object == HUD_PREFIX + "mode" + IntegerToString(i))
         ApplyRiskMode((ENUM_RISK_MODE)i);

   for(int i = 0; i < STRAT_COUNT; ++i)
      if(object == HUD_PREFIX + "s" + IntegerToString(i))
         g_enabled[i] = !g_enabled[i];

   if(object == HUD_PREFIX + "pause")
   {
      if(PutState(g_scope_key + ".pause", g_paused ? 0.0 : 1.0))
      {
         g_paused = !g_paused;
         GlobalVariablesFlush();
      }
   }
   if(object == HUD_PREFIX + "close")
   {
      ulong now = GetTickCount64();
      if(g_close_confirm_ms > now)
      {
         g_paused = true;
         g_local_close = true;
         g_close_confirm_ms = 0;
         PutState(g_scope_key + ".pause", 1.0);
         SaveLiquidation(true);
      }
      else
         g_close_confirm_ms = now + 4000;
   }
   DrawHud(true);
}

void PollTesterButtons()
{
   if(!g_use_hud || !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   for(int i = 0; i < 3 + STRAT_COUNT + 2; ++i)
   {
      string suffix;
      if(i < 3) suffix = "mode" + IntegerToString(i);
      else if(i < 3 + STRAT_COUNT) suffix = "s" + IntegerToString(i - 3);
      else suffix = i == 3 + STRAT_COUNT ? "pause" : "close";
      string object = HUD_PREFIX + suffix;
      if(ObjectGetInteger(0, object, OBJPROP_STATE) != 0)
         HandleClick(object);
   }
}

bool InputsValid()
{
   return InpMagicNumber > 0 && _Point > 0 &&
      (int)InpRiskMode >= 0 && (int)InpRiskMode <= 2 &&
      InpCustomRiskPct >= 0 && InpCustomRiskPct <= 4 &&
      InpMaxDailyLossPct >= 0 && InpMaxDailyLossPct < 100 &&
      InpMaxCycleDDPct >= 0 && InpMaxCycleDDPct < 100 &&
      InpDDCooldownMinutes >= 1 && InpDDCooldownMinutes <= 1440 &&
      InpCycleResetToken >= 0 && InpExecutionRecoveryToken >= 0 &&
      InpMaxCumulativeRiskPct > 0 && InpMaxCumulativeRiskPct < 100 &&
      InpMaxPortfolioRiskPct >= 0 && InpMaxPortfolioRiskPct < 100 &&
      InpMaxOpenSignalsSymbol > 0 && InpMaxTranchesPerSignal >= 1 && InpMaxTranchesPerSignal <= 8 &&
      InpMinMarginLevelPct >= 100 &&
      InpTickWindow >= 5 && InpTickWindow <= TICK_CAPACITY && InpMinTickVelocity >= 0 &&
      InpCommissionPerLot >= 0 && InpBaseSlippagePips >= 0 && InpMaxSpreadPips >= 0 &&
      InpMaxSpreadATR_Ratio > 0 && InpMaxTickAgeSeconds >= 1 &&
      InpM1_FastEMA > 0 && InpM1_SlowEMA > 0 && InpM1_ATR_Period > 0 && InpM1_RSI_Period > 0 &&
      InpM1_BB_Period > 1 && InpM1_BB_Deviation > 0 &&
      InpM5_FastEMA > 0 && InpM5_SlowEMA > 0 && InpM5_ATR_Period > 0 && InpM5_ADX_Period > 0 &&
      InpM15_SwingLookback >= 5 && InpM15_SwingLookback <= 500 &&
      InpH1_FastEMA > 0 && InpH1_SlowEMA > 0 && InpH1_ADX_Period > 0 &&
      InpSL_ATR_Multiplier > 0 && InpTP_ATR_Multiplier > 0 && InpBreakevenRR > 0 &&
      InpPartialCloseRR > 0 && InpPartialClosePct > 0 && InpPartialClosePct < 100 &&
      InpTrailActivationRR > 0 && InpTrailStepATR > 0 && InpMaxHoldSeconds >= 0 && InpReEntryCooldownSec >= 0 &&
      InpRollingWindowTrades >= 5 && InpRollingWindowTrades <= 100 &&
      InpMinTradesForAdapt >= 5 && InpMinTradesForAdapt <= InpRollingWindowTrades &&
      InpSuspendCooldownMinutes >= 1 && InpSuspendCooldownMinutes <= 1440 &&
      InpHistoryDays >= 1 && InpHistoryDays <= 90 && InpTesterMinTrades >= 1 &&
      InpSessionStartHour >= 0 && InpSessionStartHour <= 23 && InpSessionEndHour >= 0 && InpSessionEndHour <= 23;
}

int OnInit()
{
   if(!InputsValid())
   {
      Print("MIDAS VX: invalid EA inputs");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ||
      AccountInfoInteger(ACCOUNT_FIFO_CLOSE))
   {
      Print("MIDAS VX: independently managed tranches require a non-FIFO MT5 hedging account");
      return INIT_FAILED;
   }
   if(!InpAllowRealAccount && AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_REAL &&
      !MQLInfoInteger(MQL_TESTER))
   {
      Print("MIDAS VX: real account disabled by InpAllowRealAccount");
      return INIT_FAILED;
   }

   string server = AccountInfoString(ACCOUNT_SERVER);
   string scope = _Symbol + "#" + IntegerToString((long)InpMagicNumber);
   g_account_key = StringFormat("M82.%08X.%I64d", TextHash(server), AccountInfoInteger(ACCOUNT_LOGIN));
   string scope_identity = g_account_key + "#" + scope;
   g_scope_key = StringFormat("M82S.%08X%08X", TextHash(scope_identity), TextHash("scope#" + scope_identity));
   string owner = g_scope_key + ".owner";
   if(!GlobalVariableCheck(owner))
      GlobalVariableTemp(owner);
   g_scope_owner = GlobalVariableSetOnCondition(owner, 1.0, 0.0);
   if(!g_scope_owner)
   {
      Print("MIDAS VX: this symbol and magic already have an active instance in this terminal");
      return INIT_FAILED;
   }
   g_paused = State(g_scope_key + ".pause") > 0.0;
   ApplyRiskMode(InpRiskMode);
   g_enabled[0] = InpEnableStratA0_Momentum;
   g_enabled[1] = InpEnableStratA1_LiqSweep;
   g_enabled[2] = InpEnableStratA2_MeanRev;
   g_enabled[3] = InpEnableStratA3_VolExpl;
   g_enabled[4] = InpEnableStratA4_TrendImp;
   g_enabled[5] = InpEnableStratA5_Pullback;
   g_commission = InpCommissionPerLot;
   g_slippage = InpBaseSlippagePips * PipScale() * _Point;

   g_ema1_fast = iMA(_Symbol, PERIOD_M1, InpM1_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ema1_slow = iMA(_Symbol, PERIOD_M1, InpM1_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_atr1 = iATR(_Symbol, PERIOD_M1, InpM1_ATR_Period);
   g_rsi1 = iRSI(_Symbol, PERIOD_M1, InpM1_RSI_Period, PRICE_CLOSE);
   g_bands = iBands(_Symbol, PERIOD_M1, InpM1_BB_Period, 0, InpM1_BB_Deviation, PRICE_CLOSE);
   g_ema5_fast = iMA(_Symbol, PERIOD_M5, InpM5_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_ema5_slow = iMA(_Symbol, PERIOD_M5, InpM5_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_atr5 = iATR(_Symbol, PERIOD_M5, InpM5_ATR_Period);
   g_adx5 = iADX(_Symbol, PERIOD_M5, InpM5_ADX_Period);
   g_emaH_fast = iMA(_Symbol, PERIOD_H1, InpH1_FastEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_emaH_slow = iMA(_Symbol, PERIOD_H1, InpH1_SlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   g_adxH = iADX(_Symbol, PERIOD_H1, InpH1_ADX_Period);

   if(g_ema1_fast == INVALID_HANDLE || g_ema1_slow == INVALID_HANDLE ||
      g_atr1 == INVALID_HANDLE || g_rsi1 == INVALID_HANDLE || g_bands == INVALID_HANDLE ||
      g_ema5_fast == INVALID_HANDLE || g_ema5_slow == INVALID_HANDLE || g_atr5 == INVALID_HANDLE ||
      g_adx5 == INVALID_HANDLE || g_emaH_fast == INVALID_HANDLE || g_emaH_slow == INVALID_HANDLE ||
      g_adxH == INVALID_HANDLE || !EventSetTimer(1))
      return INIT_FAILED;

   g_initialized = true;
   g_use_hud = InpShowDashboardPanel && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
   PrintFormat("MIDAS VX V8.2 ready | %s | magic %I64u", _Symbol, InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   UnlockAccount();
   if(g_scope_owner)
      GlobalVariableSetOnCondition(g_scope_key + ".owner", 0.0, 1.0);
   int handles[12];
   handles[0] = g_ema1_fast; handles[1] = g_ema1_slow; handles[2] = g_atr1;
   handles[3] = g_rsi1; handles[4] = g_bands; handles[5] = g_ema5_fast;
   handles[6] = g_ema5_slow; handles[7] = g_atr5; handles[8] = g_adx5;
   handles[9] = g_emaH_fast; handles[10] = g_emaH_slow; handles[11] = g_adxH;
   for(int i = 0; i < 12; ++i)
      if(handles[i] != INVALID_HANDLE)
         IndicatorRelease(handles[i]);
   if(g_use_hud)
      ObjectsDeleteAll(0, HUD_PREFIX);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
      HandleClick(sparam);
}

void EvaluateEntry(const MqlTick &quote, const datetime now)
{
   if(!g_stats_ready)
   {
      Status("WAITING TO RECONCILE HISTORY");
      return;
   }
   if(g_paused)
   {
      Status("ENTRIES PAUSED");
      return;
   }
   if(HasScopedOrders())
   {
      Status("WAITING FOR SCOPED ORDER");
      return;
   }
   if(State(g_scope_key + ".flight") > 0)
   {
      Status("PENDING EXECUTION RECONCILIATION");
      return;
   }
   if((datetime)State(g_scope_key + ".bar") == g_bar)
   {
      Status("WAIT NEXT M1 BAR");
      return;
   }
   if(now - (datetime)State(g_scope_key + ".entry") < InpReEntryCooldownSec)
   {
      Status("RE-ENTRY COOLDOWN");
      return;
   }
   if(CountSignals() >= InpMaxOpenSignalsSymbol)
   {
      Status("MAX ACTIVE SIGNALS");
      return;
   }
   if(!EntryEnvironment(quote, now))
      return;
   Signal best;
   BestSignal(quote, now, best);
   if(InpDiagnosticLog && g_last_diagnostic_bar != g_bar)
   {
      g_last_diagnostic_bar = g_bar;
      string diagnostics = "";
      for(int i = 0; i < STRAT_COUNT; ++i)
         diagnostics += StrategyCode(i) + "=" + g_signal_state[i] + " ";
      Print("MIDAS VX [", _Symbol, "] ", diagnostics);
   }
   if(best.side == 0)
   {
      Status("NO QUALIFIED SIGNAL | SEE A0-A5");
      return;
   }
   ExecuteSignal(best);
}

void Run(const bool on_tick)
{
   if(!g_initialized)
      return;
   MqlTick quote = {};
   SymbolInfoTick(_Symbol, quote);
   datetime now = ServerNow();
   if(now <= 0)
      return;
   if(!on_tick)
      PollTesterButtons();
   if(!RunGuards(now, quote, !on_tick))
   {
      DrawHud();
      return;
   }

   bool timed_exit = now != g_last_time_exit;
   if(timed_exit)
      g_last_time_exit = now;
   if(!on_tick)
   {
      ManagePositions(quote, now, false, timed_exit);
      if(!g_stats_ready)
         g_stats_ready = BootstrapStats(now);
      if(g_stats_ready)
         ProcessPositionChanges(now);
      DrawHud();
      return;
   }

   if(timed_exit)
      ManagePositions(quote, now, false, true);
   bool mtf_ready = UpdateMtf();
   bool micro_ready = UpdateMicro(quote);
   if(mtf_ready && micro_ready)
      ManagePositions(quote, now, true, false);
   if(ArraySize(g_dirty_ids) > 0 && g_stats_ready)
      ProcessPositionChanges(now);
   if(!mtf_ready)
      Status("WAITING FOR CLOSED MTF BARS");
   else if(!micro_ready)
      Status("WAITING FOR QUOTE TICKS");
   else
      EvaluateEntry(quote, now);
   DrawHud();
}

void OnTimer() { Run(false); }
void OnTick() { Run(true); }

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!g_initialized || trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.symbol != _Symbol)
      return;
   if(trans.deal == 0 || !HistoryDealSelect(trans.deal))
      return;
   ulong id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   QueuePosition(id);
}

double OnTester()
{
   double initial = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double profit = TesterStatistics(STAT_PROFIT);
   double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double trades = TesterStatistics(STAT_TRADES);
   if(initial <= 0 || profit <= 0 || trades < InpTesterMinTrades || pf <= 1.0)
      return 0.0;
   return (100.0 * profit / initial) / MathMax(1.0, drawdown) * MathMin(pf, 3.0);
}
