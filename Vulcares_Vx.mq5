//+------------------------------------------------------------------+
//|                                               Vulcares_Vx_V4.mq5 |
//|                                  Copyright 2026, Vulcares Quant  |
//|      ALWAYS-ACTIVE XAUUSD MTF MOMENTUM & STRUCTURE ENGINE V4.00  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vulcares Quant"
#property link      "https://www.mql5.com"
#property version   "4.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//--- Enumerations
enum ENUM_USER_CONTROL
{
   CTRL_EA_ON               = 0,
   CTRL_EA_OFF              = 1,
   CTRL_SOFT_STOP_REQUESTED = 2,
   CTRL_STOPPED             = 3,
   CTRL_EMERGENCY_LOCKED    = 4
};

enum ENUM_EXEC_STATE
{
   STATE_SCANNING,
   STATE_POSITION_ACTIVE,
   STATE_TRAILING_ACTIVE,
   STATE_STOPPING_AFTER_POS,
   STATE_STOPPED,
   STATE_RISK_LOCKED,
   STATE_EMERGENCY_LOCKED,
   STATE_DISCONNECTED
};

//--- Input Parameters
input group "=== 1. GENERAL & RISK SETTINGS (FLAT 1% RISK) ==="
input ulong    InpMagicNumber             = 20260444;
input bool     InpAllowRealMoneyTrading   = false;   // Set true explicitly for Live Real Account
input double   InpInitialCapital          = 1000.00; // Baseline Capital (USD / USC)
input double   InpFixedRiskPercent        = 1.00;    // Fixed 1.00% Risk per Trade (10.00 on 1000)
input double   InpDailyLossLimitPct       = 5.00;    // Max 5% Daily Loss (50.00)
input double   InpMaxInitialDDPct         = 15.00;   // Max 15% Initial Capital Drawdown (150.00)
input int      InpMaxConsecutiveLosses    = 4;       // Pause after 4 consecutive losses
input int      InpLossCooldownMinutes     = 10;      // Cooldown duration in minutes

input group "=== 2. STRATEGY & EXECUTION (ALWAYS ACTIVE) ==="
input int      InpReEntryDelaySec         = 3;       // Brief 3s pause between closed & next trade
input double   InpSL_ATR_M5_Mult          = 1.80;    // Structural Stop Loss = 1.8x ATR(M5)
input double   InpTP_R_Multiple           = 2.20;    // Target Take Profit = 2.2R
input double   InpMaxSpreadToSLRatio      = 0.25;    // Block entry only if spread > 25% of SL

input group "=== 3. SMART BREATHING TRAILING STOP ==="
input bool     InpEnableTrailing          = true;
input double   InpBreakEvenTriggerR       = 1.00;    // Move to Break-Even after +1.0R profit
input double   InpTrailingStartR          = 1.30;    // Start trailing after +1.3R profit
input double   InpTrailingLockPct         = 0.55;    // Lock 55% of peak floating profit
input int      InpTrailIntervalMs         = 250;     // Trailing update throttle (ms)

input group "=== 4. UI DASHBOARD ==="
input bool     InpShowDashboard           = true;

//--- Persistent State Structure
struct PersistentState
{
   double   initial_capital;
   double   daily_start_balance;
   int      period_year;
   int      period_yday;
   int      consecutive_losses;
   datetime cooldown_until;
   int      user_control;
   bool     hard_dd_locked;
   double   max_fav_net_profit;
   double   last_confirmed_sl;
   int      total_trades;
   int      win_trades;
   int      loss_trades;
   double   gross_profit;
   double   gross_loss;
};

//--- Global Objects
CTrade          g_trade;
CSymbolInfo     g_symbol;
CPositionInfo   g_pos;
COrderInfo      g_ord;

ENUM_EXEC_STATE g_exec_state       = STATE_SCANNING;
PersistentState g_persist;

// Cached Indicator Handles (M1, M5, M15)
int g_hATR_M5     = INVALID_HANDLE;
int g_hEMA_8_M15  = INVALID_HANDLE;
int g_hEMA_21_M15 = INVALID_HANDLE;
int g_hEMA_8_M5   = INVALID_HANDLE;
int g_hEMA_21_M5  = INVALID_HANDLE;
int g_hEMA_9_M1   = INVALID_HANDLE;
int g_hEMA_21_M1  = INVALID_HANDLE;
int g_hRSI_14_M5  = INVALID_HANDLE;

