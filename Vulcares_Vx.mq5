//+------------------------------------------------------------------+
//|                                                   Vulcares_Vx.mq5|
//|                     VULCARES VX MOMENTUM SCALPING ENGINE         |
//|                      Behavioral Reconstruction Candidate        |
//|                              Version 1.00                       |
//+------------------------------------------------------------------+
// Demo / Strategy Tester only.
// MetaEditor compilation and real-tick backtest not yet verified.
// Original EA behavioral similarity not yet verified.

#property strict
#property version "1.00"
#property description "Vulcares Vx - Tick Momentum Scalping Engine"

#include <Trade/Trade.mqh>

CTrade trade;

enum VX_MODE
{
   SINGLE_ENTRY,
   CONDITIONAL_RECOVERY
};

enum VX_TRAIL
{
   FIXED_DISTANCE,
   VOLATILITY_ADAPTIVE,
   ATR_DISTANCE,
   SPREAD_AWARE,
   PERCENT_LOCK,
   STEP_DISTANCE,
   MOMENTUM_ADAPTIVE
};

enum VX_STATE
{
   INITIALIZING,
   SCANNING,
   MOMENTUM_DETECTED,
   SIGNAL_READY,
   ENTRY_PENDING,
   POSITION_ACTIVE,
   RECOVERY_EVALUATION,
   RECOVERY_ACTIVE,
   BREAK_EVEN_ACTIVE,
   PROFIT_LOCK_ACTIVE,
   TRAILING_ACTIVE,
   EXIT_PENDING,
   RECONCILIATION,
   RE_ENTRY_SCANNING,
   RISK_LOCK,
   DISCONNECTED,
   EMERGENCY_STOP
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+

input group "GENERAL SETTINGS"

input bool TradingEnabled=true;
input bool DemoOnly=true;
input ulong MagicNumber=26011251;
input string TradingSymbol="";
input ENUM_TIMEFRAMES SignalTimeframe=PERIOD_M1;
input bool EnableBuy=true;
input bool EnableSell=false;
input VX_MODE ExecutionMode=SINGLE_ENTRY;

input group "MOMENTUM ENGINE"

input double ReferencePoint=0.001;
input double MomentumThreshold=85;
input int MomentumWindow=2000;
input double TickVelocityThreshold=35;
input double AccelerationThreshold=0;
input double BreakoutSensitivity=0.12;
input double PullbackSensitivity=0.35;
input double EntryConfidenceThreshold=0.62;
input bool EnableIntrabarEntry=true;
input int MinimumPriceChanges=3;

input group "POSITION MANAGEMENT"

input double BaseLot=0.01;
input int MaxPrimaryPositions=1;
input bool EnableRecovery=false;
input double RecoveryLot=0.02;
input double RecoveryTriggerPoints=650;
input int MaxRecoveryPositions=1;
input bool AutoLotMode=false;
input double RiskPerTradePercent=1.0;

input group "STOP MANAGEMENT"

input double InitialStopLossPoints=850;
input bool EnableBreakEven=true;
input double BreakEvenTrigger=150;
input double BreakEvenOffset=20;
input double EstimatedRoundTripCostPerLot=0;
input bool EnableTrailingStop=true;
input VX_TRAIL TrailingMode=FIXED_DISTANCE;
input double TrailingStart=200;
input double TrailingDistance=350;
input double TrailingStep=10;
input bool EnableAdaptiveTrailing=false;
input double AdaptiveMultiplier=1.5;
input double ProfitLockFraction=0.70;
input int ATRPeriod=14;
input bool EnableFixedTakeProfit=false;
input double FixedTakeProfitPoints=1500;
input int MinModifyIntervalMilliseconds=100;

input group "RAPID RE-ENTRY"

input bool EnableRapidReentry=true;
input int ReentryDelayMilliseconds=0;
input bool AllowSameCandleReentry=true;

input group "RISK MANAGEMENT"

input double MaxSpreadPoints=400;
input int MaxSlippagePoints=100;
input double MaxDailyLossPercent=5;
input double MaxEquityDrawdownPercent=12;
input double MaxExposure=0.03;
input double MinimumFreeMarginPercent=50;
input double MaxSingleOrderRiskPercent=3;
input int MaximumConsecutiveLosses=4;
input double MaxAbnormalJumpPoints=5000;
input bool CloseOnRiskLock=true;
input bool ExportEvents=true;
input bool DashboardEnabled=true;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                 |
//+------------------------------------------------------------------+

string sym,prefix,key;

double pt,unit,ticksize,vmin,vmax,vstep;

int digits;
int atrHandle=INVALID_HANDLE;
int logfile=INVALID_HANDLE;

bool hedging=false;
bool pending=false;
bool uncertain=false;
bool emergency=false;
bool riskLocked=false;
bool recoveryUsed=false;
bool hadPosition=false;
bool historyDirty=true;
bool historyOK=false;

long lastEntryTry=0;
long lastExit=0;
long lastTick=0;
long lastSignalBar=0;
long pendingSince=0;
long lastEvaluatedBar=0;

int dayCode=0;
int losses=0;
int wins=0;
int trades=0;
int active=0;

double dayEquity=0;
double peakEquity=0;
double dailyNet=0;
double grossWin=0;
double grossLoss=0;
double exposure=0;
double floating=0;
double locked=0;

double buyConf=0;
double sellConf=0;
double velocity=0;
double accel=0;
double shortRange=0;
double displaySL=0;
double displayExtreme=0;

string regime="DORMANT";
string statusReason="";
string modeText="";

VX_STATE state=INITIALIZING;

struct Sample
{
   long ms;
   double mid;
};

Sample ring[8192];

int head=0;
int used=0;

struct Feature
{
   double delta;
   double range;
   double consistency;
   double speed;
   double low;
   double high;
   int changes;
   long span;
};

struct Track
{
   ulong ticket;
   double extreme;
   long lastModify;
};

Track tracks[8];

int ntracks=0;

const int windows[11]=
{
   100,250,500,1000,2000,3000,
   5000,10000,15000,30000,60000
};

Feature features[11];

//+------------------------------------------------------------------+
//| ACCOUNT SECURITY                                                 |
//+------------------------------------------------------------------+

bool Tester()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

bool SafeAccount()
{
   return Tester() ||
          AccountInfoInteger(ACCOUNT_TRADE_MODE)
          ==ACCOUNT_TRADE_MODE_DEMO;
}

long NowMs()
{
   MqlTick t;

   if(SymbolInfoTick(sym,t))
      return t.time_msc;

   return lastTick;
}

void SetState(VX_STATE s,string why="")
{
   state=s;
   statusReason=why;
}

void Event(
   string kind,
   ulong ticket,
   double price,
   double lot,
   double sl,
   string detail
)
{
   if(logfile!=INVALID_HANDLE)
   {
      FileWrite(
         logfile,
         NowMs(),
         kind,
         ticket,
         DoubleToString(price,digits),
         DoubleToString(lot,4),
         DoubleToString(sl,digits),
         detail
      );

      FileFlush(logfile);
   }
}

//+------------------------------------------------------------------+
//| PERSISTENT STATE                                                 |
//+------------------------------------------------------------------+

string Persistent(string suffix)
{
   return key+suffix;
}

double Load(string suffix,double fallback)
{
   if(!Tester() &&
      GlobalVariableCheck(Persistent(suffix)))
      return GlobalVariableGet(Persistent(suffix));

   return fallback;
}

void Save(string suffix,double value)
{
   if(!Tester())
      GlobalVariableSet(Persistent(suffix),value);
}

string TrackKey(ulong ticket)
{
   return "H"+IntegerToString((long)ticket);
}

//+------------------------------------------------------------------+
//| NORMALIZATION                                                    |
//+------------------------------------------------------------------+

double Down(double price)
{
   return NormalizeDouble(
      MathFloor(price/ticksize+1e-8)*ticksize,
      digits
   );
}

double Up(double price)
{
   return NormalizeDouble(
      MathCeil(price/ticksize-1e-8)*ticksize,
      digits
   );
}

double Volume(double value)
{
   if(value<vmin-1e-9)
      return 0;

   double result=NormalizeDouble(
      MathFloor(
         (MathMin(value,vmax)+1e-10)/vstep
      )*vstep,
      8
   );

   return result>=vmin-1e-9 ? result : 0;
}

bool Own()
{
   return PositionGetString(POSITION_SYMBOL)==sym &&
          (ulong)PositionGetInteger(POSITION_MAGIC)
          ==MagicNumber;
}

//+------------------------------------------------------------------+
//| NETTING ACCOUNT ISOLATION                                        |
//+------------------------------------------------------------------+

bool NettingIsolated()
{
   if(hedging || !PositionSelect(sym))
      return true;

   if(!Own())
      return false;

   ulong id=(ulong)PositionGetInteger(
      POSITION_IDENTIFIER
   );

   if(!HistorySelectByPosition(id))
      return false;

   bool seen=false;

   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);

