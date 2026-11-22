#property strict
#property version     "1.00"
#property description "Mercury Vx | MT5 tick and minute scalper"
#include <Trade/Trade.mqh>

enum MercuryExecution
  {
   TESTER_ONLY = 0,
   ENABLE_DEMO = 1,
   ENABLE_REAL = 2
  };

input group "Execution"
input MercuryExecution ExecutionMode = TESTER_ONLY;
input ulong MagicNumber = 60261122;
input int MaxDeviationPoints = 20;
input int DecisionIntervalSeconds = 2;
input int CooldownSeconds = 20;
input int MaxHoldSeconds = 180; // 0 keeps the broker-side SL and TP as the normal exits.
input int SessionStartHour = 0;
input int SessionEndHour = 0;   // Same as start means all hours. Broker server time.

input group "Position risk"
input double RiskPerTradePct = 0.50;
input double DailyLossLimitPct = 3.00;
input double StopAtrMultiple = 0.65;
input double MaxSpreadToRisk = 0.30;
input double MaxSpreadToAtr = 0.25;
input double CommissionPerLotRoundTrip = 0.0; // Account currency.

input group "Signal"
input double MinimumSignal = 0.32;
input double MinimumMicroSignal = 0.13;
input double OpposingTrendLimit = 0.20;

input group "Backtest report"
input int MinimumReportTrades = 100;
input int MinimumReportDays = 20;
input bool ExportDailyCsv = true;

#define FRAME_COUNT 4
#define PERIOD_COUNT 128
#define FIRST_PERIOD 4
#define BAR_COUNT (FIRST_PERIOD + PERIOD_COUNT)
#define FAMILY_COUNT 8
#define SETUP_COUNT 3
#define QUOTE_SLOTS 128

const double RewardToRisk = 3.0;
const double DailyTargetPct = 50.0;
const double WinRateTargetPct = 75.0;
const double SizingReserve = 0.90;

struct FrameSignal
  {
   datetime bar;
   double atr;
   double trend;
   double breakout;
   double pullback;
  };

struct QuoteSample
  {
   long second;
   double mid;
  };

struct EntryDiagnostics
  {
   int history;
   int tickWindow;
   int signal;
   int spread;
   int contract;
   int sizeOrMargin;
   int rejected;
   int accepted;
  };

CTrade trade;
EntryDiagnostics diagnostics;
ENUM_TIMEFRAMES timeframes[FRAME_COUNT] = {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M5};
double frameWeight[FRAME_COUNT] = {0.46, 0.25, 0.17, 0.12};
FrameSignal frames[FRAME_COUNT];
QuoteSample quotes[QUOTE_SLOTS];
int lookbackSeconds[3] = {5, 15, 30};
double microWeight[3] = {0.45, 0.35, 0.20};

bool inTester = false;
bool inOptimization = false;
bool ownsLock = false;
string accountKey, lockKey, dayKey;
double tickSize = 0.0;
double pointSize = 0.0;
int priceDigits = 0;
double lotMin = 0.0;
double lotMax = 0.0;
double lotStep = 0.0;
long nextDecision = 0;
long nextEntry = 0;
long nextClose = 0;
ulong checkedPosition = 0;
double checkedEntry = 0.0;
double checkedStop = 0.0;
double checkedTake = 0.0;
double checkedVolume = 0.0;
ulong observedPosition = 0;
int csv = INVALID_HANDLE;
int daysObserved = 0;
int daysAtTarget = 0;
double worstDayPct = 0.0;
bool hasDayReturn = false;
datetime activeDay = 0;
double dayStartEquity = 0.0;
double lastEquity = 0.0;
bool blockedToday = false;

double Unit(const double value)
  {
   return MathMax(-1.0, MathMin(1.0, value));
  }

double AverageTrueRange(const MqlRates &bars[])
  {
   double sum = 0.0;
   for(int i = 0; i < 14; ++i)
     {
      const double previousClose = bars[i + 1].close;
      sum += MathMax(bars[i].high - bars[i].low,
                     MathMax(MathAbs(bars[i].high - previousClose),
                             MathAbs(bars[i].low - previousClose)));
     }
   return sum / 14.0;
  }

