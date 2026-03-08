#!/usr/bin/env python3
"""
Sand Portfolio — Market Data Pipeline
======================================
Pulls OHLCV data for all tracked tickers via yfinance and writes
a bundled SQLite database (market_data.db) ready to drop into
the SandPortfolio.swiftpm Xcode project.

Usage:
    pip install yfinance
    python generate_market_data.py              # 2000-present, all tickers
    python generate_market_data.py --start 2010 # from 2010 onward
    python generate_market_data.py --tickers XLK XLV  # subset only

Output:
    market_data.db  (in current directory)

Schema matches what ContentView.swift expects:
    prices(ticker, date, open, high, low, close, volume)
    assets(ticker, name, category, parent, level)
"""

import argparse
import sqlite3
import sys
from datetime import date, datetime
from pathlib import Path

try:
    import yfinance as yf
except ImportError:
    sys.exit("yfinance not installed. Run: pip install yfinance")


# ---------------------------------------------------------------------------
# Asset registry — matches the seed data in ContentView.swift
# ---------------------------------------------------------------------------

ASSETS = [
    # ticker,  name,                   category,         parent,      level
    # ── Top-level asset classes ──────────────────────────────────────────
    ("US_EQ", "US Equities",           "equity",         None,        1),  # basket, not traded
    ("TLT",   "Long Treasuries",       "bond",           None,        1),
    ("SHV",   "Short T-Bills",         "bond",           None,        1),
    ("GLD",   "Gold",                  "commodity",      None,        1),
    ("DJP",   "Broad Commodities",     "commodity",      None,        1),
    ("UUP",   "USD Index",             "forex",          None,        1),
    ("EFA",   "Intl Developed",        "equity",         None,        1),
    ("EEM",   "Emerging Markets",      "equity",         None,        1),
    ("VNQ",   "Real Estate",           "realestate",     None,        1),
    ("SGOV",  "Cash / Money Market",   "cash",           None,        1),
    # ── US Equity Sectors (SPDR) ─────────────────────────────────────────
    ("XLK",  "Technology",             "equity_sector",  "US_EQ",     2),
    ("XLV",  "Healthcare",             "equity_sector",  "US_EQ",     2),
    ("XLF",  "Financials",             "equity_sector",  "US_EQ",     2),
    ("XLY",  "Cons. Discretionary",    "equity_sector",  "US_EQ",     2),
    ("XLP",  "Cons. Staples",          "equity_sector",  "US_EQ",     2),
    ("XLI",  "Industrials",            "equity_sector",  "US_EQ",     2),
    ("XLE",  "Energy",                 "equity_sector",  "US_EQ",     2),
    ("XLU",  "Utilities",              "equity_sector",  "US_EQ",     2),
    ("XLB",  "Materials",              "equity_sector",  "US_EQ",     2),
    ("XLRE", "Real Estate (Sector)",   "equity_sector",  "US_EQ",     2),
    ("XLC",  "Comm. Services",         "equity_sector",  "US_EQ",     2),
]

# Tickers to actually pull price data for (US_EQ is a virtual basket, no ETF)
TRADEABLE = [t for t, *_ in ASSETS if t != "US_EQ"]


# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

DDL = """
CREATE TABLE IF NOT EXISTS assets (
    ticker   TEXT PRIMARY KEY,
    name     TEXT NOT NULL,
    category TEXT NOT NULL,
    parent   TEXT,            -- NULL for top-level; FK to assets.ticker
    level    INTEGER NOT NULL -- 1 = asset class, 2 = sector
);

CREATE TABLE IF NOT EXISTS prices (
    ticker  TEXT    NOT NULL,
    date    TEXT    NOT NULL,  -- ISO 8601: YYYY-MM-DD
    open    REAL,
    high    REAL,
    low     REAL,
    close   REAL,
    volume  INTEGER,
    PRIMARY KEY (ticker, date)
);

-- Pre-computed weekly returns view; Swift can query this directly.
-- weekly_return = (close / prev_close) - 1 for each Monday's close.
CREATE VIEW IF NOT EXISTS weekly_returns AS
SELECT
    p.ticker,
    p.date,
    p.close,
    LAG(p.close) OVER (PARTITION BY p.ticker ORDER BY p.date) AS prev_close,
    (p.close / LAG(p.close) OVER (PARTITION BY p.ticker ORDER BY p.date)) - 1
        AS weekly_return
FROM prices p
WHERE strftime('%w', p.date) = '1'  -- Monday rows only
ORDER BY p.ticker, p.date;
"""


