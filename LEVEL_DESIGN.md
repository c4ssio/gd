# Level Design Guidelines

## Jump Mechanics

### Player Physics
- **Player height**: 30 pixels
- **Jump force**: -12 (upward velocity)
- **Gravity**: 0.8 pixels/frame²
- **Max jump height**: ~90 pixels upward from starting position
- **Jump duration**: ~30 frames (15 frames up + 15 frames down)
- **Player speed**: 4 pixels/frame (normal speed)

### Calculating Reachable Heights

When a player is on a platform:
- Player bottom = platform top
- Player top = platform top - 30 (player height)

When jumping:
- Player top reaches: `current_top - 90` pixels
- Player can land on platforms where: `platform_top >= jump_reach_top + 30`

### Platform Height Guidelines

For a level to be completable, ensure:
1. **First platform after ground**: Maximum 60 pixels above ground
2. **Subsequent platforms**: Maximum 60 pixels above previous platform
3. **Horizontal spacing**: Minimum 100 pixels between platform edges (gives ~25 frames for jump timing)

### Level 01 Design

**Platform Progression:**
- Ground: y=400 (starting position)
- Platform 2: y=340 (60 pixels above ground) ✓
- Platform 3: y=280 (60 pixels above platform 2) ✓
- Ground 4: y=400 (drop down from platform 3) ✓

**Horizontal Spacing:**
- Ground to Platform 2: 50 pixels gap (comfortable)
- Platform 2 to Platform 3: 50 pixels gap (comfortable)
- Platform 3 to Ground 4: 50 pixels gap (comfortable drop)

**Platform Widths:**
- Tutorial platforms: 250 pixels wide (forgiving landing)
- Ground sections: 500+ pixels wide (safe starting/ending areas)

## Best Practices

1. **Start Easy**: First level should have generous spacing and low platforms
2. **Progressive Difficulty**: Gradually increase height differences and reduce spacing
3. **Visual Cues**: Place obstacles before platforms to encourage jumping
4. **Safety Nets**: Wide platforms for landing, especially in tutorial levels
5. **Test Jumps**: Always verify that each platform is reachable from the previous one

## Validation Checklist

Before finalizing a level:
- [ ] Player starts on ground/platform
- [ ] All platforms are within 90 pixels vertical reach
- [ ] Horizontal spacing allows comfortable jump timing
- [ ] No impossible jumps (platforms too high or too far)
- [ ] Level can be completed without getting stuck
- [ ] Obstacles are placed to guide player, not block progress

