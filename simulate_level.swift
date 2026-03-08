// simulate_level.swift
// Mirrors ContentView.swift physics exactly and runs an AI player through the level.
// Usage: swift simulate_level.swift
// Usage (specific screen size): swift simulate_level.swift 852 393

import Foundation

// MARK: - Constants (must match ContentView.swift)
let playerW:  Double = 30
let playerH:  Double = 30
let gravity:  Double = 0.65
let jumpVel:  Double = -13.5
let scrollSpd: Double = 5
let levelLen:  Double = 7700
let groundH:   Double = 50

// Screen size — default is iPhone 15 landscape
let screenW: Double = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[1])! : 852
let screenH: Double = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 393
let groundY: Double = screenH - groundH
let floorY:  Double = groundY - playerH

// MARK: - Types
enum ObstacleKind: CustomStringConvertible {
    case spike, block, platform, ceilSpike, jumpPad, portal
    var description: String {
        switch self {
        case .spike: return "spike"
        case .block: return "block"
        case .platform: return "platform"
        case .ceilSpike: return "ceilSpike"
        case .jumpPad: return "jumpPad"
        case .portal: return "portal"
        }
    }
}
enum GameMode { case cube, ship }

struct Obs {
    var x, y, w, h: Double
    var kind: ObstacleKind
}

// MARK: - Level builder (must match ContentView.swift buildLevel exactly)
func buildLevel() -> (obstacles: [Obs], gaps: [(Double, Double)]) {
    var obs: [Obs] = []
    var gaps: [(Double, Double)] = []
    let gY = groundY

    func spike(_ x: Double, _ ci: Int = 0) {
        obs.append(Obs(x: x+2, y: gY-30, w: 26, h: 29, kind: .spike))
    }
    func cSpike(_ x: Double, _ y: Double) {
        obs.append(Obs(x: x+2, y: y, w: 26, h: 29, kind: .ceilSpike))
    }
    func block(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ ci: Int = 1) {
        obs.append(Obs(x: x, y: y, w: w, h: h, kind: .block))
    }
    func plat(_ x: Double, _ y: Double, _ w: Double) {
        obs.append(Obs(x: x, y: y, w: w, h: 12, kind: .platform))
    }
    func pad(_ x: Double) {
        obs.append(Obs(x: x, y: gY-18, w: 36, h: 18, kind: .jumpPad))
    }
    func pit(_ s: Double, _ e: Double) { gaps.append((s, e)) }
    func portal(_ x: Double) {
        obs.append(Obs(x: x, y: 20, w: 24, h: gY-20, kind: .portal))
    }
    func twall(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        obs.append(Obs(x: x, y: y, w: w, h: h, kind: .block))
    }

    // ── Section 1 ──────────────────────────────────────── x 800–1600
    spike(800); spike(1050); spike(1300); spike(1550)

    // ── Section 2 ──────────────────────────────────────── x 1850–2700
    spike(1850); spike(2050); spike(2250); spike(2450)
    pad(2650)

    // ── Section 3 ──────────────────────────────────────── x 2900–3600
    plat(2900, gY-80, 150); cSpike(2970, 30)
    spike(3110)
    plat(3200, gY-130, 120); cSpike(3240, 20)
    plat(3420, gY-80, 120)
    spike(3580)

    // ── Ship section ───────────────────────────────────── x 3800–4000
    portal(3800)
    let tunnelY = gY - 110
    let gapH: Double = 80
    twall(3840, 0, 180, tunnelY)
    twall(3940, 0, 180, tunnelY-20)
    portal(3990)

    // ── Section 4 ──────────────────────────────────────── x 4200–5100
    pit(4250, 4370)
    spike(4510)
    pit(4660, 4780)
    pit(4980, 5060)

    // ── Section 5 ──────────────────────────────────────── x 5200–6400
    spike(5200)
    cSpike(5380, 15)
    spike(5460)
    spike(5660)
    cSpike(5720, 15)
    spike(5850)
    spike(6050)
    plat(6200, gY-90, 140); cSpike(6230, 20)
    spike(6370)

    // ── Section 6 ──────────────────────────────────────── x 6550–7400
    spike(6550, 0); spike(6750, 1)
    spike(6950, 2); spike(7150, 0)
    pit(7400, 7520)
    spike(7600)

    return (obs, gaps)
}

// MARK: - Helpers
func intersects(_ ax: Double, _ ay: Double, _ aw: Double, _ ah: Double,
                _ bx: Double, _ by: Double, _ bw: Double, _ bh: Double) -> Bool {
    ax < bx+bw && ax+aw > bx && ay < by+bh && ay+ah > by
}

func overGap(_ scrollX: Double, _ px: Double, _ gaps: [(Double, Double)]) -> Bool {
    let lw = scrollX + px
    let rw = scrollX + px + playerW
    return gaps.contains { rw > $0.0 && lw < $0.1 }
}

// MARK: - AI: jump when a deadly obstacle or pit is within the trigger window
// triggerDist: how far ahead (in screen px) to react. Tuned to ~half a jump arc.
let triggerDist: Double = 120

