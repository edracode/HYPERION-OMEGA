#property strict
#property version "1.05"
#property description "Quantum Trading Engine | Strategy Tester risk-limited research build"

#include <Trade/Trade.mqh>

enum QTERiskMode { AGGRESSIVE, SUPER_AGGRESSIVE, ADAPTIVE_AGGRESSIVE };
input group "Risk and account"
input QTERiskMode RiskMode=ADAPTIVE_AGGRESSIVE;
input double RiskPerTradeAggressive=0.5;
input double RiskPerTradeSuperAggressive=1.0;
input double MaxDailyRiskPercent=3.0;
input double MaxPortfolioDrawdownPercent=10.0;
input double RiskRewardRatio=2.0;
input double TargetWinRate=60.0;
input int MinimumValidationTrades=1000;
input long StrategySearchCapacity=1000000;
input double ReferenceAccountEquity=1000.0;
input double ReferenceDailyRiskAmount=30.0;
input double ReferenceTradeRiskAggressive=5.0;
input double ReferenceTradeRiskSuperAggressive=10.0;
input bool EnableCompoundRisk=true;
input bool AllowDemoTrading=false;
input bool AllowLiveTrading=false;
input bool StartOnLoad=false;
input bool AutoStartTester=true;
input bool EnableDailyRiskLock=true;
input bool EnableEmergencyStop=true;
input bool EnableMartingale=false;
input bool EnableUnlimitedAveraging=false;
input double MinimumMarginLevel=250.0;
input double MaxCurrencyClusterPercent=10.0;
input double CommissionRoundTurnPerLot=0.0;
input double MaxFeesAtStopPerLot=0.0;
input bool ConfirmCostInputs=false;
input bool AllowUnconfirmedCostsInTester=true;
input double StopSlippageTicks=3.0;
input double EntrySlippageTicks=2.0;
input ulong Magic=761921;
input group "Market and strategies"
input string Symbols="AUTO";
input ENUM_TIMEFRAMES SignalTimeframe=PERIOD_M1;
input ENUM_TIMEFRAMES ContextTimeframe=PERIOD_M5;
input bool EnableMultiSymbol=true;
input bool EnableMultiStrategy=true;
input bool EnableIntrabarExecution=true;
input bool EnableTickBackfill=false;
input bool EnableRapidReentry=true;
input bool EnableAI=true;
input bool EnableAdaptiveStrategies=true;
input bool EnableCorrelationFilter=true;
input bool StrictRiskRewardMode=true;
input bool EnableBreakEven=false;
input bool EnableTrailing=false;
input int MaximumHoldSeconds=180;
input int MinimumReentrySeconds=10;
input int MaximumPositionsPerSymbol=1;
input int PollMilliseconds=100;
input int MaximumQuoteAgeSeconds=3;
input double MaxSpreadToATR=0.18;
input double MinimumSignalScore=64.0;
input int StrategyMask=63;
input int FastEMA=9;
input int SlowEMA=26;
input int BreakoutLookback=16;
input double ATRStopMultiple=1.25;
input bool WriteExecutionLog=true;

CTrade trade;
QTERiskMode activeMode;
bool running=false, emergency=false, dailyLock=false, tester=false, storageOK=true;
bool foreignExposure=false, exposureOK=false, finishFlatten=false;
datetime sessionDay=0;
bool portfolioLocked=false;
double equityPeak=0.0, portfolioRoom=0.0;
double startEquity=0, dayLimit=0, dailyLoss=0, dailyNet=0, floatingLoss=0;
double riskToStop=0, remaining=0, drawdown=0, maxDrawdown=0;
int lease=INVALID_HANDLE, ledger=INVALID_HANDLE;
ulong latencyBuffer[512];
int latencyCount=0, latencyNext=0;
ulong lastPanel=0, nextFlatten=0;
string statusText="Paused";

enum EntryGate
{
   GATE_QUOTES, GATE_WARMUP, GATE_EVALUATED, GATE_NO_SIGNAL, GATE_LOW_SCORE,
   GATE_PAUSED, GATE_FEES, GATE_PERMISSIONS, GATE_ACCOUNT_RISK,
   GATE_SPREAD, GATE_STALE, GATE_SESSION, GATE_COOLDOWN, GATE_CONFLICT,
   GATE_POSITION_SLOT, GATE_SYMBOL_RULES, GATE_MIN_LOT, GATE_STOP_TARGET,
   GATE_MARGIN, GATE_CHECK_REJECT, GATE_SENT, GATE_FILLED, GATE_SEND_REJECT,
   GATE_COUNT
};

ulong gateCounts[GATE_COUNT];
uint lastCheckCode=0,lastSendCode=0;
datetime nextTesterProgress=0;

bool RejectGate(const EntryGate gate)
{
   gateCounts[gate]++;
   return false;
}


struct Market
{
   string symbol;
   int fastHandle, slowHandle, atrHandle, rsiHandle, adxHandle, contextFast, contextSlow;
   datetime barTime;
   long quoteTime;
   double lastBid,lastAsk,atr,fast,slow,rsi,adx,higherFast,higherSlow;
   double high,low,mean,deviation,pivot,previousClose;
   double impulse[16];
   int head,count;
   string regime;
   double regimeScore, score, spread;
};

struct Signal
{
   int strategy;
   int direction;
   double score;
   double stopDistance;
};

Market markets[];

string Upper(string value)
{
   StringToUpper(value);
   return value;
}

string ResolveSymbol(string name)
{
   StringTrimLeft(name);
   StringTrimRight(name);
   if(name=="")
      return "";

   bool custom=false;
   if(SymbolExist(name,custom))
      return name;

   const string wanted=Upper(name);
   const int total=SymbolsTotal(false);
   string alias="";
   int matches=0;
   bool chartMatches=false;
   for(int i=0;i<total;i++)
   {
      const string candidate=SymbolName(i,false);
      const string upper=Upper(candidate);
      if(upper==wanted)
         return candidate;
      if(StringFind(upper,wanted)<0)
         continue;
      alias=candidate;
      matches++;
      if(candidate==_Symbol)
         chartMatches=true;
   }

   if(chartMatches)
      return _Symbol;
   if(matches==1)
      return alias;
   if(matches>1)
      Print("QTE: ambiguous alias ",name,"; use the exact broker symbol.");
   return "";
}

void ReleaseMarketIndicators(Market &market)
{
   if(market.fastHandle!=INVALID_HANDLE) IndicatorRelease(market.fastHandle);
   if(market.slowHandle!=INVALID_HANDLE) IndicatorRelease(market.slowHandle);
   if(market.atrHandle!=INVALID_HANDLE) IndicatorRelease(market.atrHandle);
   if(market.rsiHandle!=INVALID_HANDLE) IndicatorRelease(market.rsiHandle);
   if(market.adxHandle!=INVALID_HANDLE) IndicatorRelease(market.adxHandle);
   if(market.contextFast!=INVALID_HANDLE) IndicatorRelease(market.contextFast);
   if(market.contextSlow!=INVALID_HANDLE) IndicatorRelease(market.contextSlow);
   market.fastHandle=INVALID_HANDLE;
   market.slowHandle=INVALID_HANDLE;
   market.atrHandle=INVALID_HANDLE;
   market.rsiHandle=INVALID_HANDLE;
   market.adxHandle=INVALID_HANDLE;
   market.contextFast=INVALID_HANDLE;
   market.contextSlow=INVALID_HANDLE;
}

