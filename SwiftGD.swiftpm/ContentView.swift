import SwiftUI

// MARK: - Constants
fileprivate let playerW:    CGFloat = 30
fileprivate let playerH:    CGFloat = 30
fileprivate let gravity:    CGFloat = 0.65
fileprivate let jumpVel:    CGFloat = -13.5
fileprivate let scrollSpd:  CGFloat = 5
fileprivate let levelLen:   CGFloat = 5200
fileprivate let groundH:    CGFloat = 50

// MARK: - Types

enum GDState { case menu, playing, dead, victory }

enum ObstacleKind { case spike, block, platform }

struct GDObstacle {
    var rect: CGRect
    var kind: ObstacleKind
    var colorIdx: Int
}

struct GDParticle {
    var pos: CGPoint
    var vel: CGPoint
    var life: CGFloat
    var maxLife: CGFloat
    var color: Color
    var size: CGFloat
}

// MARK: - Engine

class GDEngine: ObservableObject {
    @Published var state: GDState = .menu
    @Published var attempts: Int = 0

    // Player
    var playerX: CGFloat = 120
    var playerY: CGFloat = 0
    var velY: CGFloat = 0
    var onGround: Bool = false

    // World
    var scrollX: CGFloat = 0
    var progress: CGFloat = 0

    // Obstacles & particles
    var obstacles: [GDObstacle] = []
    var particles: [GDParticle] = []

    // Timers
    var deathFlash: CGFloat = 0
    var deathPause: CGFloat = 0
    var victoryTimer: CGFloat = 0
    var lastDate: Date = Date()

    // Set once from size
    var groundY: CGFloat = 400
    private var sizeSet = false

    // MARK: Setup

    func setup(size: CGSize) {
        guard !sizeSet else { return }
        sizeSet = true
        groundY = size.height - groundH
        playerY = groundY - playerH
        buildLevel()
    }

