# Geometry Dash - Feature Specification Prompt

## Overview
Geometry Dash is a rhythm-based action platformer where players control a geometric icon that automatically moves forward through levels filled with obstacles. The game is synchronized to energetic music, requiring precise timing and rhythm-based gameplay.

## Core Gameplay Mechanics

### 1. Player Control
- **One-Touch Controls**: Single tap/click to jump or activate mode-specific actions
- **Auto-Scrolling**: Player icon automatically moves forward through the level
- **Instant Restart**: Colliding with any obstacle immediately restarts the level from the beginning
- **No Backward Movement**: Player can only move forward (except in Platformer Mode)

### 2. Game Modes & Physics
The game features multiple modes, each with unique physics and control mechanics:

- **Cube Mode**: Standard jumping mechanics - tap to jump, affected by gravity
- **Ship Mode**: Flying mechanics - hold to ascend, release to descend, controlled flight
- **Ball Mode**: Gravity inversion - each tap flips gravity (up becomes down, down becomes up)
- **UFO Mode**: Mid-air jumping - can perform short jumps while in the air
- **Wave Mode**: Diagonal movement - moves in a wave pattern, changes direction with each input
- **Robot Mode**: Variable jump height - jump distance varies based on how long input is held
- **Spider Mode**: Instant gravity switching - immediately flips gravity upon input
- **Swing Copter Mode**: Helicopter-like navigation - controlled hovering and movement

### 3. Level Elements

#### Obstacles
- **Spikes**: Static or moving spikes that cause instant death on contact
- **Walls**: Solid barriers that block player movement
- **Moving Platforms**: Platforms that move in various patterns (horizontal, vertical, circular)
- **Saws**: Rotating saw blades that move along paths
- **Orbs**: Interactive objects that trigger actions when touched

#### Interactive Elements
- **Portals**: Change the player's mode (Cube → Ship, etc.)
- **Speed Portals**: Alter the player's movement speed (normal, slow, fast, very fast)
- **Gravity Portals**: Flip gravity direction
- **Size Portals**: Change player icon size (normal, mini, large)
- **Jump Pads**: Launch the player upward with force
- **Teleport Portals**: Instantly transport player to another location
- **Checkpoints**: Save points (used in Practice Mode)

#### Collectibles
- **Stars**: Collectible items that unlock rewards
- **Coins**: Currency for unlocking customization options
- **Secret Coins**: Hidden collectibles that unlock special rewards

## Visual Design

### Art Style
- **Minimalist Aesthetic**: Simple geometric shapes (squares, triangles, circles)
- **Vibrant Colors**: Bright, saturated color palette with high contrast
- **Clean Lines**: Sharp, well-defined edges on all shapes
- **Background Layers**: Multiple parallax scrolling background layers for depth

### Visual Effects
- **Pulse Effects**: Objects pulse in sync with music beats
- **Flash Effects**: Screen flashes on important events (deaths, mode changes)
- **Particle Effects**: Explosions, trails, and impact particles
- **Color Transitions**: Smooth color changes synchronized with music
- **Glow Effects**: Glowing outlines on important objects
- **Screen Shake**: Subtle camera shake on impacts and mode changes

### UI Elements
- **Progress Bar**: Shows level completion percentage
- **Attempt Counter**: Displays number of attempts on current level
- **Mode Indicator**: Visual indicator of current game mode
- **Icon Display**: Shows current player icon/customization

## Audio Integration

### Music System
- **Rhythm Synchronization**: All gameplay elements sync to the music's beat and tempo
- **Dynamic Soundtrack**: Music changes intensity based on level sections
- **Beat Detection**: Automatic analysis of music to detect beats and sync events
- **Multiple Tracks**: Support for various music tracks from different artists

### Sound Effects
- **Jump Sounds**: Audio feedback for player actions
- **Death Sound**: Distinct sound when player collides with obstacle
- **Mode Change Sounds**: Audio cues when entering portals
- **Collectible Sounds**: Audio feedback for collecting stars/coins
- **Impact Sounds**: Sound effects for collisions and interactions

## Level System

### Official Levels
- **27 Official Levels**: Pre-designed levels with increasing difficulty
- **Difficulty Progression**: Easy → Normal → Hard → Harder → Insane → Demon
- **Demon Difficulty Tiers**: Easy Demon, Medium Demon, Hard Demon, Insane Demon, Extreme Demon
- **Unique Themes**: Each level has distinct visual theme and music track

