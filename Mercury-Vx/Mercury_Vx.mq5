#property strict
#property version     "1.40"
#property description "Mercury Vx | MT5 scalper and higher-timeframe research"
#include <Trade/Trade.mqh>

enum MercuryExecution
  {
   TESTER_ONLY = 0,
   ENABLE_DEMO = 1,
   ENABLE_REAL = 2
  };

enum MercurySignal
  {
   AUTO_BY_SYMBOL = 0,
   LEGACY_MICRO = 1,
   XAU_MEAN_REVERSION = 2,
   BTC_WICK_RECLAIM = 3,
   RESEARCH_BY_SYMBOL = 4,
   RESEARCH_CUSTOM = 5
  };

enum MercuryResearchPattern
  {
   RANGE_BREAKOUT = 0,
   TREND_PULLBACK = 1,
   WICK_REVERSAL = 2,
   TREND_CONTINUATION = 3,
   EXHAUSTION_REVERSAL = 4,
   COMPRESSION_BREAKOUT = 5
  };

enum MercuryExitPolicy
  {
   PROFILE_TIMED = 0,
   BRACKETS_ONLY = 1
  };

input group "Execution"
input MercuryExecution ExecutionMode = TESTER_ONLY;
input ulong MagicNumber = 60261122;
input int MaxDeviationPoints = 20;
input int DecisionIntervalSeconds = 2;
input int CooldownSeconds = 20;
input MercuryExitPolicy ExitPolicy = PROFILE_TIMED;
input int MaxHoldSeconds = 180; // LEGACY_MICRO only. 0 disables the time exit.
input int SessionStartHour = 0;
input int SessionEndHour = 0;   // Same as start means all hours. Broker server time.

input group "Position risk"
input double RiskPerTradePct = 0.25;
input double DailyLossLimitPct = 2.00;
input double MaxEquityDrawdownPct = 10.00; // 0 disables the peak-equity limit.
input double StopAtrMultiple = 0.65;
input double MaxSpreadToRisk = 0.20;
input double MaxSpreadToAtr = 0.25;
input double CommissionPerLotRoundTrip = 0.0; // Account currency.

input group "Signal"
input MercurySignal SignalModel = RESEARCH_BY_SYMBOL;
input double MinimumSignal = 0.32;
input double MinimumMicroSignal = 0.13;
input double MinimumTrendAlignment = 0.15; // Set to 0 to use the previous directional filter.
input double OpposingTrendLimit = 0.20;

input group "Higher-timeframe research"
input ENUM_TIMEFRAMES ResearchTimeframe = PERIOD_M15; // Custom profile.
input MercuryResearchPattern ResearchPattern = COMPRESSION_BREAKOUT; // Custom profile.
input int ResearchLookback = 18; // Custom profile.
input bool ResearchLongOnly = true; // Custom profile.
input double ResearchStopATR = 1.50; // Custom profile.
input double ResearchRewardRisk = 3.0; // Custom profile.
input double ResearchRiskPct = 0.75; // Both research profiles.

input group "Backtest report"
input int MinimumReportTrades = 100;
input int MinimumReportDays = 20;
input bool ExportAnnualCsv = true;
input bool ExportDailyCsv = false;

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
   int minLot;
   int equityFloor;
   int rejected;
   int accepted;
  };

struct YearSummary
  {
   int year;
   datetime firstTick;
   datetime lastTick;
   long tickCount;
   int entryDeals;
   int exitDeals;
   double startEquity;
   double endEquity;
   double peak;
   double maxDrawdownPct;
  };

CTrade trade;
EntryDiagnostics diagnostics;
YearSummary testYears[];
int activeYearIndex = -1;
datetime coverageDay = 0;
datetime firstTestTick = 0;
datetime lastTestTick = 0;
datetime firstEntryDeal = 0;
datetime lastExitDeal = 0;
long observedTickCount = 0;
ENUM_TIMEFRAMES timeframes[FRAME_COUNT] = {PERIOD_M1, PERIOD_M2, PERIOD_M3, PERIOD_M5};
double frameWeight[FRAME_COUNT] = {0.46, 0.25, 0.17, 0.12};
FrameSignal frames[FRAME_COUNT];
QuoteSample quotes[QUOTE_SLOTS];
int lookbackSeconds[3] = {5, 15, 30};
double microWeight[3] = {0.45, 0.35, 0.20};