bool PrepareMarketIndicators(Market &market)
{
   if(market.fastHandle!=INVALID_HANDLE)
      return true;

   const string s=market.symbol;
   market.fastHandle=iMA(s,SignalTimeframe,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   market.slowHandle=iMA(s,SignalTimeframe,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   market.atrHandle=iATR(s,SignalTimeframe,14);
   market.rsiHandle=iRSI(s,SignalTimeframe,14,PRICE_CLOSE);
   market.adxHandle=iADX(s,SignalTimeframe,14);
   market.contextFast=iMA(s,ContextTimeframe,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   market.contextSlow=iMA(s,ContextTimeframe,SlowEMA,0,MODE_EMA,PRICE_CLOSE);

   if(market.fastHandle!=INVALID_HANDLE && market.slowHandle!=INVALID_HANDLE &&
      market.atrHandle!=INVALID_HANDLE && market.rsiHandle!=INVALID_HANDLE &&
      market.adxHandle!=INVALID_HANDLE && market.contextFast!=INVALID_HANDLE &&
      market.contextSlow!=INVALID_HANDLE)
      return true;

   ReleaseMarketIndicators(market);
   return false;
}

void AddMarket(const string symbol)
{
   if(symbol=="")
      return;

   const int count=ArraySize(markets);
   for(int i=0;i<count;i++)
      if(markets[i].symbol==symbol)
         return;

   if(symbol!=_Symbol && !SymbolSelect(symbol,true))
   {
      Print("QTE: could not select ",symbol);
      return;
   }

   // The chart/tester symbol is already bound by MT5. Entry checks
   // in MakePlan still enforce its current trading mode.
   long mode=0;
   if(symbol!=_Symbol &&
      (!SymbolInfoInteger(symbol,SYMBOL_TRADE_MODE,mode) ||
       mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY))
      return;

   if(ArrayResize(markets,count+1,128)!=count+1)
   {
      Print("QTE: could not allocate market state for ",symbol);
      return;
   }

   markets[count].symbol=symbol;
   markets[count].fastHandle=INVALID_HANDLE;
   markets[count].slowHandle=INVALID_HANDLE;
   markets[count].atrHandle=INVALID_HANDLE;
   markets[count].rsiHandle=INVALID_HANDLE;
   markets[count].adxHandle=INVALID_HANDLE;
   markets[count].contextFast=INVALID_HANDLE;
   markets[count].contextSlow=INVALID_HANDLE;
}

bool LoadMarkets()
{
   string source=Symbols;
   StringTrimLeft(source);
   StringTrimRight(source);
   const string mode=Upper(source);
   const bool autoMode=mode=="" || mode=="AUTO";

   if(!EnableMultiSymbol || (autoMode && tester))
      AddMarket(_Symbol);
   else if(autoMode || mode=="MARKET_WATCH" || mode=="*")
   {
      const bool selectedOnly=mode!="*";
      const int total=SymbolsTotal(selectedOnly);
      for(int i=0;i<total;i++)
      {
         const string name=SymbolName(i,selectedOnly);
         bool custom=false;
         if(!selectedOnly && (!SymbolExist(name,custom) || custom))
            continue;
         AddMarket(name);
      }
      AddMarket(_Symbol);
   }
   else
   {
      string names[];
      const int total=StringSplit(source,',',names);
      for(int i=0;i<total;i++)
      {
         const string symbol=ResolveSymbol(names[i]);
         if(symbol=="")
         {
            Print("QTE: skipped unknown or ambiguous symbol ",names[i]);
            continue;
         }
         AddMarket(symbol);
      }
      if(ArraySize(markets)==0)
         AddMarket(_Symbol);
   }

   const int loaded=ArraySize(markets);
   Print("QTE: ",loaded," symbol(s) registered. Chart: ",_Symbol);
   return loaded>0;
}

void ReleaseMarkets()
{
   for(int i=0;i<ArraySize(markets);i++)
      ReleaseMarketIndicators(markets[i]);
}

bool ReadFeature(const int handle,double &value)
{
   double buffer[1];
   if(CopyBuffer(handle,0,1,1,buffer)!=1 || buffer[0]==EMPTY_VALUE ||
      !MathIsValidNumber(buffer[0]))
      return false;
   value=buffer[0];
   return true;
}

bool RefreshFeatures(Market &market,const datetime currentBar)
{
   if(market.barTime==currentBar)
      return true;
   if(!PrepareMarketIndicators(market))
      return false;
   if(!ReadFeature(market.fastHandle,market.fast) || !ReadFeature(market.slowHandle,market.slow) ||
      !ReadFeature(market.atrHandle,market.atr) || market.atr<=0 ||
      !ReadFeature(market.rsiHandle,market.rsi) || !ReadFeature(market.adxHandle,market.adx) ||
      !ReadFeature(market.contextFast,market.higherFast) ||
      !ReadFeature(market.contextSlow,market.higherSlow))
      return false;

   MqlRates bars[];
   ArraySetAsSeries(bars,true);
   if(CopyRates(market.symbol,SignalTimeframe,1,BreakoutLookback,bars)!=BreakoutLookback)
      return false;
   market.high=bars[0].high;
   market.low=bars[0].low;
   market.previousClose=bars[0].close;
   market.pivot=(bars[0].high+bars[0].low+bars[0].close)/3.0;
   double average=0,m2=0;
   for(int i=0;i<BreakoutLookback;i++)
   {
      market.high=MathMax(market.high,bars[i].high);
      market.low=MathMin(market.low,bars[i].low);
      const double delta=bars[i].close-average;
      average+=delta/(i+1);
      m2+=delta*(bars[i].close-average);
   }
   market.mean=average;
   market.deviation=MathSqrt(MathMax(0,m2/BreakoutLookback));
   market.barTime=currentBar;
   return true;
}

double TickImpulse(const Market &market)
{
   double total=0;
   for(int i=0;i<market.count;i++)
      total+=market.impulse[i];
   return market.atr>0 ? total/market.atr : 0;
}

void Offer(Signal &signals[],const int strategy,const int direction,const double base,
           const double strength,const double stop,const bool regimeMatch)
{
   if((StrategyMask & (1 << (strategy-1)))==0)
      return;
   const int n=ArraySize(signals);
   ArrayResize(signals,n+1);
   signals[n].strategy=strategy;
   signals[n].direction=direction;
   const double adjustment=EnableAdaptiveStrategies ? (regimeMatch ? 5.0 : -10.0) : 0;
   signals[n].score=MathMin(100.0,base+adjustment+MathMin(15.0,MathAbs(strength)*12.0));
   signals[n].stopDistance=stop;
}

void Evaluate(Market &m,const double price,const double prev,Signal &signals[])
{
   const double trend=(m.fast-m.slow)/m.atr;
   const double confirmation=m.higherFast-m.higherSlow;
   const double velocity=TickImpulse(m);
   const bool trending=m.adx>=23 && MathAbs(trend)>=0.18;
   const bool range=m.adx<23;
   const bool extreme=MathAbs(price-m.previousClose)>2.7*m.atr;
   m.regime=extreme ? "Volatility expansion" :
            (trending ? (trend>0 ? "Bull trend" : "Bear trend") : (range ? "Range" : "Mixed"));
   m.regimeScore=MathMin(100.0,extreme ? MathAbs(price-m.previousClose)/m.atr*25 : m.adx*2);
   if(extreme && EnableAdaptiveStrategies)
      return;
   const double stop=ATRStopMultiple*m.atr;

   if(trend>0.16 && confirmation>0 && prev<=m.fast && price>m.fast && m.rsi>48)
      Offer(signals,1,1,65,trend,stop,trending);
   if(trend<-0.16 && confirmation<0 && prev>=m.fast && price<m.fast && m.rsi<52)
      Offer(signals,1,-1,65,trend,stop,trending);

   if(prev<=m.high && price>m.high && m.rsi>52)
      Offer(signals,2,1,67,trend,stop,!range);
   if(prev>=m.low && price<m.low && m.rsi<48)
      Offer(signals,2,-1,67,trend,stop,!range);

   if(m.deviation>0 && range)
   {
      const double lower=m.mean-1.65*m.deviation;
      const double upper=m.mean+1.65*m.deviation;
      if(prev<=lower && price>lower && m.rsi<46)
         Offer(signals,3,1,65,(m.mean-price)/m.deviation,stop,true);
      if(prev>=upper && price<upper && m.rsi>54)
         Offer(signals,3,-1,65,(price-m.mean)/m.deviation,stop,true);
   }

   if(m.count>=8 && velocity>0.28 && price>m.pivot && price>prev && m.rsi>52)
      Offer(signals,4,1,62,velocity,stop,trending);
   if(m.count>=8 && velocity<-0.28 && price<m.pivot && price<prev && m.rsi<48)
      Offer(signals,4,-1,62,velocity,stop,trending);

   if(prev<m.low && price>=m.low)
      Offer(signals,5,1,64,(m.low-prev)/m.atr,MathMax(stop,price-prev),range);
   if(prev>m.high && price<=m.high)
      Offer(signals,5,-1,64,(prev-m.high)/m.atr,MathMax(stop,prev-price),range);

   if(m.high-m.low<4.5*m.atr && confirmation>0 && prev<=m.pivot && price>m.pivot && velocity>0.12)
      Offer(signals,6,1,66,velocity,stop,!extreme);
   if(m.high-m.low<4.5*m.atr && confirmation<0 && prev>=m.pivot && price<m.pivot && velocity<-0.12)
      Offer(signals,6,-1,66,velocity,stop,!extreme);
}



double AvailableRisk(const double limit,const double realizedLoss,const double markedLoss,
                     const double stopExposure)
{
   return MathMax(0.0,limit-realizedLoss-MathMax(markedLoss,stopExposure));
}

double StopExposure(const double markedProfit,const double projectedProfit)
{
   return MathMax(0.0,-markedProfit)+MathMax(0.0,MathMin(0.0,markedProfit)-projectedProfit);
}

bool SizeDown(const double minVolume,const double maxVolume,const double step,
              const double cashLimit,const double lossPerLot,double &lots)
{
   lots=0;
   if(minVolume<=0 || maxVolume<minVolume || step<=0 || lossPerLot<=0 || cashLimit<=0)
      return false;
   const double cap=MathMin(maxVolume,cashLimit/lossPerLot);
   if(cap+1e-12<minVolume)
      return false;
   lots=NormalizeDouble(minVolume+MathFloor((cap-minVolume)/step+1e-10)*step,8);
   return lots>=minVolume && lots<=maxVolume && lots*lossPerLot<=cashLimit+1e-7;
}


datetime historyDay=0;
ulong lastHistoryRead=0;
double cashFlow=0, testerOpeningFunding=0;
datetime testerFundingDay=0;
bool historyValid=false;

bool AllowedAccount()
{
   return (bool)MQLInfoInteger(MQL_TESTER);
}

bool EntryCostsReady()
{
   return ConfirmCostInputs || (tester && AllowUnconfirmedCostsInTester);
}

bool InputsValid()
{
   return !AllowLiveTrading && !AllowDemoTrading && !EnableMartingale && !EnableUnlimitedAveraging &&
          EnableDailyRiskLock && EnableEmergencyStop && RiskRewardRatio>=2 &&
          RiskPerTradeAggressive>0 && RiskPerTradeAggressive<=0.5 &&
          RiskPerTradeSuperAggressive>0 && RiskPerTradeSuperAggressive<=1.0 &&
          MaxDailyRiskPercent>0 && MaxDailyRiskPercent<=3.0 &&
          MaxPortfolioDrawdownPercent>0 && MaxPortfolioDrawdownPercent<=10.0 &&
          MaxCurrencyClusterPercent>0 && MaxCurrencyClusterPercent<=20 &&
          TargetWinRate>=60 && TargetWinRate<=100 && MinimumValidationTrades>=1 &&
          StrategySearchCapacity>=1 && Magic>0 && ReferenceAccountEquity>0 &&
          MinimumMarginLevel>=100 && CommissionRoundTurnPerLot>=0 &&
          MaxFeesAtStopPerLot>=0 && StopSlippageTicks>=0 && EntrySlippageTicks>=0 &&
          FastEMA>=2 && SlowEMA>FastEMA && BreakoutLookback>=4 && BreakoutLookback<=512 &&
          PollMilliseconds>=25 && MaximumQuoteAgeSeconds>=1 && MaximumPositionsPerSymbol>=1 &&
          MinimumReentrySeconds>=0 && MaximumHoldSeconds>=1 && ATRStopMultiple>0 &&
          MaxSpreadToATR>0 && MinimumSignalScore>=0 && MinimumSignalScore<=100 &&
          StrategyMask>0 && StrategyMask<=63;
}

uint ServerKey(const string server)
{
   uint hash=5381;
   for(int i=0;i<StringLen(server);i++)
      hash=hash*33+(uint)StringGetCharacter(server,i);
   return hash;
}

bool SaveState()
{
   if(tester)
      return true;
   if(!storageOK || !FileSeek(lease,0,SEEK_SET))
   {
      storageOK=false;
      return false;
   }
   const bool written=FileWriteDouble(lease,1.0)==8 &&
                      FileWriteDouble(lease,(double)sessionDay)==8 &&
                      FileWriteDouble(lease,startEquity)==8 &&
                      FileWriteDouble(lease,dailyLock ? 1.0 : 0.0)==8 &&
                      FileWriteDouble(lease,emergency ? 1.0 : 0.0)==8;
   FileFlush(lease);
   storageOK=written && FileSize(lease)==40;
   return storageOK;
}

bool OpenState()
{
   if(tester)
      return true;
   const string filename="QTE_state_"+(string)ServerKey(AccountInfoString(ACCOUNT_SERVER))+
                         "_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+".bin";
   lease=FileOpen(filename,FILE_COMMON|FILE_BIN|FILE_READ|FILE_WRITE);
   if(lease==INVALID_HANDLE)
   {
      Print("QTE: account state unavailable or another instance has the account lease.");
      return false;
   }
   if(FileSize(lease)==0)
      return SaveState();
   if(FileSize(lease)!=40 || FileReadDouble(lease)!=1.0)
      return false;
   const double storedDay=FileReadDouble(lease);
   startEquity=FileReadDouble(lease);
   const double lockedFlag=FileReadDouble(lease);
   const double emergencyFlag=FileReadDouble(lease);
   if(!MathIsValidNumber(storedDay) || storedDay<0 || !MathIsValidNumber(startEquity) ||
      startEquity<0 || (lockedFlag!=0 && lockedFlag!=1) || (emergencyFlag!=0 && emergencyFlag!=1))
      return false;
   sessionDay=(datetime)storedDay;
   dailyLock=lockedFlag==1;
   emergency=emergencyFlag==1;
   return true;
}

datetime BrokerDay(const datetime now)
{
   MqlDateTime fields;
   if(now<=0 || !TimeToStruct(now,fields))
      return 0;
   fields.hour=0;
   fields.min=0;
   fields.sec=0;
   return StructToTime(fields);
}

bool ReadDayHistory(const datetime day,const datetime now)
{
   const ulong instant=GetTickCount64();
   if(historyValid && historyDay==day && instant-lastHistoryRead<1000)
      return true;
   historyValid=false;
   if(!HistorySelect(day,now+1))
      return false;
   double net=0,loss=0,cash=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      const ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0)
         return false;
      const ENUM_DEAL_TYPE kind=(ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);
      const double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      if(kind==DEAL_TYPE_BALANCE || kind==DEAL_TYPE_CREDIT || kind==DEAL_TYPE_BONUS ||
         kind==DEAL_TYPE_CORRECTION)
      {
         cash+=profit;
         continue;
      }
      const double dealNet=profit+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
                           HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_FEE);
      net+=dealNet;
      loss+=MathMax(0.0,-dealNet);
   }
   historyDay=day;
   lastHistoryRead=instant;
   historyValid=true;
   dailyNet=net;
   dailyLoss=loss;
   cashFlow=cash-(testerFundingDay==day ? testerOpeningFunding : 0);
   return true;
}