### Level Editor
- **Comprehensive Editor**: Full-featured level creation tool
- **Object Placement**: Drag-and-drop placement of all game elements
- **Timeline Editor**: Visual timeline for syncing objects to music
- **Testing Mode**: Playtest levels directly from editor
- **Copy/Paste**: Duplicate sections and objects
- **Grouping**: Group objects for easier manipulation
- **Layers**: Organize objects into layers for better management

### User-Generated Content
- **Level Sharing**: Upload and share custom levels online
- **Level Browser**: Browse and search community-created levels
- **Rating System**: Rate levels by difficulty and quality
- **Featured Levels**: Curated selection of high-quality community levels
- **Gauntlets**: Themed collections of user-created levels

## Game Modes

### Main Gameplay
- **Normal Mode**: Standard gameplay with instant restart on death
- **Practice Mode**: Place checkpoints to practice difficult sections
- **Platformer Mode**: Free movement left/right (introduced in v2.2)

### Additional Features
- **Daily Challenges**: Special levels available for limited time
- **Weekly Demon**: Weekly featured demon difficulty level
- **Map Packs**: Curated collections of levels with rewards

## Customization System

### Icon Customization
- **Shapes**: Multiple geometric shapes (cube, ship, ball, UFO, wave, robot, spider, swing copter)
- **Colors**: Extensive color palette for icon coloring
- **Effects**: Visual effects and trails for icons
- **Unlock System**: Unlock customization options through gameplay

### Progression
- **Achievements**: Complete challenges to unlock rewards
- **Stars**: Collect stars to unlock new icons and colors
- **Coins**: Spend coins on special customization items
- **Milestones**: Reach milestones to unlock new features

## Technical Requirements

### Performance
- **60 FPS Target**: Smooth gameplay at 60 frames per second
- **Low Latency Input**: Minimal delay between input and action
- **Optimized Rendering**: Efficient rendering for fast-paced gameplay
- **Memory Management**: Efficient handling of level data and assets

### Platform Support
- **Cross-Platform**: Support for multiple platforms (iOS, Android, Windows, macOS)
- **Touch Controls**: Optimized for touchscreen devices
- **Keyboard/Mouse**: Support for keyboard and mouse input
- **Controller Support**: Optional gamepad support

### Save System
- **Progress Tracking**: Save level completion status
- **Statistics**: Track attempts, best times, completion rates
- **Cloud Save**: Optional cloud synchronization across devices

## Community Features

### Social Integration
- **Player Profiles**: Display player statistics and achievements
- **Leaderboards**: Global and friend-based leaderboards
- **Comments**: Comment on levels and player profiles
- **Following System**: Follow favorite level creators

### Content Discovery
- **Search Functionality**: Search levels by name, creator, difficulty
- **Filtering**: Filter by difficulty, rating, date, featured status
- **Recommendations**: Suggested levels based on player preferences

## Level Design Principles

### Rhythm Integration
- **Beat Alignment**: Obstacles and jumps align with music beats
- **Tempo Changes**: Level difficulty adapts to music tempo changes
- **Drop Sections**: Intense sections during music drops
- **Build-up Sections**: Gradual difficulty increase matching music build-up

### Difficulty Curve
- **Progressive Challenge**: Gradual increase in difficulty throughout level
- **Fair Difficulty**: Challenging but not unfair obstacles
- **Readability**: Clear visual indication of upcoming obstacles
- **Pattern Recognition**: Teachable patterns that players can learn

### Visual Feedback
- **Clear Obstacles**: Obstacles are visually distinct and easy to identify
- **Color Coding**: Use colors to indicate different obstacle types
- **Timing Indicators**: Visual cues for optimal jump timing
- **Death Feedback**: Clear indication of what caused death

## Implementation Priorities

### Phase 1: Core Mechanics
1. Basic player movement and jumping
2. Obstacle collision detection
3. Level loading and rendering
4. Basic music playback and sync
5. Restart functionality

### Phase 2: Game Modes
1. Implement all 8 game modes
2. Portal system for mode switching
3. Speed and gravity portals
4. Size modification portals

### Phase 3: Level Editor
1. Object placement tools
2. Timeline editor for music sync
3. Testing and preview functionality
4. Save/load level files

### Phase 4: Polish
1. Visual effects and particles
2. Sound effects integration
3. UI/UX improvements
4. Performance optimization

### Phase 5: Community Features
1. Level sharing system
2. Online level browser
3. Rating and commenting system
4. User profiles and statistics

## References

For visual references and gameplay examples, refer to:
- Official Geometry Dash gameplay videos
- Screenshots from Steam store page
- Community-created level showcases
- Gameplay mechanics demonstration videos

---

**Note**: This specification is based on research of Geometry Dash's features and mechanics. When implementing, ensure to create original content while capturing the essence of the rhythm-based platformer genre.

