#!/usr/bin/env python3
"""Convert Exness or dukascopy-node tick CSV into MT5 ticks and M1 bars."""

import argparse
from contextlib import contextmanager
import csv
from datetime import datetime, timezone
from decimal import Decimal
from io import TextIOWrapper
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile


@contextmanager
def open_csv(source):
    if source.suffix.lower() == ".zip":
        with ZipFile(source) as archive:
            entries = [item for item in archive.namelist() if item.lower().endswith(".csv")]
            if len(entries) != 1:
                raise ValueError("The ZIP must contain exactly one CSV.")
            with archive.open(entries[0]) as binary:
                with TextIOWrapper(binary, encoding="utf-8-sig", newline="") as rows:
                    yield rows
    else:
        with source.open(encoding="utf-8-sig", newline="") as rows:
            yield rows


def to_points(price, digits):
    whole, _, fraction = price.partition(".")
    if not whole.isdecimal() or (fraction and not fraction.isdecimal()):
        raise ValueError("A price must contain decimal digits.")
    if fraction[digits:].strip("0"):
        scaled = Decimal(price).scaleb(digits)
        nearest = scaled.to_integral_value()
        if abs(scaled - nearest) > Decimal("0.00000001"):
            raise ValueError("The selected number of digits would alter a quote.")
        return int(nearest)
    return int(whole + fraction[:digits].ljust(digits, "0"))


def from_points(points, digits):
    price = str(points).zfill(digits + 1)
    return price[:-digits] + "." + price[-digits:] if digits else price


def write_bar(out, minute, opening, high, low, close, count, spread, digits):
    date, time = minute.split()
    prices = (from_points(price, digits) for price in (opening, high, low, close))
    out.writerow((date, time + ":00", *prices, count, 0, spread))


def utc_stamp(timestamp):
    if not timestamp:
        raise ValueError("Missing tick timestamp.")
    if timestamp.isdecimal():
        seconds, millis = divmod(int(timestamp), 1000)
        date = datetime.fromtimestamp(seconds, timezone.utc)
        return date.strftime("%Y-%m-%d %H:%M:%S") + f".{millis:03d}"
    if timestamp.endswith("+00:00"):
        timestamp = timestamp[:-6] + "Z"
    if not timestamp.endswith("Z") or len(timestamp) not in (20, 24):
        raise ValueError("Expected a UTC timestamp with optional milliseconds or Unix milliseconds.")
    stamp = timestamp[:-1].replace("T", " ")
    return stamp if len(stamp) == 23 else stamp + ".000"


def convert(source, ticks_path, bars_path, digits, external_symbol):
    with open_csv(source) as source_file, ticks_path.open("w", newline="") as tick_file, bars_path.open("w", newline="") as bar_file:
        rows = csv.DictReader(source_file)
        columns = set(rows.fieldnames or ())
        if {"Symbol", "Timestamp", "Bid", "Ask"}.issubset(columns):
            time_column, bid_column, ask_column = "Timestamp", "Bid", "Ask"
            has_symbol = True
        elif {"timestamp", "bidPrice", "askPrice"}.issubset(columns) and external_symbol:
            time_column, bid_column, ask_column = "timestamp", "bidPrice", "askPrice"
            has_symbol = False
        else:
            raise ValueError("Expected an Exness tick archive or a dukascopy-node tick CSV with --symbol.")
        ticks = csv.writer(tick_file, delimiter="\t")
        bars = csv.writer(bar_file, delimiter="\t")
        ticks.writerow(("<DATE>", "<TIME>", "<BID>", "<ASK>", "<LAST>", "<VOLUME>"))
        bars.writerow(("<DATE>", "<TIME>", "<OPEN>", "<HIGH>", "<LOW>", "<CLOSE>", "<TICKVOL>", "<VOL>", "<SPREAD>"))
        symbol = first = last = active = ""
        tick_count = bar_count = minute_ticks = 0

        for row in rows:
            stamp = utc_stamp(row[time_column])
            row_symbol = row["Symbol"] if has_symbol else external_symbol
            if last and stamp < last:
                raise ValueError(f"Time moved backward on row {rows.line_num}.")
            if not symbol:
                symbol, first = row_symbol, stamp
            if not symbol or row_symbol != symbol:
                raise ValueError(f"Each file must contain a single symbol. Check row {rows.line_num}.")
            last = stamp
            bid = to_points(row[bid_column], digits)
            ask = to_points(row[ask_column], digits)
            if bid <= 0 or ask < bid:
                raise ValueError(f"Invalid bid or ask on row {rows.line_num}.")

            date = stamp[:10].replace("-", ".")
            ticks.writerow((date, stamp[11:], from_points(bid, digits), from_points(ask, digits), 0, 0))
            tick_count += 1
            minute = date + " " + stamp[11:16]
            spread = ask - bid
            if minute != active:
                if active:
                    write_bar(bars, active, opening, high, low, close, minute_ticks, min_spread, digits)
                    bar_count += 1
                active = minute
                opening = high = low = bid
                min_spread = spread
                minute_ticks = 0
            high = max(high, bid)
            low = min(low, bid)
            close = bid
            min_spread = min(spread, min_spread)
            minute_ticks += 1

        if not active:
            raise ValueError("The archive contained no ticks.")
        datetime.fromisoformat(first)
        datetime.fromisoformat(last)
        write_bar(bars, active, opening, high, low, close, minute_ticks, min_spread, digits)
        return symbol, tick_count, bar_count + 1, first, last


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Tick CSV or ZIP containing one tick CSV")
    parser.add_argument("--symbol", help="Symbol name for a CSV without a Symbol column")
    parser.add_argument("--digits", type=int, required=True, choices=range(9),
                        help="Digits from MT5 Specification for the custom symbol")
    parser.add_argument("--output", type=Path, default=Path("mt5_import"))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    names = [args.archive.stem + suffix for suffix in ("_ticks.csv", "_m1.csv")]
    destinations = [args.output / name for name in names]
    if any(path.exists() for path in destinations):
        parser.error("Output already exists. Choose another output directory.")
    try:
        with TemporaryDirectory(dir=args.output) as staging:
            tmp = [Path(staging) / name for name in names]
            symbol, ticks, bars, first, last = convert(args.archive, *tmp, args.digits, args.symbol)
            for original, target in zip(tmp, destinations):
                original.rename(target)
    except (OSError, ValueError, TypeError, OverflowError) as error:
        parser.exit(1, f"Conversion failed: {error}\n")
    print(f"{symbol}: {ticks:,} ticks, {bars:,} M1 bars, {first} to {last} UTC.")
    for path in destinations:
        print(path)


if __name__ == "__main__":
    main()
