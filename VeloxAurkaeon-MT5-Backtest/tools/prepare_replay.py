#!/usr/bin/env python3
"""Convert Velox OHLC CSV into the EA's UTC bid/ask and financing format."""
import argparse
import csv
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from pathlib import Path
from tempfile import NamedTemporaryFile


PRICES = ("open", "high", "low", "close")
HEADER = ("open_utc", "close_utc", *(f"bid_{k}" for k in PRICES),
          *(f"ask_{k}" for k in PRICES), "buy_swap", "sell_swap")


def number(value):
    result = Decimal(value)
    if not result.is_finite():
        raise ValueError("Non-finite price or cost")
    return result


def convert(source, destination, interval):
    if source.resolve() == destination.resolve():
        raise ValueError("Choose a separate output file")
    if interval not in (3600, 14400, 86400):
        raise ValueError("Supported intervals are H1, H4 and D1")
    temporary = None
    try:
        with source.open(newline="", encoding="utf-8-sig") as input_file, NamedTemporaryFile(
            mode="w", newline="", encoding="ascii", dir=destination.parent, delete=False
        ) as output:
            temporary = Path(output.name)
            reader = csv.DictReader(input_file)
            writer = csv.writer(output, lineterminator="\n")
            writer.writerow(HEADER)
            fields = set(reader.fieldnames or ())
            if not {"close_time", *PRICES, "spread", "swap_cash_per_lot"} <= fields:
                raise ValueError("Velox CSV requires close_time, OHLC, spread and swap_cash_per_lot")
            ask_keys = tuple(f"ask_{k}" for k in PRICES)
            ask_fields = fields.intersection(ask_keys)
            if ask_fields and not set(ask_keys) <= fields:
                raise ValueError("Supply all four ask OHLC fields together")
            count = 0
            previous_close = None
            epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
            for count, row in enumerate(reader, 1):
                closed = datetime.fromisoformat(row["close_time"].replace("Z", "+00:00"))
                if closed.utcoffset() is None or closed.microsecond:
                    raise ValueError(f"Row {count}: use a timezone-aware whole-second close_time")
                opened = closed - timedelta(seconds=interval)
                if opened < epoch or (previous_close is not None and opened < previous_close):
                    raise ValueError(f"Row {count}: bars overlap or precede 1970")
                bid = tuple(number(row[k]) for k in PRICES)
                spread = number(row["spread"])
                ask = tuple(number(row[k]) for k in ask_keys) if ask_fields else tuple(p + spread for p in bid)
                extra = spread - (ask[0] - bid[0])
                if spread < 0 or extra < 0 or any(a < b for a, b in zip(ask, bid)):
                    raise ValueError(f"Row {count}: invalid ask/spread")
                ask = tuple(price + extra for price in ask)
                buy = number(row["swap_cash_per_lot"])
                sell_text = row.get("sell_swap_cash_per_lot")
                sell = buy if sell_text in (None, "") else number(sell_text)
                writer.writerow((int(opened.timestamp()), int(closed.timestamp()),
                                 *(format(x, "f") for x in (*bid, *ask, buy, sell))))
                previous_close = closed
            if not count:
                raise ValueError("No bars in CSV")
        temporary.replace(destination)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--interval", type=int, required=True)
    args = parser.parse_args()
    print(f"{convert(args.input, args.output, args.interval)} bars written to {args.output}")


if __name__ == "__main__":
    main()