      if(deal==0)
         continue;

      long type=HistoryDealGetInteger(
         deal,DEAL_TYPE
      );

      if(type!=DEAL_TYPE_BUY &&
         type!=DEAL_TYPE_SELL)
         continue;

      seen=true;

      if((ulong)HistoryDealGetInteger(
         deal,DEAL_MAGIC
      )!=MagicNumber)
         return false;
   }

   return seen;
}

int OwnOrders()
{
   int count=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(OrderGetString(ORDER_SYMBOL)==sym &&
         (ulong)OrderGetInteger(ORDER_MAGIC)
         ==MagicNumber)
         count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| POSITION RECONCILIATION                                          |
//+------------------------------------------------------------------+

void Reconcile()
{
   active=0;
   exposure=0;
   floating=0;

   bool rec=false;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0 || !Own())
         continue;

      active++;

      exposure+=PositionGetDouble(
         POSITION_VOLUME
      );

      floating+=PositionGetDouble(
         POSITION_PROFIT
      )+PositionGetDouble(POSITION_SWAP);

      if(StringFind(
         PositionGetString(POSITION_COMMENT),
         "VX-R"
      )>=0)
         rec=true;
   }

   if(active>1 || rec)
   {
      recoveryUsed=true;
      Save("rec",1);
   }

   if(active==0 && hadPosition)
   {
      lastExit=NowMs();

      Save("exit",(double)lastExit);

      recoveryUsed=false;

      Save("rec",0);

      ntracks=0;

      Event(
         "FLAT",0,0,0,0,
         "Position lifecycle ended"
      );
   }

   hadPosition=active>0;
}

//+------------------------------------------------------------------+
//| REAL-TIME TICK BUFFER                                            |
//+------------------------------------------------------------------+

void AddTick(MqlTick &tick)
{
   double mid=(tick.bid+tick.ask)*0.5;

   if(used>0)
   {
      int prev=(head+8191)%8192;

      if(tick.time_msc<ring[prev].ms)
         return;

      if(tick.time_msc==ring[prev].ms &&
         mid==ring[prev].mid)
         return;
   }

   ring[head].ms=tick.time_msc;
   ring[head].mid=mid;

   head=(head+1)%8192;

   if(used<8192)
      used++;
}

//+------------------------------------------------------------------+
//| MULTI-WINDOW MOMENTUM MEASUREMENT                                |
//+------------------------------------------------------------------+

Feature Measure(int milliseconds)
{
   Feature f;

   ZeroMemory(f);

   if(used<2)
      return f;

   int j=(head+8191)%8192;

   double end=ring[j].mid;
   double old=end;

   long now=ring[j].ms;

   f.low=end;
   f.high=end;

   int up=0;
   int down=0;

   for(int i=1;i<used;i++)
   {
      int k=(head+8191-i+8192)%8192;

      long age=now-ring[k].ms;

      if(age>milliseconds)
         break;

      double price=ring[k].mid;

      if(old>price)
         up++;

      if(old<price)
         down++;

      old=price;

      f.low=MathMin(f.low,price);
      f.high=MathMax(f.high,price);
      f.span=age;
   }

   f.changes=up+down;

   f.delta=(end-old)/unit;

   f.range=(f.high-f.low)/unit;

   f.consistency=f.changes>0
      ? (double)(up-down)/f.changes
      : 0;

   f.speed=f.span>0
      ? f.delta*1000.0/(double)f.span
      : 0;

   return f;
}

double Clamp(double value)
{
   return MathMax(
      0.0,
      MathMin(1.0,value)
   );
}

//+------------------------------------------------------------------+
//| MOMENTUM SIGNAL ENGINE                                           |
//+------------------------------------------------------------------+

