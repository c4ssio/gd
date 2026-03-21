#!/usr/bin/env python3
"""
Stockfish self-play simulation from the given position.
Both White and Black are played by Stockfish 16.

White: Ke2  Qh7  Re1  Rd3  Bh6   Pawns: a3 c2 g4
Black: Ke8  Qh3  Rg8  Rd6  Bc4   Pawns: a7 e7 g5
"""

import subprocess
import sys
import argparse
import threading
import queue

STOCKFISH = "/usr/games/stockfish"
FEN = "4k1r1/p3p2Q/3r3B/6p1/2b3P1/P2R3q/2P1K3/4R3 w - - 0 1"

# ── Minimal board tracker (SAN-like display via UCI square names) ─────────────
FILE_NAMES = "abcdefgh"


def fen_to_board(fen):
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


def apply_uci(board, uci):
    """Apply a UCI move string to a board dict, return new dict."""
    board = dict(board)
    fr, to = uci[:2], uci[2:4]
    promo = uci[4] if len(uci) > 4 else None
    piece = board.pop(fr, "?")
    # castling: move rook too
    if piece in ("K", "k"):
        if fr == "e1" and to == "g1":
            board.pop("h1", None); board["f1"] = "R"
        elif fr == "e1" and to == "c1":
            board.pop("a1", None); board["d1"] = "R"
        elif fr == "e8" and to == "g8":
            board.pop("h8", None); board["f8"] = "r"
        elif fr == "e8" and to == "c8":
            board.pop("a8", None); board["d8"] = "r"
    # en-passant capture
    if piece in ("P", "p") and fr[0] != to[0] and to not in board:
        ep_sq = to[0] + fr[1]
        board.pop(ep_sq, None)
    board[to] = (promo.upper() if piece == "P" else promo.lower()) if promo else piece
    return board


def piece_label(p):
    return {"K": "K", "Q": "Q", "R": "R", "B": "B", "N": "N", "P": "",
            "k": "k", "q": "q", "r": "r", "b": "b", "n": "n", "p": ""}.get(p, p)


def pretty_move(board, uci):
    """Return a readable label for the move, e.g. Qxg8, Rd8."""
    fr, to = uci[:2], uci[2:4]
    piece  = board.get(fr, "?")
    target = board.get(to)
    lbl    = piece_label(piece).upper()
    cap    = "x" if target else "-"
    promo  = ("=" + uci[4].upper()) if len(uci) > 4 else ""
    return f"{lbl}{fr}{cap}{to}{promo}"


def print_board(board):
    SYMBOLS = {
        "K": "♔", "Q": "♕", "R": "♖", "B": "♗", "N": "♘", "P": "♙",
        "k": "♚", "q": "♛", "r": "♜", "b": "♝", "n": "♞", "p": "♟",
    }
    print("  ┌────────────────┐")
    for rank in range(8, 0, -1):
        row = f"  {rank} │"
        for file in FILE_NAMES:
            sq = file + str(rank)
            sym = SYMBOLS.get(board.get(sq, ""), "·")
            row += f" {sym}"
        row += " │"
        print(row)
    print("  └────────────────┘")
    print("    a b c d e f g h")