    func buildLevel() {
        obstacles = []
        let gY = groundY

        // Spike on ground: triangle bounding rect
        func spike(_ x: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x + 2, y: gY - 30, width: 26, height: 29),
                kind: .spike, colorIdx: 0))
        }

        // Solid block (wall / raised block)
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ ci: Int = 1) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: y, width: w, height: h),
                kind: .block, colorIdx: ci))
        }

        // Thin platform (land on top)
        func plat(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: y, width: w, height: 12),
                kind: .platform, colorIdx: 2))
        }

        // --- Section 1: Tutorial single spikes (x 350–1100) ---
        spike(350); spike(530); spike(710); spike(890); spike(1070)

        // --- Section 2: Double spikes (x 1300–2000) ---
        for i in 0..<4 {
            let bx = 1300 + CGFloat(i) * 190
            spike(bx); spike(bx + 32)
        }

        // --- Section 3: Step platforms (x 2200–3000) ---
        plat(2200, gY - 80, 160)
        spike(2420)
        plat(2500, gY - 130, 130)
        plat(2720, gY - 80, 130)
        spike(2900); spike(2932)

        // --- Section 4: Raised blocks + spikes (x 3200–4000) ---
        block(3200, gY - 60, 60, 60, 1)
        spike(3310); spike(3342)
        block(3500, gY - 90, 60, 90, 2)
        spike(3620); spike(3652); spike(3684)
        block(3800, gY - 60, 60, 60, 1)
        spike(3920)

        // --- Section 5: Final gauntlet (x 4200–5000) ---
        for i in 0..<5 {
            let bx = 4200 + CGFloat(i) * 140
            spike(bx)
            if i % 2 == 0 { spike(bx + 32) }
        }
        spike(4900); spike(4932); spike(4964)
    }

    // MARK: Input

    func tap() {
        switch state {
        case .menu:
            state = .playing
            attempts = 1
        case .playing:
            if onGround {
                velY = jumpVel
                onGround = false
            }
        case .dead:
            break  // auto-restart via deathPause
        case .victory:
            restartGame()
        }
    }

    // MARK: Game loop

    func tick(size: CGSize) {
        setup(size: size)

        let now = Date()
        let rawDt = now.timeIntervalSince(lastDate)
        lastDate = now
        let dt = CGFloat(min(rawDt, 0.05))

        switch state {
        case .menu: return
        case .dead:
            updateParticles(dt: dt)
            deathFlash = max(0, deathFlash - dt * 2.5)
            deathPause -= dt
            if deathPause <= 0 { restartGame() }
            return
        case .victory:
            victoryTimer += dt
            updateParticles(dt: dt)
            return
        case .playing: break
        }

        // --- Physics ---
        velY += gravity
        playerY += velY
        scrollX += scrollSpd
        progress = min(1, scrollX / levelLen)

        // Ground
        let floorY = groundY - playerH
        if playerY >= floorY {
            playerY = floorY
            velY = 0
            onGround = true
        } else {
            onGround = false
        }

        // Ceiling kill
        if playerY < -playerH {
            die(size: size); return
        }

        // --- Obstacle collision ---
        let pRect = CGRect(x: playerX, y: playerY, width: playerW, height: playerH)

        for obs in obstacles {
            let sx = obs.rect.minX - scrollX
            let sRect = CGRect(x: sx, y: obs.rect.minY,
                               width: obs.rect.width, height: obs.rect.height)

            guard pRect.intersects(sRect) else { continue }

            switch obs.kind {
            case .spike:
                die(size: size); return

            case .block, .platform:
                // Land on top if coming down
                let prevBottom = playerY + playerH - velY
                if prevBottom <= sRect.minY + 4 && velY >= 0 {
                    playerY = sRect.minY - playerH
                    velY = 0
                    onGround = true
                } else {
                    // Side / bottom collision = death
                    die(size: size); return
                }
            }
        }

        // Fall off world
        if playerY > groundY + 80 {
            die(size: size); return
        }

        // Victory
        if scrollX >= levelLen {
            state = .victory
            victoryTimer = 0
            spawnParticles(at: CGPoint(x: playerX + playerW/2, y: playerY + playerH/2),
                           count: 60, speed: 3...10, life: 2.5,
                           colors: [.yellow, .cyan, Color(red:1,green:0.5,blue:0), .white,
                                    Color(red:0.8,green:0,blue:1)])
        }

        updateParticles(dt: dt)
    }

    func die(size: CGSize) {
        state = .dead
        deathFlash = 1.0
        deathPause = 1.2
        attempts += 1
        spawnParticles(at: CGPoint(x: playerX + playerW/2, y: playerY + playerH/2),
                       count: 30, speed: 2...9, life: 1.0,
                       colors: [.cyan, .green, Color(red:0,green:1,blue:0.5), .yellow, .white])
    }

    func restartGame() {
        playerY = groundY - playerH
        velY = 0
        scrollX = 0
        progress = 0
        onGround = false
        particles = []
        deathFlash = 0
        state = .playing
    }

    // MARK: Particles

    func spawnParticles(at pos: CGPoint, count: Int, speed: ClosedRange<CGFloat>,
                        life: CGFloat, colors: [Color]) {
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0..<CGFloat.pi * 2)
            let spd   = CGFloat.random(in: speed)
            particles.append(GDParticle(
                pos: pos,
                vel: CGPoint(x: cos(angle) * spd, y: sin(angle) * spd),
                life: life, maxLife: life,
                color: colors.randomElement()!,
                size: CGFloat.random(in: 3...8)))
        }
    }

    func updateParticles(dt: CGFloat) {
        for i in particles.indices {
            particles[i].pos.x += particles[i].vel.x
            particles[i].pos.y += particles[i].vel.y
            particles[i].vel.y += 0.15
            particles[i].life  -= dt
        }
        particles.removeAll { $0.life <= 0 }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var engine = GDEngine()

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    renderFrame(ctx: ctx, size: size, engine: engine)
                }
                .onChange(of: tl.date) { _ in
                    engine.tick(size: geo.size)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { engine.tap() }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

// MARK: - Renderer

fileprivate func renderFrame(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    // Background
    drawBackground(ctx: ctx, size: size)

    // Ground
    let gRect = CGRect(x: 0, y: engine.groundY, width: size.width, height: groundH)
    ctx.fill(Path(gRect), with: .color(Color(red: 0.07, green: 0.35, blue: 0.45)))
    // Ground top edge glow line
    let edgePath = Path { p in
        p.move(to: CGPoint(x: 0, y: engine.groundY))
        p.addLine(to: CGPoint(x: size.width, y: engine.groundY))
    }
    ctx.stroke(edgePath, with: .color(.cyan.opacity(0.8)), lineWidth: 2)

    // Obstacles
    drawObstacles(ctx: ctx, size: size, engine: engine)

    // Player (only when alive/playing)
    if engine.state == .playing || engine.state == .menu {
        drawPlayer(ctx: ctx, engine: engine)
    }

    // Particles
    drawParticles(ctx: ctx, engine: engine)

    // Death flash
    if engine.deathFlash > 0 {
        ctx.drawLayer { c in
            c.opacity = Double(engine.deathFlash * 0.6)
            c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
        }
    }

    // UI
    drawUI(ctx: ctx, size: size, engine: engine)
}

fileprivate func drawBackground(ctx: GraphicsContext, size: CGSize) {
    let bg = Path(CGRect(origin: .zero, size: size))
    ctx.fill(bg, with: .color(Color(red: 0.04, green: 0.04, blue: 0.12)))
}

fileprivate let spikeColors: [Color] = [
    Color(red: 0, green: 1, blue: 0.9),
    Color(red: 1, green: 0.3, blue: 0.6),
    Color(red: 1, green: 0.8, blue: 0),
]
fileprivate let blockColors: [Color] = [
    Color(red: 0.2, green: 0.6, blue: 1),
    Color(red: 0.5, green: 0.1, blue: 0.8),
    Color(red: 0,   green: 0.8, blue: 0.5),
]

fileprivate func drawObstacles(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    for obs in engine.obstacles {
        let sx = obs.rect.minX - engine.scrollX
        guard sx > -obs.rect.width && sx < size.width else { continue }

        let sr = CGRect(x: sx, y: obs.rect.minY, width: obs.rect.width, height: obs.rect.height)

        switch obs.kind {
        case .spike:
            // Draw triangle
            let triPath = Path { p in
                p.move(to: CGPoint(x: sr.minX, y: sr.maxY))
                p.addLine(to: CGPoint(x: sr.midX, y: sr.minY))
                p.addLine(to: CGPoint(x: sr.maxX, y: sr.maxY))
                p.closeSubpath()
            }
            let col = spikeColors[obs.colorIdx % spikeColors.count]
            ctx.fill(triPath, with: .color(col))
            ctx.stroke(triPath, with: .color(.white.opacity(0.4)), lineWidth: 1)

        case .block:
            let col = blockColors[obs.colorIdx % blockColors.count]
            ctx.fill(Path(sr), with: .color(col))
            ctx.stroke(Path(sr), with: .color(.white.opacity(0.3)), lineWidth: 1)

        case .platform:
            ctx.fill(Path(sr), with: .color(Color(red: 0.1, green: 0.7, blue: 0.4)))
            ctx.stroke(Path(sr), with: .color(.white.opacity(0.4)), lineWidth: 1)
        }
    }
}

fileprivate func drawPlayer(ctx: GraphicsContext, engine: GDEngine) {
    let r = CGRect(x: engine.playerX, y: engine.playerY, width: playerW, height: playerH)

    // Cube fill
    ctx.fill(Path(r), with: .color(Color(red: 0.1, green: 0.9, blue: 0.4)))

    // Inner detail lines
    let inset: CGFloat = 6
    let innerPath = Path { p in
        let ir = r.insetBy(dx: inset, dy: inset)
        p.addRect(ir)
    }
    ctx.stroke(innerPath, with: .color(.white.opacity(0.5)), lineWidth: 1.5)

    // Diagonal cross detail
    let diagPath = Path { p in
        p.move(to: CGPoint(x: r.minX + inset, y: r.minY + inset))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY - inset))
    }
    ctx.stroke(diagPath, with: .color(.white.opacity(0.3)), lineWidth: 1)

    // Outline
    ctx.stroke(Path(r), with: .color(.white.opacity(0.8)), lineWidth: 1.5)
}