void ActivateDailyLock()
{
   if(!dailyLock)
   {
      dailyLock=true;
      SaveState();
      Print("QTE: daily loss limit reached. Entry locked.");
   }
}

void HaltEmergency(const string reason)
{
   emergency=true;
   running=false;
   statusText=reason;
   SaveState();
   Print("QTE emergency: ",reason);
}

// A netting position can combine manual and EA fills despite having an EA magic.
bool OwnedPosition()
{
   if((ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)
      return false;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      return true;
   const ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(id==0 || !HistorySelectByPosition(id))
      return false;
   bool found=false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      const ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         return false;
      const long kind=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(kind==DEAL_TYPE_BUY || kind==DEAL_TYPE_SELL)
      {
         found=true;
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic)
            return false;
      }
   }
   return found;
}

double Cost(const double volume,const bool lossSide)
{
   return volume*(CommissionRoundTurnPerLot+(lossSide ? MaxFeesAtStopPerLot : 0));
}

bool PositionRisk(double &reserved,double &markedLoss,double &additionalStopLoss)
{
   const string symbol=PositionGetString(POSITION_SYMBOL);
   const double open=PositionGetDouble(POSITION_PRICE_OPEN), stop=PositionGetDouble(POSITION_SL);
   const double volume=PositionGetDouble(POSITION_VOLUME);
   const ENUM_ORDER_TYPE side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ?
                              ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   const double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   const double stopFill=stop+(side==ORDER_TYPE_BUY ? -1.0 : 1.0)*tickSize*StopSlippageTicks;
   double terminalProfit=0;
   const double marked=PositionGetDouble(POSITION_PROFIT);
   const double swap=PositionGetDouble(POSITION_SWAP);
   markedLoss=MathMax(0.0,-(marked+swap));
   if(stop<=0 || tickSize<=0 || stopFill<=0 ||
      !OrderCalcProfit(side,symbol,volume,open,stopFill,terminalProfit))
      return false;
   terminalProfit+=MathMin(0.0,swap)-Cost(volume,true);
   reserved=StopExposure(marked+swap,terminalProfit);
   additionalStopLoss=MathMax(0.0,marked+swap-terminalProfit);
   return true;
}

