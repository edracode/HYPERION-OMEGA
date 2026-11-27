//+------------------------------------------------------------------+
//|                                                 OurOBoros_Vx.mq5 |
//|                     OurOBoros Quantitative Engineering Division  |
//|         Ultimate Bidirectional Anti-Martingale & Smart Hedge EA  |
//+------------------------------------------------------------------+
#property copyright   "OurOBoros Quantitative Engineering"
#property link        "https://www.mql5.com"
#property version     "2.02"
#property description "OurOBoros Vx V2.02 - Anti-Stacking Bidirectional Anti-Martingale, Smart Hedge, Adaptive Pyramiding & Basket Trailing EA"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\DealInfo.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_EA_STATE
  {
   STATE_INITIALIZING = 0,
   STATE_BASKET_INITIALIZATION,
   STATE_OPENING_INITIAL_HEDGE,
   STATE_INITIAL_HEDGE_CONFIRMED,
   STATE_MARKET_DIRECTION_DETECTION,
   STATE_BULLISH_PYRAMIDING,
   STATE_BEARISH_PYRAMIDING,
   STATE_SIDEWAYS_ADAPTATION,
   STATE_REVERSAL_DETECTION,
   STATE_DIRECTION_TRANSITION,
   STATE_POSITION_OPTIMIZATION,
   STATE_BASKET_PROFIT_TARGET_REACHED,
   STATE_PROFIT_EXTENSION,
   STATE_BASKET_PROFIT_TRAILING,
   STATE_STAGNATION_DETECTED,
   STATE_BREAK_EVEN_RECOVERY,
   STATE_BASKET_CLOSING,
   STATE_TRANSACTION_RECONCILIATION,
   STATE_BASKET_RESET,
   STATE_AUTOMATIC_RE_ENTRY,
   STATE_MARGIN_INSUFFICIENT,
   STATE_MARKET_CLOSED,
   STATE_CONNECTION_RECOVERY
  };

enum ENUM_MARKET_REGIME
  {
   REGIME_TRENDING_STRONG = 0,
   REGIME_TRENDING_MODERATE,
   REGIME_SIDEWAYS_RANGING,
   REGIME_VOLATILE_BREAKOUT,
   REGIME_CHOPPY_WHIPSAW
  };

enum ENUM_DIR_SIGNAL
  {
   DIR_BEARISH = -1,
   DIR_NEUTRAL = 0,
   DIR_BULLISH = 1
  };

//+------------------------------------------------------------------+
//| Input Parameters (Grouped by Functional Module)                  |
//+------------------------------------------------------------------+
input group "=== 1. GENERAL SETTINGS ==="
input string          InpEAName                        = "OurOBoros Vx";   // EA Name
input ulong           InpMagicNumber                   = 20260909;         // Magic Number (Unique Identifier)
input ENUM_TIMEFRAMES InpTradingTimeframe              = PERIOD_M1;        // Primary Analysis Timeframe
input bool            InpEnableBuy                     = true;             // Enable BUY Engine
input bool            InpEnableSell                    = true;             // Enable SELL Engine
input bool            InpEnableInitialDualEntry        = true;             // Enable Simultaneous Dual Entry (BUY + SELL)
input bool            InpEnableAutomaticRestart        = true;             // Enable Automatic Basket Restart
input int             InpSlippagePoints                = 50;               // Execution Slippage Deviation (Points)

input group "=== 2. BIDIRECTIONAL ANTI-MARTINGALE SETTINGS ==="
input double          InpInitialBuyLot                 = 0.01;             // Initial BUY Lot
input double          InpInitialSellLot                = 0.01;             // Initial SELL Lot
input double          InpBuyLotIncrement               = 0.01;             // BUY Linear Lot Increment
input double          InpSellLotIncrement              = 0.01;             // SELL Linear Lot Increment
input double          InpMaximumBuyLot                 = 0.02;             // Maximum Individual BUY Lot
input double          InpMaximumSellLot                = 0.02;             // Maximum Individual SELL Lot
input bool            InpEnableIndependentLotCounters  = true;             // Independent BUY/SELL Counters
input bool            InpResetLotOnReversal            = false;            // Reset Lot on Reversal (Must be false)
input bool            InpResetLotOnPartialClose        = false;            // Reset Lot on Partial Close (Must be false)
input bool            InpResetLotAfterBasketClose      = true;             // Reset Lot Counters After Full Basket Close

input group "=== 3. UNLIMITED ADAPTIVE LAYERING SETTINGS ==="
input bool            InpEnableUnlimitedLayering       = true;             // Unlimited Layering (No Hard Cap)
input bool            InpEnableTrendPyramiding         = true;             // Enable Trend-Following Pyramiding
input bool            InpEnableBullishPyramiding       = true;             // Enable Bullish Pyramiding
input bool            InpEnableBearishPyramiding       = true;             // Enable Bearish Pyramiding
input bool            InpEnableAdaptiveGrid            = true;             // Enable Adaptive ATR/Regime Grid Distance
input bool            InpEnableReversalAdaptation      = true;             // Enable Intelligent Reversal Adaptation
input int             InpATRPeriod                     = 14;               // ATR Period for Adaptive Grid
input double          InpGridATRMultiplier             = 0.50;             // Grid ATR Multiplier (Optimizable)
input double          InpMinimumGridDistancePoints     = 200.0;            // Minimum Grid Distance in Points (Anti-Stacking)
input int             InpMinOrderCooldownSec           = 3;                // Min Seconds Between Same-Side Orders
input double          InpDirectionalConfirmThreshold   = 0.20;             // Directional Confirmation Threshold (0.05 - 0.80)
input double          InpReversalConfirmThreshold      = 0.26;             // Reversal Confirmation Threshold (0.10 - 0.90)

input group "=== 4. BASKET PROFIT & TRAILING MAXIMIZATION ==="
input double          InpMinimumBasketProfitPercent    = 2.00;             // Minimum Normal Basket Profit (%)
input bool            InpEnableDynamicProfitExtension  = true;             // Enable Dynamic Profit Extension (>2%)
input bool            InpEnableBasketTrailing          = true;             // Enable Dynamic Basket Profit Trailing
input double          InpTrailLockRatio                = 0.80;             // Profit Lock Ratio above Target (e.g., 0.80 = 80%)
input double          InpTrailActivationBufferPercent  = 0.35;             // Extra % Above Target to Activate Trailing
input bool            InpEnableMaximumProfitCap        = false;            // Enable Maximum Profit Cap
input double          InpMaximumProfitCapPercent       = 25.0;             // Maximum Profit Cap (%) if Enabled
input bool            InpEnableSelectivePosOpt         = true;             // Enable Selective Position Optimization

input group "=== 5. STAGNANT BASKET RECOVERY SETTINGS ==="
input bool            InpEnableStagnationRecovery      = true;             // Enable Stagnant Basket BEP Recovery
input int             InpStagnationMinAgeMinutes       = 60;               // Min Basket Age for Stagnation Check (Min)
input int             InpStagnationMinPositions        = 20;               // Min Open Positions for Stagnation Check
input int             InpNoMeaningfulImproveMinutes    = 30;               // Minutes Without Meaningful Profit Gain
input int             InpBreakEvenDwellMinutes         = 10;               // Cumulative Minutes in Break-Even Zone
input double          InpBreakEvenZonePercent          = 0.10;             // Break-Even Proximity Zone (% of Start Balance)
input double          InpMaximumRecoveryLossPercent    = 0.05;             // Max Tolerated Recovery Loss (% of Start Balance)
input bool            InpEnableAutoRecoveryRestart     = true;             // Auto Start New Cycle After Recovery Close

input group "=== 6. EXECUTION, RISK & PERSISTENCE SETTINGS ==="
input bool            InpEnableMaximumSpreadFilter     = false;            // Maximum Spread Filter (Default: Disabled)
input double          InpMaxSpreadPointsIfEnabled      = 500.0;            // Max Spread Points (Only if Filter Enabled)
input bool            InpEnableConventionalStopLoss    = false;            // Conventional Individual SL (Default: Disabled)
input bool            InpEnableMarginValidation        = true;             // Validate Free Margin Before New Layer
input double          InpMinFreeMarginLevelPercent     = 120.0;            // Minimum Margin Level (%) Safety Guard
input bool            InpEnableDuplicatePrevention     = true;             // Enable Duplicate Order & Partial Fill Guard
input bool            InpEnableTxReconciliation        = true;             // Enable Transaction Reconciliation
input bool            InpEnablePersistentBasketState   = true;             // Enable Crash/Restart Persistent State
input bool            InpEnableCloseByOptimization     = true;             // Enable CloseBy Hedged Pair Optimization
input bool            InpEnableConnectionRecovery      = true;             // Enable Broker Connection Recovery

input group "=== 7. DASHBOARD & VISUAL SETTINGS ==="
input bool            InpShowDashboard                 = true;             // Show Professional Chart Dashboard
input int             InpDashboardX                    = 14;               // Dashboard X Offset
input int             InpDashboardY                    = 22;               // Dashboard Y Offset
input int             InpDashboardUpdateMs             = 250;              // Dashboard Refresh Interval (ms)

//+------------------------------------------------------------------+
//| Data Structures                                                  |
//+------------------------------------------------------------------+
struct MarketAnalysisResult
  {
   double            bullishScore;
   double            bearishScore;
   double            netScore;
   double            trendConfidence;
   double            reversalProbability;
   double            momentumStrength;
   double            entryOpportunityScore;
   double            atrValue;
   double            atrPoints;
   double            dynamicGridPoints;
   double            tickVelocity;
   double            tickAcceleration;
   double            tickImbalance;
   double            zScore;
   double            slopeNormalized;
   ENUM_MARKET_REGIME regime;
   ENUM_DIR_SIGNAL   direction;
   bool              isReversalConfirmed;
   bool              isPullbackOnly;
  };

struct BasketMetrics
  {
   int               totalOpenPositions;
   int               buyPositions;
   int               sellPositions;
   double            buyVolume;
   double            sellVolume;
   double            netExposure;
   double            grossExposure;
   double            buyWeightedAvgPrice;
   double            sellWeightedAvgPrice;
   double            highestBuyPrice;
   double            lowestSellPrice;
   double            nearestBuyDistance;
   double            nearestSellDistance;
   double            buyFloatingPnL;
   double            sellFloatingPnL;
   double            floatingGrossPnL;
   double            floatingCommission;
   double            floatingSwap;
   double            floatingNetPnL;
   double            estimatedExitCosts;
   double            basketNetPnL;
   double            basketNetPercent;
   double            estimatedBreakEvenPrice;
   double            breakEvenDistancePoints;
   double            usedMargin;
   double            freeMargin;
   double            marginLevel;
  };

struct BasketPersistentState
  {
   long              basketId;
   double            basketStartBalance;
   datetime          basketStartTime;
   double            initialBuyPrice;
   double            initialSellPrice;
   double            initialReferencePrice;
   int               buyLayerCounter;
   int               sellLayerCounter;
   double            lastBuyEntryPrice;
   double            lastSellEntryPrice;
   double            lastBuyLot;
   double            lastSellLot;
   int               activeTrendDirection;
   double            activeTrendStartPrice;
   double            activeDirectionalAnchor;
   double            lastConfirmedSwingHigh;
   double            lastConfirmedSwingLow;
   double            realizedBasketPnL;
   double            peakBasketProfitDollars;
   double            peakBasketProfitPercent;
   double            protectedProfitFloorPercent;
   datetime          lastProfitImprovementTime;
   double            bestObservedProfitPercent;
   int               reversalCount;
   int               totalHistoricalEntries;
   int               breakEvenDwellSeconds;
   datetime          lastTickTimestamp;
   bool              stagnationDetected;
   bool              recoveryModeActive;
   bool              basketClosingActive;
   bool              profitTrailingActive;
   bool              initialHedgeCompleted;
  };

//+------------------------------------------------------------------+
//| Global Objects & Runtime State                                   |
//+------------------------------------------------------------------+
CTrade               g_trade;
ENUM_EA_STATE        g_eaState                = STATE_INITIALIZING;
ENUM_ORDER_TYPE_FILLING g_fillingMode         = ORDER_FILLING_FOK;
BasketPersistentState g_state;
MarketAnalysisResult g_market;
BasketMetrics        g_metrics;

//--- Interactive Dashboard Controls State
bool                 g_autoTradingEnabled     = true;
bool                 g_pauseNewEntries        = false;
bool                 g_resetWhenFlatRequested = false;
bool                 g_manualReEntryRequested = false;
bool                 g_panelVisible           = true;

//--- Historical & Telemetry Statistics
int                  g_totalCompletedBaskets  = 0;
int                  g_winningBaskets         = 0;
int                  g_completedRecoveryBaskets = 0;
int                  g_attemptedRecoveryBaskets = 0;
double               g_totalRealizedAllTime   = 0.0;
double               g_peakAccountEquity      = 0.0;
double               g_maxObservedDrawdownPct = 0.0;

//--- Anti-Stacking Order Cooldown Timestamps
datetime             g_lastBuyOrderTime       = 0;
datetime             g_lastSellOrderTime      = 0;

//--- Cached Indicator Handles
int                  g_hATR                   = INVALID_HANDLE;
int                  g_hEMAFast               = INVALID_HANDLE;
int                  g_hEMAMid                = INVALID_HANDLE;
int                  g_hEMASlow               = INVALID_HANDLE;
int                  g_hHMAHalf               = INVALID_HANDLE;
int                  g_hHMAFull               = INVALID_HANDLE;
int                  g_hRSI                   = INVALID_HANDLE;
int                  g_hMACD                  = INVALID_HANDLE;
int                  g_hADX                   = INVALID_HANDLE;
int                  g_hBands                 = INVALID_HANDLE;
int                  g_hCCI                   = INVALID_HANDLE;
int                  g_hStoch                 = INVALID_HANDLE;
int                  g_hSAR                   = INVALID_HANDLE;

//--- Tick Microstructure Ring Buffer
#define TICK_BUF_SIZE 64
double               g_tickMidBuf[TICK_BUF_SIZE];
ulong                g_tickTimeMsBuf[TICK_BUF_SIZE];
int                  g_tickHead               = 0;
int                  g_tickCount              = 0;
double               g_prevTickVelocity       = 0.0;

//--- Duplicate & Partial-Fill Order Tracking
ulong                g_countedOrderTickets[];
ulong                g_lastDashboardUpdateMs  = 0;
string               g_gvPrefix               = "";
string               g_stateFileName          = "";

