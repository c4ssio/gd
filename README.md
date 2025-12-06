# Geometry Dash

A rhythm-based action platformer game implementation.

## Project Structure

```
gd/
├── gd/              # Main game code
│   └── game.py      # Level loader and processor
├── levels/          # Level configuration files (YAML)
│   └── level_01.yml # First tutorial level
├── requirements.txt # Python dependencies
└── README.md        # This file
```

## Level Configuration Format

Levels are stored as YAML files in the `levels/` directory. Each level file contains:

- **metadata**: Level name, difficulty, description, etc.
- **settings**: Player start configuration, level dimensions, theme colors, music settings
- **objects**: All game objects organized by type:
  - `platforms`: Solid surfaces the player can land on
  - `obstacles`: Spikes, walls, and other hazards
  - `moving_platforms`: Platforms that move in patterns
  - `portals`: Mode, speed, gravity, size, and teleport portals
  - `jump_pads`: Launch pads that boost the player
  - `collectibles`: Stars and coins
  - `checkpoints`: Save points for practice mode
  - `decorations`: Non-interactive visual elements
- **sync_points**: Music synchronization points for rhythm-based gameplay

## Usage

### Loading a Level

```python
from gd.game import LevelLoader, LevelProcessor

# Initialize loader
loader = LevelLoader()

# Load a level
level_data = loader.load_level("level_01")

# Process the level
processor = LevelProcessor(level_data)

# Access level information
player_start = processor.get_player_start()
obstacles = processor.get_all_obstacles()
platforms = processor.get_all_platforms()
```

### Creating a New Level

1. Create a new YAML file in the `levels/` directory
2. Follow the structure defined in `level_01.yml`
3. Use the `LevelLoader` to load and validate your level

## Installation

```bash
pip install -r requirements.txt
```

## Running the Game

To play the game, run:

```bash
python3 run_game.py
```

Or use the module directly:

```bash
python3 -m gd.main
```

Or specify a level:

```bash
python3 -m gd.main --level level_01
```

### Controls

- **SPACE**: Jump (or restart after death)
- **ESC**: Quit game

### Gameplay

- The player automatically moves forward
- Press SPACE to jump over obstacles
- Avoid spikes and walls - they cause instant death
- Collect stars and coins for points
- Use jump pads to launch higher
- Navigate moving platforms carefully

## Level 01: First Steps

The first level is a simple tutorial that introduces:
- Basic jumping mechanics
- Simple obstacles (spikes)
- Platforms at different heights
- Collectibles (stars and coins)
- A moving platform
- A jump pad

This level serves as a template for creating additional levels.

## Game Features

### Implemented
- ✅ Player physics (cube mode)
- ✅ Auto-scrolling camera
- ✅ Platform collision detection
- ✅ Obstacle collision (spikes, walls)
- ✅ Collectibles (stars, coins)
- ✅ Moving platforms
- ✅ Jump pads
- ✅ Progress tracking
- ✅ Attempt counter
- ✅ Game over and restart
- ✅ Level loading from YAML

### Planned
- Additional game modes (Ship, Ball, UFO, Wave, Robot, Spider, Swing Copter)
- Portals (mode, speed, gravity, size)
- Music synchronization
- Sound effects
- Particle effects
- Level editor