bool UpdatePortfolioRisk(const double equity,const double limitPercent)
{
   if(portfolioLocked || !MathIsValidNumber(equity))
      return false;
   if(equityPeak<=0 && equity<=0)
      return false;

   equityPeak=MathMax(equityPeak,equity);
   const double equityFloor=equityPeak*(1.0-limitPercent/100.0);
   portfolioRoom=MathMax(0.0,equity-equityFloor);
   if(portfolioRoom<=0)
      portfolioLocked=true;
   return !portfolioLocked;
}

bool RefreshRisk()
{
   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   const bool alreadyLocked=portfolioLocked;
   if(!UpdatePortfolioRisk(equity,MaxPortfolioDrawdownPercent))
   {
      remaining=0;
      if(portfolioLocked && !alreadyLocked)
         HaltEmergency("Portfolio drawdown limit reached");
      statusText=portfolioLocked ? "Portfolio drawdown lock" : "Equity unavailable";
      return false;
   }
   const datetime now=tester ? TimeCurrent() : TimeTradeServer();
   const datetime today=BrokerDay(now);
   if(!storageOK || today==0 || today<sessionDay || !ReadDayHistory(today,now))
   {
      statusText="Account audit unavailable";
      return false;
   }
   if(today!=sessionDay)
   {
      if(dailyLock && (PositionsTotal()>0 || OrdersTotal()>0))
      {
         statusText="Previous daily lock awaits flat account";
         return false;
      }
      const bool firstTesterDay=tester && sessionDay==0;
      sessionDay=today;
      if(firstTesterDay)
      {
         testerOpeningFunding=cashFlow;
         testerFundingDay=today;
         cashFlow=0;
      }
      const double openingBalance=AccountInfoDouble(ACCOUNT_BALANCE)-dailyNet-cashFlow;
      // When a first observation is late, use the lower observed / reconstructed value.
      startEquity=MathMax(0.0,MathMin(equity-MathMax(0.0,cashFlow),openingBalance));
      dailyLock=false;
      if(!SaveState())
         return false;
   }
   dayLimit=startEquity*MaxDailyRiskPercent/100;
   if(!MathIsValidNumber(equity) || startEquity<=0)
      return false;
   drawdown=MathMax(0.0,startEquity-(equity-cashFlow));
   maxDrawdown=MathMax(maxDrawdown,drawdown);
   foreignExposure=false;
   exposureOK=true;
   riskToStop=0;
   floatingLoss=0;
   double additionalStopLoss=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0)
      {
         exposureOK=false;
         continue;
      }
      const bool own=OwnedPosition();
      if(!own)
         foreignExposure=true;
      double reserved=0,markedLoss=0,futureLoss=0;
      if(!PositionRisk(reserved,markedLoss,futureLoss) || PositionGetDouble(POSITION_TP)<=0)
      {
         exposureOK=false;
         if(own && !emergency)
            HaltEmergency("Owned position has missing or invalid protection");
      }
      riskToStop+=reserved;
      floatingLoss+=markedLoss;
      additionalStopLoss+=futureLoss;
   }
   // This EA never intentionally places pending entries. Any existing order blocks new entries.
   if(OrdersTotal()>0)
      foreignExposure=true;
   remaining=MathMin(AvailableRisk(dayLimit,dailyLoss,floatingLoss,riskToStop),
                     MathMax(0.0,portfolioRoom-additionalStopLoss));
   if(MathMax(drawdown,dailyLoss+floatingLoss)>=dayLimit)
      ActivateDailyLock();
   statusText=emergency ? "Emergency stop" : (dailyLock ? "Daily risk lock" :
              (!exposureOK ? "Unprotected exposure" : (foreignExposure ? "Other exposure / order" :
              (!EntryCostsReady() ? "Confirm broker costs" : (running ? "Scanning" : "Paused")))));
   return !dailyLock && !emergency && exposureOK && !foreignExposure && EntryCostsReady() && storageOK;
}

double RoundPrice(const string s,const double price,const bool up)
{
   const double tickSize=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0)
      return 0;
   const double steps=price/tickSize;
   return NormalizeDouble((up ? MathCeil(steps-1e-9) : MathFloor(steps+1e-9))*tickSize,
                          (int)SymbolInfoInteger(s,SYMBOL_DIGITS));
}

bool VolumeAtRisk(const string symbol,const double maximum,const double riskPerLot,double &lots)
{
   const double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   const double maxVolume=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   const double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   return SizeDown(minimum,maxVolume,step,maximum,riskPerLot,lots);
}

double ClusterBudget(const string symbol,const int direction)
{
   if(!EnableCorrelationFilter)
      return remaining;
   const string base=SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE);
   const string quote=SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT);
   double used=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0)
         return 0;
      const string other=PositionGetString(POSITION_SYMBOL);
      const string otherBase=SymbolInfoString(other,SYMBOL_CURRENCY_BASE);
      const string otherQuote=SymbolInfoString(other,SYMBOL_CURRENCY_PROFIT);
      const int otherDirection=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      const bool shareSame=direction==otherDirection &&
         ((base!="" && base==otherBase) || (quote!="" && quote==otherQuote));
      const bool shareOpposite=direction!=otherDirection &&
         ((base!="" && base==otherQuote) || (quote!="" && quote==otherBase));
      if(other==symbol || shareSame || shareOpposite)
      {
         double reserved=0,markedLoss=0,futureLoss=0;
         if(!PositionRisk(reserved,markedLoss,futureLoss))
            return 0;
         used+=reserved;
      }
   }
   return MathMax(0.0,startEquity*MaxCurrencyClusterPercent/100-used);
}


struct TradePlan
{
   double entry,stop,target,lots,estimatedRisk,estimatedReward;
   ENUM_ORDER_TYPE side;
   ENUM_ORDER_TYPE_FILLING filling;
};

bool CanSend()
{
   if(!AllowedAccount())
      return false;
   // Simulated order acceptance is determined by OrderCheck and OrderSend.
   if(tester)
      return true;
   return TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}

bool SymbolSessionOpen(const string s,const datetime now)
{
   MqlDateTime fields;
   if(!TimeToStruct(now,fields))
      return false;
   const int seconds=fields.hour*3600+fields.min*60+fields.sec;
   for(int backwards=0;backwards<=1;backwards++)
   {
      const ENUM_DAY_OF_WEEK day=(ENUM_DAY_OF_WEEK)((fields.day_of_week+7-backwards)%7);
      datetime from=0,to=0;
      for(uint i=0;SymbolInfoSessionTrade(s,day,i,from,to);i++)
      {
         const int first=(int)((long)from%86400);
         const int last=(int)((long)to%86400);
         if(backwards==0 && ((first==last) || (first<last && seconds>=first && seconds<last) ||
                            (first>last && seconds>=first)))
            return true;
         if(backwards==1 && first>last && seconds<last)
            return true;
      }
   }
   return false;
}

bool FillPolicy(const string symbol,ENUM_ORDER_TYPE_FILLING &filling)
{
   const long execution=SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE);
   const long mask=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if(execution==SYMBOL_TRADE_EXECUTION_REQUEST || execution==SYMBOL_TRADE_EXECUTION_INSTANT ||
      (mask & SYMBOL_FILLING_FOK)!=0)
   {
      filling=ORDER_FILLING_FOK;
      return true;
   }
   if((mask & SYMBOL_FILLING_IOC)==0)
      return false;
   filling=ORDER_FILLING_IOC;
   return true;
}

