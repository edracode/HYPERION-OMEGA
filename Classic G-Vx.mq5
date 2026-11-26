//+------------------------------------------------------------------+
//|                                                 Classic G-Vx.mq5 |
//|                                  Copyright 2026, Quant Architecture |
//|                     Adaptive Multi-Regime Grid Expert Advisor    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Quant Architecture"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_GRID_MODE {
   MODE_AUTO       = 0, // AUTO (Regime Classifier)
   MODE_RANGE_ONLY = 1, // RANGE GRID Only
   MODE_TREND_ONLY = 2  // TREND GRID Only
};

enum ENUM_ACTIVE_REGIME {
   REGIME_NONE  = 0,
   REGIME_RANGE = 1,
   REGIME_TREND = 2
};

enum ENUM_LOT_MODE {
   LOT_FIXED        = 0, // Fixed Base Lot
   LOT_RISK_PERCENT = 1  // Risk % of Equity
};

enum ENUM_TARGET_MODE {
   TARGET_FIXED_MONEY = 0, // Fixed Currency Amount
   TARGET_ATR_SCALED  = 1  // ATR Scaled Basket Target
};

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== 1. SYSTEM & SAFETY ==="
input ulong          InpMagicNumber        = 20261126;        // Magic Number
input string         InpTradeComment       = "Classic G-Vx";  // Order Comment
input bool           InpAllowDemo          = true;            // Allow Demo Account
input bool           InpAllowLive          = false;           // Allow Real/Live Account (Blocked Default)
input bool           InpSingleSymbolOnly   = true;            // Enforce Single Symbol Isolation
input bool           InpEmergencyStop      = false;           // TRIGGER EMERGENCY STOP (Manual Override)
input bool           InpResetLock          = false;           // Reset Emergency Lock on Init

input group "=== 2. STRATEGY & REGIME ENGINE ==="
input ENUM_GRID_MODE InpGridMode           = MODE_AUTO;       // Strategy Execution Mode
input ENUM_TIMEFRAMES InpSignalTF          = PERIOD_M15;      // Signal & Grid Timeframe
input ENUM_TIMEFRAMES InpTrendTF           = PERIOD_H1;       // Higher Timeframe (Trend Filter)
input int            InpADXPeriod          = 14;              // ADX Period (Regime & Trend)
input double         InpADXTrendEnter      = 28.0;            // ADX Threshold to ENTER Trend Mode
input double         InpADXTrendExit       = 22.0;            // ADX Threshold to EXIT Trend Mode (Hysteresis)
input double         InpADXRangeMax        = 20.0;            // Max ADX for Range Mode
input int            InpEMAFast            = 20;              // Fast EMA Period (Slope/Trend)
input int            InpEMASlow            = 50;              // Slow EMA Period (Trend Bias)
input double         InpMinEMASlopeATR     = 0.15;            // Min EMA Slope (in ATR units) for Trend
input int            InpBBPeriod           = 20;              // Bollinger Bands Period (Range Extremes)
input double         InpBBDeviation        = 2.0;             // Bollinger Bands Deviation
input int            InpRSIPeriod          = 14;              // RSI Period (Range Confirmation)
input double         InpRSIOverbought      = 70.0;            // RSI Overbought Level
input double         InpRSIOversold        = 30.0;            // RSI Oversold Level

input group "=== 3. ADAPTIVE GRID & GEOMETRY ==="
input int            InpATRPeriod          = 14;              // ATR Period for Step & Volatility
input double         InpATRStepMultiplier  = 1.2;             // BaseStep = ATR * Multiplier
input double         InpSpikeATRMult       = 2.5;             // Block Entry if Bar Range > ATR * SpikeMult
input double         InpGridMultiplier     = 1.35;            // Geometric Step Multiplier (from 3rd pos)
input int            InpMaxGridLevels      = 5;               // Max Grid Levels per Basket
input int            InpCooldownSeconds    = 60;              // Cooldown Between Grid Additions (Sec)
input double         InpMaxSpreadATR       = 0.25;            // Max Spread as Fraction of ATR (0 = off)
input double         InpMaxSpreadPoints    = 500;             // Max Spread in Points

input group "=== 4. SIZING & BASKET EXIT ==="
input ENUM_LOT_MODE  InpLotMode            = LOT_FIXED;       // Base Lot Sizing Mode
input double         InpFixedLot           = 0.01;            // Fixed Base Lot Size
input double         InpRiskPercent        = 0.5;             // Risk % per Basket (if Risk Mode)
input bool           InpUseLotMultiplier   = false;           // Enable Geometric Lot Multiplier (Optional)
input double         InpLotMultiplier      = 1.25;            // Lot Multiplier (if enabled)
input double         InpMaxBasketVolume    = 0.50;            // Hard Cap Total Basket Volume
input ENUM_TARGET_MODE InpTargetMode       = TARGET_ATR_SCALED; // Basket Take Profit Mode
input double         InpFixedBasketTP      = 25.0;            // Fixed Net Profit Target (Account Currency)
input double         InpATRBasketTPMult    = 0.8;             // ATR TP Multiplier (scaled by base volume)
input bool           InpUseBasketTrail     = true;            // Enable Basket Profit Trailing
input double         InpTrailStartPct      = 0.70;            // Start Trailing at % of TP Target
input double         InpTrailDropPct       = 0.30;            // Close if Profit Drops by % from Peak
input double         InpBasketHardSLMoney  = 150.0;           // Hard Basket Stop Loss (Account Currency)
input int            InpMaxCycleHours      = 72;              // Max Basket Duration in Hours (0 = off)
input bool           InpCloseOnTrendBreak  = true;            // Close Trend Basket if HTF Trend Breaks

input group "=== 5. PORTFOLIO & ACCOUNT RISK LIMITS ==="
input double         InpMaxDailyLossPct    = 3.0;             // Max Daily Equity Loss % (Blocks & Closes)
input double         InpMaxAccountDDPct    = 10.0;            // Max Account Drawdown % from Peak (Emergency)
input double         InpMinFreeMarginPct   = 200.0;           // Min Margin Level % Allowed for New Entry
input double         InpMaxTotalExposure   = 1.00;            // Max Total Volume Across Symbol/Account
input double         InpEstExitSlippagePts = 20.0;            // Estimated Exit Slippage Buffer (Points)
input double         InpCommPerLotRound    = 7.0;             // Estimated Round-Turn Commission per Lot

//+------------------------------------------------------------------+
//| Global State & Objects                                           |
//+------------------------------------------------------------------+
CTrade         ExtTrade;
CSymbolInfo    ExtSymbol;
CPositionInfo  ExtPos;
CAccountInfo   ExtAcc;

