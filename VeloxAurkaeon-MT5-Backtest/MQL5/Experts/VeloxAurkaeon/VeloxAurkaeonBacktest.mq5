#property strict
#property version "1.00"
#property description "VeloxAurkaeon Dev36 historical simulator for MT5 Strategy Tester."
#include "VeloxCore.mqh"
#include "VeloxLondon.mqh"

enum ReplaySource { MT5_BAR_PROXY, VELOX_OHLC_CSV, MT5_LONDON_TICKS };

input ReplaySource InpSource = MT5_BAR_PROXY;
input VeloxPolicy InpPolicy = ExampleEMA;
input string InpCsv = "";
input string InpReportPrefix = "velox_dev36";
input bool InpPaperNewsClear = false;
input bool InpConfirmHistoricalCosts = false;
input int InpServerUtcOffsetMinutes = 0;
input int InpPaperHistory = 2000;
input int InpQuantWindow = 24;
input int InpWarmupBars = 0;
input int InpDelayBars = 0;
input int InpSignalMaxAgeSeconds = -1;
input double InpInitialEquity = 10000.0;
input double InpTickSize = 0.01;
input double InpTickValue = 1.0;
input double InpPipSize = 0.1;
input double InpMinLots = 0.01;
input double InpMaxLots = 1.0;
input double InpLotStep = 0.01;
input double InpMarginPerLot = 5000.0;
input double InpCommissionPerLot = 7.0;
input double InpMinStopDistance = 0.50;
input double InpMaxSpreadPips = 5.0;
input double InpRiskPerTrade = 0.0025;
input double InpDailyLoss = 0.01;
input double InpWeeklyLoss = 0.025;
input double InpDrawdown = 0.05;
input double InpMaxOpenRisk = 0.01;
input double InpMarginReserve = 0.50;
input int InpSlippageTicks = 2;
input double InpEntryLotCap = 0;
input double InpLondonAllInExtraPips = 0.40;
input datetime InpLondonHoldoutFromUTC = D'2025.06.01 00:00:00';

VeloxReplay book;
ENUM_TIMEFRAMES frame;
int fills_file = INVALID_HANDLE, rejects_file = INVALID_HANDLE, summary_file = INVALID_HANDLE;
int equity_file = INVALID_HANDLE, london_file = INVALID_HANDLE;
int rejected_count = 0;
bool failed = false, csv_done = false;
datetime last_seen = 0;
datetime last_processed = 0;
long first_open = 0, london_day = -1;
int london_sessions = 0, london_pass = 0, london_holdout = 0;
double london_total[3];

bool IsPaper()
{
   return InpPolicy == ExampleEMA || InpPolicy == ExperimentDonchian;
}

string PolicyId()
{
   switch(InpPolicy)
   {
      case ExampleEMA: return "example-ema";
      case ExperimentDonchian: return "experiment-donchian";
      case LabRSI21: return "lab-rsi21";
      case LabADX18Burst: return "lab-adx18_burst";
      case LabSupertrend15_3: return "lab-supertrend15_3";
      case QuantTSMomentum: return "quant-ts_momentum";
      case QuantZReversion: return "quant-z_reversion";
      case QuantMultiHorizon: return "quant-multi_horizon_momentum";
      case QuantATRBreakout: return "quant-atr_breakout";
      case QuantVolatilityMomentum: return "quant-volatility_adjusted_momentum";
   }
   return "unknown";
}

string ClockText(const long utc)
{
   return TimeToString((datetime)utc, TIME_DATE | TIME_MINUTES | TIME_SECONDS);
}

void Fail(const string message)
{
   failed = true;
   Print("VeloxAurkaeon: ", message);
   TesterStop();
}

bool ValidRisk()
{
   return InpInitialEquity > 0 && InpRiskPerTrade > 0 && InpRiskPerTrade <= 0.01 &&
          InpDailyLoss > 0 && InpDailyLoss <= 0.03 &&
          InpWeeklyLoss > 0 && InpWeeklyLoss <= 0.06 &&
          InpDrawdown > 0 && InpDrawdown <= 0.10 &&
          InpMaxOpenRisk > 0 && InpMaxOpenRisk <= 0.03 &&
          InpMarginReserve > 0 && InpMarginReserve < 1 &&
          InpSlippageTicks >= 0 && InpSlippageTicks <= 20 &&
          InpDelayBars >= 0 && InpDelayBars <= 3 && InpSignalMaxAgeSeconds >= -1 &&
          InpWarmupBars >= 0 && InpEntryLotCap >= 0;
}