# ── Stockfish UCI wrapper ─────────────────────────────────────────────────────
class Engine:
    def __init__(self, path=STOCKFISH):
        self.proc = subprocess.Popen(
            [path],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, bufsize=1,
        )
        self._q = queue.Queue()
        self._t = threading.Thread(target=self._reader, daemon=True)
        self._t.start()
        self._send("uci")
        self._wait("uciok")

    def _reader(self):
        for line in self.proc.stdout:
            self._q.put(line.rstrip())

    def _send(self, cmd):
        self.proc.stdin.write(cmd + "\n")
        self.proc.stdin.flush()

    def _wait(self, token, timeout=10):
        lines = []
        while True:
            try:
                line = self._q.get(timeout=timeout)
                lines.append(line)
                if line.startswith(token):
                    return lines
            except queue.Empty:
                raise TimeoutError(f"Timed out waiting for '{token}'")

    def set_option(self, name, value):
        self._send(f"setoption name {name} value {value}")

    def new_game(self):
        self._send("ucinewgame")
        self._send("isready")
        self._wait("readyok")

    def best_move(self, fen, moves, depth=18):
        pos = f"position fen {fen}"
        if moves:
            pos += " moves " + " ".join(moves)
        self._send(pos)
        self._send(f"go depth {depth}")
        lines = self._wait("bestmove")
        bm_line = next(l for l in reversed(lines) if l.startswith("bestmove"))
        parts = bm_line.split()
        bm = parts[1]
        # extract score from last info line
        score_str = "?"
        for l in reversed(lines):
            if l.startswith("info") and " score " in l:
                sp = l.split()
                try:
                    si = sp.index("score")
                    kind, val = sp[si+1], sp[si+2]
                    if kind == "mate":
                        score_str = f"#{val}"
                    else:
                        score_str = f"{int(val)/100:+.2f}"
                except (ValueError, IndexError):
                    pass
                break
        return bm, score_str

    def quit(self):
        try:
            self._send("quit")
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.kill()


# ── Self-play loop ────────────────────────────────────────────────────────────
def self_play(depth=18, max_moves=80):
    print(f"Stockfish 16 vs Stockfish 16  (depth={depth} per move)")
    print(f"Starting position: White to move\n")

    engine = Engine()
    engine.set_option("Threads", "2")
    engine.new_game()

    board   = fen_to_board(FEN)
    moves   = []          # UCI move history from starting FEN
    turn    = "White"
    result  = None
    move_no = 1

    # Track fifty-move rule and repetitions via simple counters
    halfmove = 0
    pos_counts = {}

    print_board(board)
    print()

    for ply in range(max_moves * 2):
        uci, score = engine.best_move(FEN, moves, depth=depth)

        if uci == "(none)" or not uci:
            # No legal moves — checkmate or stalemate
            # Determine which by checking if king is in check (heuristic: score)
            if "#" in score or score == "?":
                result = f"Checkmate — {'Black' if turn == 'White' else 'White'} wins"
            else:
                result = "Stalemate — Draw"
            break

        label = pretty_move(board, uci)
        # score is from engine's perspective (side to move)
        score_disp = score

        if turn == "White":
            print(f"  {move_no:3d}.  {label:<12}  {score_disp}")
        else:
            print(f"       {'':12}  {label:<12}  {score_disp}")
            move_no += 1

        board = apply_uci(board, uci)
        moves.append(uci)
        turn = "Black" if turn == "White" else "White"

        # Fifty-move / repetition detection (lightweight)
        fen_key = str(sorted(board.items()))
        pos_counts[fen_key] = pos_counts.get(fen_key, 0) + 1
        if pos_counts[fen_key] >= 3:
            result = "Threefold repetition — Draw"
            break
        if len(moves) > 100:
            result = "Fifty-move rule (approximation) — Draw"
            break

        # Checkmate detected by engine score
        if score.startswith("#0") or score == "#0":
            winner = "Black" if turn == "White" else "White"
            result = f"Checkmate — {winner} wins"
            break

    print()
    print_board(board)
    print()
    print("─" * 50)

    if not result:
        result = "Game unfinished (move limit reached)"

    print(f"  Result : {result}")
    print(f"  Moves  : {move_no - 1}")
    print(f"  PGN    : {' '.join(moves)}")
    print("─" * 50)
    engine.quit()


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Stockfish self-play from position.")
    parser.add_argument("--depth", type=int, default=18,
                        help="Search depth per move (default: 18)")
    parser.add_argument("--max-moves", type=int, default=80,
                        help="Max full moves before stopping (default: 80)")
    args = parser.parse_args()

    print("=" * 60)
    print("  Stockfish Self-Play — Chess Game Simulation")
    print("=" * 60)
    print()
    self_play(depth=args.depth, max_moves=args.max_moves)


if __name__ == "__main__":
    main()