bool CalculateFrame(const MqlRates &bars[], FrameSignal &signal)
  {
   const double atr = AverageTrueRange(bars);
   if(!MathIsValidNumber(atr) || atr <= 0.0)
      return false;

   const double last = bars[0].close;
   double sum = 0.0, squares = 0.0, weighted = 0.0;
   double gains = 0.0, losses = 0.0, gainLag = 0.0, lossLag = 0.0;
   double high = bars[0].high, low = bars[0].low;
   double priorHigh = bars[1].high, priorLow = bars[1].low;
   double sumTrend = 0.0, sumBreakout = 0.0, sumPullback = 0.0, sumWeights = 0.0;

   for(int j = 0; j < BAR_COUNT - 1; ++j)
     {
      const double relative = bars[j].close - last;
      const double change = bars[j].close - bars[j + 1].close;
      sum += relative;
      squares += relative * relative;
      weighted -= j * relative;
      const double gain = MathMax(0.0, change);
      const double loss = MathMax(0.0, -change);
      gains += gain;
      losses += loss;
      gainLag += j * gain;
      lossLag += j * loss;
      high = MathMax(high, bars[j].high);
      low = MathMin(low, bars[j].low);
      priorHigh = MathMax(priorHigh, bars[j + 1].high);
      priorLow = MathMin(priorLow, bars[j + 1].low);
      const int count = j + 1;
      if(count < FIRST_PERIOD)
         continue;

      const double n = (double)count;
      const double weight = 1.0 / n;
      const double mean = sum / n;
      const double sigma = MathSqrt(MathMax(0.0, squares / n - mean * mean));
      const double slope = (weighted + j * sum / 2.0) / (n * (n * n - 1.0) / 12.0);
      const double path = gains + losses;
      const double weightedGains = n * gains - gainLag;
      const double weightedLosses = n * losses - lossLag;
      const double weightedPath = weightedGains + weightedLosses;
      const double move = last - bars[j + 1].close;
      const double channelMid = (priorHigh + priorLow) / 2.0;

      const double smaVote = Unit(-mean / (1.50 * atr));
      const double slopeVote = Unit(slope * MathSqrt(n) / atr);
      const double rsiVote = weightedPath > 0.0 ? Unit((weightedGains - weightedLosses) / weightedPath) : 0.0;
      const double momentumVote = Unit(move / (1.15 * atr * MathSqrt(n)));
      const double stochVote = high > low ? Unit(2.0 * (last - low) / (high - low) - 1.0) : 0.0;
      const double channelVote = Unit(0.65 * (last - channelMid) /
                                      MathMax(atr, (priorHigh - priorLow) / 2.0));
      const double bollingerVote = sigma > 0.0 ? Unit(-mean / (2.20 * sigma)) : 0.0;
      const double efficiencyVote = path > 0.0 ? Unit(move / path) : 0.0;

      const double direction = 0.55 * slopeVote + 0.45 * smaVote;
      const double oscillator = 0.50 * stochVote + 0.30 * bollingerVote + 0.20 * rsiVote;

      sumTrend += weight * (0.36 * direction + 0.24 * rsiVote + 0.22 * momentumVote +
                            0.10 * efficiencyVote + 0.08 * bollingerVote);
      sumBreakout += weight * (0.42 * channelVote + 0.25 * momentumVote +
                               0.18 * efficiencyVote + 0.15 * stochVote);
      sumPullback += weight * direction * MathMax(0.0, 1.0 - 2.0 * MathAbs(oscillator + 0.18 * direction));
      sumWeights += weight;
     }

   signal.bar = bars[0].time;
   signal.atr = atr;
   signal.trend = sumTrend / sumWeights;
   signal.breakout = sumBreakout / sumWeights;
   signal.pullback = sumPullback / sumWeights;
   return true;
  }

