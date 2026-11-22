#ifndef VELOX_CORE_MQH
#define VELOX_CORE_MQH

enum VeloxPolicy
{
   ExampleEMA, ExperimentDonchian, LabRSI21, LabADX18Burst, LabSupertrend15_3,
   QuantTSMomentum, QuantZReversion, QuantMultiHorizon, QuantATRBreakout, QuantVolatilityMomentum
};

struct ReplayBar
{
   long opened;
   long closed;
   double bid_open, bid_high, bid_low, bid_close;
   double ask_open, ask_high, ask_low, ask_close;
   double buy_swap, sell_swap;
};

struct Intent
{
   int side;
   double stop, target;
   int hold_bars;
   long known_at;
};

struct Contract
{
   double tick_size, tick_value, pip_size;
   double lot_min, lot_max, lot_step, margin, commission, minimum_stop, maximum_spread;
};

struct RiskLimits
{
   double starting_equity, risk_per_trade, max_daily, max_weekly, max_drawdown;
   double max_open_risk, margin_reserve, entry_lot_cap;
   int slippage_ticks, delay_bars, max_signal_age, first_trade_bar;
};

struct Position
{
   Intent signal;
   long opened;
   double entry, lots, swap_cost;
   int age;
};

struct Fill
{
   long entered, exited;
   int side;
   double lots, entry, exit_price, gross, commission, swap_cost, net;
   long signal_known_at;
   string reason;
};

double Absolute(const double x) { return MathAbs(x); }

double TrueRange(const ReplayBar &bar, const double previous_close)
{
   return MathMax(bar.bid_high - bar.bid_low,
                  MathMax(Absolute(bar.bid_high - previous_close), Absolute(bar.bid_low - previous_close)));
}

double Rma(const double current, const double value, const int period)
{
   return (current * (period - 1) + value) / period;
}

int Direction(const double x, const double threshold)
{
   if(x > threshold) return 1;
   if(x < -threshold) return -1;
   return 0;
}

class VeloxSignals
{
private:
   ReplayBar bars[2000];
   int count, contiguous;
   double rsi_gain, rsi_loss, rsi_value;
   double atr15, upper, lower;
   int trend;
   double tr18, plus18, minus18, adx_value;
   VeloxPolicy policy;
   int window, paper_history, seconds;

   int Index(const int i) const { return (i + 2000) % 2000; }

   double Sma(const int i, const int n) const
   {
      double sum = 0;
      for(int j = i - n + 1; j <= i; j++) sum += bars[Index(j)].bid_close;
      return sum / n;
   }

   double Extreme(const int i, const int n, const int side) const
   {
      double value = side > 0 ? bars[Index(i)].bid_low : bars[Index(i)].bid_high;
      for(int j = i - n + 1; j < i; j++)
      {
         if(side > 0) value = MathMin(value, bars[Index(j)].bid_low);
         else value = MathMax(value, bars[Index(j)].bid_high);
      }
      return value;
   }

   double Ema(const int first, const int last, const int n) const
   {
      double value = Sma(first + n - 1, n);
      const double alpha = 2.0 / (n + 1);
      for(int j = first + n; j <= last; j++)
         value += alpha * (bars[Index(j)].bid_close - value);
      return value;
   }

   void PaperSignal(const int i, Intent &signal) const
   {
      const int length = (int)MathMin(contiguous, paper_history);
      if(length < 31) return;
      const int first = i - length + 1;
      double atr14 = 0;
      for(int j = first + 1; j <= first + 14; j++)
         atr14 += TrueRange(bars[Index(j)], bars[Index(j - 1)].bid_close);
      atr14 /= 14;
      for(int j = first + 15; j <= i; j++)
         atr14 = Rma(atr14, TrueRange(bars[Index(j)], bars[Index(j - 1)].bid_close), 14);

      const double current = Ema(first, i, 10) - Ema(first, i, 30);
      const double strength = atr14 == 0 ? 0 : Absolute(current) / atr14;
      const double price = bars[Index(i)].bid_close;
      if(policy == ExampleEMA)
      {
         const double previous = Ema(first, i - 1, 10) - Ema(first, i - 1, 30);
         if(previous > 0 || current <= 0 || atr14 <= 0) return;
         signal.stop = price - 2 * atr14;
      }
      else
      {
         const double previous_high = Extreme(i - 1, 25, -1);
         if(strength < 0.3 || price <= previous_high) return;
         signal.stop = Extreme(i - 1, 3, 1);
      }
      signal.target = price + 2 * (price - signal.stop);
      signal.side = 1;
   }