string StrategyTag(const int id) { return "QTE:S"+IntegerToString(id); }

bool PositionSlot(const string symbol,const int strategy,const int direction)
{
   const bool hedging=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   int count=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0)
         return false;
      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;
      if(!hedging || !EnableMultiStrategy)
         return false;
      const int held=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      const string label=PositionGetString(POSITION_COMMENT);
      if(held!=direction || label==StrategyTag(strategy) || StringFind(label,"QTE:S")!=0)
         return false;
      count++;
   }
   return count<MaximumPositionsPerSymbol;
}

bool MakePlan(const Market &market,const MqlTick &tick,const Signal &signal,TradePlan &plan)
{
   const string s=market.symbol;
   const int d=signal.direction;
   const long mode=SymbolInfoInteger(s,SYMBOL_TRADE_MODE);
   if((mode!=SYMBOL_TRADE_MODE_FULL && mode!=(d>0 ? SYMBOL_TRADE_MODE_LONGONLY : SYMBOL_TRADE_MODE_SHORTONLY))
      || !FillPolicy(s,plan.filling))
      return RejectGate(GATE_SYMBOL_RULES);

   const long supported=SymbolInfoInteger(s,SYMBOL_ORDER_MODE);
   if((supported & SYMBOL_ORDER_MARKET)==0 || (supported & SYMBOL_ORDER_SL)==0 ||
      (supported & SYMBOL_ORDER_TP)==0)
      return RejectGate(GATE_SYMBOL_RULES);
   const double point=SymbolInfoDouble(s,SYMBOL_POINT);
   const double unit=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
   if(point<=0 || unit<=0)
      return RejectGate(GATE_SYMBOL_RULES);

   const double minimumDistance=unit+point*MathMax(SymbolInfoInteger(s,SYMBOL_TRADE_STOPS_LEVEL),
                                                   SymbolInfoInteger(s,SYMBOL_TRADE_FREEZE_LEVEL));
   plan.side=d>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   plan.entry=d>0 ? tick.ask : tick.bid;
   const double exitQuote=d>0 ? tick.bid : tick.ask;
   const double assumed=plan.entry+d*unit*EntrySlippageTicks;
   const double stopDistance=MathMax(signal.stopDistance,market.spread+minimumDistance);
   plan.stop=RoundPrice(s,plan.entry-d*stopDistance,d<0);
   const double stopFill=plan.stop-d*unit*StopSlippageTicks;
   const double probe=SymbolInfoDouble(s,SYMBOL_VOLUME_MIN);
   double stopPnL=0;
   if(probe<=0 || stopFill<=0 || assumed<=0 ||
      !OrderCalcProfit(plan.side,s,probe,assumed,stopFill,stopPnL) || stopPnL>=0)
      return RejectGate(GATE_STOP_TARGET);
   const double riskPerLot=-stopPnL/probe+Cost(1,true);

   const double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   const double sizingEquity=EnableCompoundRisk ? equity : MathMin(equity,ReferenceAccountEquity);
   const double percent=activeMode==AGGRESSIVE ? RiskPerTradeAggressive : RiskPerTradeSuperAggressive;
   const double adaptive=activeMode==ADAPTIVE_AGGRESSIVE ?
      MathMax(0.25,MathMin(1.0,signal.score/100.0-market.spread/market.atr)) : 1.0;
   const double cap=MathMin(sizingEquity*percent*adaptive/100,
                            MathMin(remaining,ClusterBudget(s,d)));
   if(!VolumeAtRisk(s,cap,riskPerLot,plan.lots))
      return RejectGate(GATE_MIN_LOT);
   double actualStopPnL=0;
   if(!OrderCalcProfit(plan.side,s,plan.lots,assumed,stopFill,actualStopPnL))
      return RejectGate(GATE_STOP_TARGET);
   plan.estimatedRisk=-actualStopPnL+Cost(plan.lots,true);
   if(plan.estimatedRisk<=0 || plan.estimatedRisk>cap+1e-7)
      return RejectGate(GATE_MIN_LOT);
   const double targetGross=RiskRewardRatio*plan.estimatedRisk+Cost(plan.lots,false);

   const double minTargetDistance=MathMax(unit,minimumDistance-d*(assumed-exitQuote));
   double low=minTargetDistance,high=MathMax(low,2.0*MathAbs(assumed-stopFill));
   double gross=0;
   bool bracketed=false;
   for(int i=0;i<16;i++)
   {
      const double trial=assumed+d*high;
      if(trial<=0 || !OrderCalcProfit(plan.side,s,plan.lots,assumed,trial,gross))
         return RejectGate(GATE_STOP_TARGET);
      if(gross>=targetGross)
      {
         bracketed=true;
         break;
      }
      high*=1.5;
      if(d<0 && high>=assumed)
         high=assumed-unit;
      if(high<low)
         return RejectGate(GATE_STOP_TARGET);
   }
   if(!bracketed)
      return RejectGate(GATE_STOP_TARGET);
   for(int i=0;i<32 && high-low>unit*0.05;i++)
   {
      const double middle=(low+high)/2;
      if(!OrderCalcProfit(plan.side,s,plan.lots,assumed,assumed+d*middle,gross))
         return RejectGate(GATE_STOP_TARGET);
      if(gross>=targetGross)
         high=middle;
      else
         low=middle;
   }

   plan.target=RoundPrice(s,assumed+d*high,d>0);
   if(plan.target<=0 ||
      !OrderCalcProfit(plan.side,s,plan.lots,assumed,plan.target,gross))
      return RejectGate(GATE_STOP_TARGET);
   plan.estimatedReward=gross-Cost(plan.lots,false);
   if(plan.estimatedReward+1e-7<RiskRewardRatio*plan.estimatedRisk)
      return RejectGate(GATE_STOP_TARGET);

   double margin=0;
   if(!OrderCalcMargin(plan.side,s,plan.lots,assumed,margin) ||
      margin<0 || AccountInfoDouble(ACCOUNT_MARGIN_FREE)<margin ||
      equity*100<MinimumMarginLevel*(AccountInfoDouble(ACCOUNT_MARGIN)+margin))
      return RejectGate(GATE_MARGIN);
   return true;
}

void LogExecution(const string s,const string action,const int strategy,const uint retcode,
                  const ulong order,const ulong deal,const double price,const double lots,
                  const double risk,const double reward,const ulong elapsed)
{
   if(ledger==INVALID_HANDLE)
      return;
   FileWrite(ledger,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),s,action,strategy,retcode,
             order,deal,price,lots,risk,reward,elapsed);
   FileFlush(ledger);
}

void ReconcileDeal(const ulong deal)
{
   lastHistoryRead=0;
   historyValid=false;
   if(deal==0 || !HistoryDealSelect(deal) || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic)
      return;
   const ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_IN)
      return;
   const long id=HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0 || PositionGetInteger(POSITION_IDENTIFIER)!=id)
         continue;
      const string s=PositionGetString(POSITION_SYMBOL);
      const bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      const ENUM_ORDER_TYPE side=buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      const double open=PositionGetDouble(POSITION_PRICE_OPEN);
      const double stop=PositionGetDouble(POSITION_SL);
      const double take=PositionGetDouble(POSITION_TP);
      const double vol=PositionGetDouble(POSITION_VOLUME);
      const double tickSize=SymbolInfoDouble(s,SYMBOL_TRADE_TICK_SIZE);
      const double fill=stop+(buy ? -1.0 : 1.0)*tickSize*StopSlippageTicks;
      double gain=0,loss=0;
      if(tickSize<=0 || stop<=0 || take<=0 || fill<=0 ||
         !OrderCalcProfit(side,s,vol,open,fill,loss) ||
         !OrderCalcProfit(side,s,vol,open,take,gain) ||
         gain-Cost(vol,false)+1e-7 < RiskRewardRatio*(-loss+Cost(vol,true)))
         HaltEmergency("Fill failed protection or net RR reconciliation");
      return;
   }
}