bool RefreshFrames()
  {
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   for(int i = 0; i < FRAME_COUNT; ++i)
     {
      const datetime latest = iTime(_Symbol, timeframes[i], 1);
      if(latest == 0)
         return false;
      if(frames[i].bar == latest)
         continue;
      if(CopyRates(_Symbol, timeframes[i], 1, BAR_COUNT, bars) != BAR_COUNT ||
         !CalculateFrame(bars, frames[i]))
         return false;
     }
   return true;
  }

void RecordQuote(const long second, const double mid)
  {
   const int slot = (int)(second % QUOTE_SLOTS);
   quotes[slot].second = second;
   quotes[slot].mid = mid;
  }

bool MicroSignal(const long second, const double mid, double &signal)
  {
   signal = 0.0;
   if(second <= 33 || frames[0].atr <= 0.0)
      return false;
   for(int i = 0; i < 3; ++i)
     {
      bool found = false;
      const long cutoff = second - lookbackSeconds[i];
      for(int gap = 0; gap <= 3; ++gap)
        {
         const long stamp = cutoff - gap;
         const int slot = (int)(stamp % QUOTE_SLOTS);
         if(quotes[slot].second != stamp || quotes[slot].mid <= 0.0)
            continue;
         const double scale = frames[0].atr * MathSqrt((lookbackSeconds[i] + gap) / 60.0);
         signal += microWeight[i] * Unit((mid - quotes[slot].mid) / scale);
         found = true;
         break;
        }
      if(!found)
         return false;
     }
   return true;
  }

int ChooseDirection(const double micro, string &setup)
  {
   if(MathAbs(micro) < MinimumMicroSignal)
      return 0;
   const int direction = micro > 0.0 ? 1 : -1;
   const double higherTrend = 0.58 * frames[2].trend + 0.42 * frames[3].trend;
   if(direction * higherTrend < -OpposingTrendLimit)
      return 0;

   double trend = 0.0, breakout = 0.0, pullback = 0.0;
   for(int i = 0; i < FRAME_COUNT; ++i)
     {
      trend += frameWeight[i] * frames[i].trend;
      breakout += frameWeight[i] * frames[i].breakout;
      pullback += frameWeight[i] * frames[i].pullback;
     }

   const double trendScore = direction * (0.76 * trend + 0.24 * micro);
   const double breakoutScore = direction * (0.67 * breakout + 0.33 * micro);
   const double pullbackScore = direction * (0.68 * pullback + 0.32 * micro);
   double best = 0.0;
   if(direction * trend >= 0.10)
     {
      best = trendScore;
      setup = "Trend";
     }
   if(direction * breakout >= 0.16 && breakoutScore > best)
     {
      best = breakoutScore;
      setup = "Breakout";
     }
   if(direction * higherTrend >= 0.12 && direction * pullback >= 0.10 && pullbackScore > best)
     {
      best = pullbackScore;
      setup = "Pullback";
     }
   return best >= MinimumSignal ? direction : 0;
  }

uint HashText(const string value)
  {
   uint hash = 2166136261;
   for(int i = 0; i < StringLen(value); ++i)
      hash = (hash ^ (uint)StringGetCharacter(value, i)) * 16777619;
   return hash;
  }

bool InTradingSession(const datetime when)
  {
   MqlDateTime parts;
   if(!TimeToStruct(when, parts))
      return false;
   if(SessionStartHour == SessionEndHour)
      return true;
   if(SessionStartHour < SessionEndHour)
      return parts.hour >= SessionStartHour && parts.hour < SessionEndHour;
   return parts.hour >= SessionStartHour || parts.hour < SessionEndHour;
  }