int Signal(MqlTick &tick)
{
   Feature f=Measure(MomentumWindow);

   Feature fast=Measure(
      (int)MathMax(100,MomentumWindow/4)
   );

   for(int i=0;i<11;i++)
      features[i]=Measure(windows[i]);

   velocity=f.speed;
   accel=fast.speed-f.speed;
   shortRange=f.range;

   regime=
      f.changes<MinimumPriceChanges
      ? "DORMANT"
      : f.range<MomentumThreshold*0.5
      ? "LOW VOLATILITY"
      : f.range>MomentumThreshold*5
      ? "EXTREME VOLATILITY"
      : f.range>MomentumThreshold*2
      ? "HIGH VOLATILITY"
      : "NORMAL VOLATILITY";

   buyConf=0;
   sellConf=0;

   if(f.changes<MinimumPriceChanges ||
      f.span<MomentumWindow/4 ||
      f.range<=0)
      return 0;

   double mid=(tick.bid+tick.ask)*0.5;

   double loc=Clamp(
      (mid-f.low)/(f.high-f.low)
   );

   double candleOpen=iOpen(
      sym,SignalTimeframe,0
   );

   if(candleOpen<=0)
      return 0;

   double candle=(mid-candleOpen)/unit;

   buyConf=
      0.4*Clamp(f.delta/MomentumThreshold)
      +0.3*Clamp((f.consistency+1)/2)
      +0.2*loc
      +0.1*Clamp(candle/MomentumThreshold);

   sellConf=
      0.4*Clamp(-f.delta/MomentumThreshold)
      +0.3*Clamp((1-f.consistency)/2)
      +0.2*(1-loc)
      +0.1*Clamp(-candle/MomentumThreshold);

   bool buy=
      f.delta>=MomentumThreshold &&
      f.speed>=TickVelocityThreshold &&
      buyConf>=EntryConfidenceThreshold &&
      (
         loc>=1-BreakoutSensitivity ||
         (
            loc>=1-PullbackSensitivity &&
            fast.delta>0
         )
      );

   bool sell=
      -f.delta>=MomentumThreshold &&
      -f.speed>=TickVelocityThreshold &&
      sellConf>=EntryConfidenceThreshold &&
      (
         loc<=BreakoutSensitivity ||
         (
            loc<=PullbackSensitivity &&
            fast.delta<0
         )
      );

   if(AccelerationThreshold>0)
   {
      buy=buy &&
          accel>=AccelerationThreshold;

      sell=sell &&
           -accel>=AccelerationThreshold;
   }

   if(buy || sell)
      regime="MOMENTUM CONTINUATION";

   if(buy && EnableBuy)
      return 1;

   if(sell && EnableSell)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| RISK MANAGEMENT ENGINE                                           |
//+------------------------------------------------------------------+

int Day(datetime time)
{
   MqlDateTime d;

   TimeToStruct(time,d);

   return d.year*1000+d.day_of_year;
}

void RefreshRisk()
{
   double equity=AccountInfoDouble(
      ACCOUNT_EQUITY
   );

   int currentDay=Day(TimeCurrent());

   if(currentDay!=dayCode)
   {
      dayCode=currentDay;
      dayEquity=equity;

      Save("day",dayCode);
      Save("dayeq",dayEquity);

      historyDirty=true;
   }

   if(equity>peakEquity)
   {
      peakEquity=equity;
      Save("peak",equity);
   }

   if(historyDirty)
   {
      MqlDateTime dt;

      TimeToStruct(TimeCurrent(),dt);

      dt.hour=0;
      dt.min=0;
      dt.sec=0;

      historyOK=HistorySelect(
         0,TimeCurrent()
      );

      if(historyOK)
      {
         dailyNet=0;
         wins=0;
         trades=0;
         grossWin=0;
         grossLoss=0;
         losses=0;

         datetime dayStart=StructToTime(dt);

         ulong ids[];
         double pnl[];
         long exitTime[];
         double volumes[];

         int n=0;

         for(int i=0;i<HistoryDealsTotal();i++)
         {
            ulong z=HistoryDealGetTicket(i);

            if(z==0 ||
               HistoryDealGetString(
                  z,DEAL_SYMBOL
               )!=sym ||
               (ulong)HistoryDealGetInteger(
                  z,DEAL_MAGIC
               )!=MagicNumber)
               continue;

            long type=HistoryDealGetInteger(
               z,DEAL_TYPE
            );

            if(type!=DEAL_TYPE_BUY &&
               type!=DEAL_TYPE_SELL)
               continue;

            double profit=
               HistoryDealGetDouble(
                  z,DEAL_PROFIT
               )+
               HistoryDealGetDouble(
                  z,DEAL_COMMISSION
               )+
               HistoryDealGetDouble(
                  z,DEAL_SWAP
               )+
               HistoryDealGetDouble(
                  z,DEAL_FEE
               );

            datetime ts=(datetime)
               HistoryDealGetInteger(
                  z,DEAL_TIME
               );

            if(ts>=dayStart)
               dailyNet+=profit;

            ulong id=(ulong)
               HistoryDealGetInteger(
                  z,DEAL_POSITION_ID
               );

            int j=0;

            for(;j<n;j++)
               if(ids[j]==id)
                  break;

            if(j==n)
            {
               n++;

               ArrayResize(ids,n,128);
               ArrayResize(pnl,n,128);
               ArrayResize(exitTime,n,128);
               ArrayResize(volumes,n,128);

               ids[j]=id;
               pnl[j]=0;
               exitTime[j]=0;
               volumes[j]=0;
            }

            pnl[j]+=profit;

            long entry=HistoryDealGetInteger(
               z,DEAL_ENTRY
            );

            double volume=HistoryDealGetDouble(
               z,DEAL_VOLUME
            );

            if(entry==DEAL_ENTRY_IN)
               volumes[j]+=volume;

            else if(entry==DEAL_ENTRY_OUT ||
                    entry==DEAL_ENTRY_OUT_BY)
            {
               volumes[j]-=volume;

               exitTime[j]=
                  HistoryDealGetInteger(
                     z,DEAL_TIME_MSC
                  );
            }
         }

         long cutoff=LONG_MAX;

         for(int j=0;j<n;j++)
         {
            if(exitTime[j]<=0 ||
               MathAbs(volumes[j])>1e-7)
               continue;

            trades++;

            if(pnl[j]>0)
            {
               wins++;
               grossWin+=pnl[j];
            }
            else
            {
               grossLoss-=MathMin(0,pnl[j]);
            }
         }

         for(int k=0;k<n;k++)
         {
            int best=-1;
            long latest=0;

            for(int j=0;j<n;j++)
            {
               if(MathAbs(volumes[j])<=1e-7 &&
                  exitTime[j]>latest &&
                  exitTime[j]<cutoff)
               {
                  latest=exitTime[j];
                  best=j;
               }
            }

            if(best<0 || pnl[best]>=0)
               break;

            losses++;
            cutoff=latest;
         }

         historyDirty=false;
      }
   }

   double dayDD=dayEquity>0
      ? 100*(dayEquity-equity)/dayEquity
      : 0;

   double drawdown=peakEquity>0
      ? 100*(peakEquity-equity)/peakEquity
      : 0;

   if(
      dayDD>=MaxDailyLossPercent ||
      (
         dayEquity>0 &&
         -dailyNet>=
            dayEquity*MaxDailyLossPercent/100
      ) ||
      drawdown>=MaxEquityDrawdownPercent ||
      losses>=MaximumConsecutiveLosses
   )
   {
      riskLocked=true;
      Save("risk",1);
   }
}

//+------------------------------------------------------------------+
//| EXECUTION VALIDATION                                             |
//+------------------------------------------------------------------+

bool Accepted(uint retcode)
{
   return
      retcode==TRADE_RETCODE_DONE ||
      retcode==TRADE_RETCODE_DONE_PARTIAL ||
      retcode==TRADE_RETCODE_PLACED;
}

bool Ambiguous(uint retcode)
{
   return
      retcode==TRADE_RETCODE_TIMEOUT ||
      retcode==TRADE_RETCODE_CONNECTION ||
      retcode==TRADE_RETCODE_ERROR ||
      retcode==0;
}

void TradeResult(
   bool sent,
   string action,
   ulong ticket,
   double price,
   double volume,
   double sl
)
{
   uint retcode=trade.ResultRetcode();

   Event(
      action,
      ticket,
      price,
      volume,
      sl,
      IntegerToString((long)retcode)
      +" "+trade.ResultRetcodeDescription()
   );

   if(!sent || !Accepted(retcode))
   {
      Print(
         "VX ",
         action,
         " ",
         retcode,
         " ",
         trade.ResultRetcodeDescription()
      );
   }
}

bool CanSend()
{
   return
      SafeAccount() &&
      (
         Tester() ||
         TerminalInfoInteger(
            TERMINAL_CONNECTED
         )
      ) &&
      MQLInfoInteger(MQL_TRADE_ALLOWED) &&
      AccountInfoInteger(
         ACCOUNT_TRADE_ALLOWED
      ) &&
      AccountInfoInteger(
         ACCOUNT_TRADE_EXPERT
      ) &&
      (
         Tester() ||
         TerminalInfoInteger(
            TERMINAL_TRADE_ALLOWED
         )
      );
}

double StopGap(bool freeze)
{
   long stops=SymbolInfoInteger(
      sym,SYMBOL_TRADE_STOPS_LEVEL
   );

   if(freeze)
   {
      stops=(long)MathMax(
         stops,
         SymbolInfoInteger(
            sym,SYMBOL_TRADE_FREEZE_LEVEL
         )
      );
   }

   return MathMax(
      ticksize,
      (double)stops*pt
   )+ticksize;
}

//+------------------------------------------------------------------+
//| HIGH-WATERMARK POSITION TRACKING                                 |
//+------------------------------------------------------------------+

int TrackIndex(ulong ticket,double price)
{
   for(int i=0;i<ntracks;i++)
      if(tracks[i].ticket==ticket)
         return i;

   if(ntracks>=8)
   {
      for(int i=0;i<ntracks;i++)
      {
         if(!PositionSelectByTicket(
            tracks[i].ticket
         ))
         {
            tracks[i]=tracks[ntracks-1];
            ntracks--;
            break;
         }
      }
   }

   if(ntracks>=8)
      return -1;

   int j=ntracks++;

   tracks[j].ticket=ticket;

   tracks[j].extreme=Load(
      TrackKey(ticket),price
   );

   tracks[j].lastModify=0;

   Save(
      TrackKey(ticket),
      tracks[j].extreme
   );

   return j;
}

//+------------------------------------------------------------------+
//| ULTRA-RESPONSIVE TRAILING STOP                                   |
//+------------------------------------------------------------------+

void ManageStops(MqlTick &tick)
{
   if(!CanSend() || !NettingIsolated())
      return;

   locked=0;
   displaySL=0;
   displayExtreme=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0 || !Own())
         continue;

      bool buy=
         PositionGetInteger(POSITION_TYPE)
         ==POSITION_TYPE_BUY;

      double openPrice=PositionGetDouble(
         POSITION_PRICE_OPEN
      );

      double oldSL=PositionGetDouble(
         POSITION_SL
      );

      double tp=PositionGetDouble(
         POSITION_TP
      );

      double volume=PositionGetDouble(
         POSITION_VOLUME
      );

      double swap=PositionGetDouble(
         POSITION_SWAP
      );

      double price=buy ? tick.bid : tick.ask;

      int j=TrackIndex(ticket,price);

      if(j<0)
         continue;

      if(!PositionSelectByTicket(ticket) ||
         !Own())
         continue;

      double extreme=buy
         ? MathMax(tracks[j].extreme,price)
         : MathMin(tracks[j].extreme,price);

      if(extreme!=tracks[j].extreme)
      {
         tracks[j].extreme=extreme;

         Save(
            TrackKey(ticket),
            extreme
         );
      }

      displayExtreme=extreme;
      displaySL=oldSL;

      if(DashboardEnabled &&
         !MQLInfoInteger(MQL_OPTIMIZATION) &&
         oldSL>0)
      {
         string line=prefix+"SL"+
            IntegerToString((long)ticket);

         if(ObjectFind(0,line)<0)
         {
            ObjectCreate(
               0,line,OBJ_HLINE,0,0,oldSL
            );
         }

         ObjectSetDouble(
            0,line,OBJPROP_PRICE,oldSL
         );

         ObjectSetInteger(
            0,line,OBJPROP_COLOR,clrTomato
         );

         ObjectSetInteger(
            0,line,OBJPROP_STYLE,STYLE_DASH
         );
      }

      double gap=StopGap(true);

      double profitPoints=
         (
            buy
            ? extreme-openPrice
            : openPrice-extreme
         )/unit;

      double candidate=oldSL>0
         ? oldSL
         : (
            buy
            ? openPrice-InitialStopLossPoints*unit
            : openPrice+InitialStopLossPoints*unit
         );

      double costPoints=0;
      double one=0;

      if(
         OrderCalcProfit(
            buy ? ORDER_TYPE_BUY
                : ORDER_TYPE_SELL,
            sym,
            volume,
            openPrice,
            openPrice+(buy ? unit : -unit),
            one
         ) &&
         one>0
      )
      {
         costPoints=MathMax(
            0.0,
            (
               EstimatedRoundTripCostPerLot
               *volume-swap
            )/one
         );
      }

      // BREAK-EVEN PROTECTION

      if(EnableBreakEven &&
         profitPoints>=BreakEvenTrigger)
      {
         double be=openPrice+
            (buy ? 1 : -1)*
            (BreakEvenOffset+costPoints)*unit;

         candidate=buy
            ? MathMax(candidate,be)
            : MathMin(candidate,be);

         SetState(BREAK_EVEN_ACTIVE);
      }

      // DYNAMIC TRAILING

      if(EnableTrailingStop &&
         profitPoints>=TrailingStart)
      {
         double distance=TrailingDistance;

         if(
            TrailingMode==VOLATILITY_ADAPTIVE ||
            EnableAdaptiveTrailing
         )
         {
            distance=MathMax(
               distance,
               shortRange*AdaptiveMultiplier
            );
         }

         if(
            TrailingMode==ATR_DISTANCE &&
            atrHandle!=INVALID_HANDLE
         )
         {
            double atr[1];

            if(CopyBuffer(
               atrHandle,0,1,1,atr
            )==1)
            {
               distance=MathMax(
                  distance,
                  atr[0]/unit*AdaptiveMultiplier
               );
            }
         }

         if(TrailingMode==SPREAD_AWARE)
         {
            distance=MathMax(
               distance,
               (tick.ask-tick.bid)/unit
               *AdaptiveMultiplier
            );
         }

         if(TrailingMode==PERCENT_LOCK)
         {
            distance=MathMax(
               ticksize/unit,
               profitPoints*
               (1-ProfitLockFraction)
            );
         }

         if(TrailingMode==MOMENTUM_ADAPTIVE)
         {
            distance=MathMax(
               distance,
               MathAbs(velocity)
               *AdaptiveMultiplier
            );
         }

         double trailing=extreme+
            (buy ? -1 : 1)*distance*unit;

         candidate=buy
            ? MathMax(candidate,trailing)
            : MathMin(candidate,trailing);

         SetState(TRAILING_ACTIVE);
      }

      // BROKER VALIDATION

      candidate=buy
         ? Down(MathMin(
            candidate,tick.bid-gap
         ))
         : Up(MathMax(
            candidate,tick.ask+gap
         ));

      if(oldSL>0)
      {
         double profit=0;

         if(OrderCalcProfit(
            buy ? ORDER_TYPE_BUY
                : ORDER_TYPE_SELL,
            sym,
            volume,
            openPrice,
            oldSL,
            profit
         ))
         {
            locked+=profit+swap-
               EstimatedRoundTripCostPerLot
               *volume;
         }
      }

      double step=MathMax(
         ticksize,
         TrailingStep*unit
      );

      if(TrailingMode==STEP_DISTANCE)
      {
         step=MathMax(
            step,
            TrailingDistance*unit/4
         );
      }

      // NEVER WIDEN EXISTING STOP LOSS

      if(
         candidate<=0 ||
         (
            oldSL>0 &&
            (
               buy
               ? candidate-oldSL
               : oldSL-candidate
            )<step-1e-9
         )
      )
         continue;

      long freeze=SymbolInfoInteger(
         sym,SYMBOL_TRADE_FREEZE_LEVEL
      );

      if(
         oldSL>0 &&
         freeze>0 &&
         MathAbs(price-oldSL)<=freeze*pt
      )
         continue;

      if(
         tick.time_msc-tracks[j].lastModify
         <MinModifyIntervalMilliseconds
      )
         continue;

      tracks[j].lastModify=tick.time_msc;

      bool ok=trade.PositionModify(
         ticket,candidate,tp
      );

      TradeResult(
         ok,
         "SL",
         ticket,
         price,
         volume,
         candidate
      );

      if(
         ok &&
         trade.ResultRetcode()
         ==TRADE_RETCODE_DONE
      )
      {
         Event(
            "SL_CONFIRMED",
            ticket,
            price,
            volume,
            candidate,
            "Server confirmed"
         );

         displaySL=candidate;

         if(
            (buy && candidate>openPrice) ||
            (!buy && candidate<openPrice)
         )
            SetState(PROFIT_LOCK_ACTIVE);
      }
   }
}

