//+------------------------------------------------------------------+
//|                                               Vulcares_Vx_V6.mq5 |
//|                                  Copyright 2026, Vulcares Quant  |
//|      PROFIT-BANKED ANTIMARTINGALE 2X + VALUE PULLBACK ENGINE     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vulcares Quant"
#property link      "https://www.mql5.com"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

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
   STATE_IN_POSITION,
   STATE_STOPPING_AFTER_POS,
   STATE_STOPPED,
   STATE_RISK_LOCKED,
   STATE_EMERGENCY_LOCKED,
   STATE_DISCONNECTED
};

//--- Input Parameters
input group "=== 1. CAPITAL & PROFIT-BANKED ANTIMARTINGALE 2X ==="
input ulong    InpMagicNumber             = 20260666;
input bool     InpAllowRealMoneyTrading   = false;   // Set true explicitly for Live Real Account
input double   InpInitialCapital          = 1000.00; // Modal Dasar (USD / USC)
input double   InpBaseRiskPercent         = 1.20;    // Base Risk = 1.20% ($12.00 pada modal 1000)
input bool     InpEnableAntiMartingale2x  = true;    // Aktifkan Anti-Martingale 2.0x
input double   InpAntiMartingaleMult      = 2.00;    // Pengali 2.0x setelah menang (1.0x -> 2.0x -> Banked Reset)
input double   InpMaxDrawdownPct          = 20.00;   // Batas Drawdown Maksimal 20%

input group "=== 2. HIGH WIN-RATE PULLBACK & SWING ENGINE ==="
input ENUM_TIMEFRAMES InpSignalTF         = PERIOD_M5; // Timeframe Utama Sinyal (M5 anti-noise)
input double   InpSL_ATR_Mult             = 2.00;    // Stop Loss Struktural (2.0x ATR M5)
input double   InpTP_R_Ratio              = 1.75;    // Take Profit Murni (1.75R - Hit Rate Tinggi)
input bool     InpUseLateBreakEven        = true;    // Geser ke BE hanya setelah 85% menuju TP
input int      InpCooldownSec             = 15;      // Jeda antar transaksi (detik)

input group "=== 3. UI DASHBOARD ==="
input bool     InpShowDashboard           = true;

//--- Persistent State Structure
struct PersistentState
{
   double   initial_capital;
   double   daily_start_balance;
   int      period_yday;
   int      am_step;            // 0 = Base 1.0x, 1 = Boosted 2.0x
   double   current_mult;
   int      user_control;
   bool     hard_dd_locked;
   double   entry_risk_usd;
   bool     be_applied;
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

ENUM_EXEC_STATE g_exec_state      = STATE_SCANNING;
PersistentState g_persist;

// Indicator Handles
int g_hATR_M5     = INVALID_HANDLE;
int g_hEMA_50_M15 = INVALID_HANDLE;
int g_hEMA_20_M5  = INVALID_HANDLE;
int g_hBB_20_M5   = INVALID_HANDLE;
int g_hRSI_14_M5  = INVALID_HANDLE;
int g_hStoch_M1   = INVALID_HANDLE;

// Runtime Telemetry
string   g_validated_symbol = "";
string   g_gv_prefix        = "";
string   g_status_note      = "READY";
string   g_last_signal      = "SCAN";
double   g_buy_prob         = 50.0;
double   g_sell_prob        = 50.0;
datetime g_last_close_time  = 0;
datetime g_last_bar_time    = 0;
bool     g_dash_minimized   = false;
bool     g_dash_dirty       = true;

#define UI_PFX "VCX6_"

//+------------------------------------------------------------------+
//| Validate XAUUSD / GOLD Symbol                                    |
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
//| State Persistence                                                |
//+------------------------------------------------------------------+
void BuildGVPrefix()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   string srv = AccountInfoString(ACCOUNT_SERVER);
   StringReplace(srv, " ", "_");
   g_gv_prefix = StringFormat("VCX6_%I64d_%s_%I64u_", login, srv, InpMagicNumber);
}