//--- UI Constants
#define UI_PREFIX     "OBVX_"
#define BTN_AUTO      "OBVX_BTN_AUTO"
#define BTN_PAUSE     "OBVX_BTN_PAUSE"
#define BTN_RESUME    "OBVX_BTN_RESUME"
#define BTN_CLOSEALL  "OBVX_BTN_CLOSEALL"
#define BTN_RESET     "OBVX_BTN_RESET"
#define BTN_REENTRY   "OBVX_BTN_REENTRY"
#define BTN_RESET_PNL "OBVX_BTN_RESET_PNL"
#define BTN_TOGGLE    "OBVX_BTN_TOGGLE"

//+------------------------------------------------------------------+
//| Helper: Check if Order Ticket Already Counted as a Logical Layer |
//+------------------------------------------------------------------+
bool IsOrderTicketCounted(ulong orderTicket)
  {
   if(orderTicket == 0)
      return(false);
   int sz = ArraySize(g_countedOrderTickets);
   for(int i = 0; i < sz; i++)
     {
      if(g_countedOrderTickets[i] == orderTicket)
         return(true);
     }
   return(false);
  }

void MarkOrderTicketCounted(ulong orderTicket)
  {
   if(orderTicket == 0 || IsOrderTicketCounted(orderTicket))
      return;
   int sz = ArraySize(g_countedOrderTickets);
   if(sz > 2000)
     {
      for(int i = 0; i < sz - 1; i++)
         g_countedOrderTickets[i] = g_countedOrderTickets[i + 1];
      g_countedOrderTickets[sz - 1] = orderTicket;
     }
   else
     {
      ArrayResize(g_countedOrderTickets, sz + 1);
      g_countedOrderTickets[sz] = orderTicket;
     }
  }

//+------------------------------------------------------------------+
//| Helper: Normalize & Validate Lot Size                            |
//+------------------------------------------------------------------+
double NormalizeLot(double rawLot)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(stepLot <= 0.0)
      stepLot = 0.01;
   if(minLot <= 0.0)
      minLot = 0.01;
   if(maxLot <= 0.0)
      maxLot = 100.0;

   double clamped = MathMax(minLot, MathMin(maxLot, rawLot));
   double steps   = MathFloor((clamped + 1e-9) / stepLot);
   double normLot = steps * stepLot;
   normLot = MathMax(minLot, MathMin(maxLot, normLot));

   int lotDigits = 2;
   if(stepLot >= 1.0)
      lotDigits = 0;
   else if(stepLot >= 0.1)
      lotDigits = 1;
   else if(stepLot >= 0.01)
      lotDigits = 2;
   else
      lotDigits = 3;

   return(NormalizeDouble(normLot, lotDigits));
  }

//+------------------------------------------------------------------+
//| Helper: Calculate Next Independent BUY and SELL Lot              |
//+------------------------------------------------------------------+
double GetNextBuyLot()
  {
   int buyStage = InpEnableIndependentLotCounters ? g_state.buyLayerCounter : (g_state.buyLayerCounter + g_state.sellLayerCounter);
   double raw = InpInitialBuyLot + (InpBuyLotIncrement * (double)buyStage);
   double capped = MathMin(raw, InpMaximumBuyLot);
   return(NormalizeLot(capped));
  }

double GetNextSellLot()
  {
   int sellStage = InpEnableIndependentLotCounters ? g_state.sellLayerCounter : (g_state.buyLayerCounter + g_state.sellLayerCounter);
   double raw = InpInitialSellLot + (InpSellLotIncrement * (double)sellStage);
   double capped = MathMin(raw, InpMaximumSellLot);
   return(NormalizeLot(capped));
  }

