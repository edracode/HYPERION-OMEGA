//+------------------------------------------------------------------+
//|                                              Vulcares_Vx_V11.mq5 |
//|                                  Copyright 2026, Vulcares Quant  |
//|   SLOPE-CONFIRMED VALUE PULLBACK + PROFIT-BANKED ANTIMARTINGALE  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Vulcares Quant"
#property link      "https://www.mql5.com"
#property version   "11.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>

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
   STATE_EMERGENCY_LOCKED
};

//--- Input Parameters
input group "=== 1. CAPITAL & PROFIT-BANKED ANTIMARTINGALE 2X ==="
input ulong    InpMagicNumber             = 20261111;
input double   InpInitialCapital          = 1000.00; // Modal Dasar (USD / USC)
input double   InpBaseRiskPercent         = 1.00;    // Base Risk = 1.00% ($10.00 pada modal 1000)
input bool     InpEnableAntiMartingale2x  = true;    // Aktifkan Anti-Martingale 2.0x
input double   InpAntiMartingaleMult      = 2.00;    // Pengali 2.0x setelah menang (1.0x -> 2.0x -> Banked)
input double   InpMaxPeakDrawdownPct      = 15.00;   // Batas Drawdown Maksimal 15%

input group "=== 2. SLOPE-FILTERED VALUE PULLBACK ENGINE ==="
input double   InpSL_ATR_M5_Mult          = 2.10;    // Pengali ATR M5 untuk SL
input double   InpSL_ATR_M15_Floor        = 1.15;    // Batas Bawah SL berbasis ATR M15 (Anti-Spread)
input double   InpTP_R_Ratio              = 2.15;    // Target Profit 2.15R (Surplus Penuh di Step 2)
input bool     InpUseLateBreakEven        = true;    // Geser ke BE setelah 80% jarak TP
input int      InpCooldownSec             = 20;      // Jeda antar transaksi (detik)
input bool     InpAvoidRolloverHours      = true;    // Hindari jam spread lebar (22:00 - 01:30)

input group "=== 3. UI DASHBOARD ==="
input bool     InpShowDashboard           = true;

//--- Persistent State
struct PersistentState
{
   double   initial_capital;
   double   equity_peak;
   int      am_step;            // 0 = Base 1.0x, 1 = Boosted 2.0x
   double   current_mult;
   int      user_control;
   bool     hard_dd_locked;
   bool     be_applied;
   int      total_trades;
   int      win_trades;
   int      loss_trades;
   double   gross_profit;
   double   gross_loss;
};

CTrade          g_trade;
CSymbolInfo     g_symbol;
CPositionInfo   g_pos;

ENUM_EXEC_STATE g_exec_state      = STATE_SCANNING;
PersistentState g_persist;

int g_hATR_M5     = INVALID_HANDLE;
int g_hATR_M15    = INVALID_HANDLE;
int g_hEMA_50_H1  = INVALID_HANDLE;
int g_hEMA_21_M15 = INVALID_HANDLE;
int g_hEMA_50_M15 = INVALID_HANDLE;
int g_hEMA_20_M5  = INVALID_HANDLE;
int g_hBB_20_M5   = INVALID_HANDLE;
int g_hRSI_14_M5  = INVALID_HANDLE;
int g_hStoch_M1   = INVALID_HANDLE;

string   g_gv_prefix        = "";
string   g_status_note      = "ACTIVE";
string   g_last_signal      = "SCANNING";
double   g_buy_prob         = 50.0;
double   g_sell_prob        = 50.0;
datetime g_last_close_time  = 0;
datetime g_last_m1_bar      = 0;
bool     g_dash_minimized   = false;
bool     g_dash_dirty       = true;

#define UI_PFX "VCX11_"

//+------------------------------------------------------------------+
//| State Persistence                                                |
//+------------------------------------------------------------------+
void BuildGVPrefix()
{
   long login = AccountInfoInteger(ACCOUNT_LOGIN);
   g_gv_prefix = StringFormat("VCX11_%I64d_%I64u_", login, InpMagicNumber);
}