bool Submit(const Market &market,const Signal &signal,const TradePlan &plan)
{
   MqlTradeRequest request={};
   MqlTradeCheckResult check={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_DEAL;
   request.magic=Magic;
   request.symbol=market.symbol;
   request.volume=plan.lots;
   request.type=plan.side;
   request.price=plan.entry;
   request.sl=plan.stop;
   request.tp=plan.target;
   request.deviation=(ulong)MathCeil(EntrySlippageTicks*
      SymbolInfoDouble(market.symbol,SYMBOL_TRADE_TICK_SIZE)/SymbolInfoDouble(market.symbol,SYMBOL_POINT));
   request.type_filling=plan.filling;
   request.comment=StrategyTag(signal.strategy);
   if(!OrderCheck(request,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE) ||
      check.margin_free<0 || (check.margin_level>0 && check.margin_level<MinimumMarginLevel))
   {
      gateCounts[GATE_CHECK_REJECT]++;
      lastCheckCode=check.retcode;
      if(tester && gateCounts[GATE_CHECK_REJECT]==1)
         Print("QTE 1.05 CHECK | symbol=",market.symbol," code=",check.retcode,
               " description=",check.comment," lots=",plan.lots);
      LogExecution(market.symbol,"CHECK_REJECT",signal.strategy,check.retcode,0,0,
                   plan.entry,plan.lots,plan.estimatedRisk,plan.estimatedReward,0);
      return true;
   }

   const ulong before=GetMicrosecondCount();
   const bool sent=OrderSend(request,result);
   gateCounts[GATE_SENT]++;
   lastSendCode=result.retcode;
   const ulong elapsed=GetMicrosecondCount()-before;
   latencyBuffer[latencyNext]=elapsed;
   latencyNext=(latencyNext+1)%512;
   if(latencyCount<512)
      latencyCount++;
   LogExecution(market.symbol,"SEND",signal.strategy,result.retcode,result.order,result.deal,
                result.price,result.volume,plan.estimatedRisk,plan.estimatedReward,elapsed);

   if(sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL) &&
      result.deal!=0 && result.price>0)
   {
      gateCounts[GATE_FILLED]++;
      const double slip=signal.direction*(result.price-plan.entry);
      const double maxSlip=EntrySlippageTicks*SymbolInfoDouble(market.symbol,SYMBOL_TRADE_TICK_SIZE);
      if(slip>maxSlip+1e-9)
         HaltEmergency("Entry slippage exceeded the risk estimate");
      ReconcileDeal(result.deal);
      RefreshRisk();
      if(!exposureOK || riskToStop+dailyLoss>dayLimit+1e-7)
         HaltEmergency("Post-fill portfolio risk exceeded the estimate");
   }
   else
   {
      gateCounts[GATE_SEND_REJECT]++;
      if(tester && gateCounts[GATE_SEND_REJECT]==1)
         Print("QTE 1.05 SEND | symbol=",market.symbol," code=",result.retcode,
               " description=",result.comment," lots=",plan.lots);
      if(result.retcode==TRADE_RETCODE_PLACED || result.retcode==TRADE_RETCODE_TIMEOUT ||
         result.retcode==TRADE_RETCODE_CONNECTION || result.order!=0 || result.deal!=0 ||
         (sent && (result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL)))
         HaltEmergency("Ambiguous order outcome; reconciling");
   }
   return true;
}

bool FlattenOwned()
{
   bool done=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      const ulong ticket=OrderGetTicket(i);
      if(ticket==0)
      {
         done=false;
         continue;
      }
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=Magic)
         continue;
      trade.OrderDelete(ticket);
      if(trade.ResultRetcode()!=TRADE_RETCODE_DONE)
         done=false;
   }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0)
      {
         done=false;
         continue;
      }
      if(!OwnedPosition())
         continue;
      const string s=PositionGetString(POSITION_SYMBOL);
      trade.SetTypeFillingBySymbol(s);
      trade.PositionClose(ticket);
      if(trade.ResultRetcode()!=TRADE_RETCODE_DONE)
         done=false;
   }
   return done;
}

void ManagePositions()
{
   if(StrictRiskRewardMode)
      return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !OwnedPosition())
         continue;
      const string s=PositionGetString(POSITION_SYMBOL);
      if(TimeCurrent()-(datetime)PositionGetInteger(POSITION_TIME)>=MaximumHoldSeconds)
      {
         trade.SetTypeFillingBySymbol(s);
         trade.PositionClose(ticket);
         continue;
      }
      if(!EnableBreakEven && !EnableTrailing)
         continue;
      MqlTick tick;
      if(!SymbolInfoTick(s,tick))
         continue;
      const bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      const int direction=buy ? 1 : -1;
      const double price=buy ? tick.bid : tick.ask;
      const double open=PositionGetDouble(POSITION_PRICE_OPEN);
      const double stop=PositionGetDouble(POSITION_SL);
      const double target=PositionGetDouble(POSITION_TP);
      const double initialRisk=MathAbs(target-open)/RiskRewardRatio;
      const double moved=direction*(price-open);
      if(initialRisk<=0 || moved<initialRisk)
         continue;
      double proposed=EnableTrailing ? price-direction*initialRisk : open;
      if(EnableBreakEven)
         proposed=buy ? MathMax(proposed,open) : MathMin(proposed,open);
      proposed=RoundPrice(s,proposed,!buy);
      const double point=SymbolInfoDouble(s,SYMBOL_POINT);
      const double minimum=point*MathMax(SymbolInfoInteger(s,SYMBOL_TRADE_FREEZE_LEVEL),
                                         SymbolInfoInteger(s,SYMBOL_TRADE_STOPS_LEVEL));
      if(proposed>0 && direction*(proposed-stop)>point/2 && direction*(price-proposed)>minimum)
         trade.PositionModify(ticket,proposed,target);
   }
}

void SampleQuote(Market &m,const MqlTick &tick)
{
   m.impulse[m.head]=((tick.bid+tick.ask)-(m.lastBid+m.lastAsk))/2;
   m.head=(m.head+1)%16;
   if(m.count<16)
      m.count++;
}

void UpdateImpulse(Market &m,const MqlTick &latest)
{
   if(!EnableTickBackfill || latest.time_msc<=m.quoteTime || latest.time_msc-m.quoteTime>1000)
   {
      if(latest.time_msc-m.quoteTime>1000)
      {
         m.head=0;
         m.count=0;
      }
      SampleQuote(m,latest);
      return;
   }
   MqlTick recent[];
   const int count=CopyTicks(m.symbol,recent,COPY_TICKS_INFO,(ulong)m.quoteTime+1,32);
   if(count>0 && count<32)
   {
      for(int i=0;i<count;i++)
      {
         if(recent[i].time_msc>=latest.time_msc)
            break;
         if(recent[i].bid<=0 || recent[i].ask<recent[i].bid)
            continue;
         SampleQuote(m,recent[i]);
         m.lastBid=recent[i].bid;
         m.lastAsk=recent[i].ask;
      }
   }
   else if(count==32)
   {
      m.head=0;
      m.count=0;
   }
   SampleQuote(m,latest);
}

datetime lastAttempt[];