void WriteDay(const double endingEquity)
  {
   if(!inTester || activeDay == 0)
      return;
   ++daysObserved;
   if(dayStartEquity <= 0.0)
     {
      if(csv != INVALID_HANDLE)
         FileWrite(csv, TimeToString(activeDay, TIME_DATE), DoubleToString(dayStartEquity, 2),
                   DoubleToString(endingEquity, 2), "", "NO");
      return;
     }
   const double result = 100.0 * (endingEquity / dayStartEquity - 1.0);
   const bool atTarget = endingEquity >= dayStartEquity * (1.0 + DailyTargetPct / 100.0);
   if(atTarget)
      ++daysAtTarget;
   if(!hasDayReturn || result < worstDayPct)
      worstDayPct = result;
   hasDayReturn = true;
   if(csv != INVALID_HANDLE)
      FileWrite(csv, TimeToString(activeDay, TIME_DATE), DoubleToString(dayStartEquity, 2),
                DoubleToString(endingEquity, 2), DoubleToString(result, 6), atTarget ? "YES" : "NO");
  }

void UpdateDay(const datetime when)
  {
   const datetime day = (datetime)(((long)when / 86400) * 86400);
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(activeDay != day)
     {
      WriteDay(lastEquity);
      dayStartEquity = activeDay == 0 ? equity : lastEquity;
      activeDay = day;
      blockedToday = false;
      if(!inTester)
        {
         dayKey = accountKey + "." + IntegerToString((long)day / 86400);
         double saved = 0.0;
         if(GlobalVariableGet(dayKey, saved) && saved > 0.0)
            dayStartEquity = saved;
         else if(dayStartEquity > 0.0)
            GlobalVariableSet(dayKey, dayStartEquity);
         blockedToday = GlobalVariableCheck(dayKey + ".halt");
        }
     }
   lastEquity = equity;
   if(!blockedToday && dayStartEquity > 0.0 &&
      equity <= dayStartEquity * (1.0 - DailyLossLimitPct / 100.0))
     {
      blockedToday = true;
      if(!inTester)
         GlobalVariableSet(dayKey + ".halt", 1.0);
      Print("Mercury Vx | daily equity loss limit reached for ", _Symbol);
     }
  }

double GridPrice(const long ticks)
  {
   return NormalizeDouble(ticks * tickSize, priceDigits);
  }

double TargetPrice(const int direction, const double entry, const double stop)
  {
   const double theoretical = entry + direction * RewardToRisk * MathAbs(entry - stop);
   const double ticks = theoretical / tickSize;
   return GridPrice(direction > 0 ? (long)MathCeil(ticks - 1e-8) : (long)MathFloor(ticks + 1e-8));
  }

double BrokerGap(const ENUM_SYMBOL_INFO_INTEGER property)
  {
   return (double)SymbolInfoInteger(_Symbol, property) * pointSize + tickSize;
  }

bool RiskCash(const int direction, const double volume, const double entry,
              const double stop, double &cash)
  {
   double profit = 0.0;
   const ENUM_ORDER_TYPE side = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(side, _Symbol, volume, entry, stop, profit) || profit >= 0.0)
      return false;
   cash = -profit + volume * CommissionPerLotRoundTrip;
   return MathIsValidNumber(cash) && cash > 0.0;
  }

double RiskBudget()
  {
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double remainingDayRisk = equity - dayStartEquity * (1.0 - DailyLossLimitPct / 100.0);
   return MathMin(equity * RiskPerTradePct / 100.0, remainingDayRisk);
  }

double OrderVolume(const int direction, const double entry, const double stop)
  {
   const double riskBudget = RiskBudget() * SizingReserve;
   double minimumRisk = 0.0;
   if(riskBudget <= 0.0 || !RiskCash(direction, lotMin, entry, stop, minimumRisk) ||
      minimumRisk > riskBudget)
      return 0.0;
   const double raw = MathMin(lotMax, lotMin * riskBudget / minimumRisk);
   return NormalizeDouble(lotMin + MathFloor((raw - lotMin) / lotStep + 1e-8) * lotStep, 8);
  }

