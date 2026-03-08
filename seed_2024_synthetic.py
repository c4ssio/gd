#!/usr/bin/env python3
"""
Sand Portfolio — Synthetic 2024 Data Seeder
=============================================
Generates a market_data.db with plausible 2024 daily OHLCV for all
tracked tickers, calibrated to real 2024 annual return targets.

Use this when yfinance / network access is unavailable (CI, offline
development). Replace with the real pipeline once you have internet:

    python generate_market_data.py --start 2024-01-01 --end 2024-12-31

This script has zero dependencies beyond the standard library + sqlite3.
"""

import math
import random
import sqlite3
from datetime import date, timedelta
from pathlib import Path

# ---------------------------------------------------------------------------
# Real-world 2024 annual returns (approximate, used to calibrate drift)
# Sources: commonly cited year-end ETF performance figures for 2024
# ---------------------------------------------------------------------------
ANNUAL_RETURNS_2024 = {
    # Top-level
    "TLT":   -0.08,   # long duration got hit by rates
    "SHV":    0.053,  # short T-bills ~5.3%
    "GLD":    0.27,   # gold had a strong year
    "DJP":   -0.02,   # broad commodities roughly flat
    "UUP":    0.07,   # USD strengthened
    "EFA":    0.04,   # international developed lagged
    "EEM":    0.08,   # emerging markets modest gain
    "VNQ":    0.05,   # REITs muted
    "SGOV":   0.053,  # cash / money market
    # US Equity sectors
    "XLK":    0.43,   # tech/AI boom
    "XLV":    0.02,   # healthcare flat
    "XLF":    0.30,   # financials strong
    "XLY":    0.30,   # consumer discretionary
    "XLP":   -0.01,   # staples underperformed
    "XLI":    0.18,   # industrials solid
    "XLE":   -0.03,   # energy pulled back
    "XLU":    0.23,   # utilities benefited from AI power demand
    "XLB":    0.02,   # materials flat
    "XLRE":   0.04,   # sector real estate muted
    "XLC":    0.40,   # comm services (Meta, Alphabet)
}

# Approximate annual volatility (σ) per asset class — used for noise
ANNUAL_VOL = {
    "TLT": 0.14, "SHV": 0.005, "GLD": 0.13, "DJP": 0.16, "UUP": 0.07,
    "EFA": 0.12, "EEM": 0.16,  "VNQ": 0.18, "SGOV": 0.003,
    "XLK": 0.22, "XLV": 0.14,  "XLF": 0.18, "XLY": 0.22, "XLP": 0.11,
    "XLI": 0.16, "XLE": 0.22,  "XLU": 0.15, "XLB": 0.18, "XLRE": 0.18,
    "XLC": 0.22,
}

# Approximate starting price (Jan 1 2024) — close enough for simulation
START_PRICE = {
    "TLT":  92.0,  "SHV":  110.4, "GLD":  186.0, "DJP":  19.2,  "UUP": 28.5,
    "EFA":  72.0,  "EEM":   38.5, "VNQ":   82.0, "SGOV": 100.3,
    "XLK": 191.0,  "XLV":  134.0, "XLF":   36.0, "XLY": 168.0,  "XLP": 70.0,
    "XLI": 113.0,  "XLE":   88.0, "XLU":   61.0, "XLB":  84.0,  "XLRE": 39.0,
    "XLC": 64.0,
}

ASSETS = [
    ("US_EQ", "US Equities",          "equity",         None,      1),
    ("TLT",   "Long Treasuries",       "bond",           None,      1),
    ("SHV",   "Short T-Bills",         "bond",           None,      1),
    ("GLD",   "Gold",                  "commodity",      None,      1),
    ("DJP",   "Broad Commodities",     "commodity",      None,      1),
    ("UUP",   "USD Index",             "forex",          None,      1),
    ("EFA",   "Intl Developed",        "equity",         None,      1),
    ("EEM",   "Emerging Markets",      "equity",         None,      1),
    ("VNQ",   "Real Estate",           "realestate",     None,      1),
    ("SGOV",  "Cash / Money Market",   "cash",           None,      1),
    ("XLK",  "Technology",             "equity_sector",  "US_EQ",   2),
    ("XLV",  "Healthcare",             "equity_sector",  "US_EQ",   2),
    ("XLF",  "Financials",             "equity_sector",  "US_EQ",   2),
    ("XLY",  "Cons. Discretionary",    "equity_sector",  "US_EQ",   2),
    ("XLP",  "Cons. Staples",          "equity_sector",  "US_EQ",   2),
    ("XLI",  "Industrials",            "equity_sector",  "US_EQ",   2),
    ("XLE",  "Energy",                 "equity_sector",  "US_EQ",   2),
    ("XLU",  "Utilities",              "equity_sector",  "US_EQ",   2),
    ("XLB",  "Materials",              "equity_sector",  "US_EQ",   2),
    ("XLRE", "Real Estate (Sector)",   "equity_sector",  "US_EQ",   2),
    ("XLC",  "Comm. Services",         "equity_sector",  "US_EQ",   2),
]

