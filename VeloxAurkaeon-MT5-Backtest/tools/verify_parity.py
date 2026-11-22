#!/usr/bin/env python3
"""Compare the compiled C++ subset of the MQL rules with the pinned Python rules."""
import argparse
import math
import random
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
from decimal import Decimal as D
from pathlib import Path


def close(actual, expected):
    if not math.isclose(float(actual), float(expected), rel_tol=1e-10, abs_tol=1e-8):
        raise AssertionError((actual, expected))


def seconds(value):
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path, help="Extracted upstream veloxaurkaeon checkout")
    args = parser.parse_args()
    sys.path.insert(0, str(args.reference / "backend"))

    from velox.api import paper_spec
    from velox.domain import Candle
    from velox.intelligence import generate, regime
    from velox.quantitative import AlphaPolicy, FAMILIES
    from velox.registry import initial_strategies
    from velox.research_lab import LabBar, ReferencePolicy, backtest, read_csv

    path = Path(__file__).resolve().parent
    with tempfile.TemporaryDirectory() as scratch:
        binary = Path(scratch) / "verify_core"
        subprocess.run(["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror", "-O2",
                        str(path / "verify_core.cpp"), "-o", str(binary)], check=True)

        def run(mode, policy, window, interval, bars, warmup=0, delay=0, expiry=-1, cap=0):
            payload = [f"{mode} {policy} {window} {interval} {warmup} {delay} {expiry} {cap}"]
            for bar in bars:
                candle = bar.candle
                closed = int(candle.close_time.timestamp())
                fields = ("open", "high", "low", "close")
                payload.append(" ".join(map(str, (closed - interval, closed,
                    *(getattr(candle, field) for field in fields), *(bar.ask_price(field) for field in fields),
                    bar.financing("BUY"), bar.financing("SELL")))))
            result = subprocess.run([str(binary)], input="\n".join(payload) + "\n", text=True,
                                    capture_output=True, check=True)
            return [line.split() for line in result.stdout.splitlines()]

        def synthetic(interval, count=220, gaps=True):
            rng = random.Random(872)
            stamp = datetime(2020, 1, 6, tzinfo=timezone.utc)
            price = 200_000
            result = []
            for i in range(count):
                opened = price + rng.randint(-12, 12)
                trend = 26 if i < 40 or i % 120 >= 80 else -23
                price = opened + rng.randint(-90, 90) + trend
                bid_low = min(opened, price) - rng.randint(20, 90)
                bid_high = max(opened, price) + rng.randint(20, 90)
                if gaps and i == 95:
                    stamp += timedelta(seconds=3 * interval)
                stamp += timedelta(seconds=interval)
                bid = Candle(close_time=stamp, open=D(opened)/100, high=D(bid_high)/100,
                             low=D(bid_low)/100, close=D(price)/100)
                ask = Candle(close_time=stamp, open=bid.open+D(".2"), high=bid.high+D(".14"),
                             low=bid.low+D(".27"), close=bid.close+D(".25"))
                result.append(LabBar(bid, ".22", ".35" if i % 6 == 0 else "0",
                                     ask, "-.25" if i % 7 == 0 else "0"))
            return result

        total_trades = total_signals = 0
        for i, strategy in enumerate(initial_strategies()[:2]):
            bars = synthetic(strategy.timeframe_seconds, count=2110)
            history = []
            expected = []
            for row in bars:
                if history and row.candle.close_time - history[-1].close_time != timedelta(seconds=strategy.timeframe_seconds):
                    history.clear()
                history.append(row.candle)
                current = tuple(history[-2000:])
                if regime(current)["label"] not in strategy.activation.regimes:
                    continue
                signal = generate(strategy, current, "XAUUSD")
                if signal:
                    expected.append((int(signal.bar_close.timestamp()), 1, signal.stop_loss, signal.take_profit, 0))
            actual = run(0, i, 24, strategy.timeframe_seconds, bars)
            assert expected and len(actual) == len(expected), (strategy.id, len(actual), len(expected))
            for row, target in zip(actual, expected):
                for result, value in zip(row[1:], target, strict=True):
                    close(result, value)
            total_signals += len(actual)
            print(f"{strategy.id}: {len(actual)} signal events matched with rollover of the 2000-bar history")

        reference = [ReferencePolicy(n) for n in ("rsi21", "adx18_burst", "supertrend15_3")]
        families = ("ts_momentum", "z_reversion", "multi_horizon_momentum", "atr_breakout", "volatility_adjusted_momentum")
        cases = [(i+2, 24, p) for i, p in enumerate(reference)]
        cases.extend((i+5, n, AlphaPolicy(name, n)) for i, name in enumerate(families)
                     for n in FAMILIES[name]["windows"])
        for i, window, policy in cases:
            interval = policy.required_interval_seconds
            fixture = args.reference / "examples" / f"{policy.name}_SYNTHETIC.csv"
            inputs = [synthetic(interval)]
            if fixture.exists():
                inputs.append(read_csv(fixture))
            for bars in inputs:
                actual_signals = run(0, i, window, interval, bars)
                expected_signals = []
                history = []
                for bar in bars:
                    history.append(bar.candle)
                    signal = policy.event(history)
                    if signal:
                        expected_signals.append((int(bar.candle.close_time.timestamp()),
                            1 if signal.side == "BUY" else -1, signal.stop_loss,
                            signal.take_profit or 0, signal.hold_bars or 0))
                assert len(actual_signals) == len(expected_signals), (policy.name, window, len(actual_signals), len(expected_signals))
                for row, target in zip(actual_signals, expected_signals):
                    for result, value in zip(row[1:], target, strict=True):
                        close(result, value)
                total_signals += len(actual_signals)
                for warmup, delay, expiry, cap in ((0, 0, -1, 0), (38, 1, interval, 0), (5, 0, 0, 0.08)):
                    expected = backtest(bars, policy, paper_spec(), interval, label="SYNTHETIC",
                        trade_start_index=warmup, execution_delay_bars=delay,
                        max_signal_age_seconds=None if expiry == -1 else expiry,
                        entry_lot_cap=D(str(cap)) if cap else None)
                    rows = run(1, i, window, interval, bars, warmup, delay, expiry, cap)
                    fills = [row[1:] for row in rows if row[0] == "F"]
                    rejects = [(int(row[1]), row[2]) for row in rows if row[0] == "R"]
                    assert len(fills) == len(expected["trades"]), (policy.name, window, warmup, len(fills), len(expected["trades"]))
                    assert rejects == [(seconds(r["at"]), r["reason"]) for r in expected["rejected_orders"]], (policy.name, window, warmup)
                    for result, trade in zip(fills, expected["trades"], strict=True):
                        assert result[11] == trade["reason"], (result, trade)
                        target = [seconds(trade["entry_at"]), seconds(trade["exit_bar_close"]),
                                  1 if trade["side"] == "BUY" else -1]
                        target.extend(trade[k] for k in ("lots", "entry", "exit", "gross_pnl",
                                                         "commission", "swap_cost", "net_pnl"))
                        target.append(seconds(trade["signal_known_at"]))
                        for value, reference_value in zip(result[:11], target, strict=True):
                            close(value, reference_value)
                    metrics = expected["metrics"]
                    for value, target in zip(rows[-1][1:], (metrics["trade_count"], expected["ambiguous_stop_target_bars"],
                        expected["realized_balance"], expected["final_equity"], metrics["max_drawdown_fraction"],
                        metrics["max_consecutive_losses"], int(expected["open_position"] is not None)), strict=True):
                        close(value, target)
                    total_trades += len(fills)
            print(f"{policy.name}({window}): signals, fills, costs, rejections and equity matched")
        print(f"{total_signals} signals and {total_trades} closed trades matched across all fixtures")


if __name__ == "__main__":
    main()
