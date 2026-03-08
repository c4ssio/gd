// test_game.swift
// Headless tests for SwiftGD physics, editor logic, and level design.
// Usage: swift test_game.swift
// All constants and physics must stay in sync with ContentView.swift.

import Foundation

// MARK: - Mirror of game constants (keep in sync with ContentView.swift)
let playerW:   Double = 30
let playerH:   Double = 30
let gravity:   Double = 0.65
let jumpVel:   Double = -13.5
let scrollSpd: Double = 5
let groundH:   Double = 50
let screenW:   Double = 852
let screenH:   Double = 393
let groundY:   Double = screenH - groundH       // 343
let floorY:    Double = groundY - playerH       // 313

// MARK: - Test harness

var passed = 0
var failed = 0

func test(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("  ✅  \(name)")
        passed += 1
    } else {
        print("  ❌  \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        failed += 1
    }
}

func section(_ title: String) {
    print("\n── \(title) " + String(repeating: "─", count: max(0, 50 - title.count)))
}

// MARK: - Physics tests

section("Jump arc geometry")

// Simulate a single jump from ground, return (peakY, landFrame, landScrollX)
func simulateJump() -> (peakY: Double, airFrames: Int, distTravelled: Double) {
    var py = floorY, vy = jumpVel, frames = 0
    var peakY = py, dist = 0.0
    while true {
        vy += gravity
        py += vy
        dist += scrollSpd
        frames += 1
        if py < peakY { peakY = py }
        if py >= floorY && vy > 0 { py = floorY; break }
        if frames > 200 { break }  // safety
    }
    return (peakY, frames, dist)
}

let jump = simulateJump()
test("Jump arc: air time ~41 frames", abs(Double(jump.airFrames) - 41) <= 2,
     "got \(jump.airFrames) frames")
test("Jump arc: horizontal distance ~205px", abs(jump.distTravelled - 205) <= 15,
     "got \(Int(jump.distTravelled))px")
test("Jump peak above ground by >100px", floorY - jump.peakY > 100,
     "peak at y=\(Int(jump.peakY)), ground at y=\(Int(floorY))")

section("Jump pad")

// Simulate player running over a jump pad at ground level
func simulateJumpPad() -> (triggered: Bool, peakY: Double) {
    var py = floorY, vy = 0.0

    // Player is at ground level — velY=0, intersecting pad: should trigger
    let triggered = vy >= 0  // the fixed condition
    if triggered {
        vy = jumpVel * 1.35
    }
    var peakY = py
    for _ in 0..<200 {
        vy += gravity
        py += vy
        if py < peakY { peakY = py }
        if py >= floorY && vy > 0 { py = floorY; break }
    }
    return (triggered, peakY)
}

let pad = simulateJumpPad()
test("Jump pad triggers at ground level (velY=0)", pad.triggered)
test("Jump pad reaches higher than normal jump",
     pad.peakY < jump.peakY,   // lower Y number = higher on screen
     "pad peak y=\(Int(pad.peakY)) vs normal y=\(Int(jump.peakY))")

section("Spike clearance")

// Can a single jump clear a spike, given that the player jumps at jumpWorldX?
// Player is always at screen x=120; scrollX = jumpWorldX - 120 at jump moment.
func canClearSpike(spikeWorldX: Double, jumpWorldX: Double) -> Bool {
    let spikeTop = groundY - 30, spikeBot = groundY
    let spkLeft  = spikeWorldX + 2, spkRight = spikeWorldX + 28
    let playerScreenX: Double = 120

    var py = floorY, vy = jumpVel
    var scrollX = jumpWorldX - playerScreenX  // camera offset at jump frame

    for _ in 0..<100 {
        vy += gravity
        py += vy
        scrollX += scrollSpd
        let pLeft = playerScreenX, pRight = pLeft + playerW
        let obsLeft  = spkLeft  - scrollX
        let obsRight = spkRight - scrollX
        if pLeft < obsRight && pRight > obsLeft && py < spikeBot && py + playerH > spikeTop {
            return false
        }
        if py >= floorY && vy > 0 { break }
    }
    return true
}

// With jump arc = 205px, spike enters player X range when n > (spikeDistance-26)/5 frames.
// Clearable if that's after landing (>41 frames), or player is still rising enough to clear.
test("Spike 300px ahead: clearable (spike enters range after landing)",
     canClearSpike(spikeWorldX: 1300, jumpWorldX: 1000))
test("Spike 200px ahead: NOT clearable (player descending through spike height at intersection)",
     !canClearSpike(spikeWorldX: 1200, jumpWorldX: 1000))
