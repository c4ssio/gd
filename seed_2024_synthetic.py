#!/usr/bin/env python3
"""
Sand Portfolio — Synthetic 2024 Hourly Data Seeder
====================================================
Generates market_data.db with hourly OHLCV for all tracked tickers across
all 2024 trading days, plus rich asset metadata for heatmap grouping.

Zero dependencies beyond the standard library + sqlite3.

Usage:
    python seed_2024_synthetic.py              # writes market_data.db
    python seed_2024_synthetic.py --out dev.db # custom output path

Replace with real data when network is available:
    python generate_market_data.py --start 2024-01-01 --end 2024-12-31
"""

import argparse
import gzip
import io
import math
import random
import shutil
import sqlite3
from datetime import date, datetime, timedelta
from pathlib import Path


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

DDL = """
CREATE TABLE IF NOT EXISTS assets (
    ticker        TEXT    PRIMARY KEY,
    name          TEXT    NOT NULL,
    short_name    TEXT,                  -- tight label for heatmap cells
    category      TEXT    NOT NULL,      -- equity_sector | bond | commodity | forex | realestate | cash | equity
    parent        TEXT    REFERENCES assets(ticker),  -- NULL = top-level
    level         INTEGER NOT NULL,      -- 1 = asset class, 2 = sector
    display_group TEXT,                  -- heatmap top-level bucket label
    color_hex     TEXT,                  -- suggested base color for renderer
    sort_order    INTEGER DEFAULT 99,    -- within display_group
    description   TEXT
);

CREATE TABLE IF NOT EXISTS prices (
    ticker  TEXT    NOT NULL REFERENCES assets(ticker),
    ts      TEXT    NOT NULL,            -- ISO 8601 Eastern: YYYY-MM-DDTHH:MM:SS
    open    REAL,
    high    REAL,
    low     REAL,
    close   REAL,
    volume  INTEGER,
    PRIMARY KEY (ticker, ts)
);

CREATE INDEX IF NOT EXISTS idx_prices_ticker_ts ON prices (ticker, ts);

-- Hourly returns — primary view for the game loop
-- Join on this per tick: SELECT * FROM hourly_returns WHERE ts = ?
CREATE VIEW IF NOT EXISTS hourly_returns AS
SELECT
    ticker,
    ts,
    close,
    LAG(close) OVER (PARTITION BY ticker ORDER BY ts) AS prev_close,
    CASE
        WHEN LAG(close) OVER (PARTITION BY ticker ORDER BY ts) IS NOT NULL
        THEN (close / LAG(close) OVER (PARTITION BY ticker ORDER BY ts)) - 1
        ELSE 0.0
    END AS hourly_return
FROM prices
ORDER BY ticker, ts;

-- Weekly summary view (coarser ticks for the backtest scrubber)
CREATE VIEW IF NOT EXISTS weekly_returns AS
WITH wk AS (
    SELECT ticker,
           strftime('%Y-%W', ts) AS year_week,
           MIN(ts) AS first_ts,
           MAX(ts) AS last_ts,
           MAX(high) AS week_high,
           MIN(low)  AS week_low,
           SUM(volume) AS week_volume
    FROM prices
    GROUP BY ticker, strftime('%Y-%W', ts)
)
SELECT
    wk.ticker,
    wk.year_week,
    wk.first_ts                                   AS week_start_ts,
    wk.last_ts                                    AS week_end_ts,
    p_open.open                                   AS week_open,
    p_close.close                                 AS week_close,
    wk.week_high,
    wk.week_low,
    wk.week_volume,
    (p_close.close / p_open.open) - 1            AS weekly_return
FROM wk
JOIN prices p_open  ON p_open.ticker  = wk.ticker AND p_open.ts  = wk.first_ts
JOIN prices p_close ON p_close.ticker = wk.ticker AND p_close.ts = wk.last_ts;
"""


