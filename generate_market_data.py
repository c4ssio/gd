#!/usr/bin/env python3
"""
Sand Portfolio — Market Data Pipeline
======================================
Pulls hourly OHLCV for all tracked tickers via yfinance and writes a
bundled SQLite database ready to drop into the SandPortfolio Xcode project.

Yahoo Finance serves up to 730 days of 1h data, fetched in ≤59-day chunks
to stay inside the API window limit.

Usage:
    pip install yfinance
    python generate_market_data.py                           # 2024, 1h bars
    python generate_market_data.py --start 2023-01-01       # back to 2023
    python generate_market_data.py --interval 1d            # daily bars
    python generate_market_data.py --tickers XLK XLV TLT   # subset

Output:
    market_data.db  (current directory)

Schema:
    assets(ticker, name, short_name, category, parent, level,
           display_group, color_hex, sort_order, description)
    prices(ticker, ts, open, high, low, close, volume)
    views: hourly_returns, weekly_returns
"""

import argparse
import sqlite3
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

try:
    import yfinance as yf
except ImportError:
    sys.exit("yfinance not installed. Run: pip install yfinance")


# ---------------------------------------------------------------------------
# Asset registry
# Matches ContentView.swift seed data; includes heatmap metadata.
# Fields: ticker, name, short_name, category, parent, level,
#         display_group, color_hex, sort_order, description
# ---------------------------------------------------------------------------

