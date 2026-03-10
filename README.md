# Swift Playgrounds Apps

A collection of arcade and simulation games built for Swift Playgrounds on iPad. Each app lives in its own `.swiftpm` package and is entirely self-contained in a single `ContentView.swift` file.

## Apps

### SwiftGD — Geometry Dash clone

`SwiftGD.swiftpm/`

A rhythm-based action platformer. The player auto-scrolls through a level, jumping over spikes, riding platforms, and passing through portals that switch between cube and ship mode.

- Fixed-timestep physics (cube + ship modes)
- Built-in level editor with tap-to-place and drag-to-move obstacles
- Parallax star field, particles, screen shake
- Portal, jump pad, speed-up/slow-down zones
- Headless test suite (`test_game.swift`, `simulate_level.swift`) for verifying level physics before committing

### SwiftST — Stock market simulation

`SwiftST.swiftpm/`

An investment simulation that replays 2024 hourly market data (SPY, QQQ, GLD, TLT, …) and lets you build and manage a portfolio in real time.

- Replay historical price bars at normal or fast speed
- Invest sheet: pick how much to invest, then choose which holdings to sell to fund it
- Portfolio view with per-asset return, dividend accrual, and allocation breakdown
- Asset detail sheets with category descriptions

Market data is pre-generated from `generate_market_data.py` and stored in `SwiftST.swiftpm/game_data.json`.

### SwiftBrickBreaker — Brick Breaker

`SwiftBrickBreaker.swiftpm/`

A classic brick-breaker arcade game with power-ups, multi-ball, and a colour-coded scoring system.

---

## Python utilities

| File | Purpose |
|------|---------|
| `generate_market_data.py` | Downloads/synthesises 2024 hourly price data and writes `game_data.json` |
| `seed_2024_synthetic.py` | Generates synthetic market data for offline use |
| `gd/game.py` | Level loader used by the Python prototype |
| `run_game.py` | Runs the Python GD prototype (pygame) |
| `simulate_level.swift` | AI playthrough of SwiftGD level — outputs per-jump difficulty |
| `test_game.swift` | 22-assertion headless test suite for SwiftGD physics + editor |

---

## Development notes

See `CLAUDE.md` for Swift Playgrounds gotchas (private types, Canvas reactivity, fixed timestep, etc.) and the git workflow.