   void RsiSignal(const int i, const double change, Intent &signal)
   {
      const double gain = MathMax(0.0, change);
      const double loss = MathMax(0.0, -change);
      if(i <= 21)
      {
         rsi_gain += gain / 21;
         rsi_loss += loss / 21;
      }
      else
      {
         rsi_gain = Rma(rsi_gain, gain, 21);
         rsi_loss = Rma(rsi_loss, loss, 21);
      }
      const double previous = rsi_value;
      rsi_value = rsi_loss == 0 ? (rsi_gain == 0 ? 50 : 100) : 100 - 100 / (1 + rsi_gain / rsi_loss);
      if(i < 22) return;
      if(previous <= 50 && rsi_value > 50) signal.side = 1;
      if(previous >= 50 && rsi_value < 50) signal.side = -1;
      if(signal.side != 0) signal.stop = Extreme(i, 20, signal.side);
   }

   void AdxSignal(const int i, const ReplayBar &bar, const ReplayBar &prev, const double tr, Intent &signal)
   {
      const double up = bar.bid_high - prev.bid_high;
      const double down = prev.bid_low - bar.bid_low;
      const double plus = up > down && up > 0 ? up : 0;
      const double minus = down > up && down > 0 ? down : 0;
      if(i <= 18)
      {
         tr18 += tr / 18;
         plus18 += plus / 18;
         minus18 += minus / 18;
      }
      else
      {
         tr18 = Rma(tr18, tr, 18);
         plus18 = Rma(plus18, plus, 18);
         minus18 = Rma(minus18, minus, 18);
      }
      if(i < 18) return;
      const double p = tr18 == 0 ? 0 : 100 * plus18 / tr18;
      const double m = tr18 == 0 ? 0 : 100 * minus18 / tr18;
      const double dx = p + m == 0 ? 0 : 100 * Absolute(p - m) / (p + m);
      const double previous = adx_value;
      if(i <= 35) adx_value += dx / 18;
      else adx_value = Rma(adx_value, dx, 18);
      if(i < 36 || adx_value - previous <= 1) return;
      signal.side = Direction(Sma(i, 3) - Sma(i, 12), 0);
      if(signal.side == 0) return;
      signal.stop = Extreme(i, 10, signal.side);
      signal.hold_bars = 20;
   }

   void SupertrendSignal(const int i, const ReplayBar &bar, const double previous_close,
                         const double tr, Intent &signal)
   {
      if(i <= 14) atr15 += tr / 15;
      else atr15 = Rma(atr15, tr, 15);
      if(i < 14) return;
      const double midpoint = (bar.bid_high + bar.bid_low) / 2;
      const double next_upper = midpoint + 3 * atr15;
      const double next_lower = midpoint - 3 * atr15;
      if(i == 14)
      {
         upper = next_upper;
         lower = next_lower;
         return;
      }
      if(next_upper < upper || previous_close > upper) upper = next_upper;
      if(next_lower > lower || previous_close < lower) lower = next_lower;
      const int before = trend;
      if(trend == -1 && bar.bid_close > upper) trend = 1;
      else if(trend == 1 && bar.bid_close < lower) trend = -1;
      if(trend == before) return;
      signal.side = trend;
      signal.stop = trend > 0 ? lower : upper;
   }

   void QuantSignal(const int i, const double price, Intent &signal) const
   {
      const int horizon = policy == QuantMultiHorizon ? window * 2 : window;
      if(i < horizon || i < 14) return;
      double tr = 0;
      for(int j = i - 13; j <= i; j++)
         tr += TrueRange(bars[Index(j)], bars[Index(j - 1)].bid_close);
      const double atr14 = tr / 14;
      if(atr14 <= 0) return;
      const int first = i - window;
      if(policy == QuantTSMomentum)
         signal.side = Direction(price - bars[Index(first)].bid_close, atr14 / 2);
      else if(policy == QuantMultiHorizon)
      {
         const int fast = Direction(price - bars[Index(first)].bid_close, atr14 / 2);
         const int slow = Direction(price - bars[Index(i - 2 * window)].bid_close, atr14 / 2);
         if(fast == slow) signal.side = fast;
      }
      else if(policy == QuantZReversion)
      {
         const double mean = Sma(i - 1, window);
         double squares = 0;
         for(int j = first; j < i; j++)
         {
            const double delta = bars[Index(j)].bid_close - mean;
            squares += delta * delta;
         }
         if(squares > 0) signal.side = -Direction(price - mean, 1.5 * MathSqrt(squares / window));
      }
      else if(policy == QuantVolatilityMomentum)
      {
         double sum = 0, squares = 0;
         for(int j = first + 1; j <= i; j++)
         {
            const double value = bars[Index(j)].bid_close / bars[Index(j - 1)].bid_close - 1;
            sum += value;
            squares += value * value;
         }
         if(squares > 0) signal.side = Direction(sum, MathSqrt(squares));
      }
      else
      {
         if(price > Extreme(i - 1, window, -1) + atr14 / 10) signal.side = 1;
         if(price < Extreme(i - 1, window, 1) - atr14 / 10) signal.side = -1;
      }
      signal.stop = price - signal.side * 2 * atr14;
      signal.hold_bars = 6;
   }

public:
   void Configure(const VeloxPolicy selected, const int n, const int history, const int interval)
   {
      policy = selected;
      window = n;
      paper_history = history;
      seconds = interval;
      count = 0;
      contiguous = 0;
      trend = -1;
      rsi_gain = rsi_loss = rsi_value = atr15 = upper = lower = 0;
      tr18 = plus18 = minus18 = adx_value = 0;
   }

