#!/usr/bin/env python3
"""
build_game_data.py — Extract market_data.db into game_data.json for SwiftST.

Outputs a compact JSON with:
  bars   : list of ISO-8601 timestamps (one per hourly bar, market hours)
  assets : list of {ticker, code, name, group, color, closes}
             closes[] is index-aligned to bars[]

Run after seed_2024_synthetic.py or generate_market_data.py:
  python3 build_game_data.py
"""

import sqlite3, json, os, sys

DB_PATH  = "market_data.db"
OUT_PATH = "SwiftST.swiftpm/game_data.json"

# ── Human-friendly labels ─────────────────────────────────────────────────────
# Maps DB ticker → (3-letter code, display name, override group)
# The 3-letter codes are designed to be instantly readable to non-traders.
HUMAN: dict[str, tuple[str, str, str]] = {
    # Fixed income — safest assets; receive inflows during panic
    "TLT":      ("LTB", "Long Bonds",    "Fixed Income"),
    "SHV":      ("BIL", "T-Bills",       "Fixed Income"),
    "TIP":      ("TIP", "Infl. Bonds",   "Fixed Income"),

    # Credit — corporate bonds; HYG/LQD fall when fear spikes
    "HYG":      ("JNK", "Junk Bonds",    "Credit"),
    "LQD":      ("IGC", "Corp Bonds",    "Credit"),

    # Volatility — VIX futures: 'Panic' rises sharply during crisis
    "VXX":      ("PAN", "Panic",         "Volatility"),

    # Commodities — gold = safe haven; DJP = broad commodity basket
    "GLD":      ("GLD", "Gold",          "Commodities"),
    "DJP":      ("CMD", "Commodities",   "Commodities"),

    # Forex — USD & yen both strengthen in risk-off; EUR weakens
    "UUP":      ("USD", "US Dollar",     "Forex"),
    "EURUSD=X": ("EUR", "Euro",          "Forex"),
    "JPY=X":    ("JPY", "Yen",           "Forex"),

    # International equity
    "EFA":      ("DEV", "Intl Stocks",   "International"),
    "EEM":      ("EMG", "Emerging",      "International"),

    # Alternatives
    "VNQ":      ("REI", "REITs",         "Alternatives"),

    # Cash — near-zero risk; safe parking during storms
    "SGOV":     ("CSH", "Cash",          "Cash"),

    # US equity sectors — risk-on vs risk-off rotation visible here
    "XLK":      ("TEC", "Technology",    "US Sectors"),
    "XLV":      ("HLT", "Healthcare",    "US Sectors"),
    "XLF":      ("FIN", "Financials",    "US Sectors"),
    "XLY":      ("DSC", "Discretionary", "US Sectors"),
    "XLP":      ("STA", "Staples",       "US Sectors"),
    "XLI":      ("IND", "Industrials",   "US Sectors"),
    "XLE":      ("NRG", "Energy",        "US Sectors"),
    "XLU":      ("UTL", "Utilities",     "US Sectors"),
    "XLB":      ("MAT", "Materials",     "US Sectors"),
    "XLRE":     ("RST", "RE Sector",     "US Sectors"),
    "XLC":      ("CMS", "Comm. Svcs",    "US Sectors"),
}

# Group display order in the game grid
GROUP_ORDER = [
    "US Sectors", "Fixed Income", "Credit", "Volatility",
    "Commodities", "Forex", "International", "Alternatives", "Cash",
]


def main() -> None:
    if not os.path.exists(DB_PATH):
        sys.exit(f"❌  Not found: {DB_PATH}  — run seed_2024_synthetic.py first")

    conn = sqlite3.connect(DB_PATH)

    # ── All timestamps in chronological order ──────────────────────────────
    bars: list[str] = [
        r[0] for r in conn.execute("SELECT DISTINCT ts FROM prices ORDER BY ts")
    ]
    ts_index = {ts: i for i, ts in enumerate(bars)}
    n = len(bars)

    # ── Asset metadata from DB ─────────────────────────────────────────────
    meta_rows = conn.execute("""
        SELECT ticker, color_hex, sort_order
        FROM   assets
        WHERE  ticker != 'US_EQ'
        ORDER  BY sort_order
    """).fetchall()

    result_assets = []
    missing = []

    for ticker, color_hex, db_sort in meta_rows:
        if ticker not in HUMAN:
            missing.append(ticker)
            continue

        code, name, group = HUMAN[ticker]

        # Fetch closes in timestamp order
        rows = conn.execute(
            "SELECT ts, close FROM prices WHERE ticker = ? ORDER BY ts",
            (ticker,),
        ).fetchall()

        # Build aligned array with forward-fill for any gaps
        closes: list[float | None] = [None] * n
        for ts, close in rows:
            idx = ts_index.get(ts)
            if idx is not None:
                closes[idx] = close

        last = None
        for i in range(n):
            if closes[i] is not None:
                last = closes[i]
            elif last is not None:
                closes[i] = last
        closes = [round(c, 4) if c is not None else 0.0 for c in closes]

        group_order = GROUP_ORDER.index(group) if group in GROUP_ORDER else 99

        result_assets.append({
            "_sort": group_order * 1000 + (db_sort or 0),
            "ticker": ticker,
            "code":   code,
            "name":   name,
            "group":  group,
            "color":  color_hex,
            "closes": closes,
        })

    if missing:
        print(f"⚠️   Skipped (no HUMAN entry): {missing}")

    # Sort by group order then DB sort_order
    result_assets.sort(key=lambda a: a["_sort"])
    for a in result_assets:
        del a["_sort"]

    conn.close()

    # ── Write JSON ─────────────────────────────────────────────────────────
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    payload = {"bars": bars, "assets": result_assets}
    with open(OUT_PATH, "w") as f:
        json.dump(payload, f, separators=(",", ":"))

    size_kb = os.path.getsize(OUT_PATH) / 1024
    print(f"✓  {OUT_PATH}")
    print(f"   {len(bars)} bars  ×  {len(result_assets)} assets  =  {len(bars)*len(result_assets):,} cells")
    print(f"   Raw JSON: {size_kb:.0f} KB")

    # Spot-check first and last bar for one ticker
    sample = result_assets[0]
    pct = (sample["closes"][-1] - sample["closes"][0]) / sample["closes"][0] * 100
    print(f"   Sample: {sample['code']} ({sample['ticker']})  "
          f"first={sample['closes'][0]}  last={sample['closes'][-1]}  "
          f"ytd={pct:+.1f}%")


if __name__ == "__main__":
    main()