//+------------------------------------------------------------------+
//| EMERGENCY POSITION CLOSURE                                       |
//+------------------------------------------------------------------+

void CloseOwn()
{
   if(
      !CanSend() ||
      !NettingIsolated() ||
      uncertain
   )
      return;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0 || !Own())
         continue;

      SetState(EXIT_PENDING);

      bool ok=trade.PositionClose(
         ticket,
         (ulong)MaxSlippagePoints
      );

      TradeResult(
         ok,"CLOSE",ticket,0,0,0
      );

      if(Ambiguous(trade.ResultRetcode()))
      {
         uncertain=true;
         Save("uncertain",1);
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| MARKET ORDER EXECUTION                                           |
//+------------------------------------------------------------------+

bool OpenPosition(
   int direction,
   bool recovery,
   MqlTick &tick
)
{
   if(
      !CanSend() ||
      !NettingIsolated() ||
      pending ||
      uncertain ||
      OwnOrders()>0 ||
      !historyOK
   )
      return false;

   long tradeMode=SymbolInfoInteger(
      sym,SYMBOL_TRADE_MODE
   );

   if(
      tradeMode==SYMBOL_TRADE_MODE_DISABLED ||
      tradeMode==SYMBOL_TRADE_MODE_CLOSEONLY ||
      (
         direction>0 &&
         tradeMode==SYMBOL_TRADE_MODE_SHORTONLY
      ) ||
      (
         direction<0 &&
         tradeMode==SYMBOL_TRADE_MODE_LONGONLY
      )
   )
      return false;

   double volume=recovery
      ? RecoveryLot
      : BaseLot;

   double price=direction>0
      ? tick.ask
      : tick.bid;

   double gap=StopGap(false);

   double sl=direction>0
      ? Down(
         MathMin(
            price-InitialStopLossPoints*unit,
            tick.bid-gap
         )
      )
      : Up(
         MathMax(
            price+InitialStopLossPoints*unit,
            tick.ask+gap
         )
      );

   double tp=0;

   if(EnableFixedTakeProfit)
   {
      tp=direction>0
         ? Up(
            MathMax(
               price+FixedTakeProfitPoints*unit,
               tick.ask+gap
            )
         )
         : Down(
            MathMin(
               price-FixedTakeProfitPoints*unit,
               tick.bid-gap
            )
         );
   }

   ENUM_ORDER_TYPE type=direction>0
      ? ORDER_TYPE_BUY
      : ORDER_TYPE_SELL;

   double equity=AccountInfoDouble(
      ACCOUNT_EQUITY
   );

   double loss=0;
   double margin=0;

   if(
      sl<=0 ||
      equity<=0 ||
      !OrderCalcProfit(
         type,sym,1.0,price,sl,loss
      ) ||
      loss>=0
   )
      return false;

   double riskOne=
      -loss+EstimatedRoundTripCostPerLot;

   if(AutoLotMode && !recovery)
   {
      volume=equity*
         RiskPerTradePercent/100/riskOne;
   }

   volume=Volume(volume);

   if(
      volume<=0 ||
      exposure+volume>MaxExposure+1e-9 ||
      riskOne*volume>
         equity*MaxSingleOrderRiskPercent/100
   )
   {
      statusReason="Lot/exposure/risk limit";

      return false;
   }

   if(
      !OrderCalcMargin(
         type,sym,volume,price,margin
      ) ||
      AccountInfoDouble(
         ACCOUNT_MARGIN_FREE
      )-margin<
         equity*MinimumFreeMarginPercent/100
   )
   {
      statusReason="Margin limit";

      return false;
   }

   MqlTradeRequest request={};
   MqlTradeCheckResult check={};

   request.action=TRADE_ACTION_DEAL;
   request.symbol=sym;
   request.magic=MagicNumber;
   request.volume=volume;
   request.type=type;
   request.price=price;
   request.sl=sl;
   request.tp=tp;
   request.deviation=(ulong)MaxSlippagePoints;

   request.comment=recovery
      ? "VX-R"
      : "VX-P";

   long filling=SymbolInfoInteger(
      sym,SYMBOL_FILLING_MODE
   );

   long execution=SymbolInfoInteger(
      sym,SYMBOL_TRADE_EXEMODE
   );

   request.type_filling=
      (filling&SYMBOL_FILLING_FOK)!=0
      ? ORDER_FILLING_FOK
      : (filling&SYMBOL_FILLING_IOC)!=0
      ? ORDER_FILLING_IOC
      : ORDER_FILLING_RETURN;

   if(
      execution==SYMBOL_TRADE_EXECUTION_MARKET &&
      request.type_filling==ORDER_FILLING_RETURN
   )
   {
      statusReason="Unsupported filling";
      return false;
   }

   if(
      !OrderCheck(request,check) ||
      (
         check.retcode!=0 &&
         check.retcode!=TRADE_RETCODE_DONE
      )
   )
   {
      Event(
         "CHECK_REJECT",
         0,
         price,
         volume,
         sl,
         check.comment
      );

      statusReason=check.comment;

      return false;
   }

   trade.SetTypeFilling(
      request.type_filling
   );

   pending=true;
   pendingSince=tick.time_msc;

   SetState(ENTRY_PENDING);

   Save("uncertain",1);

   bool ok=direction>0
      ? trade.Buy(
         volume,sym,price,sl,tp,
         request.comment
      )
      : trade.Sell(
         volume,sym,price,sl,tp,
         request.comment
      );

   uint retcode=trade.ResultRetcode();

   TradeResult(
      ok,
      recovery
         ? "RECOVERY_REQUEST"
         : "ENTRY_REQUEST",
      trade.ResultOrder(),
      price,
      volume,
      sl
   );

   if(Accepted(retcode))
   {
      if(recovery)
      {
         recoveryUsed=true;
         Save("rec",1);
      }

      lastSignalBar=(long)iTime(
         sym,SignalTimeframe,0
      );

      return true;
   }

   pending=false;

   if(Ambiguous(retcode))
   {
      uncertain=true;
      Save("uncertain",1);
   }
   else
   {
      Save("uncertain",0);
   }

   return false;
}

//+------------------------------------------------------------------+
//| MASTER TRADING ENGINE                                            |
//+------------------------------------------------------------------+

void Evaluate(MqlTick &tick)
{
   if(!SafeAccount())
   {
      SetState(RISK_LOCK,"Live disabled");
      return;
   }

   if(
      !Tester() &&
      !TerminalInfoInteger(
         TERMINAL_CONNECTED
      )
   )
   {
      SetState(DISCONNECTED);
      return;
   }

   Reconcile();

   if(!NettingIsolated())
   {
      SetState(
         RISK_LOCK,
         "Foreign/mixed netting position"
      );

      return;
   }

   RefreshRisk();

   if(emergency || riskLocked)
   {
      if(emergency || CloseOnRiskLock)
      {
         if(
            tick.time_msc-lastEntryTry>=500
         )
         {
            lastEntryTry=tick.time_msc;
            CloseOwn();
         }
      }
      else
      {
         ManageStops(tick);
      }

      SetState(
         emergency
            ? EMERGENCY_STOP
            : RISK_LOCK,
         "Latched; no automatic reset"
      );

      return;
   }

   if(pending)
   {
      SetState(RECONCILIATION);

      if(tick.time_msc-pendingSince>5000)
      {
         pending=false;
         uncertain=true;

         Save("uncertain",1);
      }
   }

   int direction=Signal(tick);

   if(active>0)
   {
      SetState(
         active>1
            ? RECOVERY_ACTIVE
            : POSITION_ACTIVE
      );

      ManageStops(tick);
   }

   if(
      pending ||
      uncertain ||
      !TradingEnabled ||
      !historyOK ||
      !CanSend() ||
      OwnOrders()>0
   )
   {
      if(uncertain)
      {
         SetState(
            RISK_LOCK,
            "Uncertain execution"
         );
      }

      return;
   }

   if(
      (tick.ask-tick.bid)/unit
      >MaxSpreadPoints
   )
   {
      statusReason="Spread limit";
      return;
   }

   if(!EnableIntrabarEntry)
   {
      long bar=(long)iTime(
         sym,SignalTimeframe,0
      );

      if(bar==lastEvaluatedBar)
         return;

      lastEvaluatedBar=bar;
   }

   if(direction==0)
   {
      if(active==0)
         SetState(SCANNING);

      return;
   }

   if(active==0)
      SetState(MOMENTUM_DETECTED);

   if(tick.time_msc-lastEntryTry<250)
      return;

   // PRIMARY SINGLE ENTRY

   if(active==0)
   {
      if(
         lastExit>0 &&
         !EnableRapidReentry &&
         (long)iTime(
            sym,SignalTimeframe,0
         )<=lastSignalBar
      )
         return;

      if(
         lastExit>0 &&
         tick.time_msc-lastExit
         <ReentryDelayMilliseconds
      )
         return;

      if(
         !AllowSameCandleReentry &&
         (long)iTime(
            sym,SignalTimeframe,0
         )==lastSignalBar
      )
         return;

      SetState(
         lastExit>0
            ? RE_ENTRY_SCANNING
            : SIGNAL_READY
      );

      lastEntryTry=tick.time_msc;

      OpenPosition(
         direction,false,tick
      );

      return;
   }

   // CONDITIONAL RECOVERY

   if(
      ExecutionMode!=CONDITIONAL_RECOVERY ||
      !EnableRecovery ||
      !hedging ||
      recoveryUsed ||
      active!=1 ||
      MaxRecoveryPositions!=1
   )
      return;

   SetState(RECOVERY_EVALUATION);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0 || !Own())
         continue;

      bool buy=
         PositionGetInteger(POSITION_TYPE)
         ==POSITION_TYPE_BUY;

      double openPrice=PositionGetDouble(
         POSITION_PRICE_OPEN
      );

      double adverse=
         (
            buy
            ? openPrice-tick.bid
            : tick.ask-openPrice
         )/unit;

      if(
         adverse>=RecoveryTriggerPoints &&
         direction==(buy ? 1 : -1)
      )
      {
         lastEntryTry=tick.time_msc;

         OpenPosition(
            direction,true,tick
         );
      }

      break;
   }
}

