"""
Ad-mechanic classifier.

Scores a game description (and optionally review text) for signals that
the game uses rewarded ads or is a high-quality F2P title worth playing
despite ads.

Returns a dict:
  {
    "ad_score":     float 0-1,   # how likely it has rewarded/watchable ads
    "quality_score": float 0-1,  # proxy for game quality
    "signals":      list[str],   # matched signal phrases
    "verdict":      str,         # "rewarded_ads" | "quality_f2p" | "skip" | "unknown"
  }
"""

import re

# ---------------------------------------------------------------------------
# Signal phrase lists
# ---------------------------------------------------------------------------

# Strong positive: game explicitly offers ad-watching for rewards
REWARDED_AD_SIGNALS = [
    r"watch (an? )?(ad|video|advertisement)s? (to|and) (unlock|earn|get|receive|skip|continue)",
    r"(earn|get|unlock|win) .{0,30} (by |by watching |watching )?(an? )?(ad|video)",
    r"rewarded (ads?|videos?)",
    r"ad[\-\s]?free (upgrade|version|experience)",
    r"remove ads",
    r"no ads (upgrade|option|purchase|available)",
    r"watch video(s)? for",
    r"optional (ads?|videos?)",
    r"free[\-\s]?to[\-\s]?play with (optional )?ads",
    r"supported by (optional )?ads",
    r"ad[\-\s]supported",
]

# Quality signals: high-quality F2P with some ad tolerance
QUALITY_SIGNALS = [
    r"(award[\-\s]?winning|critically acclaimed|featured by apple|app store (best|editors|pick))",
    r"editors.{0,10}choice",
    r"(featured|highlighted) (on|by|in) (the )?app store",
    r"(millions|thousands) of (players|downloads|users)",
    r"(best|top|#1) (game|app|puzzle|strategy)",
    r"no (internet|wifi|wi[\-\s]fi) required",
    r"(offline|play offline)",
    r"(no|without) (in[\-\s]?app purchases|iap)",
    r"(no|zero|without) (pay[\-\s]?to[\-\s]?win|p2w)",
]

# Negative signals: likely predatory or heavily paywalled
NEGATIVE_SIGNALS = [
    r"(subscription required|monthly (fee|subscription|charge))",
    r"pay[\-\s]?to[\-\s]?win",
    r"(limited|limited[\-\s]time) (offer|deal|pack)",
    r"exclusive (bundle|offer|pack|deal)",
    r"vip (membership|pass|subscription)",
    r"energy (system|refill|mechanic)",
    r"stamina (system|refill)",
]


def _compile(patterns: list[str]) -> list[re.Pattern]:
    return [re.compile(p, re.IGNORECASE) for p in patterns]


_REWARDED = _compile(REWARDED_AD_SIGNALS)
_QUALITY   = _compile(QUALITY_SIGNALS)
_NEGATIVE  = _compile(NEGATIVE_SIGNALS)


# ---------------------------------------------------------------------------
# Scorer
# ---------------------------------------------------------------------------

def score(description: str, reviews: str = "", rating: float = 0.0, rating_count: int = 0) -> dict:
    text = f"{description}\n{reviews}"

    rewarded_hits = [p.pattern for p in _REWARDED if p.search(text)]
    quality_hits  = [p.pattern for p in _QUALITY  if p.search(text)]
    negative_hits = [p.pattern for p in _NEGATIVE if p.search(text)]

    # --- ad_score ---
    # Each rewarded hit adds weight; negatives reduce it
    ad_raw = len(rewarded_hits) * 0.25 - len(negative_hits) * 0.15
    ad_score = max(0.0, min(1.0, ad_raw))

    # --- quality_score ---
    # Combine text signals + rating
    rating_norm = min(rating / 5.0, 1.0) if rating > 0 else 0.0
    # Weight ratings higher when count is meaningful
    rating_weight = min(rating_count / 5000, 1.0)
    weighted_rating = rating_norm * (0.5 + 0.5 * rating_weight)

    quality_raw = len(quality_hits) * 0.2 + weighted_rating
    quality_score = max(0.0, min(1.0, quality_raw))

    # --- verdict ---
    if ad_score >= 0.25:
        verdict = "rewarded_ads"
    elif quality_score >= 0.6 and len(negative_hits) == 0:
        verdict = "quality_f2p"
    elif len(negative_hits) >= 2:
        verdict = "skip"
    else:
        verdict = "unknown"

    return {
        "ad_score":      round(ad_score, 3),
        "quality_score": round(quality_score, 3),
        "signals":       rewarded_hits + quality_hits,
        "negative":      negative_hits,
        "verdict":       verdict,
    }
