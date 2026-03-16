#!/usr/bin/env python3
"""
Gamegram scraper CLI.

Usage:
  python scrape.py                      # scrape all game genres
  python scrape.py --genres action rpg  # specific genres only
  python scrape.py --limit 50           # fewer results per genre (for testing)
  python scrape.py --dry-run            # print to stdout, don't write DB
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from scraper import db
from scraper.classifier import score
from scraper.itunes import GAME_GENRE_NAMES, fetch_top_free_games, normalize

GENRE_NAME_TO_ID = {v.lower(): k for k, v in GAME_GENRE_NAMES.items()}


def parse_args():
    p = argparse.ArgumentParser(description="Gamegram App Store scraper")
    p.add_argument(
        "--genres", nargs="+", metavar="GENRE",
        help=f"Genre names to scrape. Choices: {', '.join(GENRE_NAME_TO_ID)}"
    )
    p.add_argument("--limit", type=int, default=200, help="Results per genre (max 200)")
    p.add_argument("--dry-run", action="store_true", help="Print results, don't save to DB")
    p.add_argument("--min-rating", type=float, default=0.0, help="Skip games below this rating")
    p.add_argument("--min-ratings-count", type=int, default=0, help="Skip games with fewer ratings")
    return p.parse_args()


def main():
    args = parse_args()

    # Resolve genre IDs
    if args.genres:
        genre_ids = []
        for name in args.genres:
            gid = GENRE_NAME_TO_ID.get(name.lower())
            if gid is None:
                print(f"Unknown genre '{name}'. Valid: {', '.join(GENRE_NAME_TO_ID)}", file=sys.stderr)
                sys.exit(1)
            genre_ids.append(gid)
    else:
        genre_ids = None  # all genres

    con = None if args.dry_run else db.connect()

    total = saved = skipped = 0

    print(f"Scraping {'all genres' if not args.genres else ', '.join(args.genres)} "
          f"(limit {args.limit}/genre) …\n")

    for raw in fetch_top_free_games(genre_ids=genre_ids, per_genre=args.limit):
        game = normalize(raw)
        total += 1

        if game["rating"] < args.min_rating:
            skipped += 1
            continue
        if game["rating_count"] < args.min_ratings_count:
            skipped += 1
            continue

        scores = score(
            description=game["description"],
            rating=game["rating"],
            rating_count=game["rating_count"],
        )

        if args.dry_run:
            verdict_icon = {
                "rewarded_ads": "✅",
                "quality_f2p":  "⭐",
                "skip":         "❌",
                "unknown":      "❓",
            }.get(scores["verdict"], "❓")
            print(
                f"{verdict_icon} [{scores['verdict']:14s}] "
                f"ad={scores['ad_score']:.2f} q={scores['quality_score']:.2f}  "
                f"{game['name'][:45]:45s}  ★{game['rating']:.1f} ({game['rating_count']})"
            )
            if scores["signals"]:
                for sig in scores["signals"][:2]:
                    print(f"     › {sig[:80]}")
        else:
            db.upsert_game(con, game, scores)
            saved += 1

        if total % 50 == 0:
            print(f"  … {total} processed", file=sys.stderr)

    print(f"\nDone. Total={total}  Saved={saved}  Skipped={skipped}")

    if not args.dry_run:
        s = db.stats(con)
        print(
            f"DB: {s['total']} games  |  "
            f"rewarded_ads={s['rewarded_ads']}  quality_f2p={s['quality_f2p']}  "
            f"pending review={s['pending']}"
        )


if __name__ == "__main__":
    main()