//+------------------------------------------------------------------+
//| ON TICK                                                          |
//+------------------------------------------------------------------+

void OnTick()
{
   MqlTick tick;

   if(
      !SymbolInfoTick(sym,tick) ||
      tick.bid<=0 ||
      tick.ask<tick.bid ||
      tick.time_msc<=0
   )
      return;

   if(used>0)
   {
      int j=(head+8191)%8192;

      double mid=
         (tick.bid+tick.ask)*0.5;

      if(tick.time_msc<ring[j].ms)
         return;

      if(
         MathAbs(mid-ring[j].mid)/unit
         >MaxAbnormalJumpPoints
      )
      {
         used=0;
         head=0;

         AddTick(tick);

         Event(
            "JUMP",
            0,
            mid,
            0,
            0,
            "Signal buffer reset"
         );

         ManageStops(tick);

         return;
      }
   }

   lastTick=tick.time_msc;

   AddTick(tick);

   Evaluate(tick);
}

//+------------------------------------------------------------------+
//| TRADE TRANSACTION RECONCILIATION                                 |
//+------------------------------------------------------------------+

void OnTradeTransaction(
   const MqlTradeTransaction &trans,
   const MqlTradeRequest &request,
   const MqlTradeResult &result
)
{
   if(
      trans.type!=TRADE_TRANSACTION_DEAL_ADD ||
      trans.deal==0 ||
      !HistoryDealSelect(trans.deal)
   )
      return;

   if(
      HistoryDealGetString(
         trans.deal,DEAL_SYMBOL
      )!=sym ||
      (ulong)HistoryDealGetInteger(
         trans.deal,DEAL_MAGIC
      )!=MagicNumber
   )
      return;

   long entry=HistoryDealGetInteger(
      trans.deal,DEAL_ENTRY
   );

   double price=HistoryDealGetDouble(
      trans.deal,DEAL_PRICE
   );

   double volume=HistoryDealGetDouble(
      trans.deal,DEAL_VOLUME
   );

   Event(
      entry==DEAL_ENTRY_IN
         ? "FILL_ENTRY"
         : "FILL_EXIT",
      trans.position,
      price,
      volume,
      0,
      IntegerToString(
         HistoryDealGetInteger(
            trans.deal,DEAL_REASON
         )
      )
   );

   if(
      DashboardEnabled &&
      !MQLInfoInteger(MQL_OPTIMIZATION)
   )
   {
      string arrow=prefix+"D"+
         IntegerToString((long)trans.deal);

      datetime ts=(datetime)
         HistoryDealGetInteger(
            trans.deal,DEAL_TIME
         );

      ObjectCreate(
         0,arrow,OBJ_ARROW,0,ts,price
      );

      ObjectSetInteger(
         0,arrow,OBJPROP_ARROWCODE,
         entry==DEAL_ENTRY_IN ? 233 : 234
      );

      ObjectSetInteger(
         0,arrow,OBJPROP_COLOR,
         entry==DEAL_ENTRY_IN
            ? clrDodgerBlue
            : clrTomato
      );
   }

   historyDirty=true;

   if(entry==DEAL_ENTRY_IN && pending)
   {
      pending=false;
      Save("uncertain",0);
   }

   if(
      entry==DEAL_ENTRY_OUT ||
      entry==DEAL_ENTRY_OUT_BY
   )
   {
      lastExit=NowMs();
      Save("exit",(double)lastExit);
   }
}