# ---------------------------------------------------------------------------
# Asset registry — matches ContentView.swift seed data + richer metadata
# ---------------------------------------------------------------------------
#
# Fields: ticker, name, short_name, category, parent, level,
#         display_group, color_hex, sort_order, description
#
ASSETS = [
    # ── Top-level asset classes ───────────────────────────────────────────
    ("US_EQ", "US Equities",         "US Eq.",   "equity",      None,    1,
     "US Equities",   "#E8943A", 1,
     "Broad US stock market; drill down to SPDR sectors"),

    ("TLT",   "Long Treasuries",     "Bonds LT", "bond",        None,    1,
     "Fixed Income",  "#4A90D9", 1,
     "iShares 20+ Year Treasury Bond ETF; rate-sensitive duration risk"),

    ("SHV",   "Short T-Bills",       "T-Bills",  "bond",        None,    1,
     "Fixed Income",  "#5BA3E8", 2,
     "iShares Short Treasury Bond ETF; near-zero duration, rate-insensitive"),

    ("GLD",   "Gold",                "Gold",     "commodity",   None,    1,
     "Commodities",   "#C4922A", 1,
     "SPDR Gold Shares; inflation hedge and safe-haven asset"),

    ("DJP",   "Broad Commodities",   "Commod.",  "commodity",   None,    1,
     "Commodities",   "#A87830", 2,
     "iPath Bloomberg Commodity Index; energy, metals, agriculture basket"),

    ("UUP",   "USD Index",           "USD",      "forex",       None,    1,
     "Forex",         "#9B6FD4", 1,
     "Invesco DB US Dollar Index Bullish Fund; USD vs DXY basket"),

    ("EFA",   "Intl Developed",      "Intl Dev", "equity",      None,    1,
     "International", "#34A87A", 1,
     "iShares MSCI EAFE; Europe, Australasia, Far East large caps"),

    ("EEM",   "Emerging Markets",    "EM",       "equity",      None,    1,
     "International", "#2D9162", 2,
     "iShares MSCI Emerging Markets; China, India, Brazil, etc."),

    ("VNQ",   "Real Estate",         "REITs",    "realestate",  None,    1,
     "Alternatives",  "#D4813A", 1,
     "Vanguard Real Estate ETF; US REITs across property types"),

    ("SGOV",  "Cash",                "Cash",     "cash",        None,    1,
     "Cash",          "#9CA3AF", 1,
     "iShares 0-3 Month Treasury Bond ETF; near-cash equivalent"),

    # ── Additional fixed income ───────────────────────────────────────────
    ("TIP",   "TIPS",               "TIPS",     "bond",        None,    1,
     "Fixed Income",  "#60A5FA", 3,
     "iShares TIPS Bond ETF; inflation-protected Treasuries; tracks real rates"),

    # ── Credit / spread products ─────────────────────────────────────────
    # Flight-to-safety: HYG/LQD fall as spreads widen; TLT/SGOV receive inflows
    ("HYG",   "High Yield Bonds",   "Hi Yield", "credit",      None,    1,
     "Credit",        "#F87171", 1,
     "iShares iBoxx High Yield Corporate Bond ETF; spread widens in risk-off"),

    ("LQD",   "IG Corp Bonds",      "IG Corp",  "credit",      None,    1,
     "Credit",        "#FCA5A5", 2,
     "iShares iBoxx Investment Grade Corporate Bond ETF; quality flight indicator"),

    # ── Volatility ────────────────────────────────────────────────────────
    # VXX rises sharply during panic; negative carry in calm markets
    ("VXX",   "Volatility (VIX)",   "Vol/VIX",  "volatility",  None,    1,
     "Volatility",    "#E879F9", 1,
     "ProShares VIX Short-Term Futures ETF; spikes during flight-to-safety events"),

    # ── Additional forex ─────────────────────────────────────────────────
    # EUR/USD: EUR weakens vs USD in risk-off; key rotation signal
    ("EURUSD=X", "EUR / USD",       "EUR/USD",  "forex",       None,    1,
     "Forex",         "#7C3AED", 2,
     "Euro vs US Dollar spot rate; EUR weakens in global risk-off events"),

    # USD/JPY: JPY is a safe-haven; yen STRENGTHENS (JPY=X falls) in panic
    # JPY=X is price of 1 USD in yen — rising = yen weakening
    ("JPY=X", "USD / JPY",          "USD/JPY",  "forex",       None,    1,
     "Forex",         "#A78BFA", 3,
     "US Dollar vs Japanese Yen; JPY=X falls when yen strengthens (safe-haven bid)"),

    # ── US Equity Sectors (SPDR) — parent = US_EQ ────────────────────────
    ("XLK",  "Technology",           "Tech",     "equity_sector", "US_EQ", 2,
     "US Equities",   "#F59E0B", 1,
     "Select Sector SPDR Technology; semiconductors, software, hardware"),

    ("XLV",  "Healthcare",           "Health",   "equity_sector", "US_EQ", 2,
     "US Equities",   "#EC4899", 2,
     "Select Sector SPDR Healthcare; pharma, biotech, medical devices"),

    ("XLF",  "Financials",           "Fin.",     "equity_sector", "US_EQ", 2,
     "US Equities",   "#3B82F6", 3,
     "Select Sector SPDR Financials; banks, insurance, asset managers"),

    ("XLY",  "Cons. Discretionary",  "Disc.",    "equity_sector", "US_EQ", 2,
     "US Equities",   "#8B5CF6", 4,
     "Select Sector SPDR Consumer Discretionary; retail, autos, leisure"),

    ("XLP",  "Cons. Staples",        "Staples",  "equity_sector", "US_EQ", 2,
     "US Equities",   "#6EE7B7", 5,
     "Select Sector SPDR Consumer Staples; food, beverage, household"),

    ("XLI",  "Industrials",          "Indust.",  "equity_sector", "US_EQ", 2,
     "US Equities",   "#F97316", 6,
     "Select Sector SPDR Industrials; aerospace, transport, machinery"),

    ("XLE",  "Energy",               "Energy",   "equity_sector", "US_EQ", 2,
     "US Equities",   "#78350F", 7,
     "Select Sector SPDR Energy; oil majors, refiners, drillers"),

    ("XLU",  "Utilities",            "Utils.",   "equity_sector", "US_EQ", 2,
     "US Equities",   "#A78BFA", 8,
     "Select Sector SPDR Utilities; electric, gas, water"),

    ("XLB",  "Materials",            "Matls.",   "equity_sector", "US_EQ", 2,
     "US Equities",   "#84CC16", 9,
     "Select Sector SPDR Materials; chemicals, metals, paper"),

    ("XLRE", "Real Estate (Sector)", "Sec. RE",  "equity_sector", "US_EQ", 2,
     "US Equities",   "#FB923C", 10,
     "Select Sector SPDR Real Estate; REITs within S&P 500"),

    ("XLC",  "Comm. Services",       "Comm.",    "equity_sector", "US_EQ", 2,
     "US Equities",   "#38BDF8", 11,
     "Select Sector SPDR Communication Services; Meta, Alphabet, Netflix"),
]

