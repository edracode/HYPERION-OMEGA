#property strict
#property version "1.00"
#property description "MIDAS VX — quantitative research EA"
#include <Trade/Trade.mqh>

enum RiskMode { CONSERVATIVE, BALANCED, AGGRESSIVE };
enum Alpha { BREAKOUT, CONTINUATION, REVERSAL, EXPANSION, MEAN_REVERSION };
input RiskMode TradingMode=BALANCED;
input double RiskPerTrade=0.5;
input double DailyLossLimit=3.0;
input double WeeklyLossLimit=6.0;
input double MaximumDrawdown=20.0;
input double MaxPortfolioRisk=1.5;
input double MaxCorrelatedRisk=0.75;
input int MaximumOpenPositions=3;
input double MinimumMarginLevel=300;
input double EmergencyMarginLevel=150;
input ulong MagicNumber=720011;
input bool AllowRealAccount=false;
input string Symbols="";
input ENUM_TIMEFRAMES SignalTF=PERIOD_M15;
input ENUM_TIMEFRAMES TrendTF=PERIOD_H1;
input int SessionStartHour=0;
input int SessionEndHour=24;
input double MaxSpreadATR=0.15;
input double SpreadLimitPoints=0;
input uint SlippageLimitPoints=20;
input double RoundTripCostPerLot=0; // Account currency, including expected commission and fees
input double FixedLot=0;
input double StopATR=1.8;
input double RewardMultiple=2.0;
input int ChannelBars=24;
input double TrendADX=23;
input double EmergencyATRRatio=3.0;
input bool TrailingStop=true;
input bool BreakEven=true;
input bool AdaptiveSelection=true;
input int MinExpectancyTrades=25;
input int ExpectancyLookbackDays=180;
input int StrategyMask=1; // 1 breakout, 2 continuation, 4 reversal, 8 expansion, 16 mean reversion
input bool ExportTesterData=false;
input string ExportLabel="baseline";

struct Market {
   string name;
   int atr, adx, trend;
   datetime last;
};
struct Signal {
   int alpha, side;
   double atr, stop, reward, volatility;
};
struct Exposure {
   int count;
   double total, correlated;
   bool blocked;
};

Market markets[];
CTrade trade;
string stateKey;
int lockFile=INVALID_HANDLE, equityFile=INVALID_HANDLE;
bool testing, emergency, dayBlocked, weekBlocked, historyDirty=true;
bool stateOK=true;
datetime dayKey, weekKey, lastExport, lastCloseAttempt;
double dayBase, weekBase, peak, maximumObservedDrawdown;
double expectancy[5];
int observations[5];

bool Quote(const string name,MqlTick &q) {
   return SymbolInfoTick(name,q) && q.bid>0 && q.ask>=q.bid;
}

double StoreRead(const string key,const double fallback) {
   double value=0;
   if(testing || !GlobalVariableGet(stateKey+key,value)) return fallback;
   return value;
}

void Store(const string key,const double value) {
   if(!testing && GlobalVariableSet(stateKey+key,value)==0) {
      stateOK=false;
      Print("MIDAS VX cannot persist ",key," error=",GetLastError());
   }
}

datetime DayStart(const datetime now) {
   MqlDateTime t={};
   TimeToStruct(now,t);
   return now-t.hour*3600-t.min*60-t.sec;
}

void Periods(const datetime now,datetime &day,datetime &week) {
   MqlDateTime t={};
   TimeToStruct(now,t);
   day=DayStart(now);
   week=day-((t.day_of_week+6)%7)*86400;
}

void RestoreRisk(const datetime now,const double equity) {
   Periods(now,dayKey,weekKey);
   peak=StoreRead(".peak",equity);
   emergency=StoreRead(".halt",0)>0;
   dayBase=StoreRead(".d"+IntegerToString(dayKey),equity);
   weekBase=StoreRead(".w"+IntegerToString(weekKey),equity);
   dayBlocked=StoreRead(".dl"+IntegerToString(dayKey),0)>0;
   weekBlocked=StoreRead(".wl"+IntegerToString(weekKey),0)>0;
   Store(".d"+IntegerToString(dayKey),dayBase);
   Store(".w"+IntegerToString(weekKey),weekBase);
   Store(".peak",peak);
   if(!testing) GlobalVariablesFlush();
}

