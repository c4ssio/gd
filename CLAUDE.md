# SwiftGD — Claude Code Notes

## Project layout

- `SwiftGD.swiftpm/ContentView.swift` — entire game (models, logic, views, renderer) in one file
- Target: Swift Playgrounds on iPad (no Xcode build step available on device)

---

## Swift Playgrounds gotchas learned the hard way

### 1. `private` types can't back internal properties

If a `struct` or type is declared `private`, any property on a non-private type that returns it will fail:

```
Property must be declared fileprivate because its type uses a private type
```

**Fix:** Use `fileprivate` (scoped to the file) or drop the access modifier entirely if the type is only used within one file. In this project `BrickStyle` must be `internal` (no modifier) so that `Brick.style` can return it.

---

### 2. `Canvas` radial gradients take `CGPoint`, not `UnitPoint`

`GraphicsContext.Shading.radialGradient(center:startRadius:endRadius:)` expects a `CGPoint` in canvas-coordinate space — **not** the `UnitPoint` used by SwiftUI's declarative gradient modifiers.

```swift
// Wrong — causes "Cannot convert value of type 'UnitPoint' to 'CGPoint'"
with: .radialGradient(..., center: UnitPoint(x: 0.5, y: 0.5), ...)

// Right — pass the actual pixel coordinate
with: .radialGradient(..., center: myCenter, ...)   // myCenter: CGPoint
```

---

### 3. `GraphicsContext` is a value type — don't mutate it in helper functions

When `Canvas` calls a renderer helper (`func render(ctx: GraphicsContext, size: CGSize)`), `ctx` arrives as a `let` copy. Assigning `ctx.opacity = …` fails at compile time.

**Fix:** Wrap any opacity-scoped drawing in `ctx.drawLayer { c in … }`. Mutations on `c` are scoped to that layer and don't require the outer `ctx` to be `var`.

```swift
// Wrong
ctx.opacity = 0.18
ctx.draw(...)
ctx.opacity = 1.0

// Right
ctx.drawLayer { c in
    c.opacity = 0.18
    c.draw(...)
}
```

---

### 4. `Canvas` only redraws when `@Published` properties change

`Canvas` is not a reactive SwiftUI view. It redraws only when `objectWillChange` fires on its observed object, which only happens for `@Published` properties. Plain `var` mutations are invisible to SwiftUI — the canvas stays frozen.

**Rule:** Any property read inside a `Canvas` closure (or `renderEditor`/`renderFrame` helper) that can change at runtime **must** be `@Published`.

```swift
// Wrong — canvas never redraws when scrollX changes
var scrollX: CGFloat = 0

// Right
@Published var scrollX: CGFloat = 0
```

This applied to: `scrollX`, `playerY`, `obstacles`, `floorGaps`, `editorOpen`, `editorScrollX`, `selectedKind`, `editorEraseMode`, `customObstacles`.

---

### 5. `TimelineSchedule` — use `.periodic(from:by:)` not `.fixed`

`.fixed` does not exist on `TimelineSchedule`. For a repeating interval:

```swift
// Wrong — build error: "has no member 'fixed'"
TimelineView(.fixed(interval: 1/30)) { _ in ... }

// Right
TimelineView(.periodic(from: .now, by: 1.0/30.0)) { _ in ... }

// Also valid for game loop (fires at display refresh rate)
TimelineView(.animation) { tl in ... }
```

---

### 6. Editor canvas vs game canvas Y-coordinate mismatch

The game canvas uses `.ignoresSafeArea()` and fills the full screen, so `engine.groundY = screenHeight - groundH`. The editor canvas sits inside a VStack with toolbars, making it shorter. Rendering game-world Y coords directly into the editor places everything **below the visible canvas bottom**.

**Fix:** In the editor renderer, compute `yScale = canvasHeight / gameGroundY` and multiply all obstacle Y positions by it. Invert for placement (tap Y → game world Y).

```swift
let gY = size.height - groundH          // ground in this canvas
let yScale = gY / engine.groundY        // e.g. 250/343 ≈ 0.73
// When drawing obstacle at obs.rect.minY:
let editorY = obs.rect.minY * yScale
```

---

### 7. Fixed timestep for consistent game speed across refresh rates

`TimelineView(.animation)` fires at display refresh rate (60 Hz or 120 Hz ProMotion). Physics that advances by a fixed amount per tick will run faster on higher-refresh devices.

**Fix:** Accumulate real elapsed time and step physics in 1/60 s increments:

```swift
var accumulator: Double = 0
let fixedStep = 1.0 / 60.0

accumulator += min(rawDt, 0.1)
while accumulator >= fixedStep {
    accumulator -= fixedStep
    // physics step here
}
```

---

### 8. Syntax-check before committing

`swiftc -parse` validates Swift syntax without building or linking. Run it on `ContentView.swift` before every commit to catch API typos early:

```bash
swiftc -parse SwiftGD.swiftpm/ContentView.swift
```

Returns nothing on success, errors on failure.

---

### 9. Level design — minimum rest frames between jumps

Jump arc at `gravity=0.65, jumpVel=-13.5, scrollSpd=5`: **41 frames air time = 205 px horizontal**. Obstacles spaced less than 205 px apart require jumping before landing — physically impossible.

**Minimum safe spacing:** 400 px between consecutive required jumps (~39 frames rest). Use `swift simulate_level.swift` to verify before committing a level change. The simulator outputs a per-jump difficulty rating (🟢🟡🟠🔴).

---

### 10. Git workflow — feature branches, not main

Always work on a feature branch. Committing directly to `main` causes Xcode to require stashing whenever the user tries to switch branches.

```bash
git checkout -b feature/my-feature   # start work
# ... commits ...
# merge / PR into main when done
```

Current active branch: `feature/gd-polish`

---

## Distribution

Xcode Cloud and TestFlight both require an Apple Developer Program membership ($99/year). There is no workaround for on-device distribution to arbitrary devices. Codemagic is a viable third-party CI alternative but has the same Apple account requirement for signing.