bool QuotedStopsValid(const int direction, const MqlTick &tick, const double stop,
                      const double target, const double gap)
  {
   const double exitQuote = direction > 0 ? tick.bid : tick.ask;
   return stop > 0.0 && target > 0.0 &&
          direction * (exitQuote - stop) >= gap - tickSize * 1e-6 &&
          direction * (target - exitQuote) >= gap - tickSize * 1e-6;
  }

bool Taken(const uint code)
  {
   return code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL ||
          code == TRADE_RETCODE_PLACED;
  }

bool CanTrade(const int direction)
  {
   if(!inTester && (!MQLInfoInteger(MQL_TRADE_ALLOWED) ||
                    !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
                    !AccountInfoInteger(ACCOUNT_TRADE_EXPERT) ||
                    !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)))
      return false;
   const long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
      return false;
   return direction == 0 || mode == SYMBOL_TRADE_MODE_FULL ||
          (direction == 1 && mode == SYMBOL_TRADE_MODE_LONGONLY) ||
          (direction == -1 && mode == SYMBOL_TRADE_MODE_SHORTONLY);
  }

void ClosePosition(const ulong ticket, const long second, const string reason)
  {
   if(second < nextClose || !CanTrade(0))
      return;
   nextClose = second + 2;
   trade.PositionClose(ticket, (ulong)MaxDeviationPoints);
   const uint code = trade.ResultRetcode();
   if(Taken(code))
      PrintFormat("Mercury Vx | close #%I64u | %s", ticket, reason);
   else
      PrintFormat("Mercury Vx | close #%I64u rejected | %u %s",
                  ticket, code, trade.ResultRetcodeDescription());
  }

void RememberPosition(const ulong ticket, const double entry, const double stop,
                      const double take, const double volume)
  {
   checkedPosition = ticket;
   checkedEntry = entry;
   checkedStop = stop;
   checkedTake = take;
   checkedVolume = volume;
  }

bool ManagePosition(const MqlTick &tick, const long second)
  {
   bool symbolOccupied = false;
   bool ownPosition = false;
   for(int index = PositionsTotal() - 1; index >= 0; --index)
     {
      const ulong ticket = PositionGetTicket(index);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      symbolOccupied = true;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;
      ownPosition = true;
      observedPosition = ticket;
      const double stop = PositionGetDouble(POSITION_SL);
      const double take = PositionGetDouble(POSITION_TP);
      if(blockedToday || stop <= 0.0 || take <= 0.0)
        {
         ClosePosition(ticket, second, blockedToday ? "daily equity limit" : "missing protective order");
         continue;
        }
      if(MaxHoldSeconds > 0 && second - PositionGetInteger(POSITION_TIME) >= MaxHoldSeconds)
        {
         ClosePosition(ticket, second, "time exit");
         continue;
        }

      const int direction = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      const double filledVolume = PositionGetDouble(POSITION_VOLUME);
      if(ticket == checkedPosition && entry == checkedEntry && stop == checkedStop &&
         take == checkedTake && filledVolume == checkedVolume)
         continue;
      double risk = 0.0;
      // The sizing budget is equity before entry. Rebuild it without the position's floating P/L.
      const double equityAtEntry = AccountInfoDouble(ACCOUNT_EQUITY) - PositionGetDouble(POSITION_PROFIT);
      const double limit = MathMin(equityAtEntry * RiskPerTradePct / 100.0,
                                   equityAtEntry - dayStartEquity * (1.0 - DailyLossLimitPct / 100.0));
      if(!RiskCash(direction, filledVolume, entry, stop, risk) || risk > limit + 1e-7)
        {
         ClosePosition(ticket, second, "filled risk exceeds limit");
         continue;
        }
      const double adjustedTarget = TargetPrice(direction, entry, stop);
      if(MathAbs(adjustedTarget - take) <= tickSize * 0.5)
        {
         RememberPosition(ticket, entry, stop, take, filledVolume);
         continue;
        }
      const double gap = MathMax(BrokerGap(SYMBOL_TRADE_STOPS_LEVEL), BrokerGap(SYMBOL_TRADE_FREEZE_LEVEL));
      if(!CanTrade(0))
         continue;
      if(QuotedStopsValid(direction, tick, stop, adjustedTarget, gap))
        {
         trade.PositionModify(ticket, stop, adjustedTarget);
         const uint code = trade.ResultRetcode();
         if(code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_NO_CHANGES)
           {
            RememberPosition(ticket, entry, stop, adjustedTarget, filledVolume);
            continue;
           }
         PrintFormat("Mercury Vx | target adjustment #%I64u rejected | %u %s",
                     ticket, code, trade.ResultRetcodeDescription());
        }
      ClosePosition(ticket, second, "filled target could not be aligned");
     }

   if(!ownPosition && observedPosition != 0)
     {
      nextEntry = (long)MathMax((double)nextEntry, (double)(second + CooldownSeconds));
      observedPosition = 0;
      checkedPosition = 0;
     }
   return symbolOccupied;
  }