bool OwnPosition() {
   return (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber;
}

bool Accepted() {
   uint code=trade.ResultRetcode();
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL ||
          code==TRADE_RETCODE_PLACED;
}

void CloseManaged(const bool all) {
   for(int i=PositionsTotal()-1;i>=0;--i) {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !OwnPosition() || (!all && PositionGetDouble(POSITION_SL)>0)) continue;
      string name=PositionGetString(POSITION_SYMBOL);
      if(!trade.SetTypeFillingBySymbol(name)) continue;
      if(!trade.PositionClose(ticket,SlippageLimitPoints) || !Accepted())
         Print("MIDAS VX close ",ticket,": ",trade.ResultRetcodeDescription());
   }
   if(!all) return;
   for(int i=OrdersTotal()-1;i>=0;--i) {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || (ulong)OrderGetInteger(ORDER_MAGIC)!=MagicNumber) continue;
      if(!trade.OrderDelete(ticket) || !Accepted())
         Print("MIDAS VX cancel ",ticket,": ",trade.ResultRetcodeDescription());
   }
}

bool RiskGate(const datetime now,const double equity) {
   datetime day,week;
   Periods(now,day,week);
   bool changed=false;
   if(day!=dayKey) {
      dayKey=day;
      dayBase=StoreRead(".d"+IntegerToString(day),equity);
      dayBlocked=StoreRead(".dl"+IntegerToString(day),0)>0;
      Store(".d"+IntegerToString(day),dayBase);
      changed=true;
   }
   if(week!=weekKey) {
      weekKey=week;
      weekBase=StoreRead(".w"+IntegerToString(week),equity);
      weekBlocked=StoreRead(".wl"+IntegerToString(week),0)>0;
      Store(".w"+IntegerToString(week),weekBase);
      changed=true;
   }
   if(equity>peak) {
      peak=equity;
      Store(".peak",peak);
      changed=true;
   }
   double drawdown=100*(peak-equity)/peak;
   maximumObservedDrawdown=MathMax(maximumObservedDrawdown,drawdown);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   double level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   if(!emergency && (drawdown>=MaximumDrawdown || equity<=0 ||
      (margin>0 && level<=EmergencyMarginLevel))) {
      emergency=true;
      Store(".halt",1);
      changed=true;
      Print("MIDAS VX emergency equity/margin halt");
   }
   if(!dayBlocked && equity<=dayBase*(1-DailyLossLimit/100)) {
      dayBlocked=true;
      Store(".dl"+IntegerToString(dayKey),1);
      changed=true;
   }
   if(!weekBlocked && equity<=weekBase*(1-WeeklyLossLimit/100)) {
      weekBlocked=true;
      Store(".wl"+IntegerToString(weekKey),1);
      changed=true;
   }
   if(changed && !testing) GlobalVariablesFlush();
   bool halted=emergency || dayBlocked || weekBlocked || !stateOK;
   if(now!=lastCloseAttempt) {
      lastCloseAttempt=now;
      CloseManaged(halted);
   }
   return !halted && (margin<=0 || level>=MinimumMarginLevel);
}

int ClockSeconds(const datetime time) {
   return (int)(time%86400);
}

bool SessionOpen(const string name,const datetime now) {
   MqlDateTime t={};
   TimeToStruct(now,t);
   if(SessionStartHour<SessionEndHour) {
      if(t.hour<SessionStartHour || t.hour>=SessionEndHour) return false;
   } else if(SessionStartHour>SessionEndHour &&
             t.hour<SessionStartHour && t.hour>=SessionEndHour) return false;

   int seconds=ClockSeconds(now);
   for(int offset=0;offset<2;++offset) {
      ENUM_DAY_OF_WEEK day=(ENUM_DAY_OF_WEEK)((t.day_of_week-offset+7)%7);
      for(uint i=0;i<32;++i) {
         datetime start,end;
         if(!SymbolInfoSessionTrade(name,day,i,start,end)) break;
         int a=ClockSeconds(start),b=ClockSeconds(end);
         if(b==0 && end>start) b=86400;
         if(offset==0 && seconds>=a && (b<a || (b==a && end>start) || seconds<b)) return true;
         if(offset==1 && b<a && seconds<b) return true;
      }
   }
   return false;
}