bool ValidContract()
{
   return InpTickSize > 0 && InpTickValue > 0 && InpPipSize > 0 &&
          InpMinLots > 0 && InpMaxLots >= InpMinLots && InpLotStep > 0 &&
          MathAbs(InpMinLots / InpLotStep - MathRound(InpMinLots / InpLotStep)) < 1e-8 &&
          MathAbs(InpMaxLots / InpLotStep - MathRound(InpMaxLots / InpLotStep)) < 1e-8 &&
          InpMarginPerLot > 0 && InpCommissionPerLot >= 0 &&
          InpMinStopDistance >= 0 && InpMaxSpreadPips > 0;
}

bool SymbolMatches(const string root, const string base, const string profit)
{
   return StringFind(_Symbol, root) >= 0 ||
          (SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE) == base &&
           SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT) == profit);
}

int OnInit()
{
   if(!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION))
   {
      Print("VeloxAurkaeon runs in a single Strategy Tester pass.");
      return INIT_FAILED;
   }
   if(StringLen(InpReportPrefix) == 0 || StringFind(InpReportPrefix, "/") >= 0 ||
      StringFind(InpReportPrefix, "\\") >= 0 ||
      InpServerUtcOffsetMinutes < -840 || InpServerUtcOffsetMinutes > 840)
      return INIT_PARAMETERS_INCORRECT;

   const int flags = FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON;
   if(InpSource == MT5_LONDON_TICKS)
   {
      if(InpLondonAllInExtraPips < 0 ||
         (!SymbolMatches("USDJPY", "USD", "JPY") && !SymbolMatches("EURUSD", "EUR", "USD")))
         return INIT_PARAMETERS_INCORRECT;
      london_file = FileOpen(InpReportPrefix + "_london.csv", flags, ',');
      if(london_file == INVALID_HANDLE) return INIT_FAILED;
      FileWrite(london_file, "day_london", "partition", "mode", "coverage", "regime", "disposition",
                "side", "entry_utc_epoch_ms", "exit_utc_epoch_ms", "pip_net_spread", "midpoint_pips", "pip_after_extra");
      Print("Velox Dev36 London replay. Select Every tick based on real ticks and verify data coverage.");
      return INIT_SUCCEEDED;
   }

   if(!ValidRisk() || !ValidContract() || InpPaperHistory < 31 || InpPaperHistory > 2000)
      return INIT_PARAMETERS_INCORRECT;
   if(InpSource == MT5_BAR_PROXY && !SymbolMatches("XAUUSD", "XAU", "USD"))
      return INIT_PARAMETERS_INCORRECT;
   if(InpSource == VELOX_OHLC_CSV && (InpCsv == "" || !InpConfirmHistoricalCosts ||
      InpCsv == InpReportPrefix + "_trades.csv" || InpCsv == InpReportPrefix + "_summary.csv" ||
      InpCsv == InpReportPrefix + "_equity.csv" || InpCsv == InpReportPrefix + "_rejections.csv"))
   {
      Print("Set InpCsv and confirm the historical per-bar financing schedule.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(IsPaper() && !InpPaperNewsClear)
   {
      Print("PAPER_ATTESTED mode requires explicit historical news clearance.");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpPolicy >= QuantTSMomentum &&
      !(InpQuantWindow == 24 || (InpPolicy == QuantZReversion ? InpQuantWindow == 16 : InpQuantWindow == 12)))
      return INIT_PARAMETERS_INCORRECT;

   frame = PERIOD_H4;
   if(InpPolicy == ExampleEMA || InpPolicy == LabADX18Burst) frame = PERIOD_H1;
   if(InpPolicy == ExperimentDonchian) frame = PERIOD_D1;
   Contract spec;
   spec.tick_size = InpTickSize;
   spec.tick_value = InpTickValue;
   spec.pip_size = InpPipSize;
   spec.lot_min = InpMinLots;
   spec.lot_max = InpMaxLots;
   spec.lot_step = InpLotStep;
   spec.margin = InpMarginPerLot;
   spec.commission = InpCommissionPerLot;
   spec.minimum_stop = InpMinStopDistance;
   spec.maximum_spread = InpMaxSpreadPips;
   RiskLimits risk;
   risk.starting_equity = InpInitialEquity;
   risk.risk_per_trade = InpRiskPerTrade;
   risk.max_daily = InpDailyLoss;
   risk.max_weekly = InpWeeklyLoss;
   risk.max_drawdown = InpDrawdown;
   risk.max_open_risk = InpMaxOpenRisk;
   risk.margin_reserve = InpMarginReserve;
   risk.entry_lot_cap = InpEntryLotCap;
   risk.slippage_ticks = InpSlippageTicks;
   risk.delay_bars = InpDelayBars;
   risk.max_signal_age = InpSignalMaxAgeSeconds;
   risk.first_trade_bar = InpWarmupBars;
   book.Configure(InpPolicy, spec, risk, InpQuantWindow, InpPaperHistory, PeriodSeconds(frame));

   fills_file = FileOpen(InpReportPrefix + "_trades.csv", flags, ',');
   rejects_file = FileOpen(InpReportPrefix + "_rejections.csv", flags, ',');
   summary_file = FileOpen(InpReportPrefix + "_summary.csv", flags, ',');
   equity_file = FileOpen(InpReportPrefix + "_equity.csv", flags, ',');
   if(fills_file == INVALID_HANDLE || rejects_file == INVALID_HANDLE ||
      summary_file == INVALID_HANDLE || equity_file == INVALID_HANDLE)
   {
      Print("Unable to open output files in ", TerminalInfoString(TERMINAL_COMMONDATA_PATH));
      return INIT_FAILED;
   }
   FileWrite(fills_file, "entry_utc", "exit_bar_close_utc", "side", "lots", "entry", "exit",
             "gross_pnl", "commission", "swap_cost", "net_pnl", "signal_known_utc", "reason");
   FileWrite(rejects_file, "bar_open_utc", "reason");
   FileWrite(equity_file, "bar_close_utc", "balance", "equity");
   Print("Velox Dev36 ", PolicyId(), ", outputs: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files");
   if(InpSource == MT5_BAR_PROXY)
      Print("BAR PROXY: MT5 bid OHLC plus a single bar spread, zero financing, fixed contract.");
   return INIT_SUCCEEDED;
}

void WriteFill(const Fill &fill)
{
   if(fill.side == 0) return;
   FileWrite(fills_file, ClockText(fill.entered), ClockText(fill.exited),
             fill.side > 0 ? "BUY" : "SELL", DoubleToString(fill.lots, 8),
             DoubleToString(fill.entry, 10), DoubleToString(fill.exit_price, 10),
             DoubleToString(fill.gross, 8), DoubleToString(fill.commission, 8), DoubleToString(fill.swap_cost, 8),
             DoubleToString(fill.net, 8), ClockText(fill.signal_known_at), fill.reason);
}

bool Process(const ReplayBar &bar)
{
   Fill first, second;
   string rejected;
   if(bar.closed - bar.opened != PeriodSeconds(frame))
   {
      Fail("BAR_DURATION_MISMATCH");
      return false;
   }
   const string error = book.Step(bar, first, second, rejected);
   if(error != "")
   {
      Fail(error + " at " + ClockText(bar.opened));
      return false;
   }
   if(book.BarCount() == 1) first_open = bar.opened;
   WriteFill(first);
   WriteFill(second);
   if(rejected != "")
   {
      FileWrite(rejects_file, ClockText(bar.opened), rejected);
      rejected_count++;
   }
   FileWrite(equity_file, ClockText(bar.closed), DoubleToString(book.Balance(), 8), DoubleToString(book.Equity(), 8));
   return true;
}

bool DecimalCell(string cell, double &value)
{
   const int n = StringLen(cell);
   bool digit = false, point = false;
   for(int i = 0; i < n; i++)
   {
      const ushort c = StringGetCharacter(cell, i);
      if(c >= '0' && c <= '9') digit = true;
      else if(c == '.' && !point) point = true;
      else if(i != 0 || (c != '-' && c != '+')) return false;
   }
   if(!digit) return false;
   value = StringToDouble(cell);
   return MathIsValidNumber(value);
}

void RunCsv()
{
   // Read complete lines so a missing column cannot desynchronize records.
   const int input_file = FileOpen(InpCsv, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(input_file == INVALID_HANDLE)
   {
      Fail("CSV not found in Terminal/Common/Files: " + InpCsv);
      return;
   }
   const string header = "open_utc,close_utc,bid_open,bid_high,bid_low,bid_close,ask_open,ask_high,ask_low,ask_close,buy_swap,sell_swap";
   if(FileReadString(input_file) != header)
   {
      FileClose(input_file);
      Fail("Invalid CSV header");
      return;
   }

   int row = 1;
   while(!FileIsEnding(input_file) && !IsStopped())
   {
      const string line = FileReadString(input_file);
      row++;
      if(line == "" && FileIsEnding(input_file)) break;
      string cells[];
      double values[12];
      bool valid = StringSplit(line, ',', cells) == 12;
      for(int i = 0; valid && i < 12; i++) valid = DecimalCell(cells[i], values[i]);
      if(!valid || values[0] != MathFloor(values[0]) || values[1] != MathFloor(values[1]))
      {
         Fail("Invalid CSV row " + IntegerToString(row));
         break;
      }
      ReplayBar bar;
      bar.opened = (long)values[0];
      bar.closed = (long)values[1];
      bar.bid_open = values[2];
      bar.bid_high = values[3];
      bar.bid_low = values[4];
      bar.bid_close = values[5];
      bar.ask_open = values[6];
      bar.ask_high = values[7];
      bar.ask_low = values[8];
      bar.ask_close = values[9];
      bar.buy_swap = values[10];
      bar.sell_swap = values[11];
      if(!Process(bar)) break;
   }
   FileClose(input_file);
   if(!failed && book.BarCount() <= InpWarmupBars) Fail("No eligible replay bars");
   csv_done = !failed && !IsStopped();
   if(csv_done) TesterStop();
}

void OnTick()
{
   if(failed) return;
   if(InpSource == MT5_LONDON_TICKS)
   {
      const long utc_now = (long)TimeCurrent() - 60 * InpServerUtcOffsetMinutes;
      ProcessLondon(utc_now, InpServerUtcOffsetMinutes, InpLondonHoldoutFromUTC,
                    InpLondonAllInExtraPips, london_file, london_day, london_sessions,
                    london_pass, london_holdout, london_total);
      return;
   }
   if(InpSource == VELOX_OHLC_CSV)
   {
      if(!csv_done) RunCsv();
      return;
   }
   const datetime current = iTime(_Symbol, frame, 0);
   if(current <= 0 || current == last_seen) return;
   if(last_seen == 0)
   {
      last_seen = current;
      return; // Begin at the first change in a bar observed by the tester.
   }
   const datetime closed = iTime(_Symbol, frame, 1);
   if(closed < last_seen) return;
   MqlRates rates[];
   const int copied = CopyRates(_Symbol, frame, last_seen, closed, rates);
   if(copied <= 0 || rates[copied - 1].time != closed) return;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time <= last_processed) continue;
      ReplayBar bar;
      const double spread = rates[i].spread * _Point;
      bar.opened = (long)rates[i].time - 60 * InpServerUtcOffsetMinutes;
      bar.closed = bar.opened + PeriodSeconds(frame);
      bar.bid_open = rates[i].open;
      bar.bid_high = rates[i].high;
      bar.bid_low = rates[i].low;
      bar.bid_close = rates[i].close;
      bar.ask_open = bar.bid_open + spread;
      bar.ask_high = bar.bid_high + spread;
      bar.ask_low = bar.bid_low + spread;
      bar.ask_close = bar.bid_close + spread;
      bar.buy_swap = bar.sell_swap = 0;
      if(!Process(bar)) return;
      last_processed = rates[i].time;
   }
   last_seen = current;
}