//+------------------------------------------------------------------+
//| PROFESSIONAL DASHBOARD                                           |
//+------------------------------------------------------------------+

void Label(
   string name,
   string text,
   int y,
   color c
)
{
   string object=prefix+name;

   if(ObjectFind(0,object)<0)
      ObjectCreate(
         0,object,OBJ_LABEL,0,0,0
      );

   ObjectSetInteger(
      0,object,OBJPROP_CORNER,
      CORNER_LEFT_UPPER
   );

   ObjectSetInteger(
      0,object,OBJPROP_XDISTANCE,18
   );

   ObjectSetInteger(
      0,object,OBJPROP_YDISTANCE,y
   );

   ObjectSetInteger(
      0,object,OBJPROP_COLOR,c
   );

   ObjectSetInteger(
      0,object,OBJPROP_FONTSIZE,10
   );

   ObjectSetString(
      0,object,OBJPROP_FONT,"Consolas"
   );

   ObjectSetString(
      0,object,OBJPROP_TEXT,text
   );
}

void Dashboard()
{
   if(
      !DashboardEnabled ||
      MQLInfoInteger(MQL_OPTIMIZATION)
   )
      return;

   string panel=prefix+"panel";

   if(ObjectFind(0,panel)<0)
   {
      ObjectCreate(
         0,panel,OBJ_RECTANGLE_LABEL,0,0,0
      );

      ObjectSetInteger(
         0,panel,OBJPROP_XDISTANCE,8
      );

      ObjectSetInteger(
         0,panel,OBJPROP_YDISTANCE,18
      );

      ObjectSetInteger(
         0,panel,OBJPROP_XSIZE,395
      );

      ObjectSetInteger(
         0,panel,OBJPROP_YSIZE,250
      );

      ObjectSetInteger(
         0,panel,OBJPROP_BGCOLOR,clrBlack
      );

      ObjectSetInteger(
         0,panel,OBJPROP_COLOR,clrDimGray
      );

      ObjectSetInteger(
         0,panel,OBJPROP_SELECTABLE,false
      );
   }

   MqlTick tick;

   ZeroMemory(tick);

   SymbolInfoTick(sym,tick);

   double equity=AccountInfoDouble(
      ACCOUNT_EQUITY
   );

   Label(
      "title",
      "VULCARES VX / RECONSTRUCTION 1.00",
      25,clrOrange
   );

   Label(
      "s",
      EnumToString(state)+" | "+sym,
      45,clrWhite
   );

   Label(
      "r",
      regime+" | "+modeText,
      62,clrSilver
   );

   Label(
      "m",
      StringFormat(
         "BUY %.2f SELL %.2f Velocity %.1f",
         buyConf,sellConf,velocity
      ),
      79,clrWhite
   );

   Label(
      "p",
      StringFormat(
         "Positions %d Lots %.3f Float %.2f",
         active,exposure,floating
      ),
      96,clrWhite
   );

   Label(
      "sl",
      StringFormat(
         "SL %s Extreme %s",
         DoubleToString(displaySL,digits),
         DoubleToString(displayExtreme,digits)
      ),
      113,clrWhite
   );

   Label(
      "l",
      StringFormat(
         "SL est. P/L %.2f Spread %.1f",
         locked,
         (tick.ask-tick.bid)/unit
      ),
      130,clrWhite
   );

   Label(
      "d",
      StringFormat(
         "Daily %.2f Drawdown %.2f%%",
         dailyNet,
         dayEquity>0
            ? 100*MathMax(
               0.0,dayEquity-equity
            )/dayEquity
            : 0
      ),
      147,clrWhite
   );

   Label(
      "w",
      StringFormat(
         "Trades %d WR %.1f%% PF %s",
         trades,
         trades>0
            ? 100.0*wins/trades
            : 0,
         grossLoss>0
            ? DoubleToString(
               grossWin/grossLoss,2
            )
            : "N/A"
      ),
      164,clrWhite
   );

   Label(
      "msg",
      StringSubstr(statusReason,0,48),
      181,clrSilver
   );

   string button=prefix+"stop";

   if(ObjectFind(0,button)<0)
      ObjectCreate(
         0,button,OBJ_BUTTON,0,0,0
      );

   ObjectSetInteger(
      0,button,OBJPROP_XDISTANCE,18
   );

   ObjectSetInteger(
      0,button,OBJPROP_YDISTANCE,208
   );

   ObjectSetInteger(
      0,button,OBJPROP_XSIZE,230
   );

   ObjectSetInteger(
      0,button,OBJPROP_YSIZE,35
   );

   ObjectSetInteger(
      0,button,OBJPROP_BGCOLOR,clrMaroon
   );

   ObjectSetInteger(
      0,button,OBJPROP_COLOR,clrWhite
   );

   ObjectSetString(
      0,button,OBJPROP_TEXT,
      emergency
         ? "STOP LATCHED"
         : "EMERGENCY STOP"
   );

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| TIMER                                                            |
//+------------------------------------------------------------------+

void OnTimer()
{
   Reconcile();

   RefreshRisk();

   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);

      if(StringFind(name,prefix+"SL")==0)
      {
         ulong ticket=(ulong)StringToInteger(
            StringSubstr(
               name,StringLen(prefix)+2
            )
         );

         if(!PositionSelectByTicket(ticket))
            ObjectDelete(0,name);
      }
   }

   if(
      (
         emergency ||
         (riskLocked && CloseOnRiskLock)
      ) &&
      CanSend()
   )
      CloseOwn();

   Dashboard();
}

