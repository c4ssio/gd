# Sand Portfolio — iOS App Project Brief

## Concept

A tactile iOS portfolio simulation game where the user’s buying power is represented as **sand**. The player distributes sand across a 2D grid of asset class boxes. As holdings grow or shrink with market movement, sand is added or removed accordingly. The goal is to build financial intuition — not to display numbers.

-----

## Core Mechanic

- A 2D grid of boxes represents investable asset categories
- The user holds a **bag of sand** representing total buying power
- Tapping/dragging pours sand into a box, increasing allocation to that category
- Sand flows back when assets lose value; more sand appears when they gain
- No dollar amounts shown — allocation is felt, not calculated

-----

## Drill-Down Structure

1. **Top level** — broad asset classes (equities, bonds, commodities, etc.)
1. **Equity drill-down** — US equity sectors (technology, energy, financials, etc.)
1. **Sector drill-down** — baskets of companies or sub-sector ETFs within each sector

This mirrors how institutional investors think: asset class → sector → individual names.

-----

## Asset Classes to Model

Capture all major buckets that real capital rotates between, using ETF proxies for clean historical data:

|Category               |Proxy Instrument                           |
|-----------------------|-------------------------------------------|
|US Equities (by sector)|Sector SPDR ETFs (XLK, XLE, XLF, XLV, etc.)|
|Long-term Treasuries   |TLT                                        |
|Short-term T-Bills     |SHV                                        |
|Gold                   |GLD                                        |
|Broad Commodities      |DJP or PDBC                                |
|USD Index              |UUP                                        |
|International Developed|EFA                                        |
|Emerging Markets       |EEM                                        |
|Real Estate            |VNQ                                        |
|Cash / Money Market    |SGOV or equivalent                         |


> The simulation is intentionally zero-sum-ish at the rotation level. Pure equity-only models miss treasury and forex flows during panic/risk-off regimes. Including these buckets makes the simulation realistic and the game more educational.

-----

## US Equity Sectors (SPDR breakdown)

|Sector                |ETF |
|----------------------|----|
|Technology            |XLK |
|Healthcare            |XLV |
|Financials            |XLF |
|Consumer Discretionary|XLY |
|Consumer Staples      |XLP |
|Industrials           |XLI |
|Energy                |XLE |
|Utilities             |XLU |
|Materials             |XLB |
|Real Estate           |XLRE|
|Communication Services|XLC |

-----

## Simulation Modes

### 1. Known-Year Backtest

- Player selects a year (e.g., 2024)
- Data plays back week by week or month by month
- Player pours sand in real time as the year unfolds
- Final score: how did your allocation strategy perform vs. a passive index?

### 2. Blind Historical Simulation *(the interesting one)*

- App picks a random year or 12-month window from market history — **does not tell the player what year it is**
- No date labels in UI, just the shape of what markets are doing
- Player must read momentum and sector rotation without the cheat code of historical knowledge
- Tests genuine financial intuition rather than memory

### 3. Live Paper Trading *(future phase)*

- Real-time market data, no real money
- Bridge between simulation and real execution

### 4. Real Money — Personal Use *(future phase)*

- Robinhood API backend, single personal account
- ~$10k initial allocation
- Full loop: pour sand → real trades execute

-----

## Data Strategy

### Phase 1 — Bundled SQLite Database

- Ship a pre-built `.db` file inside the Xcode project bundle
- Generated once via a Python data pipeline script using `yfinance`
- Offline, fast, no backend required during prototyping
- Refresh by re-running the script and replacing the file

### Suggested Schema (starting point)

```sql
-- Asset price history
CREATE TABLE prices (
    ticker      TEXT NOT NULL,
    date        TEXT NOT NULL,   -- ISO 8601: YYYY-MM-DD
    open        REAL,
    high        REAL,
    low         REAL,
    close       REAL,
    volume      INTEGER,
    PRIMARY KEY (ticker, date)
);

-- Asset metadata
CREATE TABLE assets (
    ticker      TEXT PRIMARY KEY,
    name        TEXT,
    category    TEXT,            -- 'equity_sector', 'bond', 'commodity', etc.
    parent      TEXT,            -- e.g. 'US_EQUITIES' for sector ETFs
    level       INTEGER          -- 1=top, 2=sector, 3=company basket
);
```

### Python Data Pipeline (to be built)

- Use `yfinance` to pull OHLCV for all tickers above
- Target date range: 2000–present (captures dot-com crash, 2008, COVID, etc.)
- Output: `market_data.db` dropped into Xcode project
- Run ad-hoc to refresh; eventually automate

-----

## iOS / SwiftUI Architecture Notes

- **Grid layout** — `LazyVGrid` with dynamic box sizing by allocation weight
- **Sand animation** — drag gesture + `UIImpactFeedbackGenerator` haptics
- **Box sizing** — animate allocation changes with `.animation(.spring())`
- **Charts** — Swift Charts (iOS 16+) for drill-down performance views
- **Local DB** — GRDB Swift package for SQLite access
- **No backend required** in Phase 1

-----

## Immediate Next Steps

1. **Build the Python data pipeline** — pull all tickers above into a SQLite DB
1. **Scaffold the SwiftUI project** — Xcode project with GRDB dependency
1. **Build the top-level grid** — static layout, no data yet, just the boxes
1. **Wire up the SQLite data** — load prices, compute returns per period
1. **Build the sand mechanic** — gesture system, allocation state, haptics
1. **Implement backtest playback** — scrubber through a known year
1. **Add blind simulation mode** — random year picker, strip date labels

-----

## Open Design Questions

- How does the UI communicate loss viscerally without showing dollar amounts? (sand disappearing is intentional — lean into it)
- Sector composition shifts over time (tech in 2000 ≠ tech in 2020) — normalize or surface this as part of the game?
- Scoring system for blind simulation: total return? Sharpe ratio? Beat-the-index?
- Multiplayer / leaderboard eventually?