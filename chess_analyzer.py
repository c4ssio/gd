#!/usr/bin/env python3
"""
Chess move analyzer — finds best White move.
No external dependencies. Uses Stockfish (raw UCI) if available.

White: Ke2  Qh7  Re1  Rd3  Bh6  Pawns: a3 c2 g4
Black: Ke8  Qh3  Rg8  Rd6  Bc4  Pawns: a7 e7 g5
"""

import subprocess
import sys
import os
import argparse

# ── Position ──────────────────────────────────────────────────────────────────
FEN = "4k1r1/p3p2Q/3r3B/6p1/2b3P1/P2R3q/2P1K3/4R3 w - - 0 1"

PIECE_DIAGRAM = """
  8  ·  ·  ·  ·  k  ·  r  ·
  7  p  ·  ·  ·  p  ·  ·  Q
  6  ·  ·  ·  r  ·  ·  ·  B
  5  ·  ·  ·  ·  ·  ·  p  ·
  4  ·  ·  b  ·  ·  ·  P  ·
  3  P  ·  ·  R  ·  ·  ·  q
  2  ·  ·  P  ·  K  ·  ·  ·
  1  ·  ·  ·  ·  R  ·  ·  ·
     a  b  c  d  e  f  g  h
"""

# ── Stockfish via raw UCI ─────────────────────────────────────────────────────
STOCKFISH_PATHS = [
    "stockfish",
    "/usr/bin/stockfish",
    "/usr/local/bin/stockfish",
    "/opt/homebrew/bin/stockfish",
    "/usr/games/stockfish",
]


def find_stockfish():
    for path in STOCKFISH_PATHS:
        try:
            p = subprocess.Popen(
                [path],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL, text=True,
            )
            p.stdin.write("quit\n")
            p.stdin.flush()
            p.wait(timeout=3)
            return path
        except (FileNotFoundError, OSError, subprocess.TimeoutExpired):
            pass
    return None