void SaveState(bool flush = false)
{
   GlobalVariableSet(g_gv_prefix + "INIT_CAP", g_persist.initial_capital);
   GlobalVariableSet(g_gv_prefix + "EQ_PEAK",  g_persist.equity_peak);
   GlobalVariableSet(g_gv_prefix + "AM_STEP",  (double)g_persist.am_step);
   GlobalVariableSet(g_gv_prefix + "AM_MULT",  g_persist.current_mult);
   GlobalVariableSet(g_gv_prefix + "USR_CTRL", (double)g_persist.user_control);
   GlobalVariableSet(g_gv_prefix + "HARD_DD",  g_persist.hard_dd_locked ? 1.0 : 0.0);
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
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);

   if(!GlobalVariableCheck(g_gv_prefix + "INIT_CAP") || MQLInfoInteger(MQL_TESTER))
   {
      ZeroMemory(g_persist);
      g_persist.initial_capital = (InpInitialCapital > 0.0) ? InpInitialCapital : bal;
      g_persist.equity_peak     = MathMax(eq, g_persist.initial_capital);
      g_persist.am_step         = 0;
      g_persist.current_mult    = 1.0;
      g_persist.user_control    = CTRL_EA_ON;
      SaveState(true);
      return;
   }

   g_persist.initial_capital = GlobalVariableGet(g_gv_prefix + "INIT_CAP");
   g_persist.equity_peak     = GlobalVariableGet(g_gv_prefix + "EQ_PEAK");
   g_persist.am_step         = (int)GlobalVariableGet(g_gv_prefix + "AM_STEP");
   g_persist.current_mult    = GlobalVariableGet(g_gv_prefix + "AM_MULT");
   if(g_persist.current_mult < 1.0) g_persist.current_mult = 1.0;
   g_persist.user_control    = (int)GlobalVariableGet(g_gv_prefix + "USR_CTRL");
   g_persist.hard_dd_locked  = (GlobalVariableGet(g_gv_prefix + "HARD_DD") > 0.5);
   g_persist.be_applied      = (GlobalVariableGet(g_gv_prefix + "BE_APP") > 0.5);
   g_persist.total_trades    = (int)GlobalVariableGet(g_gv_prefix + "TOT_TRD");
   g_persist.win_trades      = (int)GlobalVariableGet(g_gv_prefix + "WIN_TRD");
   g_persist.loss_trades     = (int)GlobalVariableGet(g_gv_prefix + "LOS_TRD");
   g_persist.gross_profit    = GlobalVariableGet(g_gv_prefix + "GRS_PROF");
   g_persist.gross_loss      = GlobalVariableGet(g_gv_prefix + "GRS_LOSS");
}

