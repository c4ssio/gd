"""
SQLite persistence layer for gamegram.
"""

import json
import sqlite3
from pathlib import Path
from typing import Optional

DB_PATH = Path(__file__).parent.parent / "data" / "gamegram.db"


def connect(path: Path = DB_PATH) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    con.row_factory = sqlite3.Row
    _ensure_schema(con)
    return con


def _ensure_schema(con: sqlite3.Connection) -> None:
    con.executescript("""
        CREATE TABLE IF NOT EXISTS games (
            track_id        INTEGER PRIMARY KEY,
            name            TEXT NOT NULL,
            developer       TEXT,
            bundle_id       TEXT,
            store_url       TEXT,
            icon_url        TEXT,
            price           REAL DEFAULT 0,
            rating          REAL DEFAULT 0,
            rating_count    INTEGER DEFAULT 0,
            description     TEXT,
            genre           TEXT,
            genre_id        INTEGER,
            release_date    TEXT,
            version         TEXT,
            content_rating  TEXT,
            ipad_capable    INTEGER DEFAULT 0,
            ad_score        REAL DEFAULT 0,
            quality_score   REAL DEFAULT 0,
            signals         TEXT DEFAULT '[]',
            negative        TEXT DEFAULT '[]',
            verdict         TEXT DEFAULT 'unknown',
            curator_status  TEXT DEFAULT 'pending',
            curator_note    TEXT,
            scraped_at      TEXT DEFAULT (datetime('now')),
            curated_at      TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_verdict ON games(verdict);
        CREATE INDEX IF NOT EXISTS idx_curator_status ON games(curator_status);
        CREATE INDEX IF NOT EXISTS idx_rating ON games(rating DESC);

        CREATE TABLE IF NOT EXISTS votes (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            token_hash  TEXT NOT NULL,
            track_id    INTEGER NOT NULL,
            vote        INTEGER NOT NULL CHECK(vote IN (1, -1)),
            voted_at    TEXT DEFAULT (datetime('now')),
            UNIQUE(token_hash, track_id)
        );

        CREATE INDEX IF NOT EXISTS idx_votes_track ON votes(track_id);
    """)
    con.commit()


def upsert_game(con: sqlite3.Connection, game: dict, scores: dict) -> None:
    row = {**game, **scores}
    row["signals"]  = json.dumps(scores.get("signals", []))
    row["negative"] = json.dumps(scores.get("negative", []))
    row["ipad_capable"] = int(game.get("ipad_capable", False))

    # Don't overwrite curator decisions on re-scrape
    con.execute("""
        INSERT INTO games (
            track_id, name, developer, bundle_id, store_url, icon_url,
            price, rating, rating_count, description, genre, genre_id,
            release_date, version, content_rating, ipad_capable,
            ad_score, quality_score, signals, negative, verdict
        ) VALUES (
            :track_id, :name, :developer, :bundle_id, :store_url, :icon_url,
            :price, :rating, :rating_count, :description, :genre, :genre_id,
            :release_date, :version, :content_rating, :ipad_capable,
            :ad_score, :quality_score, :signals, :negative, :verdict
        )
        ON CONFLICT(track_id) DO UPDATE SET
            name           = excluded.name,
            rating         = excluded.rating,
            rating_count   = excluded.rating_count,
            description    = excluded.description,
            version        = excluded.version,
            ad_score       = excluded.ad_score,
            quality_score  = excluded.quality_score,
            signals        = excluded.signals,
            negative       = excluded.negative,
            verdict        = excluded.verdict,
            scraped_at     = datetime('now')
        WHERE curator_status = 'pending'
    """, row)
    con.commit()


def set_curator_status(
    con: sqlite3.Connection,
    track_id: int,
    status: str,
    note: str = "",
) -> None:
    assert status in ("approved", "rejected", "pending", "flagged")
    con.execute("""
        UPDATE games
        SET curator_status = ?, curator_note = ?, curated_at = datetime('now')
        WHERE track_id = ?
    """, (status, note, track_id))
    con.commit()


def get_queue(
    con: sqlite3.Connection,
    verdict_filter: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
) -> list[sqlite3.Row]:
    """Return games pending curator review, best candidates first."""
    where = "curator_status = 'pending'"
    params: list = []
    if verdict_filter:
        where += " AND verdict = ?"
        params.append(verdict_filter)
    params += [limit, offset]
    return con.execute(f"""
        SELECT * FROM games
        WHERE {where}
        ORDER BY ad_score DESC, quality_score DESC, rating_count DESC
        LIMIT ? OFFSET ?
    """, params).fetchall()


def record_vote(con: sqlite3.Connection, token_hash: str, track_id: int, vote: int) -> str:
    """
    Insert or replace a vote. Returns 'ok', 'changed', or 'unchanged'.
    Only counts votes for approved games.
    """
    assert vote in (1, -1)
    existing = con.execute(
        "SELECT vote FROM votes WHERE token_hash = ? AND track_id = ?",
        (token_hash, track_id)
    ).fetchone()
    if existing:
        if existing["vote"] == vote:
            return "unchanged"
        con.execute(
            "UPDATE votes SET vote = ?, voted_at = datetime('now') WHERE token_hash = ? AND track_id = ?",
            (vote, token_hash, track_id)
        )
        con.commit()
        return "changed"
    con.execute(
        "INSERT INTO votes (token_hash, track_id, vote) VALUES (?, ?, ?)",
        (token_hash, track_id, vote)
    )
    con.commit()
    return "ok"


def get_vote_scores(con: sqlite3.Connection) -> dict[int, int]:
    """Return {track_id: net_vote_score} for all approved games."""
    rows = con.execute("""
        SELECT v.track_id, SUM(v.vote) as score
        FROM votes v
        JOIN games g ON g.track_id = v.track_id
        WHERE g.curator_status = 'approved'
        GROUP BY v.track_id
    """).fetchall()
    return {r["track_id"]: r["score"] for r in rows}


def get_approved(con: sqlite3.Connection) -> list[sqlite3.Row]:
    return con.execute("""
        SELECT * FROM games
        WHERE curator_status = 'approved'
        ORDER BY quality_score DESC, rating DESC
    """).fetchall()


def stats(con: sqlite3.Connection) -> dict:
    row = con.execute("""
        SELECT
            COUNT(*) as total,
            SUM(CASE WHEN curator_status='pending'  THEN 1 ELSE 0 END) as pending,
            SUM(CASE WHEN curator_status='approved' THEN 1 ELSE 0 END) as approved,
            SUM(CASE WHEN curator_status='rejected' THEN 1 ELSE 0 END) as rejected,
            SUM(CASE WHEN curator_status='flagged'  THEN 1 ELSE 0 END) as flagged,
            SUM(CASE WHEN verdict='rewarded_ads'    THEN 1 ELSE 0 END) as rewarded_ads,
            SUM(CASE WHEN verdict='quality_f2p'     THEN 1 ELSE 0 END) as quality_f2p,
            SUM(CASE WHEN verdict='skip'            THEN 1 ELSE 0 END) as skip
        FROM games
    """).fetchone()
    return dict(row)