ASSETS = [
    # ── Top-level asset classes ───────────────────────────────────────────
    ("US_EQ", "US Equities",         "US Eq.",   "equity",      None,    1,
     "US Equities",   "#E8943A", 1,
     "Broad US stock market; drill down to SPDR sectors"),
    ("TLT",   "Long Treasuries",     "Bonds LT", "bond",        None,    1,
     "Fixed Income",  "#4A90D9", 1,
     "iShares 20+ Year Treasury Bond ETF"),
    ("SHV",   "Short T-Bills",       "T-Bills",  "bond",        None,    1,
     "Fixed Income",  "#5BA3E8", 2,
     "iShares Short Treasury Bond ETF; near-zero duration"),
    ("GLD",   "Gold",                "Gold",     "commodity",   None,    1,
     "Commodities",   "#C4922A", 1,
     "SPDR Gold Shares; inflation hedge and safe-haven"),
    ("DJP",   "Broad Commodities",   "Commod.",  "commodity",   None,    1,
     "Commodities",   "#A87830", 2,
     "iPath Bloomberg Commodity Index; energy, metals, agriculture"),
    ("UUP",   "USD Index",           "USD",      "forex",       None,    1,
     "Forex",         "#9B6FD4", 1,
     "Invesco DB US Dollar Index Bullish Fund"),
    ("EFA",   "Intl Developed",      "Intl Dev", "equity",      None,    1,
     "International", "#34A87A", 1,
     "iShares MSCI EAFE; Europe, Australasia, Far East large caps"),
    ("EEM",   "Emerging Markets",    "EM",       "equity",      None,    1,
     "International", "#2D9162", 2,
     "iShares MSCI Emerging Markets; China, India, Brazil"),
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
    ("VXX",   "Volatility (VIX)",   "Vol/VIX",  "volatility",  None,    1,
     "Volatility",    "#E879F9", 1,
     "ProShares VIX Short-Term Futures ETF; spikes during flight-to-safety events"),
    # ── Additional forex ─────────────────────────────────────────────────
    ("EURUSD=X", "EUR / USD",       "EUR/USD",  "forex",       None,    1,
     "Forex",         "#7C3AED", 2,
     "Euro vs US Dollar spot rate; EUR weakens in global risk-off events"),
    # JPY=X is USD/JPY — price falls when yen strengthens (safe-haven bid)
    ("JPY=X", "USD / JPY",          "USD/JPY",  "forex",       None,    1,
     "Forex",         "#A78BFA", 3,
     "US Dollar vs Japanese Yen; falls when yen strengthens as safe-haven"),
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

TRADEABLE = [t for t, *_ in ASSETS if t != "US_EQ"]


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

DDL = """
CREATE TABLE IF NOT EXISTS assets (
    ticker        TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    short_name    TEXT,
    category      TEXT NOT NULL,
    parent        TEXT REFERENCES assets(ticker),
    level         INTEGER NOT NULL,
    display_group TEXT,
    color_hex     TEXT,
    sort_order    INTEGER DEFAULT 99,
    description   TEXT
);

CREATE TABLE IF NOT EXISTS prices (
    ticker  TEXT NOT NULL REFERENCES assets(ticker),
    ts      TEXT NOT NULL,    -- ISO 8601 Eastern: YYYY-MM-DDTHH:MM:SS
    open    REAL,
    high    REAL,
    low     REAL,
    close   REAL,
    volume  INTEGER,
    PRIMARY KEY (ticker, ts)
);

CREATE INDEX IF NOT EXISTS idx_prices_ticker_ts ON prices (ticker, ts);

-- Primary game-loop view: per-tick return for every ticker
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

-- Coarser weekly view for backtest scrubber
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
    wk.first_ts                        AS week_start_ts,
    p_open.open                        AS week_open,
    p_close.close                      AS week_close,
    wk.week_high,
    wk.week_low,
    wk.week_volume,
    (p_close.close / p_open.open) - 1 AS weekly_return
FROM wk
JOIN prices p_open  ON p_open.ticker  = wk.ticker AND p_open.ts  = wk.first_ts
JOIN prices p_close ON p_close.ticker = wk.ticker AND p_close.ts = wk.last_ts;
"""


# ---------------------------------------------------------------------------
# DB init / asset seed
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
# Chunked hourly fetch
# Yahoo Finance limits 1h data to ~730 day lookback, max 60 days per request.
# ---------------------------------------------------------------------------

def date_chunks(start: str, end: str, chunk_days: int = 58) -> list[tuple[str, str]]:
    """Split [start, end] into ≤chunk_days-wide windows."""
    d = datetime.strptime(start, "%Y-%m-%d")
    end_d = datetime.strptime(end, "%Y-%m-%d")
    chunks = []
    while d < end_d:
        chunk_end = min(d + timedelta(days=chunk_days), end_d)
        chunks.append((d.strftime("%Y-%m-%d"), chunk_end.strftime("%Y-%m-%d")))
        d = chunk_end
    return chunks


def fetch_and_store(
    conn: sqlite3.Connection,
    tickers: list[str],
    start: str,
    end: str,
    interval: str,
) -> None:
    is_intraday = interval in ("1m", "2m", "5m", "15m", "30m", "60m", "90m", "1h")
    chunks = date_chunks(start, end) if is_intraday else [(start, end)]

    for i, ticker in enumerate(tickers, 1):
        print(f"  [{i}/{len(tickers)}] {ticker}", end=" ", flush=True)
        total_rows = 0

        for chunk_start, chunk_end in chunks:
            try:
                df = yf.download(
                    ticker,
                    start=chunk_start,
                    end=chunk_end,
                    interval=interval,
                    auto_adjust=True,
                    progress=False,
                )
                if df.empty:
                    continue

                df = df.reset_index()

                # Column for timestamp differs by interval
                ts_col = "Datetime" if "Datetime" in df.columns else "Date"

                rows = []
                for _, row in df.iterrows():
                    raw_ts = row[ts_col]
                    if hasattr(raw_ts, "strftime"):
                        ts_str = raw_ts.strftime("%Y-%m-%dT%H:%M:%S")
                    else:
                        ts_str = str(raw_ts)[:19]

                    def safe(v):
                        return float(v) if v == v else None  # NaN check

                    rows.append((
                        ticker, ts_str,
                        safe(row["Open"]),
                        safe(row["High"]),
                        safe(row["Low"]),
                        safe(row["Close"]),
                        int(row["Volume"]) if row["Volume"] == row["Volume"] else None,
                    ))

                conn.executemany(
                    "INSERT OR REPLACE INTO prices (ticker,ts,open,high,low,close,volume) VALUES (?,?,?,?,?,?,?)",
                    rows,
                )
                conn.commit()
                total_rows += len(rows)

            except Exception as exc:
                print(f"\n    ⚠ chunk {chunk_start}→{chunk_end}: {exc}", end=" ")

        print(f"→ {total_rows:,} rows")


# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

def print_summary(conn: sqlite3.Connection) -> None:
    print("\n── Hourly return sample (last 10 bars, 4 tickers) ──")
    rows = conn.execute("""
        SELECT ticker, ts, round(hourly_return * 100, 3) AS pct
        FROM hourly_returns
        WHERE ticker IN ('XLK','TLT','GLD','EEM')
          AND hourly_return != 0
        ORDER BY ts DESC
        LIMIT 16
    """).fetchall()
    if not rows:
        print("  (no data — check network access to finance.yahoo.com)")
        return
    for ticker, ts, pct in rows:
        sign = "+" if pct >= 0 else ""
        bar  = ("▓" * min(20, int(abs(pct) * 10))) or "·"
        print(f"  {ticker:<5}  {ts}  {sign}{pct:.3f}%  {bar}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--start",    default="2024-01-01",
                   help="Start date YYYY-MM-DD (default: 2024-01-01)")
    p.add_argument("--end",      default=date.today().isoformat(),
                   help="End date YYYY-MM-DD (default: today)")
    p.add_argument("--interval", default="1h",
                   choices=["1m","5m","15m","30m","1h","1d","1wk"],
                   help="Bar interval (default: 1h)")
    p.add_argument("--tickers",  nargs="+", default=TRADEABLE,
                   help="Override ticker list")
    p.add_argument("--out",      default="market_data.db")
    args = p.parse_args()

    out = Path(args.out)
    print(f"\nSand Portfolio — Data Pipeline")
    print(f"  Interval : {args.interval}")
    print(f"  Tickers  : {len(args.tickers)}")
    print(f"  Range    : {args.start} → {args.end}")
    print(f"  Output   : {out.resolve()}\n")

    conn = init_db(out)
    seed_assets(conn)
    fetch_and_store(conn, args.tickers, args.start, args.end, args.interval)
    print_summary(conn)
    conn.close()

    kb = out.stat().st_size // 1024
    print(f"\n✓ {out}  ({kb:,} KB)")
    print("\nNext steps:")
    print("  1. Drag market_data.db into SandPortfolio.swiftpm (Copy Bundle Resources)")
    print("  2. Add GRDB package: https://github.com/groue/GRDB.swift")
    print("  3. Replace mockReturn() in ContentView.swift with hourly_returns queries")


if __name__ == "__main__":
    main()