   void Push(const ReplayBar &bar, Intent &signal)
   {
      const int i = count++;
      bars[Index(i)] = bar;
      signal.side = 0;
      signal.stop = signal.target = 0;
      signal.hold_bars = 0;
      signal.known_at = bar.closed;
      contiguous++;
      if(i > 0 && bars[Index(i - 1)].closed + seconds != bar.closed) contiguous = 1;

      if(policy == ExampleEMA || policy == ExperimentDonchian)
         PaperSignal(i, signal);
      else if(policy == LabSupertrend15_3)
      {
         const double previous = i == 0 ? bar.bid_close : bars[Index(i - 1)].bid_close;
         SupertrendSignal(i, bar, previous, TrueRange(bar, previous), signal);
      }
      else if(i > 0)
      {
         const ReplayBar previous = bars[Index(i - 1)];
         if(policy == LabRSI21) RsiSignal(i, bar.bid_close - previous.bid_close, signal);
         else if(policy == LabADX18Burst) AdxSignal(i, bar, previous, TrueRange(bar, previous.bid_close), signal);
         else QuantSignal(i, bar.bid_close, signal);
      }
      if(signal.stop <= 0 || signal.target < 0) signal.side = 0;
   }
};

class VeloxReplay
{
private:
   VeloxSignals signals;
   Contract spec;
   RiskLimits limits;
   VeloxPolicy policy;
   Intent queue[4];
   Position position;
   bool active, daily_latch, weekly_latch, drawdown_latch;
   double balance, equity, peak, day_start, week_start, max_dd;
   long day, week, last_close;
   int count, trades, wins, loss_streak, max_loss_streak, ambiguous;
   double gross_profit, gross_loss;

   double Pnl(const double exit_price) const
   {
      return position.signal.side * (exit_price - position.entry) / spec.tick_size
             * spec.tick_value * position.lots;
   }

   double Mark(const ReplayBar &bar, const bool at_open) const
   {
      if(!active) return balance;
      const double price = position.signal.side > 0 ? (at_open ? bar.bid_open : bar.bid_close)
                                                    : (at_open ? bar.ask_open : bar.ask_close);
      return balance + Pnl(price) - position.swap_cost - spec.commission * position.lots;
   }

   void Observe(const double value)
   {
      peak = MathMax(peak, value);
      const double dd = (peak - value) / peak;
      max_dd = MathMax(max_dd, dd);
      daily_latch = daily_latch || day_start <= 0 || (day_start - value) / day_start >= limits.max_daily;
      weekly_latch = weekly_latch || week_start <= 0 || (week_start - value) / week_start >= limits.max_weekly;
      drawdown_latch = drawdown_latch || dd >= limits.max_drawdown;
   }

   void Close(const ReplayBar &bar, const double price, const string reason, const bool slip,
              Fill &fill)
   {
      fill.entered = position.opened;
      fill.exited = bar.closed;
      fill.side = position.signal.side;
      fill.lots = position.lots;
      fill.entry = position.entry;
      fill.exit_price = slip ? MathMax(spec.tick_size, price - fill.side * limits.slippage_ticks * spec.tick_size) : price;
      fill.gross = Pnl(fill.exit_price);
      fill.commission = spec.commission * fill.lots;
      fill.swap_cost = position.swap_cost;
      fill.net = fill.gross - fill.commission - fill.swap_cost;
      fill.signal_known_at = position.signal.known_at;
      fill.reason = reason;
      balance += fill.net;
      active = false;
      trades++;
      if(fill.net > 0)
      {
         wins++;
         gross_profit += fill.net;
      }
      if(fill.net < 0) gross_loss += fill.net;
      loss_streak = fill.net < 0 ? loss_streak + 1 : 0;
      max_loss_streak = (int)MathMax(max_loss_streak, loss_streak);
   }