bool SymbolHasOrder()
  {
   for(int index = OrdersTotal() - 1; index >= 0; --index)
     {
      if(OrderGetTicket(index) != 0 && OrderGetString(ORDER_SYMBOL) == _Symbol)
         return true;
     }
   return false;
  }

void Enter(const int direction, const MqlTick &tick, const long second, const string setup)
  {
   if(!CanTrade(direction) || SymbolHasOrder())
     {
      ++diagnostics.contract;
      return;
     }
   const double spread = tick.ask - tick.bid;
   const double atr = frames[0].atr;
   if(spread > atr * MaxSpreadToAtr)
     {
      ++diagnostics.spread;
      return;
     }

   const double gap = BrokerGap(SYMBOL_TRADE_STOPS_LEVEL);
   const double distance = MathMax(atr * StopAtrMultiple, spread + gap);
   const long riskTicks = (long)MathCeil(distance / tickSize - 1e-8);
   if(riskTicks <= 0 || spread > riskTicks * tickSize * MaxSpreadToRisk)
     {
      ++diagnostics.spread;
      return;
     }

   const double quote = direction > 0 ? tick.ask : tick.bid;
   const long entryTicks = (long)MathRound(quote / tickSize);
   const double entry = GridPrice(entryTicks);
   const double stop = GridPrice(entryTicks - direction * riskTicks);
   const double take = TargetPrice(direction, entry, stop);
   if(!QuotedStopsValid(direction, tick, stop, take, gap))
     {
      ++diagnostics.contract;
      return;
     }
   const double volume = OrderVolume(direction, entry, stop);
   if(volume < lotMin)
     {
      ++diagnostics.sizeOrMargin;
      return;
     }

   const ENUM_ORDER_TYPE side = direction > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin = 0.0;
   if(!OrderCalcMargin(side, _Symbol, volume, entry, margin) ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.80)
     {
      ++diagnostics.sizeOrMargin;
      return;
     }

   nextEntry = second + (int)MathMax(2, CooldownSeconds);
   const string comment = "Mercury Vx " + setup;
   if(direction > 0)
      trade.Buy(volume, _Symbol, entry, stop, take, comment);
   else
      trade.Sell(volume, _Symbol, entry, stop, take, comment);
   const uint code = trade.ResultRetcode();
   if(!Taken(code))
     {
      ++diagnostics.rejected;
      PrintFormat("Mercury Vx | order rejected | %u %s", code, trade.ResultRetcodeDescription());
     }
   else
     {
      ++diagnostics.accepted;
      MqlTick latest;
      if(SymbolInfoTick(_Symbol, latest))
         ManagePosition(latest, second);
     }
  }

