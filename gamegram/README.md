# Gamegram

Curated discovery for free iOS games — beats Apple Arcade by needing zero publisher deals.

## How it works

1. **Scraper** hits the iTunes Search API, pulls free games across all categories
2. **Classifier** scores each game for rewarded-ad signals and overall quality
3. **Curator dashboard** lets your verifier approve/reject candidates
4. **JSON API** serves the approved catalog to the iOS switchboard app

## Setup

```bash
cd gamegram
pip install -r requirements.txt
```

## Scrape

```bash
# Full scrape (all genres, ~3000 games, ~30s)
python scrape.py

# Quick test — 50 arcade games, dry run (no DB write)
python scrape.py --genres arcade --limit 50 --dry-run

# Filter to high-rated games only
python scrape.py --min-rating 4.0 --min-ratings-count 500
```

## Curator dashboard

```bash
python curator/app.py
# → http://localhost:5050
```

- **Queue** — pending games sorted by ad score / quality score
- Filter by verdict: `rewarded_ads` | `quality_f2p` | `unknown` | `skip`
- Hit **Approve / Reject / Flag** per game
- Optional note field for curator context

## Public API

`GET /api/catalog.json` — returns approved game list for the iOS switchboard app.

## Project structure

```
gamegram/
  scrape.py            ← CLI entry point
  requirements.txt
  scraper/
    itunes.py          ← iTunes Search API client
    classifier.py      ← ad-mechanic NLP scorer
    db.py              ← SQLite persistence
  curator/
    app.py             ← Flask dashboard + JSON API
  templates/
    base.html
    queue.html
    approved.html
  static/css/
    style.css
  data/
    gamegram.db        ← created on first run
```

## Verdict logic

| Verdict | Meaning |
|---|---|
| `rewarded_ads` | Description explicitly mentions watch-ad-to-unlock mechanics |
| `quality_f2p` | High rating + quality signals, no predatory patterns |
| `skip` | Multiple predatory signals (energy systems, pay-to-win, forced subs) |
| `unknown` | Needs human eyes |