// Runtime Variables
string   g_validated_symbol  = "";
string   g_gv_prefix         = "";
string   g_status_note       = "READY";
double   g_buy_score_pct     = 50.0;
double   g_sell_score_pct    = 50.0;
string   g_last_signal_dir   = "SCANNING";
ulong    g_last_trail_ms     = 0;
datetime g_last_close_time   = 0;
bool     g_dash_minimized    = false;
bool     g_dash_dirty        = true;

#define UI_PFX "VCX4_"

//+------------------------------------------------------------------+
//| Symbol Validation (XAUUSD / GOLD Exclusive)                      |
//+------------------------------------------------------------------+
bool ValidateGoldSymbol(const string sym)
{
   string up = sym;
   StringToUpper(up);
   if(StringFind(up, "XAUUSD") < 0 && StringFind(up, "GOLD") < 0) return false;
   if(StringFind(up, "XAUEUR") >= 0 || StringFind(up, "XAUGBP") >= 0 ||
      StringFind(up, "XAUAUD") >= 0 || StringFind(up, "XAUJPY") >= 0) return false;

   return (SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE) > 0.0 &&
           SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE) > 0.0 &&
           SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE) > 0.0 &&
           SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN) > 0.0);
}

//+------------------------------------------------------------------+
//| Persistent State Management                                      |
//+------------------------------------------------------------------+
void BuildGVPrefix()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string srv = AccountInfoString(ACCOUNT_SERVER);
   StringReplace(srv, " ", "_");
   g_gv_prefix = StringFormat("VCX4_%I64d_%s_%I64u_", login, srv, InpMagicNumber);
}

void SaveState(bool flush = false)
{
   GlobalVariableSet(g_gv_prefix + "INIT_CAP", g_persist.initial_capital);
   GlobalVariableSet(g_gv_prefix + "DAY_BAL",  g_persist.daily_start_balance);
   GlobalVariableSet(g_gv_prefix + "P_YEAR",   (double)g_persist.period_year);
   GlobalVariableSet(g_gv_prefix + "P_YDAY",   (double)g_persist.period_yday);
   GlobalVariableSet(g_gv_prefix + "CON_LOSS", (double)g_persist.consecutive_losses);
   GlobalVariableSet(g_gv_prefix + "CD_UNTIL", (double)g_persist.cooldown_until);
   GlobalVariableSet(g_gv_prefix + "USR_CTRL", (double)g_persist.user_control);
   GlobalVariableSet(g_gv_prefix + "HARD_DD",  g_persist.hard_dd_locked ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "MAX_PROF", g_persist.max_fav_net_profit);
   GlobalVariableSet(g_gv_prefix + "LAST_SL",  g_persist.last_confirmed_sl);
   GlobalVariableSet(g_gv_prefix + "TOT_TRD",  (double)g_persist.total_trades);
   GlobalVariableSet(g_gv_prefix + "WIN_TRD",  (double)g_persist.win_trades);
   GlobalVariableSet(g_gv_prefix + "LOS_TRD",  (double)g_persist.loss_trades);
   GlobalVariableSet(g_gv_prefix + "GRS_PROF", g_persist.gross_profit);
   GlobalVariableSet(g_gv_prefix + "GRS_LOSS", g_persist.gross_loss);
   if(flush) GlobalVariablesFlush();
}