fileprivate func drawParticles(ctx: GraphicsContext, engine: GDEngine) {
    for p in engine.particles {
        let alpha = p.life / p.maxLife
        ctx.drawLayer { c in
            c.opacity = Double(alpha)
            let pr = CGRect(x: p.pos.x - p.size/2, y: p.pos.y - p.size/2,
                            width: p.size, height: p.size)
            c.fill(Path(ellipseIn: pr), with: .color(p.color))
        }
    }
}

fileprivate func drawUI(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    switch engine.state {
    case .menu:
        drawCenteredText(ctx: ctx, size: size,
                         line1: "GEOMETRY DASH", line2: "Tap to Start")
    case .dead:
        drawCenteredText(ctx: ctx, size: size,
                         line1: "CRASHED", line2: "Restarting...")
    case .victory:
        drawCenteredText(ctx: ctx, size: size,
                         line1: "LEVEL COMPLETE!", line2: "Tap to Play Again")
    case .playing:
        drawHUD(ctx: ctx, size: size, engine: engine)
    }
}

fileprivate func drawHUD(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    // Progress bar background
    let barW = size.width - 40
    let barH: CGFloat = 6
    let barX: CGFloat = 20
    let barY: CGFloat = 14
    ctx.fill(Path(CGRect(x: barX, y: barY, width: barW, height: barH)),
             with: .color(.white.opacity(0.15)))

    // Progress fill
    let fillW = barW * engine.progress
    if fillW > 0 {
        ctx.fill(Path(CGRect(x: barX, y: barY, width: fillW, height: barH)),
                 with: .color(.cyan))
    }

    // Attempt counter
    let attText = Text("Attempt \(engine.attempts)")
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundColor(.white.opacity(0.7))
    ctx.draw(attText, at: CGPoint(x: 20, y: 32), anchor: .topLeading)

    // Percent
    let pct = Int(engine.progress * 100)
    let pctText = Text("\(pct)%")
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundColor(.cyan.opacity(0.9))
    ctx.draw(pctText, at: CGPoint(x: size.width - 20, y: 32), anchor: .topTrailing)
}

fileprivate func drawCenteredText(ctx: GraphicsContext, size: CGSize,
                                   line1: String, line2: String) {
    ctx.drawLayer { c in
        c.opacity = 0.6
        c.fill(Path(CGRect(x: size.width/2 - 160, y: size.height/2 - 50,
                           width: 320, height: 90)),
               with: .color(.black))
    }
    let t1 = Text(line1)
        .font(.system(size: 26, weight: .black, design: .monospaced))
        .foregroundColor(.cyan)
    ctx.draw(t1, at: CGPoint(x: size.width/2, y: size.height/2 - 20), anchor: .center)

    let t2 = Text(line2)
        .font(.system(size: 15, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.8))
    ctx.draw(t2, at: CGPoint(x: size.width/2, y: size.height/2 + 14), anchor: .center)
}