# Tickers with real price data (US_EQ is a virtual basket)
TRADEABLE = [t for t, *_ in ASSETS if t != "US_EQ"]


# ---------------------------------------------------------------------------
# 2024 calibration data
# ---------------------------------------------------------------------------

# Approximate annual returns (total return, 2024)
ANNUAL_RETURN_2024 = {
    # Core asset classes
    "TLT":  -0.079, "SHV":   0.053, "GLD":   0.272, "DJP":  -0.020,
    "UUP":   0.068, "EFA":   0.040, "EEM":   0.080, "VNQ":   0.054,
    "SGOV":  0.053,
    # Fixed income additions
    "TIP":   0.045,   # TIPS positive as real rates stayed elevated
    # Credit spread products
    "HYG":   0.085,   # high yield did well in the 2024 risk-on environment
    "LQD":   0.015,   # IG credit roughly flat
    # Volatility — large negative due to contango decay; VIX stayed subdued
    "VXX":  -0.580,
    # Forex (price of 1 EUR in USD; price of 1 USD in JPY)
    "EURUSD=X": -0.070,  # EUR weakened vs USD in 2024
    "JPY=X":     0.110,  # USD/JPY rose: yen weakened significantly in 2024
    # US equity sectors
    "XLK":   0.430, "XLV":   0.020, "XLF":   0.300, "XLY":   0.300,
    "XLP":  -0.010, "XLI":   0.180, "XLE":  -0.030, "XLU":   0.230,
    "XLB":   0.020, "XLRE":  0.040, "XLC":   0.400,
}

# Annual volatility (σ) — drives noise amplitude
ANNUAL_VOL = {
    "TLT":  0.140, "SHV":  0.005, "GLD":  0.130, "DJP":  0.160,
    "UUP":  0.065, "EFA":  0.120, "EEM":  0.160, "VNQ":  0.180,
    "SGOV": 0.003,
    "TIP":  0.080,
    "HYG":  0.060, "LQD":  0.070,
    "VXX":  0.650,   # very high vol; path-dependent decay
    "EURUSD=X": 0.070, "JPY=X": 0.090,
    "XLK":  0.220, "XLV":  0.140, "XLF":  0.180, "XLY":  0.220,
    "XLP":  0.110, "XLI":  0.160, "XLE":  0.220, "XLU":  0.150,
    "XLB":  0.180, "XLRE": 0.180, "XLC":  0.220,
}