void SaveState(bool flush = false)
{
   GlobalVariableSet(g_gv_prefix + "INIT_CAP", g_persist.initial_capital);
   GlobalVariableSet(g_gv_prefix + "DAY_BAL",  g_persist.daily_start_balance);
   GlobalVariableSet(g_gv_prefix + "P_YDAY",   (double)g_persist.period_yday);
   GlobalVariableSet(g_gv_prefix + "AM_STEP",  (double)g_persist.am_step);
   GlobalVariableSet(g_gv_prefix + "AM_MULT",  g_persist.current_mult);
   GlobalVariableSet(g_gv_prefix + "USR_CTRL", (double)g_persist.user_control);
   GlobalVariableSet(g_gv_prefix + "HARD_DD",  g_persist.hard_dd_locked ? 1.0 : 0.0);
   GlobalVariableSet(g_gv_prefix + "ENT_RSK",  g_persist.entry_risk_usd);
   GlobalVariableSet(g_gv_prefix + "BE_APP",   g_persist.be_applied ? 1.0 : 0.0);
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
      g_persist.period_yday         = dt.day_of_year;
      g_persist.am_step             = 0;
      g_persist.current_mult        = 1.0;
      g_persist.user_control        = CTRL_EA_ON;
      SaveState(true);
      return;
   }

   g_persist.initial_capital     = GlobalVariableGet(g_gv_prefix + "INIT_CAP");
   g_persist.daily_start_balance = GlobalVariableGet(g_gv_prefix + "DAY_BAL");
   g_persist.period_yday         = (int)GlobalVariableGet(g_gv_prefix + "P_YDAY");
   g_persist.am_step             = (int)GlobalVariableGet(g_gv_prefix + "AM_STEP");
   g_persist.current_mult        = GlobalVariableGet(g_gv_prefix + "AM_MULT");
   if(g_persist.current_mult < 1.0) g_persist.current_mult = 1.0;
   g_persist.user_control        = (int)GlobalVariableGet(g_gv_prefix + "USR_CTRL");
   g_persist.hard_dd_locked      = (GlobalVariableGet(g_gv_prefix + "HARD_DD") > 0.5);
   g_persist.entry_risk_usd      = GlobalVariableGet(g_gv_prefix + "ENT_RSK");
   g_persist.be_applied          = (GlobalVariableGet(g_gv_prefix + "BE_APP") > 0.5);
   g_persist.total_trades        = (int)GlobalVariableGet(g_gv_prefix + "TOT_TRD");
   g_persist.win_trades          = (int)GlobalVariableGet(g_gv_prefix + "WIN_TRD");
   g_persist.loss_trades         = (int)GlobalVariableGet(g_gv_prefix + "LOS_TRD");
   g_persist.gross_profit        = GlobalVariableGet(g_gv_prefix + "GRS_PROF");
   g_persist.gross_loss          = GlobalVariableGet(g_gv_prefix + "GRS_LOSS");
}

