"""
Gamegram curator dashboard — Flask web app.

Routes:
  GET  /                  → queue (pending games, best candidates first)
  GET  /approved          → approved catalog
  POST /decide/<track_id> → approve | reject | flag a game
  GET  /api/catalog.json  → public JSON feed for the iOS switchboard app
  POST /api/vote          → cast or change a vote {token_hash, track_id, vote}
"""

import json
import sys
from pathlib import Path

from flask import Flask, jsonify, redirect, render_template, request, url_for

sys.path.insert(0, str(Path(__file__).parent.parent))
from scraper import db

app = Flask(__name__, template_folder="../templates", static_folder="../static")

import json as _json
app.jinja_env.filters["from_json"] = _json.loads


def _con():
    return db.connect()


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

@app.get("/")
def queue():
    con = _con()
    verdict = request.args.get("verdict")
    page = int(request.args.get("page", 0))
    per_page = 20
    games = db.get_queue(con, verdict_filter=verdict or None, limit=per_page, offset=page * per_page)
    s = db.stats(con)
    return render_template(
        "queue.html",
        games=games,
        stats=s,
        page=page,
        verdict=verdict or "",
        per_page=per_page,
    )


@app.get("/approved")
def approved():
    con = _con()
    games = db.get_approved(con)
    s = db.stats(con)
    return render_template("approved.html", games=games, stats=s)


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

@app.post("/decide/<int:track_id>")
def decide(track_id: int):
    action = request.form.get("action", "pending")
    note   = request.form.get("note", "")
    con = _con()
    db.set_curator_status(con, track_id, action, note)
    # Return to whichever page referred us
    return redirect(request.referrer or url_for("queue"))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

@app.get("/api/catalog.json")
def catalog_json():
    con = _con()
    rows = db.get_approved(con)
    vote_scores = db.get_vote_scores(con)
    games = []
    for r in rows:
        games.append({
            "track_id":      r["track_id"],
            "name":          r["name"],
            "developer":     r["developer"],
            "genre":         r["genre"],
            "rating":        r["rating"],
            "rating_count":  r["rating_count"],
            "icon_url":      r["icon_url"],
            "store_url":     r["store_url"],
            "ad_score":      r["ad_score"],
            "quality_score": r["quality_score"],
            "signals":       json.loads(r["signals"] or "[]"),
            "curator_note":  r["curator_note"] or "",
            "vote_score":    vote_scores.get(r["track_id"], 0),
        })
    # Sort approved games by community vote score, then quality
    games.sort(key=lambda g: (g["vote_score"], g["quality_score"]), reverse=True)
    return jsonify({"games": games, "count": len(games)})


@app.post("/api/vote")
def api_vote():
    data = request.get_json(silent=True) or {}
    token_hash = data.get("token_hash", "").strip()
    track_id   = data.get("track_id")
    vote       = data.get("vote")

    if not token_hash or len(token_hash) != 64:
        return jsonify({"error": "invalid token_hash"}), 400
    if not isinstance(track_id, int):
        return jsonify({"error": "invalid track_id"}), 400
    if vote not in (1, -1):
        return jsonify({"error": "vote must be 1 or -1"}), 400

    con = _con()
    # Only allow votes on approved games
    game = con.execute(
        "SELECT track_id FROM games WHERE track_id = ? AND curator_status = 'approved'",
        (track_id,)
    ).fetchone()
    if not game:
        return jsonify({"error": "game not found"}), 404

    result = db.record_vote(con, token_hash, track_id, vote)
    new_score = con.execute(
        "SELECT COALESCE(SUM(vote), 0) as score FROM votes WHERE track_id = ?",
        (track_id,)
    ).fetchone()["score"]
    return jsonify({"status": result, "vote_score": new_score})


if __name__ == "__main__":
    app.run(debug=True, port=5050)