bool inTester = false;
bool inOptimization = false;
bool ownsLock = false;
string accountKey, lockKey, dayKey, peakKey;
double tickSize = 0.0;
double pointSize = 0.0;
int priceDigits = 0;
double lotMin = 0.0;
double lotMax = 0.0;
double lotStep = 0.0;
MercurySignal signalInUse = LEGACY_MICRO;
int positionMaxSeconds = 0;
double entryStopMultiple = 0.0;
double entryMaxSpreadToRisk = 0.0;
double entryRewardRisk = 3.0;
double activeRiskPct = 0.0;
int activeCooldown = 0;
bool researchMode = false;
ENUM_TIMEFRAMES activeResearchTimeframe = PERIOD_M15;
MercuryResearchPattern activeResearchPattern = COMPRESSION_BREAKOUT;
int activeResearchLookback = 18;
bool activeResearchLongOnly = true;
datetime seenResearchBar = 0;
int researchBarsObserved = 0;
datetime seenMinute = 0;
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
double bestDayPct = 0.0;
bool hasDayReturn = false;
datetime activeDay = 0;
double dayStartEquity = 0.0;
double lastEquity = 0.0;
bool blockedToday = false;
double peakEquity = 0.0;
bool blockedByDrawdown = false;
int stopLossDeals = 0;
int takeProfitDeals = 0;
int otherExitDeals = 0;
int acceptedTimeExits = 0;

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
   if(MinimumTrendAlignment > 0.0 &&
      MathMin(direction * frames[0].trend, direction * higherTrend) < MinimumTrendAlignment)
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

void ConfigureSignal()
  {
   signalInUse = SignalModel;
   researchMode = SignalModel == RESEARCH_BY_SYMBOL || SignalModel == RESEARCH_CUSTOM;
   const string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   const string quote = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   if(signalInUse == AUTO_BY_SYMBOL)
     {
      if(base == "XAU" && quote == "USD")
         signalInUse = XAU_MEAN_REVERSION;
      else if(base == "BTC" && quote == "USD")
         signalInUse = BTC_WICK_RECLAIM;
      else
         signalInUse = LEGACY_MICRO;
     }
   positionMaxSeconds = MaxHoldSeconds;
   entryStopMultiple = StopAtrMultiple;
   entryMaxSpreadToRisk = MaxSpreadToRisk;
   entryRewardRisk = RewardToRisk;
   activeRiskPct = RiskPerTradePct;
   activeCooldown = CooldownSeconds;
   if(researchMode)
     {
      positionMaxSeconds = 48 * 60 * 60;
      entryMaxSpreadToRisk = 0.15;
      activeRiskPct = ResearchRiskPct;
      activeCooldown = 60;
      activeResearchTimeframe = ResearchTimeframe;
      activeResearchPattern = ResearchPattern;
      activeResearchLookback = ResearchLookback;
      activeResearchLongOnly = ResearchLongOnly;
      entryStopMultiple = ResearchStopATR;
      entryRewardRisk = ResearchRewardRisk;
      if(signalInUse == RESEARCH_BY_SYMBOL && base == "XAU" && quote == "USD")
        {
         activeResearchTimeframe = PERIOD_M15;
         activeResearchPattern = COMPRESSION_BREAKOUT;
         activeResearchLookback = 18;
         activeResearchLongOnly = true;
         entryStopMultiple = 1.50;
         entryRewardRisk = 3.0;
        }
      else if(signalInUse == RESEARCH_BY_SYMBOL && base == "BTC" && quote == "USD")
        {
         activeResearchTimeframe = PERIOD_H1;
         activeResearchPattern = COMPRESSION_BREAKOUT;
         activeResearchLookback = 32;
         activeResearchLongOnly = false;
         entryStopMultiple = 1.00;
         entryRewardRisk = 3.0;
        }
      else
         signalInUse = RESEARCH_CUSTOM;
      seenResearchBar = 0;
      researchBarsObserved = 0;
     }
   else if(signalInUse == XAU_MEAN_REVERSION)
     {
      positionMaxSeconds = 720;
      entryStopMultiple = 1.00;
      entryMaxSpreadToRisk = 0.14;
     }
   else if(signalInUse == BTC_WICK_RECLAIM)
     {
      positionMaxSeconds = 300;
      entryStopMultiple = 1.80;
      entryMaxSpreadToRisk = 0.10;
     }
   if(ExitPolicy == BRACKETS_ONLY)
      positionMaxSeconds = 0;
  }