//+------------------------------------------------------------------+
//| Price & Lot Normalization                                        |
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
      Print("CRITICAL [Vulcares Vx V6]: Set InpAllowRealMoneyTrading=true for live real account.");
      return INIT_FAILED;
   }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(35);
   g_trade.SetTypeFilling(GetFillingMode(g_validated_symbol));
   g_trade.SetAsyncMode(false);

   LoadState();

   g_hATR_M5     = iATR(g_validated_symbol, PERIOD_M5, 14);
   g_hEMA_50_M15 = iMA(g_validated_symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_20_M5  = iMA(g_validated_symbol, PERIOD_M5,  20, 0, MODE_EMA, PRICE_CLOSE);
   g_hBB_20_M5   = iBands(g_validated_symbol, PERIOD_M5, 20, 0, 2.0, PRICE_CLOSE);
   g_hRSI_14_M5  = iRSI(g_validated_symbol, PERIOD_M5, 14, PRICE_CLOSE);
   g_hStoch_M1   = iStochastic(g_validated_symbol, PERIOD_M1, 8, 3, 3, MODE_SMA, STO_LOWHIGH);

   if(g_hATR_M5 == INVALID_HANDLE || g_hEMA_50_M15 == INVALID_HANDLE || g_hEMA_20_M5 == INVALID_HANDLE ||
      g_hBB_20_M5 == INVALID_HANDLE || g_hRSI_14_M5 == INVALID_HANDLE || g_hStoch_M1 == INVALID_HANDLE)
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
   IndicatorRelease(g_hATR_M5);   IndicatorRelease(g_hEMA_50_M15);
   IndicatorRelease(g_hEMA_20_M5);IndicatorRelease(g_hBB_20_M5);
   IndicatorRelease(g_hRSI_14_M5);IndicatorRelease(g_hStoch_M1);
   ObjectsDeleteAll(0, UI_PFX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Risk Budget & Lot Calculation (Anti-Martingale 2x)               |
//+------------------------------------------------------------------+
double GetCurrentRiskBudget()
{
   double base_risk = (g_persist.initial_capital * InpBaseRiskPercent) / 100.0;
   double mult = InpEnableAntiMartingale2x ? g_persist.current_mult : 1.0;
   return base_risk * mult;
}

double ComputeOptimalLot(ENUM_ORDER_TYPE ord_type, double entry_p, double sl_p, double &risk_used)
{
   double risk_budget = GetCurrentRiskBudget();
   double vol_min  = g_symbol.LotsMin();
   double vol_max  = g_symbol.LotsMax();
   double vol_step = g_symbol.LotsStep();

   double prof_1lot = 0.0;
   if(!OrderCalcProfit(ord_type, g_validated_symbol, 1.0, entry_p, sl_p, prof_1lot))
      return 0.0;

   double loss_1lot = MathAbs(prof_1lot);
   if(loss_1lot <= 0.0 || prof_1lot >= 0.0) return 0.0;

   // Account for spread/commission buffer
   double lot = NormLot((risk_budget * 0.90) / loss_1lot);
   if(lot < vol_min)
   {
      // Allow 0.01 min lot if within 1.5x risk budget so small accounts never stall
      double min_loss = 0.0;
      if(OrderCalcProfit(ord_type, g_validated_symbol, vol_min, entry_p, sl_p, min_loss) && MathAbs(min_loss) <= risk_budget * 1.5)
         lot = vol_min;
      else
      {
         g_status_note = "MIN_LOT_TOO_LARGE";
         return 0.0;
      }
   }
   if(lot > vol_max) lot = vol_max;

   double actual_loss = 0.0;
   OrderCalcProfit(ord_type, g_validated_symbol, lot, entry_p, sl_p, actual_loss);
   risk_used = MathAbs(actual_loss);
   return lot;
}

//+------------------------------------------------------------------+
//| Active Position Helper                                           |
//+------------------------------------------------------------------+
ulong GetActiveTicket()
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
   ulong tkt = GetActiveTicket();
   if(g_persist.user_control == CTRL_EMERGENCY_LOCKED) { g_exec_state = STATE_EMERGENCY_LOCKED; return; }
   if(g_persist.hard_dd_locked) { g_exec_state = STATE_RISK_LOCKED; return; }

   if(tkt > 0 && g_pos.SelectByTicket(tkt))
   {
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_IN_POSITION;
   }
   else
   {
      g_persist.be_applied = false;
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
//| High Win-Rate Value Pullback & Reversal Engine                   |
//+------------------------------------------------------------------+
int EvaluateValuePullbackSignal(double &sl_dist_out)
{
   double atr5[2], e50_15[2], e20_5[2], bb_u[2], bb_l[2], bb_m[2], rsi5[2], sto_m[2], sto_s[2];
   if(CopyBuffer(g_hATR_M5,     0, 0, 2, atr5)   < 2 ||
      CopyBuffer(g_hEMA_50_M15, 0, 0, 2, e50_15) < 2 ||
      CopyBuffer(g_hEMA_20_M5,  0, 0, 2, e20_5)  < 2 ||
      CopyBuffer(g_hBB_20_M5,   1, 0, 2, bb_u)   < 2 ||
      CopyBuffer(g_hBB_20_M5,   2, 0, 2, bb_l)   < 2 ||
      CopyBuffer(g_hBB_20_M5,   0, 0, 2, bb_m)   < 2 ||
      CopyBuffer(g_hRSI_14_M5,  0, 0, 2, rsi5)   < 2 ||
      CopyBuffer(g_hStoch_M1,   0, 0, 2, sto_m)  < 2 ||
      CopyBuffer(g_hStoch_M1,   1, 0, 2, sto_s)  < 2)
      return 0;

   double bid = g_symbol.Bid();
   double m1_c1 = iClose(g_validated_symbol, PERIOD_M1, 1);
   double m1_o1 = iOpen(g_validated_symbol, PERIOD_M1, 1);
   double m1_l1 = iLow(g_validated_symbol, PERIOD_M1, 1);
   double m1_h1 = iHigh(g_validated_symbol, PERIOD_M1, 1);

   sl_dist_out = atr5[0] * InpSL_ATR_Mult;

   bool uptrend_macro   = (bid > e50_15[0] && e20_5[0] >= e20_5[1]);
   bool downtrend_macro = (bid < e50_15[0] && e20_5[0] <= e20_5[1]);

   // Setup 1: Trend Pullback ke Value Zone (Beli saat diskon di tren naik, Jual saat premium di tren turun)
   bool buy_pullback  = (uptrend_macro && (m1_l1 <= e20_5[0] || rsi5[0] < 48.0) &&
                         sto_m[0] < 35.0 && sto_m[0] > sto_s[0] && m1_c1 > m1_o1);

   bool sell_pullback = (downtrend_macro && (m1_h1 >= e20_5[0] || rsi5[0] > 52.0) &&
                         sto_m[0] > 65.0 && sto_m[0] < sto_s[0] && m1_c1 < m1_o1);

   // Setup 2: Bollinger Extreme Snap-Back (Saat pasar sideways / oversold-overbought ekstrem)
   bool buy_snap  = (m1_l1 < bb_l[1] && bid > bb_l[0] && rsi5[0] < 32.0 && m1_c1 > m1_o1);
   bool sell_snap = (m1_h1 > bb_u[1] && bid < bb_u[0] && rsi5[0] > 68.0 && m1_c1 < m1_o1);

   if(buy_pullback || buy_snap)
   {
      g_buy_prob = 82.0; g_sell_prob = 18.0;
      g_last_signal = buy_pullback ? "BUY PULLBACK" : "BUY SNAP";
      return 1;
   }
   if(sell_pullback || sell_snap)
   {
      g_buy_prob = 18.0; g_sell_prob = 82.0;
      g_last_signal = sell_pullback ? "SELL PULLBACK" : "SELL SNAP";
      return -1;
   }

   g_buy_prob = uptrend_macro ? 60.0 : 40.0;
   g_sell_prob = 100.0 - g_buy_prob;
   g_status_note = uptrend_macro ? "WAIT_BUY_DISCOUNT" : "WAIT_SELL_PREMIUM";
   g_last_signal = "SCANNING";
   return 0;
}

//+------------------------------------------------------------------+
//| Late Break-Even Only (Lets Winners Hit Full TP Without Choking)  |
//+------------------------------------------------------------------+
void ManageLateBreakEven(ulong ticket)
{
   if(!InpUseLateBreakEven || g_persist.be_applied || !g_pos.SelectByTicket(ticket)) return;

   bool is_buy       = (g_pos.PositionType() == POSITION_TYPE_BUY);
   double open_price = g_pos.PriceOpen();
   double tp_price   = g_pos.TakeProfit();
   double cur_sl     = g_pos.StopLoss();
   if(tp_price <= 0.0) return;

   double eval_price = is_buy ? g_symbol.Bid() : g_symbol.Ask();
   double total_dist = MathAbs(tp_price - open_price);
   double cur_gain   = is_buy ? (eval_price - open_price) : (open_price - eval_price);

   // Move SL to Break-Even ONLY after price reaches 85% of Take Profit target
   if(total_dist > 0.0 && cur_gain >= total_dist * 0.85)
   {
      double spread = g_symbol.Ask() - g_symbol.Bid();
      double be_sl  = is_buy ? NormPrice(open_price + spread * 0.5, true)
                             : NormPrice(open_price - spread * 0.5, false);

      if((is_buy && be_sl > cur_sl) || (!is_buy && be_sl < cur_sl))
      {
         if(g_trade.PositionModify(ticket, be_sl, tp_price) && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
         {
            g_persist.be_applied = true;
            SaveState(true);
            g_dash_dirty = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Main Tick Loop                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
   g_symbol.RefreshRates();
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { g_exec_state = STATE_DISCONNECTED; return; }

   ulong tkt = GetActiveTicket();
   if(tkt > 0)
   {
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_IN_POSITION;
      ManageLateBreakEven(tkt);
      return;
   }

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

   // Max Drawdown Guardrail
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if((g_persist.initial_capital - eq) >= g_persist.initial_capital * (InpMaxDrawdownPct / 100.0) || g_persist.hard_dd_locked)
   {
      g_persist.hard_dd_locked = true;
      g_exec_state = STATE_RISK_LOCKED;
      g_status_note = "MAX_DD_LOCKED";
      return;
   }

   if(TimeCurrent() - g_last_close_time < InpCooldownSec)
   {
      g_status_note = "COOLDOWN_WAIT";
      return;
   }

   // Evaluate only once per new M1 candle to eliminate tick-chasing noise
   datetime cur_bar = iTime(g_validated_symbol, PERIOD_M1, 0);
   if(cur_bar == g_last_bar_time) return;
   g_last_bar_time = cur_bar;

   double sl_dist = 0.0;
   int dir = EvaluateValuePullbackSignal(sl_dist);
   g_dash_dirty = true;
   if(dir == 0 || sl_dist <= 0.0) return;

   bool is_buy = (dir > 0);
   double ask = g_symbol.Ask(), bid = g_symbol.Bid(), spread = ask - bid;
   double stop_lvl = (double)g_symbol.StopsLevel() * g_symbol.Point();
   double final_sl_dist = MathMax(sl_dist, stop_lvl + spread * 2.0);

   double entry_p  = is_buy ? ask : bid;
   double sl_price = is_buy ? NormPrice(entry_p - final_sl_dist, false) : NormPrice(entry_p + final_sl_dist, true);
   double tp_price = is_buy ? NormPrice(entry_p + final_sl_dist * InpTP_R_Ratio, true)
                            : NormPrice(entry_p - final_sl_dist * InpTP_R_Ratio, false);

   double risk_used = 0.0;
   double lot = ComputeOptimalLot(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, entry_p, sl_price, risk_used);
   if(lot <= 0.0) return;

   string cmt = StringFormat("VCX6_AM%.0fx", g_persist.current_mult);
   bool sent = is_buy ? g_trade.Buy(lot, g_validated_symbol, ask, sl_price, tp_price, cmt)
                      : g_trade.Sell(lot, g_validated_symbol, bid, sl_price, tp_price, cmt);

   if(sent && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      g_status_note = "IN_TRADE";
      g_persist.entry_risk_usd = risk_used;
      g_persist.be_applied = false;
      SaveState(true);
      ReconcileState();
   }
   else
   {
      g_status_note = StringFormat("ERR_%u", g_trade.ResultRetcode());
   }
}

//+------------------------------------------------------------------+
//| Trade Deal Listener (Profit-Banked Anti-Martingale 2x)           |
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

      // PROFIT-BANKED ANTIMARTINGALE 2X:
      // Step 0 (1x) Menang -> Naik ke Step 1 (2x)
      // Step 1 (2x) Menang -> Amankan profit & kembali ke Step 0 (1x)!
      if(InpEnableAntiMartingale2x && g_persist.am_step == 0)
      {
         g_persist.am_step      = 1;
         g_persist.current_mult = InpAntiMartingaleMult; // 2.0x
      }
      else
      {
         g_persist.am_step      = 0;
         g_persist.current_mult = 1.0; // Banked!
      }
   }
   else if(net < 0.0)
   {
      g_persist.loss_trades++;
      g_persist.gross_loss += MathAbs(net);

      // Kalah di tahap mana pun -> Langsung reset ke 1.0x!
      g_persist.am_step      = 0;
      g_persist.current_mult = 1.0;
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
   int panel_w = 345;
   int panel_h = g_dash_minimized ? 36 : 265;

   ObjectCreate(0, UI_PFX + "BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_XDISTANCE, 12);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_YDISTANCE, 20);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_XSIZE, panel_w);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_YSIZE, panel_h);
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_BGCOLOR, C'18,20,26');
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_BORDER_COLOR, C'235,155,30');
   ObjectSetInteger(0, UI_PFX + "BG", OBJPROP_WIDTH, 1);

   DrawLabel(UI_PFX + "TITLE", 22, 27, "VULCARES Vx V6.0  |  BANKED ANTI-M 2X", C'245,180,45', 9, true);
   DrawButton(UI_PFX + "BTN_MIN", 320, 25, 28, 22, g_dash_minimized ? "+" : "-", C'45,50,62', clrWhite);

   if(g_dash_minimized) { ChartRedraw(0); return; }

   bool is_on = (g_persist.user_control == CTRL_EA_ON);
   DrawButton(UI_PFX + "BTN_TOGGLE", 22,  56, 77, 26, is_on ? "EA: ON" : "EA: OFF", is_on ? C'30,155,75' : C'95,100,110', clrWhite);
   DrawButton(UI_PFX + "BTN_STOP",   104, 56, 77, 26, "STOP EA", C'215,120,25', clrWhite);
   DrawButton(UI_PFX + "BTN_CLOSE",  186, 56, 77, 26, "CLOSE",   C'175,65,35',  clrWhite);
   DrawButton(UI_PFX + "BTN_EMERG",  268, 56, 78, 26, "EMERG",   C'195,25,25',  clrWhite);

   for(int i = 0; i < 9; i++)
      DrawLabel(StringFormat("%sROW_%d", UI_PFX, i), 22, 92 + i * 20, "...", C'220,225,235', 8, (i == 0 || i == 2));

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
   double net  = g_persist.gross_profit - g_persist.gross_loss;
   double wr   = (g_persist.total_trades > 0) ? ((double)g_persist.win_trades / g_persist.total_trades) * 100.0 : 0.0;

   string r[9];
   r[0] = StringFormat("STATUS  : %s (%s)", EnumToString(g_exec_state), g_status_note);
   r[1] = StringFormat("CAPITAL : %.0f %s  |  BALANCE: %.2f %s", g_persist.initial_capital, curr, bal, curr);
   r[2] = StringFormat("ANTI-M  : %.0fx ACTIVE RISK = %.2f %s (STEP %d/2)", g_persist.current_mult, GetCurrentRiskBudget(), curr, g_persist.am_step + 1);
   r[3] = "-------------------------------------------------";
   r[4] = StringFormat("SIGNAL  : %s (BUY %.0f%% | SELL %.0f%%)", g_last_signal, g_buy_prob, g_sell_prob);
   r[5] = StringFormat("STATS   : %d TRADES (W:%d L:%d) | WR: %.1f%%", g_persist.total_trades, g_persist.win_trades, g_persist.loss_trades, wr);
   r[6] = StringFormat("NET PNL : %+.2f %s  |  SPREAD: %I64d pts", net, curr, SymbolInfoInteger(g_validated_symbol, SYMBOL_SPREAD));

   ulong tkt = GetActiveTicket();
   if(tkt > 0 && g_pos.SelectByTicket(tkt))
   {
      double flt = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      r[7] = StringFormat("ACTIVE  : %s %.2f LOT @ %.2f", (g_pos.PositionType()==POSITION_TYPE_BUY?"BUY":"SELL"), g_pos.Volume(), g_pos.PriceOpen());
      r[8] = StringFormat("FLOAT   : %+.2f %s  |  SL: %.2f", flt, curr, g_pos.StopLoss());
   }
   else
   {
      r[7] = "ACTIVE  : NONE (SCANNING VALUE PULLBACK)";
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
         g_persist.daily_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
         g_persist.user_control = CTRL_EA_ON;
         g_status_note = "READY";
      }
   }
   else if(sparam == UI_PFX + "BTN_STOP")
   {
      ulong tkt = GetActiveTicket();
      g_persist.user_control = (tkt > 0) ? CTRL_SOFT_STOP_REQUESTED : CTRL_STOPPED;
   }
   else if(sparam == UI_PFX + "BTN_CLOSE")
   {
      ulong tkt = GetActiveTicket();
      if(tkt > 0) g_trade.PositionClose(tkt);
      g_persist.user_control = CTRL_STOPPED;
   }
   else if(sparam == UI_PFX + "BTN_EMERG")
   {
      g_persist.user_control = CTRL_EMERGENCY_LOCKED;
      ulong tkt = GetActiveTicket();
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