void ProcessMarket(const int index,const bool accountReady,const bool canTrade)
{
   MqlTick tick;
   const string s=markets[index].symbol;
   if(!SymbolInfoTick(s,tick) || tick.ask<tick.bid || tick.bid<=0)
      return;
   if(tick.time_msc<markets[index].quoteTime ||
      (tick.time_msc==markets[index].quoteTime &&
       tick.bid==markets[index].lastBid && tick.ask==markets[index].lastAsk))
      return;
   gateCounts[GATE_QUOTES]++;
   if(ArraySize(lastAttempt)!=ArraySize(markets))
      ArrayResize(lastAttempt,ArraySize(markets));

   const bool hadQuote=markets[index].quoteTime>0;
   const double previous=(markets[index].lastBid+markets[index].lastAsk)/2;
   const datetime previousBar=markets[index].barTime;
   const datetime activeBar=iTime(s,SignalTimeframe,0);
   const bool ready=activeBar>0 && RefreshFeatures(markets[index],activeBar);
   if(hadQuote)
      UpdateImpulse(markets[index],tick);
   markets[index].quoteTime=tick.time_msc;
   markets[index].lastBid=tick.bid;
   markets[index].lastAsk=tick.ask;
   markets[index].spread=tick.ask-tick.bid;
   if(!ready || !hadQuote)
   {
      gateCounts[GATE_WARMUP]++;
      return;
   }
   if(!EnableIntrabarExecution && activeBar==previousBar)
      return;
   gateCounts[GATE_EVALUATED]++;

   Signal signals[];
   Evaluate(markets[index],(tick.bid+tick.ask)/2,previous,signals);
   double best=0;
   const int count=ArraySize(signals);
   for(int i=0;i<count;i++)
      best=MathMax(best,signals[i].score);
   markets[index].score=best;
   if(count==0)
   {
      gateCounts[GATE_NO_SIGNAL]++;
      return;
   }
   if(best<MinimumSignalScore)
   {
      gateCounts[GATE_LOW_SCORE]++;
      return;
   }
   if(!running || finishFlatten)
   {
      gateCounts[GATE_PAUSED]++;
      return;
   }
   if(!EntryCostsReady())
   {
      gateCounts[GATE_FEES]++;
      return;
   }
   if(!canTrade)
   {
      gateCounts[GATE_PERMISSIONS]++;
      return;
   }
   if(!accountReady || dailyLock || emergency || !RefreshRisk())
   {
      gateCounts[GATE_ACCOUNT_RISK]++;
      return;
   }
   if(markets[index].spread>MaxSpreadToATR*markets[index].atr)
   {
      gateCounts[GATE_SPREAD]++;
      return;
   }
   const datetime now=tester ? TimeCurrent() : TimeTradeServer();
   if(now<tick.time || now-tick.time>MaximumQuoteAgeSeconds)
   {
      gateCounts[GATE_STALE]++;
      return;
   }
   if(!SymbolSessionOpen(s,now))
   {
      gateCounts[GATE_SESSION]++;
      return;
   }

   const int cooldown=EnableRapidReentry ? MinimumReentrySeconds :
                      (int)MathMax(MinimumReentrySeconds,PeriodSeconds(SignalTimeframe));
   if(lastAttempt[index]!=0 && now-lastAttempt[index]<cooldown)
   {
      gateCounts[GATE_COOLDOWN]++;
      return;
   }

   double support=0,resistance=0;
   for(int i=0;i<count;i++)
   {
      if(signals[i].direction>0)
         support=MathMax(support,signals[i].score);
      else
         resistance=MathMax(resistance,signals[i].score);
   }
   if(support>=MinimumSignalScore && resistance>=MinimumSignalScore &&
      MathAbs(support-resistance)<10.0)
   {
      gateCounts[GATE_CONFLICT]++;
      return;
   }
   const int direction=support>resistance ? 1 : -1;
   for(int rank=0;rank<count;rank++)
   {
      int chosen=-1;
      for(int i=0;i<count;i++)
         if(signals[i].direction==direction && signals[i].score>=MinimumSignalScore &&
            (chosen<0 || signals[i].score>signals[chosen].score))
            chosen=i;
      if(chosen<0)
         return;
      TradePlan plan;
      if(!PositionSlot(s,signals[chosen].strategy,direction))
         gateCounts[GATE_POSITION_SLOT]++;
      else if(MakePlan(markets[index],tick,signals[chosen],plan))
      {
         lastAttempt[index]=now;
         Submit(markets[index],signals[chosen],plan);
         return;
      }
      signals[chosen].score=-1;
      if(!EnableMultiStrategy)
         return;
   }
}


void Button(const string name,const string text,const int row,const int x,const int width)
{
   const string key="QTE_"+name;
   if(ObjectFind(0,key)>=0)
      return;
   if(!ObjectCreate(0,key,OBJ_BUTTON,0,0,0))
      return;
   ObjectSetInteger(0,key,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,key,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,key,OBJPROP_YDISTANCE,180+row*25);
   ObjectSetInteger(0,key,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,key,OBJPROP_YSIZE,21);
   ObjectSetInteger(0,key,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,key,OBJPROP_BGCOLOR,name=="EMERGENCY" ? clrMaroon : clrDarkSlateGray);
   ObjectSetInteger(0,key,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,key,OBJPROP_TEXT,text);
}

double Percentile(ulong &sorted[],const double probability)
{
   if(ArraySize(sorted)==0)
      return 0;
   return (double)sorted[(int)MathCeil(probability*ArraySize(sorted))-1]/1000;
}

void DrawPanel(const bool force)
{
   if(tester && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   const ulong now=GetTickCount64();
   if(!force && now-lastPanel<350)
      return;
   lastPanel=now;
   Button("START","START",0,10,62);
   Button("PAUSE","PAUSE",0,76,62);
   Button("STOP","STOP",0,142,54);
   Button("CLOSE","CLOSE ALL EA",0,200,93);
   Button("EMERGENCY","EMERGENCY STOP",0,297,120);
   Button("A","AGGRESSIVE 0.5%",1,10,121);
   Button("B","FIXED 1%",1,135,151);
   Button("C","ADAPTIVE",1,290,127);

   ulong sorted[];
   ArrayCopy(sorted,latencyBuffer,0,0,latencyCount);
   if(latencyCount>0)
      ArraySort(sorted);
   string message="QUANTUM TRADING ENGINE  |  "+(tester ? "TESTER" : "DEMO")+"  |  "+statusText+
                  "\nMode "+EnumToString(activeMode)+"  |  "+AccountInfoString(ACCOUNT_CURRENCY)+
                  "\nBalance "+DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+
                  "  Equity "+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
                  "  Free margin "+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2)+
                  "  Margin % "+DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),1)+
                  "\nDaily net "+DoubleToString(dailyNet,2)+
                  "  Daily losses "+DoubleToString(dailyLoss,2)+
                  "  Floating losses "+DoubleToString(floatingLoss,2)+
                  "\nReserved "+DoubleToString(riskToStop,2)+
                  "  Remaining "+DoubleToString(remaining,2)+
                  "  DD "+DoubleToString(drawdown,2)+" / "+DoubleToString(maxDrawdown,2)+
                  "\nPositions "+IntegerToString(PositionsTotal())+
                  "  Strategy mask "+IntegerToString(StrategyMask)+"  AI rule mode"+
                  "\nOrder latency p50 / p95 / p99 (ms) "+
                  DoubleToString(Percentile(sorted,0.5),2)+" / "+
                  DoubleToString(Percentile(sorted,0.95),2)+" / "+
                  DoubleToString(Percentile(sorted,0.99),2);
   for(int i=0;i<MathMin(ArraySize(markets),3);i++)
      message+="\n"+markets[i].symbol+"  "+markets[i].regime+
               "  strength "+DoubleToString(markets[i].regimeScore,0)+
               "  signal "+DoubleToString(markets[i].score,0)+
               "  spread "+DoubleToString(markets[i].spread,(int)SymbolInfoInteger(markets[i].symbol,SYMBOL_DIGITS));
   Comment(message);
}

void HandleButton(const string key)
{
   if(StringFind(key,"QTE_")!=0)
      return;
   ObjectSetInteger(0,key,OBJPROP_STATE,false);
   if(key=="QTE_START" && !emergency && !dailyLock && !finishFlatten)
      running=true;
   if(key=="QTE_PAUSE" || key=="QTE_STOP" || key=="QTE_CLOSE")
      running=false;
   if(key=="QTE_STOP" || key=="QTE_CLOSE")
      finishFlatten=true;
   if(key=="QTE_EMERGENCY")
      HaltEmergency("Operator emergency stop");
   if(key=="QTE_A")
      activeMode=AGGRESSIVE;
   if(key=="QTE_B")
      activeMode=SUPER_AGGRESSIVE;
   if(key=="QTE_C")
      activeMode=ADAPTIVE_AGGRESSIVE;
   Pump(false);
   ChartRedraw();
}