def run_stockfish(fen, depth=22, multipv=5):
    sf = find_stockfish()
    if not sf:
        return None

    cmd = "\n".join([
        "uci",
        f"setoption name MultiPV value {multipv}",
        "ucinewgame",
        f"position fen {fen}",
        f"go depth {depth}",
    ]) + "\n"

    try:
        result = subprocess.run(
            [sf],
            input=cmd, capture_output=True, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        return None

    lines = result.stdout.splitlines()

    # Collect the last "info depth <depth> ... multipv <N>" line for each multipv slot
    best_per_mpv = {}
    for line in lines:
        if line.startswith("info") and "multipv" in line and f"depth {depth}" in line:
            parts = line.split()
            try:
                mpv_idx = int(parts[parts.index("multipv") + 1])
                pv_start = parts.index("pv") + 1
                pv = parts[pv_start:pv_start + 6]

                # score
                if "mate" in parts:
                    mate_val = int(parts[parts.index("mate") + 1])
                    score_str = f"Mate in {mate_val}"
                elif "cp" in parts:
                    cp = int(parts[parts.index("cp") + 1])
                    score_str = f"{cp / 100:+.2f}"
                else:
                    score_str = "?"

                best_per_mpv[mpv_idx] = {"pv": pv, "score": score_str}
            except (ValueError, IndexError):
                continue

    # If depth not reached for all lines, collect last info lines per multipv
    if not best_per_mpv:
        for line in reversed(lines):
            if line.startswith("info") and "multipv" in line and " pv " in line:
                parts = line.split()
                try:
                    mpv_idx = int(parts[parts.index("multipv") + 1])
                    if mpv_idx in best_per_mpv:
                        continue
                    pv_start = parts.index("pv") + 1
                    pv = parts[pv_start:pv_start + 6]
                    if "mate" in parts:
                        mate_val = int(parts[parts.index("mate") + 1])
                        score_str = f"Mate in {mate_val}"
                    elif "cp" in parts:
                        cp = int(parts[parts.index("cp") + 1])
                        score_str = f"{cp / 100:+.2f}"
                    else:
                        score_str = "?"
                    best_per_mpv[mpv_idx] = {"pv": pv, "score": score_str}
                except (ValueError, IndexError):
                    continue

    # bestmove line
    bestmove = None
    for line in lines:
        if line.startswith("bestmove"):
            bestmove = line.split()[1]
            break

    return {"best": bestmove, "lines": best_per_mpv, "sf": sf}


# ── UCI → SAN conversion (minimal, enough for display) ───────────────────────
FILE_NAMES = "abcdefgh"
PIECE_UCI  = {
    "k": "K", "q": "Q", "r": "R", "b": "B", "n": "N", "p": "",
    "K": "K", "Q": "Q", "R": "R", "B": "B", "N": "N", "P": "",
}


def uci_to_label(uci):
    """Convert UCI move string to a readable label (approximate SAN)."""
    if len(uci) < 4:
        return uci
    return f"{uci[:2]}-{uci[2:4]}{uci[4:] if len(uci) > 4 else ''}"


def parse_fen_board(fen):
    """Return dict {square_name: piece_symbol} from FEN position part."""
    board = {}
    pos_part = fen.split()[0]
    rank = 8
    for row in pos_part.split("/"):
        file_idx = 0
        for ch in row:
            if ch.isdigit():
                file_idx += int(ch)
            else:
                sq = FILE_NAMES[file_idx] + str(rank)
                board[sq] = ch
                file_idx += 1
        rank -= 1
    return board


def board_piece_at(board_dict, sq):
    return board_dict.get(sq)


def annotate_uci(uci, board_dict):
    """Produce a human label for a UCI move given board state."""
    if len(uci) < 4:
        return uci
    from_sq = uci[:2]
    to_sq   = uci[2:4]
    promo   = uci[4:] if len(uci) > 4 else ""
    mover   = board_dict.get(from_sq, "?")
    target  = board_dict.get(to_sq)
    piece_lbl = PIECE_UCI.get(mover, mover.upper())
    capture = "x" if target else "-"
    return f"{piece_lbl}{from_sq}{capture}{to_sq}{promo.upper()}"


# ── Manual tactical analysis ──────────────────────────────────────────────────
MANUAL_ANALYSIS = """
KEY TACTICAL IDEAS
──────────────────────────────────────────────────────────────────

1. Qxg8+!  (Queen h7 captures Rook g8, with check)
   ─────────────────────────────────────────────────
   Why it works:
     • Kf8 is ILLEGAL — White Bishop on h6 controls f8 (h6–g7–f8 diagonal)
     • Kf7 is ILLEGAL — White Queen on g8 controls f7 (g8–f7 diagonal)
     • Ke7 is ILLEGAL — e7 has a Black pawn
     • Kd8 is ILLEGAL — White Rook on d3 controls d8 (d-file)
   ⟹  Black is FORCED to play Kd7 (the only legal reply)

2. After 1.Qxg8+ Kd7 — White has overwhelming threats:

   Option A: 2.Qxd8+!
     Kc7 — Queen on d8 covers c7 (d8–c7 diagonal), illegal
     Ke7 — 3.Qxe7# or 3.Re8#
     Kc6 — 3.Qd6+ or 3.Rxd6 winning more material

   Option B: 2.Rd8+! Rxd8  3.Re8+!
     Kc7 / Ke7 — both answered by Rxd8, leaving White up massive material
     Kf8? — Bh6 covers f8, illegal

   Option C: 2.Qxd6+ — simply wins the rook on d6 (already massive material gain)

MATERIAL BALANCE (before White moves)
   White: Q(9)+R(5)+R(5)+B(3)+3P(3) = 25
   Black: Q(9)+R(5)+R(5)+B(3)+3P(3) = 25   (roughly equal)

After 1.Qxg8+ Kd7 2.Qxd6:
   White net gain: +1 rook (5 pts)
   Position: completely winning

──────────────────────────────────────────────────────────────────
★  BEST WHITE MOVE:  Qxg8+  (then Qxd6, picking up the d6 rook)
──────────────────────────────────────────────────────────────────
"""


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Analyze chess position and find best White move."
    )
    parser.add_argument(
        "--depth", type=int, default=22,
        help="Stockfish search depth (default: 22)",
    )
    parser.add_argument(
        "--multipv", type=int, default=5,
        help="Number of top moves to show (default: 5)",
    )
    args = parser.parse_args()

    print("=" * 66)
    print("  Chess Move Analyzer — Best White Move")
    print("=" * 66)
    print()
    print("  White: Ke2  Qh7  Re1  Rd3  Bh6   Pawns: a3 c2 g4")
    print("  Black: Ke8  Qh3  Rg8  Rd6  Bc4   Pawns: a7 e7 g5")
    print()
    print(PIECE_DIAGRAM)
    print(f"  FEN: {FEN}")
    print()

    # ── Try Stockfish ──────────────────────────────────────────────────────
    print(f"  Searching with Stockfish (depth={args.depth}, multipv={args.multipv}) …")
    sf_result = run_stockfish(FEN, depth=args.depth, multipv=args.multipv)

    if sf_result:
        board_dict = parse_fen_board(FEN)
        print(f"  Engine : {sf_result['sf']}")
        print()
        best_uci = sf_result["best"]
        best_lbl = annotate_uci(best_uci, board_dict) if best_uci else "?"
        print(f"  ★  Best move (UCI): {best_uci}   →  {best_lbl}")
        print()
        lines = sf_result["lines"]
        if lines:
            print(f"  {'#':<3} {'Score':<18} Principal variation (UCI)")
            print("  " + "─" * 58)
            for idx in sorted(lines.keys()):
                entry = lines[idx]
                pv_str = " ".join(entry["pv"])
                score  = entry["score"]
                print(f"  {idx:<3} {score:<18} {pv_str}")
    else:
        print("  Stockfish not found — showing manual analysis.\n")
        print("  Install Stockfish for engine-quality results:")
        print("    Ubuntu/Debian : sudo apt install stockfish")
        print("    macOS         : brew install stockfish")
        print("    Windows       : https://stockfishchess.org/download/")

    # ── Always print manual analysis ──────────────────────────────────────
    print()
    print(MANUAL_ANALYSIS)


if __name__ == "__main__":
    main()