//+------------------------------------------------------------------+
//| Price & Lot Helpers                                              |
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
   g_symbol.Name(_Symbol);
   g_symbol.RefreshRates();

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints(40);
   g_trade.SetTypeFilling(GetFillingMode(_Symbol));
   g_trade.SetAsyncMode(false);

   LoadState();
   g_persist.user_control   = CTRL_EA_ON;
   g_persist.hard_dd_locked = false;

   g_hATR_M5     = iATR(_Symbol, PERIOD_M5, 14);
   g_hATR_M15    = iATR(_Symbol, PERIOD_M15, 14);
   g_hEMA_50_H1  = iMA(_Symbol, PERIOD_H1,  50, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_21_M15 = iMA(_Symbol, PERIOD_M15, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_50_M15 = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_20_M5  = iMA(_Symbol, PERIOD_M5,  20, 0, MODE_EMA, PRICE_CLOSE);
   g_hBB_20_M5   = iBands(_Symbol, PERIOD_M5, 20, 0, 2.0, PRICE_CLOSE);
   g_hRSI_14_M5  = iRSI(_Symbol, PERIOD_M5, 14, PRICE_CLOSE);
   g_hStoch_M1   = iStochastic(_Symbol, PERIOD_M1, 8, 3, 3, MODE_SMA, STO_LOWHIGH);

   ReconcileState();
   if(InpShowDashboard) BuildDashboard();
   EventSetMillisecondTimer(300);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   SaveState(true);
   if(g_hATR_M5 != INVALID_HANDLE)     IndicatorRelease(g_hATR_M5);
   if(g_hATR_M15 != INVALID_HANDLE)    IndicatorRelease(g_hATR_M15);
   if(g_hEMA_50_H1 != INVALID_HANDLE)  IndicatorRelease(g_hEMA_50_H1);
   if(g_hEMA_21_M15 != INVALID_HANDLE) IndicatorRelease(g_hEMA_21_M15);
   if(g_hEMA_50_M15 != INVALID_HANDLE) IndicatorRelease(g_hEMA_50_M15);
   if(g_hEMA_20_M5 != INVALID_HANDLE)  IndicatorRelease(g_hEMA_20_M5);
   if(g_hBB_20_M5 != INVALID_HANDLE)   IndicatorRelease(g_hBB_20_M5);
   if(g_hRSI_14_M5 != INVALID_HANDLE)  IndicatorRelease(g_hRSI_14_M5);
   if(g_hStoch_M1 != INVALID_HANDLE)   IndicatorRelease(g_hStoch_M1);
   ObjectsDeleteAll(0, UI_PFX);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Risk Budget & Lot Calculation (Anti-Martingale 2.0x)             |
//+------------------------------------------------------------------+
double GetCurrentRiskBudget()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double cap = MathMax(g_persist.initial_capital, MathMin(eq, g_persist.initial_capital * 1.5));
   double base_risk = (cap * InpBaseRiskPercent) / 100.0;
   double mult = InpEnableAntiMartingale2x ? g_persist.current_mult : 1.0;
   return base_risk * mult;
}

double ComputeSafeLot(ENUM_ORDER_TYPE ord_type, double entry_p, double sl_p)
{
   double risk_budget = GetCurrentRiskBudget();
   double vol_min  = g_symbol.LotsMin();
   double vol_max  = g_symbol.LotsMax();
   double vol_step = g_symbol.LotsStep();

   double prof_1lot = 0.0;
   if(!OrderCalcProfit(ord_type, _Symbol, 1.0, entry_p, sl_p, prof_1lot))
      return vol_min;

   double loss_1lot = MathAbs(prof_1lot);
   if(loss_1lot <= 0.0) return vol_min;

   double lot = NormLot((risk_budget * 0.90) / loss_1lot);
   if(lot < vol_min)
   {
      double min_loss = 0.0;
      if(OrderCalcProfit(ord_type, _Symbol, vol_min, entry_p, sl_p, min_loss) && MathAbs(min_loss) <= risk_budget * 1.25)
         lot = vol_min;
      else
      {
         g_status_note = "ATR_HIGH_SKIP";
         return 0.0;
      }
   }
   if(lot > vol_max) lot = vol_max;

   double actual_loss = 0.0;
   OrderCalcProfit(ord_type, _Symbol, lot, entry_p, sl_p, actual_loss);
   while(MathAbs(actual_loss) > risk_budget * 1.25 && lot > vol_min)
   {
      lot = NormLot(lot - vol_step);
      if(lot < vol_min) return 0.0;
      OrderCalcProfit(ord_type, _Symbol, lot, entry_p, sl_p, actual_loss);
   }
   return lot;
}

//+------------------------------------------------------------------+
//| Active Position Helper                                           |
//+------------------------------------------------------------------+
ulong GetActiveTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(g_pos.SelectByIndex(i) && g_pos.Symbol() == _Symbol && g_pos.Magic() == InpMagicNumber)
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
      g_exec_state = (g_persist.user_control == CTRL_SOFT_STOP_REQUESTED) ? STATE_STOPPING_AFTER_POS : STATE_IN_POSITION;
   else
   {
      g_persist.be_applied = false;
      if(g_persist.user_control == CTRL_SOFT_STOP_REQUESTED || g_persist.user_control == CTRL_STOPPED)
      {
         g_persist.user_control = CTRL_STOPPED;
         g_exec_state = STATE_STOPPED;
      }
      else if(g_persist.user_control == CTRL_EA_OFF)
         g_exec_state = STATE_STOPPED;
      else
         g_exec_state = STATE_SCANNING;
   }
   g_dash_dirty = true;
}