void LoadState()
{
   BuildGVPrefix();
   MqlDateTime dt;
   TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);

   if(!GlobalVariableCheck(g_gv_prefix + "INIT_CAP") || MQLInfoInteger(MQL_TESTER))
   {
      ZeroMemory(g_persist);
      g_persist.initial_capital     = (InpInitialCapital > 0.0) ? InpInitialCapital : bal;
      g_persist.daily_start_balance = bal;
      g_persist.period_year         = dt.year;
      g_persist.period_yday         = dt.day_of_year;
      g_persist.user_control        = CTRL_EA_ON;
      SaveState(true);
      return;
   }

   g_persist.initial_capital     = GlobalVariableGet(g_gv_prefix + "INIT_CAP");
   g_persist.daily_start_balance = GlobalVariableGet(g_gv_prefix + "DAY_BAL");
   g_persist.period_year         = (int)GlobalVariableGet(g_gv_prefix + "P_YEAR");
   g_persist.period_yday         = (int)GlobalVariableGet(g_gv_prefix + "P_YDAY");
   g_persist.consecutive_losses  = (int)GlobalVariableGet(g_gv_prefix + "CON_LOSS");
   g_persist.cooldown_until      = (datetime)GlobalVariableGet(g_gv_prefix + "CD_UNTIL");
   g_persist.user_control        = (int)GlobalVariableGet(g_gv_prefix + "USR_CTRL");
   g_persist.hard_dd_locked      = (GlobalVariableGet(g_gv_prefix + "HARD_DD") > 0.5);
   g_persist.max_fav_net_profit  = GlobalVariableGet(g_gv_prefix + "MAX_PROF");
   g_persist.last_confirmed_sl   = GlobalVariableGet(g_gv_prefix + "LAST_SL");
   g_persist.total_trades        = (int)GlobalVariableGet(g_gv_prefix + "TOT_TRD");
   g_persist.win_trades          = (int)GlobalVariableGet(g_gv_prefix + "WIN_TRD");
   g_persist.loss_trades         = (int)GlobalVariableGet(g_gv_prefix + "LOS_TRD");
   g_persist.gross_profit        = GlobalVariableGet(g_gv_prefix + "GRS_PROF");
   g_persist.gross_loss          = GlobalVariableGet(g_gv_prefix + "GRS_LOSS");
}

//+------------------------------------------------------------------+
//| Price & Volume Step Normalization                                |
//+------------------------------------------------------------------+
double NormPrice(double price, bool round_up)
{
   double ts = g_symbol.TickSize();
   if(ts <= 0.0) return NormalizeDouble(price, g_symbol.Digits());
   double steps = price / ts;
   double r = round_up ? MathCeil(steps - 1e-9) : MathFloor(steps + 1e-9);
   return NormalizeDouble(r * ts, g_symbol.Digits());
}

double NormLot(double raw_lot)
{
   double step = g_symbol.LotsStep();
   if(step <= 0.0) step = 0.01;
   int digits = 0;
   double s = step;
   while(s < 1.0 - 1e-9 && digits < 8) { s *= 10.0; digits++; }
   double lot = MathFloor((raw_lot + 1e-11) / step) * step;
   return NormalizeDouble(lot, digits);
}