   string Enter(const ReplayBar &bar, const Intent &signal)
   {
      if(balance <= 0) return "EMERGENCY_STOP";
      if(daily_latch || weekly_latch || drawdown_latch)
      {
         string codes = "";
         if(daily_latch) codes += "DAILY_LOSS";
         if(drawdown_latch) codes += (codes == "" ? "" : ",") + string("DRAWDOWN");
         if(weekly_latch) codes += (codes == "" ? "" : ",") + string("WEEKLY_LOSS");
         return "LATCHED_" + codes;
      }
      if((bar.ask_open - bar.bid_open) / spec.pip_size > spec.maximum_spread + 1e-9)
         return "SPREAD";
      const int side = signal.side;
      const double quoted = side > 0 ? bar.ask_open : bar.bid_open;
      const double executable = side > 0 ? bar.bid_open : bar.ask_open;
      const double stop_units = signal.stop / spec.tick_size;
      const double target_units = signal.target / spec.tick_size;
      const double stop = (side > 0 ? MathFloor(stop_units + 1e-9) : MathCeil(stop_units - 1e-9)) * spec.tick_size;
      const double target = (side > 0 ? MathCeil(target_units - 1e-9) : MathFloor(target_units + 1e-9)) * spec.tick_size;
      if(side * (quoted - stop) <= 1e-9 ||
         (target > 0 && side * (target - quoted) <= 1e-9)) return "INVALID_SL_TP";
      if(side * (executable - stop) < spec.minimum_stop - 1e-9 ||
         (target > 0 && side * (target - executable) < spec.minimum_stop - 1e-9)) return "STOP_DISTANCE";
      const double entry = quoted + side * limits.slippage_ticks * spec.tick_size;
      if(entry <= 0 || side * (entry - stop) <= 1e-9 ||
         (target > 0 && side * (target - entry) <= 1e-9)) return "SLIPPAGE_INVALIDATES_ORDER";
      const double loss = (Absolute(quoted - stop) / spec.tick_size + 2 * limits.slippage_ticks)
                          * spec.tick_value + spec.commission;
      double lots = MathFloor(balance * limits.risk_per_trade / loss / spec.lot_step + 1e-9) * spec.lot_step;
      lots = MathMin(lots, spec.lot_max);
      if(lots < spec.lot_min - 1e-9) return "LOT_BELOW_MINIMUM";
      if(lots * loss > balance * limits.max_open_risk + 1e-8) return "PORTFOLIO_RISK";
      if(lots * spec.margin > balance * (1 - limits.margin_reserve) + 1e-8) return "MARGIN_RESERVE";
      if(limits.entry_lot_cap > 0 && lots > limits.entry_lot_cap + 1e-9) return "ENTRY_LIQUIDITY_CAP";
      position.signal = signal;
      position.signal.stop = stop;
      position.signal.target = target;
      position.entry = entry;
      position.lots = lots;
      position.opened = bar.opened;
      position.age = 0;
      position.swap_cost = 0;
      active = true;
      return "";
   }

   bool OnGrid(const double price) const
   {
      const double units = price / spec.tick_size;
      return MathIsValidNumber(price) && price > 0 && Absolute(units - MathRound(units)) < 1e-6;
   }

public:
   void Configure(const VeloxPolicy selected, const Contract &contract, const RiskLimits &risk,
                  const int n, const int history, const int interval)
   {
      policy = selected;
      spec = contract;
      limits = risk;
      signals.Configure(selected, n, history, interval);
      for(int i = 0; i < 4; i++) queue[i].side = 0;
      active = daily_latch = weekly_latch = drawdown_latch = false;
      balance = equity = peak = day_start = week_start = risk.starting_equity;
      day = week = -1;
      count = trades = wins = loss_streak = max_loss_streak = ambiguous = 0;
      last_close = 0;
      max_dd = gross_profit = gross_loss = 0;
   }