double OnTester()
{
   if(failed) return -1.0e100;
   if(InpSource == MT5_LONDON_TICKS)
   {
      PrintFormat("London: %d weekday sessions, %d covered; net pips BUY %.6f SELL %.6f BOTH %.6f",
                  london_sessions, london_pass, london_total[0], london_total[1], london_total[2]);
      return london_holdout > 0 ? london_total[2] : -1.0e100;
   }
   if(book.BarCount() <= InpWarmupBars || (InpSource == VELOX_OHLC_CSV && !csv_done))
      return -1.0e100;
   return book.Equity() - InpInitialEquity;
}

void OnDeinit(const int reason)
{
   if(summary_file != INVALID_HANDLE)
   {
      const int trades = book.TradeCount();
      const double net = book.Balance() - InpInitialEquity;
      FileWrite(summary_file, "run_status", failed || book.BarCount() <= InpWarmupBars ? "FAILED" :
                (InpSource == VELOX_OHLC_CSV && !csv_done ? "INCOMPLETE" : "UNVALIDATED"));
      FileWrite(summary_file, "upstream", "v0.4.0.dev36");
      FileWrite(summary_file, "policy", PolicyId());
      FileWrite(summary_file, "source", EnumToString(InpSource));
      FileWrite(summary_file, "tester_symbol", _Symbol);
      FileWrite(summary_file, "symbol_scope", "XAUUSD");
      FileWrite(summary_file, "policy_period", EnumToString(frame));
      FileWrite(summary_file, "first_bar_open_utc", book.BarCount() > 0 ? ClockText(first_open) : "");
      FileWrite(summary_file, "last_bar_close_utc", book.BarCount() > 0 ? ClockText(book.LastClose()) : "");
      FileWrite(summary_file, "bars", book.BarCount());
      FileWrite(summary_file, "trades", trades);
      FileWrite(summary_file, "rejections", rejected_count);
      FileWrite(summary_file, "ambiguous_bars", book.AmbiguousBars());
      FileWrite(summary_file, "initial_balance", DoubleToString(InpInitialEquity, 8));
      FileWrite(summary_file, "balance", DoubleToString(book.Balance(), 8));
      FileWrite(summary_file, "equity", DoubleToString(book.Equity(), 8));
      FileWrite(summary_file, "net_profit", DoubleToString(net, 8));
      FileWrite(summary_file, "gross_profit", DoubleToString(book.GrossProfit(), 8));
      FileWrite(summary_file, "gross_loss", DoubleToString(book.GrossLoss(), 8));
      FileWrite(summary_file, "max_drawdown_fraction", DoubleToString(book.MaxDrawdown(), 10));
      FileWrite(summary_file, "win_rate", trades > 0 ? DoubleToString((double)book.Wins() / trades, 10) : "");
      FileWrite(summary_file, "expectancy_cash", trades > 0 ? DoubleToString(net / trades, 8) : "");
      FileWrite(summary_file, "profit_factor", book.GrossLoss() < 0 ?
                DoubleToString(book.GrossProfit() / -book.GrossLoss(), 10) : "");
      FileWrite(summary_file, "max_consecutive_losses", book.MaxConsecutiveLosses());
      if(book.HasPosition())
      {
         Position open;
         book.OpenPosition(open);
         FileWrite(summary_file, "open_side", open.signal.side > 0 ? "BUY" : "SELL");
         FileWrite(summary_file, "open_entry_utc", ClockText(open.opened));
         FileWrite(summary_file, "open_signal_utc", ClockText(open.signal.known_at));
         FileWrite(summary_file, "open_entry", DoubleToString(open.entry, 10));
         FileWrite(summary_file, "open_stop", DoubleToString(open.signal.stop, 10));
         FileWrite(summary_file, "open_target", DoubleToString(open.signal.target, 10));
         FileWrite(summary_file, "open_lots", DoubleToString(open.lots, 8));
         FileWrite(summary_file, "open_swap_cost", DoubleToString(open.swap_cost, 8));
         FileWrite(summary_file, "open_hold_bars", open.signal.hold_bars);
         FileWrite(summary_file, "open_age", open.age);
      }
      FileClose(summary_file);
   }
   if(fills_file != INVALID_HANDLE) FileClose(fills_file);
   if(rejects_file != INVALID_HANDLE) FileClose(rejects_file);
   if(equity_file != INVALID_HANDLE) FileClose(equity_file);
   if(london_file != INVALID_HANDLE) FileClose(london_file);
}