// Indicator Handles
int hATR_Sig   = INVALID_HANDLE;
int hADX_Sig   = INVALID_HANDLE;
int hEMA_F_Sig = INVALID_HANDLE;
int hEMA_S_Sig = INVALID_HANDLE;
int hBB_Sig    = INVALID_HANDLE;
int hRSI_Sig   = INVALID_HANDLE;
int hADX_HTF   = INVALID_HANDLE;
int hEMA_F_HTF = INVALID_HANDLE;
int hEMA_S_HTF = INVALID_HANDLE;

// Frozen Cycle State (Persisted via GlobalVariables)
struct BasketState {
   bool               active;
   ENUM_POSITION_TYPE direction;       // POSITION_TYPE_BUY or POSITION_TYPE_SELL
   ENUM_ACTIVE_REGIME regime;          // Frozen regime at cycle start
   double             frozenBaseStep;  // Frozen BaseStep in price units
   double             frozenATR;       // Frozen ATR at cycle start
   datetime           openTime;        // First fill timestamp
   datetime           lastAddTime;     // Last grid level timestamp
   double             peakNetProfit;   // Highest net profit reached for trailing
   int                levelCount;      // Current open positions in basket
   double             totalVolume;     // Total open lots
   double             lastFillPrice;   // Execution price of the latest fill
   double             breakEvenPrice;  // True net break-even price including costs
   double             netFloatingPL;   // Net floating P/L after swap, comm, exit slippage
};

BasketState g_Basket;
ENUM_ACTIVE_REGIME g_CurrentRegime = REGIME_NONE;

// System & Risk Locks
bool     g_EmergencyLocked    = false;
bool     g_DailyLimitHit      = false;
bool     g_OrderInFlight      = false;
datetime g_OrderSentTime      = 0;
datetime g_LastBarTime        = 0;
datetime g_LastLogTime        = 0;
string   g_LastLogReason      = "";
double   g_DailyStartEquity   = 0.0;
int      g_LastDayOfYear      = -1;
double   g_PeakEquity         = 0.0;
int      g_CloseRetryCount    = 0;
datetime g_LastRetryTime      = 0;

// GlobalVariable Prefix
string   g_GVPrefix;

//+------------------------------------------------------------------+
//| Throttled Journal Logging                                        |
//+------------------------------------------------------------------+
void LogStatus(string reason, bool force = false) {
   datetime now = TimeCurrent();
   if(!force && reason == g_LastLogReason && (now - g_LastLogTime) < 300)
      return;
   g_LastLogReason = reason;
   g_LastLogTime   = now;
   PrintFormat("[%s | %s] %s", InpTradeComment, _Symbol, reason);
}

//+------------------------------------------------------------------+
//| Save & Restore Cycle State (Crash/Restart Recovery)              |
//+------------------------------------------------------------------+
void SaveState() {
   GlobalVariableSet(g_GVPrefix + "LOCK", g_EmergencyLocked ? 1.0 : 0.0);
   GlobalVariableSet(g_GVPrefix + "PEAK_EQ", g_PeakEquity);
   GlobalVariableSet(g_GVPrefix + "DAY_EQ", g_DailyStartEquity);
   GlobalVariableSet(g_GVPrefix + "DAY_NUM", (double)g_LastDayOfYear);

   if(g_Basket.active) {
      GlobalVariableSet(g_GVPrefix + "ACTIVE", 1.0);
      GlobalVariableSet(g_GVPrefix + "DIR", (double)g_Basket.direction);
      GlobalVariableSet(g_GVPrefix + "REGIME", (double)g_Basket.regime);
      GlobalVariableSet(g_GVPrefix + "STEP", g_Basket.frozenBaseStep);
      GlobalVariableSet(g_GVPrefix + "ATR", g_Basket.frozenATR);
      GlobalVariableSet(g_GVPrefix + "OPENTIME", (double)g_Basket.openTime);
      GlobalVariableSet(g_GVPrefix + "PEAKPL", g_Basket.peakNetProfit);
   } else {
      GlobalVariableSet(g_GVPrefix + "ACTIVE", 0.0);
   }
}