int ChooseBarDirection(const MqlRates &bars[], const double atr)
  {
   const double width = bars[0].high - bars[0].low;
   if(width <= 0.0)
      return 0;
   const double closeLocation = (bars[0].close - bars[0].low) / width;
   if(signalInUse == XAU_MEAN_REVERSION)
     {
      double mean = 0.0;
      for(int i = 1; i <= 24; ++i)
         mean += bars[i].close;
      mean /= 24.0;
      const double distance = (bars[0].close - mean) / (MathSqrt(24.0) * atr);
      const double change = (bars[0].close - bars[1].close) / atr;
      if(distance > 0.65 && change < -0.18 && closeLocation < 0.60)
         return -1;
      if(distance < -0.65 && change > 0.18 && closeLocation > 0.40)
         return 1;
      return 0;
     }

   const double body = bars[0].close - bars[0].open;
   if(width <= 1.25 * atr || body == 0.0)
      return 0;
   const double trend = (bars[1].close - bars[49].close) / (7.0 * atr);
   const int direction = body > 0.0 ? 1 : -1;
   if(direction * trend <= -0.5 || direction * (closeLocation - 0.5) <= 0.28)
      return 0;
   const double level = direction > 0 ? bars[0].low : bars[0].high;
   for(int i = 1; i <= 48; ++i)
     {
      const double previousLevel = direction > 0 ? bars[i].low : bars[i].high;
      if(direction * (previousLevel - level) <= 0.0)
         return 0;
     }
   return direction;
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
   if(SessionStartHour == SessionEndHour)
      return true;
   MqlDateTime parts;
   if(!TimeToStruct(when, parts))
      return false;
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
   if(!hasDayReturn || result > bestDayPct)
      bestDayPct = result;
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

int FindYear(const int year)
  {
   for(int i = ArraySize(testYears) - 1; i >= 0; --i)
      if(testYears[i].year == year)
         return i;
   return -1;
  }

void MarkAnnualEquity(const double equity)
  {
   if(activeYearIndex < 0)
      return;
   testYears[activeYearIndex].endEquity = equity;
   const double peak = MathMax(testYears[activeYearIndex].peak, equity);
   testYears[activeYearIndex].peak = peak;
   if(peak > 0.0)
      testYears[activeYearIndex].maxDrawdownPct =
         MathMax(testYears[activeYearIndex].maxDrawdownPct, 100.0 * (peak - equity) / peak);
  }

void ObserveTestTick(const datetime when, const double previousEquity, const double equity)
  {
   if(!inTester || inOptimization)
      return;
   if(firstTestTick == 0)
      firstTestTick = when;
   lastTestTick = when;
   ++observedTickCount;
   if(coverageDay != activeDay)
     {
      coverageDay = activeDay;
      MqlDateTime parts;
      if(!TimeToStruct(when, parts))
         return;
      activeYearIndex = FindYear(parts.year);
      if(activeYearIndex < 0)
        {
         const int slot = ArraySize(testYears);
         if(ArrayResize(testYears, slot + 1, 16) != slot + 1)
            return;
         ZeroMemory(testYears[slot]);
         activeYearIndex = slot;
         testYears[slot].year = parts.year;
         testYears[slot].firstTick = when;
         testYears[slot].startEquity = observedTickCount == 1 ? equity : previousEquity;
         testYears[slot].peak = testYears[slot].startEquity;
        }
     }
   if(activeYearIndex < 0)
      return;
   testYears[activeYearIndex].lastTick = when;
   ++testYears[activeYearIndex].tickCount;
   MarkAnnualEquity(equity);
  }

double DrawdownFloor()
  {
   return MaxEquityDrawdownPct > 0.0 ? peakEquity * (1.0 - MaxEquityDrawdownPct / 100.0) : 0.0;
  }

void UpdateDrawdown(const double equity)
  {
   if(MaxEquityDrawdownPct <= 0.0 || blockedByDrawdown)
      return;
   if(equity > peakEquity)
     {
      peakEquity = equity;
      if(!inTester)
         GlobalVariableSet(peakKey, peakEquity);
     }
   if(peakEquity > 0.0 && equity <= DrawdownFloor())
     {
      blockedByDrawdown = true;
      if(!inTester && GlobalVariableSet(peakKey, -peakEquity) != 0)
         GlobalVariablesFlush();
      PrintFormat("Mercury Vx | drawdown halt | peak=%.2f equity=%.2f configured=%.2f%%",
                  peakEquity, equity, MaxEquityDrawdownPct);
     }
  }

double GridPrice(const long ticks)
  {
   return NormalizeDouble(ticks * tickSize, priceDigits);
  }

double TargetPrice(const int direction, const double entry, const double stop)
  {
   const double theoretical = entry + direction * entryRewardRisk * MathAbs(entry - stop);
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

double RiskBudget(const double equity)
  {
   const double dailyFloor = dayStartEquity * (1.0 - DailyLossLimitPct / 100.0);
   const double remainingRisk = equity - MathMax(dailyFloor, DrawdownFloor());
   return MathMin(equity * activeRiskPct / 100.0, remainingRisk);
  }

double OrderVolume(const int direction, const double entry, const double stop, const double spread)
  {
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   const double riskBudget = RiskBudget(equity) * SizingReserve;
   double minimumRisk = 0.0;
   const double sizingStop = researchMode ? stop - direction * 0.50 * spread : stop;
   if(sizingStop <= 0.0 || !RiskCash(direction, lotMin, entry, sizingStop, minimumRisk))
      return 0.0;
   if(minimumRisk > riskBudget)
     {
      ++diagnostics.minLot;
      const double floor = DrawdownFloor();
      if(floor > 0.0 && minimumRisk > SizingReserve * (equity - floor))
         ++diagnostics.equityFloor;
      return 0.0;
     }
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
     {
      if(reason == "time exit")
         ++acceptedTimeExits;
      PrintFormat("Mercury Vx | close #%I64u | %s", ticket, reason);
     }
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
      if(blockedByDrawdown)
        {
         ClosePosition(ticket, second, "peak equity drawdown limit");
         continue;
        }
      if(blockedToday || stop <= 0.0 || take <= 0.0)
        {
         ClosePosition(ticket, second, blockedToday ? "daily equity limit" : "missing protective order");
         continue;
        }
      if(positionMaxSeconds > 0 && second - PositionGetInteger(POSITION_TIME) >= positionMaxSeconds)
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
      const double limit = RiskBudget(equityAtEntry);
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
      nextEntry = (long)MathMax((double)nextEntry, (double)(second + activeCooldown));
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

void Enter(const int direction, const MqlTick &tick, const long second, const string setup, const double atr)
  {
   if(!CanTrade(direction) || SymbolHasOrder())
     {
      ++diagnostics.contract;
      return;
     }
   const double spread = tick.ask - tick.bid;
   if(spread > atr * MaxSpreadToAtr)
     {
      ++diagnostics.spread;
      return;
     }

   const double gap = BrokerGap(SYMBOL_TRADE_STOPS_LEVEL);
   const double distance = MathMax(atr * entryStopMultiple, spread + gap);
   const long riskTicks = (long)MathCeil(distance / tickSize - 1e-8);
   if(riskTicks <= 0 || spread > riskTicks * tickSize * entryMaxSpreadToRisk)
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
   const double volume = OrderVolume(direction, entry, stop, spread);
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

   nextEntry = second + (int)MathMax(2, activeCooldown);
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
          MaxEquityDrawdownPct >= 0.0 && MaxEquityDrawdownPct <= 100.0 &&
          MaxSpreadToRisk > 0.0 && MaxSpreadToRisk < 1.0 &&
          MaxSpreadToAtr > 0.0 && CommissionPerLotRoundTrip >= 0.0 &&
          MinimumSignal > 0.0 && MinimumSignal <= 1.0 &&
          MinimumMicroSignal > 0.0 && MinimumMicroSignal <= 1.0 &&
          MinimumTrendAlignment >= 0.0 && MinimumTrendAlignment <= 1.0 &&
          OpposingTrendLimit >= 0.0 && OpposingTrendLimit <= 1.0 &&
          ResearchRiskPct > 0.0 && ResearchRiskPct <= 5.0 &&
          (ResearchTimeframe == PERIOD_M5 || ResearchTimeframe == PERIOD_M15 ||
           ResearchTimeframe == PERIOD_M30 || ResearchTimeframe == PERIOD_H1) &&
          ResearchLookback >= 4 && ResearchLookback <= 32 &&
          ResearchStopATR > 0.0 && ResearchRewardRisk >= 1.0 &&
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
   ConfigureSignal();
   if(!inTester)
     {
      const long accountMode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
      const bool allowed = (ExecutionMode == ENABLE_DEMO && accountMode == ACCOUNT_TRADE_MODE_DEMO) ||
                           (!researchMode && ExecutionMode == ENABLE_REAL &&
                            accountMode == ACCOUNT_TRADE_MODE_REAL);
      if(!allowed)
        {
         Print(researchMode ? "Mercury Vx | research profiles are available in Strategy Tester and demo" :
               "Mercury Vx | use Strategy Tester or select the matching account in ExecutionMode");
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

   peakEquity = 0.0;
   blockedByDrawdown = false;
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
      peakKey = accountKey + ".peak." + IntegerToString((long)HashText(IntegerToString((long)MagicNumber)));
      double savedPeak = 0.0;
      if(MaxEquityDrawdownPct > 0.0 && GlobalVariableGet(peakKey, savedPeak) && MathIsValidNumber(savedPeak))
        {
         peakEquity = MathAbs(savedPeak);
         blockedByDrawdown = savedPeak < 0.0;
         if(blockedByDrawdown)
            Print("Mercury Vx | peak-equity drawdown halt restored for ", _Symbol);
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
   bestDayPct = 0.0;
   hasDayReturn = false;
   observedPosition = 0;
   checkedPosition = 0;
   nextDecision = 0;
   nextEntry = 0;
   nextClose = 0;
   stopLossDeals = 0;
   takeProfitDeals = 0;
   otherExitDeals = 0;
   acceptedTimeExits = 0;
   ArrayResize(testYears, 0);
   seenMinute = 0;
   activeYearIndex = -1;
   coverageDay = 0;
   firstTestTick = 0;
   lastTestTick = 0;
   firstEntryDeal = 0;
   lastExitDeal = 0;
   observedTickCount = 0;
   PrintFormat("Mercury Vx 1.40 | %s | Signal=%s | ExitPolicy=%s | Hold=%d seconds | SL=%.2f ATR | Spread/SL<=%.2f",
               _Symbol, EnumToString(signalInUse), EnumToString(ExitPolicy), positionMaxSeconds,
               entryStopMultiple, entryMaxSpreadToRisk);
   if(researchMode)
      PrintFormat("Mercury Vx | Research timeframe=%s pattern=%s lookback=%d longOnly=%s TP/SL=%.2f risk=%.2f%%",
                  EnumToString(activeResearchTimeframe), EnumToString(activeResearchPattern),
                  activeResearchLookback, activeResearchLongOnly ? "true" : "false", entryRewardRisk, activeRiskPct);
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

void EvaluateBarEntry(const MqlTick &tick, const long second, const datetime minute)
  {
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   const int count = signalInUse == XAU_MEAN_REVERSION ? 25 : 50;
   if(CopyRates(_Symbol, PERIOD_M1, 1, count, bars) != count || bars[0].time != minute - 60)
     {
      ++diagnostics.history;
      return;
     }
   const double atr = AverageTrueRange(bars);
   if(!MathIsValidNumber(atr) || atr <= 0.0)
     {
      ++diagnostics.history;
      return;
     }
   const int direction = ChooseBarDirection(bars, atr);
   if(direction == 0)
     {
      ++diagnostics.signal;
      return;
     }
   const string setup = signalInUse == XAU_MEAN_REVERSION ? "XAU mean reversion" : "BTC wick reclaim";
   Enter(direction, tick, second, setup, atr);
  }

int SwingSignal(const MqlRates &bars[], int family, int fast, int slow,
                int longOnly, double atr)
  {
   if(atr <= 0.0)
      return 0;
   const double width = bars[0].high - bars[0].low;
   if(width <= 0.0)
      return 0;
   const double loc = (bars[0].close-bars[0].low)/width;
   const double body = (bars[0].close-bars[0].open)/atr;
   const double trend = (bars[1].close-bars[slow].close)/(MathSqrt((double)slow)*atr);
   double upper = bars[1].high, lower = bars[1].low, mean = 0.0;
   for(int i=1; i<=fast; ++i)
     {
      upper = MathMax(upper,bars[i].high);
      lower = MathMin(lower,bars[i].low);
      mean += bars[i].close;
     }
   mean /= fast;
   int direction = 0;
   if(family==0)
     {
      if(trend>0.30 && bars[0].close>upper && body>0.35) direction=1;
      if(trend<-0.30 && bars[0].close<lower && body<-0.35) direction=-1;
     }
   else if(family==1)
     {
      if(trend>0.55 && bars[1].close<mean && bars[0].close>mean && loc>0.65 && body>0.25) direction=1;
      if(trend<-0.55 && bars[1].close>mean && bars[0].close<mean && loc<0.35 && body<-0.25) direction=-1;
     }
   else if(family==2)
     {
      if(trend>-0.65 && bars[0].low<lower && bars[0].close>lower && loc>0.73) direction=1;
      if(trend<0.65 && bars[0].high>upper && bars[0].close<upper && loc<0.27) direction=-1;
     }
   else if(family==3)
     {
      const double upperRecent=MathMax(MathMax(bars[1].high,bars[2].high),bars[3].high);
      const double lowerRecent=MathMin(MathMin(bars[1].low,bars[2].low),bars[3].low);
      if(trend>0.95 && bars[0].close>upperRecent && body>0.70 && loc>0.72) direction=1;
      if(trend<-0.95 && bars[0].close<lowerRecent && body<-0.70 && loc<0.28) direction=-1;
     }
   else if(family==4)
     {
      const double stretch=(bars[1].close-bars[fast].close)/(MathSqrt((double)fast)*atr);
      if(stretch<-1.30 && body>0.35 && loc>0.65 && trend>-1.80) direction=1;
      if(stretch>1.30 && body<-0.35 && loc<0.35 && trend<1.80) direction=-1;
     }
   else if(family==5)
     {
      if((upper-lower)<2.5*MathSqrt((double)fast)*atr)
        {
         if(bars[0].close>upper && body>0.60 && loc>0.72) direction=1;
         if(bars[0].close<lower && body<-0.60 && loc<0.28) direction=-1;
        }
     }
   return longOnly!=0 && direction<0 ? 0 : direction;
  }

void EvaluateResearchEntry(const MqlTick &tick, const long second)
  {
   const int span = PeriodSeconds(activeResearchTimeframe);
   const datetime open = (datetime)((long)tick.time / span * span);
   const bool newResearchBar = open != seenResearchBar;
   if(newResearchBar)
     {
      seenResearchBar = open;
      ++researchBarsObserved;
     }

   if(ManagePosition(tick, second) || !newResearchBar || blockedToday ||
      blockedByDrawdown || second < nextEntry || !InTradingSession(tick.time))
      return;

   const int slow = 4 * activeResearchLookback;
   if(researchBarsObserved <= slow + 2)
     {
      ++diagnostics.history;
      return;
     }
   MqlRates bars[];
   ArraySetAsSeries(bars, true);
   if(CopyRates(_Symbol, activeResearchTimeframe, 1, slow + 1, bars) != slow + 1 ||
      bars[0].time != open - span)
     {
      ++diagnostics.history;
      return;
     }

   const double atr = AverageTrueRange(bars);
   if(!MathIsValidNumber(atr) || atr <= 0.0)
     {
      ++diagnostics.history;
      return;
     }
   const int direction = SwingSignal(bars, (int)activeResearchPattern, activeResearchLookback,
                                     slow, activeResearchLongOnly ? 1 : 0, atr);
   if(direction != 0)
      Enter(direction, tick, second, "HTF research", atr);
   else
      ++diagnostics.signal;
  }

void EvaluateEntry(const MqlTick &tick, const long second, const double mid)
  {
   if(researchMode)
     {
      EvaluateResearchEntry(tick, second);
      return;
     }
   const datetime minute = (datetime)((long)tick.time / 60 * 60);
   const bool newMinute = minute != seenMinute;
   seenMinute = minute;
   if(ManagePosition(tick, second) || blockedToday || blockedByDrawdown ||
      second < nextEntry)
      return;
   if(signalInUse == LEGACY_MICRO ? second < nextDecision : !newMinute)
      return;
   if(signalInUse == LEGACY_MICRO)
      nextDecision = second + DecisionIntervalSeconds;
   if(!InTradingSession(tick.time))
      return;
   if(signalInUse != LEGACY_MICRO)
     {
      EvaluateBarEntry(tick, second, minute);
      return;
     }
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
      Enter(direction, tick, second, setup, frames[0].atr);
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
   if(signalInUse == LEGACY_MICRO)
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

   const double previousEquity = lastEquity;
   UpdateDay(tick.time);
   ObserveTestTick(tick.time, previousEquity, lastEquity);
   UpdateDrawdown(lastEquity);
   EvaluateEntry(tick, second, mid);
   lastEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   MarkAnnualEquity(lastEquity);
  }

void SummarizeTesterDeals()
  {
   if(firstTestTick == 0 || !HistorySelect(firstTestTick, TimeCurrent()))
      return;
   const int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
     {
      const ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
         continue;
      const long type = HistoryDealGetInteger(deal, DEAL_TYPE);
      if(type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL)
         continue;
      const datetime when = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      MqlDateTime parts;
      if(!TimeToStruct(when, parts))
         continue;
      const int slot = FindYear(parts.year);
      const long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
        {
         if(firstEntryDeal == 0 || when < firstEntryDeal)
            firstEntryDeal = when;
         if(slot >= 0)
            ++testYears[slot].entryDeals;
        }
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
        {
         if(when > lastExitDeal)
            lastExitDeal = when;
         if(slot >= 0)
            ++testYears[slot].exitDeals;
         const long reason = HistoryDealGetInteger(deal, DEAL_REASON);
         if(reason == DEAL_REASON_SL)
            ++stopLossDeals;
         else if(reason == DEAL_REASON_TP)
            ++takeProfitDeals;
         else
            ++otherExitDeals;
        }
     }
  }

string ReportDate(const datetime when)
  {
   return when > 0 ? TimeToString(when, TIME_DATE | TIME_SECONDS) : "n/a";
  }

void WriteAnnualReport()
  {
   if(firstTestTick == 0)
      return;
   PrintFormat("Mercury Vx | Coverage | FirstTick=%s LastTick=%s ObservedTicks=%I64d FirstEntry=%s LastExit=%s",
               ReportDate(firstTestTick), ReportDate(lastTestTick), observedTickCount,
               ReportDate(firstEntryDeal), ReportDate(lastExitDeal));
   if(!ExportAnnualCsv)
      return;
   const string name = "Mercury_Vx_Annual_" + IntegerToString((long)HashText(_Symbol)) + "_" +
                       IntegerToString((long)GetTickCount64()) + ".csv";
   const int file = FileOpen(name, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI, ';');
   if(file == INVALID_HANDLE)
     {
      PrintFormat("Mercury Vx | failed to open annual CSV | error %d", GetLastError());
      return;
     }
   FileWrite(file, "symbol", "server_year", "first_tick", "last_tick", "observed_ticks",
             "entry_deals", "exit_deals", "start_equity", "end_equity", "net_equity",
             "return_pct", "max_equity_drawdown_pct");
   for(int i = 0; i < ArraySize(testYears); ++i)
     {
      const double start = testYears[i].startEquity;
      const double end = testYears[i].endEquity;
      const string change = start > 0.0 ? DoubleToString(100.0 * (end / start - 1.0), 6) : "";
      FileWrite(file, _Symbol, testYears[i].year, ReportDate(testYears[i].firstTick), ReportDate(testYears[i].lastTick),
                testYears[i].tickCount, testYears[i].entryDeals, testYears[i].exitDeals, DoubleToString(start, 2),
                DoubleToString(end, 2), DoubleToString(end - start, 2), change,
                DoubleToString(testYears[i].maxDrawdownPct, 6));
     }
   FileClose(file);
   Print("Mercury Vx | annual CSV at ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", name);
  }

struct TargetAssessment
  {
   double winRate;
   double averageWin;
   double averageLoss;
   double realizedRewardRisk;
   bool hasRealizedRatio;
   bool enoughSample;
   bool winRateMet;
   bool rewardRiskMet;
   bool dailyTargetMet;
   bool profitable;
   bool pass;
  };

void AssessTargets(const double trades, const double wins, const double losses,
                   const double grossProfit, const double grossLoss, const double net,
                   const int observedDays, const int daysCheckedAtTarget,
                   TargetAssessment &assessment)
  {
   assessment.winRate = trades > 0.0 ? 100.0 * wins / trades : 0.0;
   assessment.averageWin = wins > 0.0 ? grossProfit / wins : 0.0;
   assessment.averageLoss = losses > 0.0 ? grossLoss / losses : 0.0;
   assessment.hasRealizedRatio = assessment.averageWin > 0.0 && assessment.averageLoss > 0.0;
   assessment.realizedRewardRisk =
      assessment.hasRealizedRatio ? assessment.averageWin / assessment.averageLoss : 0.0;
   assessment.enoughSample = trades >= MinimumReportTrades && observedDays >= MinimumReportDays;
   assessment.winRateMet = trades > 0.0 && 100.0 * wins >= WinRateTargetPct * trades;
   assessment.rewardRiskMet = assessment.hasRealizedRatio && assessment.realizedRewardRisk >= RewardToRisk;
   assessment.dailyTargetMet = observedDays > 0 && daysCheckedAtTarget == observedDays;
   assessment.profitable = net > 0.0;
   assessment.pass = assessment.enoughSample && assessment.winRateMet && assessment.rewardRiskMet &&
                     assessment.dailyTargetMet && assessment.profitable;
  }

double OnTester()
  {
   const double endingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   WriteDay(endingEquity);
   if(!inOptimization)
     {
      MarkAnnualEquity(endingEquity);
      SummarizeTesterDeals();
      WriteAnnualReport();
     }
   const double trades = TesterStatistics(STAT_TRADES);
   const double wins = TesterStatistics(STAT_PROFIT_TRADES);
   const double losses = TesterStatistics(STAT_LOSS_TRADES);
   const double netProfit = TesterStatistics(STAT_PROFIT);
   const double grossProfit = TesterStatistics(STAT_GROSS_PROFIT);
   const double grossLoss = MathAbs(TesterStatistics(STAT_GROSS_LOSS));
   const double startingDeposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   const double netPct = startingDeposit > 0.0 ? 100.0 * netProfit / startingDeposit : 0.0;
   const double drawdown = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   TargetAssessment assessment;
   AssessTargets(trades, wins, losses, grossProfit, grossLoss, netProfit, daysObserved, daysAtTarget, assessment);
   PrintFormat("Mercury Vx | Trades=%.0f | WinRate=%.2f%% | Net=%.2f | EquityDD=%.2f%%",
               trades, assessment.winRate, netProfit, drawdown);
   if(assessment.hasRealizedRatio)
     {
      const double averageWin = assessment.averageWin;
      const double averageLoss = assessment.averageLoss;
      PrintFormat("Mercury Vx | AvgWin=%.2f | AvgLoss=%.2f | RealizedRewardRisk=%.3f | BreakEvenWinsOrLosses=%.2f%% | ProfitFactor=%.3f",
                  averageWin, averageLoss, assessment.realizedRewardRisk,
                  100.0 * averageLoss / (averageWin + averageLoss), grossProfit / grossLoss);
     }
   const string realized = assessment.hasRealizedRatio ? DoubleToString(assessment.realizedRewardRisk, 3) : "n/a";
   const string dailyBest = hasDayReturn ? DoubleToString(bestDayPct, 4) + "%" : "n/a";
   const string dailyWorst = hasDayReturn ? DoubleToString(worstDayPct, 4) + "%" : "n/a";
   const string result = assessment.pass ? "PASS" : "FAIL";
   PrintFormat("Mercury Vx | Targets=%s | Sample=%s | WinRateAtLeast75=%s | RealizedRewardRisk=%s | RewardRiskAtLeast3=%s | NetProfitPositive=%s",
               result, assessment.enoughSample ? "SUFFICIENT" : "INSUFFICIENT",
               assessment.winRateMet ? "YES" : "NO", realized,
               assessment.rewardRiskMet ? "YES" : "NO", assessment.profitable ? "YES" : "NO");
   PrintFormat("Mercury Vx | Daily equity | DaysAt50Pct=%d/%d | AllDaysAt50Pct=%s | Best=%s | Worst=%s",
               daysAtTarget, daysObserved, assessment.dailyTargetMet ? "YES" : "NO", dailyBest, dailyWorst);
   PrintFormat("Mercury Vx | Exit deals | SL=%d TP=%d Other=%d | AcceptedTimeExitRequests=%d | DrawdownHalt=%s",
               stopLossDeals, takeProfitDeals, otherExitDeals, acceptedTimeExits,
               blockedByDrawdown ? "YES" : "NO");
   PrintFormat("Mercury Vx | Entry checks | History=%d TickWindow=%d Signal=%d Spread=%d Contract=%d SizeOrMargin=%d Rejected=%d Accepted=%d",
               diagnostics.history, diagnostics.tickWindow, diagnostics.signal, diagnostics.spread,
               diagnostics.contract, diagnostics.sizeOrMargin, diagnostics.rejected, diagnostics.accepted);
   PrintFormat("Mercury Vx | Entry checks | MinLotAboveRiskBudget=%d MinLotAboveDrawdownBudget=%d",
               diagnostics.minLot, diagnostics.equityFloor);
   if(csv != INVALID_HANDLE)
      FileFlush(csv);

   const double score = 100.0 * Unit(netPct / 100.0) - drawdown + 0.10 * assessment.winRate;
   if(!assessment.enoughSample)
      return score - 30000.0;
   if(!assessment.profitable)
      return score - 20000.0;
   return assessment.pass ? 10000.0 + score : score - 10000.0;
  }
