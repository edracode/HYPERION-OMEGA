#property strict
#property version "0.19"
#include <Trade/Trade.mqh>

enum Profile { Survival, Growth, Extreme };
enum VolumePolicy { Adaptive, Fractional, Volatility, EquityScaled, DrawdownResponsive, Sublinear, AntiMartingale, MarginConstrained };
input ulong Magic=76132019;
input Profile Mode=Growth;
input VolumePolicy Sizing=Adaptive;
input bool StartEnabled=true;
input bool MaintainOnePosition=true;
input bool MartingaleEnabled=true;
input bool Dashboard=true;
input int PanelX=12;
input int PanelY=8;
input int ScanBatchSize=16;
input bool TesterScanAllBrokerSymbols=true;
input int TimerMs=250;
input double InitialRiskPct=0.45;
input double BasketRiskPct=1.2;
input double PortfolioRiskPct=3.0;
input double DailyDrawdownPct=5;
input double TotalDrawdownPct=15;
input double MinMarginLevel=375.0;
input double MinFreeEquityPct=42.0;
input double MaxBasketLots=1.0;
input double BaseGridPoints=10;
input double LotMultiplier=1.15;
input bool ATRGridScaling=true;
input double MaxSpreadATR=0.25;
input double MaxGapATR=2.0;
input double CommissionRoundTurnPerLot=0;
input double SignalThreshold=0.30;
input int CooldownSeconds=3;
input int QuoteAgeSeconds=8;
input int TradeDeviationPoints=15;

struct Market
{
   string symbol;
   int atrHandle;
   long stamp;
   long evaluatedStamp;
   double evaluatedBid,evaluatedAsk;
   double lastBid,lastAsk,mid,atr,atrRatio,trend,momentum,meanRevert,structure,micro,score,spreadMean,shock;
   double returns[60];
   datetime returnTimes[60];
   bool returnsReady;
   string regime,feed,entryNote;
   datetime retryFeed;
   datetime lastEntryCheck;
   int count,layers,side,basketSide;
   double lots,firstLayerLots,lastFill,average,net,stress,breakeven,peak;
   datetime opened,lastAction;
   bool foreign,historyOK,mixedSides;
};
Market market[];
CTrade trade;
Profile profile;
bool enabled,averaging,halted,hedging,working,dirty,exitAmbiguous,entryAmbiguous;
string key,panel="HYDRA_VX_",status="STARTUP",haltReason="";
int lockHandle=INVALID_HANDLE, selected=0, positionCount=0;
int scanCursor=0, syncCursor=0;
string lastEntryStatus="";
bool allClosing=false;
string closingSymbol="";
int closingSide=0;
double peakEquity,viewPeakEquity,dayEquity,dayDD,totalDD,portfolioStress;
double daily,weekly,monthly,totalNet,dailyView,monthlyView;
long profitResetMsc=0,lastProfitDealMsc=0;
string panelNotice="";
ulong noticeUntil=0;
datetime dayKey,lastDashboard,historyRefresh;
ulong latencyMs;