test("Spike 50px ahead: clearable (player still rising fast when spike enters range)",
     canClearSpike(spikeWorldX: 1050, jumpWorldX: 1000))

section("Obstacle spacing / difficulty")

// Minimum rest frames between two required jumps
func restFrames(jump1WorldX: Double, jump2WorldX: Double) -> Int {
    let framesBetween = Int((jump2WorldX - jump1WorldX) / scrollSpd)
    return framesBetween - jump.airFrames
}

test("500px spacing → ≥59 rest frames (easy)",    restFrames(jump1WorldX: 0, jump2WorldX: 500) >= 59)
test("400px spacing → ≥39 rest frames (medium)",  restFrames(jump1WorldX: 0, jump2WorldX: 400) >= 39)
test("300px spacing → ≥19 rest frames (hard)",    restFrames(jump1WorldX: 0, jump2WorldX: 300) >= 19)
test("200px spacing → ≤0 rest frames (too tight)", restFrames(jump1WorldX: 0, jump2WorldX: 200) <= 0)

section("Editor erase logic")

// Simulate placing and erasing obstacles
struct ObsRect { var x, y, w, h: Double }
func rectContains(_ r: ObsRect, dx: Double = 10, dy: Double = 10, px: Double, py: Double) -> Bool {
    px >= r.x - dx && px <= r.x + r.w + dx &&
    py >= r.y - dy && py <= r.y + r.h + dy
}

var customs: [ObsRect] = []

// Place a spike at worldX=500
customs.append(ObsRect(x: 502, y: groundY-30, w: 26, h: 29))
test("Placed spike appears in custom array", customs.count == 1)

// Tap at worldX=510, gameY=groundY-15 — should hit spike
let tapX = 510.0, tapY = groundY - 15
let hit = customs.first { rectContains($0, px: tapX, py: tapY) } != nil
test("Erase hit-test finds spike at tap position", hit)

// Erase it
customs.removeAll { rectContains($0, px: tapX, py: tapY) }
test("After erase, custom array is empty", customs.count == 0)

// Tap at empty area — should not erase anything
customs.append(ObsRect(x: 502, y: groundY-30, w: 26, h: 29))
let missX = 800.0, missY = groundY - 15
customs.removeAll { rectContains($0, px: missX, py: missY) }
test("Erase miss leaves spike intact", customs.count == 1)

section("Y-scale (editor canvas coordinate mapping)")

// Editor canvas is shorter than game screen due to toolbars (~90px shorter)
let editorCanvasH = screenH - 90   // approximate
let canvasGroundY = editorCanvasH - groundH
let yScale = canvasGroundY / groundY

// A spike at game-world y=313 should map to roughly canvasGroundY-29..canvasGroundY
let spikeGameY = groundY - 30   // 313
let spikeEditorY = spikeGameY * yScale
test("Spike maps onto canvas ground (within 5px)", abs(spikeEditorY - (canvasGroundY - 29 * yScale)) < 5,
     "spikeEditorY=\(Int(spikeEditorY)) canvasGroundY=\(Int(canvasGroundY))")

// Inverse: tap at canvasGroundY-20 should map to game-world y near groundY
let tapCanvasY = canvasGroundY - 20
let tapGameY   = tapCanvasY / yScale
test("Canvas tap near ground maps to game-world near ground",
     abs(tapGameY - (groundY - 20 / yScale)) < 2)

section("Portal mode switch")

enum GameMode { case cube, ship }
var mode = GameMode.cube
var cooldown = 0

// First portal: cube → ship
if cooldown <= 0 { mode = (mode == .cube ? .ship : .cube); cooldown = 20 }
test("First portal switches cube→ship", mode == .ship)
test("Cooldown set after portal", cooldown == 20)

// Same frame: cooldown still active, should NOT switch again
if cooldown <= 0 { mode = (mode == .cube ? .ship : .cube); cooldown = 20 }
test("Portal cooldown prevents immediate re-toggle", mode == .ship)

// After cooldown expires:
cooldown = 0
if cooldown <= 0 { mode = (mode == .cube ? .ship : .cube); cooldown = 20 }
test("After cooldown, second portal switches ship→cube", mode == .cube)

// MARK: - Summary

print("\n" + String(repeating: "═", count: 52))
let total = passed + failed
print("  \(passed)/\(total) tests passed" + (failed == 0 ? "  🎉" : "  ← \(failed) FAILED"))
print(String(repeating: "═", count: 52))
if failed > 0 { exit(1) }