//+------------------------------------------------------------------+
//| Slope-Confirmed Value Pullback Engine (H1 + M15 + M5 + M1)       |
//+------------------------------------------------------------------+
int EvaluateValuePullback(double &sl_dist_out)
{
   double atr5[2], atr15[2], e50_h1[2], e21_15[2], e50_15[2], e20_5[2], bb_u[2], bb_l[2], rsi5[2], sto_m[2], sto_s[2];
   if(CopyBuffer(g_hATR_M5,     0, 0, 2, atr5)   < 2 ||
      CopyBuffer(g_hATR_M15,    0, 0, 2, atr15)  < 2 ||
      CopyBuffer(g_hEMA_50_H1,  0, 0, 2, e50_h1) < 2 ||
      CopyBuffer(g_hEMA_21_M15, 0, 0, 2, e21_15) < 2 ||
      CopyBuffer(g_hEMA_50_M15, 0, 0, 2, e50_15) < 2 ||
      CopyBuffer(g_hEMA_20_M5,  0, 0, 2, e20_5)  < 2 ||
      CopyBuffer(g_hBB_20_M5,   1, 0, 2, bb_u)   < 2 ||
      CopyBuffer(g_hBB_20_M5,   2, 0, 2, bb_l)   < 2 ||
      CopyBuffer(g_hRSI_14_M5,  0, 0, 2, rsi5)   < 2 ||
      CopyBuffer(g_hStoch_M1,   0, 0, 2, sto_m)  < 2 ||
      CopyBuffer(g_hStoch_M1,   1, 0, 2, sto_s)  < 2)
   {
      g_status_note = "SYNCING_DATA";
      return 0;
   }

   double bid   = g_symbol.Bid();
   double m1_c1 = iClose(_Symbol, PERIOD_M1, 1);
   double m1_o1 = iOpen(_Symbol, PERIOD_M1, 1);
   double m1_l1 = iLow(_Symbol, PERIOD_M1, 1);
   double m1_h1 = iHigh(_Symbol, PERIOD_M1, 1);

   // Hybrid ATR Floor prevents spread sweeps during quiet sessions
   sl_dist_out = MathMax(atr5[0] * InpSL_ATR_M5_Mult, atr15[0] * InpSL_ATR_M15_Floor);

   // Triple-EMA Alignment + Active Slope Confirmation
   bool macro_bull = (bid > e50_h1[0] && e21_15[0] > e50_15[0] &&
                      e50_h1[0] > e50_h1[1] && e21_15[0] > e21_15[1] && e20_5[0] > e20_5[1]);

   bool macro_bear = (bid < e50_h1[0] && e21_15[0] < e50_15[0] &&
                      e50_h1[0] < e50_h1[1] && e21_15[0] < e21_15[1] && e20_5[0] < e20_5[1]);

   // Buy at Value Discount inside Confirmed Uptrend
   bool buy_pullback  = (macro_bull && (m1_l1 <= e20_5[0] || m1_l1 <= bb_l[0]) &&
                         rsi5[0] > 42.0 && rsi5[0] < 65.0 &&
                         sto_m[0] < 36.0 && sto_m[0] > sto_s[0] && m1_c1 > m1_o1);

   // Sell at Value Premium inside Confirmed Downtrend
   bool sell_pullback = (macro_bear && (m1_h1 >= e20_5[0] || m1_h1 >= bb_u[0]) &&
                         rsi5[0] < 58.0 && rsi5[0] > 35.0 &&
                         sto_m[0] > 64.0 && sto_m[0] < sto_s[0] && m1_c1 < m1_o1);

   if(buy_pullback)
   {
      g_buy_prob = 88.0; g_sell_prob = 12.0;
      g_last_signal = "BUY VALUE";
      return 1;
   }
   if(sell_pullback)
   {
      g_buy_prob = 12.0; g_sell_prob = 88.0;
      g_last_signal = "SELL VALUE";
      return -1;
   }

   if(macro_bull)      { g_buy_prob = 70.0; g_sell_prob = 30.0; g_status_note = "WAIT_BUY_DISCOUNT"; }
   else if(macro_bear) { g_buy_prob = 30.0; g_sell_prob = 70.0; g_status_note = "WAIT_SELL_PREMIUM"; }
   else                { g_buy_prob = 50.0; g_sell_prob = 50.0; g_status_note = "SLOPE_NEUTRAL"; }

   g_last_signal = "SCANNING";
   return 0;
}

