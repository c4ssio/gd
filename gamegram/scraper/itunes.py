"""
iTunes Search API client.
Docs: https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/
"""

import time
import requests
from typing import Iterator

SEARCH_URL = "https://itunes.apple.com/search"
LOOKUP_URL = "https://itunes.apple.com/lookup"

# Genre IDs for games on iOS
GAME_GENRE_IDS = [
    6014,   # Games (top-level)
    7001,   # Action
    7002,   # Adventure
    7003,   # Arcade
    7004,   # Board
    7005,   # Card
    7006,   # Casino
    7009,   # Family
    7011,   # Music
    7012,   # Puzzle
    7013,   # Racing
    7014,   # Role Playing
    7015,   # Simulation
    7016,   # Sports
    7017,   # Strategy
    7018,   # Trivia
    7019,   # Word
]

GAME_GENRE_NAMES = {
    6014: "Games",
    7001: "Action",
    7002: "Adventure",
    7003: "Arcade",
    7004: "Board",
    7005: "Card",
    7006: "Casino",
    7009: "Family",
    7011: "Music",
    7012: "Puzzle",
    7013: "Racing",
    7014: "RPG",
    7015: "Simulation",
    7016: "Sports",
    7017: "Strategy",
    7018: "Trivia",
    7019: "Word",
}


def search_free_games(
    term: str = "game",
    genre_id: int = 6014,
    country: str = "us",
    limit: int = 200,
) -> list[dict]:
    """
    Search for free iOS games via iTunes Search API.
    Returns raw result dicts from the API.
    """
    params = {
        "term": term,
        "country": country,
        "media": "software",
        "entity": "software",
        "genreId": genre_id,
        "price": "0",          # free only
        "limit": min(limit, 200),  # API cap is 200
    }
    resp = requests.get(SEARCH_URL, params=params, timeout=15)
    resp.raise_for_status()
    data = resp.json()
    return data.get("results", [])


def fetch_top_free_games(
    genre_ids: list[int] | None = None,
    country: str = "us",
    per_genre: int = 200,
    delay: float = 0.5,
) -> Iterator[dict]:
    """
    Yield raw app records across multiple genre searches.
    Deduplicates by trackId.
    """
    if genre_ids is None:
        genre_ids = GAME_GENRE_IDS

    seen: set[int] = set()
    for gid in genre_ids:
        results = search_free_games(
            term=GAME_GENRE_NAMES.get(gid, "game"),
            genre_id=gid,
            country=country,
            limit=per_genre,
        )
        for r in results:
            tid = r.get("trackId")
            if tid and tid not in seen:
                seen.add(tid)
                yield r
        time.sleep(delay)


def normalize(raw: dict) -> dict:
    """Pull the fields we care about from a raw iTunes result."""
    return {
        "track_id":       raw.get("trackId"),
        "name":           raw.get("trackName", ""),
        "developer":      raw.get("artistName", ""),
        "bundle_id":      raw.get("bundleId", ""),
        "store_url":      raw.get("trackViewUrl", ""),
        "icon_url":       raw.get("artworkUrl100", ""),
        "price":          raw.get("price", 0.0),
        "rating":         raw.get("averageUserRating", 0.0),
        "rating_count":   raw.get("userRatingCount", 0),
        "description":    raw.get("description", ""),
        "genre":          raw.get("primaryGenreName", ""),
        "genre_id":       raw.get("primaryGenreId"),
        "release_date":   raw.get("releaseDate", ""),
        "version":        raw.get("version", ""),
        "content_rating": raw.get("contentAdvisoryRating", ""),
        "ipad_capable":   "iPad" in raw.get("supportedDevices", []),
    }