int OnInit()
{
   tester=(bool)MQLInfoInteger(MQL_TESTER);
   Print("QTE 1.05 INIT | chart=",_Symbol," | Symbols=",Symbols,
         " | tester=",tester," | StartOnLoad=",StartOnLoad,
         " | ConfirmCostInputs=",ConfirmCostInputs);
   if(!AllowedAccount())
   {
      Print("QTE 1.05: this research build runs only in Strategy Tester.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(!InputsValid())
   {
      Print("QTE 1.05: invalid EA inputs. Check risk, strategy and execution settings.");
      return INIT_PARAMETERS_INCORRECT;
   }
   activeMode=RiskMode;
   equityPeak=MathMax(0.0,AccountInfoDouble(ACCOUNT_EQUITY));
   trade.SetExpertMagicNumber(Magic);
   trade.SetAsyncMode(false);
   if(!OpenState())
   {
      Print("QTE 1.05: could not open account risk state.");
      return INIT_FAILED;
   }
   if(!LoadMarkets())
   {
      Print("QTE 1.05: no market state available. Chart=",_Symbol);
      return INIT_FAILED;
   }
   const bool chartOnlyTest=tester && ArraySize(markets)==1 && markets[0].symbol==_Symbol;
   if(!chartOnlyTest && !EventSetMillisecondTimer(PollMilliseconds))
   {
      Print("QTE 1.05: timer initialization failed. Error=",GetLastError());
      return INIT_FAILED;
   }
   if(WriteExecutionLog)
   {
      const string filename="QTE_"+(string)AccountInfoInteger(ACCOUNT_LOGIN)+"_"+
                            (string)GetTickCount64()+".csv";
      ledger=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(ledger!=INVALID_HANDLE)
         FileWrite(ledger,"server_time","symbol","action","strategy","retcode","order",
                   "deal","price","lots","estimated_risk","estimated_reward","elapsed_us");
   }
   running=StartOnLoad || (tester && AutoStartTester);
   Print("QTE 1.05 MODE | scanning=",running," | chart_tick_only=",chartOnlyTest);
   if(tester && !running)
      Print("QTE 1.05: tester entries paused; set AutoStartTester=true.");
   if(!EntryCostsReady())
      Print("QTE 1.05: entries blocked until broker fee inputs are confirmed.");
   else if(!ConfirmCostInputs)
      Print("QTE 1.05: TESTER ONLY | execution test with unconfirmed fees.",
            " Estimated SL/TP uses the configured cost inputs; verify broker fees before judging net RR.");
   if(EnableAI)
      Print("QTE: AI input enabled, calibrated runtime model unavailable; rule strategies only.");
   DrawPanel(true);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ReleaseMarkets();
   if(ledger!=INVALID_HANDLE)
      FileClose(ledger);
   if(lease!=INVALID_HANDLE)
      FileClose(lease);
   ObjectsDeleteAll(0,"QTE_");
   Comment("");
}

void LogTesterProgress()
{
   if(!tester)
      return;
   const datetime now=TimeCurrent();
   if(now<=0)
      return;
   if(nextTesterProgress==0)
      nextTesterProgress=now+900;
   if(now<nextTesterProgress)
      return;
   nextTesterProgress=now+86400;
   Print("QTE 1.05 PROGRESS | status=",statusText," evaluated=",gateCounts[GATE_EVALUATED],
         " no_signal=",gateCounts[GATE_NO_SIGNAL]," score=",gateCounts[GATE_LOW_SCORE],
         " risk=",gateCounts[GATE_ACCOUNT_RISK]," spread=",gateCounts[GATE_SPREAD],
         " lot_or_budget=",gateCounts[GATE_MIN_LOT]," stops=",gateCounts[GATE_STOP_TARGET],
         " session=",gateCounts[GATE_SESSION]," checks_rejected=",gateCounts[GATE_CHECK_REJECT],
         " sent=",gateCounts[GATE_SENT]," fills=",gateCounts[GATE_FILLED]);
}

void Pump(const bool chartTick)
{
   if(!AllowedAccount() || (!tester && !TerminalInfoInteger(TERMINAL_CONNECTED)))
   {
      statusText="Disconnected or unsupported account";
      DrawPanel(false);
      return;
   }

   const bool ready=RefreshRisk();
   const bool canTrade=CanSend();
   const ulong flattenClock=(ulong)TimeCurrent()*1000;
   if((dailyLock || emergency || finishFlatten) && canTrade && flattenClock>=nextFlatten)
   {
      nextFlatten=flattenClock+1000;
      if(FlattenOwned())
         finishFlatten=false;
   }
   if(ready && !dailyLock && !emergency && !finishFlatten && canTrade)
      ManagePositions();

   for(int i=0;i<ArraySize(markets);i++)
   {
      if(chartTick && markets[i].symbol!=_Symbol)
         continue;
      ProcessMarket(i,ready,canTrade);
   }
   LogTesterProgress();
   DrawPanel(false);
}

void OnTick() { Pump(true); }
void OnTimer() { Pump(false); }
void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(transaction.type==TRADE_TRANSACTION_DEAL_ADD)
   {
      LogExecution(transaction.symbol,"DEAL",0,result.retcode,transaction.order,
                   transaction.deal,transaction.price,transaction.volume,0,0,0);
      ReconcileDeal(transaction.deal);
   }
}

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(id==CHARTEVENT_OBJECT_CLICK)
      HandleButton(sparam);
}

// The terminal's standard tester report remains the authoritative account curve.
double OnTester()
{
   Print("QTE 1.05 DIAG | quotes=",gateCounts[GATE_QUOTES]," warmup=",gateCounts[GATE_WARMUP],
         " evaluated=",gateCounts[GATE_EVALUATED]," no_signal=",gateCounts[GATE_NO_SIGNAL],
         " low_score=",gateCounts[GATE_LOW_SCORE]," paused=",gateCounts[GATE_PAUSED],
         " fees_unconfirmed=",gateCounts[GATE_FEES]," permissions=",gateCounts[GATE_PERMISSIONS],
         " account_risk=",gateCounts[GATE_ACCOUNT_RISK]," last_status=",statusText);
   Print("QTE 1.05 DIAG | spread=",gateCounts[GATE_SPREAD]," stale=",gateCounts[GATE_STALE],
         " session=",gateCounts[GATE_SESSION]," cooldown=",gateCounts[GATE_COOLDOWN],
         " conflict=",gateCounts[GATE_CONFLICT]," position_slot=",gateCounts[GATE_POSITION_SLOT],
         " symbol_rules=",gateCounts[GATE_SYMBOL_RULES]," minimum_lot_or_budget=",gateCounts[GATE_MIN_LOT],
         " stop_or_target=",gateCounts[GATE_STOP_TARGET]," margin=",gateCounts[GATE_MARGIN]);
   Print("QTE 1.05 DIAG | check_rejected=",gateCounts[GATE_CHECK_REJECT]," check_code=",lastCheckCode,
         " sent=",gateCounts[GATE_SENT]," fills=",gateCounts[GATE_FILLED],
         " send_unconfirmed=",gateCounts[GATE_SEND_REJECT]," send_code=",lastSendCode);
   PrintFormat("QTE TESTER | trades %.0f | net %.2f | gross profit %.2f | gross loss %.2f | "
               "equity DD %.2f%% | profit factor %.4f",
               TesterStatistics(STAT_TRADES),TesterStatistics(STAT_PROFIT),
               TesterStatistics(STAT_GROSS_PROFIT),TesterStatistics(STAT_GROSS_LOSS),
               TesterStatistics(STAT_EQUITY_DDREL_PERCENT),TesterStatistics(STAT_PROFIT_FACTOR));
   const double trades=TesterStatistics(STAT_TRADES);
   const double wins=TesterStatistics(STAT_PROFIT_TRADES);
   const double winRate=trades>0 ? 100.0*wins/trades : 0.0;
   const double net=TesterStatistics(STAT_PROFIT);
   const bool passes=ConfirmCostInputs && !portfolioLocked &&
                     trades>=MinimumValidationTrades && winRate>=TargetWinRate &&
                     MathIsValidNumber(net) && net>0 &&
                     TesterStatistics(STAT_PROFIT_FACTOR)>1.0 &&
                     TesterStatistics(STAT_EQUITY_DDREL_PERCENT)<MaxPortfolioDrawdownPercent;
   Print("QTE 1.05 METRICS | passes=",passes," | fee_confirmed=",ConfirmCostInputs,
         " | portfolio_locked=",portfolioLocked," | win_rate=",DoubleToString(winRate,2));
   return passes ? net : -1.0e100;
}