bool Correlated(const string a,const string b) {
   string base=SymbolInfoString(a,SYMBOL_CURRENCY_BASE);
   string quote=SymbolInfoString(a,SYMBOL_CURRENCY_PROFIT);
   string otherBase=SymbolInfoString(b,SYMBOL_CURRENCY_BASE);
   string otherQuote=SymbolInfoString(b,SYMBOL_CURRENCY_PROFIT);
   if(base=="" || quote=="" || otherBase=="" || otherQuote=="") return true;
   return a==b || base==otherBase || base==otherQuote || quote==otherBase || quote==otherQuote;
}

void MeasureExposure(const string name,Exposure &e) {
   bool netting=AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   for(int i=0;i<OrdersTotal();++i) {
      if(OrderGetTicket(i)==0) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)==MagicNumber ||
         (netting && OrderGetString(ORDER_SYMBOL)==name)) e.blocked=true;
   }
   for(int i=0;i<PositionsTotal();++i) {
      if(PositionGetTicket(i)==0) continue;
      string other=PositionGetString(POSITION_SYMBOL);
      if(other==name && (netting || OwnPosition())) e.blocked=true;
      if(!OwnPosition()) continue;
      ++e.count;
      double stop=PositionGetDouble(POSITION_SL), loss=0;
      double volume=PositionGetDouble(POSITION_VOLUME);
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      ENUM_ORDER_TYPE side=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      MqlTick q={};
      if(stop<=0 || !Quote(other,q) ||
         !OrderCalcProfit(side,other,volume,buy?q.bid:q.ask,stop,loss)) {
         e.blocked=true;
         continue;
      }
      double risk=MathMax(0,-loss)+volume*RoundTripCostPerLot;
      e.total+=risk;
      if(Correlated(name,other)) e.correlated+=risk;
   }
}

int AlphaFromComment(const string comment) {
   for(int a=0;a<5;++a)
      if(comment=="MVX"+IntegerToString(a)) return a;
   return -1;
}

void UpdateExpectancy(const datetime now) {
   if(!AdaptiveSelection || !historyDirty) return;
   datetime start=now-ExpectancyLookbackDays*86400;
   if(!HistorySelect(start,now)) return;
   ulong ids[];
   int total=HistoryDealsTotal();
   ArrayResize(ids,total);
   int used=0;
   for(int i=0;i<total;++i) {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber) continue;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
         ids[used++]=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
   }
   ArrayResize(ids,used);
   ArraySort(ids);
   ArrayInitialize(expectancy,0);
   ArrayInitialize(observations,0);
   for(int i=0;i<used;++i) {
      if(ids[i]==0 || (i>0 && ids[i]==ids[i-1]) || !HistorySelectByPosition(ids[i])) continue;
      double net=0,balance=0;
      int a=-1;
      datetime closed=0;
      bool mixed=false;
      int deals=HistoryDealsTotal();
      for(int j=0;j<deals;++j) {
         ulong deal=HistoryDealGetTicket(j);
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
         if(entry==DEAL_ENTRY_IN) {
            if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber) mixed=true;
            if(a<0) a=AlphaFromComment(HistoryDealGetString(deal,DEAL_COMMENT));
            balance+=volume;
         } else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) {
            balance-=volume;
            datetime stamp=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
            if(stamp>closed) closed=stamp;
         } else mixed=true;
         net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)
             +HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
      }
      if(!mixed && a>=0 && MathAbs(balance)<1e-7 && closed>=start && closed<=now) {
         expectancy[a]+=net;
         ++observations[a];
      }
   }
   for(int a=0;a<5;++a)
      if(observations[a]>0) expectancy[a]/=observations[a];
   historyDirty=false;
}

int SignalSide(const int alpha,const int bull,const int bear) {
   if(!(StrategyMask & (1<<alpha))) return 0;
   if(AdaptiveSelection && observations[alpha]>=MinExpectancyTrades && expectancy[alpha]<=0) return 0;
   return bull==bear?0:(bull?1:-1);
}

