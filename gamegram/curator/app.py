"""
Gamegram curator dashboard — Flask web app.

Routes:
  GET  /                  → queue (pending games, best candidates first)
  GET  /approved          → approved catalog
  POST /decide/<track_id> → approve | reject | flag a game
  GET  /api/catalog.json  → public JSON feed for the iOS switchboard app
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
    games = []
    for r in rows:
        games.append({
            "track_id":     r["track_id"],
            "name":         r["name"],
            "developer":    r["developer"],
            "genre":        r["genre"],
            "rating":       r["rating"],
            "rating_count": r["rating_count"],
            "icon_url":     r["icon_url"],
            "store_url":    r["store_url"],
            "ad_score":     r["ad_score"],
            "quality_score": r["quality_score"],
            "signals":      json.loads(r["signals"] or "[]"),
            "curator_note": r["curator_note"] or "",
        })
    return jsonify({"games": games, "count": len(games)})


if __name__ == "__main__":
    app.run(debug=True, port=5050)