DDL = """
CREATE TABLE IF NOT EXISTS assets (
    ticker   TEXT PRIMARY KEY,
    name     TEXT NOT NULL,
    category TEXT NOT NULL,
    parent   TEXT,
    level    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS prices (
    ticker  TEXT    NOT NULL,
    date    TEXT    NOT NULL,
    open    REAL,
    high    REAL,
    low     REAL,
    close   REAL,
    volume  INTEGER,
    PRIMARY KEY (ticker, date)
);
CREATE VIEW IF NOT EXISTS weekly_returns AS
SELECT
    p.ticker,
    p.date,
    p.close,
    LAG(p.close) OVER (PARTITION BY p.ticker ORDER BY p.date) AS prev_close,
    (p.close / LAG(p.close) OVER (PARTITION BY p.ticker ORDER BY p.date)) - 1
        AS weekly_return
FROM prices p
WHERE strftime('%w', p.date) = '1'
ORDER BY p.ticker, p.date;
"""


def trading_days_2024() -> list[date]:
    """Returns all weekdays in 2024 (simplified — doesn't remove holidays)."""
    days = []
    d = date(2024, 1, 2)  # first trading day
    end = date(2024, 12, 31)
    while d <= end:
        if d.weekday() < 5:   # Mon–Fri
            days.append(d)
        d += timedelta(days=1)
    return days


def gbm_prices(
    ticker: str,
    days: list[date],
    annual_return: float,
    annual_vol: float,
    start_price: float,
    seed: int,
) -> list[tuple]:
    """
    Generate daily OHLCV via Geometric Brownian Motion.
    Returns list of (ticker, date, open, high, low, close, volume).
    """
    rng = random.Random(seed)
    n = len(days)
    dt = 1 / 252
    mu = annual_return
    sigma = annual_vol

    prices = [start_price]
    for _ in range(n - 1):
        z = rng.gauss(0, 1)
        drift = (mu - 0.5 * sigma ** 2) * dt
        shock = sigma * math.sqrt(dt) * z
        prices.append(prices[-1] * math.exp(drift + shock))

    rows = []
    for i, (d, close) in enumerate(zip(days, prices)):
        prev = prices[i - 1] if i > 0 else close
        open_ = prev * (1 + rng.gauss(0, 0.002))
        intraday_range = abs(rng.gauss(0, sigma * math.sqrt(dt) * 1.5))
        high = max(open_, close) * (1 + intraday_range)
        low  = min(open_, close) * (1 - intraday_range)
        volume = int(rng.uniform(0.5e6, 5e6))
        rows.append((ticker, d.isoformat(), round(open_, 4), round(high, 4),
                     round(low, 4), round(close, 4), volume))
    return rows


def main():
    out = Path("market_data.db")
    rng_seed_base = 42

    conn = sqlite3.connect(out)
    conn.executescript(DDL)

    conn.executemany(
        "INSERT OR REPLACE INTO assets (ticker,name,category,parent,level) VALUES (?,?,?,?,?)",
        ASSETS,
    )
    conn.commit()
    print(f"Seeded {len(ASSETS)} asset rows.")

    days = trading_days_2024()
    print(f"Generating {len(days)} trading days × {len(ANNUAL_RETURNS_2024)} tickers …")

    total_rows = 0
    for ticker, annual_ret in ANNUAL_RETURNS_2024.items():
        seed = rng_seed_base + sum(ord(c) for c in ticker)
        rows = gbm_prices(
            ticker,
            days,
            annual_return=annual_ret,
            annual_vol=ANNUAL_VOL.get(ticker, 0.15),
            start_price=START_PRICE.get(ticker, 100.0),
            seed=seed,
        )
        conn.executemany(
            "INSERT OR REPLACE INTO prices (ticker,date,open,high,low,close,volume) VALUES (?,?,?,?,?,?,?)",
            rows,
        )
        conn.commit()
        actual_ret = (rows[-1][5] / rows[0][5]) - 1
        print(f"  {ticker:<5}  {annual_ret*100:+.1f}% target  {actual_ret*100:+.1f}% actual  ({len(rows)} rows)")
        total_rows += len(rows)

    conn.close()

    raw_kb  = out.stat().st_size // 1024
    print(f"\n✓ {out}  —  {total_rows:,} price rows  —  {raw_kb} KB raw SQLite")

    # Estimate gzip size
    import gzip, io, shutil
    buf = io.BytesIO()
    with open(out, "rb") as f_in, gzip.GzipFile(fileobj=buf, mode="wb") as f_gz:
        shutil.copyfileobj(f_in, f_gz)
    gz_kb = len(buf.getvalue()) // 1024
    print(f"   Estimated gzip size: {gz_kb} KB  ({gz_kb/1024:.2f} MB)")
    print(f"\n   {'✓ Well under 100 MB GitHub limit' if gz_kb < 100*1024 else '⚠ Large — consider LFS'}")

    print("\nNOTE: This is synthetic data calibrated to real 2024 returns.")
    print("      Replace with: python generate_market_data.py --start 2024-01-01 --end 2024-12-31")


if __name__ == "__main__":
    main()