//+------------------------------------------------------------------+
//| Helper: Detect Optimal Broker Filling Mode                       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFillingMode()
  {
   long fillingFlags = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fillingFlags & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return(ORDER_FILLING_FOK);
   if((fillingFlags & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return(ORDER_FILLING_IOC);
   return(ORDER_FILLING_RETURN);
  }

//+------------------------------------------------------------------+
//| Helper: Validate Broker & Account Compatibility                  |
//+------------------------------------------------------------------+
bool ValidateEnvironmentCompatibility(string &errorMsg)
  {
   ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      errorMsg = "UNSUPPORTED ACCOUNT TYPE: MT5 Netting account detected. OurOBoros Vx requires an MT5 Hedging account.";
      return(false);
     }

   double minVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(minVol > InpInitialBuyLot + 1e-8 || minVol > InpInitialSellLot + 1e-8)
     {
      errorMsg = StringFormat("VOLUME INCOMPATIBILITY: Broker SYMBOL_VOLUME_MIN (%.2f) exceeds initial lot (%.2f).", minVol, InpInitialBuyLot);
      return(false);
     }
   if(maxVol < InpMaximumBuyLot - 1e-8 || maxVol < InpMaximumSellLot - 1e-8)
     {
      errorMsg = StringFormat("VOLUME INCOMPATIBILITY: Broker SYMBOL_VOLUME_MAX (%.2f) is below configured max lot (%.2f).", maxVol, InpMaximumBuyLot);
      return(false);
     }

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tickSize <= 0.0 || point <= 0.0)
     {
      errorMsg = "SYMBOL METADATA ERROR: Invalid tick size or point value.";
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Helper: Check Market & Terminal Trade Permissions                |
//+------------------------------------------------------------------+
bool IsTradingAllowedNow()
  {
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return(false);
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return(false);
   if(InpEnableConnectionRecovery && !TerminalInfoInteger(TERMINAL_CONNECTED))
      return(false);

   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(tradeMode != SYMBOL_TRADE_MODE_FULL)
      return(false);

   return(true);
  }

//+------------------------------------------------------------------+
//| Helper: Extract Basket ID from Position/Order Comment            |
//+------------------------------------------------------------------+
long ParseBasketIdFromComment(string comment)
  {
   int idx = StringFind(comment, "OBX#");
   if(idx < 0)
      return(0);
   string sub = StringSubstr(comment, idx + 4);
   int sep = StringFind(sub, "|");
   if(sep > 0)
      sub = StringSubstr(sub, 0, sep);
   return(StringToInteger(sub));
  }

//+------------------------------------------------------------------+
//| Persistent State: Save & Load (GlobalVariables + File Backup)    |
//+------------------------------------------------------------------+
void SavePersistentState()
  {
   if(!InpEnablePersistentBasketState)
      return;

   GlobalVariableSet(g_gvPrefix + "BASKET_ID",      (double)g_state.basketId);
   GlobalVariableSet(g_gvPrefix + "START_BAL",      g_state.basketStartBalance);
   GlobalVariableSet(g_gvPrefix + "START_TIME",     (double)g_state.basketStartTime);
   GlobalVariableSet(g_gvPrefix + "INIT_BUY_PX",    g_state.initialBuyPrice);
   GlobalVariableSet(g_gvPrefix + "INIT_SELL_PX",   g_state.initialSellPrice);
   GlobalVariableSet(g_gvPrefix + "INIT_REF_PX",    g_state.initialReferencePrice);
   GlobalVariableSet(g_gvPrefix + "BUY_CNT",        (double)g_state.buyLayerCounter);
   GlobalVariableSet(g_gvPrefix + "SELL_CNT",       (double)g_state.sellLayerCounter);
   GlobalVariableSet(g_gvPrefix + "LAST_BUY_PX",    g_state.lastBuyEntryPrice);
   GlobalVariableSet(g_gvPrefix + "LAST_SELL_PX",   g_state.lastSellEntryPrice);
   GlobalVariableSet(g_gvPrefix + "LAST_BUY_LOT",   g_state.lastBuyLot);
   GlobalVariableSet(g_gvPrefix + "LAST_SELL_LOT",  g_state.lastSellLot);
   GlobalVariableSet(g_gvPrefix + "ACTIVE_DIR",     (double)g_state.activeTrendDirection);
   GlobalVariableSet(g_gvPrefix + "DIR_START_PX",   g_state.activeTrendStartPrice);
   GlobalVariableSet(g_gvPrefix + "DIR_ANCHOR",     g_state.activeDirectionalAnchor);
   GlobalVariableSet(g_gvPrefix + "SWING_HIGH",     g_state.lastConfirmedSwingHigh);
   GlobalVariableSet(g_gvPrefix + "SWING_LOW",      g_state.lastConfirmedSwingLow);
   GlobalVariableSet(g_gvPrefix + "REALIZED_PNL",   g_state.realizedBasketPnL);
   GlobalVariableSet(g_gvPrefix + "PEAK_PNL_USD",   g_state.peakBasketProfitDollars);
   GlobalVariableSet(g_gvPrefix + "PEAK_PNL_PCT",   g_state.peakBasketProfitPercent);
   GlobalVariableSet(g_gvPrefix + "FLOOR_PCT",      g_state.protectedProfitFloorPercent);
   GlobalVariableSet(g_gvPrefix + "LAST_IMP_TIME",  (double)g_state.lastProfitImprovementTime);
   GlobalVariableSet(g_gvPrefix + "BEST_PNL_PCT",   g_state.bestObservedProfitPercent);
   GlobalVariableSet(g_gvPrefix + "REV_CNT",        (double)g_state.reversalCount);
   GlobalVariableSet(g_gvPrefix + "HIST_ENTRIES",   (double)g_state.totalHistoricalEntries);
   GlobalVariableSet(g_gvPrefix + "BEP_DWELL_SEC",  (double)g_state.breakEvenDwellSeconds);
   GlobalVariableSet(g_gvPrefix + "STAG_DET",       g_state.stagnationDetected ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "REC_ACTIVE",     g_state.recoveryModeActive ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "CLOSING",        g_state.basketClosingActive ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "TRAIL_ACTIVE",   g_state.profitTrailingActive ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "INIT_DONE",      g_state.initialHedgeCompleted ? 1.0 : 0.0);
   GlobalVariableSet(g_gvPrefix + "TOT_BASKETS",    (double)g_totalCompletedBaskets);
   GlobalVariableSet(g_gvPrefix + "WIN_BASKETS",    (double)g_winningBaskets);
   GlobalVariableSet(g_gvPrefix + "REC_BASKETS",    (double)g_completedRecoveryBaskets);
   GlobalVariableSet(g_gvPrefix + "ATT_REC_BSK",    (double)g_attemptedRecoveryBaskets);
   GlobalVariableSet(g_gvPrefix + "TOT_REALIZED",   g_totalRealizedAllTime);

   int handle = FileOpen(g_stateFileName, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle != INVALID_HANDLE)
     {
      FileWriteStruct(handle, g_state);
      FileWriteInteger(handle, g_totalCompletedBaskets);
      FileWriteInteger(handle, g_winningBaskets);
      FileWriteInteger(handle, g_completedRecoveryBaskets);
      FileWriteInteger(handle, g_attemptedRecoveryBaskets);
      FileWriteDouble(handle, g_totalRealizedAllTime);
      FileClose(handle);
     }
  }

bool LoadPersistentState()
  {
   if(!InpEnablePersistentBasketState)
      return(false);

   if(GlobalVariableCheck(g_gvPrefix + "BASKET_ID"))
     {
      g_state.basketId                  = (long)GlobalVariableGet(g_gvPrefix + "BASKET_ID");
      g_state.basketStartBalance        = GlobalVariableGet(g_gvPrefix + "START_BAL");
      g_state.basketStartTime           = (datetime)GlobalVariableGet(g_gvPrefix + "START_TIME");
      g_state.initialBuyPrice           = GlobalVariableGet(g_gvPrefix + "INIT_BUY_PX");
      g_state.initialSellPrice          = GlobalVariableGet(g_gvPrefix + "INIT_SELL_PX");
      g_state.initialReferencePrice     = GlobalVariableGet(g_gvPrefix + "INIT_REF_PX");
      g_state.buyLayerCounter           = (int)GlobalVariableGet(g_gvPrefix + "BUY_CNT");
      g_state.sellLayerCounter          = (int)GlobalVariableGet(g_gvPrefix + "SELL_CNT");
      g_state.lastBuyEntryPrice         = GlobalVariableGet(g_gvPrefix + "LAST_BUY_PX");
      g_state.lastSellEntryPrice        = GlobalVariableGet(g_gvPrefix + "LAST_SELL_PX");
      g_state.lastBuyLot                = GlobalVariableGet(g_gvPrefix + "LAST_BUY_LOT");
      g_state.lastSellLot               = GlobalVariableGet(g_gvPrefix + "LAST_SELL_LOT");
      g_state.activeTrendDirection      = (int)GlobalVariableGet(g_gvPrefix + "ACTIVE_DIR");
      g_state.activeTrendStartPrice     = GlobalVariableGet(g_gvPrefix + "DIR_START_PX");
      g_state.activeDirectionalAnchor   = GlobalVariableGet(g_gvPrefix + "DIR_ANCHOR");
      g_state.lastConfirmedSwingHigh    = GlobalVariableGet(g_gvPrefix + "SWING_HIGH");
      g_state.lastConfirmedSwingLow     = GlobalVariableGet(g_gvPrefix + "SWING_LOW");
      g_state.realizedBasketPnL         = GlobalVariableGet(g_gvPrefix + "REALIZED_PNL");
      g_state.peakBasketProfitDollars   = GlobalVariableGet(g_gvPrefix + "PEAK_PNL_USD");
      g_state.peakBasketProfitPercent   = GlobalVariableGet(g_gvPrefix + "PEAK_PNL_PCT");
      g_state.protectedProfitFloorPercent = GlobalVariableGet(g_gvPrefix + "FLOOR_PCT");
      g_state.lastProfitImprovementTime = (datetime)GlobalVariableGet(g_gvPrefix + "LAST_IMP_TIME");
      g_state.bestObservedProfitPercent = GlobalVariableGet(g_gvPrefix + "BEST_PNL_PCT");
      g_state.reversalCount             = (int)GlobalVariableGet(g_gvPrefix + "REV_CNT");
      g_state.totalHistoricalEntries    = (int)GlobalVariableGet(g_gvPrefix + "HIST_ENTRIES");
      g_state.breakEvenDwellSeconds     = (int)GlobalVariableGet(g_gvPrefix + "BEP_DWELL_SEC");
      g_state.stagnationDetected        = (GlobalVariableGet(g_gvPrefix + "STAG_DET") > 0.5);
      g_state.recoveryModeActive        = (GlobalVariableGet(g_gvPrefix + "REC_ACTIVE") > 0.5);
      g_state.basketClosingActive       = (GlobalVariableGet(g_gvPrefix + "CLOSING") > 0.5);
      g_state.profitTrailingActive      = (GlobalVariableGet(g_gvPrefix + "TRAIL_ACTIVE") > 0.5);
      g_state.initialHedgeCompleted     = (GlobalVariableGet(g_gvPrefix + "INIT_DONE") > 0.5);

      if(GlobalVariableCheck(g_gvPrefix + "TOT_BASKETS"))
         g_totalCompletedBaskets = (int)GlobalVariableGet(g_gvPrefix + "TOT_BASKETS");
      if(GlobalVariableCheck(g_gvPrefix + "WIN_BASKETS"))
         g_winningBaskets = (int)GlobalVariableGet(g_gvPrefix + "WIN_BASKETS");
      if(GlobalVariableCheck(g_gvPrefix + "REC_BASKETS"))
         g_completedRecoveryBaskets = (int)GlobalVariableGet(g_gvPrefix + "REC_BASKETS");
      if(GlobalVariableCheck(g_gvPrefix + "ATT_REC_BSK"))
         g_attemptedRecoveryBaskets = (int)GlobalVariableGet(g_gvPrefix + "ATT_REC_BSK");
      if(GlobalVariableCheck(g_gvPrefix + "TOT_REALIZED"))
         g_totalRealizedAllTime = GlobalVariableGet(g_gvPrefix + "TOT_REALIZED");

      return(g_state.basketId > 0);
     }

   if(FileIsExist(g_stateFileName, FILE_COMMON))
     {
      int handle = FileOpen(g_stateFileName, FILE_READ | FILE_BIN | FILE_COMMON);
      if(handle != INVALID_HANDLE)
        {
         FileReadStruct(handle, g_state);
         g_totalCompletedBaskets    = FileReadInteger(handle);
         g_winningBaskets           = FileReadInteger(handle);
         g_completedRecoveryBaskets = FileReadInteger(handle);
         g_attemptedRecoveryBaskets = FileReadInteger(handle);
         g_totalRealizedAllTime     = FileReadDouble(handle);
         FileClose(handle);
         return(g_state.basketId > 0);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Reconcile State With Live Positions & Deal History on Restart    |
//+------------------------------------------------------------------+
void ReconcileBasketFromBroker()
  {
   int openBuy = 0, openSell = 0;
   double lastBuyPx = 0.0, lastSellPx = 0.0;
   double lastBuyLot = 0.0, lastSellLot = 0.0;
   datetime earliestOpen = 0;
   long detectedBasketId = 0;

   int totalPos = PositionsTotal();
   for(int i = 0; i < totalPos; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long posType  = PositionGetInteger(POSITION_TYPE);
      double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      datetime opTm = (datetime)PositionGetInteger(POSITION_TIME);
      string cmt    = PositionGetString(POSITION_COMMENT);
      long bId      = ParseBasketIdFromComment(cmt);

      if(bId > 0 && detectedBasketId == 0)
         detectedBasketId = bId;
      if(earliestOpen == 0 || opTm < earliestOpen)
         earliestOpen = opTm;

      if(posType == POSITION_TYPE_BUY)
        {
         openBuy++;
         lastBuyPx  = openPx;
         lastBuyLot = vol;
        }
      else if(posType == POSITION_TYPE_SELL)
        {
         openSell++;
         lastSellPx  = openPx;
         lastSellLot = vol;
        }
     }

   if(openBuy + openSell > 0)
     {
      if(g_state.basketId <= 0)
         g_state.basketId = (detectedBasketId > 0) ? detectedBasketId : (long)TimeCurrent();
      if(g_state.basketStartBalance <= 0.0)
         g_state.basketStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(g_state.basketStartTime <= 0)
         g_state.basketStartTime = (earliestOpen > 0) ? earliestOpen : TimeCurrent();

      datetime histFrom = g_state.basketStartTime - 60;
      if(HistorySelect(histFrom, TimeCurrent() + 60))
        {
         int histBuyLayers = 0;
         int histSellLayers = 0;
         double histRealized = 0.0;
         ulong seenOrders[];

         int totalDeals = HistoryDealsTotal();
         for(int d = 0; d < totalDeals; d++)
           {
            ulong dealTicket = HistoryDealGetTicket(d);
            if(dealTicket == 0)
               continue;
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
               continue;
            if((ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
               continue;

            string dCmt  = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            long dBasket = ParseBasketIdFromComment(dCmt);
            if(dBasket > 0 && dBasket != g_state.basketId)
               continue;

            long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            long dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
            ulong orderId  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);

            if(entryType == DEAL_ENTRY_IN)
              {
               bool alreadySeen = false;
               for(int k = 0; k < ArraySize(seenOrders); k++)
                 {
                  if(seenOrders[k] == orderId)
                    {
                     alreadySeen = true;
                     break;
                    }
                 }
               if(!alreadySeen && orderId > 0)
                 {
                  int sSz = ArraySize(seenOrders);
                  ArrayResize(seenOrders, sSz + 1);
                  seenOrders[sSz] = orderId;
                  MarkOrderTicketCounted(orderId);

                  if(dealType == DEAL_TYPE_BUY)
                     histBuyLayers++;
                  else if(dealType == DEAL_TYPE_SELL)
                     histSellLayers++;
                 }
               histRealized += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
              }
            else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
              {
               histRealized += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                             + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                             + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                             + HistoryDealGetDouble(dealTicket, DEAL_FEE);
              }
           }

         g_state.buyLayerCounter  = MathMax(g_state.buyLayerCounter, MathMax(histBuyLayers, openBuy));
         g_state.sellLayerCounter = MathMax(g_state.sellLayerCounter, MathMax(histSellLayers, openSell));
         g_state.realizedBasketPnL = histRealized;
        }
      else
        {
         g_state.buyLayerCounter  = MathMax(g_state.buyLayerCounter, openBuy);
         g_state.sellLayerCounter = MathMax(g_state.sellLayerCounter, openSell);
        }

      if(lastBuyPx > 0.0)
         g_state.lastBuyEntryPrice = lastBuyPx;
      if(lastSellPx > 0.0)
         g_state.lastSellEntryPrice = lastSellPx;
      if(lastBuyLot > 0.0)
         g_state.lastBuyLot = lastBuyLot;
      if(lastSellLot > 0.0)
         g_state.lastSellLot = lastSellLot;

      g_state.initialHedgeCompleted = true;
      SavePersistentState();
      PrintFormat("[OurOBoros Vx] Basket reconciliation completed. BasketID=%I64d | BuyCnt=%d | SellCnt=%d | Realized=%.2f",
                  g_state.basketId, g_state.buyLayerCounter, g_state.sellLayerCounter, g_state.realizedBasketPnL);
     }
  }

//+------------------------------------------------------------------+
//| Initialize Brand New Basket Cycle                                |
//+------------------------------------------------------------------+
void InitializeNewBasketCycle()
  {
   ZeroMemory(g_state);
   ArrayResize(g_countedOrderTickets, 0);
   g_lastBuyOrderTime  = 0;
   g_lastSellOrderTime = 0;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = 0.5 * (ask + bid);

   g_state.basketId                  = (long)TimeCurrent() * 100 + (long)(GetTickCount() % 100);
   g_state.basketStartBalance        = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state.basketStartTime           = TimeCurrent();
   g_state.initialBuyPrice           = ask;
   g_state.initialSellPrice          = bid;
   g_state.initialReferencePrice     = mid;
   g_state.buyLayerCounter           = 0;
   g_state.sellLayerCounter          = 0;
   g_state.lastBuyEntryPrice         = ask;
   g_state.lastSellEntryPrice        = bid;
   g_state.lastBuyLot                = 0.0;
   g_state.lastSellLot               = 0.0;
   g_state.activeTrendDirection      = DIR_NEUTRAL;
   g_state.activeTrendStartPrice     = mid;
   g_state.activeDirectionalAnchor   = mid;
   g_state.lastConfirmedSwingHigh    = ask;
   g_state.lastConfirmedSwingLow     = bid;
   g_state.realizedBasketPnL         = 0.0;
   g_state.peakBasketProfitDollars   = 0.0;
   g_state.peakBasketProfitPercent   = 0.0;
   g_state.protectedProfitFloorPercent = InpMinimumBasketProfitPercent;
   g_state.lastProfitImprovementTime = TimeCurrent();
   g_state.bestObservedProfitPercent = -999.0;
   g_state.reversalCount             = 0;
   g_state.totalHistoricalEntries    = 0;
   g_state.breakEvenDwellSeconds     = 0;
   g_state.lastTickTimestamp         = TimeCurrent();
   g_state.stagnationDetected        = false;
   g_state.recoveryModeActive        = false;
   g_state.basketClosingActive       = false;
   g_state.profitTrailingActive      = false;
   g_state.initialHedgeCompleted     = false;

   SavePersistentState();
   PrintFormat("[OurOBoros Vx] New Basket Initialized | BasketID=%I64d | StartBalance=%.2f | RefPrice=%.5f",
               g_state.basketId, g_state.basketStartBalance, mid);
  }

//+------------------------------------------------------------------+
//| Pre-Order Margin & OrderCheck Validation                         |
//+------------------------------------------------------------------+
bool ValidateOrderExecution(ENUM_ORDER_TYPE orderType, double volume, double price, string &rejectReason)
  {
   if(InpEnableMaximumSpreadFilter)
     {
      double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;
      if(spreadPts > InpMaxSpreadPointsIfEnabled)
        {
         rejectReason = StringFormat("Spread filter active: %.1f > %.1f pts", spreadPts, InpMaxSpreadPointsIfEnabled);
         return(false);
        }
     }

   if(InpEnableMarginValidation)
     {
      double marginRequired = 0.0;
      if(!OrderCalcMargin(orderType, _Symbol, volume, price, marginRequired))
        {
         rejectReason = "OrderCalcMargin failed";
         return(false);
        }
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
      double usedMargin = AccountInfoDouble(ACCOUNT_MARGIN);

      if(freeMargin <= marginRequired * 1.05)
        {
         rejectReason = StringFormat("Insufficient free margin: Free=%.2f, Req=%.2f", freeMargin, marginRequired);
         return(false);
        }

      double projectedUsed = usedMargin + marginRequired;
      if(projectedUsed > 0.0)
        {
         double projectedMarginLevel = (equity / projectedUsed) * 100.0;
         if(projectedMarginLevel < InpMinFreeMarginLevelPercent)
           {
            rejectReason = StringFormat("Projected Margin Level %.1f%% < Min %.1f%%", projectedMarginLevel, InpMinFreeMarginLevelPercent);
            return(false);
           }
        }
     }

   MqlTradeRequest req;
   MqlTradeCheckResult check;
   ZeroMemory(req);
   ZeroMemory(check);

   req.action       = TRADE_ACTION_DEAL;
   req.symbol       = _Symbol;
   req.volume       = volume;
   req.type         = orderType;
   req.price        = price;
   req.deviation    = (ulong)InpSlippagePoints;
   req.magic        = InpMagicNumber;
   req.type_filling = g_fillingMode;

   if(!OrderCheck(req, check))
     {
      rejectReason = StringFormat("OrderCheck failed (retcode=%u): %s", check.retcode, check.comment);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Execute Single Layer Order With Bounded Retries & Reconciliation |
//+------------------------------------------------------------------+
bool ExecuteLayerOrder(ENUM_POSITION_TYPE dir, double lot, string phaseTag, double &executedPrice)
  {
   executedPrice = 0.0;
   double normLot = NormalizeLot(lot);
   if(normLot <= 0.0)
      return(false);

   ENUM_ORDER_TYPE orderType = (dir == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   string comment = StringFormat("OBX#%I64d|%s|L%d",
                                 g_state.basketId,
                                 phaseTag,
                                 (dir == POSITION_TYPE_BUY) ? (g_state.buyLayerCounter + 1) : (g_state.sellLayerCounter + 1));

   for(int attempt = 1; attempt <= 3; attempt++)
     {
      MqlTick latestTick;
      if(!SymbolInfoTick(_Symbol, latestTick))
         continue;
      double price = (dir == POSITION_TYPE_BUY) ? latestTick.ask : latestTick.bid;
      if(price <= 0.0)
         continue;

      string rejectReason = "";
      if(!ValidateOrderExecution(orderType, normLot, price, rejectReason))
        {
         if(StringFind(rejectReason, "Insufficient") >= 0 || StringFind(rejectReason, "Margin Level") >= 0)
            g_eaState = STATE_MARGIN_INSUFFICIENT;
         PrintFormat("[OurOBoros Vx] Order skipped (%s): %s", phaseTag, rejectReason);
         return(false);
        }

      g_trade.SetExpertMagicNumber(InpMagicNumber);
      g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
      g_trade.SetTypeFilling(g_fillingMode);

      bool sent = (dir == POSITION_TYPE_BUY)
                  ? g_trade.Buy(normLot, _Symbol, price, 0.0, 0.0, comment)
                  : g_trade.Sell(normLot, _Symbol, price, 0.0, 0.0, comment);

      uint retcode = g_trade.ResultRetcode();
      if(sent && (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL || retcode == TRADE_RETCODE_PLACED))
        {
         ulong orderTicket = g_trade.ResultOrder();
         double fillPrice  = g_trade.ResultPrice();
         if(fillPrice <= 0.0)
            fillPrice = price;
         executedPrice = fillPrice;

         if(dir == POSITION_TYPE_BUY)
            g_lastBuyOrderTime = TimeCurrent();
         else
            g_lastSellOrderTime = TimeCurrent();

         if(!InpEnableDuplicatePrevention || !IsOrderTicketCounted(orderTicket))
           {
            MarkOrderTicketCounted(orderTicket);
            if(dir == POSITION_TYPE_BUY)
              {
               g_state.buyLayerCounter++;
               g_state.lastBuyEntryPrice = fillPrice;
               g_state.lastBuyLot        = normLot;
               if(g_state.buyLayerCounter == 1)
                  g_state.initialBuyPrice = fillPrice;
              }
            else
              {
               g_state.sellLayerCounter++;
               g_state.lastSellEntryPrice = fillPrice;
               g_state.lastSellLot        = normLot;
               if(g_state.sellLayerCounter == 1)
                  g_state.initialSellPrice = fillPrice;
              }
            g_state.totalHistoricalEntries++;
            g_state.activeDirectionalAnchor = fillPrice;
            SavePersistentState();
           }

         PrintFormat("[OurOBoros Vx] %s layer executed | Lot=%.2f | Price=%.5f | BuyCnt=%d | SellCnt=%d | Tag=%s",
                     (dir == POSITION_TYPE_BUY) ? "BUY" : "SELL",
                     normLot, fillPrice, g_state.buyLayerCounter, g_state.sellLayerCounter, phaseTag);
         return(true);
        }
      else
        {
         PrintFormat("[OurOBoros Vx] Order attempt %d rejected (retcode=%u): %s",
                     attempt, retcode, g_trade.ResultRetcodeDescription());
         if(retcode == TRADE_RETCODE_NO_MONEY)
           {
            g_eaState = STATE_MARGIN_INSUFFICIENT;
            return(false);
           }
         if(retcode == TRADE_RETCODE_MARKET_CLOSED)
           {
            g_eaState = STATE_MARKET_CLOSED;
            return(false);
           }
        }
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Simultaneous Dual Entry Engine (BUY 0.01 + SELL 0.01)            |
//+------------------------------------------------------------------+
bool ExecuteInitialDualEntry()
  {
   if(!InpEnableInitialDualEntry)
     {
      g_state.initialHedgeCompleted = true;
      SavePersistentState();
      return(true);
     }

   g_eaState = STATE_OPENING_INITIAL_HEDGE;

   int curBuy = 0, curSell = 0;
   double existingBuyPx = 0.0, existingSellPx = 0.0;
   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long pType = PositionGetInteger(POSITION_TYPE);
      if(pType == POSITION_TYPE_BUY)
        {
         curBuy++;
         existingBuyPx = PositionGetDouble(POSITION_PRICE_OPEN);
        }
      else if(pType == POSITION_TYPE_SELL)
        {
         curSell++;
         existingSellPx = PositionGetDouble(POSITION_PRICE_OPEN);
        }
     }

   bool buyOk  = (curBuy > 0) || !InpEnableBuy;
   bool sellOk = (curSell > 0) || !InpEnableSell;
   double pxBuy = existingBuyPx;
   double pxSell = existingSellPx;

   if(!buyOk)
      buyOk = ExecuteLayerOrder(POSITION_TYPE_BUY, InpInitialBuyLot, "INIT_HEDGE", pxBuy);

   if(!sellOk)
      sellOk = ExecuteLayerOrder(POSITION_TYPE_SELL, InpInitialSellLot, "INIT_HEDGE", pxSell);

   if(buyOk && sellOk)
     {
      if(pxBuy > 0.0 && pxSell > 0.0)
         g_state.initialReferencePrice = 0.5 * (pxBuy + pxSell);
      else if(pxBuy > 0.0)
         g_state.initialReferencePrice = pxBuy;
      else if(pxSell > 0.0)
         g_state.initialReferencePrice = pxSell;

      g_state.activeDirectionalAnchor = g_state.initialReferencePrice;
      g_state.activeTrendStartPrice   = g_state.initialReferencePrice;
      g_state.initialHedgeCompleted   = true;
      g_eaState = STATE_INITIAL_HEDGE_CONFIRMED;
      SavePersistentState();

      PrintFormat("[OurOBoros Vx] Initial Hedge Confirmed | BasketID=%I64d | BuyCnt=%d | SellCnt=%d | NextBuy=%.2f | NextSell=%.2f",
                  g_state.basketId, g_state.buyLayerCounter, g_state.sellLayerCounter, GetNextBuyLot(), GetNextSellLot());
      return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Update Tick Microstructure Ring Buffer                           |
//+------------------------------------------------------------------+
void RecordTickMicrostructure()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   double mid = 0.5 * (ask + bid);
   ulong nowMs = GetTickCount64();

   g_tickMidBuf[g_tickHead]    = mid;
   g_tickTimeMsBuf[g_tickHead] = nowMs;
   g_tickHead = (g_tickHead + 1) % TICK_BUF_SIZE;
   if(g_tickCount < TICK_BUF_SIZE)
      g_tickCount++;
  }

//+------------------------------------------------------------------+
//| Multi-Strategy Weighted Ensemble Market Analysis Engine          |
//+------------------------------------------------------------------+
bool AnalyzeMarketMicrostructureAndRegime(MarketAnalysisResult &out)
  {
   ZeroMemory(out);

   int availBars = Bars(_Symbol, InpTradingTimeframe);
   if(availBars < 60)
      return(false);

   double atrBuf[], emaF[], emaM[], emaS[], hmaH[], hmaF[], rsiBuf[], macdMain[], macdSig[], adxMain[], adxPlus[], adxMinus[], bbUpper[], bbLower[], bbMid[], cciBuf[], stochMain[], sarBuf[];
   MqlRates rates[];

   if(CopyBuffer(g_hATR,     0, 0, 5, atrBuf)   < 5) return(false);
   if(CopyBuffer(g_hEMAFast, 0, 0, 5, emaF)     < 5) return(false);
   if(CopyBuffer(g_hEMAMid,  0, 0, 5, emaM)     < 5) return(false);
   if(CopyBuffer(g_hEMASlow, 0, 0, 5, emaS)     < 5) return(false);
   if(CopyBuffer(g_hHMAHalf, 0, 0, 5, hmaH)     < 5) return(false);
   if(CopyBuffer(g_hHMAFull, 0, 0, 5, hmaF)     < 5) return(false);
   if(CopyBuffer(g_hRSI,     0, 0, 5, rsiBuf)   < 5) return(false);
   if(CopyBuffer(g_hMACD,    0, 0, 5, macdMain) < 5) return(false);
   if(CopyBuffer(g_hMACD,    1, 0, 5, macdSig)  < 5) return(false);
   if(CopyBuffer(g_hADX,     0, 0, 5, adxMain)  < 5) return(false);
   if(CopyBuffer(g_hADX,     1, 0, 5, adxPlus)  < 5) return(false);
   if(CopyBuffer(g_hADX,     2, 0, 5, adxMinus) < 5) return(false);
   if(CopyBuffer(g_hBands,   1, 0, 5, bbUpper)  < 5) return(false);
   if(CopyBuffer(g_hBands,   2, 0, 5, bbLower)  < 5) return(false);
   if(CopyBuffer(g_hBands,   0, 0, 5, bbMid)    < 5) return(false);
   if(CopyBuffer(g_hCCI,     0, 0, 5, cciBuf)   < 5) return(false);
   if(CopyBuffer(g_hStoch,   0, 0, 5, stochMain)< 5) return(false);
   if(CopyBuffer(g_hSAR,     0, 0, 5, sarBuf)   < 5) return(false);
   if(CopyRates(_Symbol, InpTradingTimeframe, 0, 30, rates) < 30) return(false);

   ArraySetAsSeries(atrBuf,   true);
   ArraySetAsSeries(emaF,     true);
   ArraySetAsSeries(emaM,     true);
   ArraySetAsSeries(emaS,     true);
   ArraySetAsSeries(hmaH,     true);
   ArraySetAsSeries(hmaF,     true);
   ArraySetAsSeries(rsiBuf,   true);
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSig,  true);
   ArraySetAsSeries(adxMain,  true);
   ArraySetAsSeries(adxPlus,  true);
   ArraySetAsSeries(adxMinus, true);
   ArraySetAsSeries(bbUpper,  true);
   ArraySetAsSeries(bbLower,  true);
   ArraySetAsSeries(bbMid,    true);
   ArraySetAsSeries(cciBuf,   true);
   ArraySetAsSeries(stochMain,true);
   ArraySetAsSeries(sarBuf,   true);
   ArraySetAsSeries(rates,    true);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid   = 0.5 * (ask + bid);

   double atr = MathMax(atrBuf[0], point * 5.0);
   out.atrValue  = atr;
   out.atrPoints = atr / point;

   //--- 1. Trend Following Module (-1.0 to +1.0)
   double hma0 = 2.0 * hmaH[0] - hmaF[0];
   double hma1 = 2.0 * hmaH[1] - hmaF[1];
   double trendScore = 0.0;
   if(emaF[0] > emaM[0] && emaM[0] > emaS[0]) trendScore += 0.35;
   else if(emaF[0] < emaM[0] && emaM[0] < emaS[0]) trendScore -= 0.35;
   else if(emaF[0] > emaM[0]) trendScore += 0.15;
   else if(emaF[0] < emaM[0]) trendScore -= 0.15;

   trendScore += (hma0 > hma1) ? 0.25 : ((hma0 < hma1) ? -0.25 : 0.0);
   trendScore += (mid > sarBuf[0]) ? 0.20 : -0.20;
   double diDiff = (adxPlus[0] - adxMinus[0]) / MathMax(adxPlus[0] + adxMinus[0], 1.0);
   trendScore += 0.20 * MathMax(-1.0, MathMin(1.0, diDiff * 2.0));
   trendScore = MathMax(-1.0, MathMin(1.0, trendScore));

   //--- 2. Momentum Analysis Module (-1.0 to +1.0)
   double rsiNorm  = MathMax(-1.0, MathMin(1.0, (rsiBuf[0] - 50.0) / 25.0));
   double macdHist = (macdMain[0] - macdSig[0]) / atr;
   double macdNorm = MathMax(-1.0, MathMin(1.0, macdHist * 4.0));
   double cciNorm  = MathMax(-1.0, MathMin(1.0, cciBuf[0] / 150.0));
   double stochNorm= MathMax(-1.0, MathMin(1.0, (stochMain[0] - 50.0) / 35.0));
   double rocNorm  = MathMax(-1.0, MathMin(1.0, (rates[0].close - rates[2].close) / atr));
   double momentumScore = 0.22 * rsiNorm + 0.22 * macdNorm + 0.15 * cciNorm + 0.16 * stochNorm + 0.25 * rocNorm;
   momentumScore = MathMax(-1.0, MathMin(1.0, momentumScore));

   //--- 3. Market Structure Module (HH/HL, LH/LL, BOS, CHoCH)
   double swingHigh = rates[1].high;
   double swingLow  = rates[1].low;
   for(int b = 2; b <= 10; b++)
     {
      if(rates[b].high > swingHigh) swingHigh = rates[b].high;
      if(rates[b].low  < swingLow)  swingLow  = rates[b].low;
     }
   g_state.lastConfirmedSwingHigh = swingHigh;
   g_state.lastConfirmedSwingLow  = swingLow;

   double structScore = 0.0;
   if(mid > swingHigh) structScore += 0.65;
   else if(mid < swingLow) structScore -= 0.65;
   else
     {
      double rangeSpan = MathMax(swingHigh - swingLow, atr);
      double relPos = ((mid - swingLow) / rangeSpan) * 2.0 - 1.0;
      structScore += 0.35 * relPos;
     }
   if(rates[0].close > rates[1].high) structScore += 0.35;
   if(rates[0].close < rates[1].low)  structScore -= 0.35;
   structScore = MathMax(-1.0, MathMin(1.0, structScore));

   //--- 4. Quantitative & Statistical Module (Z-Score & Linear Regression Slope)
   double sumPx = 0.0, sumSq = 0.0;
   int regN = 14;
   double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
   for(int i = 0; i < regN; i++)
     {
      double c = rates[i].close;
      double x = (double)(regN - 1 - i);
      sumPx += c;
      sumSq += c * c;
      sumX  += x;
      sumY  += c;
      sumXY += x * c;
      sumXX += x * x;
     }
   double meanPx = sumPx / regN;
   double varPx  = MathMax((sumSq / regN) - (meanPx * meanPx), point * point);
   double stdPx  = MathSqrt(varPx);
   out.zScore = (mid - meanPx) / stdPx;

   double denomSlope = (regN * sumXX - sumX * sumX);
   double slope = (MathAbs(denomSlope) > 1e-9) ? ((regN * sumXY - sumX * sumY) / denomSlope) : 0.0;
   out.slopeNormalized = MathMax(-1.0, MathMin(1.0, (slope / atr) * 5.0));
   double quantScore = MathMax(-1.0, MathMin(1.0, 0.55 * out.slopeNormalized + 0.45 * MathMax(-1.0, MathMin(1.0, out.zScore / 2.0))));

   //--- 5. Tick-Based Micro-Momentum Module
   double tickScore = 0.0;
   if(g_tickCount >= 6)
     {
      int latestIdx = (g_tickHead - 1 + TICK_BUF_SIZE) % TICK_BUF_SIZE;
      int lookback  = MathMin(12, g_tickCount - 1);
      int oldIdx    = (g_tickHead - 1 - lookback + TICK_BUF_SIZE) % TICK_BUF_SIZE;

      double dPx = g_tickMidBuf[latestIdx] - g_tickMidBuf[oldIdx];
      double dtSec = MathMax((double)(g_tickTimeMsBuf[latestIdx] - g_tickTimeMsBuf[oldIdx]) / 1000.0, 0.05);
      out.tickVelocity = (dPx / point) / dtSec;
      out.tickAcceleration = out.tickVelocity - g_prevTickVelocity;
      g_prevTickVelocity = out.tickVelocity;

      int upTicks = 0, downTicks = 0;
      for(int t = 0; t < lookback; t++)
        {
         int idxA = (g_tickHead - 1 - t + TICK_BUF_SIZE) % TICK_BUF_SIZE;
         int idxB = (g_tickHead - 2 - t + TICK_BUF_SIZE) % TICK_BUF_SIZE;
         if(g_tickMidBuf[idxA] > g_tickMidBuf[idxB]) upTicks++;
         else if(g_tickMidBuf[idxA] < g_tickMidBuf[idxB]) downTicks++;
        }
      out.tickImbalance = (double)(upTicks - downTicks) / (double)lookback;
      tickScore = MathMax(-1.0, MathMin(1.0, 0.60 * out.tickImbalance + 0.40 * MathMax(-1.0, MathMin(1.0, dPx / (atr * 0.35)))));
     }

   //--- 6. Market Regime Detection (ADX + Bollinger Bandwidth)
   double bbWidth = (bbUpper[0] - bbLower[0]) / MathMax(bbMid[0], point);
   double bbWidthPrev = (bbUpper[3] - bbLower[3]) / MathMax(bbMid[3], point);
   double adx = adxMain[0];

   if(adx >= 28.0 && MathAbs(trendScore) >= 0.35)
      out.regime = REGIME_TRENDING_STRONG;
   else if(bbWidth > bbWidthPrev * 1.25 && MathAbs(momentumScore) >= 0.40)
      out.regime = REGIME_VOLATILE_BREAKOUT;
   else if(adx >= 18.0 && MathAbs(trendScore) >= 0.20)
      out.regime = REGIME_TRENDING_MODERATE;
   else if(adx < 16.0 && bbWidth < bbWidthPrev)
      out.regime = REGIME_SIDEWAYS_RANGING;
   else
      out.regime = REGIME_CHOPPY_WHIPSAW;

   //--- 7. Regime-Adaptive Weighted Ensemble (Stable Multi-Indicator Consensus)
   double wTrend = 0.26, wMom = 0.26, wStruct = 0.22, wQuant = 0.14, wTick = 0.12;
   if(out.regime == REGIME_TRENDING_STRONG)
     { wTrend = 0.32; wMom = 0.26; wStruct = 0.20; wQuant = 0.12; wTick = 0.10; }
   else if(out.regime == REGIME_VOLATILE_BREAKOUT)
     { wTrend = 0.20; wMom = 0.30; wStruct = 0.22; wQuant = 0.12; wTick = 0.16; }
   else if(out.regime == REGIME_SIDEWAYS_RANGING || out.regime == REGIME_CHOPPY_WHIPSAW)
     { wTrend = 0.20; wMom = 0.26; wStruct = 0.26; wQuant = 0.16; wTick = 0.12; }

   out.netScore = wTrend * trendScore + wMom * momentumScore + wStruct * structScore + wQuant * quantScore + wTick * tickScore;
   out.netScore = MathMax(-1.0, MathMin(1.0, out.netScore));

   out.bullishScore = MathMax(0.0, out.netScore);
   out.bearishScore = MathMax(0.0, -out.netScore);
   out.trendConfidence = MathMin(1.0, MathAbs(out.netScore) * (0.7 + adx / 60.0));
   out.momentumStrength = MathAbs(momentumScore);
   out.entryOpportunityScore = MathMin(1.0, 0.55 * MathAbs(out.netScore) + 0.25 * out.momentumStrength + 0.20 * MathAbs(tickScore));

   if(out.netScore >= InpDirectionalConfirmThreshold)
      out.direction = DIR_BULLISH;
   else if(out.netScore <= -InpDirectionalConfirmThreshold)
      out.direction = DIR_BEARISH;
   else
      out.direction = DIR_NEUTRAL;

   //--- 8. Reversal Probability & Pullback Filtering
   int prevDir = g_state.activeTrendDirection;
   double displacementFromAnchor = (mid - g_state.activeDirectionalAnchor) / atr;

   if(prevDir == DIR_BULLISH && out.direction == DIR_BEARISH)
     {
      double revScore = 0.45 * out.bearishScore + 0.30 * MathMax(0.0, -displacementFromAnchor) + 0.25 * MathMax(0.0, -tickScore);
      out.reversalProbability = MathMin(1.0, revScore);
      out.isReversalConfirmed = (out.netScore <= -InpReversalConfirmThreshold && displacementFromAnchor <= -0.35);
      out.isPullbackOnly      = !out.isReversalConfirmed;
     }
   else if(prevDir == DIR_BEARISH && out.direction == DIR_BULLISH)
     {
      double revScore = 0.45 * out.bullishScore + 0.30 * MathMax(0.0, displacementFromAnchor) + 0.25 * MathMax(0.0, tickScore);
      out.reversalProbability = MathMin(1.0, revScore);
      out.isReversalConfirmed = (out.netScore >= InpReversalConfirmThreshold && displacementFromAnchor >= 0.35);
      out.isPullbackOnly      = !out.isReversalConfirmed;
     }
   else
     {
      out.reversalProbability = 0.0;
      out.isReversalConfirmed = false;
      out.isPullbackOnly      = false;
     }

   //--- 9. Adaptive Grid Distance Calculation
   double regimeFactor = 1.0;
   if(out.regime == REGIME_TRENDING_STRONG)
      regimeFactor = 0.85;
   else if(out.regime == REGIME_VOLATILE_BREAKOUT)
      regimeFactor = 0.95;
   else if(out.regime == REGIME_SIDEWAYS_RANGING)
      regimeFactor = 1.25;
   else if(out.regime == REGIME_CHOPPY_WHIPSAW)
      regimeFactor = 1.45;

   double rawGridPoints = InpEnableAdaptiveGrid
                          ? (out.atrPoints * InpGridATRMultiplier * regimeFactor)
                          : InpMinimumGridDistancePoints;

   double tickSizePts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / point;
   double minValidPts = MathMax(InpMinimumGridDistancePoints, MathMax(tickSizePts * 2.0, 10.0));
   out.dynamicGridPoints = MathMax(minValidPts, rawGridPoints);

   return(true);
  }

//+------------------------------------------------------------------+
//| Helper: Retrieve Position Entry Commission From Deal History     |
//+------------------------------------------------------------------+
double GetPositionCommission(ulong posId)
  {
   if(posId == 0 || !HistorySelectByPosition(posId))
      return(0.0);

   double totalComm = 0.0;
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
     {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
         totalComm += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
     }
   return(totalComm);
  }

//+------------------------------------------------------------------+
//| Real-Time Basket Metrics, Cost & Break-Even Calculator           |
//+------------------------------------------------------------------+
void ComputeBasketMetrics(BasketMetrics &m)
  {
   ZeroMemory(m);
   m.nearestBuyDistance  = 1e9;
   m.nearestSellDistance = 1e9;

   double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double buyWeightedSum  = 0.0;
   double sellWeightedSum = 0.0;
   double estCommissionPerLot = 0.0;
   int commSamples = 0;

   int totalPos = PositionsTotal();
   for(int i = 0; i < totalPos; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long posId    = PositionGetInteger(POSITION_IDENTIFIER);
      long posType  = PositionGetInteger(POSITION_TYPE);
      double vol    = PositionGetDouble(POSITION_VOLUME);
      double openPx = PositionGetDouble(POSITION_PRICE_OPEN);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap   = PositionGetDouble(POSITION_SWAP);
      double comm   = GetPositionCommission((ulong)posId);

      if(vol > 0.0 && MathAbs(comm) > 0.0)
        {
         estCommissionPerLot += MathAbs(comm) / vol;
         commSamples++;
        }

      m.totalOpenPositions++;
      m.floatingGrossPnL   += profit;
      m.floatingSwap       += swap;
      m.floatingCommission += comm;

      if(posType == POSITION_TYPE_BUY)
        {
         m.buyPositions++;
         m.buyVolume += vol;
         buyWeightedSum += openPx * vol;
         m.buyFloatingPnL += (profit + swap + comm);
         if(openPx > m.highestBuyPrice)
            m.highestBuyPrice = openPx;
         double dist = MathAbs(ask - openPx);
         if(dist < m.nearestBuyDistance)
            m.nearestBuyDistance = dist;
        }
      else if(posType == POSITION_TYPE_SELL)
        {
         m.sellPositions++;
         m.sellVolume += vol;
         sellWeightedSum += openPx * vol;
         m.sellFloatingPnL += (profit + swap + comm);
         if(m.lowestSellPrice == 0.0 || openPx < m.lowestSellPrice)
            m.lowestSellPrice = openPx;
         double dist = MathAbs(bid - openPx);
         if(dist < m.nearestSellDistance)
            m.nearestSellDistance = dist;
        }
     }

   m.netExposure   = m.buyVolume - m.sellVolume;
   m.grossExposure = m.buyVolume + m.sellVolume;
   m.buyWeightedAvgPrice  = (m.buyVolume  > 0.0) ? (buyWeightedSum  / m.buyVolume)  : 0.0;
   m.sellWeightedAvgPrice = (m.sellVolume > 0.0) ? (sellWeightedSum / m.sellVolume) : 0.0;

   double avgExitCommPerLot = (commSamples > 0) ? (estCommissionPerLot / commSamples) : 0.0;
   double slippageDollars   = (tickSize > 0.0) ? ((2.0 * point / tickSize) * tickValue * m.grossExposure) : 0.0;
   m.estimatedExitCosts     = (avgExitCommPerLot * m.grossExposure) + slippageDollars;

   m.floatingNetPnL = m.floatingGrossPnL + m.floatingSwap + m.floatingCommission;
   m.basketNetPnL   = g_state.realizedBasketPnL + m.floatingNetPnL - m.estimatedExitCosts;

   double refBalance = (g_state.basketStartBalance > 0.0) ? g_state.basketStartBalance : AccountInfoDouble(ACCOUNT_BALANCE);
   m.basketNetPercent = (refBalance > 0.0) ? ((m.basketNetPnL / refBalance) * 100.0) : 0.0;

   double mid = 0.5 * (ask + bid);
   if(MathAbs(m.netExposure) >= 0.009 && tickSize > 0.0 && tickValue > 0.0)
     {
      double dollarPerPoint = (point / tickSize) * tickValue * m.netExposure;
      if(MathAbs(dollarPerPoint) > 1e-9)
        {
         double pointsToBEP = -m.basketNetPnL / dollarPerPoint;
         m.estimatedBreakEvenPrice = mid + pointsToBEP * point;
         m.breakEvenDistancePoints = MathAbs(pointsToBEP);
        }
     }
   else
     {
      m.estimatedBreakEvenPrice = mid;
      m.breakEvenDistancePoints = 0.0;
     }

   m.usedMargin  = AccountInfoDouble(ACCOUNT_MARGIN);
   m.freeMargin  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   m.marginLevel = (m.usedMargin > 0.0) ? ((equity / m.usedMargin) * 100.0) : 9999.0;

   if(equity > g_peakAccountEquity)
      g_peakAccountEquity = equity;
   if(g_peakAccountEquity > 0.0)
     {
      double ddPct = ((g_peakAccountEquity - equity) / g_peakAccountEquity) * 100.0;
      if(ddPct > g_maxObservedDrawdownPct)
         g_maxObservedDrawdownPct = ddPct;
     }
  }

//+------------------------------------------------------------------+
//| Selective Position Optimization (Hedged Pair / Winner-Loser)     |
//+------------------------------------------------------------------+
void RunSelectivePositionOptimization()
  {
   if(!InpEnableSelectivePosOpt)
      return;
   if(g_metrics.buyPositions < 3 || g_metrics.sellPositions < 3)
      return;

   ulong bestWinTicket = 0;
   double bestWinPnL   = 0.0;
   double bestWinVol   = 0.0;
   long bestWinType    = -1;

   ulong smallLossTicket = 0;
   double smallLossPnL   = -1e9;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long posId  = PositionGetInteger(POSITION_IDENTIFIER);
      long pType  = PositionGetInteger(POSITION_TYPE);
      double vol  = PositionGetDouble(POSITION_VOLUME);
      double prof = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      double net  = prof + swap + GetPositionCommission((ulong)posId);

      if(net > bestWinPnL && vol <= 0.03)
        {
         bestWinPnL    = net;
         bestWinTicket = ticket;
         bestWinVol    = vol;
         bestWinType   = pType;
        }
     }

   if(bestWinTicket == 0 || bestWinPnL <= 0.0)
      return;

   for(int j = 0; j < PositionsTotal(); j++)
     {
      ulong ticket = PositionGetTicket(j);
      if(ticket == 0 || ticket == bestWinTicket)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      long posId = PositionGetInteger(POSITION_IDENTIFIER);
      long pType = PositionGetInteger(POSITION_TYPE);
      if(pType == bestWinType)
         continue;

      double vol  = PositionGetDouble(POSITION_VOLUME);
      double prof = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      double net  = prof + swap + GetPositionCommission((ulong)posId);

      if(net < 0.0 && (bestWinPnL + net) > 0.05 && MathAbs(vol - bestWinVol) < 0.005)
        {
         if(net > smallLossPnL)
           {
            smallLossPnL    = net;
            smallLossTicket = ticket;
           }
        }
     }

   if(bestWinTicket > 0 && smallLossTicket > 0 && (bestWinPnL + smallLossPnL) > 0.05)
     {
      g_eaState = STATE_POSITION_OPTIMIZATION;
      g_trade.SetExpertMagicNumber(InpMagicNumber);
      g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);

      long orderMode = SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE);
      bool supportsCloseBy = ((orderMode & SYMBOL_ORDER_CLOSEBY) == SYMBOL_ORDER_CLOSEBY);

      if(InpEnableCloseByOptimization && supportsCloseBy)
        {
         if(g_trade.PositionCloseBy(bestWinTicket, smallLossTicket))
           {
            PrintFormat("[OurOBoros Vx] Selective CloseBy Optimization executed | NetGain=+%.2f | Counters Preserved (Buy=%d, Sell=%d)",
                        (bestWinPnL + smallLossPnL), g_state.buyLayerCounter, g_state.sellLayerCounter);
            SavePersistentState();
           }
        }
      else
        {
         if(g_trade.PositionClose(bestWinTicket, (ulong)InpSlippagePoints) &&
            g_trade.PositionClose(smallLossTicket, (ulong)InpSlippagePoints))
           {
            PrintFormat("[OurOBoros Vx] Selective Winner-Loser Pairing executed | NetGain=+%.2f | Counters Preserved (Buy=%d, Sell=%d)",
                        (bestWinPnL + smallLossPnL), g_state.buyLayerCounter, g_state.sellLayerCounter);
            SavePersistentState();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Intelligent Close All Engine (With CloseBy & Reconciliation)     |
//+------------------------------------------------------------------+
bool ExecuteIntelligentCloseAll(string closeReason, bool isRecoveryExit)
  {
   g_eaState = STATE_BASKET_CLOSING;
   g_state.basketClosingActive = true;
   SavePersistentState();

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);

   for(int o = OrdersTotal() - 1; o >= 0; o--)
     {
      ulong ordTicket = OrderGetTicket(o);
      if(ordTicket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC) != InpMagicNumber)
         continue;
      g_trade.OrderDelete(ordTicket);
     }

   long orderMode = SymbolInfoInteger(_Symbol, SYMBOL_ORDER_MODE);
   bool supportsCloseBy = ((orderMode & SYMBOL_ORDER_CLOSEBY) == SYMBOL_ORDER_CLOSEBY);

   if(InpEnableCloseByOptimization && supportsCloseBy)
     {
      for(int pass = 0; pass < 50; pass++)
        {
         ulong buyT = 0, sellT = 0;
         for(int i = 0; i < PositionsTotal(); i++)
           {
            ulong t = PositionGetTicket(i);
            if(t == 0)
               continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
               continue;

            long pType = PositionGetInteger(POSITION_TYPE);
            if(pType == POSITION_TYPE_BUY && buyT == 0)
               buyT = t;
            else if(pType == POSITION_TYPE_SELL && sellT == 0)
               sellT = t;

            if(buyT > 0 && sellT > 0)
               break;
           }
         if(buyT > 0 && sellT > 0)
           {
            if(!g_trade.PositionCloseBy(buyT, sellT))
               break;
           }
         else
            break;
        }
     }

   for(int p = PositionsTotal() - 1; p >= 0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      g_trade.PositionClose(ticket, (ulong)InpSlippagePoints);
     }

   int remaining = 0;
   for(int r = 0; r < PositionsTotal(); r++)
     {
      ulong ticket = PositionGetTicket(r);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;
      remaining++;
     }

   if(remaining > 0)
     {
      PrintFormat("[OurOBoros Vx] Close All partial completion: %d positions remaining, will retry next tick.", remaining);
      return(false);
     }

   g_eaState = STATE_TRANSACTION_RECONCILIATION;
   double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double finalBasketPnL = (g_state.basketStartBalance > 0.0) ? (finalBalance - g_state.basketStartBalance) : g_metrics.basketNetPnL;

   g_totalCompletedBaskets++;
   g_totalRealizedAllTime += finalBasketPnL;
   if(finalBasketPnL >= 0.0)
      g_winningBaskets++;
   if(isRecoveryExit)
      g_completedRecoveryBaskets++;

   PrintFormat("[OurOBoros Vx] BASKET CLOSED (%s) | BasketID=%I64d | NetResult=%.2f | TotalBaskets=%d | WinRate=%.1f%%",
               closeReason, g_state.basketId, finalBasketPnL, g_totalCompletedBaskets,
               (g_totalCompletedBaskets > 0) ? ((double)g_winningBaskets / g_totalCompletedBaskets * 100.0) : 0.0);

   g_eaState = STATE_BASKET_RESET;
   InitializeNewBasketCycle();

   if(g_manualReEntryRequested)
     {
      g_manualReEntryRequested = false;
      g_resetWhenFlatRequested = false;
      g_pauseNewEntries        = false;
      g_autoTradingEnabled     = true;
      g_eaState                = STATE_AUTOMATIC_RE_ENTRY;
      ExecuteInitialDualEntry();
      return(true);
     }

   if(g_resetWhenFlatRequested)
     {
      g_resetWhenFlatRequested = false;
      g_pauseNewEntries = true;
      Print("[OurOBoros Vx] Reset-When-Flat fulfilled: Basket reset and new entries paused.");
      return(true);
     }

   bool shouldRestart = isRecoveryExit ? InpEnableAutoRecoveryRestart : InpEnableAutomaticRestart;
   if(shouldRestart && g_autoTradingEnabled && !g_pauseNewEntries)
     {
      g_eaState = STATE_AUTOMATIC_RE_ENTRY;
      ExecuteInitialDualEntry();
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Evaluate Profit Target, Dynamic Extension & Stagnation Recovery  |
//+------------------------------------------------------------------+
bool EvaluateBasketExitAndRecovery()
  {
   if(g_metrics.totalOpenPositions == 0)
      return(false);

   double netPct    = g_metrics.basketNetPercent;
   double targetPct = InpMinimumBasketProfitPercent;

   if(netPct > g_state.bestObservedProfitPercent + 0.10)
     {
      g_state.bestObservedProfitPercent = netPct;
      g_state.lastProfitImprovementTime = TimeCurrent();
     }

   if(netPct > g_state.peakBasketProfitPercent)
     {
      g_state.peakBasketProfitPercent = netPct;
      g_state.peakBasketProfitDollars = g_metrics.basketNetPnL;
     }

   //--- A. Optional Maximum Profit Cap
   if(InpEnableMaximumProfitCap && netPct >= InpMaximumProfitCapPercent)
     {
      return(ExecuteIntelligentCloseAll(StringFormat("MAX PROFIT CAP %.2f%%", netPct), false));
     }

   //--- B. Minimum Normal Basket Profit Target (2%+) & Dynamic Trailing Extension
   if(netPct >= targetPct)
     {
      g_eaState = STATE_BASKET_PROFIT_TARGET_REACHED;

      // Immediately lock at least the minimum target profit (2%+) once reached
      g_state.profitTrailingActive = true;
      g_state.protectedProfitFloorPercent = MathMax(g_state.protectedProfitFloorPercent, targetPct);

      bool strongMomentumContinuing = InpEnableDynamicProfitExtension
                                      && (g_market.trendConfidence >= 0.45)
                                      && (g_market.reversalProbability < 0.35)
                                      && ((g_metrics.netExposure > 0.0 && g_market.direction == DIR_BULLISH) ||
                                          (g_metrics.netExposure < 0.0 && g_market.direction == DIR_BEARISH));

      if(!InpEnableDynamicProfitExtension && !InpEnableBasketTrailing)
        {
         return(ExecuteIntelligentCloseAll(StringFormat("TARGET REACHED %.2f%%", netPct), false));
        }

      if(InpEnableBasketTrailing)
        {
         if(g_state.peakBasketProfitPercent >= targetPct + InpTrailActivationBufferPercent)
           {
            g_eaState = STATE_BASKET_PROFIT_TRAILING;
            double dynamicFloor = MathMax(targetPct, g_state.peakBasketProfitPercent * InpTrailLockRatio);
            g_state.protectedProfitFloorPercent = MathMax(g_state.protectedProfitFloorPercent, dynamicFloor);

            if(netPct <= g_state.protectedProfitFloorPercent)
              {
               return(ExecuteIntelligentCloseAll(StringFormat("TRAILING FLOOR HIT %.2f%% (Peak %.2f%%)", netPct, g_state.peakBasketProfitPercent), false));
              }
           }
         else if(!strongMomentumContinuing)
           {
            return(ExecuteIntelligentCloseAll(StringFormat("TARGET REALIZED %.2f%%", netPct), false));
           }
         else
           {
            g_eaState = STATE_PROFIT_EXTENSION;
           }
        }
      else if(!strongMomentumContinuing)
        {
         return(ExecuteIntelligentCloseAll(StringFormat("EXTENDED TARGET REALIZED %.2f%%", netPct), false));
        }
     }
   else if(g_state.profitTrailingActive && netPct <= g_state.protectedProfitFloorPercent)
     {
      return(ExecuteIntelligentCloseAll(StringFormat("TRAILING FLOOR PROTECTED %.2f%%", netPct), false));
     }

   //--- C. Intelligent Stagnant Basket Recovery Engine
   if(InpEnableStagnationRecovery)
     {
      datetime now = TimeCurrent();
      int dtSec = (int)(now - g_state.lastTickTimestamp);
      if(dtSec < 0 || dtSec > 60)
         dtSec = 1;
      g_state.lastTickTimestamp = now;

      double ageMinutes = (double)(now - g_state.basketStartTime) / 60.0;
      double noImproveMinutes = (double)(now - g_state.lastProfitImprovementTime) / 60.0;

      if(MathAbs(netPct) <= InpBreakEvenZonePercent)
         g_state.breakEvenDwellSeconds += dtSec;

      double dwellMinutes = (double)g_state.breakEvenDwellSeconds / 60.0;

      bool condAge       = (ageMinutes >= (double)InpStagnationMinAgeMinutes);
      bool condPositions = (g_metrics.totalOpenPositions >= InpStagnationMinPositions);
      bool condStagnant  = (noImproveMinutes >= (double)InpNoMeaningfulImproveMinutes) || (dwellMinutes >= (double)InpBreakEvenDwellMinutes) || (g_state.reversalCount >= 4);

      if(condAge && condPositions && condStagnant)
        {
         if(!g_state.stagnationDetected)
           {
            g_state.stagnationDetected = true;
            g_state.recoveryModeActive = true;
            g_attemptedRecoveryBaskets++;
            SavePersistentState();
            PrintFormat("[OurOBoros Vx] Basket stagnation detected | BasketID=%I64d | Age=%.1fm | Pos=%d | NetPct=%.3f%%",
                        g_state.basketId, ageMinutes, g_metrics.totalOpenPositions, netPct);
           }

         g_eaState = STATE_BREAK_EVEN_RECOVERY;

         double minAcceptablePct = -MathAbs(InpMaximumRecoveryLossPercent);
         if(netPct >= minAcceptablePct)
           {
            return(ExecuteIntelligentCloseAll(StringFormat("STAGNATION BEP RECOVERY (Net=%.3f%%)", netPct), true));
           }
        }
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Directional Pyramiding & Anti-Stacking Reversal Adaptation       |
//+------------------------------------------------------------------+
void ProcessPyramidingAndReversal()
  {
   if(!InpEnableUnlimitedLayering || !InpEnableTrendPyramiding)
      return;
   if(g_pauseNewEntries || !g_autoTradingEnabled || g_state.basketClosingActive)
      return;

   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid   = 0.5 * (ask + bid);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double gridDistPrice = g_market.dynamicGridPoints * point;
   datetime now = TimeCurrent();

   //--- 1. Update Trend State When Reversal Confirmed
   if(InpEnableReversalAdaptation && g_market.isReversalConfirmed)
     {
      if(g_state.activeTrendDirection == DIR_BULLISH && g_market.direction == DIR_BEARISH)
        {
         g_eaState = STATE_REVERSAL_DETECTION;
         g_state.activeTrendDirection    = DIR_BEARISH;
         g_state.activeTrendStartPrice   = bid;
         g_state.activeDirectionalAnchor = bid;
         g_state.reversalCount++;
         SavePersistentState();
        }
      else if(g_state.activeTrendDirection == DIR_BEARISH && g_market.direction == DIR_BULLISH)
        {
         g_eaState = STATE_REVERSAL_DETECTION;
         g_state.activeTrendDirection    = DIR_BULLISH;
         g_state.activeTrendStartPrice   = ask;
         g_state.activeDirectionalAnchor = ask;
         g_state.reversalCount++;
         SavePersistentState();
        }
     }

   if(g_state.activeTrendDirection == DIR_NEUTRAL && g_market.direction != DIR_NEUTRAL)
     {
      g_state.activeTrendDirection    = (int)g_market.direction;
      g_state.activeTrendStartPrice   = mid;
      g_state.activeDirectionalAnchor = (g_market.direction == DIR_BULLISH) ? ask : bid;
      SavePersistentState();
     }

   //--- 2. State Classification
   if(g_market.regime == REGIME_SIDEWAYS_RANGING || g_market.regime == REGIME_CHOPPY_WHIPSAW)
      g_eaState = STATE_SIDEWAYS_ADAPTATION;
   else if(g_market.direction == DIR_BULLISH)
      g_eaState = STATE_BULLISH_PYRAMIDING;
   else if(g_market.direction == DIR_BEARISH)
      g_eaState = STATE_BEARISH_PYRAMIDING;
   else
      g_eaState = STATE_MARKET_DIRECTION_DETECTION;

   //--- 3. Anti-Stacking Bullish Trend & Reversal Pyramiding
   if(InpEnableBuy && InpEnableBullishPyramiding && g_market.direction == DIR_BULLISH && !g_market.isPullbackOnly)
     {
      bool cooldownOk    = ((now - g_lastBuyOrderTime) >= InpMinOrderCooldownSec);
      bool spatialClear  = (g_metrics.buyPositions == 0) || (g_metrics.nearestBuyDistance >= gridDistPrice);

      if(cooldownOk && spatialClear)
        {
         bool trendUpBreakout   = (g_metrics.buyPositions > 0 && ask >= (g_metrics.highestBuyPrice + gridDistPrice));
         bool lowReversalEntry  = (g_metrics.buyPositions == 0) ||
                                  (g_metrics.sellPositions > 0 &&
                                   ask <= (g_metrics.highestBuyPrice - gridDistPrice) &&
                                   (ask - g_metrics.lowestSellPrice) >= gridDistPrice);

         if(trendUpBreakout || lowReversalEntry)
           {
            double nextBuyLot = GetNextBuyLot();
            double execPx = 0.0;
            string tag = trendUpBreakout ? "PYR_BUY" : "REV_BUY";
            if(ExecuteLayerOrder(POSITION_TYPE_BUY, nextBuyLot, tag, execPx))
              {
               g_state.activeTrendDirection    = DIR_BULLISH;
               g_state.activeDirectionalAnchor = execPx;
               SavePersistentState();
              }
           }
        }
     }

   //--- 4. Anti-Stacking Bearish Trend & Reversal Pyramiding
   if(InpEnableSell && InpEnableBearishPyramiding && g_market.direction == DIR_BEARISH && !g_market.isPullbackOnly)
     {
      bool cooldownOk    = ((now - g_lastSellOrderTime) >= InpMinOrderCooldownSec);
      bool spatialClear  = (g_metrics.sellPositions == 0) || (g_metrics.nearestSellDistance >= gridDistPrice);

      if(cooldownOk && spatialClear)
        {
         bool trendDownBreakout = (g_metrics.sellPositions > 0 && bid <= (g_metrics.lowestSellPrice - gridDistPrice));
         bool highReversalEntry = (g_metrics.sellPositions == 0) ||
                                  (g_metrics.buyPositions > 0 &&
                                   bid >= (g_metrics.lowestSellPrice + gridDistPrice) &&
                                   (g_metrics.highestBuyPrice - bid) >= gridDistPrice);

         if(trendDownBreakout || highReversalEntry)
           {
            double nextSellLot = GetNextSellLot();
            double execPx = 0.0;
            string tag = trendDownBreakout ? "PYR_SELL" : "REV_SELL";
            if(ExecuteLayerOrder(POSITION_TYPE_SELL, nextSellLot, tag, execPx))
              {
               g_state.activeTrendDirection    = DIR_BEARISH;
               g_state.activeDirectionalAnchor = execPx;
               SavePersistentState();
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Dashboard UI Creation & Update Helpers                           |
//+------------------------------------------------------------------+
void CreateRectLabel(string name, int x, int y, int w, int h, color bgClr, color borderClr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, borderClr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void CreateTextLabel(string name, int x, int y, string text, color clr, int fontSize = 8, string font = "Consolas")
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, font);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void CreateActionButton(string name, int x, int y, int w, int h, string text, color bgClr, color txtClr)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'212,175,55');
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

void DestroyDashboard()
  {
   ObjectsDeleteAll(0, UI_PREFIX);
   ChartRedraw(0);
  }

double ComputePeriodRealizedPnL(datetime fromTime)
  {
   if(!HistorySelect(fromTime, TimeCurrent() + 60))
      return(0.0);
   double sum = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong dt = HistoryDealGetTicket(i);
      if(dt == 0)
         continue;
      if(HistoryDealGetString(dt, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(dt, DEAL_MAGIC) != InpMagicNumber)
         continue;
      long entry = HistoryDealGetInteger(dt, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_IN)
        {
         sum += HistoryDealGetDouble(dt, DEAL_PROFIT)
              + HistoryDealGetDouble(dt, DEAL_SWAP)
              + HistoryDealGetDouble(dt, DEAL_COMMISSION)
              + HistoryDealGetDouble(dt, DEAL_FEE);
        }
     }
   return(sum);
  }

void UpdateDashboard()
  {
   if(!InpShowDashboard)
      return;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;

   ulong nowMs = GetTickCount64();
   if(nowMs - g_lastDashboardUpdateMs < (ulong)InpDashboardUpdateMs)
      return;
   g_lastDashboardUpdateMs = nowMs;

   int x = InpDashboardX;
   int y = InpDashboardY;

   CreateActionButton(BTN_TOGGLE, x, y, 125, 22, g_panelVisible ? "HIDE PANEL" : "SHOW PANEL", C'26,31,42', C'212,175,55');

   if(!g_panelVisible)
     {
      int totalObjs = ObjectsTotal(0);
      for(int idx = totalObjs - 1; idx >= 0; idx--)
        {
         string objName = ObjectName(0, idx);
         if(StringFind(objName, UI_PREFIX) == 0 && objName != BTN_TOGGLE)
            ObjectDelete(0, objName);
        }
      ChartRedraw(0);
      return;
     }

   int panelW = 540;
   int panelH = 503;
   color bgDark   = C'14,17,23';
   color bgCard   = C'22,27,36';
   color cGold    = C'212,175,55';
   color cGreen   = C'34,197,94';
   color cRed     = C'239,68,68';
   color cAmber   = C'245,158,11';
   color cMuted   = C'160,170,185';

   CreateRectLabel(UI_PREFIX + "BG", x, y + 26, panelW, panelH, bgDark, cGold);
   CreateTextLabel(UI_PREFIX + "TITLE", x + 12, y + 34, InpEAName + "  |  BIDIRECTIONAL ANTI-MARTINGALE ENGINE", cGold, 10, "Arial Bold");

   string stateStr = EnumToString(g_eaState);
   StringReplace(stateStr, "STATE_", "");
   CreateTextLabel(UI_PREFIX + "STATE", x + 12, y + 52, "STATE: " + stateStr + (g_pauseNewEntries ? " [PAUSED]" : ""), g_pauseNewEntries ? cAmber : clrWhite, 8, "Consolas");

   int c1X = x + 12;
   int c2X = x + 278;
   int rowY = y + 74;

   MqlDateTime dtNow;
   TimeToStruct(TimeCurrent(), dtNow);
   dtNow.hour = 0; dtNow.min = 0; dtNow.sec = 0;
   datetime dayStart   = StructToTime(dtNow);
   datetime weekStart  = dayStart - (dtNow.day_of_week * 86400);
   datetime monthStart = dayStart - ((dtNow.day - 1) * 86400);

   double dailyPnL   = ComputePeriodRealizedPnL(dayStart);
   double weeklyPnL  = ComputePeriodRealizedPnL(weekStart);
   double monthlyPnL = ComputePeriodRealizedPnL(monthStart);

   CreateRectLabel(UI_PREFIX + "CARD_ACC", c1X - 4, rowY - 2, 256, 152, bgCard, C'45,52,66');
   CreateTextLabel(UI_PREFIX + "H_ACC", c1X, rowY, "[ ACCOUNT INFORMATION ]", cGold, 8, "Arial Bold");
   CreateTextLabel(UI_PREFIX + "A1", c1X, rowY + 15, StringFormat("Balance / Equity : %.2f / %.2f", AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY)), clrWhite);
   CreateTextLabel(UI_PREFIX + "A2", c1X, rowY + 29, StringFormat("Free / Used Mgn  : %.2f / %.2f", g_metrics.freeMargin, g_metrics.usedMargin), cMuted);
   CreateTextLabel(UI_PREFIX + "A3", c1X, rowY + 43, StringFormat("Margin Level     : %.1f%%", g_metrics.marginLevel), clrWhite);
   CreateTextLabel(UI_PREFIX + "A4", c1X, rowY + 57, StringFormat("Floating P/L     : %+.2f", g_metrics.floatingNetPnL), (g_metrics.floatingNetPnL >= 0.0) ? cGreen : cRed);
   CreateTextLabel(UI_PREFIX + "A5", c1X, rowY + 71, StringFormat("Daily / Weekly   : %+.2f / %+.2f", dailyPnL, weeklyPnL), clrWhite);
   CreateTextLabel(UI_PREFIX + "A6", c1X, rowY + 85, StringFormat("Monthly Realized : %+.2f", monthlyPnL), clrWhite);
   CreateTextLabel(UI_PREFIX + "A7", c1X, rowY + 99, StringFormat("Total Realized   : %+.2f", g_totalRealizedAllTime), (g_totalRealizedAllTime >= 0.0) ? cGreen : cRed);
   CreateTextLabel(UI_PREFIX + "A8", c1X, rowY + 113, StringFormat("Max Obs Drawdown : %.2f%%", g_maxObservedDrawdownPct), cAmber);
   CreateTextLabel(UI_PREFIX + "A9", c1X, rowY + 127, StringFormat("Completed/Win%%   : %d (%.1f%%)", g_totalCompletedBaskets, (g_totalCompletedBaskets > 0) ? ((double)g_winningBaskets / g_totalCompletedBaskets * 100.0) : 0.0), clrWhite);

   int ageMin = (g_state.basketStartTime > 0) ? (int)((TimeCurrent() - g_state.basketStartTime) / 60) : 0;
   double targetUsd = g_state.basketStartBalance * (InpMinimumBasketProfitPercent / 100.0);

   CreateRectLabel(UI_PREFIX + "CARD_BSK", c2X - 4, rowY - 2, 254, 152, bgCard, C'45,52,66');
   CreateTextLabel(UI_PREFIX + "H_BSK", c2X, rowY, "[ BASKET INFORMATION ]", cGold, 8, "Arial Bold");
   CreateTextLabel(UI_PREFIX + "B1", c2X, rowY + 15, StringFormat("Basket ID / Age  : #%I64d (%dm)", g_state.basketId % 1000000, ageMin), clrWhite);
   CreateTextLabel(UI_PREFIX + "B2", c2X, rowY + 29, StringFormat("Start Balance    : %.2f", g_state.basketStartBalance), cMuted);
   CreateTextLabel(UI_PREFIX + "B3", c2X, rowY + 43, StringFormat("Basket Net P/L   : %+.2f (%+.2f%%)", g_metrics.basketNetPnL, g_metrics.basketNetPercent), (g_metrics.basketNetPnL >= 0.0) ? cGreen : cRed);
   CreateTextLabel(UI_PREFIX + "B4", c2X, rowY + 57, StringFormat("Target (%.1f%%)    : +%.2f", InpMinimumBasketProfitPercent, targetUsd), cGold);
   CreateTextLabel(UI_PREFIX + "B5", c2X, rowY + 71, StringFormat("Peak / Floor     : %.2f%% / %.2f%%", g_state.peakBasketProfitPercent, g_state.protectedProfitFloorPercent), clrWhite);
   CreateTextLabel(UI_PREFIX + "B6", c2X, rowY + 85, StringFormat("Est. Break-Even  : %.5f", g_metrics.estimatedBreakEvenPrice), clrWhite);
   CreateTextLabel(UI_PREFIX + "B7", c2X, rowY + 99, StringFormat("Open Positions   : %d (Net %.2f)", g_metrics.totalOpenPositions, g_metrics.netExposure), clrWhite);
   CreateTextLabel(UI_PREFIX + "B8", c2X, rowY + 113, StringFormat("Reversal Count   : %d", g_state.reversalCount), cMuted);
   CreateTextLabel(UI_PREFIX + "B9", c2X, rowY + 127, StringFormat("Exit Cost Buffer : -%.2f", g_metrics.estimatedExitCosts), cMuted);

   int r2Y = rowY + 158;
   CreateRectLabel(UI_PREFIX + "CARD_BUY", c1X - 4, r2Y - 2, 256, 98, bgCard, cGreen);
   CreateTextLabel(UI_PREFIX + "H_BUY", c1X, r2Y, "[ BUY ANTI-MARTINGALE ENGINE ]", cGreen, 8, "Arial Bold");
   CreateTextLabel(UI_PREFIX + "BUY1", c1X, r2Y + 15, StringFormat("Positions / Vol  : %d / %.2f lots", g_metrics.buyPositions, g_metrics.buyVolume), clrWhite);
   CreateTextLabel(UI_PREFIX + "BUY2", c1X, r2Y + 29, StringFormat("BUY Counter      : %d (Max %.2f)", g_state.buyLayerCounter, InpMaximumBuyLot), cGreen);
   CreateTextLabel(UI_PREFIX + "BUY3", c1X, r2Y + 43, StringFormat("Last / Next Lot  : %.2f -> %.2f", g_state.lastBuyLot, GetNextBuyLot()), clrWhite);
   CreateTextLabel(UI_PREFIX + "BUY4", c1X, r2Y + 57, StringFormat("BUY Floating P/L : %+.2f", g_metrics.buyFloatingPnL), (g_metrics.buyFloatingPnL >= 0.0) ? cGreen : cRed);
   CreateTextLabel(UI_PREFIX + "BUY5", c1X, r2Y + 71, StringFormat("BUY Avg Entry    : %.5f", g_metrics.buyWeightedAvgPrice), cMuted);

   CreateRectLabel(UI_PREFIX + "CARD_SELL", c2X - 4, r2Y - 2, 254, 98, bgCard, cRed);
   CreateTextLabel(UI_PREFIX + "H_SELL", c2X, r2Y, "[ SELL ANTI-MARTINGALE ENGINE ]", cRed, 8, "Arial Bold");
   CreateTextLabel(UI_PREFIX + "SELL1", c2X, r2Y + 15, StringFormat("Positions / Vol  : %d / %.2f lots", g_metrics.sellPositions, g_metrics.sellVolume), clrWhite);
   CreateTextLabel(UI_PREFIX + "SELL2", c2X, r2Y + 29, StringFormat("SELL Counter     : %d (Max %.2f)", g_state.sellLayerCounter, InpMaximumSellLot), cRed);
   CreateTextLabel(UI_PREFIX + "SELL3", c2X, r2Y + 43, StringFormat("Last / Next Lot  : %.2f -> %.2f", g_state.lastSellLot, GetNextSellLot()), clrWhite);
   CreateTextLabel(UI_PREFIX + "SELL4", c2X, r2Y + 57, StringFormat("SELL Floating P/L: %+.2f", g_metrics.sellFloatingPnL), (g_metrics.sellFloatingPnL >= 0.0) ? cGreen : cRed);
   CreateTextLabel(UI_PREFIX + "SELL5", c2X, r2Y + 71, StringFormat("SELL Avg Entry   : %.5f", g_metrics.sellWeightedAvgPrice), cMuted);

   int r3Y = r2Y + 104;
   string dirStr = (g_market.direction == DIR_BULLISH) ? "BULLISH" : ((g_market.direction == DIR_BEARISH) ? "BEARISH" : "NEUTRAL");
   color dirClr  = (g_market.direction == DIR_BULLISH) ? cGreen : ((g_market.direction == DIR_BEARISH) ? cRed : cMuted);
   string regStr = EnumToString(g_market.regime);
   StringReplace(regStr, "REGIME_", "");
   double curSpreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point;

   CreateRectLabel(UI_PREFIX + "CARD_MKT", c1X - 4, r3Y - 2, 256, 98, bgCard, C'45,52,66');
   CreateTextLabel(UI_PREFIX + "H_MKT", c1X, r3Y, "[ MARKET ANALYSIS ENGINE ]", cGold, 8, "Arial Bold");
   CreateTextLabel(UI_PREFIX + "M1", c1X, r3Y + 15, StringFormat("Direction / Score: %s (%+.2f)", dirStr, g_market.netScore), dirClr);
   CreateTextLabel(UI_PREFIX + "M2", c1X, r3Y + 29, StringFormat("Market Regime    : %s", regStr), clrWhite);
   CreateTextLabel(UI_PREFIX + "M3", c1X, r3Y + 43, StringFormat("Trend / Mom Conf : %.0f%% / %.0f%%", g_market.trendConfidence * 100.0, g_market.momentumStrength * 100.0), clrWhite);
   CreateTextLabel(UI_PREFIX + "M4", c1X, r3Y + 57, StringFormat("Reversal Prob    : %.0f%%", g_market.reversalProbability * 100.0), (g_market.reversalProbability > 0.5) ? cAmber : cMuted);
   CreateTextLabel(UI_PREFIX + "M5", c1X, r3Y + 71, StringFormat("Spread / Grid    : %.1f / %.1f pts", curSpreadPts, g_market.dynamicGridPoints), clrWhite);

   int noImpMin = (g_state.lastProfitImprovementTime > 0) ? (int)((TimeCurrent() - g_state.lastProfitImprovementTime) / 60) : 0;
   double recSuccessRate = (g_attemptedRecoveryBaskets > 0) ? ((double)g_completedRecoveryBaskets / g_attemptedRecoveryBaskets * 100.0) : 100.0;

   CreateRectLabel(UI_PREFIX + "CARD_REC", c2X - 4, r3Y - 2, 254, 98, bgCard, g_state.recoveryModeActive ? cAmber : C'45,52,66');
   CreateTextLabel(UI_PREFIX + "H_REC", c2X, r3Y, "[ STAGNATION RECOVERY ENGINE ]", cAmber, 8, "Arial Bold");
   CreateTextLabel(UI_PREFIX + "R1", c2X, r3Y + 15, StringFormat("Stagnation/Recov : %s / %s", g_state.stagnationDetected ? "YES" : "NO", g_state.recoveryModeActive ? "ACTIVE" : "STANDBY"), g_state.recoveryModeActive ? cAmber : clrWhite);
   CreateTextLabel(UI_PREFIX + "R2", c2X, r3Y + 29, StringFormat("BEP Distance     : %.1f pts", g_metrics.breakEvenDistancePoints), clrWhite);
   CreateTextLabel(UI_PREFIX + "R3", c2X, r3Y + 43, StringFormat("No Gain / Dwell  : %dm / %dm", noImpMin, g_state.breakEvenDwellSeconds / 60), cMuted);
   CreateTextLabel(UI_PREFIX + "R4", c2X, r3Y + 57, StringFormat("Max Recov Loss   : -%.2f%%", InpMaximumRecoveryLossPercent), clrWhite);
   CreateTextLabel(UI_PREFIX + "R5", c2X, r3Y + 71, StringFormat("Recov Baskets    : %d (%.0f%%)", g_completedRecoveryBaskets, recSuccessRate), clrWhite);

   int btnY  = r3Y + 105;
   int btnY2 = btnY + 29;
   int btnY3 = btnY2 + 29;
   CreateActionButton(BTN_AUTO,      c1X,       btnY,  96,  24, g_autoTradingEnabled ? "AUTO: ON" : "AUTO: OFF", g_autoTradingEnabled ? C'22,101,52' : C'127,29,29', clrWhite);
   CreateActionButton(BTN_PAUSE,     c1X + 101, btnY,  102, 24, "PAUSE ENTRIES", g_pauseNewEntries ? C'180,83,9' : C'30,41,59', clrWhite);
   CreateActionButton(BTN_RESUME,    c1X + 208, btnY,  96,  24, "RESUME", C'30,41,59', cGreen);
   CreateActionButton(BTN_CLOSEALL,  c1X + 309, btnY,  102, 24, "CLOSE ALL EA", C'153,27,27', clrWhite);
   CreateActionButton(BTN_RESET,     c1X + 416, btnY,  100, 24, g_resetWhenFlatRequested ? "RESETTING..." : "RESET FLAT", C'30,41,59', cAmber);
   CreateActionButton(BTN_REENTRY,   c1X,       btnY2, 516, 24, "RESET & RE-ENTRY (NEW CYCLE 0.01)", C'26,54,93', cGold);
   CreateActionButton(BTN_RESET_PNL, c1X,       btnY3, 516, 24, "RESET BASKET NET P/L", C'38,48,64', cAmber);

   ChartRedraw(0);
  }

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   string errMsg = "";
   if(!ValidateEnvironmentCompatibility(errMsg))
     {
      Print("[OurOBoros Vx] INITIALIZATION ERROR: ", errMsg);
      Alert(errMsg);
      return(INIT_FAILED);
     }

   g_fillingMode = DetectFillingMode();
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetDeviationInPoints((ulong)InpSlippagePoints);
   g_trade.SetTypeFilling(g_fillingMode);

   g_gvPrefix      = StringFormat("OBX_%s_%I64u_", _Symbol, InpMagicNumber);
   g_stateFileName = StringFormat("OurOBoros_Vx_%s_%I64u.bin", _Symbol, InpMagicNumber);

   g_hATR     = iATR(_Symbol, InpTradingTimeframe, InpATRPeriod);
   g_hEMAFast = iMA(_Symbol, InpTradingTimeframe, 8,  0, MODE_EMA, PRICE_CLOSE);
   g_hEMAMid  = iMA(_Symbol, InpTradingTimeframe, 21, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMASlow = iMA(_Symbol, InpTradingTimeframe, 55, 0, MODE_EMA, PRICE_CLOSE);
   g_hHMAHalf = iMA(_Symbol, InpTradingTimeframe, 8,  0, MODE_LWMA, PRICE_CLOSE);
   g_hHMAFull = iMA(_Symbol, InpTradingTimeframe, 16, 0, MODE_LWMA, PRICE_CLOSE);
   g_hRSI     = iRSI(_Symbol, InpTradingTimeframe, 14, PRICE_CLOSE);
   g_hMACD    = iMACD(_Symbol, InpTradingTimeframe, 12, 26, 9, PRICE_CLOSE);
   g_hADX     = iADX(_Symbol, InpTradingTimeframe, 14);
   g_hBands   = iBands(_Symbol, InpTradingTimeframe, 20, 0, 2.0, PRICE_CLOSE);
   g_hCCI     = iCCI(_Symbol, InpTradingTimeframe, 14, PRICE_TYPICAL);
   g_hStoch   = iStochastic(_Symbol, InpTradingTimeframe, 14, 3, 3, MODE_SMA, STO_LOWHIGH);
   g_hSAR     = iSAR(_Symbol, InpTradingTimeframe, 0.02, 0.2);

   if(g_hATR == INVALID_HANDLE || g_hEMAFast == INVALID_HANDLE || g_hEMAMid == INVALID_HANDLE ||
      g_hEMASlow == INVALID_HANDLE || g_hHMAHalf == INVALID_HANDLE || g_hHMAFull == INVALID_HANDLE ||
      g_hRSI == INVALID_HANDLE || g_hMACD == INVALID_HANDLE || g_hADX == INVALID_HANDLE ||
      g_hBands == INVALID_HANDLE || g_hCCI == INVALID_HANDLE || g_hStoch == INVALID_HANDLE || g_hSAR == INVALID_HANDLE)
     {
      Print("[OurOBoros Vx] INITIALIZATION ERROR: Failed to create one or more indicator handles.");
      return(INIT_FAILED);
     }

   g_peakAccountEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   bool loaded = LoadPersistentState();
   ReconcileBasketFromBroker();

   ComputeBasketMetrics(g_metrics);
   if(g_metrics.totalOpenPositions == 0 && (!loaded || g_state.basketId <= 0 || g_state.basketClosingActive))
     {
      g_eaState = STATE_BASKET_INITIALIZATION;
      InitializeNewBasketCycle();
     }

   EventSetMillisecondTimer(MathMax(100, InpDashboardUpdateMs));
   UpdateDashboard();

   PrintFormat("[OurOBoros Vx] Initialized successfully on %s (%s) | Magic=%I64u | Filling=%d",
               _Symbol, EnumToString(InpTradingTimeframe), InpMagicNumber, (int)g_fillingMode);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   SavePersistentState();

   if(g_hATR     != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hEMAFast != INVALID_HANDLE) IndicatorRelease(g_hEMAFast);
   if(g_hEMAMid  != INVALID_HANDLE) IndicatorRelease(g_hEMAMid);
   if(g_hEMASlow != INVALID_HANDLE) IndicatorRelease(g_hEMASlow);
   if(g_hHMAHalf != INVALID_HANDLE) IndicatorRelease(g_hHMAHalf);
   if(g_hHMAFull != INVALID_HANDLE) IndicatorRelease(g_hHMAFull);
   if(g_hRSI     != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hMACD    != INVALID_HANDLE) IndicatorRelease(g_hMACD);
   if(g_hADX     != INVALID_HANDLE) IndicatorRelease(g_hADX);
   if(g_hBands   != INVALID_HANDLE) IndicatorRelease(g_hBands);
   if(g_hCCI     != INVALID_HANDLE) IndicatorRelease(g_hCCI);
   if(g_hStoch   != INVALID_HANDLE) IndicatorRelease(g_hStoch);
   if(g_hSAR     != INVALID_HANDLE) IndicatorRelease(g_hSAR);

   DestroyDashboard();
   PrintFormat("[OurOBoros Vx] Deinitialized (Reason=%d). Persistent state saved.", reason);
  }

//+------------------------------------------------------------------+
//| Expert Tick Function (Real-Time Tick-Driven Execution)           |
//+------------------------------------------------------------------+
void OnTick()
  {
   RecordTickMicrostructure();

   if(!IsTradingAllowedNow())
     {
      g_eaState = TerminalInfoInteger(TERMINAL_CONNECTED) ? STATE_MARKET_CLOSED : STATE_CONNECTION_RECOVERY;
      UpdateDashboard();
      return;
     }

   ComputeBasketMetrics(g_metrics);

   if(g_state.basketClosingActive)
     {
      if(g_metrics.totalOpenPositions > 0)
        {
         ExecuteIntelligentCloseAll("RESUME_CLOSING_PHASE", g_state.recoveryModeActive);
         UpdateDashboard();
         return;
        }
      else
        {
         InitializeNewBasketCycle();
         if(g_manualReEntryRequested)
           {
            g_manualReEntryRequested = false;
            g_resetWhenFlatRequested = false;
            g_pauseNewEntries        = false;
            g_autoTradingEnabled     = true;
            g_eaState                = STATE_AUTOMATIC_RE_ENTRY;
            ExecuteInitialDualEntry();
           }
        }
     }

   if(!AnalyzeMarketMicrostructureAndRegime(g_market))
     {
      static datetime lastWaitLog = 0;
      if(TimeCurrent() - lastWaitLog >= 10)
        {
         Print("[OurOBoros Vx] Waiting for historical data and indicator buffers...");
         lastWaitLog = TimeCurrent();
        }
      UpdateDashboard();
      return;
     }

   if(g_metrics.totalOpenPositions == 0 && !g_state.initialHedgeCompleted)
     {
      if(g_autoTradingEnabled && !g_pauseNewEntries)
        {
         if(g_state.basketId <= 0)
            InitializeNewBasketCycle();
         ExecuteInitialDualEntry();
         ComputeBasketMetrics(g_metrics);
        }
      UpdateDashboard();
      return;
     }

   if(EvaluateBasketExitAndRecovery())
     {
      ComputeBasketMetrics(g_metrics);
      UpdateDashboard();
      return;
     }

   RunSelectivePositionOptimization();
   ProcessPyramidingAndReversal();

   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Timer Heartbeat for UI & Connection Monitoring                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   UpdateDashboard();
  }

//+------------------------------------------------------------------+
//| Trade Transaction Listener (Reconciliation & Partial Fill Guard) |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!InpEnableTxReconciliation)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.symbol == _Symbol)
     {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
        {
         if((ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
            return;

         long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         long dealType  = HistoryDealGetInteger(dealTicket, DEAL_TYPE);
         ulong orderId  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);
         double dealPx  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
         double dealVol = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);

         if(entryType == DEAL_ENTRY_IN)
           {
            g_state.realizedBasketPnL += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            if(orderId > 0 && (!InpEnableDuplicatePrevention || !IsOrderTicketCounted(orderId)))
              {
               MarkOrderTicketCounted(orderId);
               if(dealType == DEAL_TYPE_BUY)
                 {
                  g_state.buyLayerCounter++;
                  g_state.lastBuyEntryPrice = dealPx;
                  g_state.lastBuyLot = dealVol;
                 }
               else if(dealType == DEAL_TYPE_SELL)
                 {
                  g_state.sellLayerCounter++;
                  g_state.lastSellEntryPrice = dealPx;
                  g_state.lastSellLot = dealVol;
                 }
               g_state.totalHistoricalEntries++;
              }
            SavePersistentState();
           }
         else if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY)
           {
            double netDeal = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                           + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                           + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                           + HistoryDealGetDouble(dealTicket, DEAL_FEE);
            g_state.realizedBasketPnL += netDeal;
            SavePersistentState();
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Chart Event Handler for Interactive Dashboard Buttons            |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;

   if(sparam == BTN_TOGGLE)
     {
      g_panelVisible = !g_panelVisible;
      ObjectSetInteger(0, BTN_TOGGLE, OBJPROP_STATE, false);
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_AUTO)
     {
      g_autoTradingEnabled = !g_autoTradingEnabled;
      ObjectSetInteger(0, BTN_AUTO, OBJPROP_STATE, false);
      PrintFormat("[OurOBoros Vx] Dashboard Button: AUTO TRADING = %s", g_autoTradingEnabled ? "ON" : "OFF");
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_PAUSE)
     {
      g_pauseNewEntries = true;
      ObjectSetInteger(0, BTN_PAUSE, OBJPROP_STATE, false);
      Print("[OurOBoros Vx] Dashboard Button: NEW ENTRIES PAUSED.");
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_RESUME)
     {
      g_pauseNewEntries = false;
      g_autoTradingEnabled = true;
      ObjectSetInteger(0, BTN_RESUME, OBJPROP_STATE, false);
      Print("[OurOBoros Vx] Dashboard Button: TRADING RESUMED.");
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_CLOSEALL)
     {
      ObjectSetInteger(0, BTN_CLOSEALL, OBJPROP_STATE, false);
      Print("[OurOBoros Vx] Dashboard Button: MANUAL CLOSE ALL EA POSITIONS TRIGGERED.");
      ComputeBasketMetrics(g_metrics);
      ExecuteIntelligentCloseAll("MANUAL_DASHBOARD_CLOSE", false);
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_RESET)
     {
      g_resetWhenFlatRequested = !g_resetWhenFlatRequested;
      ObjectSetInteger(0, BTN_RESET, OBJPROP_STATE, false);
      PrintFormat("[OurOBoros Vx] Dashboard Button: RESET WHEN FLAT = %s", g_resetWhenFlatRequested ? "ARMED" : "CANCELLED");
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_REENTRY)
     {
      ObjectSetInteger(0, BTN_REENTRY, OBJPROP_STATE, false);
      g_manualReEntryRequested = true;
      Print("[OurOBoros Vx] Dashboard Button: MANUAL BASKET RESET & AUTOMATIC RE-ENTRY (0.01) TRIGGERED.");
      ComputeBasketMetrics(g_metrics);
      ExecuteIntelligentCloseAll("MANUAL_RESET_AND_REENTRY", false);
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
   else if(sparam == BTN_RESET_PNL)
     {
      ObjectSetInteger(0, BTN_RESET_PNL, OBJPROP_STATE, false);
      ComputeBasketMetrics(g_metrics);
      g_state.realizedBasketPnL           = -(g_metrics.floatingNetPnL - g_metrics.estimatedExitCosts);
      g_state.peakBasketProfitDollars     = 0.0;
      g_state.peakBasketProfitPercent     = 0.0;
      g_state.protectedProfitFloorPercent = InpMinimumBasketProfitPercent;
      g_state.lastProfitImprovementTime   = TimeCurrent();
      g_state.bestObservedProfitPercent   = -999.0;
      g_state.profitTrailingActive        = false;
      SavePersistentState();
      ComputeBasketMetrics(g_metrics);
      PrintFormat("[OurOBoros Vx] Dashboard Button: BASKET NET P/L RESET TO 0.00 (RealizedOffset=%.2f).", g_state.realizedBasketPnL);
      g_lastDashboardUpdateMs = 0;
      UpdateDashboard();
     }
  }
//+------------------------------------------------------------------+