void RestoreState() {
   if(GlobalVariableCheck(g_GVPrefix + "LOCK"))
      g_EmergencyLocked = (GlobalVariableGet(g_GVPrefix + "LOCK") > 0.5);
   if(InpResetLock && g_EmergencyLocked) {
      g_EmergencyLocked = false;
      Print("Manual ResetLock applied. Emergency lock cleared.");
   }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_PeakEquity = GlobalVariableCheck(g_GVPrefix + "PEAK_EQ") ? GlobalVariableGet(g_GVPrefix + "PEAK_EQ") : eq;
   if(eq > g_PeakEquity) g_PeakEquity = eq;

   MqlDateTime dt;
   TimeCurrent(dt);
   if(GlobalVariableCheck(g_GVPrefix + "DAY_NUM") && (int)GlobalVariableGet(g_GVPrefix + "DAY_NUM") == dt.day_of_year) {
      g_LastDayOfYear    = dt.day_of_year;
      g_DailyStartEquity = GlobalVariableGet(g_GVPrefix + "DAY_EQ");
   } else {
      g_LastDayOfYear    = dt.day_of_year;
      g_DailyStartEquity = eq;
   }

   // Reconcile actual open positions first
   ReconcilePositions();

   if(g_Basket.levelCount > 0) {
      g_Basket.active = true;
      if(GlobalVariableCheck(g_GVPrefix + "ACTIVE") && GlobalVariableGet(g_GVPrefix + "ACTIVE") > 0.5) {
         g_Basket.regime         = (ENUM_ACTIVE_REGIME)((int)GlobalVariableGet(g_GVPrefix + "REGIME"));
         g_Basket.frozenBaseStep = GlobalVariableGet(g_GVPrefix + "STEP");
         g_Basket.frozenATR      = GlobalVariableGet(g_GVPrefix + "ATR");
         g_Basket.openTime       = (datetime)GlobalVariableGet(g_GVPrefix + "OPENTIME");
         g_Basket.peakNetProfit  = GlobalVariableGet(g_GVPrefix + "PEAKPL");
         LogStatus(StringFormat("Restored active basket after restart: %d levels, Vol=%.2f, Regime=%d",
                   g_Basket.levelCount, g_Basket.totalVolume, g_Basket.regime), true);
      } else {
         // Fallback if GlobalVariables were wiped while positions stayed open
         double atr[1];
         if(CopyBuffer(hATR_Sig, 0, 1, 1, atr) > 0) {
            g_Basket.frozenATR      = atr[0];
            g_Basket.frozenBaseStep = atr[0] * InpATRStepMultiplier;
         } else {
            g_Basket.frozenBaseStep = 100 * ExtSymbol.Point();
         }
         g_Basket.regime = (InpGridMode == MODE_TREND_ONLY) ? REGIME_TREND : REGIME_RANGE;
         LogStatus("Recovered orphan EA positions into reconstructed basket state.", true);
      }
      SaveState();
   } else {
      ZeroMemory(g_Basket);
      SaveState();
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   PrintFormat("=== [%s] Initializing on %s (Timeframe: %s) ===", InpTradeComment, _Symbol, EnumToString(InpSignalTF));

   // 1. Account Environment Check (Demo vs Live)
   ENUM_ACCOUNT_TRADE_MODE accMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(accMode == ACCOUNT_TRADE_MODE_REAL && !InpAllowLive) {
      Print("INIT_FAILED: Real/Live account execution is disabled by default (InpAllowLive=false).");
      return(INIT_FAILED);
   }
   if(accMode == ACCOUNT_TRADE_MODE_DEMO && !InpAllowDemo && !MQLInfoInteger(MQL_TESTER)) {
      Print("INIT_FAILED: Demo account execution is disabled (InpAllowDemo=false).");
      return(INIT_FAILED);
   }

   // 2. Parameter Validation
   if(InpMaxGridLevels < 1 || InpMaxGridLevels > 30) {
      Print("INIT_PARAMETERS_INCORRECT: InpMaxGridLevels must be between 1 and 30.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpGridMultiplier < 1.0 || InpATRStepMultiplier <= 0.0) {
      Print("INIT_PARAMETERS_INCORRECT: InpGridMultiplier must be >= 1.0 and InpATRStepMultiplier > 0.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpADXTrendEnter <= InpADXTrendExit) {
      Print("INIT_PARAMETERS_INCORRECT: InpADXTrendEnter must be > InpADXTrendExit for hysteresis.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(InpFixedLot <= 0.0 && InpLotMode == LOT_FIXED) {
      Print("INIT_PARAMETERS_INCORRECT: InpFixedLot must be > 0.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   // 3. Symbol Initialization & Contract Specs
   if(!ExtSymbol.Name(_Symbol)) {
      PrintFormat("INIT_FAILED: Unable to bind symbol %s.", _Symbol);
      return(INIT_FAILED);
   }
   ExtSymbol.Refresh();
   ExtSymbol.RefreshRates();

   if(ExtSymbol.LotsMin() <= 0 || ExtSymbol.LotsStep() <= 0 || ExtSymbol.TickSize() <= 0) {
      PrintFormat("INIT_FAILED: Invalid contract specifications for %s (LotsMin=%.4f, TickSize=%.6f).",
                  _Symbol, ExtSymbol.LotsMin(), ExtSymbol.TickSize());
      return(INIT_FAILED);
   }

   // 4. Configure CTrade & Filling Mode
   ExtTrade.SetExpertMagicNumber(InpMagicNumber);
   ExtTrade.SetDeviationInPoints(30);
   ExtTrade.SetAsyncMode(false);
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      ExtTrade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      ExtTrade.SetTypeFilling(ORDER_FILLING_RETURN);

   // 5. Initialize Indicator Handles
   hATR_Sig   = iATR(_Symbol, InpSignalTF, InpATRPeriod);
   hADX_Sig   = iADX(_Symbol, InpSignalTF, InpADXPeriod);
   hEMA_F_Sig = iMA(_Symbol, InpSignalTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA_S_Sig = iMA(_Symbol, InpSignalTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);
   hBB_Sig    = iBands(_Symbol, InpSignalTF, InpBBPeriod, 0, InpBBDeviation, PRICE_CLOSE);
   hRSI_Sig   = iRSI(_Symbol, InpSignalTF, InpRSIPeriod, PRICE_CLOSE);

   hADX_HTF   = iADX(_Symbol, InpTrendTF, InpADXPeriod);
   hEMA_F_HTF = iMA(_Symbol, InpTrendTF, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   hEMA_S_HTF = iMA(_Symbol, InpTrendTF, InpEMASlow, 0, MODE_EMA, PRICE_CLOSE);

   if(hATR_Sig == INVALID_HANDLE || hADX_Sig == INVALID_HANDLE || hEMA_F_Sig == INVALID_HANDLE ||
      hEMA_S_Sig == INVALID_HANDLE || hBB_Sig == INVALID_HANDLE || hRSI_Sig == INVALID_HANDLE ||
      hADX_HTF == INVALID_HANDLE || hEMA_F_HTF == INVALID_HANDLE || hEMA_S_HTF == INVALID_HANDLE) {
      Print("INIT_FAILED: Failed to create one or more indicator handles.");
      return(INIT_FAILED);
   }

   // 6. State & Recovery Setup
   g_GVPrefix = StringFormat("CGVX_%I64u_%s_", InpMagicNumber, _Symbol);
   RestoreState();

   if(InpEmergencyStop) {
      g_EmergencyLocked = true;
      SaveState();
      Print("WARNING: InpEmergencyStop is TRUE. EA will close owned positions and lock.");
   }

   PrintFormat("=== [%s] Initialization SUCCEEDED. MarginMode=%s, Filling=%d ===",
               InpTradeComment,
               (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "HEDGING" : "NETTING"),
               ExtTrade.RequestTypeFilling());
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   SaveState();
   IndicatorRelease(hATR_Sig);
   IndicatorRelease(hADX_Sig);
   IndicatorRelease(hEMA_F_Sig);
   IndicatorRelease(hEMA_S_Sig);
   IndicatorRelease(hBB_Sig);
   IndicatorRelease(hRSI_Sig);
   IndicatorRelease(hADX_HTF);
   IndicatorRelease(hEMA_F_HTF);
   IndicatorRelease(hEMA_S_HTF);
   PrintFormat("[%s] Deinitialized. Reason code: %d", InpTradeComment, reason);
}

//+------------------------------------------------------------------+
//| Check Ownership & Symbol Isolation (Hedging & Netting Safe)      |
//+------------------------------------------------------------------+
bool CheckSymbolOwnership(string &blockReason) {
   bool isHedging = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   int totalPos = PositionsTotal();

   for(int i = 0; i < totalPos; i++) {
      if(!ExtPos.SelectByIndex(i)) continue;
      string posSym = ExtPos.Symbol();
      ulong  posMag = ExtPos.Magic();

      if(posSym == _Symbol) {
         if(!isHedging) {
            // Netting mode requires exclusive symbol ownership
            if(posMag != InpMagicNumber) {
               blockReason = StringFormat("Blocked (Netting Mode): Foreign position on %s (Magic=%I64u).", _Symbol, posMag);
               return false;
            }
         } else {
            // Hedging mode: block if foreign manual/EA position exists on same symbol per safety rule
            if(posMag != InpMagicNumber) {
               blockReason = StringFormat("Blocked (Hedging Isolation): Foreign position on %s (Magic=%I64u).", _Symbol, posMag);
               return false;
            }
         }
      } else if(InpSingleSymbolOnly && posMag == InpMagicNumber) {
         blockReason = StringFormat("Blocked: Single-symbol mode active, position exists on %s.", posSym);
         return false;
      }
   }

   // Check pending orders by other EAs/manual on same symbol
   int totalOrd = OrdersTotal();
   for(int i = 0; i < totalOrd; i++) {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) {
         blockReason = StringFormat("Blocked: Foreign pending order #%I64u on %s.", ticket, _Symbol);
         return false;
      }
   }

   return true;
}

//+------------------------------------------------------------------+
//| Reconcile Basket Positions, True Break-Even & Net Floating P/L   |
//+------------------------------------------------------------------+
void ReconcilePositions() {
   ExtSymbol.RefreshRates();
   int count = 0;
   double sumVol = 0.0;
   double weightedPrice = 0.0;
   double grossPL = 0.0;
   double totalSwap = 0.0;
   double totalComm = 0.0;
   datetime earliest = 0;
   datetime latest = 0;
   double lastPrice = 0.0;
   ENUM_POSITION_TYPE dir = POSITION_TYPE_BUY;

   for(int i = 0; i < PositionsTotal(); i++) {
      if(!ExtPos.SelectByIndex(i)) continue;
      if(ExtPos.Symbol() != _Symbol || ExtPos.Magic() != InpMagicNumber) continue;

      double vol   = ExtPos.Volume();
      double openP = ExtPos.PriceOpen();
      datetime tOpen = (datetime)ExtPos.Time();

      if(count == 0) {
         dir      = ExtPos.PositionType();
         earliest = tOpen;
         latest   = tOpen;
         lastPrice = openP;
      } else {
         if(tOpen < earliest) earliest = tOpen;
         if(tOpen >= latest) {
            latest    = tOpen;
            lastPrice = openP;
         }
      }

      count++;
      sumVol        += vol;
      weightedPrice += openP * vol;
      grossPL       += ExtPos.Profit();
      totalSwap     += ExtPos.Swap();
      // Estimate round-turn commission if broker reports 0 before close
      double posComm = ExtPos.Commission();
      totalComm     += (MathAbs(posComm) > 0.0001) ? (posComm * 2.0) : (-InpCommPerLotRound * vol);
   }

   g_Basket.levelCount  = count;
   g_Basket.totalVolume = NormalizeDouble(sumVol, 2);

   if(count == 0) {
      g_Basket.active        = false;
      g_Basket.netFloatingPL = 0.0;
      g_Basket.breakEvenPrice = 0.0;
      return;
   }

   g_Basket.active        = true;
   g_Basket.direction     = dir;
   g_Basket.openTime      = earliest;
   g_Basket.lastAddTime   = latest;
   g_Basket.lastFillPrice = lastPrice;

   double avgEntry = weightedPrice / sumVol;
   double tickVal  = ExtSymbol.TickValue();
   double tickSize = ExtSymbol.TickSize();
   double exitSlipMoney = 0.0;

   if(tickVal > 0 && tickSize > 0) {
      double slipPrice = InpEstExitSlippagePts * ExtSymbol.Point();
      exitSlipMoney = (slipPrice / tickSize) * tickVal * sumVol;
   }

   // Net P/L accounts for Bid/Ask (via ExtPos.Profit()), swap, round-turn commission, and exit slippage buffer
   g_Basket.netFloatingPL = grossPL + totalSwap + totalComm - exitSlipMoney;

   // Compute true break-even price
   if(tickVal > 0 && tickSize > 0 && sumVol > 0) {
      double costPerLot = -(totalSwap + totalComm - exitSlipMoney) / sumVol;
      double priceOffset = (costPerLot / tickVal) * tickSize;
      g_Basket.breakEvenPrice = (dir == POSITION_TYPE_BUY) ? (avgEntry + priceOffset) : (avgEntry - priceOffset);
   } else {
      g_Basket.breakEvenPrice = avgEntry;
   }
}

//+------------------------------------------------------------------+
//| Close All EA Positions & Cancel Pending Orders (With Retry)      |
//+------------------------------------------------------------------+
bool CloseAllEAOrdersAndPositions(string reason) {
   LogStatus("EXECUTING BASKET/EMERGENCY CLOSE: " + reason, true);

   // 1. Delete pending orders owned by EA
   for(int i = OrdersTotal() - 1; i >= 0; i--) {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == InpMagicNumber) {
         ExtTrade.OrderDelete(ticket);
      }
   }

   // 2. Close open positions owned by EA
   bool allClosed = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!ExtPos.SelectByIndex(i)) continue;
      if(ExtPos.Symbol() != _Symbol || ExtPos.Magic() != InpMagicNumber) continue;

      ulong ticket = ExtPos.Ticket();
      if(!ExtTrade.PositionClose(ticket)) {
         allClosed = false;
         PrintFormat("WARNING: Failed to close ticket #%I64u. Retcode=%d (%s)",
                     ticket, ExtTrade.ResultRetcode(), ExtTrade.ResultRetcodeDescription());
      }
   }

   ReconcilePositions();
   if(g_Basket.levelCount == 0) {
      ZeroMemory(g_Basket);
      g_CloseRetryCount = 0;
      SaveState();
      return true;
   }
   return allClosed;
}

//+------------------------------------------------------------------+
//| Check Account & Portfolio Risk Limits                            |
//+------------------------------------------------------------------+
bool CheckRiskLimits(string &blockReason) {
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   // Update Peak Equity
   if(equity > g_PeakEquity) g_PeakEquity = equity;

   // Daily reset check
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day_of_year != g_LastDayOfYear) {
      g_LastDayOfYear    = dt.day_of_year;
      g_DailyStartEquity = equity;
      g_DailyLimitHit    = false;
      SaveState();
   }

   // 1. Emergency Lock Check
   if(g_EmergencyLocked || InpEmergencyStop) {
      g_EmergencyLocked = true;
      if(g_Basket.levelCount > 0) CloseAllEAOrdersAndPositions("Emergency Stop Active");
      blockReason = "Blocked: EMERGENCY LOCK is active.";
      return false;
   }

   // 2. Max Account Drawdown Check (Closes basket & locks)
   double ddPct = (g_PeakEquity > 0) ? ((g_PeakEquity - equity) / g_PeakEquity) * 100.0 : 0.0;
   if(ddPct >= InpMaxAccountDDPct) {
      g_EmergencyLocked = true;
      SaveState();
      CloseAllEAOrdersAndPositions(StringFormat("Max Account Drawdown Hit (%.2f%% >= %.2f%%)", ddPct, InpMaxAccountDDPct));
      blockReason = StringFormat("Blocked: Max Account DD %.2f%% exceeded.", ddPct);
      return false;
   }

   // 3. Daily Equity Loss Check (Closes basket & blocks until next day)
   double dailyLossPct = (g_DailyStartEquity > 0) ? ((g_DailyStartEquity - equity) / g_DailyStartEquity) * 100.0 : 0.0;
   if(dailyLossPct >= InpMaxDailyLossPct || g_DailyLimitHit) {
      g_DailyLimitHit = true;
      if(g_Basket.levelCount > 0)
         CloseAllEAOrdersAndPositions(StringFormat("Max Daily Loss Hit (%.2f%% >= %.2f%%)", dailyLossPct, InpMaxDailyLossPct));
      blockReason = StringFormat("Blocked: Daily equity loss limit %.2f%% reached.", dailyLossPct);
      return false;
   }

   // 4. Minimum Free Margin Level Check (Blocks new entries)
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   double usedMargin  = AccountInfoDouble(ACCOUNT_MARGIN);
   if(usedMargin > 0 && marginLevel < InpMinFreeMarginPct) {
      blockReason = StringFormat("Blocked: Margin Level %.1f%% below minimum %.1f%%.", marginLevel, InpMinFreeMarginPct);
      return false;
   }

   // 5. Total Account Exposure Cap
   double totalAccVol = 0.0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(ExtPos.SelectByIndex(i)) totalAccVol += ExtPos.Volume();
   }
   if(totalAccVol >= InpMaxTotalExposure) {
      blockReason = StringFormat("Blocked: Total exposure %.2f >= max %.2f lots.", totalAccVol, InpMaxTotalExposure);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Validate Data & Indicator Buffers Readiness                      |
//+------------------------------------------------------------------+
bool AreIndicatorsReady(string &notReadyReason) {
   if(Bars(_Symbol, InpSignalTF) < 100 || Bars(_Symbol, InpTrendTF) < 100) {
      notReadyReason = "Waiting: Historical bars loading (< 100 bars).";
      return false;
   }
   if(BarsCalculated(hATR_Sig) < 10 || BarsCalculated(hADX_Sig) < 10 ||
      BarsCalculated(hEMA_F_Sig) < 10 || BarsCalculated(hEMA_S_Sig) < 10 ||
      BarsCalculated(hBB_Sig) < 10 || BarsCalculated(hRSI_Sig) < 10 ||
      BarsCalculated(hADX_HTF) < 10 || BarsCalculated(hEMA_F_HTF) < 10 ||
      BarsCalculated(hEMA_S_HTF) < 10) {
      notReadyReason = "Waiting: Indicator buffers still calculating.";
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Market Regime Classifier (Hysteresis & Volatility Spike Guard)   |
//+------------------------------------------------------------------+
ENUM_ACTIVE_REGIME ClassifyRegime(double atrVal, string &regimeNote) {
   if(InpGridMode == MODE_RANGE_ONLY) return REGIME_RANGE;
   if(InpGridMode == MODE_TREND_ONLY) return REGIME_TREND;

   double adxHTF[2], emaF_HTF[3], emaS_HTF[3];
   MqlRates rates[3];

   if(CopyBuffer(hADX_HTF, 0, 1, 2, adxHTF) < 2 ||
      CopyBuffer(hEMA_F_HTF, 0, 1, 3, emaF_HTF) < 3 ||
      CopyBuffer(hEMA_S_HTF, 0, 1, 3, emaS_HTF) < 3 ||
      CopyRates(_Symbol, InpSignalTF, 1, 2, rates) < 2) {
      regimeNote = "Regime Unknown: Buffer copy incomplete.";
      return REGIME_NONE;
   }

   // Check Volatility Spike on closed signal bar
   double lastBarRange = rates[1].high - rates[1].low;
   if(atrVal > 0 && lastBarRange > atrVal * InpSpikeATRMult) {
      regimeNote = StringFormat("Volatility Spike Detected (Range %.5f > %.2fx ATR). Blocking new entries.", lastBarRange, InpSpikeATRMult);
      return REGIME_NONE;
   }

   double curADX = adxHTF[1];
   double emaSlope = MathAbs(emaF_HTF[2] - emaF_HTF[0]) / 2.0;
   double normSlope = (atrVal > 0) ? (emaSlope / atrVal) : 0.0;
   bool aligned = (emaF_HTF[2] > emaS_HTF[2] && emaF_HTF[2] > emaF_HTF[1]) ||
                  (emaF_HTF[2] < emaS_HTF[2] && emaF_HTF[2] < emaF_HTF[1]);

   // Hysteresis logic to prevent rapid regime flipping
   if(g_CurrentRegime == REGIME_TREND) {
      if(curADX < InpADXTrendExit || !aligned) {
         g_CurrentRegime = REGIME_NONE;
      }
   } else {
      if(curADX >= InpADXTrendEnter && normSlope >= InpMinEMASlopeATR && aligned) {
         g_CurrentRegime = REGIME_TREND;
      } else if(curADX <= InpADXRangeMax && normSlope < InpMinEMASlopeATR) {
         g_CurrentRegime = REGIME_RANGE;
      } else {
         g_CurrentRegime = REGIME_NONE;
      }
   }

   if(g_CurrentRegime == REGIME_NONE) {
      regimeNote = StringFormat("Regime Transitional/Unclear (HTF ADX=%.1f, SlopeATR=%.2f). Blocking new entries.", curADX, normSlope);
   }
   return g_CurrentRegime;
}

//+------------------------------------------------------------------+
//| Check Spread Filter                                              |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(double atrVal, string &reason) {
   ExtSymbol.RefreshRates();
   double spreadPts = (double)ExtSymbol.Spread();
   double spreadPrice = spreadPts * ExtSymbol.Point();

   if(InpMaxSpreadPoints > 0 && spreadPts > InpMaxSpreadPoints) {
      reason = StringFormat("Blocked: Spread %.0f pts > max %.0f pts.", spreadPts, InpMaxSpreadPoints);
      return false;
   }
   if(InpMaxSpreadATR > 0 && atrVal > 0 && spreadPrice > atrVal * InpMaxSpreadATR) {
      reason = StringFormat("Blocked: Spread %.5f > %.2f * ATR.", spreadPrice, InpMaxSpreadATR);
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Calculate & Validate Next Grid Lot Size                           |
//+------------------------------------------------------------------+
double CalculateNextLot(int nextLevelIndex, double baseStepPrice, string &blockReason) {
   double baseLot = InpFixedLot;

   if(InpLotMode == LOT_RISK_PERCENT) {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double riskMoney = equity * (InpRiskPercent / 100.0);
      double tickVal = ExtSymbol.TickValue();
      double tickSize = ExtSymbol.TickSize();
      // Estimate worst-case grid distance across MaxGridLevels
      double totalSpan = baseStepPrice * InpMaxGridLevels;
      if(tickVal > 0 && tickSize > 0 && totalSpan > 0) {
         double lossPerLot = (totalSpan / tickSize) * tickVal;
         baseLot = riskMoney / lossPerLot;
      }
   }

   double rawLot = baseLot;
   if(InpUseLotMultiplier && nextLevelIndex > 0) {
      rawLot = baseLot * MathPow(InpLotMultiplier, nextLevelIndex);
   }

   // Normalize to broker volume constraints
   double minLot  = ExtSymbol.LotsMin();
   double maxLot  = ExtSymbol.LotsMax();
   double stepLot = ExtSymbol.LotsStep();

   double normLot = MathFloor(rawLot / stepLot) * stepLot;
   normLot = MathMax(minLot, MathMin(maxLot, normLot));
   normLot = NormalizeDouble(normLot, 2);

   // Check Basket Volume Cap
   if(g_Basket.totalVolume + normLot > InpMaxBasketVolume + 1e-6) {
      blockReason = StringFormat("Blocked: Projected basket volume %.2f > max %.2f.",
                                 g_Basket.totalVolume + normLot, InpMaxBasketVolume);
      return 0.0;
   }

   // Check Projected Margin Requirement
   double marginReq = 0.0;
   ENUM_ORDER_TYPE oType = (g_Basket.active && g_Basket.direction == POSITION_TYPE_SELL) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (oType == ORDER_TYPE_BUY) ? ExtSymbol.Ask() : ExtSymbol.Bid();

   if(!OrderCalcMargin(oType, _Symbol, normLot, price, marginReq)) {
      blockReason = "Blocked: OrderCalcMargin failed.";
      return 0.0;
   }
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin - marginReq <= 0) {
      blockReason = StringFormat("Blocked: Insufficient free margin (Req=%.2f, Free=%.2f).", marginReq, freeMargin);
      return 0.0;
   }

   // Check Projected Loss vs Hard Basket SL
   if(MathAbs(g_Basket.netFloatingPL) >= InpBasketHardSLMoney * 0.85) {
      blockReason = "Blocked: Basket floating loss too close to Hard SL to add levels.";
      return 0.0;
   }

   return normLot;
}

//+------------------------------------------------------------------+
//| Evaluate Initial Cycle Entry Signal (Closed Bars Only)           |
//+------------------------------------------------------------------+
int GetInitialEntrySignal(ENUM_ACTIVE_REGIME regime, string &signalNote) {
   MqlRates rates[3];
   if(CopyRates(_Symbol, InpSignalTF, 1, 2, rates) < 2) return 0; // rates[1] = last closed bar, rates[0] = bar before

   if(regime == REGIME_RANGE) {
      double bbUpper[2], bbLower[2], rsi[2], adx[1];
      if(CopyBuffer(hBB_Sig, 1, 1, 2, bbUpper) < 2 ||
         CopyBuffer(hBB_Sig, 2, 1, 2, bbLower) < 2 ||
         CopyBuffer(hRSI_Sig, 0, 1, 2, rsi) < 2 ||
         CopyBuffer(hADX_Sig, 0, 1, 1, adx) < 1) return 0;

      if(adx[0] > InpADXRangeMax) {
         signalNote = StringFormat("Range Signal Wait: Signal ADX %.1f > %.1f.", adx[0], InpADXRangeMax);
         return 0;
      }

      // BUY Rejection: Bar touched/pierced lower BB, RSI oversold, closed bullishly back inside
      bool touchedLow = (rates[1].low <= bbLower[1] || rates[0].low <= bbLower[0]);
      bool bullReject = (rates[1].close > rates[1].open && rates[1].close > bbLower[1]);
      if(touchedLow && bullReject && rsi[1] <= InpRSIOversold + 5.0) {
         return 1; // BUY
      }

      // SELL Rejection: Bar touched/pierced upper BB, RSI overbought, closed bearishly back inside
      bool touchedHigh = (rates[1].high >= bbUpper[1] || rates[0].high >= bbUpper[0]);
      bool bearReject  = (rates[1].close < rates[1].open && rates[1].close < bbUpper[1]);
      if(touchedHigh && bearReject && rsi[1] >= InpRSIOverbought - 5.0) {
         return -1; // SELL
      }

      signalNote = "Range Signal Wait: No band touch + rejection confirmation on closed bar.";
      return 0;
   }

   if(regime == REGIME_TREND) {
      double emaF_HTF[2], emaS_HTF[2], emaF_Sig[2], emaS_Sig[2];
      if(CopyBuffer(hEMA_F_HTF, 0, 1, 2, emaF_HTF) < 2 ||
         CopyBuffer(hEMA_S_HTF, 0, 1, 2, emaS_HTF) < 2 ||
         CopyBuffer(hEMA_F_Sig, 0, 1, 2, emaF_Sig) < 2 ||
         CopyBuffer(hEMA_S_Sig, 0, 1, 2, emaS_Sig) < 2) return 0;

      bool htfUp   = (emaF_HTF[1] > emaS_HTF[1] && emaF_HTF[1] > emaF_HTF[0]);
      bool htfDown = (emaF_HTF[1] < emaS_HTF[1] && emaF_HTF[1] < emaF_HTF[0]);

      // Trend BUY: HTF Uptrend + Pullback to Signal Fast EMA + Resumption bullish close
      if(htfUp && rates[1].low <= emaF_Sig[1] && rates[1].close > emaF_Sig[1] && rates[1].close > rates[1].open) {
         return 1;
      }
      // Trend SELL: HTF Downtrend + Pullback to Signal Fast EMA + Resumption bearish close
      if(htfDown && rates[1].high >= emaF_Sig[1] && rates[1].close < emaF_Sig[1] && rates[1].close < rates[1].open) {
         return -1;
      }

      signalNote = "Trend Signal Wait: Waiting for HTF-aligned pullback & resumption candle.";
      return 0;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Check Trend Structure Break (For Open Trend Baskets)             |
//+------------------------------------------------------------------+
bool IsTrendStructureBroken() {
   if(g_Basket.regime != REGIME_TREND || !InpCloseOnTrendBreak) return false;

   double emaF_HTF[1], emaS_HTF[1];
   if(CopyBuffer(hEMA_F_HTF, 0, 1, 1, emaF_HTF) < 1 ||
      CopyBuffer(hEMA_S_HTF, 0, 1, 1, emaS_HTF) < 1) return false;

   if(g_Basket.direction == POSITION_TYPE_BUY && emaF_HTF[0] < emaS_HTF[0]) return true;
   if(g_Basket.direction == POSITION_TYPE_SELL && emaF_HTF[0] > emaS_HTF[0]) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Manage Active Basket Exit Rules                                  |
//+------------------------------------------------------------------+
void ManageBasketExit() {
   if(!g_Basket.active || g_Basket.levelCount == 0) return;

   // 1. Hard Basket Stop Loss
   if(InpBasketHardSLMoney > 0 && g_Basket.netFloatingPL <= -InpBasketHardSLMoney) {
      CloseAllEAOrdersAndPositions(StringFormat("Hard Basket SL Hit (NetPL=%.2f <= -%.2f)",
                                   g_Basket.netFloatingPL, InpBasketHardSLMoney));
      return;
   }

   // 2. Max Cycle Duration
   if(InpMaxCycleHours > 0) {
      int elapsedSec = (int)(TimeCurrent() - g_Basket.openTime);
      if(elapsedSec >= InpMaxCycleHours * 3600) {
         CloseAllEAOrdersAndPositions(StringFormat("Max Cycle Duration Reached (%d hours)", InpMaxCycleHours));
         return;
      }
   }

   // 3. Trend Structure Break Exit
   if(IsTrendStructureBroken()) {
      CloseAllEAOrdersAndPositions("HTF Trend Structure Broken during Trend Grid cycle");
      return;
   }

   // 4. Calculate Net Basket Take Profit Target
   double targetMoney = InpFixedBasketTP;
   if(InpTargetMode == TARGET_ATR_SCALED) {
      double tickVal  = ExtSymbol.TickValue();
      double tickSize = ExtSymbol.TickSize();
      if(tickVal > 0 && tickSize > 0 && g_Basket.frozenATR > 0) {
         double baseLot = MathMax(ExtSymbol.LotsMin(), InpFixedLot);
         targetMoney = ((g_Basket.frozenATR * InpATRBasketTPMult) / tickSize) * tickVal * baseLot;
         targetMoney = MathMax(1.0, targetMoney);
      }
   }

   // Track peak net profit for trailing
   if(g_Basket.netFloatingPL > g_Basket.peakNetProfit) {
      g_Basket.peakNetProfit = g_Basket.netFloatingPL;
      SaveState();
   }

   // 5. Trailing Basket Profit
   if(InpUseBasketTrail && targetMoney > 0) {
      double trailActivate = targetMoney * InpTrailStartPct;
      if(g_Basket.peakNetProfit >= trailActivate) {
         double trailFloor = g_Basket.peakNetProfit * (1.0 - InpTrailDropPct);
         if(g_Basket.netFloatingPL <= trailFloor && g_Basket.netFloatingPL > 0) {
            CloseAllEAOrdersAndPositions(StringFormat("Basket Profit Trail Triggered (NetPL=%.2f, Peak=%.2f)",
                                         g_Basket.netFloatingPL, g_Basket.peakNetProfit));
            return;
         }
      }
   }

   // 6. Standard Net Basket Take Profit
   if(g_Basket.netFloatingPL >= targetMoney) {
      CloseAllEAOrdersAndPositions(StringFormat("Basket Net TP Reached (NetPL=%.2f >= Target=%.2f)",
                                   g_Basket.netFloatingPL, targetMoney));
      return;
   }
}

//+------------------------------------------------------------------+
//| Evaluate & Execute Grid Level Additions                          |
//+------------------------------------------------------------------+
void ManageGridAddition(double curATR, ENUM_ACTIVE_REGIME currentMarketRegime) {
   if(!g_Basket.active || g_Basket.levelCount == 0) return;

   // Check Max Grid Levels
   if(g_Basket.levelCount >= InpMaxGridLevels) {
      LogStatus(StringFormat("Grid Cap: Max levels (%d) reached.", InpMaxGridLevels));
      return;
   }

   // Check Cooldown
   if((TimeCurrent() - g_Basket.lastAddTime) < InpCooldownSeconds) {
      return;
   }

   // Block additions during unclear market or volatility spike
   if(InpGridMode == MODE_AUTO && currentMarketRegime == REGIME_NONE) {
      LogStatus("Grid Add Blocked: Market regime unclear or volatility spike active.");
      return;
   }

   // Validate regime still valid for frozen strategy
   if(g_Basket.regime == REGIME_RANGE) {
      double adx[1];
      if(CopyBuffer(hADX_Sig, 0, 1, 1, adx) > 0 && adx[0] > InpADXRangeMax + 5.0) {
         LogStatus(StringFormat("Grid Add Blocked: Range invalidated (ADX=%.1f).", adx[0]));
         return;
      }
   } else if(g_Basket.regime == REGIME_TREND) {
      if(IsTrendStructureBroken()) {
         LogStatus("Grid Add Blocked: Trend structure broken.");
         return;
      }
   }

   // Calculate required geometric distance from last fill price:
   // Level 1 -> Level 2 (levelCount == 1): BaseStep * Multiplier^0 = BaseStep
   // Level 2 -> Level 3 (levelCount == 2): BaseStep * Multiplier^1
   // Level k -> Level k+1 (levelCount == k): BaseStep * Multiplier^(k - 1)
   int exponent = MathMax(0, g_Basket.levelCount - 1);
   double reqStep = g_Basket.frozenBaseStep * MathPow(InpGridMultiplier, exponent);

   ExtSymbol.RefreshRates();
   double curPrice = (g_Basket.direction == POSITION_TYPE_BUY) ? ExtSymbol.Ask() : ExtSymbol.Bid();
   double adverseMove = 0.0;

   if(g_Basket.direction == POSITION_TYPE_BUY) {
      adverseMove = g_Basket.lastFillPrice - curPrice;
   } else {
      adverseMove = curPrice - g_Basket.lastFillPrice;
   }

   if(adverseMove < reqStep) {
      return; // Price has not reached next grid level yet
   }

   // If Trend Grid, require pullback/resumption candle on closed bar before adding
   if(g_Basket.regime == REGIME_TREND) {
      MqlRates rates[2];
      if(CopyRates(_Symbol, InpSignalTF, 1, 1, rates) < 1) return;
      bool resumed = (g_Basket.direction == POSITION_TYPE_BUY) ? (rates[0].close > rates[0].open)
                                                               : (rates[0].close < rates[0].open);
      if(!resumed) {
         LogStatus("Trend Grid Add Wait: Distance met, waiting for closed resumption candle.");
         return;
      }
   }

   // Spread & Lot/Margin Validation (Opens max 1 level even if price gapped multiple steps)
   string blockReason = "";
   if(!IsSpreadAcceptable(curATR, blockReason)) {
      LogStatus(blockReason);
      return;
   }

   double nextLot = CalculateNextLot(g_Basket.levelCount, g_Basket.frozenBaseStep, blockReason);
   if(nextLot <= 0.0) {
      LogStatus(blockReason);
      return;
   }

   // Execute single grid addition
   g_OrderInFlight = true;
   g_OrderSentTime = TimeCurrent();
   string comment = StringFormat("%s L%d", InpTradeComment, g_Basket.levelCount + 1);
   bool sent = false;

   if(g_Basket.direction == POSITION_TYPE_BUY) {
      sent = ExtTrade.Buy(nextLot, _Symbol, ExtSymbol.Ask(), 0, 0, comment);
   } else {
      sent = ExtTrade.Sell(nextLot, _Symbol, ExtSymbol.Bid(), 0, 0, comment);
   }

   if(!sent) {
      g_OrderInFlight = false;
      LogStatus(StringFormat("Grid Add Rejected by Server: Retcode=%d (%s)",
                ExtTrade.ResultRetcode(), ExtTrade.ResultRetcodeDescription()), true);
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   // Release stale in-flight lock after 10 seconds safety timeout
   if(g_OrderInFlight && (TimeCurrent() - g_OrderSentTime) > 10) {
      g_OrderInFlight = false;
   }

   // Handle pending close retries if partial/failed close occurred
   if(g_EmergencyLocked && g_Basket.levelCount > 0) {
      if(TimeCurrent() - g_LastRetryTime >= 3 && g_CloseRetryCount < 10) {
         g_LastRetryTime = TimeCurrent();
         g_CloseRetryCount++;
         CloseAllEAOrdersAndPositions("Emergency Close Retry #" + IntegerToString(g_CloseRetryCount));
      }
      return;
   }

   // Reconcile open positions & floating P/L on every tick
   ReconcilePositions();

   // 1. Always manage active basket exits first (tick-level precision)
   if(g_Basket.active) {
      ManageBasketExit();
      if(!g_Basket.active) return; // Basket just closed
   }

   // 2. Check global risk limits (may close basket or block entries)
   string riskBlock = "";
   if(!CheckRiskLimits(riskBlock)) {
      LogStatus(riskBlock);
      return;
   }

   // 3. Check symbol/magic isolation
   string isoBlock = "";
   if(!CheckSymbolOwnership(isoBlock)) {
      LogStatus(isoBlock);
      return;
   }

   // 4. Ensure indicator buffers & history are ready
   string readyReason = "";
   if(!AreIndicatorsReady(readyReason)) {
      LogStatus(readyReason);
      return;
   }

   // Fetch current closed-bar ATR
   double atrBuf[1];
   if(CopyBuffer(hATR_Sig, 0, 1, 1, atrBuf) < 1 || atrBuf[0] <= 0) {
      LogStatus("Waiting: Invalid ATR value on closed bar.");
      return;
   }
   double curATR = atrBuf[0];

   // Classify current market regime
   string regimeNote = "";
   ENUM_ACTIVE_REGIME marketRegime = ClassifyRegime(curATR, regimeNote);

   // Prevent duplicate orders while request is executing
   if(g_OrderInFlight) return;

   // 5. If Basket is Active -> Evaluate Grid Addition
   if(g_Basket.active) {
      ManageGridAddition(curATR, marketRegime);
      return;
   }

   // 6. New Cycle Entry Evaluation (Strictly on New Closed Bar)
   datetime curBarTime = iTime(_Symbol, InpSignalTF, 0);
   if(curBarTime == g_LastBarTime) return;
   g_LastBarTime = curBarTime;

   if(marketRegime == REGIME_NONE) {
      LogStatus(regimeNote);
      return;
   }

   string spreadBlock = "";
   if(!IsSpreadAcceptable(curATR, spreadBlock)) {
      LogStatus(spreadBlock);
      return;
   }

   string sigNote = "";
   int signal = GetInitialEntrySignal(marketRegime, sigNote);
   if(signal == 0) {
      LogStatus(sigNote);
      return;
   }

   // Freeze cycle parameters before sending initial order
   double frozenStep = curATR * InpATRStepMultiplier;
   double minStep = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * ExtSymbol.Point();
   if(frozenStep < minStep) frozenStep = minStep + ExtSymbol.Point();

   string lotBlock = "";
   double initLot = CalculateNextLot(0, frozenStep, lotBlock);
   if(initLot <= 0.0) {
      LogStatus(lotBlock);
      return;
   }

   // Pre-freeze cycle metadata so OnTradeTransaction locks it on fill
   g_Basket.direction      = (signal > 0) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
   g_Basket.regime         = marketRegime;
   g_Basket.frozenBaseStep = frozenStep;
   g_Basket.frozenATR      = curATR;
   g_Basket.peakNetProfit  = 0.0;

   g_OrderInFlight = true;
   g_OrderSentTime = TimeCurrent();
   string comment  = StringFormat("%s L1 (%s)", InpTradeComment, (marketRegime == REGIME_RANGE ? "RNG" : "TRD"));
   bool sent = false;

   ExtSymbol.RefreshRates();
   if(signal > 0) {
      sent = ExtTrade.Buy(initLot, _Symbol, ExtSymbol.Ask(), 0, 0, comment);
   } else {
      sent = ExtTrade.Sell(initLot, _Symbol, ExtSymbol.Bid(), 0, 0, comment);
   }

   if(!sent) {
      g_OrderInFlight = false;
      ZeroMemory(g_Basket);
      LogStatus(StringFormat("Initial Entry Rejected by Server: Retcode=%d (%s)",
                ExtTrade.ResultRetcode(), ExtTrade.ResultRetcodeDescription()), true);
   }
}

//+------------------------------------------------------------------+
//| OnTradeTransaction: Reconcile Fills, Partial Fills & Closures    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      if(trans.symbol != _Symbol) return;
      if(HistoryDealSelect(trans.deal)) {
         ulong dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         if(dealMagic == InpMagicNumber) {
            g_OrderInFlight = false;
            ReconcilePositions();
            SaveState();

            long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
            double price   = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
            double vol     = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

            if(entryType == DEAL_ENTRY_IN) {
               LogStatus(StringFormat("FILL CONFIRMED: Level %d | Vol=%.2f @ %.5f | FrozenStep=%.5f",
                         g_Basket.levelCount, vol, price, g_Basket.frozenBaseStep), true);
            } else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY) {
               LogStatus(StringFormat("EXIT FILL CONFIRMED: Vol=%.2f @ %.5f | Remaining Levels=%d",
                         vol, price, g_Basket.levelCount), true);
            }
         }
      }
   } else if(trans.type == TRADE_TRANSACTION_REQUEST) {
      if(request.magic == InpMagicNumber && result.retcode != TRADE_RETCODE_DONE &&
         result.retcode != TRADE_RETCODE_PLACED && result.retcode != TRADE_RETCODE_DONE_PARTIAL) {
         g_OrderInFlight = false;
      }
   }
}
//+------------------------------------------------------------------+