bool ReadSignal(Market &m,Signal &s) {
   int count=ChannelBars+2;
   MqlRates bars[], htf[];
   double atr[], adx[1], trend[];
   ArraySetAsSeries(bars,true);
   ArraySetAsSeries(htf,true);
   ArraySetAsSeries(atr,true);
   ArraySetAsSeries(trend,true);
   if(CopyRates(m.name,SignalTF,1,count,bars)!=count ||
      CopyRates(m.name,TrendTF,1,6,htf)!=6 ||
      CopyBuffer(m.atr,0,1,41,atr)!=41 ||
      CopyBuffer(m.adx,0,1,1,adx)!=1 ||
      CopyBuffer(m.trend,0,1,6,trend)!=6) return false;
   if(atr[0]<=0 || trend[0]<=0 || atr[0]==EMPTY_VALUE || trend[0]==EMPTY_VALUE ||
      trend[5]==EMPTY_VALUE || adx[0]==EMPTY_VALUE) return false;
   double average=0;
   for(int i=1;i<=40;++i) {
      if(atr[i]<=0 || atr[i]==EMPTY_VALUE) return false;
      average+=atr[i]/40;
   }
   double unit=atr[0], ratio=unit/average;
   s.volatility=ratio;
   if(ratio>=EmergencyATRRatio) return true;

   double high=bars[1].high,low=bars[1].low,mean=0;
   for(int i=1;i<=ChannelBars;++i) {
      high=MathMax(high,bars[i].high);
      low=MathMin(low,bars[i].low);
      mean+=bars[i].close/ChannelBars;
   }
   double variance=0;
   for(int i=1;i<=ChannelBars;++i) variance+=MathPow(bars[i].close-mean,2)/ChannelBars;
   double z=variance>0?(bars[0].close-mean)/MathSqrt(variance):0;
   double close=bars[0].close,open=bars[0].open,previous=bars[1].close;
   double range=bars[0].high-bars[0].low;
   double momentum=close-bars[5].close;
   double efficiency=MathAbs(momentum);
   double travel=0;
   for(int i=0;i<5;++i) travel+=MathAbs(bars[i].close-bars[i+1].close);
   efficiency=travel>0?efficiency/travel:0;
   bool up=adx[0]>=TrendADX && htf[0].close>trend[0] && trend[0]>trend[5] && htf[0].close>htf[5].close;
   bool down=adx[0]>=TrendADX && htf[0].close<trend[0] && trend[0]<trend[5] && htf[0].close<htf[5].close;
   bool sideways=adx[0]<TrendADX && ratio<=1.25;
   bool sweepLow=bars[0].low<low-0.05*unit && close>low && close>open && close-bars[0].low>0.6*range;
   bool sweepHigh=bars[0].high>high+0.05*unit && close<high && close<open && bars[0].high-close>0.6*range;
   bool compression=(atr[2]+atr[3]+atr[4]+atr[5])/4<0.88*average;
   bool expansion=ratio>1.10 && range>=1.4*unit && compression;
   int directions[5];
   directions[BREAKOUT]=SignalSide(BREAKOUT,up && close>high+0.05*unit && efficiency>0.55,
                                             down && close<low-0.05*unit && efficiency>0.55);
   directions[CONTINUATION]=SignalSide(CONTINUATION,up && previous<bars[4].close && close>bars[1].high,
                                                     down && previous>bars[4].close && close<bars[1].low);
   directions[REVERSAL]=SignalSide(REVERSAL,!down && sweepLow,!up && sweepHigh);
   directions[EXPANSION]=SignalSide(EXPANSION,expansion && !down && momentum>0 && close>high,
                                               expansion && !up && momentum<0 && close<low);
   directions[MEAN_REVERSION]=SignalSide(MEAN_REVERSION,sideways && z<-2 && close>open && close>previous,
                                                         sideways && z>2 && close<open && close<previous);
   double best=-DBL_MAX;
   for(int a=0;a<5;++a) {
      if(directions[a]==0) continue;
      double score=AdaptiveSelection && observations[a]>=MinExpectancyTrades?expectancy[a]:0;
      if(score<=best) continue;
      best=score;
      s.alpha=a;
      s.side=directions[a];
   }
   s.atr=unit;
   s.stop=StopATR*unit;
   s.reward=RewardMultiple;
   if(s.alpha==REVERSAL) s.stop=MathMax(s.stop,(s.side>0?close-bars[0].low:bars[0].high-close)+0.15*unit);
   if(s.alpha==MEAN_REVERSION) {
      s.reward=MathMin(s.reward,MathAbs(mean-close)/s.stop);
      if(s.reward<1.05) s.side=0;
   }
   return true;
}