//+------------------------------------------------------------------+
//| Late Break-Even Protection (80% of TP Distance)                  |
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

   if(total_dist > 0.0 && cur_gain >= total_dist * 0.80)
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

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_persist.equity_peak) g_persist.equity_peak = eq;
   double dd_pct = (g_persist.equity_peak > 0.0) ? ((g_persist.equity_peak - eq) / g_persist.equity_peak) * 100.0 : 0.0;
   if(dd_pct >= InpMaxPeakDrawdownPct || g_persist.hard_dd_locked)
   {
      g_persist.hard_dd_locked = true;
      g_exec_state = STATE_RISK_LOCKED;
      g_status_note = "MAX_DD_LOCKED";
      return;
   }

   if(InpAvoidRolloverHours)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.hour >= 22 || dt.hour == 0 || (dt.hour == 1 && dt.min < 30))
      {
         g_status_note = "ROLLOVER_PAUSE";
         return;
      }
   }

   if(TimeCurrent() - g_last_close_time < InpCooldownSec)
   {
      g_status_note = "COOLDOWN_WAIT";
      return;
   }

   datetime cur_m1 = iTime(_Symbol, PERIOD_M1, 0);
   if(cur_m1 == g_last_m1_bar) return;
   g_last_m1_bar = cur_m1;

   double sl_dist = 0.0;
   int dir = EvaluateValuePullback(sl_dist);
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

   double lot = ComputeSafeLot(is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, entry_p, sl_price);
   if(lot <= 0.0) return;

   string cmt = StringFormat("VCX11_AM%.0fx", g_persist.current_mult);
   bool sent = is_buy ? g_trade.Buy(lot, _Symbol, ask, sl_price, tp_price, cmt)
                      : g_trade.Sell(lot, _Symbol, bid, sl_price, tp_price, cmt);

   if(sent && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
   {
      g_status_note = "IN_TRADE";
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
//| Trade Deal Listener (Profit-Banked Anti-Martingale 2.0x)          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;

   ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   if(dtype == DEAL_TYPE_BALANCE || dtype == DEAL_TYPE_CREDIT || dtype == DEAL_TYPE_BONUS)
   {
      double amt = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      if(amt > 0.0) g_persist.equity_peak += amt;
      SaveState(true);
      g_dash_dirty = true;
      return;
   }

   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != (long)InpMagicNumber ||
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol ||
      HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                HistoryDealGetDouble(trans.deal, DEAL_SWAP) +
                HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   g_persist.total_trades++;
   if(net > 0.0)
   {
      g_persist.win_trades++;
      g_persist.gross_profit += net;

      if(InpEnableAntiMartingale2x && g_persist.am_step == 0)
      {
         g_persist.am_step      = 1;
         g_persist.current_mult = InpAntiMartingaleMult;
      }
      else
      {
         g_persist.am_step      = 0;
         g_persist.current_mult = 1.0;
      }
   }
   else if(net < 0.0)
   {
      g_persist.loss_trades++;
      g_persist.gross_loss += MathAbs(net);

      g_persist.am_step      = 0;
      g_persist.current_mult = 1.0;
   }

   g_last_close_time = TimeCurrent();
   SaveState(true);
   ReconcileState();
}

void OnTimer()
{
   if(!InpShowDashboard) return;
   if(ObjectFind(0, UI_PFX + "BG") < 0) BuildDashboard();
   if(g_dash_dirty) { UpdateDashboard(); g_dash_dirty = false; }
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

   DrawLabel(UI_PFX + "TITLE", 22, 27, "VULCARES Vx V11.0 | SLOPE ANTI-M 2X", C'245,180,45', 9, true);
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
   r[6] = StringFormat("NET PNL : %+.2f %s  |  SPREAD: %I64d pts", net, curr, SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));

   ulong tkt = GetActiveTicket();
   if(tkt > 0 && g_pos.SelectByTicket(tkt))
   {
      double flt = g_pos.Profit() + g_pos.Swap() + g_pos.Commission();
      r[7] = StringFormat("ACTIVE  : %s %.2f LOT @ %.2f", (g_pos.PositionType()==POSITION_TYPE_BUY?"BUY":"SELL"), g_pos.Volume(), g_pos.PriceOpen());
      r[8] = StringFormat("FLOAT   : %+.2f %s  |  SL: %.2f", flt, curr, g_pos.StopLoss());
   }
   else
   {
      r[7] = "ACTIVE  : NONE (SCANNING SLOPE PULLBACK)";
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
         g_persist.equity_peak = AccountInfoDouble(ACCOUNT_EQUITY);
         g_persist.user_control = CTRL_EA_ON;
         g_status_note = "ACTIVE";
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