def init_db(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.executescript(DDL)
    conn.commit()
    return conn


def seed_assets(conn: sqlite3.Connection) -> None:
    conn.executemany(
        "INSERT OR REPLACE INTO assets (ticker, name, category, parent, level) VALUES (?,?,?,?,?)",
        ASSETS,
    )
    conn.commit()
    print(f"  Seeded {len(ASSETS)} asset rows.")


# ---------------------------------------------------------------------------
# Price fetching
# ---------------------------------------------------------------------------

def fetch_and_store(
    conn: sqlite3.Connection,
    tickers: list[str],
    start: str,
    end: str,
) -> None:
    """Download daily OHLCV for each ticker and insert into prices table."""
    total = len(tickers)
    for i, ticker in enumerate(tickers, 1):
        print(f"  [{i}/{total}] Fetching {ticker} …", end=" ", flush=True)
        try:
            df = yf.download(
                ticker,
                start=start,
                end=end,
                auto_adjust=True,   # adjusts for splits/dividends
                progress=False,
            )
            if df.empty:
                print("no data.")
                continue

            df = df.reset_index()
            rows = []
            for _, row in df.iterrows():
                rows.append((
                    ticker,
                    row["Date"].strftime("%Y-%m-%d"),
                    float(row["Open"])   if row["Open"]   == row["Open"] else None,
                    float(row["High"])   if row["High"]   == row["High"] else None,
                    float(row["Low"])    if row["Low"]    == row["Low"]  else None,
                    float(row["Close"])  if row["Close"]  == row["Close"] else None,
                    int(row["Volume"])   if row["Volume"] == row["Volume"] else None,
                ))

            conn.executemany(
                """INSERT OR REPLACE INTO prices
                   (ticker, date, open, high, low, close, volume)
                   VALUES (?,?,?,?,?,?,?)""",
                rows,
            )
            conn.commit()
            print(f"{len(rows)} rows.")

        except Exception as exc:
            print(f"ERROR: {exc}")


# ---------------------------------------------------------------------------
# Weekly-return summary (for quick sanity check)
# ---------------------------------------------------------------------------

def print_summary(conn: sqlite3.Connection) -> None:
    print("\n── Recent weekly returns (last 5 weeks, sample tickers) ──")
    rows = conn.execute("""
        SELECT ticker, date, round(weekly_return * 100, 2) AS pct
        FROM weekly_returns
        WHERE ticker IN ('XLK','TLT','GLD','EEM')
          AND weekly_return IS NOT NULL
        ORDER BY date DESC
        LIMIT 20
    """).fetchall()
    if not rows:
        print("  (no data yet — run with --start 2000 to populate)")
        return
    for ticker, dt, pct in rows:
        bar = "▓" * int(abs(pct)) if abs(pct) < 20 else "▓" * 20
        sign = "+" if pct >= 0 else ""
        print(f"  {ticker:<5}  {dt}  {sign}{pct:>6.2f}%  {bar}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--start", default="2000-01-01",
                   help="Start date YYYY-MM-DD (default: 2000-01-01)")
    p.add_argument("--end",   default=date.today().isoformat(),
                   help="End date YYYY-MM-DD (default: today)")
    p.add_argument("--tickers", nargs="+", default=TRADEABLE,
                   help="Override ticker list (space-separated)")
    p.add_argument("--out", default="market_data.db",
                   help="Output SQLite file path (default: market_data.db)")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    out_path = Path(args.out)

    print(f"\nSand Portfolio — Data Pipeline")
    print(f"  Tickers : {len(args.tickers)}")
    print(f"  Range   : {args.start} → {args.end}")
    print(f"  Output  : {out_path.resolve()}\n")

    conn = init_db(out_path)
    seed_assets(conn)
    fetch_and_store(conn, args.tickers, args.start, args.end)
    print_summary(conn)
    conn.close()

    size_kb = out_path.stat().st_size // 1024
    print(f"\n✓ Done. {out_path} ({size_kb:,} KB)")
    print("\nNext steps:")
    print("  1. Drag market_data.db into the SandPortfolio.swiftpm project in Xcode")
    print("  2. Add it to the AppModule target's 'Copy Bundle Resources'")
    print("  3. In ContentView.swift, add GRDB and query prices/weekly_returns")
    print("     instead of mockReturn()")


if __name__ == "__main__":
    main()