double PriceGrid(const string name,const double value,const bool upward) {
   double size=SymbolInfoDouble(name,SYMBOL_TRADE_TICK_SIZE);
   if(size<=0) return 0;
   double count=value/size;
   double rounded=upward?MathCeil(count-1e-9):MathFloor(count+1e-9);
   return NormalizeDouble(rounded*size,(int)SymbolInfoInteger(name,SYMBOL_DIGITS));
}

double ProtectionGap(const string name) {
   double point=SymbolInfoDouble(name,SYMBOL_POINT);
   long stop=SymbolInfoInteger(name,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(name,SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(stop,freeze)*point+SymbolInfoDouble(name,SYMBOL_TRADE_TICK_SIZE);
}

double NormalizeVolume(const string name,const double requested) {
   double minLot=SymbolInfoDouble(name,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(name,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(name,SYMBOL_VOLUME_STEP);
   if(step<=0 || minLot<=0 || requested<minLot) return 0;
   double volume=NormalizeDouble(minLot+step*MathFloor((MathMin(requested,maxLot)-minLot)/step+1e-8),8);
   return volume>=minLot && volume<=maxLot?volume:0;
}

void OpenTrade(const Market &m,const Signal &s,const MqlTick &q,const double equity) {
   string name=m.name;
   double point=SymbolInfoDouble(name,SYMBOL_POINT), spread=q.ask-q.bid;
   if(point<=0 || spread>s.atr*MaxSpreadATR || (SpreadLimitPoints>0 && spread>SpreadLimitPoints*point)) return;
   bool buy=s.side>0;
   long mode=SymbolInfoInteger(name,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL && mode!=(buy?SYMBOL_TRADE_MODE_LONGONLY:SYMBOL_TRADE_MODE_SHORTONLY)) return;
   long flags=SymbolInfoInteger(name,SYMBOL_ORDER_MODE);
   if(!(flags & SYMBOL_ORDER_MARKET) || !(flags & SYMBOL_ORDER_SL) || !(flags & SYMBOL_ORDER_TP)) return;
   Exposure e={};
   MeasureExposure(name,e);
   if(e.blocked || e.count>=MaximumOpenPositions) return;

   ENUM_ORDER_TYPE side=buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double price=buy?q.ask:q.bid;
   double gap=ProtectionGap(name);
   double stop=PriceGrid(name,buy?MathMin(price-s.stop,q.bid-gap):MathMax(price+s.stop,q.ask+gap),!buy);
   double distance=MathAbs(price-stop);
   double target=PriceGrid(name,buy?MathMax(price+s.reward*distance,q.bid+gap):
                                   MathMin(price-s.reward*distance,q.ask-gap),buy);
   if(stop<=0 || target<=0 || distance<=0) return;
   double adverse=price+s.side*SlippageLimitPoints*point;
   double sample=SymbolInfoDouble(name,SYMBOL_VOLUME_MIN), result=0;
   if(sample<=0 || !OrderCalcProfit(side,name,sample,adverse,stop,result) || result>=0) return;
   double perLot=-result/sample+RoundTripCostPerLot;
   double risk=RiskPerTrade;
   if(TradingMode==CONSERVATIVE) risk=MathMin(risk,0.25);
   if(TradingMode==BALANCED) risk=MathMin(risk,0.50);
   double budget=equity*risk/100/MathMax(1.0,s.volatility);
   budget=MathMin(budget,equity*MaxPortfolioRisk/100-e.total);
   budget=MathMin(budget,equity*MaxCorrelatedRisk/100-e.correlated);
   budget=MathMin(budget,equity-dayBase*(1-DailyLossLimit/100)-e.total);
   budget=MathMin(budget,equity-weekBase*(1-WeeklyLossLimit/100)-e.total);
   budget=MathMin(budget,equity-peak*(1-MaximumDrawdown/100)-e.total);
   if(budget<=0) return;
   double volume=NormalizeVolume(name,FixedLot>0?FixedLot:budget/perLot);
   if(volume<=0 || volume*perLot>budget+1e-8) return;
   double margin=0;
   if(!OrderCalcMargin(side,name,volume,adverse,margin) ||
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE) ||
      (AccountInfoDouble(ACCOUNT_MARGIN)+margin)*MinimumMarginLevel/100>equity) return;

   if(!trade.SetTypeFillingBySymbol(name)) return;
   ResetLastError();
   bool sent=trade.PositionOpen(name,side,volume,price,stop,target,"MVX"+IntegerToString(s.alpha));
   if(!sent || !Accepted()) {
      Print("MIDAS VX entry ",name,": ",trade.ResultRetcodeDescription()," error=",GetLastError());
      return;
   }
   double fill=trade.ResultPrice();
   if(fill>0 && (fill-price)*s.side>SlippageLimitPoints*point+point*0.001) {
      Print("MIDAS VX adverse fill beyond requested deviation ",name," requested=",price," fill=",fill);
      dayBlocked=true;
      Store(".dl"+IntegerToString(dayKey),1);
      if(!testing) GlobalVariablesFlush();
      CloseManaged(true);
   }
}

void ManageStops(const Market &m,const MqlTick &q) {
   if(PositionsTotal()==0 || (!TrailingStop && !BreakEven)) return;
   double atr[1];
   if(CopyBuffer(m.atr,0,1,1,atr)!=1 || atr[0]<=0 || atr[0]==EMPTY_VALUE) return;
   MqlRates structure[];
   if(TrailingStop && CopyRates(m.name,SignalTF,1,5,structure)!=5) return;
   for(int i=PositionsTotal()-1;i>=0;--i) {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !OwnPosition() || PositionGetString(POSITION_SYMBOL)!=m.name) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      int side=buy?1:-1;
      double open=PositionGetDouble(POSITION_PRICE_OPEN), stop=PositionGetDouble(POSITION_SL);
      double take=PositionGetDouble(POSITION_TP), bidAsk=buy?q.bid:q.ask;
      if(stop<=0 || (bidAsk-open)*side<atr[0]) continue;
      double proposed=stop;
      if(BreakEven) proposed=buy?MathMax(proposed,open):MathMin(proposed,open);
      if(TrailingStop) {
         double edge=buy?structure[0].low:structure[0].high;
         for(int j=1;j<5;++j)
            edge=buy?MathMin(edge,structure[j].low):MathMax(edge,structure[j].high);
         edge-=side*atr[0]*0.15;
         proposed=buy?MathMax(proposed,edge):MathMin(proposed,edge);
      }
      double gap=ProtectionGap(m.name);
      if(take>0 && (take-bidAsk)*side<=gap) continue;
      proposed=PriceGrid(m.name,buy?MathMin(proposed,bidAsk-gap):MathMax(proposed,bidAsk+gap),!buy);
      if(proposed<=0 || (proposed-stop)*side<SymbolInfoDouble(m.name,SYMBOL_TRADE_TICK_SIZE)*0.9) continue;
      if(!trade.PositionModify(ticket,proposed,take) || !Accepted())
         Print("MIDAS VX modify ",ticket,": ",trade.ResultRetcodeDescription());
   }
}

void SampleEquity(const datetime now,const double equity,const bool force=false) {
   if(equityFile==INVALID_HANDLE || (!force && lastExport!=0 && now-lastExport<3600)) return;
   FileWrite(equityFile,(long)now,equity,maximumObservedDrawdown);
   lastExport=now;
}

void Run() {
   datetime now=TimeCurrent();
   if(now<=0 || (!testing && !TerminalInfoInteger(TERMINAL_CONNECTED))) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(peak<=0) {
      if(equity<=0) return;
      RestoreRisk(now,equity);
   }
   bool entries=RiskGate(now,equity);
   SampleEquity(now,equity);
   if(emergency || dayBlocked || weekBlocked || !stateOK) return;
   UpdateExpectancy(now);
   for(int i=0;i<ArraySize(markets);++i) {
      MqlTick q={};
      string name=markets[i].name;
      if(!Quote(name,q) || now-q.time>60) continue;
      ManageStops(markets[i],q);
      datetime bar=iTime(name,SignalTF,0);
      if(bar<=0 || bar==markets[i].last) continue;
      if(markets[i].last==0) {
         markets[i].last=bar;
         continue;
      }
      if(!entries || !SessionOpen(name,now)) {
         markets[i].last=bar;
         continue;
      }
      Signal s={};
      if(!ReadSignal(markets[i],s)) continue;
      markets[i].last=bar;
      if(s.side!=0) {
         equity=AccountInfoDouble(ACCOUNT_EQUITY);
         if(RiskGate(now,equity)) OpenTrade(markets[i],s,q,equity);
      }
   }
}

int OnInit() {
   testing=(bool)MQLInfoInteger(MQL_TESTER);
   if(!testing && !AllowRealAccount && AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL) {
      Print("MIDAS VX real account disabled in inputs");
      return INIT_FAILED;
   }
   if(RiskPerTrade<=0 || RiskPerTrade>1 || MagicNumber==0 || DailyLossLimit<=0 ||
      WeeklyLossLimit<DailyLossLimit || MaximumDrawdown<WeeklyLossLimit || MaximumDrawdown>=100 ||
      MaximumOpenPositions<1 || MaxPortfolioRisk<=0 || MaxCorrelatedRisk<=0 ||
      EmergencyMarginLevel<=100 || MinimumMarginLevel<EmergencyMarginLevel ||
      SessionStartHour<0 || SessionStartHour>23 || SessionEndHour<0 || SessionEndHour>24 ||
      MaxSpreadATR<=0 || SpreadLimitPoints<0 || RoundTripCostPerLot<0 || FixedLot<0 ||
      StopATR<=0 || RewardMultiple<=0 || ChannelBars<8 || ChannelBars>250 ||
      TrendADX<=0 || TrendADX>=100 || EmergencyATRRatio<=1 || MinExpectancyTrades<1 ||
      ExpectancyLookbackDays<1 || ExpectancyLookbackDays>3650 || StrategyMask<1 || StrategyMask>31 ||
      PeriodSeconds(TrendTF)<=PeriodSeconds(SignalTF)) return INIT_PARAMETERS_INCORRECT;
   uint serverHash=0;
   string server=AccountInfoString(ACCOUNT_SERVER);
   for(int i=0;i<StringLen(server);++i) serverHash=31*serverHash+StringGetCharacter(server,i);
   stateKey=StringFormat("MVX.%08X.%I64d.%I64X",serverHash,AccountInfoInteger(ACCOUNT_LOGIN),MagicNumber);
   if(!testing) {
      lockFile=FileOpen(stateKey+".lock",FILE_BIN|FILE_READ|FILE_WRITE|FILE_COMMON);
      if(lockFile==INVALID_HANDLE) {
         Print("MIDAS VX coordinator lock unavailable ",GetLastError());
         return INIT_FAILED;
      }
   }
   string names[];
   int count=StringSplit(Symbols==""?_Symbol:Symbols,(ushort)44,names);
   if(count<=0 || count>32) return INIT_PARAMETERS_INCORRECT;
   for(int i=0;i<count;++i) {
      StringTrimLeft(names[i]);
      StringTrimRight(names[i]);
      if(names[i]=="" || !SymbolSelect(names[i],true)) return INIT_FAILED;
      for(int j=0;j<i;++j) if(names[j]==names[i]) return INIT_PARAMETERS_INCORRECT;
      ArrayResize(markets,i+1);
      markets[i].name=names[i];
      markets[i].last=0;
      PrintFormat("MIDAS VX %s: digits=%d tick_size=%.10f tick_value=%.8f contract=%.8f execution=%d",
                  names[i],(int)SymbolInfoInteger(names[i],SYMBOL_DIGITS),
                  SymbolInfoDouble(names[i],SYMBOL_TRADE_TICK_SIZE),
                  SymbolInfoDouble(names[i],SYMBOL_TRADE_TICK_VALUE),
                  SymbolInfoDouble(names[i],SYMBOL_TRADE_CONTRACT_SIZE),
                  (int)SymbolInfoInteger(names[i],SYMBOL_TRADE_EXEMODE));
      markets[i].atr=iATR(names[i],SignalTF,14);
      markets[i].adx=iADX(names[i],SignalTF,14);
      markets[i].trend=iMA(names[i],TrendTF,50,0,MODE_EMA,PRICE_CLOSE);
      if(markets[i].atr==INVALID_HANDLE || markets[i].adx==INVALID_HANDLE ||
         markets[i].trend==INVALID_HANDLE) return INIT_FAILED;
   }
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(SlippageLimitPoints);
   trade.SetAsyncMode(false);
   if(testing && ExportTesterData && !MQLInfoInteger(MQL_OPTIMIZATION)) {
      equityFile=FileOpen("MVX_"+ExportLabel+"_equity.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
      if(equityFile==INVALID_HANDLE) return INIT_FAILED;
      FileWrite(equityFile,"time","equity","max_drawdown_pct");
   }
   // Strategy Tester processes the chart's tick stream. A slower timer also
   // polls other symbols between chart ticks.
   if(!EventSetTimer(testing?60:1)) return INIT_FAILED;
   return INIT_SUCCEEDED;
}

void OnTick() { Run(); }
void OnTimer() { Run(); }

void OnTradeTransaction(const MqlTradeTransaction &tx,const MqlTradeRequest &request,
                        const MqlTradeResult &result) {
   if(tx.type==TRADE_TRANSACTION_DEAL_ADD) historyDirty=true;
}

double OnTester() {
   double trades=TesterStatistics(STAT_TRADES);
   if(trades<50 || maximumObservedDrawdown>MaximumDrawdown ||
      TesterStatistics(STAT_PROFIT_FACTOR)<1.2 || TesterStatistics(STAT_PROFIT)<=0) return -1;
   return TesterStatistics(STAT_RECOVERY_FACTOR)*MathSqrt(trades);
}

void ExportDeals() {
   if(!HistorySelect(0,TimeCurrent())) return;
   int fd=FileOpen("MVX_"+ExportLabel+"_deals.csv",FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(fd==INVALID_HANDLE) {
      Print("MIDAS VX deal export failed ",GetLastError());
      return;
   }
   FileWrite(fd,"time","position_id","symbol","entry","volume","profit","swap","commission","fee","comment");
   for(int i=0;i<HistoryDealsTotal();++i) {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      FileWrite(fd,HistoryDealGetInteger(ticket,DEAL_TIME),HistoryDealGetInteger(ticket,DEAL_POSITION_ID),
                HistoryDealGetString(ticket,DEAL_SYMBOL),HistoryDealGetInteger(ticket,DEAL_ENTRY),
                HistoryDealGetDouble(ticket,DEAL_VOLUME),HistoryDealGetDouble(ticket,DEAL_PROFIT),
                HistoryDealGetDouble(ticket,DEAL_SWAP),HistoryDealGetDouble(ticket,DEAL_COMMISSION),
                HistoryDealGetDouble(ticket,DEAL_FEE),HistoryDealGetString(ticket,DEAL_COMMENT));
   }
   FileClose(fd);
}

void OnDeinit(const int reason) {
   EventKillTimer();
   if(equityFile!=INVALID_HANDLE) {
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(peak>0) maximumObservedDrawdown=MathMax(maximumObservedDrawdown,100*(peak-equity)/peak);
      SampleEquity(TimeCurrent(),equity,true);
      FileClose(equityFile);
      ExportDeals();
   }
   for(int i=0;i<ArraySize(markets);++i) {
      if(markets[i].atr!=INVALID_HANDLE) IndicatorRelease(markets[i].atr);
      if(markets[i].adx!=INVALID_HANDLE) IndicatorRelease(markets[i].adx);
      if(markets[i].trend!=INVALID_HANDLE) IndicatorRelease(markets[i].trend);
   }
   if(lockFile!=INVALID_HANDLE) FileClose(lockFile);
}