func shouldJump(px: Double, scrollX: Double,
                obstacles: [Obs], gaps: [(Double, Double)]) -> Bool {
    let playerRight = px + playerW
    let lookAheadRight = playerRight + triggerDist

    for o in obstacles {
        guard o.kind == .spike || o.kind == .ceilSpike else { continue }
        let screenX = o.x - scrollX
        // Spike is ahead of player and within trigger distance
        guard screenX > playerRight && screenX < lookAheadRight else { continue }
        // Spike Y range overlaps with player Y range at ground level (would kill if walked into)
        let playerTop = floorY
        let playerBot = floorY + playerH
        if o.y < playerBot && (o.y + o.h) > playerTop {
            return true
        }
    }

    // Jump when the gap is just about to reach the player's left foot.
    // The jump arc covers ~205px, so we need scrollX to be ~(gap.start - 205)
    // when we jump. Trigger when gap start is 0–85px ahead of player left edge.
    for gap in gaps {
        let gapScreenStart = gap.0 - scrollX
        if gapScreenStart > px && gapScreenStart < px + 85 {
            return true
        }
    }

    return false
}

// MARK: - Simulation
struct Event { let frame: Int; let scrollX: Double; let msg: String }

func simulate() -> (completed: Bool, frames: Int, events: [Event], deathMsg: String?) {
    let (obstacles, gaps) = buildLevel()
    var px = 120.0, py = floorY, velY = 0.0
    var onGround = true
    var mode = GameMode.cube
    var scrollX = 0.0
    var holding = false
    var portalCooldown = 0
    var events: [Event] = []

    let maxFrames = Int(levelLen / scrollSpd) + 600

    for frame in 0..<maxFrames {
        // AI decisions
        if mode == .cube {
            if shouldJump(px: px, scrollX: scrollX,
                          obstacles: obstacles, gaps: gaps) && onGround {
                velY = jumpVel
                onGround = false
                events.append(Event(frame: frame, scrollX: scrollX,
                                    msg: "JUMP at worldX≈\(Int(scrollX+px))"))
            }
        } else {
            // Ship: stay in middle of tunnel gap
            let tunnelMid = (groundY - 110) + 40
            holding = (py + playerH/2) > tunnelMid
        }

        if portalCooldown > 0 { portalCooldown -= 1 }

        // Physics
        if mode == .ship {
            velY += gravity * 0.55 + (holding ? -1.1 : 0)
            velY = max(-4, min(9, velY))
        } else {
            velY += gravity
        }
        py += velY
        scrollX += scrollSpd

        // Ground
        let og = overGap(scrollX, px, gaps)
        if !og && py >= floorY { py = floorY; velY = 0; onGround = true }
        else if og { onGround = false }
        else { onGround = false }

        // Ceiling
        if py < -playerH {
            return (false, frame, events, "Hit ceiling at scrollX=\(Int(scrollX)) frame=\(frame)")
        }

        // Obstacle collision
        for o in obstacles {
            let ox = o.x - scrollX
            guard intersects(px, py, playerW, playerH, ox, o.y, o.w, o.h) else { continue }
            switch o.kind {
            case .spike, .ceilSpike:
                return (false, frame, events,
                        "Hit \(o.kind) at worldX=\(Int(o.x)) scrollX=\(Int(scrollX)) frame=\(frame)")
            case .portal:
                if portalCooldown <= 0 {
                    let prev = mode
                    mode = mode == .cube ? .ship : .cube
                    if mode == .ship { velY = min(velY, -2) }
                    portalCooldown = 20
                    events.append(Event(frame: frame, scrollX: scrollX,
                                        msg: "Portal: \(prev)→\(mode) at worldX≈\(Int(o.x))"))
                }
            case .jumpPad:
                if (py + playerH - velY) <= o.y + 6 && velY >= 0 {
                    py = o.y - playerH; velY = jumpVel * 1.35; onGround = false
                    events.append(Event(frame: frame, scrollX: scrollX,
                                        msg: "JUMP PAD at worldX≈\(Int(o.x))"))
                }
            case .platform:
                // One-way: only land on top, pass through from below/sides
                if (py + playerH - velY) <= o.y + 4 && velY >= 0 {
                    py = o.y - playerH; velY = 0; onGround = true
                }
            case .block:
                if (py + playerH - velY) <= o.y + 4 && velY >= 0 {
                    py = o.y - playerH; velY = 0; onGround = true
                } else {
                    return (false, frame, events,
                            "Hit block side at worldX=\(Int(o.x)) scrollX=\(Int(scrollX)) frame=\(frame)")
                }
            }
        }

        // Pit death
        if py > groundY + 80 {
            return (false, frame, events,
                    "Fell in pit at scrollX=\(Int(scrollX)) frame=\(frame)")
        }

        // Victory
        if scrollX >= levelLen {
            return (true, frame, events, nil)
        }
    }
    return (false, maxFrames, events, "Timed out")
}

// MARK: - Output
print("╔══════════════════════════════════════════════════╗")
print("║          SwiftGD Level Simulator                 ║")
print("╚══════════════════════════════════════════════════╝")
print("Screen: \(Int(screenW))×\(Int(screenH))  groundY=\(Int(groundY))")
print("")

let (completed, frames, events, deathMsg) = simulate()

for e in events {
    let pct = Int(e.scrollX / levelLen * 100)
    print("  f\(String(format: "%04d", e.frame))  \(pct)%  \(e.msg)")
}
print("")

if completed {
    print("✅  LEVEL COMPLETABLE")
    print("    Finished in \(frames) frames (\(String(format: "%.1f", Double(frames)/60))s at 60fps)")
    print("    \(events.filter { $0.msg.hasPrefix("JUMP") }.count) jumps required")
} else {
    print("❌  LEVEL NOT COMPLETABLE")
    print("    \(deathMsg ?? "unknown")")
}