ENUM_ORDER_TYPE_FILLING GetFillingMode(const string sym)
{
   uint f = (uint)SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) return ORDER_FILLING_IOC;
   if((f & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) return ORDER_FILLING_FOK;
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

   ENUM_ACCOUNT_TRADE_MODE tm = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(tm == ACCOUNT_TRADE_MODE_REAL && !InpAllowRealMoneyTrading && !MQLInfoInteger(MQL_TESTER))
   {
      Print("CRITICAL [Vulcares Vx V4]: Set InpAllowRealMoneyTrading=true to run on a Real account.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(35);
   g_trade.SetTypeFilling(GetFillingMode(g_validated_symbol));
   g_trade.SetAsyncMode(false);

   LoadState();

   g_hATR_M5     = iATR(g_validated_symbol, PERIOD_M5, 14);
   g_hEMA_8_M15  = iMA(g_validated_symbol, PERIOD_M15, 8,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M15 = iMA(g_validated_symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_8_M5   = iMA(g_validated_symbol, PERIOD_M5,  8,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M5  = iMA(g_validated_symbol, PERIOD_M5,  21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_9_M1   = iMA(g_validated_symbol, PERIOD_M1,  9,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M1  = iMA(g_validated_symbol, PERIOD_M1,  21, 0, MODE_EMA, PRICE_CLOSE);
   g_hRSI_14_M5  = iRSI(g_validated_symbol, PERIOD_M5, 14, PRICE_CLOSE);

   if(g_hATR_M5 == INVALID_HANDLE || g_hEMA_8_M15 == INVALID_HANDLE || g_hEMA_21_M15 == INVALID_HANDLE ||
      g_hEMA_8_M5 == INVALID_HANDLE || g_hEMA_21_M5 == INVALID_HANDLE || g_hEMA_9_M1 == INVALID_HANDLE ||
      g_hEMA_21_M1 == INVALID_HANDLE || g_hRSI_14_M5 == INVALID_HANDLE)
      return INIT_FAILED;

   ReconcileState();
   if(InpShowDashboard) BuildDashboard();
   EventSetMillisecondTimer(250);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveState(true);
   IndicatorRelease(g_hATR_M5);    IndicatorRelease(g_hEMA_8_M15); IndicatorRelease(g_hEMA_21_M15);
   IndicatorRelease(g_hEMA_8_M5);  IndicatorRelease(g_hEMA_21_M5);  IndicatorRelease(g_hEMA_9_M1);
   IndicatorRelease(g_hEMA_21_M1); IndicatorRelease(g_hRSI_14_M5);
   ObjectsDeleteAll(0, UI_PFX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Fixed Flat Risk & Dynamic Lot Calculation (No Martingale)        |
//+------------------------------------------------------------------+
double GetFlatRiskBudget()
{
   return (g_persist.initial_capital * InpFixedRiskPercent) / 100.0;
}

double ComputeSafeLot(ENUM_ORDER_TYPE ord_type, double entry_p, double sl_p)
{
   double risk_budget = GetFlatRiskBudget();
   double vol_min  = g_symbol.LotsMin();
   double vol_max  = g_symbol.LotsMax();
   double vol_step = g_symbol.LotsStep();

   double prof_1lot = 0.0;
   if(!OrderCalcProfit(ord_type, g_validated_symbol, 1.0, entry_p, sl_p, prof_1lot))
      return 0.0;

   double loss_1lot = MathAbs(prof_1lot);
   if(loss_1lot <= 0.0 || prof_1lot >= 0.0) return 0.0;

   // Reserve 15% for commission/slippage
   double lot = NormLot((risk_budget * 0.85) / loss_1lot);
   if(lot < vol_min)
   {
      g_status_note = "MIN_LOT_EXCEEDS_1%_RISK";
      return 0.0;
   }
   if(lot > vol_max) lot = vol_max;

   double actual_loss = 0.0;
   if(!OrderCalcProfit(ord_type, g_validated_symbol, lot, entry_p, sl_p, actual_loss))
      return 0.0;

   while(MathAbs(actual_loss) > risk_budget && lot > vol_min)
   {
      lot = NormLot(lot - vol_step);
      if(lot < vol_min) return 0.0;
      if(!OrderCalcProfit(ord_type, g_validated_symbol, lot, entry_p, sl_p, actual_loss))
         return 0.0;
   }
   return (MathAbs(actual_loss) <= risk_budget) ? lot : 0.0;
}

//+------------------------------------------------------------------+
//| Position Audit & Reconciliation                                  |
//+------------------------------------------------------------------+
ulong GetActivePositionTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == g_validated_symbol && g_pos.Magic() == InpMagicNumber)
         return g_pos.Ticket();
   }
   return 0;
}

void ReconcileState()
{
   ulong tkt = GetActivePositionTicket();
   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED) { g_exec_state = STATE_EMERGENCY_LOCKED; return; }
   if(g_persist.hard_dd_locked) { g_exec_state = STATE_RISK_LOCKED; return; }

   if(tkt > 0 && g_pos.SelectByTicket(tkt))
   {
      if(g_pos.StopLoss() <= 0.0)
      {
         g_trade.PositionClose(tkt);
         g_exec_state = STATE_SCANNING;
         return;
      }
      if(g_persist.last_confirmed_sl <= 0.0) g_persist.last_confirmed_sl = g_pos.StopLoss();
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_TRAILING_ACTIVE;
   }
   else
   {
      g_persist.max_fav_net_profit = 0.0;
      g_persist.last_confirmed_sl  = 0.0;
      if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
      {
         g_persist.user_control = CTRL_STOPPED;
         g_exec_state = STATE_STOPPED;
      }
      else if(g_persist.user_control == CTRL_EA_OFF)
      {
         g_exec_state = STATE_STOPPED;
      }
      else
      {
         g_exec_state = STATE_SCANNING;
      }
   }
   g_dash_dirty = true;
}

//+------------------------------------------------------------------+
//| Always-Active Multi-Timeframe Dominance Analyzer                 |
//+------------------------------------------------------------------+
int EvaluateMarketDirection(double &sl_dist_out)
{
   double atr5[2], e8_15[2], e21_15[2], e8_5[2], e21_5[2], e9_1[2], e21_1[2], rsi5[2];
   if(CopyBuffer(g_hATR_M5,     0, 0, 2, atr5)   < 2 ||
      CopyBuffer(g_hEMA_8_M15,  0, 0, 2, e8_15)  < 2 || CopyBuffer(g_hEMA_21_M15, 0, 0, 2, e21_15) < 2 ||
      CopyBuffer(g_hEMA_8_M5,   0, 0, 2, e8_5)   < 2 || CopyBuffer(g_hEMA_21_M5,  0, 0, 2, e21_5)  < 2 ||
      CopyBuffer(g_hEMA_9_M1,   0, 0, 2, e9_1)   < 2 || CopyBuffer(g_hEMA_21_M1,  0, 0, 2, e21_1)  < 2 ||
      CopyBuffer(g_hRSI_14_M5,  0, 0, 2, rsi5)   < 2)
      return 0;

   double bid = g_symbol.Bid();
   double c1_prev = iClose(g_validated_symbol, PERIOD_M1, 1);
   double o1_prev = iOpen(g_validated_symbol, PERIOD_M1, 1);

   double buy_pts = 0.0, sell_pts = 0.0;

   // 1. M15 Primary Trend Structure (Weight: 35%)
   if(e8_15[0] > e21_15[0]) buy_pts += 35.0; else sell_pts += 35.0;

   // 2. M5 Dominant Momentum (Weight: 30%)
   if(e8_5[0] > e21_5[0])   buy_pts += 30.0; else sell_pts += 30.0;

   // 3. M1 Execution Trigger & Pullback Alignment (Weight: 20%)
   if(e9_1[0] > e21_1[0] && bid > e9_1[0]) buy_pts += 20.0;
   else if(e9_1[0] < e21_1[0] && bid < e9_1[0]) sell_pts += 20.0;
   else if(c1_prev > o1_prev) buy_pts += 10.0;
   else sell_pts += 10.0;

   // 4. RSI M5 Momentum Filter (Avoid buying extreme top / selling extreme bottom) (Weight: 15%)
   if(rsi5[0] > 50.0 && rsi5[0] < 72.0) buy_pts += 15.0;
   else if(rsi5[0] < 50.0 && rsi5[0] > 28.0) sell_pts += 15.0;
   else if(rsi5[0] >= 72.0) sell_pts += 15.0; // Exhaustion mean reversion
   else if(rsi5[0] <= 28.0) buy_pts += 15.0;

   double total = buy_pts + sell_pts;
   g_buy_score_pct  = (total > 0.0) ? (buy_pts / total) * 100.0 : 50.0;
   g_sell_score_pct = (total > 0.0) ? (sell_pts / total) * 100.0 : 50.0;

   sl_dist_out = atr5[0] * InpSL_ATR_M5_Mult;
   int dir = (buy_pts >= sell_pts) ? 1 : -1;
   g_last_signal_dir = (dir > 0) ? "BUY" : "SELL";
   return dir;
}

//+------------------------------------------------------------------+
//| Smart Breathing Trailing Stop (Protects Winners Without Choking) |
//+------------------------------------------------------------------+
void ManageSmartTrailing(ulong ticket)
{
   if(!InpEnableTrailing || !g_pos.SelectByTicket(ticket)) return;
   ulong now_ms = GetTickCount64();
   if(now_ms - g_last_trail_ms < (ulong)InpTrailIntervalMs) return;

   bool is_buy       = (g_pos.PositionType() == POSITION_TYPE_BUY);
   double open_price = g_pos.PriceOpen();
   double cur_sl     = g_pos.StopLoss();
   double lot        = g_pos.Volume();
   double eval_price = is_buy ? g_symbol.Bid() : g_symbol.Ask();
   double spread     = g_symbol.Ask() - g_symbol.Bid();

   double net_float  = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
   double risk_r     = GetFlatRiskBudget();
   if(net_float > g_persist.max_fav_net_profit) g_persist.max_fav_net_profit = net_float;
   double peak_r     = (risk_r > 0.0) ? (g_persist.max_fav_net_profit / risk_r) : 0.0;

   if(peak_r < InpBreakEvenTriggerR) return;

   double stop_lvl = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double candidate_sl = cur_sl;

   if(peak_r >= InpTrailingStartR)
   {
      double price_gain = MathAbs(eval_price - open_price);
      double lock_dist  = price_gain * InpTrailingLockPct;
      candidate_sl = is_buy ? (open_price + lock_dist) : (open_price - lock_dist);
   }
   else if(peak_r >= InpBreakEvenTriggerR)
   {
      double be_offset = spread * 0.5 + g_symbol.TickSize() * 3.0;
      candidate_sl = is_buy ? (open_price + be_offset) : (open_price - be_offset);
   }

   double legal_sl = is_buy ? (eval_price - stop_lvl - g_symbol.TickSize())
                            : (eval_price + stop_lvl + g_symbol.TickSize());
   candidate_sl = is_buy ? MathMin(candidate_sl, legal_sl) : MathMax(candidate_sl, legal_sl);
   candidate_sl = NormPrice(candidate_sl, !is_buy);

   double anchor = (g_persist.last_confirmed_sl > 0.0) ? g_persist.last_confirmed_sl : cur_sl;
   double new_sl = is_buy ? MathMax(anchor, candidate_sl) : MathMin(anchor, candidate_sl);
   double step   = g_symbol.TickSize() * 3.0;

   if((is_buy && new_sl >= cur_sl + step) || (!is_buy && new_sl <= cur_sl - step))
   {
      if(g_trade.PositionModify(ticket, new_sl, g_pos.TakeProfit()) && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
      {
         g_persist.last_confirmed_sl = new_sl;
         g_last_trail_ms = now_ms;
         g_dash_dirty = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Capital Survival Guardrails                                      |
//+------------------------------------------------------------------+
bool CheckRiskGuardrails()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(dt.year != g_persist.period_year || dt.day_of_year != g_persist.period_yday)
   {
      g_persist.period_year = dt.year;
      g_persist.period_yday = dt.day_of_year;
      g_persist.daily_start_balance = bal;
      SaveState(false);
   }

   if((g_persist.initial_capital - eq) >= g_persist.initial_capital * (InpMaxInitialDDPct / 100.0) || g_persist.hard_dd_locked)
   {
      g_persist.hard_dd_locked = true;
      g_exec_state = STATE_RISK_LOCKED;
      g_status_note = "MAX_DD_LOCKED";
      return false;
   }

   if((eq - g_persist.daily_start_balance) <= -(g_persist.initial_capital * (InpDailyLossLimitPct / 100.0)))
   {
      g_status_note = "DAILY_LOSS_LIMIT";
      return false;
   }

   if(TimeCurrent() < g_persist.cooldown_until)
   {
      g_status_note = "LOSS_COOLDOWN";
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Main Tick Loop (Always Active Execution)                         |
//+------------------------------------------------------------------+
void OnTick()
{
   g_symbol.RefreshRates();
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { g_exec_state = STATE_DISCONNECTED; return; }

   ulong pos_tkt = GetActivePositionTicket();
   if(pos_tkt > 0)
   {
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_TRAILING_ACTIVE;
      ManageSmartTrailing(pos_tkt);
      return;
   }

   // User Control Gates
   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED) { g_exec_state = STATE_EMERGENCY_LOCKED; g_status_note = "EMERGENCY_LOCKED"; return; }
   if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
   {
      g_persist.user_control = CTRL_STOPPED;
      g_exec_state = STATE_STOPPED;
      g_status_note = "STOPPED_BY_USER";
      return;
   }
   if(g_persist.user_control == CTRL_EA_OFF)
   {
      g_exec_state = STATE_STOPPED;
      g_status_note = "EA_OFF_STANDBY";
      return;
   }

   if(!CheckRiskGuardrails()) return;

   if(TimeCurrent() - g_last_close_time < InpReEntryDelaySec)
   {
      g_status_note = "REENTRY_WAIT";
      return;
   }

   // Evaluate Direction & Execute Immediately
   double sl_dist = 0.0;
   int dir = EvaluateMarketDirection(sl_dist);
   g_dash_dirty = true;
   if(dir == 0 || sl_dist <= 0.0) return;

   double ask = g_symbol.Ask(), bid = g_symbol.Bid(), spread = ask - bid;
   if((spread / sl_dist) > InpMaxSpreadToSLRatio)
   {
      g_status_note = "SPREAD_HIGH";
      return;
   }

   bool is_buy = (dir > 0);
   double stop_lvl = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double final_sl_dist = MathMax(sl_dist, stop_lvl + spread * 1.5);
   double entry_p  = is_buy ? ask : bid;
   double sl_price = is_buy ? NormPrice(entry_p - final_sl_dist, false) : NormPrice(entry_p + final_sl_dist, true);
   double tp_price = is_buy ? NormPrice(entry_p + final_sl_dist * InpTP_R_Multiple, true)
                            : NormPrice(entry_p - final_sl_dist * InpTP_R_Multiple, false);

   double lot = ComputeSafeLot(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, entry_p, sl_price);
   if(lot <= 0.0) return;

   bool sent = is_buy ? g_trade.Buy(lot, g_validated_symbol, ask, sl_price, tp_price, "VCX4_BUY")
                      : g_trade.Sell(lot, g_validated_symbol, bid, sl_price, tp_price, "VCX4_SELL");

   if(sent && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      g_status_note = "ACTIVE_TRADE";
      g_persist.max_fav_net_profit = 0.0;
      g_persist.last_confirmed_sl  = sl_price;
      SaveState(true);
      ReconcileState();
   }
   else
   {
      g_status_note = StringFormat("ERR_%u", g_trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Trade Deal Listener (Deposit Isolation & Stats)                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;

   ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dtype == DEAL_TYPE_BALANCE || dtype == DEAL_TYPE_CREDIT || dtype == DEAL_TYPE_BONUS)
   {
      g_persist.daily_start_balance += HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      SaveState(true);
      g_dash_dirty = true;
      return;
   }

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagicNumber ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != g_validated_symbol ||
      HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   g_persist.total_trades++;
   if(net > 0.0)
   {
      g_persist.win_trades++;
      g_persist.gross_profit += net;
      g_persist.consecutive_losses = 0;
   }
   else if(net < 0.0)
   {
      g_persist.loss_trades++;
      g_persist.gross_loss += MathAbs(net);
      g_persist.consecutive_losses++;
      if(g_persist.consecutive_losses >= InpMaxConsecutiveLosses)
         g_persist.cooldown_until = TimeCurrent() + InpLossCooldownMinutes * 60;
   }

   g_last_close_time = TimeCurrent();
   SaveState(true);
   ReconcileState();
}

void OnTimer()
{
   if(InpShowDashboard && g_dash_dirty) { UpdateDashboard(); g_dash_dirty = false; }
}

//+------------------------------------------------------------------+
//| Clean & Modern Compact UI Dashboard                              |
//+------------------------------------------------------------------+
void DrawLabel(string name, int x, int y, string text, color clr, int sz = 9, bool bold = false)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, sz);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Segoe UI Bold" : "Consolas");
}

void DrawButton(string name, int x, int y, int w, int h, string text, color bg, color fg)
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
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Bold");
}

void BuildDashboard()
{
   int panel_w = 340;
   int panel_h = g_dash_minimized ? 36 : 265;

   ObjectCreate(0, UI_PFX + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_XSIZE, panel_w);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_YSIZE, panel_h);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_BGCOLOR, C'20,22,28');
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_BORDER_COLOR, C'235,155,30');
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_WIDTH, 1);

   DrawLabel(UI_PFX + "TITLE", 22, 27, "VULCARES Vx V4.0  |  XAUUSD", C'245,180,45', 9, true);
   DrawButton(UI_PFX + "BTN_MIN", 316, 25, 28, 22, g_dash_minimized ? "+" : "-", C'45,50,62', clrWhite);

   if(g_dash_minimized) { ChartRedraw(0); return; }

   // 4 Clean Control Buttons (Combined EA ON/OFF Toggle + STOP EA + CLOSE + EMERG)
   bool is_on = (g_persist.user_control == CTRL_EA_ON);
   DrawButton(UI_PFX + "BTN_TOGGLE", 22,  56, 76, 26, is_on ? "EA: ON" : "EA: OFF", is_on ? C'30,155,75' : C'95,100,110', clrWhite);
   DrawButton(UI_PFX + "BTN_STOP",   103, 56, 76, 26, "STOP EA", C'215,120,25', clrWhite);
   DrawButton(UI_PFX + "BTN_CLOSE",  184, 56, 76, 26, "CLOSE",   C'175,65,35',  clrWhite);
   DrawButton(UI_PFX + "BTN_EMERG",  265, 56, 77, 26, "EMERG",   C'195,25,25',  clrWhite);

   for(int i = 0; i < 9; i++)
      DrawLabel(StringFormat("%sROW_%d", UI_PFX, i), 22, 92 + i * 20, "...", C'220,225,235', 8, (i == 0 || i == 4));

   UpdateDashboard();
}

void UpdateDashboard()
{
   if(g_dash_minimized) return;

   bool is_on = (g_persist.user_control == CTRL_EA_ON);
   ObjectSetString(0, UI_PFX + "BTN_TOGGLE", OBJPROP_TEXT, is_on ? "EA: ON" : "EA: OFF");
   ObjectSetInteger(0, UI_PFX + "BTN_TOGGLE", OBJPROP_BGCOLOR, is_on ? C'30,155,75' : C'95,100,110');

   string curr = AccountInfoString(ACCOUNT_CURRENCY);
   double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double net  = g_persist.gross_profit - g_persist.gross_loss;
   double wr   = (g_persist.total_trades > 0) ? ((double)g_persist.win_trades / g_persist.total_trades) * 100.0 : 0.0;

   string r[9];
   r[0] = StringFormat("STATUS  : %s (%s)", EnumToString(g_exec_state), g_status_note);
   r[1] = StringFormat("CAPITAL : %.0f %s  |  FLAT RISK: %.2f %s", g_persist.initial_capital, curr, GetFlatRiskBudget(), curr);
   r[2] = StringFormat("BALANCE : %.2f %s  |  EQUITY: %.2f", bal, curr, eq);
   r[3] = "------------------------------------------------";
   r[4] = StringFormat("SIGNAL  : %s (BUY %.0f%% | SELL %.0f%%)", g_last_signal_dir, g_buy_score_pct, g_sell_score_pct);
   r[5] = StringFormat("STATS   : %d TRADES (W:%d L:%d) | WR: %.1f%%", g_persist.total_trades, g_persist.win_trades, g_persist.loss_trades, wr);
   r[6] = StringFormat("NET PNL : %+.2f %s  |  SPREAD: %I64d pts", net, curr, SymbolInfoInteger(g_validated_symbol, SYMBOL_SPREAD));

   ulong tkt = GetActivePositionTicket();
   if(tkt > 0 && g_pos.SelectByTicket(tkt))
   {
      double flt = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      r[7] = StringFormat("ACTIVE  : %s %.2f LOT @ %.2f", (g_pos.PositionType()==POSITION_TYPE_BUY?"BUY":"SELL"), g_pos.Volume(), g_pos.PriceOpen());
      r[8] = StringFormat("FLOAT   : %+.2f %s  |  SL: %.2f", flt, curr, g_pos.StopLoss());
   }
   else
   {
      r[7] = "ACTIVE  : NONE (READY TO ENTER)";
      r[8] = "FLOAT   : 0.00  |  SL: 0.00";
   }

   for(int i = 0; i < 9; i++)
      ObjectSetString(0, StringFormat("%sROW_%d", UI_PFX, i), OBJPROP_TEXT, r[i]);

   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Interactive Button Handler                                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == UI_PFX + "BTN_TOGGLE")
   {
      if(g_persist.user_control == CTRL_EA_ON)
      {
         g_persist.user_control = CTRL_EA_OFF;
      }
      else
      {
         g_persist.hard_dd_locked = false;
         g_persist.cooldown_until = 0;
         g_persist.daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
         g_persist.user_control = CTRL_EA_ON;
         g_status_note = "READY";
      }
   }
   else if(sparam == UI_PFX + "BTN_STOP")
   {
      ulong tkt = GetActivePositionTicket();
      g_persist.user_control = (tkt > 0) ? CTRL_SOFT_STOP_REQUESTED : CTRL_STOPPED;
   }
   else if(sparam == UI_PFX + "BTN_CLOSE")
   {
      ulong tkt = GetActivePositionTicket();
      if(tkt > 0) g_trade.PositionClose(tkt);
      g_persist.user_control = CTRL_STOPPED;
   }
   else if(sparam == UI_PFX + "BTN_EMERG")
   {
      g_persist.user_control = CTRL_EMERGENCY_LOCKED;
      ulong tkt = GetActivePositionTicket();
      if(tkt > 0) g_trade.PositionClose(tkt);
   }
   else if(sparam == UI_PFX + "BTN_MIN")
   {
      g_dash_minimized = !g_dash_minimized;
      ObjectsDeleteAll(0, UI_PFX);
      BuildDashboard();
   }

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   SaveState(true);
   ReconcileState();
   UpdateDashboard();
}