# Approximate Jan 2 2024 open price
START_PRICE = {
    "TLT":  93.0,  "SHV": 110.4, "GLD": 186.5, "DJP":  19.3,
    "UUP":  28.5,  "EFA":  72.1, "EEM":  38.6, "VNQ":  82.0,
    "SGOV": 100.3,
    "TIP":  107.0,
    "HYG":  77.5,  "LQD": 108.5,
    "VXX":  27.5,
    "EURUSD=X": 1.105, "JPY=X": 141.5,
    "XLK": 192.0,  "XLV": 133.5, "XLF":  35.8, "XLY": 168.0,
    "XLP":  70.2,  "XLI": 113.0, "XLE":  88.5, "XLU":  61.0,
    "XLB":  84.0,  "XLRE": 39.2, "XLC":  64.3,
}

# Market hour slots (Eastern, 7 bars per trading day)
HOUR_SLOTS = ["09:30", "10:30", "11:30", "12:30", "13:30", "14:30", "15:00"]


# ---------------------------------------------------------------------------
# Simulation helpers
# ---------------------------------------------------------------------------

def intraday_vol_weight(slot_idx: int, n_slots: int = 7) -> float:
    """
    U-shaped intraday volatility multiplier.
    Higher at open (slot 0) and close (slot 6), quieter midday.
    Returns a value in roughly [0.4, 1.6].
    """
    x = slot_idx / max(1, n_slots - 1)   # 0.0 → 1.0
    # abs(2x-1): 1.0 at edges, 0.0 at midpoint
    return 0.5 + 1.1 * abs(2 * x - 1)


def generate_ticker(
    ticker: str,
    trading_days: list[date],
    annual_return: float,
    annual_vol: float,
    start_price: float,
    seed: int,
) -> list[tuple]:
    """
    Produce 7 hourly OHLCV bars for every trading day.

    Strategy:
      1. Generate daily closes via GBM (one random step per day).
      2. For each day, break the daily return across 7 intraday slots
         with U-shaped weighting.  Scale so the slot returns sum exactly
         to the day's log-return — the bar's close at 15:00 equals the
         GBM daily close.
      3. Construct open/high/low from the bar's return + small intraday noise.
    """
    rng = random.Random(seed)
    n_days = len(trading_days)
    dt_day = 1.0 / 252

    # ── Step 1: GBM daily closes ──────────────────────────────────────────
    daily_closes = [start_price]
    for _ in range(n_days - 1):
        drift = (annual_return - 0.5 * annual_vol ** 2) * dt_day
        shock = annual_vol * math.sqrt(dt_day) * rng.gauss(0, 1)
        daily_closes.append(daily_closes[-1] * math.exp(drift + shock))

    # Daily opens: previous close ± small overnight gap
    daily_opens = [start_price]
    for i in range(1, n_days):
        gap = rng.gauss(0, annual_vol * math.sqrt(dt_day) * 0.3)
        daily_opens.append(daily_closes[i - 1] * math.exp(gap))

    # ── Step 2 & 3: Hourly bars ──────────────────────────────────────────
    rows = []
    n_slots = len(HOUR_SLOTS)
    dt_slot = dt_day / n_slots

    for day_i, d in enumerate(trading_days):
        day_open  = daily_opens[day_i]
        day_close = daily_closes[day_i]
        day_log_ret = math.log(day_close / day_open) if day_open > 0 else 0.0

        # Weights for distributing the daily log-return across slots
        weights = [intraday_vol_weight(j, n_slots) for j in range(n_slots)]
        weight_sum = sum(weights)

        # Random noise per slot (zero-mean so they don't bias the day)
        noises = [rng.gauss(0, annual_vol * math.sqrt(dt_slot) * w)
                  for w in weights]
        noise_mean = sum(noises) / n_slots

        # Each slot log-return = its share of the day + de-meaned noise
        slot_log_rets = [
            day_log_ret * (weights[j] / weight_sum) + (noises[j] - noise_mean)
            for j in range(n_slots)
        ]

        # Force exact close: rescale so sum of slot log-returns = day_log_ret
        actual_sum = sum(slot_log_rets)
        if abs(actual_sum) > 1e-10:
            slot_log_rets = [r * day_log_ret / actual_sum for r in slot_log_rets]

        # Build bars
        price = day_open
        for slot_i, slot_lr in enumerate(slot_log_rets):
            bar_open  = price
            bar_close = price * math.exp(slot_lr)

            # Small intraday wick noise
            wick = abs(rng.gauss(0, annual_vol * math.sqrt(dt_slot) * 0.5))
            bar_high  = max(bar_open, bar_close) * (1 + wick)
            bar_low   = min(bar_open, bar_close) * (1 - wick)
            bar_vol   = int(abs(rng.gauss(200_000, 80_000)))

            ts = f"{d.isoformat()}T{HOUR_SLOTS[slot_i]}:00"
            rows.append((
                ticker,
                ts,
                round(bar_open,  4),
                round(bar_high,  4),
                round(bar_low,   4),
                round(bar_close, 4),
                bar_vol,
            ))
            price = bar_close

    return rows