   string Step(const ReplayBar &bar, Fill &first, Fill &second, string &rejected)
   {
      first.side = second.side = 0;
      rejected = "";
      if(bar.opened < 0 || bar.closed <= bar.opened || (count > 0 && bar.opened < last_close))
         return "DUPLICATE_OR_OVERLAPPING_BARS";
      if(!OnGrid(bar.bid_open) || !OnGrid(bar.bid_high) || !OnGrid(bar.bid_low) || !OnGrid(bar.bid_close) ||
         !OnGrid(bar.ask_open) || !OnGrid(bar.ask_high) || !OnGrid(bar.ask_low) || !OnGrid(bar.ask_close))
         return "OHLC_OFF_TICK_GRID";
      if(bar.bid_low > MathMin(bar.bid_open, bar.bid_close) || MathMax(bar.bid_open, bar.bid_close) > bar.bid_high ||
         bar.ask_low > MathMin(bar.ask_open, bar.ask_close) || MathMax(bar.ask_open, bar.ask_close) > bar.ask_high ||
         bar.ask_open < bar.bid_open || bar.ask_high < bar.bid_high || bar.ask_low < bar.bid_low || bar.ask_close < bar.bid_close ||
         !MathIsValidNumber(bar.buy_swap) || !MathIsValidNumber(bar.sell_swap))
         return "INVALID_OHLC_OR_FINANCING";

      const long new_day = bar.opened / 86400;
      const long new_week = (new_day + 3) / 7; // Unix epoch was Thursday.
      if(new_day != day)
      {
         day = new_day;
         day_start = equity;
         daily_latch = false;
      }
      if(new_week != week)
      {
         week = new_week;
         week_start = equity;
         weekly_latch = false;
      }

      Intent pending = queue[count % 4];
      queue[count % 4].side = 0;
      if(count < limits.first_trade_bar) pending.side = 0;
      int expiry = limits.max_signal_age;
      if(policy == ExampleEMA || policy == ExperimentDonchian)
      {
         if(expiry < 0 || expiry > 30) expiry = 30;
         const int weekday = (int)((new_day + 3) % 7);
         if(weekday > 4) pending.side = 0;
      }
      if(pending.side != 0 && expiry >= 0 && bar.opened - pending.known_at > expiry)
      {
         rejected = "SIGNAL_EXPIRED_ACROSS_GAP";
         pending.side = 0;
      }

      if(active) position.swap_cost += (position.signal.side > 0 ? bar.buy_swap : bar.sell_swap) * position.lots;
      Observe(Mark(bar, true));
      if(active)
      {
         const int side = position.signal.side;
         const double open = side > 0 ? bar.bid_open : bar.ask_open;
         if(side * (open - position.signal.stop) <= 1e-9) Close(bar, open, "STOP_GAP", true, first);
      }
      if(pending.side != 0)
      {
         if(active && policy != LabADX18Burst && pending.side != position.signal.side)
         {
            const double open = position.signal.side > 0 ? bar.bid_open : bar.ask_open;
            Close(bar, open, "REVERSE_NEXT_OPEN", true, first);
         }
         if(!active)
         {
            Observe(balance);
            rejected = Enter(bar, pending);
         }
      }
      if(active)
      {
         position.age++;
         const int side = position.signal.side;
         const double adverse = side > 0 ? bar.bid_low : bar.ask_high;
         const double favorable = side > 0 ? bar.bid_high : bar.ask_low;
         const bool stop = side * (adverse - position.signal.stop) <= 1e-9;
         const bool target = position.signal.target > 0 && side * (favorable - position.signal.target) >= -1e-9;
         if(stop && target) ambiguous++;
         if(stop || target || (position.signal.hold_bars > 0 && position.age >= position.signal.hold_bars))
         {
            const double price = stop ? position.signal.stop :
                                 (target ? position.signal.target : (side > 0 ? bar.bid_close : bar.ask_close));
            const string reason = stop ? "STOP_ADVERSE_FIRST" : (target ? "TARGET" : "MAX_HOLD_BARS");
            if(first.side == 0) Close(bar, price, reason, !target || stop, first);
            else Close(bar, price, reason, !target || stop, second);
         }
      }

      equity = Mark(bar, false);
      Observe(equity);
      Intent signal;
      signals.Push(bar, signal);
      if(count >= limits.first_trade_bar - 1 && !(active && policy == LabADX18Burst))
         queue[(count + 1 + limits.delay_bars) % 4] = signal;
      count++;
      last_close = bar.closed;
      return "";
   }

   int BarCount() const { return count; }
   long LastClose() const { return last_close; }
   bool HasPosition() const { return active; }
   void OpenPosition(Position &value) const { value = position; }
   int TradeCount() const { return trades; }
   int AmbiguousBars() const { return ambiguous; }
   int Wins() const { return wins; }
   int MaxConsecutiveLosses() const { return max_loss_streak; }
   double Balance() const { return balance; }
   double Equity() const { return equity; }
   double MaxDrawdown() const { return max_dd; }
   double GrossProfit() const { return gross_profit; }
   double GrossLoss() const { return gross_loss; }
};
#endif
