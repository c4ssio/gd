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

## Distribution

Xcode Cloud and TestFlight both require an Apple Developer Program membership ($99/year). There is no workaround for on-device distribution to arbitrary devices. Codemagic is a viable third-party CI alternative but has the same Apple account requirement for signing.