double Clamp(double value,double low,double high){ return MathMax(low,MathMin(high,value)); }
datetime DayStart(datetime now){ return (datetime)((long)now-(long)now%86400); }
bool Persist(string suffix,double value)
{
   if(MQLInfoInteger(MQL_TESTER)) return true;
   if(GlobalVariableSet(key+suffix,value)==0)
   {
      halted=true;
      enabled=false;
      Print("Cannot persist state ",suffix," error ",GetLastError());
      return false;
   }
   return true;
}
double Stored(string suffix,double fallback)
{
   if(MQLInfoInteger(MQL_TESTER) || !GlobalVariableCheck(key+suffix)) return fallback;
   return GlobalVariableGet(key+suffix);
}
void Latch(string reason)
{
   if(!halted || haltReason=="") Print("Hydra-Vx emergency: ",reason);
   if(haltReason!="") return;
   haltReason=reason;
   halted=true;
   enabled=false;
   status=reason;
   Persist(".halt",1);
   if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
}
double ProfileFactor()
{
   if(profile==Growth) return 1.25;
   if(profile==Extreme) return 1.60;
   return 1.0;
}
double PriceTick(string symbol,double price,int direction)
{
   double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) return 0;
   double units=price/tick;
   return NormalizeDouble((direction<0 ? MathFloor(units+1e-8) : MathCeil(units-1e-8))*tick,
                          (int)SymbolInfoInteger(symbol,SYMBOL_DIGITS));
}
double VolumeFloor(string symbol,double volume)
{
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   if(step<=0 || volume<minimum) return 0;
   double capped=MathMin(volume,SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX));
   return NormalizeDouble(MathFloor(capped/step+1e-9)*step,8);
}
int MarketIndex(string symbol,int basketSide)
{
   for(int i=0;i<ArraySize(market);i++) if(market[i].symbol==symbol && market[i].basketSide==basketSide) return i;
   return -1;
}
int RegisterMarket(string symbol,int basketSide)
{
   if(symbol=="") return -1;
   int existing=MarketIndex(symbol,basketSide);
   if(existing>=0) return existing;
   int index=ArrayResize(market,ArraySize(market)+1,64)-1;
   if(index<0) return -1;
   market[index].symbol=symbol;
   market[index].basketSide=basketSide;
   market[index].atrHandle=INVALID_HANDLE;
   market[index].historyOK=true;
   market[index].regime="WARMUP";
   market[index].feed="Waiting for scan";
   return index;
}
bool RegisterSymbol(string symbol)
{
   if(!hedging) return RegisterMarket(symbol,0)>=0;
   return RegisterMarket(symbol,1)>=0 && RegisterMarket(symbol,-1)>=0;
}
int SelectedPositionSide()
{
   return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
}
bool MatchesBasket(int basketSide,int positionSide)
{
   return basketSide==0 || basketSide==positionSide;
}
void Discover(int budget)
{
   // Keep broker names verbatim, including account-specific suffixes.
   int total=SymbolsTotal(false);
   if(total<=0) return;
   for(int i=0;i<budget && syncCursor<total;i++,syncCursor++)
   {
      string symbol=SymbolName(syncCursor,false);
      if(symbol=="") continue;
      if(!RegisterSymbol(symbol)) Latch("SYMBOL SCAN FAILED");
   }
}
bool Sample(Market &m)
{
   datetime now=MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeLocal();
   if(m.atrHandle==INVALID_HANDLE)
   {
      if(now<m.retryFeed) return false;
      if(!SymbolSelect(m.symbol,true) || (m.atrHandle=iATR(m.symbol,PERIOD_M1,14))==INVALID_HANDLE)
      {
         m.feed="Symbol feed unavailable";
         m.retryFeed=now+10;
         return false;
      }
   }
   MqlTick q;
   if(!SymbolInfoTick(m.symbol,q) || q.bid<=0 || q.ask<q.bid || q.time_msc<=0)
   {
      m.feed="Waiting for broker quote";
      return false;
   }
   datetime clock=MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeTradeServer();
   if(clock<=0 || clock-q.time>QuoteAgeSeconds)
   {
      m.feed="Quote stale / market may be closed";
      return false;
   }
   m.feed="Quote ready";
   long mode=0,custom=0;
   if(SymbolInfoInteger(m.symbol,SYMBOL_TRADE_MODE,mode) && SymbolInfoInteger(m.symbol,SYMBOL_CUSTOM,custom) &&
      (custom || mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY))
   {
      m.feed="Broker entry unavailable";
      return false;
   }
   if(q.time_msc==m.stamp && q.bid==m.lastBid && q.ask==m.lastAsk) return m.atr>0;
   MqlRates bars[];
   double atr[];
   ArraySetAsSeries(bars,true);
   ArraySetAsSeries(atr,true);
   if(CopyRates(m.symbol,PERIOD_M1,1,61,bars)!=61 || CopyBuffer(m.atrHandle,0,1,31,atr)!=31 || atr[0]<=0)
   {
      m.feed="Loading M1 history";
      return false;
   }
   double base=0;
   for(int i=1;i<=30;i++) base+=atr[i]/30;
   if(base<=0) return false;
   m.atr=atr[0];
   m.atrRatio=m.atr/base;
   double mid=(q.bid+q.ask)/2, spread=q.ask-q.bid;
   double center=0,fast=0,fastWeight=0,high=bars[0].high,low=bars[0].low;
   for(int i=0;i<60;i++)
   {
      if(bars[i+1].close<=0) return false;
      m.returns[i]=bars[i].close/bars[i+1].close-1;
      m.returnTimes[i]=bars[i].time;
      if(i<20) center+=bars[i].close/20;
      if(i<8)
      {
         fast+=bars[i].close*(8-i);
         fastWeight+=8-i;
      }
      if(i<12)
      {
         high=MathMax(high,bars[i].high);
         low=MathMin(low,bars[i].low);
      }
   }
   m.returnsReady=true;
   m.trend=Clamp((fast/fastWeight-center)/m.atr,-1,1);
   m.momentum=Clamp((mid-bars[4].close)/(2*m.atr),-1,1);
   m.meanRevert=Clamp((center-mid)/(1.8*m.atr),-1,1);
   m.structure=Clamp((2*mid-high-low)/MathMax(high-low,m.atr),-1,1);
   MqlTick ticks[];
   int copied=CopyTicks(m.symbol,ticks,COPY_TICKS_INFO,0,32);
   int moves=0, signedMoves=0;
   for(int i=1;i<copied;i++)
   {
      if(ticks[i].time_msc>q.time_msc || q.time_msc-ticks[i-1].time_msc>10000) continue;
      double delta=ticks[i].bid+ticks[i].ask-ticks[i-1].bid-ticks[i-1].ask;
      if(delta==0) continue;
      signedMoves+=(delta>0 ? 1 : -1);
      moves++;
   }
   m.micro=(moves>=5 ? (double)signedMoves/moves : 0);
   m.shock=MathAbs(mid-bars[0].close)/m.atr;
   double baseline=m.spreadMean;
   m.spreadMean=(baseline>0 ? 0.98*baseline+0.02*spread : spread);
   if(spread>MaxSpreadATR*m.atr || (baseline>0 && spread>2.5*baseline)) m.regime="UNSTABLE LIQUIDITY";
   else if(m.shock>MaxGapATR) m.regime="PRICE SHOCK";
   else if(m.atrRatio>1.8) m.regime="HIGH VOLATILITY";
   else if(mid>high || mid<low) m.regime="BREAKOUT";
   else if(m.trend*m.momentum<-0.35) m.regime="REVERSAL";
   else if(m.atrRatio<0.65) m.regime="LOW VOLATILITY";
   else if(m.trend>0.45) m.regime="TREND UP";
   else if(m.trend<-0.45) m.regime="TREND DOWN";
   else m.regime="RANGE";
   double directional=0.55*m.trend+0.30*m.momentum+0.15*m.structure;
   m.score=(m.regime=="RANGE" || m.regime=="LOW VOLATILITY")
           ? 0.75*m.meanRevert+0.25*m.micro : 0.85*directional+0.15*m.micro;
   m.mid=mid;
   m.lastBid=q.bid;
   m.lastAsk=q.ask;
   m.stamp=q.time_msc;
   return true;
}
// Hypothetical adverse move for sizing only; no price level is sent as an SL.
double StressPrice(Market &m,int side,double mark)
{
   double point=SymbolInfoDouble(m.symbol,SYMBOL_POINT);
   double distance=MathMax(m.atr,point*BaseGridPoints)*(2.4+MaxGapATR);
   distance+=2*MathMax(0,m.lastAsk-m.lastBid);
   double price=mark-side*distance;
   if(side>0) price=MathMax(SymbolInfoDouble(m.symbol,SYMBOL_TRADE_TICK_SIZE),price);
   return PriceTick(m.symbol,price,-side);
}
bool PositionRisk(string symbol,int side,double lots,double from,double stop,double &loss)
{
   double cash=0;
   if(stop<=0 || from<=0 || !OrderCalcProfit(side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
      symbol,lots,from,stop,cash)) return false;
   loss=MathMax(0,-cash)+CommissionRoundTurnPerLot*lots;
   return true;
}
void Reconcile(Market &m)
{
   int oldSide=m.side;
   m.count=0; m.layers=0; m.side=0; m.lots=0; m.net=0; m.stress=0; m.average=0;
   m.lastFill=0; m.firstLayerLots=0; m.opened=0; m.foreign=false; m.historyOK=true; m.mixedSides=false; m.breakeven=0;
   long lastDealTime=0;
   ulong lastDeal=0,firstOrder=0,firstDeal=0;
   long firstDealTime=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=m.symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=Magic)
      {
         if(!hedging) m.foreign=true;
         continue;
      }
      int side=SelectedPositionSide();
      if(!MatchesBasket(m.basketSide,side)) continue;
      double vol=PositionGetDouble(POSITION_VOLUME), entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double profit=PositionGetDouble(POSITION_PROFIT);
      double carry=PositionGetDouble(POSITION_SWAP);
      long id=PositionGetInteger(POSITION_IDENTIFIER);
      if(m.side!=0 && m.side!=side)
      {
         m.historyOK=false;
         m.mixedSides=true;
      }
      m.side=side;
      m.count++;
      m.lots+=vol;
      m.average+=entry*vol;
      m.net+=profit+carry-CommissionRoundTurnPerLot*vol/2;
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      if(m.opened==0 || opened<m.opened) m.opened=opened;
      double mark=PositionGetDouble(POSITION_PRICE_CURRENT), loss=0;
      double worst=StressPrice(m,side,mark);
      if(!PositionRisk(m.symbol,side,vol,mark,worst,loss)) m.historyOK=false;
      else m.stress+=loss;
      if(!HistorySelectByPosition((ulong)id))
      {
         m.historyOK=false;
         continue;
      }
      ulong previousOrder=0;
      int positionLayers=0;
      for(int j=0;j<HistoryDealsTotal();j++)
      {
         ulong deal=HistoryDealGetTicket(j);
         if(deal==0) continue;
         long dealType=HistoryDealGetInteger(deal,DEAL_TYPE);
         if(dealType!=DEAL_TYPE_BUY && dealType!=DEAL_TYPE_SELL) continue;
         if(!hedging && (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=Magic) m.foreign=true;
         m.net+=HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE);
         long kind=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(kind==DEAL_ENTRY_INOUT) m.historyOK=false;
         if(kind!=DEAL_ENTRY_IN)
         {
            m.net+=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP);
            continue;
         }
         ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(positionLayers==0 || order!=previousOrder) positionLayers++;
         previousOrder=order;
         long stamp=HistoryDealGetInteger(deal,DEAL_TIME_MSC);
         double dealLots=HistoryDealGetDouble(deal,DEAL_VOLUME);
         if(order!=0 && order==firstOrder)
            m.firstLayerLots+=dealLots;
         else if(firstDeal==0 || stamp<firstDealTime || (stamp==firstDealTime && deal<firstDeal))
         {
            firstOrder=order;
            firstDeal=deal;
            firstDealTime=stamp;
            m.firstLayerLots=dealLots;
         }
         if(stamp>lastDealTime || (stamp==lastDealTime && deal>lastDeal))
         {
            lastDealTime=stamp;
            lastDeal=deal;
            m.lastFill=HistoryDealGetDouble(deal,DEAL_PRICE);
         }
      }
      m.layers+=positionLayers;
   }
   if(m.lots>0)
   {
      m.average/=m.lots;
      double tick=SymbolInfoDouble(m.symbol,SYMBOL_TRADE_TICK_SIZE), change=0;
      if(tick>0 && m.mid>0 && OrderCalcProfit(m.side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
         m.symbol,m.lots,m.side>0 ? m.lastBid : m.lastAsk,(m.side>0 ? m.lastBid : m.lastAsk)+m.side*tick,change)
         && change>0)
         m.breakeven=(m.side>0 ? m.lastBid : m.lastAsk)-m.side*m.net*tick/change;
      if(m.layers==0 || m.firstLayerLots<=0 || m.lastFill<=0) m.historyOK=false;
      m.peak=MathMax(m.peak,m.net);
   }
   else
   {
      if(oldSide!=0) m.lastAction=TimeCurrent();
      m.peak=0;
   }
}
bool Outstanding(string symbol)
{
   for(int i=0;i<OrdersTotal();i++)
      if(OrderGetTicket(i)!=0 && OrderGetString(ORDER_SYMBOL)==symbol &&
         (!hedging || (ulong)OrderGetInteger(ORDER_MAGIC)==Magic)) return true;
   return false;
}
string PermissionIssue()
{
   if(!MQLInfoInteger(MQL_TESTER) && !TerminalInfoInteger(TERMINAL_CONNECTED)) return "Broker disconnected";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return "Enable Algo Trading in MT5";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return "Enable Allow Algo Trading in EA";
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return "Account blocks automated trades";
   return "";
}
bool ExecutionAllowed()
{
   return PermissionIssue()=="";
}
bool RiskGuardTriggered()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double margin=AccountInfoDouble(ACCOUNT_MARGIN);
   return equity<=0 || dayDD>=DailyDrawdownPct || totalDD>=TotalDrawdownPct ||
      (margin>0 && 100*equity/margin<MinMarginLevel*0.65);
}
void Guardian()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   datetime today=DayStart(TimeCurrent());
   if(today>0 && today!=dayKey)
   {
      dayKey=today;
      dayEquity=equity;
      Persist(".dayeq",dayEquity);
      Persist(".day",(double)dayKey);
   }
   if(equity>peakEquity)
   {
      peakEquity=equity;
      Persist(".peak",peakEquity);
   }
   if(equity>viewPeakEquity)
   {
      viewPeakEquity=equity;
      Persist(".viewpeak",viewPeakEquity);
   }
   dayDD=(dayEquity>0 ? 100*(1-equity/dayEquity) : 100);
   totalDD=(peakEquity>0 ? 100*(1-equity/peakEquity) : 100);
   if(RiskGuardTriggered()) Latch("EQUITY / MARGIN GUARD");
}
double Correlation(Market &a,Market &b)
{
   if(!a.returnsReady || !b.returnsReady) return 1.0;
   double x=0,y=0,xx=0,yy=0,xy=0;
   int j=0,n=0;
   for(int i=0;i<60 && j<60;i++)
   {
      while(j<60 && b.returnTimes[j]>a.returnTimes[i]) j++;
      if(j>=60 || b.returnTimes[j]!=a.returnTimes[i]) continue;
      double u=a.returns[i], v=b.returns[j];
      x+=u; y+=v; xx+=u*u; yy+=v*v; xy+=u*v;
      n++;
   }
   if(n<30) return 1.0;
   double den=MathSqrt(MathMax(0,xx-x*x/n)*MathMax(0,yy-y*y/n));
   return den>0 ? Clamp((xy-x*y/n)/den,-1,1) : 1.0;
}
double GridFactor(int nextLayer)
{
   if(nextLayer<=2) return 1.0;
   if(nextLayer==3) return 1.5;
   if(nextLayer==4) return 2.25;
   if(nextLayer==5) return 3.375;
   return 6.75;
}
double LotFactor(Market &m)
{
   return Clamp(LotMultiplier*ProfileFactor()-0.18*MathMax(0,m.atrRatio-1)-
                0.25*MathMax(0,-m.side*m.trend)-0.025*MathMax(0,totalDD),0.65,1.30);
}
double GridDistance(Market &m)
{
   double point=SymbolInfoDouble(m.symbol,SYMBOL_POINT);
   double tick=SymbolInfoDouble(m.symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0 || m.atr<=0) return 0;
   double base=MathMax(BaseGridPoints*point,ATRGridScaling ? 0.35*m.atr : tick);
   return MathCeil(base*GridFactor(m.layers+1)/tick-1e-9)*tick;
}
bool NeedsExposure()
{
   return MaintainOnePosition && positionCount==0;
}
bool CanOpen(Market &m)
{
   if(!enabled || halted || allClosing || closingSymbol!="" || m.foreign ||
      !m.historyOK || !ExecutionAllowed()) return false;
   long mode=0,custom=0;
   if(!SymbolInfoInteger(m.symbol,SYMBOL_TRADE_MODE,mode) ||
      !SymbolInfoInteger(m.symbol,SYMBOL_CUSTOM,custom) || custom ||
      mode==SYMBOL_TRADE_MODE_DISABLED || mode==SYMBOL_TRADE_MODE_CLOSEONLY) return false;
   if(m.regime=="UNSTABLE LIQUIDITY" || m.regime=="PRICE SHOCK" || m.atrRatio>2.5) return false;
   int cooldown=NeedsExposure() && m.count==0 ? 2 : CooldownSeconds;
   if(TimeCurrent()-m.lastAction<cooldown || TimeCurrent()-m.lastEntryCheck<2 || Outstanding(m.symbol)) return false;
   return true;
}
bool FillPolicy(string symbol,ENUM_ORDER_TYPE_FILLING &policy)
{
   long flags=SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
   if((flags&SYMBOL_FILLING_FOK)!=0) policy=ORDER_FILLING_FOK;
   else if((flags&SYMBOL_FILLING_IOC)!=0) policy=ORDER_FILLING_IOC;
   else if(SymbolInfoInteger(symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET) policy=ORDER_FILLING_RETURN;
   else return false;
   return true;
}
double StopoutFloor(double margin)
{
   double stopout=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   if(AccountInfoInteger(ACCOUNT_MARGIN_SO_MODE)==ACCOUNT_STOPOUT_MODE_PERCENT)
      return margin*MathMax(MinMarginLevel,stopout+100)/100;
   return MathMax(margin*MinMarginLevel/100,margin+MathMax(0,stopout));
}
bool Definitive(uint code)
{
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL ||
      code==TRADE_RETCODE_REQUOTE || code==TRADE_RETCODE_REJECT ||
      code==TRADE_RETCODE_INVALID || code==TRADE_RETCODE_INVALID_VOLUME ||
      code==TRADE_RETCODE_INVALID_PRICE || code==TRADE_RETCODE_INVALID_STOPS ||
      code==TRADE_RETCODE_TRADE_DISABLED || code==TRADE_RETCODE_MARKET_CLOSED ||
      code==TRADE_RETCODE_NO_MONEY || code==TRADE_RETCODE_PRICE_CHANGED ||
      code==TRADE_RETCODE_PRICE_OFF || code==TRADE_RETCODE_INVALID_FILL ||
      code==TRADE_RETCODE_POSITION_CLOSED;
}
double OppositeBasketLots(string symbol,int side)
{
   if(!hedging) return 0;
   double lots=0;
   for(int i=0;i<PositionsTotal();i++)
   {
      if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic || SelectedPositionSide()!=-side) continue;
      lots+=PositionGetDouble(POSITION_VOLUME);
   }
   return NormalizeDouble(lots,8);
}
void Submit(Market &m,int side)
{
   if(!CanOpen(m)) return;
   m.lastEntryCheck=TimeCurrent();
   m.entryNote="Checking broker and risk";
   for(int i=0;i<ArraySize(market);i++)
      if(market[i].count>0 && (!market[i].historyOK || market[i].foreign))
      {
         m.entryNote="Open position reconciliation pending";
         return;
      }
   for(int i=0;i<OrdersTotal();i++)
      if(OrderGetTicket(i)!=0 && (ulong)OrderGetInteger(ORDER_MAGIC)==Magic)
      {
         m.entryNote="Broker order still pending";
         return;
      }
   long mode=SymbolInfoInteger(m.symbol,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL &&
      !(side>0 && mode==SYMBOL_TRADE_MODE_LONGONLY) &&
      !(side<0 && mode==SYMBOL_TRADE_MODE_SHORTONLY)) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double price=side>0 ? m.lastAsk : m.lastBid;
   double mark=side>0 ? m.lastBid : m.lastAsk;
   double point=SymbolInfoDouble(m.symbol,SYMBOL_POINT);
   if(equity<=0 || point<=0) return;
   double worst=StressPrice(m,side,mark), unit=0;
   double sample=SymbolInfoDouble(m.symbol,SYMBOL_VOLUME_MIN);
   if(sample<=0 || !PositionRisk(m.symbol,side,sample,price+side*TradeDeviationPoints*point,worst,unit) || unit<=0)
      return;
   unit/=sample;
   double correlated=0;
   for(int i=0;i<ArraySize(market);i++)
   {
      if(market[i].count==0 || market[i].symbol==m.symbol) continue;
      if(!market[i].historyOK || market[i].foreign) return;
      correlated+=market[i].stress*MathMax(0,Correlation(m,market[i])*side*market[i].side);
   }
   double budget=equity*InitialRiskPct*ProfileFactor()/100;
   double base=m.count>0 ? m.firstLayerLots : budget/unit;
   double layers=(double)m.layers;
   double raw=base;
   switch(Sizing)
   {
      case Adaptive: raw*=MathPow(LotFactor(m),MathMin(layers,1024.0)); break;
      case Fractional: raw/=1+0.25*layers; break;
      case Volatility: raw/=MathMax(1,m.atrRatio); break;
      case EquityScaled: raw*=Clamp(equity/peakEquity,0.25,1); break;
      case DrawdownResponsive: raw*=Clamp(1-totalDD/TotalDrawdownPct,0,1); break;
      case Sublinear: raw*=MathSqrt(1+0.20*layers); break;
      case AntiMartingale: raw*=Clamp(1+daily/equity,0.50,1.15); break;
      case MarginConstrained: raw*=Clamp(AccountInfoDouble(ACCOUNT_MARGIN_FREE)/equity,0,1); break;
   }
   // Current equity already reflects floating P/L. Reserve only the forward stress loss.
   double basketRoom=equity*BasketRiskPct/100-m.stress;
   double portfolioRoom=equity*PortfolioRiskPct/100-portfolioStress-0.5*correlated;
   double remaining=MathMin(basketRoom,portfolioRoom);
   double volumeCap=MathMin(remaining/unit,MaxBasketLots-m.lots);
   double matched=m.count==0 ? OppositeBasketLots(m.symbol,side) : 0;
   double lots=0;
   if(matched>0)
   {
      lots=VolumeFloor(m.symbol,matched);
      if(lots<sample || MathAbs(lots-matched)>1e-8)
      {
         m.entryNote="1:1 blocked: broker volume limit/step";
         return;
      }
      if(lots>volumeCap+1e-8)
      {
         m.entryNote="1:1 needs "+DoubleToString(lots,8)+" lots; cap "+
            DoubleToString(MathMax(0,volumeCap),8);
         return;
      }
   }
   else
   {
      if((NeedsExposure() || m.count>0) && raw<sample && sample*unit<=equity*0.01)
         raw=sample;
      lots=VolumeFloor(m.symbol,MathMin(raw,volumeCap));
   }
   if(lots<sample)
   {
      m.entryNote=(basketRoom<=portfolioRoom ? "Basket risk" : "Portfolio risk")+
         ": need "+Money(sample*unit)+"; room "+Money(MathMax(0,remaining));
      if(MaxBasketLots-m.lots<sample) m.entryNote="Basket lot cap below broker minimum";
      else if(remaining>=sample*unit && raw<sample) m.entryNote="Calculated lot below broker minimum";
      return;
   }
   MqlTradeRequest request={};
   MqlTradeCheckResult check={};
   MqlTradeResult result={};
   if(!FillPolicy(m.symbol,request.type_filling))
   {
      m.entryNote="Broker filling policy unavailable";
      return;
   }
   if(matched>0)
   {
      long execution=SymbolInfoInteger(m.symbol,SYMBOL_TRADE_EXEMODE);
      long filling=SymbolInfoInteger(m.symbol,SYMBOL_FILLING_MODE);
      if((filling&SYMBOL_FILLING_FOK)==0 &&
         execution!=SYMBOL_TRADE_EXECUTION_REQUEST && execution!=SYMBOL_TRADE_EXECUTION_INSTANT)
      {
         m.entryNote="1:1 blocked: broker FOK unavailable";
         return;
      }
      request.type_filling=ORDER_FILLING_FOK;
   }
   request.action=TRADE_ACTION_DEAL;
   request.symbol=m.symbol;
   request.magic=Magic;
   request.type=(side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   request.price=price;
   request.volume=lots;
   request.deviation=(ulong)TradeDeviationPoints;
   request.sl=0;
   datetime basketTime=(m.opened>0 ? m.opened : TimeCurrent());
   request.comment="VIO.E."+IntegerToString((long)basketTime)+"."+IntegerToString(m.layers+1);
   double increment=0;
   if(!OrderCalcMargin(request.type,m.symbol,lots,price,increment) || !OrderCheck(request,check))
   {
      m.entryNote="OrderCheck "+IntegerToString((long)check.retcode);
      Print("Hydra-Vx preflight ",m.symbol," retcode ",check.retcode," ",check.comment);
      m.lastAction=TimeCurrent();
      return;
   }
   double margin=MathMax(check.margin,AccountInfoDouble(ACCOUNT_MARGIN)+increment);
   double stressed=MathMin(equity,check.equity)-portfolioStress-lots*unit;
   if(stressed<StopoutFloor(margin) || stressed-margin<equity*MinFreeEquityPct/100 ||
      check.margin_free<equity*MinFreeEquityPct/100)
   {
      m.entryNote="Margin buffer blocked order";
      return;
   }
   if(!Persist(".intent",(double)TimeCurrent()) || halted) return;
   entryAmbiguous=true;
   if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
   m.lastAction=TimeCurrent();
   ulong started=GetTickCount64();
   bool sent=OrderSend(request,result);
   latencyMs=GetTickCount64()-started;
   m.entryNote="Trade server "+IntegerToString((long)result.retcode);
   Print("Hydra-Vx entry ",m.symbol," layer ",m.layers+1," signed score ",m.score,
         " stressed equity ",stressed," stopout floor ",StopoutFloor(margin),
         " sent ",sent," retcode ",result.retcode," order ",result.order," deal ",result.deal," ",result.comment);
   if(!Definitive(result.retcode))
   {
      Latch("ORDER RESULT UNCERTAIN");
      return;
   }
   if(matched>0 && result.retcode==TRADE_RETCODE_DONE_PARTIAL)
   {
      Latch("1:1 order partially filled: review execution");
      return;
   }
   if(result.retcode==TRADE_RETCODE_DONE || result.retcode==TRADE_RETCODE_DONE_PARTIAL)
   {
      int oldLayers=m.layers;
      Reconcile(m);
      if(!m.historyOK || m.layers<=oldLayers || (matched>0 && MathAbs(m.lots-matched)>1e-8))
      {
         Latch("DEAL RECONCILIATION REQUIRED");
         return;
      }
   }
   if(Persist(".intent",0)) entryAmbiguous=false;
   if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
}
bool CloseOne(Market &m)
{
   if(m.foreign || Outstanding(m.symbol) || !ExecutionAllowed()) return false;
   if(TimeCurrent()-m.lastAction<2) return false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=m.symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic ||
         !MatchesBasket(m.basketSide,SelectedPositionSide())) continue;
      if(!trade.SetTypeFillingBySymbol(m.symbol)) return false;
      double held=PositionGetDouble(POSITION_VOLUME);
      if(!Persist(".exitambiguous",1)) return false;
      if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
      m.lastAction=TimeCurrent();
      ulong started=GetTickCount64();
      bool sent=trade.PositionClose(ticket,(ulong)TradeDeviationPoints);
      latencyMs=GetTickCount64()-started;
      uint code=trade.ResultRetcode();
      Print("Hydra-Vx exit ",ticket," retcode ",code," ",trade.ResultRetcodeDescription());
      if(!Definitive(code))
      {
         exitAmbiguous=true;
         Persist(".exitambiguous",1);
         Latch("EXIT RESULT UNCERTAIN");
      }
      else
      {
         bool executed=code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL;
         if(executed && PositionSelectByTicket(ticket) &&
            PositionGetDouble(POSITION_VOLUME)>=held-1e-9)
         {
            exitAmbiguous=true;
            Latch("EXIT RECONCILIATION REQUIRED");
            return false;
         }
         Persist(".exitambiguous",0);
         if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
      }
      return sent && (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL);
   }
   return false;
}
void ManagedExit(Market &m,bool sampled)
{
   if(m.count==0 || m.foreign || exitAmbiguous) return;
   if(allClosing || (closingSymbol==m.symbol && closingSide==m.basketSide))
   {
      CloseOne(m);
      return;
   }
   // Automatic exits are available only while the tracked basket is profitable.
   if(!sampled || !m.historyOK || m.net<=0 || m.atr<=0) return;
   double target=0;
   double mark=m.side>0 ? m.lastBid : m.lastAsk;
   bool targetOK=OrderCalcProfit(m.side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,m.symbol,m.lots,
                                mark,mark+m.side*0.48*m.atr,target) && target>0;
   bool trailing=targetOK && m.peak>=target*0.65 && m.net<m.peak*0.45;
   if(targetOK && (m.net>=target || trailing)) CloseOne(m);
}
bool EligibleSignal(Market &m,int &side,double &rank)
{
   if(!CanOpen(m)) return false;
   if(m.evaluatedStamp==m.stamp && m.evaluatedBid==m.lastBid && m.evaluatedAsk==m.lastAsk) return false;
   double friction=(m.lastAsk-m.lastBid)/m.atr;
   rank=MathAbs(m.score)-friction;
   side=(m.score>0 ? 1 : -1);
   double threshold=SignalThreshold/ProfileFactor();
   if(m.count==0)
   {
      long mode=SymbolInfoInteger(m.symbol,SYMBOL_TRADE_MODE);
      if(mode==SYMBOL_TRADE_MODE_LONGONLY) side=1;
      if(mode==SYMBOL_TRADE_MODE_SHORTONLY) side=-1;
      rank=side*m.score-friction;
      if(m.basketSide!=0 && m.basketSide!=side) return false;
      return NeedsExposure() || rank>=threshold;
   }
   if(!averaging || m.net>=0 || m.side==0) return false;
   side=m.side;
   long mode=SymbolInfoInteger(m.symbol,SYMBOL_TRADE_MODE);
   if(mode!=SYMBOL_TRADE_MODE_FULL &&
      !(side>0 && mode==SYMBOL_TRADE_MODE_LONGONLY) &&
      !(side<0 && mode==SYMBOL_TRADE_MODE_SHORTONLY)) return false;
   // Give eligible additions priority over opening baskets on other symbols.
   rank=2+side*m.score-friction;
   double distance=GridDistance(m);
   double executable=(side>0 ? m.lastAsk : m.lastBid);
   return distance>0 && (m.lastFill-executable)*side>=distance;
}
bool ProfitHistory(bool refresh=false)
{
   datetime now=TimeCurrent();
   if(!refresh && !dirty && now-historyRefresh<30) return true;
   if(now<=0 || !HistorySelect(0,now)) return false;
   dirty=false;
   historyRefresh=now;
   MqlDateTime dt;
   TimeToStruct(now,dt);
   datetime today=DayStart(now);
   datetime week=today-((dt.day_of_week+6)%7)*86400;
   dt.day=1; dt.hour=0; dt.min=0; dt.sec=0;
   datetime month=StructToTime(dt);
   daily=0; weekly=0; monthly=0; totalNet=0;
   dailyView=0; monthlyView=0; lastProfitDealMsc=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0 || (ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=Magic) continue;
      double net=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+
         HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE);
      datetime at=(datetime)HistoryDealGetInteger(ticket,DEAL_TIME);
      long msc=HistoryDealGetInteger(ticket,DEAL_TIME_MSC);
      if(msc<=0) msc=(long)at*1000;
      if(msc>lastProfitDealMsc) lastProfitDealMsc=msc;
      if(msc>profitResetMsc)
      {
         if(at>=today) dailyView+=net;
         if(at>=month) monthlyView+=net;
      }
      totalNet+=net;
      if(at>=today) daily+=net;
      if(at>=week) weekly+=net;
      if(at>=month) monthly+=net;
   }
   return true;
}
void Feedback(string message)
{
   panelNotice=message;
   noticeUntil=GetTickCount64()+5000;
   Print("Hydra-Vx panel: ",message);
}
void ToggleEntries()
{
   if(enabled && !halted)
   {
      enabled=false;
      panelNotice="";
      return;
   }
   if(allClosing || closingSymbol!="") { Feedback("Start blocked: closing positions"); return; }
   string issue=PermissionIssue();
   if(issue!="") { Feedback(issue); return; }
   Guardian();
   if(RiskGuardTriggered()) { Feedback("Start blocked: drawdown / margin guard"); return; }
   if(entryAmbiguous || exitAmbiguous || Stored(".exitambiguous",0)>0 || Stored(".intent",0)>0)
   {
      Feedback("Start blocked: check unresolved order");
      return;
   }
   if(halted && !Persist(".halt",0)) { Feedback("Start blocked: state write failed"); return; }
   halted=false;
   haltReason="";
   status="Scanning | Risk checks active";
   lastEntryStatus="";
   panelNotice="";
   enabled=true;
   if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
}
void ResetProfitView()
{
   if(!ProfitHistory(true)) { Feedback("Reset P/L: history unavailable"); return; }
   long cutoff=(long)TimeCurrent()*1000-1;
   if(lastProfitDealMsc>cutoff) cutoff=lastProfitDealMsc;
   if(profitResetMsc>cutoff) cutoff=profitResetMsc;
   if(!Persist(".plreset",(double)cutoff)) { Feedback("Reset P/L: state write failed"); return; }
   profitResetMsc=cutoff;
   dailyView=0;
   monthlyView=0;
   if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
   Feedback("Daily and monthly P/L reset");
}
double panelScale=1;
int renderX=0,renderY=0;
int Pixels(int nominal){ return (int)MathRound(nominal*panelScale); }
void PanelObject(string suffix,ENUM_OBJECT type,int x,int y,int w,int h,string value,color ink,color bg,int size)
{
   string name=panel+suffix;
   bool exists=ObjectFind(0,name)>=0;
   if(!exists && !ObjectCreate(0,name,type,0,0,0)) return;
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,renderX+Pixels(x));
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,renderY+Pixels(y));
   ObjectSetInteger(0,name,OBJPROP_XSIZE,Pixels(w));
   ObjectSetInteger(0,name,OBJPROP_YSIZE,Pixels(h));
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   if(type==OBJ_RECTANGLE_LABEL) ObjectSetInteger(0,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,name,OBJPROP_BORDER_COLOR,C'41,58,79');
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,(int)MathMax(8,Pixels(size)));
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,type==OBJ_BUTTON ? 20 : 0);
   ObjectSetString(0,name,OBJPROP_FONT,suffix=="title" ? "Trebuchet MS" : "Verdana");
   ObjectSetString(0,name,OBJPROP_TEXT,value);
}
void Label(string id,int x,int y,string title,color ink,int size=10)
{
   PanelObject(id,OBJ_LABEL,x,y,0,0,title,ink,clrNONE,size);
}
string Money(double x){ return DoubleToString(x,2); }
string Price(string symbol,double x)
{
   return x>0 ? DoubleToString(x,(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS)) : "--";
}
void Box(string id,int x,int y,int w,int h,color fill)
{
   PanelObject(id,OBJ_RECTANGLE_LABEL,x,y,w,h,"",fill,fill,10);
}
void Button(string id,int x,int y,int w,string title,color ink,color fill)
{
   PanelObject(id,OBJ_BUTTON,x,y,w,22,title,ink,fill,9);
}
string Truncate(string value,int width)
{
   return StringLen(value)>width ? StringSubstr(value,0,width-3)+"..." : value;
}
void Draw()
{
   if(!Dashboard || ArraySize(market)==0 || (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return;
   int width=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   int height=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   if(width<160 || height<120) return;
   const int panelWidth=390, panelHeight=203;
   renderX=(int)Clamp(PanelX,0,MathMax(0,width-320));
   renderY=(int)Clamp(PanelY,0,MathMax(0,height-panelHeight));
   panelScale=MathMin(1.0,MathMin((width-renderX-5)/(double)panelWidth,
                                 (height-renderY-5)/(double)panelHeight));
   color bg=C'10,20,27', card=C'25,45,51', muted=C'196,220,223', white=C'249,255,254';
   color teal=C'110,247,206', violet=C'101,226,189', amber=C'255,201,115', red=C'255,141,145';
   color purple=C'67,48,124', danger=C'86,36,53';
   color signal=halted ? red : (enabled && ExecutionAllowed() ? teal : amber);
   string sym=market[selected].symbol, ccy=AccountInfoString(ACCOUNT_CURRENCY);
   string reason=market[selected].feed;
   if(reason=="") reason="Waiting for scan";
   if(reason=="Quote ready")
   {
      if(market[selected].mixedSides) reason="Mixed BUY/SELL under this Magic";
      else if(!market[selected].historyOK) reason="Position history / risk unavailable";
      else if(market[selected].foreign) reason="Netting position owned externally";
      else if(market[selected].regime=="UNSTABLE LIQUIDITY") reason="Spread filter active";
      else if(market[selected].regime=="PRICE SHOCK") reason="Price shock filter active";
      else if(market[selected].entryNote!="") reason=market[selected].entryNote;
      else reason=market[selected].regime+" | Score "+Money(market[selected].score);
   }
   Box("base",0,0,panelWidth,panelHeight,bg);
   Box("headerbar",0,0,panelWidth,3,violet);
   Label("title",10,6,"Hydra-Vx",white,16);
   Label("profile",296,10,EnumToString(profile),violet,10);
   string displayed=panelNotice!="" && GetTickCount64()<noticeUntil ? panelNotice : status;
   Label("status",10,29,Truncate(displayed,47),signal,10);

   Box("eqcard",10,49,116,40,card);
   Box("plcard",132,49,116,40,card);
   Box("riskcard",254,49,116,40,card);
   double floating=AccountInfoDouble(ACCOUNT_PROFIT);
   Label("eqlabel",16,51,"EQUITY "+ccy,muted,8);
   Label("equity",16,65,Truncate(Money(AccountInfoDouble(ACCOUNT_EQUITY)),12),white,12);
   Label("pllabel",138,51,"FLOATING P/L",muted,8);
   Label("floating",138,65,Truncate(Money(floating),12),floating>=0 ? teal : red,12);
   double viewDD=viewPeakEquity>0 ? MathMax(0,100*(1-AccountInfoDouble(ACCOUNT_EQUITY)/viewPeakEquity)) : 0;
   Label("risklabel",260,51,"DRAWDOWN",muted,8);
   Label("drawdown",260,65,Money(viewDD)+"%",viewDD>0 ? amber : teal,12);
   Box("meter",260,85,(int)MathMax(1,MathRound(104*Clamp(viewDD/TotalDrawdownPct,0,1))),2,signal);
   Label("daily",10,92,"Daily  "+Money(dailyView)+" "+ccy,dailyView>=0 ? teal : red,9);
   Label("monthly",193,92,"Monthly  "+Money(monthlyView)+" "+ccy,monthlyView>=0 ? teal : red,9);

   string sideName=market[selected].basketSide>0 ? " BUY" : (market[selected].basketSide<0 ? " SELL" : "");
   Label("focus",10,109,Truncate(sym+sideName,20),white,10);
   Label("counts",183,110,IntegerToString(selected+1)+"/"+IntegerToString(ArraySize(market))+
      " baskets | "+IntegerToString(positionCount)+" positions",muted,9);
   int side=market[selected].side;
   double distance=GridDistance(market[selected]);
   string next=(side!=0 && distance>0 && !market[selected].mixedSides) ?
      Price(sym,market[selected].lastFill-side*distance) : "--";
   if(market[selected].feed=="Quote ready" && market[selected].historyOK &&
      market[selected].net<0 && averaging && next!="--" &&
      (market[selected].lastFill-(side>0 ? market[selected].lastAsk : market[selected].lastBid))*side<distance &&
      market[selected].regime!="UNSTABLE LIQUIDITY" && market[selected].regime!="PRICE SHOCK")
      reason="Next "+(side>0 ? "BUY Ask " : "SELL Bid ")+next+" | Gap "+Price(sym,distance);
   Label("feed",10,129,Truncate(reason,49),teal,9);
   ObjectSetString(0,panel+"status",OBJPROP_TOOLTIP,displayed);
   ObjectSetString(0,panel+"feed",OBJPROP_TOOLTIP,reason);
   ObjectSetString(0,panel+"equity",OBJPROP_TOOLTIP,
      "Balance "+Money(AccountInfoDouble(ACCOUNT_BALANCE))+
      " | Free margin "+Money(AccountInfoDouble(ACCOUNT_MARGIN_FREE))+
      " | Margin "+Money(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL))+"%");
   ObjectSetString(0,panel+"floating",OBJPROP_TOOLTIP,
      "Realized D "+Money(daily)+" | W "+Money(weekly)+" | M "+Money(monthly)+" | All "+Money(totalNet));
   ObjectSetString(0,panel+"drawdown",OBJPROP_TOOLTIP,
      "Guard DD "+Money(MathMax(0,totalDD))+"% | Daily "+Money(MathMax(0,dayDD))+"%");
   ObjectSetString(0,panel+"focus",OBJPROP_TOOLTIP,
      "Layers "+IntegerToString(market[selected].layers)+" | Next "+next+
      " ("+(side>0 ? "Ask" : "Bid")+") | Gap "+Price(sym,distance));
   ObjectSetString(0,panel+"daily",OBJPROP_TOOLTIP,"Realized EA P/L today after Reset P/L, broker time");
   ObjectSetString(0,panel+"monthly",OBJPROP_TOOLTIP,"Realized EA P/L this month after Reset P/L, broker time");

   Button("start",10,151,72,halted ? "Resume" : (enabled ? "Pause" : "Start"),bg,teal);
   Button("gridtoggle",86,151,58,averaging ? "Grid ON" : "Grid OFF",white,purple);
   Button("mode",148,151,47,"Mode",white,card);
   Button("basket",199,151,79,"Close basket",white,card);
   Button("stop",282,151,88,"Stop entry",red,danger);
   Button("prev",10,176,32,"<",white,card);
   Button("chart",46,176,68,"Chart",white,card);
   Button("next",118,176,32,">",white,card);
   Button("resetpl",154,176,68,"Reset P/L",white,card);
   Button("close",226,176,52,"Close all",amber,card);
   Button("resetdd",282,176,88,"Reset DD",white,card);
   ChartRedraw();
}
void Consider(int index,int &candidate,int &direction,double &best)
{
   if(index<0 || !Sample(market[index])) return;
   int side=0;
   double rank=0;
   if(EligibleSignal(market[index],side,rank) && rank>best)
   {
      best=rank;
      candidate=index;
      direction=side;
   }
}
void Cycle(bool scanCatalog)
{
   if(working) return;
   working=true;
   Guardian();
   ProfitHistory();
   if(scanCatalog && (!MQLInfoInteger(MQL_TESTER) || TesterScanAllBrokerSymbols)) Discover(32);
   int live[];
   int total=PositionsTotal();
   bool missing=false;
   for(int j=0;j<total;j++)
   {
      if(PositionGetTicket(j)==0 || (ulong)PositionGetInteger(POSITION_MAGIC)!=Magic) continue;
      int basketSide=hedging ? SelectedPositionSide() : 0;
      int index=RegisterMarket(PositionGetString(POSITION_SYMBOL),basketSide);
      if(index<0)
      {
         missing=true;
         continue;
      }
      bool found=false;
      for(int k=0;k<ArraySize(live);k++) if(live[k]==index) found=true;
      if(!found)
      {
         int used=ArraySize(live);
         if(ArrayResize(live,used+1)!=used+1) missing=true;
         else live[used]=index;
      }
   }
   if(missing) Latch("POSITION SCAN FAILED");
   int n=ArraySize(market);
   bool hasPosition[];
   if(ArrayResize(hasPosition,n)!=n)
   {
      Latch("POSITION SCAN FAILED");
      working=false;
      Draw();
      return;
   }
   for(int i=0;i<n;i++) hasPosition[i]=false;
   portfolioStress=0; positionCount=0;
   for(int j=0;j<ArraySize(live);j++) hasPosition[live[j]]=true;
   for(int i=0;i<n;i++)
   {
      if(hasPosition[i]) continue;
      if(market[i].count>0) Reconcile(market[i]);
   }
   for(int j=0;j<ArraySize(live);j++)
   {
      int i=live[j];
      Sample(market[i]);
      Reconcile(market[i]);
      positionCount+=market[i].count;
      portfolioStress+=market[i].stress;
   }
   int candidate=-1, direction=0;
   double best=-DBL_MAX;
   bool changed=false;
   for(int j=0;j<ArraySize(live);j++)
   {
      int i=live[j];
      int count=market[i].count;
      double volume=market[i].lots;
      bool sampled=market[i].feed=="Quote ready" && market[i].atr>0;
      ManagedExit(market[i],sampled);
      if(market[i].lastAction==TimeCurrent()) Reconcile(market[i]);
      if(market[i].count!=count || market[i].lots!=volume) changed=true;
      if(sampled && !changed)
      {
         int side=0;
         double rank=0;
         if(EligibleSignal(market[i],side,rank) && rank>best)
         {
            best=rank;
            candidate=i;
            direction=side;
         }
      }
   }
   if(closingSymbol!="")
   {
      int index=MarketIndex(closingSymbol,closingSide);
      if(index>=0 && market[index].count==0 && !Outstanding(closingSymbol)) closingSymbol="";
   }
   if(allClosing && positionCount==0) allClosing=false;
   if(n>0 && !hasPosition[0]) Consider(0,candidate,direction,best);
   if(hedging && n>1 && !hasPosition[1]) Consider(1,candidate,direction,best);
   if(scanCatalog && selected>=(hedging ? 2 : 1) && selected<n && !hasPosition[selected])
      Consider(selected,candidate,direction,best);
   if(scanCatalog && n>0)
   {
      int batch=(int)MathMin(ScanBatchSize,n);
      for(int j=0;j<batch;j++)
      {
         int i=scanCursor;
         scanCursor=(scanCursor+1)%n;
         if(i>=(hedging ? 2 : 1) && i!=selected && !hasPosition[i]) Consider(i,candidate,direction,best);
      }
   }
   if(!changed && candidate>=0)
   {
      // Refresh ownership for an idle candidate immediately before preflight.
      int previousCount=market[candidate].count;
      double previousLots=market[candidate].lots;
      Reconcile(market[candidate]);
      double rank=0;
      if(market[candidate].count==previousCount && market[candidate].lots==previousLots &&
         EligibleSignal(market[candidate],direction,rank))
      {
         Submit(market[candidate],direction);
         lastEntryStatus=market[candidate].symbol+"  "+market[candidate].entryNote;
      }
      market[candidate].evaluatedStamp=market[candidate].stamp;
      market[candidate].evaluatedBid=market[candidate].lastBid;
      market[candidate].evaluatedAsk=market[candidate].lastAsk;
   }
   if(!halted)
   {
      string issue=PermissionIssue();
      if(allClosing || closingSymbol!="") status="Closing positions";
      else if(issue!="") status=issue;
      else if(!enabled) status="Entries paused";
      else if(NeedsExposure()) status=lastEntryStatus=="" ? "Seeking first position | Risk checks on" : lastEntryStatus;
      else status="Scanning | Risk checks active";
   }
   datetime now=MQLInfoInteger(MQL_TESTER) ? TimeCurrent() : TimeLocal();
   if(now!=lastDashboard)
   {
      lastDashboard=now;
      Draw();
   }
   working=false;
}
int OnInit()
{
   if(Magic==0 ||
      InitialRiskPct<0.25 || InitialRiskPct>1 || BasketRiskPct<InitialRiskPct ||
      BasketRiskPct>2 || PortfolioRiskPct<BasketRiskPct || PortfolioRiskPct>5 ||
      DailyDrawdownPct<=0 || DailyDrawdownPct>5 || TotalDrawdownPct<DailyDrawdownPct || TotalDrawdownPct>15 ||
      MinMarginLevel<200 || MinFreeEquityPct<25 || MinFreeEquityPct>=95 || MaxBasketLots<=0 ||
      BaseGridPoints<=0 ||
      LotMultiplier<1.05 || LotMultiplier>1.30 || MaxSpreadATR<=0 || MaxGapATR<1 ||
      CommissionRoundTurnPerLot<0 || QuoteAgeSeconds<1 || CooldownSeconds<2 ||
      SignalThreshold<=0 || SignalThreshold>=1 ||
      ScanBatchSize<1 || ScanBatchSize>100 || TimerMs<100 || TimerMs>1000 || TradeDeviationPoints<0)
      return INIT_PARAMETERS_INCORRECT;
   bool real=AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL;
   if(real && !MQLInfoInteger(MQL_TESTER))
   {
      Print("Hydra-Vx research build: use a demo account or Strategy Tester.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(Mode==Extreme && !MQLInfoInteger(MQL_TESTER)) return INIT_PARAMETERS_INCORRECT;
   string server=AccountInfoString(ACCOUNT_SERVER);
   uint serverHash=2166136261;
   for(int j=0;j<StringLen(server);j++) serverHash=(serverHash^(uint)StringGetCharacter(server,j))*16777619;
   key="VIO."+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+"."+IntegerToString((long)Magic)+"."+IntegerToString((long)serverHash);
   hedging=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   if(!RegisterSymbol(_Symbol)) return INIT_FAILED;
   if(!MQLInfoInteger(MQL_TESTER) || TesterScanAllBrokerSymbols) Discover(32);
   if(!MQLInfoInteger(MQL_TESTER))
   {
      lockHandle=FileOpen(key+".lock",FILE_BIN|FILE_READ|FILE_WRITE|FILE_COMMON);
      if(lockHandle==INVALID_HANDLE)
      {
         Print("Hydra-Vx another instance owns this account/magic or the lock could not be opened.");
         return INIT_FAILED;
      }
   }
   trade.SetExpertMagicNumber(Magic);
   trade.SetAsyncMode(false);
   profile=Mode;
   averaging=MartingaleEnabled;
   enabled=StartEnabled;
   peakEquity=Stored(".peak",AccountInfoDouble(ACCOUNT_EQUITY));
   viewPeakEquity=Stored(".viewpeak",AccountInfoDouble(ACCOUNT_EQUITY));
   dayEquity=Stored(".dayeq",AccountInfoDouble(ACCOUNT_EQUITY));
   dayKey=(datetime)Stored(".day",(double)DayStart(TimeCurrent()));
   Persist(".peak",peakEquity);
   Persist(".viewpeak",viewPeakEquity);
   Persist(".dayeq",dayEquity);
   Persist(".day",(double)dayKey);
   profitResetMsc=(long)Stored(".plreset",0);
   exitAmbiguous=Stored(".exitambiguous",0)>0;
   if(Stored(".halt",0)>0 || Stored(".intent",0)>0 || exitAmbiguous) Latch("PERSISTENT EMERGENCY LOCK");
   if(!EventSetMillisecondTimer(TimerMs))
   {
      Print("Hydra-Vx unable to start scan timer, error ",GetLastError());
      return INIT_FAILED;
   }
   Print("Hydra-Vx 0.19 attached to ",_Symbol," | broker catalog: ",SymbolsTotal(false),
         " | entry enabled at start: ",enabled);
   Draw();
   dirty=true;
   Cycle(true);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   for(int i=0;i<ArraySize(market);i++)
      if(market[i].atrHandle!=INVALID_HANDLE) IndicatorRelease(market[i].atrHandle);
   if(lockHandle!=INVALID_HANDLE) FileClose(lockHandle);
   ObjectsDeleteAll(0,panel);
}
void OnTick(){ Cycle(false); }
void OnTimer(){ Cycle(true); }
void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   dirty=true;
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &name)
{
   if(id==CHARTEVENT_CHART_CHANGE) { Draw(); return; }
   if(id!=CHARTEVENT_OBJECT_CLICK || StringFind(name,panel)!=0 || ArraySize(market)==0) return;
   string action=StringSubstr(name,StringLen(panel));
   ObjectSetInteger(0,name,OBJPROP_STATE,false);
   if(action=="start") ToggleEntries();
   if(action=="resetpl") ResetProfitView();
   if(action=="next") selected=(selected+1)%ArraySize(market);
   if(action=="prev") selected=(selected+ArraySize(market)-1)%ArraySize(market);
   if(action=="chart") selected=0;
   if(action=="gridtoggle") averaging=!averaging;
   if(action=="mode")
   {
      if(profile==Survival) profile=Growth;
      else if(profile==Growth && MQLInfoInteger(MQL_TESTER)) profile=Extreme;
      else profile=Survival;
   }
   if(action=="basket")
   {
      closingSymbol=market[selected].symbol;
      closingSide=market[selected].basketSide;
   }
   if(action=="close")
   {
      enabled=false;
      allClosing=true;
   }
   if(action=="stop") Latch("OPERATOR ENTRY HALT");
   if(action=="resetdd")
   {
      viewPeakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      Persist(".viewpeak",viewPeakEquity);
      if(!MQLInfoInteger(MQL_TESTER)) GlobalVariablesFlush();
   }
   Cycle(true);
   Draw();
}