def trading_days_2024() -> list[date]:
    """Weekdays in 2024 (approx — doesn't remove US holidays)."""
    days = []
    d = date(2024, 1, 2)
    while d <= date(2024, 12, 31):
        if d.weekday() < 5:
            days.append(d)
        d += timedelta(days=1)
    return days


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def init_db(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(path)
    conn.executescript(DDL)
    conn.commit()
    return conn


def seed_assets(conn: sqlite3.Connection) -> None:
    conn.executemany(
        """INSERT OR REPLACE INTO assets
           (ticker,name,short_name,category,parent,level,
            display_group,color_hex,sort_order,description)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        ASSETS,
    )
    conn.commit()
    print(f"  Seeded {len(ASSETS)} asset rows.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default="market_data.db")
    args = parser.parse_args()

    out = Path(args.out)
    if out.exists():
        out.unlink()

    print("\nSand Portfolio — Synthetic 2024 Seeder")
    print(f"  Output: {out.resolve()}\n")

    conn = init_db(out)
    seed_assets(conn)

    days = trading_days_2024()
    n_slots = len(HOUR_SLOTS)
    print(f"  Trading days: {len(days)}  ×  {n_slots} hourly bars  ×  {len(TRADEABLE)} tickers\n")

    total_rows = 0
    for ticker in TRADEABLE:
        seed = 42 + sum(ord(c) for c in ticker)
        rows = generate_ticker(
            ticker,
            days,
            annual_return=ANNUAL_RETURN_2024[ticker],
            annual_vol=ANNUAL_VOL[ticker],
            start_price=START_PRICE[ticker],
            seed=seed,
        )
        conn.executemany(
            "INSERT OR REPLACE INTO prices (ticker,ts,open,high,low,close,volume) VALUES (?,?,?,?,?,?,?)",
            rows,
        )
        conn.commit()

        actual_ret = (rows[-1][5] / rows[0][2] - 1) if rows else 0
        target_ret = ANNUAL_RETURN_2024[ticker]
        print(f"  {ticker:<5}  target {target_ret*100:+5.1f}%  actual {actual_ret*100:+6.1f}%  ({len(rows):,} rows)")
        total_rows += len(rows)

    conn.close()

    # ── Size report ───────────────────────────────────────────────────────
    raw_kb = out.stat().st_size // 1024

    buf = io.BytesIO()
    with open(out, "rb") as f_in, gzip.GzipFile(fileobj=buf, mode="wb") as gz:
        shutil.copyfileobj(f_in, gz)
    gz_kb = len(buf.getvalue()) // 1024

    print(f"\n✓ {out.name}")
    print(f"  Price rows : {total_rows:,}")
    print(f"  Raw SQLite : {raw_kb:,} KB  ({raw_kb/1024:.1f} MB)")
    print(f"  Gzip est.  : {gz_kb:,} KB  ({gz_kb/1024:.2f} MB)")
    flag = "✓ under GitHub 100 MB limit" if gz_kb < 100 * 1024 else "⚠ consider Git LFS"
    print(f"  {flag}")

    print("\nNOTE: synthetic data. Real-pipeline command:")
    print("  python generate_market_data.py --start 2024-01-01 --end 2024-12-31 --interval 1h")


if __name__ == "__main__":
    main()