bool InputsValid()
  {
   return MagicNumber > 0 && MaxDeviationPoints >= 0 && DecisionIntervalSeconds >= 1 &&
          CooldownSeconds >= 0 && MaxHoldSeconds >= 0 &&
          SessionStartHour >= 0 && SessionStartHour <= 23 && SessionEndHour >= 0 && SessionEndHour <= 23 &&
          RiskPerTradePct > 0.0 && RiskPerTradePct <= 100.0 &&
          DailyLossLimitPct > 0.0 && DailyLossLimitPct <= 100.0 && StopAtrMultiple > 0.0 &&
          MaxSpreadToRisk > 0.0 && MaxSpreadToRisk < 1.0 &&
          MaxSpreadToAtr > 0.0 && CommissionPerLotRoundTrip >= 0.0 &&
          MinimumSignal > 0.0 && MinimumSignal <= 1.0 &&
          MinimumMicroSignal > 0.0 && MinimumMicroSignal <= 1.0 &&
          OpposingTrendLimit >= 0.0 && OpposingTrendLimit <= 1.0 &&
          MinimumReportTrades >= 1 && MinimumReportDays >= 1;
  }

int OnInit()
  {
   inTester = (bool)MQLInfoInteger(MQL_TESTER);
   inOptimization = (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   if(!InputsValid())
     {
      Print("Mercury Vx | invalid inputs");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!inTester)
     {
      const long accountMode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
      const bool allowed = (ExecutionMode == ENABLE_DEMO && accountMode == ACCOUNT_TRADE_MODE_DEMO) ||
                           (ExecutionMode == ENABLE_REAL && accountMode == ACCOUNT_TRADE_MODE_REAL);
      if(!allowed)
        {
         Print("Mercury Vx | use Strategy Tester or select the matching account in ExecutionMode");
         return INIT_FAILED;
        }
     }

   tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   pointSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   priceDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(tickSize <= 0.0 || pointSize <= 0.0 || lotMin <= 0.0 || lotMax < lotMin || lotStep <= 0.0)
     {
      Print("Mercury Vx | broker returned invalid contract specifications for ", _Symbol);
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints((ulong)MaxDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetMarginMode();
   if(!trade.SetTypeFillingBySymbol(_Symbol))
     {
      const long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
      if(mode == SYMBOL_TRADE_EXECUTION_MARKET || mode == SYMBOL_TRADE_EXECUTION_EXCHANGE)
        {
         Print("Mercury Vx | symbol does not advertise FOK or IOC filling: ", _Symbol);
         return INIT_FAILED;
        }
      trade.SetTypeFilling(ORDER_FILLING_FOK);
     }

   if(!inTester)
     {
      accountKey = "MercuryVx." + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "." +
                   IntegerToString((long)HashText(AccountInfoString(ACCOUNT_SERVER) + "/" + _Symbol));
      lockKey = accountKey + ".active";
      GlobalVariableTemp(lockKey);
      ownsLock = GlobalVariableSetOnCondition(lockKey, 1.0, 0.0);
      if(!ownsLock)
        {
         Print("Mercury Vx | another instance is already attached to this symbol in this terminal");
         return INIT_FAILED;
        }
     }

   for(int i = 0; i < FRAME_COUNT; ++i)
      frames[i].bar = 0;
   for(int i = 0; i < QUOTE_SLOTS; ++i)
      quotes[i].second = 0;
   ZeroMemory(diagnostics);
   activeDay = 0;
   daysObserved = 0;
   daysAtTarget = 0;
   worstDayPct = 0.0;
   hasDayReturn = false;
   observedPosition = 0;
   checkedPosition = 0;
   nextDecision = 0;
   nextEntry = 0;
   nextClose = 0;
   PrintFormat("Mercury Vx | %s | %d indicator variants | %d strategy combinations",
               _Symbol, FAMILY_COUNT * PERIOD_COUNT * FRAME_COUNT,
               SETUP_COUNT * PERIOD_COUNT * FRAME_COUNT);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(csv != INVALID_HANDLE)
     {
      FileClose(csv);
      csv = INVALID_HANDLE;
     }
   if(ownsLock)
     {
      GlobalVariableSetOnCondition(lockKey, 0.0, 1.0);
      ownsLock = false;
     }
  }

void EvaluateEntry(const MqlTick &tick, const long second, const double mid)
  {
   if(ManagePosition(tick, second) || blockedToday || second < nextEntry || second < nextDecision)
      return;
   nextDecision = second + DecisionIntervalSeconds;
   if(!InTradingSession(tick.time))
      return;
   if(!RefreshFrames())
     {
      ++diagnostics.history;
      return;
     }
   double micro = 0.0;
   if(!MicroSignal(second, mid, micro))
     {
      ++diagnostics.tickWindow;
      return;
     }
   string setup = "";
   const int direction = ChooseDirection(micro, setup);
   if(direction != 0)
      Enter(direction, tick, second, setup);
   else
      ++diagnostics.signal;
  }

void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.time <= 0 || tick.bid <= 0.0 || tick.ask < tick.bid)
      return;
   const long second = tick.time_msc > 0 ? tick.time_msc / 1000 : (long)tick.time;
   const double mid = (tick.ask + tick.bid) / 2.0;
   RecordQuote(second, mid);

   if(inTester && !inOptimization && ExportDailyCsv && activeDay == 0)
     {
      const string name = "Mercury_Vx_" + IntegerToString((long)HashText(_Symbol)) + "_" +
                          IntegerToString((long)GetTickCount64()) + ".csv";
      csv = FileOpen(name, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
      if(csv != INVALID_HANDLE)
        {
         FileWrite(csv, "server_date", "start_equity", "end_equity", "return_pct", "target_50_pct");
         Print("Mercury Vx | daily CSV at ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", name);
        }
      else
         PrintFormat("Mercury Vx | failed to open daily CSV | error %d", GetLastError());
     }

   UpdateDay(tick.time);
   EvaluateEntry(tick, second, mid);
   lastEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  }

double OnTester()
  {
   const double endingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   WriteDay(endingEquity);
   const double trades = TesterStatistics(STAT_TRADES);
   const double winRate = trades > 0.0 ? 100.0 * TesterStatistics(STAT_PROFIT_TRADES) / trades : 0.0;
   const double netProfit = TesterStatistics(STAT_PROFIT);
   const double startingDeposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   const double netPct = startingDeposit > 0.0 ? 100.0 * netProfit / startingDeposit : 0.0;
   const double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   const bool enoughSample = trades >= MinimumReportTrades && daysObserved >= MinimumReportDays;
   const bool dailyTargetMet = daysObserved > 0 && daysAtTarget == daysObserved;
   const bool winRateMet = winRate > WinRateTargetPct;
   const bool pass = enoughSample && dailyTargetMet && winRateMet;
   PrintFormat("Mercury Vx | Trades=%.0f | WinRate=%.2f%% | Net=%.2f | EquityDD=%.2f%%",
               trades, winRate, netProfit, drawdown);
   const string worst = hasDayReturn ? DoubleToString(worstDayPct, 4) + "%" : "n/a";
   PrintFormat("Mercury Vx | Days >= 50%%: %d/%d | Worst day=%s | Sample=%s | Targets=%s",
               daysAtTarget, daysObserved, worst,
               enoughSample ? "ENOUGH" : "BELOW CONFIGURED MINIMUM",
               pass ? "PASS" : "FAIL");
   PrintFormat("Mercury Vx | Entry checks | History=%d TickWindow=%d Signal=%d Spread=%d Contract=%d SizeOrMargin=%d Rejected=%d Accepted=%d",
               diagnostics.history, diagnostics.tickWindow, diagnostics.signal, diagnostics.spread,
               diagnostics.contract, diagnostics.sizeOrMargin, diagnostics.rejected, diagnostics.accepted);
   if(csv != INVALID_HANDLE)
      FileFlush(csv);

   const double dayScore = daysObserved > 0 ? 1000.0 * daysAtTarget / daysObserved : 0.0;
   const double score = dayScore + winRate + 100.0 * Unit(worstDayPct / 100.0) +
                        50.0 * Unit(netPct / 100.0) -
                        100.0 * Unit(drawdown / 100.0);
   if(!enoughSample)
      return score - 10000.0;
   return pass ? 10000.0 + score : score;
  }