//+------------------------------------------------------------------+
//| CHART EVENTS                                                     |
//+------------------------------------------------------------------+

void OnChartEvent(
   const int id,
   const long &lp,
   const double &dp,
   const string &sp
)
{
   if(
      id==CHARTEVENT_OBJECT_CLICK &&
      sp==prefix+"stop"
   )
   {
      emergency=true;

      Save("emergency",1);

      SetState(EMERGENCY_STOP);

      CloseOwn();

      Dashboard();
   }
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                   |
//+------------------------------------------------------------------+

int OnInit()
{
   sym=TradingSymbol==""
      ? _Symbol
      : TradingSymbol;

   if(sym!=_Symbol)
   {
      Print(
         "Attach EA to the exact TradingSymbol chart."
      );

      return INIT_PARAMETERS_INCORRECT;
   }

   if(!SafeAccount())
   {
      Print(
         "Vulcares Vx blocks live accounts."
      );

      return INIT_FAILED;
   }

   pt=SymbolInfoDouble(
      sym,SYMBOL_POINT
   );

   ticksize=SymbolInfoDouble(
      sym,SYMBOL_TRADE_TICK_SIZE
   );

   digits=(int)SymbolInfoInteger(
      sym,SYMBOL_DIGITS
   );

   vmin=SymbolInfoDouble(
      sym,SYMBOL_VOLUME_MIN
   );

   vmax=SymbolInfoDouble(
      sym,SYMBOL_VOLUME_MAX
   );

   vstep=SymbolInfoDouble(
      sym,SYMBOL_VOLUME_STEP
   );

   unit=ReferencePoint>0
      ? ReferencePoint
      : pt;

   if(
      pt<=0 ||
      ticksize<=0 ||
      vstep<=0 ||
      unit<=0 ||
      MomentumWindow<100 ||
      MomentumWindow>60000 ||
      MomentumThreshold<=0 ||
      MinimumPriceChanges<1 ||
      InitialStopLossPoints<=0 ||
      TrailingDistance<=0 ||
      TrailingStep<=0 ||
      BaseLot<=0 ||
      MaxPrimaryPositions!=1 ||
      MaxRecoveryPositions<0 ||
      MaxRecoveryPositions>1 ||
      MaxDailyLossPercent<=0 ||
      MaxEquityDrawdownPercent<=0 ||
      MaxSingleOrderRiskPercent<=0 ||
      MaximumConsecutiveLosses<1 ||
      MinimumFreeMarginPercent<0 ||
      MaxExposure<=0 ||
      ProfitLockFraction<=0 ||
      ProfitLockFraction>=1 ||
      MaxSpreadPoints<=0 ||
      EntryConfidenceThreshold<0 ||
      EntryConfidenceThreshold>1 ||
      BreakoutSensitivity<0 ||
      BreakoutSensitivity>1 ||
      PullbackSensitivity<0 ||
      PullbackSensitivity>1 ||
      ATRPeriod<1 ||
      ReentryDelayMilliseconds<0 ||
      MinModifyIntervalMilliseconds<0 ||
      MaxSlippagePoints<0
   )
      return INIT_PARAMETERS_INCORRECT;

   hedging=
      AccountInfoInteger(ACCOUNT_MARGIN_MODE)
      ==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;

   prefix="VX_"+
      IntegerToString((long)MagicNumber)
      +"_";

   key="VX."+
      IntegerToString(
         AccountInfoInteger(ACCOUNT_LOGIN)
      )+"."+
      IntegerToString((long)MagicNumber)
      +"."+sym+".";

   if(StringLen(key)>40)
   {
      Print(
         "Symbol/magic persistence key too long"
      );

      return INIT_PARAMETERS_INCORRECT;
   }

   trade.SetExpertMagicNumber(MagicNumber);

   trade.SetDeviationInPoints(
      (ulong)MaxSlippagePoints
   );

   trade.SetAsyncMode(false);

   trade.SetTypeFillingBySymbol(sym);

   double equity=AccountInfoDouble(
      ACCOUNT_EQUITY
   );

   dayCode=(int)Load(
      "day",Day(TimeCurrent())
   );

   dayEquity=Load("dayeq",equity);

   peakEquity=Load("peak",equity);

   lastExit=(long)Load("exit",0);

   riskLocked=Load("risk",0)>0;

   emergency=Load("emergency",0)>0;

   uncertain=Load("uncertain",0)>0;

   recoveryUsed=Load("rec",0)>0;

   Save("day",dayCode);
   Save("dayeq",dayEquity);
   Save("peak",peakEquity);

   atrHandle=iATR(
      sym,SignalTimeframe,ATRPeriod
   );

   if(
      TrailingMode==ATR_DISTANCE &&
      atrHandle==INVALID_HANDLE
   )
      return INIT_FAILED;

   modeText=
      ExecutionMode==CONDITIONAL_RECOVERY &&
      EnableRecovery &&
      hedging
      ? "RECOVERY TEST"
      : "SINGLE";

   if(
      ExportEvents &&
      !MQLInfoInteger(MQL_OPTIMIZATION)
   )
   {
      string filename=
         "VX_"+sym+"_"+
         IntegerToString((long)MagicNumber)
         +"_"+
         IntegerToString((long)TimeLocal())
         +".csv";

      logfile=FileOpen(
         filename,
         FILE_WRITE|FILE_CSV|FILE_ANSI,
         ','
      );

      if(logfile!=INVALID_HANDLE)
      {
         FileWrite(
            logfile,
            "time_msc",
            "event",
            "ticket",
            "price",
            "lot",
            "sl",
            "detail"
         );
      }
   }

   MqlTick tick;

   if(
      SymbolInfoTick(sym,tick) &&
      !Tester()
   )
   {
      MqlTick seed[];

      ulong end=(ulong)tick.time_msc;

      ulong start=end>60000
         ? end-60000
         : 0;

      int n=CopyTicksRange(
         sym,
         seed,
         COPY_TICKS_INFO,
         start,
         end
      );

      if(n>0)
      {
         for(
            int i=(int)MathMax(0,n-8192);
            i<n;
            i++
         )
         {
            if(
               seed[i].bid>0 &&
               seed[i].ask>=seed[i].bid
            )
               AddTick(seed[i]);
         }
      }
   }

   Reconcile();

   if(active==0 && !uncertain)
   {
      recoveryUsed=false;
      Save("rec",0);
   }

   RefreshRisk();

   EventSetTimer(1);

   SetState(SCANNING);

   Dashboard();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                 |
//+------------------------------------------------------------------+

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(atrHandle!=INVALID_HANDLE)
      IndicatorRelease(atrHandle);

   if(logfile!=INVALID_HANDLE)
      FileClose(logfile);

   if(StringLen(prefix)>0)
      ObjectsDeleteAll(0,prefix);
}

//+------------------------------------------------------------------+
//| END OF VULCARES VX V1.00                                         |
//+------------------------------------------------------------------+
