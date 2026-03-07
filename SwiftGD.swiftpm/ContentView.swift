import SwiftUI

// MARK: - Constants
fileprivate let playerW:    CGFloat = 30
fileprivate let playerH:    CGFloat = 30
fileprivate let gravity:    CGFloat = 0.65
fileprivate let jumpVel:    CGFloat = -13.5
fileprivate let scrollSpd:  CGFloat = 5
fileprivate let levelLen:   CGFloat = 6500
fileprivate let groundH:    CGFloat = 50

// MARK: - Types

enum GDState  { case menu, playing, dead, victory }
enum GameMode { case cube, ship }

enum ObstacleKind { case spike, block, platform, ceilSpike, jumpPad, portal }

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

// MARK: - Star (background parallax)

struct GDStar {
    var worldX: CGFloat   // position in a virtual world wider than screen
    var y: CGFloat
    var radius: CGFloat
    var brightness: CGFloat
    var parallax: CGFloat  // 0..1, lower = further back = slower
}

// MARK: - Engine

class GDEngine: ObservableObject {
    @Published var state: GDState = .menu
    @Published var attempts: Int = 0

    // Player
    var playerX:   CGFloat = 120
    var playerY:   CGFloat = 0
    var velY:      CGFloat = 0
    var onGround:  Bool = false
    var cubeAngle: CGFloat = 0      // degrees, updated while scrolling
    var mode:      GameMode = .cube
    var holding:   Bool = false     // tap held (ship thrust)

    // World
    var scrollX: CGFloat = 0
    var progress: CGFloat = 0

    // Obstacles & particles
    var obstacles: [GDObstacle] = []
    var particles: [GDParticle] = []
    var stars: [GDStar] = []

    // Floor gaps: world-x ranges where floor is absent
    var floorGaps: [(start: CGFloat, end: CGFloat)] = []

    // Screen shake
    var shakeTimer: CGFloat = 0
    var shakeX: CGFloat = 0
    var shakeY: CGFloat = 0

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
        buildStars(size: size)
    }

    func buildStars(size: CGSize) {
        stars = []
        let worldW = size.width * 4  // tile across 4 screen-widths
        let skyH   = size.height * 0.75
        for i in 0..<90 {
            let seed = CGFloat(i * 6791 + 3)
            let wx   = seed.truncatingRemainder(dividingBy: worldW)
            let y    = (seed * 1.7).truncatingRemainder(dividingBy: skyH) + 4
            let r    = CGFloat.random(in: 0.8...2.4)
            let br   = CGFloat.random(in: 0.3...1.0)
            let par  = CGFloat.random(in: 0.05...0.25)
            stars.append(GDStar(worldX: wx, y: y, radius: r, brightness: br, parallax: par))
        }
    }

    func buildLevel() {
        obstacles = []
        floorGaps = []
        let gY = groundY

        // Ground spike (cyan, triangle)
        func spike(_ x: CGFloat, _ ci: Int = 0) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x + 2, y: gY - 30, width: 26, height: 29),
                kind: .spike, colorIdx: ci))
        }
        // Ceiling spike (inverted, hangs from top + some offset)
        func cSpike(_ x: CGFloat, _ y: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x + 2, y: y, width: 26, height: 29),
                kind: .ceilSpike, colorIdx: 1))
        }
        // Solid block
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ ci: Int = 1) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: y, width: w, height: h),
                kind: .block, colorIdx: ci))
        }
        // Thin platform
        func plat(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: y, width: w, height: 12),
                kind: .platform, colorIdx: 2))
        }
        // Jump pad (on ground)
        func pad(_ x: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: gY - 18, width: 36, height: 18),
                kind: .jumpPad, colorIdx: 0))
        }
        // Floor gap
        func pit(_ start: CGFloat, _ end: CGFloat) {
            floorGaps.append((start: start, end: end))
        }
        // Mode-change portal (tall rectangle, pass-through)
        func portal(_ x: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: 20, width: 24, height: gY - 20),
                kind: .portal, colorIdx: 0))
        }
        // Tunnel wall for ship section (ceiling or floor block the passage)
        func twall(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
            obstacles.append(GDObstacle(
                rect: CGRect(x: x, y: y, width: w, height: h),
                kind: .block, colorIdx: 2))
        }

        // ── Section 1: Tutorial — gentle single spikes ──────────── x 300–1150
        spike(300); spike(480); spike(660); spike(840); spike(1020)

        // ── Section 2: Double spikes + a jump pad ───────────────── x 1300–2100
        for i in 0..<4 {
            let bx = 1300 + CGFloat(i) * 200
            spike(bx); spike(bx + 32)
        }
        pad(2000)   // teach the jump pad mechanic

        // ── Section 3: Platforms + ceiling threat ───────────────── x 2300–3100
        plat(2300, gY - 80,  150)
        cSpike(2370, 30)
        spike(2510)
        plat(2600, gY - 130, 120)
        cSpike(2640, 20)
        plat(2820, gY - 80,  120)
        spike(2980); spike(3012)

        // ── Ship section: portal → narrow tunnel → return portal ─── x 3100–3300
        portal(3100)  // cube → ship
        // Tunnel: ceiling blocks force player to fly at mid-height
        let tunnelY  = gY - 110   // ceiling of tunnel
        let gapH: CGFloat = 80    // fly-through gap
        twall(3140, 0,       180, tunnelY)            // upper wall (ceiling)
        twall(3140, tunnelY + gapH, 180, gY - (tunnelY + gapH))  // lower wall (floor plug)
        twall(3240, 0,       180, tunnelY - 20)       // narrower 2nd tunnel ceiling
        twall(3240, tunnelY + gapH - 20, 180, 60)    // lower wall
        portal(3290)  // ship → cube

        // ── Section 4: Death pits ────────────────────────────────── x 3500–4300
        // Floor gaps — player must jump over them
        pit(3550, 3670)         // first pit
        spike(3710)             // spike right after pit edge
        pit(3900, 4020)         // second pit, wider
        pad(4030)               // jump pad to clear next section
        pit(4250, 4330)         // tight pit

        // ── Section 5: Block maze + ceiling spikes ───────────────── x 4500–5500
        block(4500, gY - 60,  60,  60, 1)
        spike(4610); spike(4642)
        block(4750, gY - 90,  60,  90, 2)
        cSpike(4770, 15)
        spike(4860); spike(4892); spike(4924)
        block(5000, gY - 60,  60,  60, 1)
        spike(5110)
        plat(5250, gY - 110, 120)
        cSpike(5280, 25)
        spike(5400); spike(5432)

        // ── Section 6: Final gauntlet ────────────────────────────── x 5700–6400
        for i in 0..<6 {
            let bx = 5700 + CGFloat(i) * 130
            spike(bx, i % 3)
            if i % 2 == 0 { spike(bx + 32, (i+1) % 3) }
        }
        pit(6300, 6400)
        spike(6430); spike(6462); spike(6494)
        pad(6380)
    }

    // MARK: Input

    func tap() {
        switch state {
        case .menu:
            state = .playing
            attempts = 1
        case .playing:
            if mode == .cube {
                if onGround {
                    velY = jumpVel
                    onGround = false
                }
            }
            // Ship thrust is handled via holding flag
        case .dead:
            break  // auto-restart via deathPause
        case .victory:
            restartGame()
        }
    }

    func touchDown() {
        if state == .playing { holding = true }
    }

    func touchUp() {
        holding = false
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

        // Screen shake decay
        if shakeTimer > 0 {
            shakeTimer -= dt
            let t = shakeTimer * 45
            shakeX = sin(t) * 7 * (shakeTimer / 0.35)
            shakeY = cos(t * 1.3) * 5 * (shakeTimer / 0.35)
        } else {
            shakeX = 0; shakeY = 0
        }

        // --- Physics ---
        if mode == .ship {
            // Ship: hold = thrust up, release = fall
            let thrust: CGFloat = holding ? -1.1 : 0.0
            velY += gravity * 0.55 + thrust
            velY = max(-9, min(9, velY))  // clamp ship speed
        } else {
            velY += gravity
        }
        playerY += velY
        scrollX += scrollSpd
        cubeAngle = scrollX * 0.09  // slow rotation as level scrolls
        progress = min(1, scrollX / levelLen)

        // Ground — only if player is NOT over a floor gap
        let floorY = groundY - playerH
        let pLeftWorld  = scrollX + playerX
        let pRightWorld = scrollX + playerX + playerW
        let overGap = floorGaps.contains { pRightWorld > $0.start && pLeftWorld < $0.end }
        if !overGap && playerY >= floorY {
            playerY = floorY
            velY = 0
            onGround = true
        } else if overGap {
            onGround = false
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
            case .spike, .ceilSpike:
                die(size: size); return

            case .portal:
                // Switch modes
                if mode == .cube {
                    mode = .ship
                    velY = min(velY, -2)  // slight upward nudge on entry
                } else {
                    mode = .cube
                }
                continue  // don't die or land, just pass through

            case .jumpPad:
                // Bounce — only trigger if coming down onto it
                let prevBottom = playerY + playerH - velY
                if prevBottom <= sRect.minY + 6 && velY >= 0 {
                    playerY = sRect.minY - playerH
                    velY = jumpVel * 1.35   // ~18% stronger than normal jump
                    onGround = false
                    spawnParticles(at: CGPoint(x: playerX + playerW/2, y: playerY + playerH),
                                   count: 10, speed: 2...5, life: 0.5,
                                   colors: [.yellow, Color(red:1,green:0.8,blue:0), .white])
                }

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
        shakeTimer = 0.35
        attempts += 1
        spawnParticles(at: CGPoint(x: playerX + playerW/2, y: playerY + playerH/2),
                       count: 40, speed: 2...11, life: 1.0,
                       colors: [.cyan, .green, Color(red:0,green:1,blue:0.5), .yellow, .white])
    }

    func restartGame() {
        playerY = groundY - playerH
        velY = 0
        scrollX = 0
        progress = 0
        onGround = false
        mode = .cube
        holding = false
        particles = []
        deathFlash = 0
        shakeTimer = 0
        shakeX = 0; shakeY = 0
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
            // Tap = cube jump; hold = ship thrust
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        engine.touchDown()
                        engine.tap()  // also triggers cube jump on first touch
                    }
                    .onEnded { _ in engine.touchUp() }
            )
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

// MARK: - Renderer

fileprivate func renderFrame(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    // Synthwave background
    drawBackground(ctx: ctx, size: size)
    drawStars(ctx: ctx, size: size, engine: engine)

    // World content (apply screen shake offset via drawLayer)
    ctx.drawLayer { wc in
        wc.concatenate(CGAffineTransform(translationX: engine.shakeX, y: engine.shakeY))
        drawGround(ctx: wc, size: size, engine: engine)
        drawObstacles(ctx: wc, size: size, engine: engine)
        if engine.state == .playing || engine.state == .menu {
            if engine.mode == .ship {
                drawShip(ctx: wc, engine: engine)
            } else {
                drawPlayer(ctx: wc, engine: engine)
            }
        }
        drawParticles(ctx: wc, engine: engine)
    }

    // Death flash (no shake — full screen)
    if engine.deathFlash > 0 {
        ctx.drawLayer { c in
            c.opacity = Double(engine.deathFlash * 0.55)
            c.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
        }
    }

    // UI always on top, no shake
    drawUI(ctx: ctx, size: size, engine: engine)
}

fileprivate func drawBackground(ctx: GraphicsContext, size: CGSize) {
    // Deep synthwave gradient: top dark-navy → bottom deep-purple
    let stops: [Gradient.Stop] = [
        .init(color: Color(red: 0.02, green: 0.02, blue: 0.10), location: 0),
        .init(color: Color(red: 0.06, green: 0.02, blue: 0.16), location: 0.55),
        .init(color: Color(red: 0.10, green: 0.03, blue: 0.22), location: 1),
    ]
    ctx.fill(Path(CGRect(origin: .zero, size: size)),
             with: .linearGradient(Gradient(stops: stops),
                                   startPoint: CGPoint(x: size.width/2, y: 0),
                                   endPoint: CGPoint(x: size.width/2, y: size.height)))

    // Horizon glow band
    let hY = size.height * 0.62
    ctx.drawLayer { c in
        c.opacity = 0.18
        let glowRect = CGRect(x: 0, y: hY - 40, width: size.width, height: 80)
        c.fill(Path(glowRect), with: .color(Color(red: 0, green: 0.8, blue: 1)))
    }
}

fileprivate func drawStars(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    let worldW = size.width * 4
    for star in engine.stars {
        // Parallax: slow stars move less than world scroll
        let screenX = star.worldX - engine.scrollX * star.parallax
        // Wrap to screen
        let wrapped = screenX.truncatingRemainder(dividingBy: worldW)
        let fx = wrapped < 0 ? wrapped + worldW : wrapped
        guard fx >= 0 && fx < size.width else { continue }

        let pr = CGRect(x: fx - star.radius, y: star.y - star.radius,
                        width: star.radius * 2, height: star.radius * 2)
        ctx.drawLayer { c in
            c.opacity = Double(star.brightness)
            c.fill(Path(ellipseIn: pr), with: .color(.white))
        }
    }
}

fileprivate func drawGround(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    let gY   = engine.groundY
    let gCol = Color(red: 0.03, green: 0.18, blue: 0.25)
    let edgeCol = Color(red: 0, green: 1, blue: 0.9)

    // Build sorted list of gap screen-x ranges
    let gaps: [(CGFloat, CGFloat)] = engine.floorGaps
        .map { (($0.start - engine.scrollX), ($0.end - engine.scrollX)) }
        .filter { $0.1 > 0 && $0.0 < size.width }
        .sorted { $0.0 < $1.0 }

    // Draw ground segments between gaps
    var cursor: CGFloat = 0
    for gap in gaps {
        let segEnd = max(cursor, min(gap.0, size.width))
        if segEnd > cursor {
            let segRect = CGRect(x: cursor, y: gY, width: segEnd - cursor, height: groundH)
            ctx.fill(Path(segRect), with: .color(gCol))
            // edge glow on that segment
            let edge = Path { p in
                p.move(to: CGPoint(x: cursor, y: gY))
                p.addLine(to: CGPoint(x: segEnd, y: gY))
            }
            ctx.stroke(edge, with: .color(edgeCol), lineWidth: 2.5)
        }
        cursor = max(cursor, gap.1)
    }
    // Final segment after last gap
    if cursor < size.width {
        let segRect = CGRect(x: cursor, y: gY, width: size.width - cursor, height: groundH)
        ctx.fill(Path(segRect), with: .color(gCol))
        let edge = Path { p in
            p.move(to: CGPoint(x: cursor, y: gY))
            p.addLine(to: CGPoint(x: size.width, y: gY))
        }
        ctx.stroke(edge, with: .color(edgeCol), lineWidth: 2.5)
    }

    // Pit danger indicators: glowing red at pit edges
    for gap in gaps {
        let lx = max(gap.0 - 3, 0)
        let rx = min(gap.1,     size.width - 3)
        ctx.drawLayer { c in
            c.opacity = 0.7
            c.fill(Path(CGRect(x: lx, y: gY, width: 6, height: groundH / 2)),
                   with: .color(Color(red: 1, green: 0.1, blue: 0.2)))
            c.fill(Path(CGRect(x: rx, y: gY, width: 6, height: groundH / 2)),
                   with: .color(Color(red: 1, green: 0.1, blue: 0.2)))
        }
    }

    // Grid lines on all ground segments
    let gridSpacing: CGFloat = 40
    let offset = engine.scrollX.truncatingRemainder(dividingBy: gridSpacing)
    var gx = -offset
    while gx < size.width {
        // Only draw if not in a gap
        let inGap = gaps.contains { gx >= $0.0 && gx <= $0.1 }
        if !inGap {
            let linePath = Path { p in
                p.move(to: CGPoint(x: gx, y: gY))
                p.addLine(to: CGPoint(x: gx, y: gY + groundH))
            }
            ctx.drawLayer { c in
                c.opacity = 0.22
                c.stroke(linePath, with: .color(.cyan), lineWidth: 1)
            }
        }
        gx += gridSpacing
    }
}

fileprivate let spikeColors: [Color] = [
    Color(red: 0,   green: 1,   blue: 0.9),   // cyan
    Color(red: 1,   green: 0.2, blue: 0.5),   // hot pink
    Color(red: 1,   green: 0.75,blue: 0),      // amber
]
fileprivate let blockColors: [Color] = [
    Color(red: 0.15,green: 0.5, blue: 1),      // electric blue
    Color(red: 0.55,green: 0.1, blue: 0.9),    // deep violet
    Color(red: 0,   green: 0.75,blue: 0.45),   // teal
]

fileprivate func drawObstacles(ctx: GraphicsContext, size: CGSize, engine: GDEngine) {
    for obs in engine.obstacles {
        let sx = obs.rect.minX - engine.scrollX
        guard sx > -obs.rect.width - 20 && sx < size.width + 20 else { continue }

        let sr = CGRect(x: sx, y: obs.rect.minY, width: obs.rect.width, height: obs.rect.height)

        switch obs.kind {
        case .spike:
            let col = spikeColors[obs.colorIdx % spikeColors.count]
            let triPath = Path { p in
                p.move(to: CGPoint(x: sr.minX, y: sr.maxY))
                p.addLine(to: CGPoint(x: sr.midX, y: sr.minY))
                p.addLine(to: CGPoint(x: sr.maxX, y: sr.maxY))
                p.closeSubpath()
            }
            // Outer glow
            ctx.drawLayer { c in
                c.opacity = 0.35
                let bigTri = Path { p in
                    p.move(to: CGPoint(x: sr.minX - 3, y: sr.maxY + 2))
                    p.addLine(to: CGPoint(x: sr.midX,  y: sr.minY - 5))
                    p.addLine(to: CGPoint(x: sr.maxX + 3, y: sr.maxY + 2))
                    p.closeSubpath()
                }
                c.fill(bigTri, with: .color(col))
            }
            ctx.fill(triPath, with: .color(col))
            // Bright inner highlight edge
            ctx.stroke(triPath, with: .color(.white.opacity(0.55)), lineWidth: 1)

        case .block:
            let col = blockColors[obs.colorIdx % blockColors.count]
            // Glow halo
            ctx.drawLayer { c in
                c.opacity = 0.3
                c.fill(Path(sr.insetBy(dx: -4, dy: -4)), with: .color(col))
            }
            ctx.fill(Path(sr), with: .color(col))
            // Diagonal inner highlight
            let diagPath = Path { p in
                p.move(to: CGPoint(x: sr.minX + 6, y: sr.minY + 6))
                p.addLine(to: CGPoint(x: sr.maxX - 6, y: sr.minY + 6))
                p.addLine(to: CGPoint(x: sr.maxX - 6, y: sr.maxY - 6))
            }
            ctx.stroke(diagPath, with: .color(.white.opacity(0.25)), lineWidth: 1)
            ctx.stroke(Path(sr), with: .color(.white.opacity(0.5)), lineWidth: 1.5)

        case .platform:
            let platCol = Color(red: 0.05, green: 0.65, blue: 0.45)
            ctx.drawLayer { c in
                c.opacity = 0.3
                c.fill(Path(sr.insetBy(dx: -3, dy: -3)), with: .color(platCol))
            }
            ctx.fill(Path(sr), with: .color(platCol))
            ctx.stroke(Path(sr), with: .color(.white.opacity(0.5)), lineWidth: 1.5)

        case .ceilSpike:
            // Inverted triangle (tip points down)
            let col = Color(red: 1, green: 0.2, blue: 0.5)
            let triPath = Path { p in
                p.move(to: CGPoint(x: sr.minX,  y: sr.minY))  // top-left
                p.addLine(to: CGPoint(x: sr.maxX,  y: sr.minY))  // top-right
                p.addLine(to: CGPoint(x: sr.midX,  y: sr.maxY))  // bottom tip
                p.closeSubpath()
            }
            ctx.drawLayer { c in
                c.opacity = 0.35
                let bigTri = Path { p in
                    p.move(to: CGPoint(x: sr.minX - 3, y: sr.minY - 2))
                    p.addLine(to: CGPoint(x: sr.maxX + 3, y: sr.minY - 2))
                    p.addLine(to: CGPoint(x: sr.midX,     y: sr.maxY + 5))
                    p.closeSubpath()
                }
                c.fill(bigTri, with: .color(col))
            }
            ctx.fill(triPath, with: .color(col))
            ctx.stroke(triPath, with: .color(.white.opacity(0.55)), lineWidth: 1)

        case .portal:
            // Tall vertical ring — glowing purple/orange depending on destination
            let portalCol = Color(red: 0.7, green: 0.1, blue: 1)   // purple = ship portal
            ctx.drawLayer { c in
                c.opacity = 0.25
                c.fill(Path(sr), with: .color(portalCol))
            }
            ctx.stroke(Path(sr), with: .color(portalCol), lineWidth: 3)
            // Chevron arrows inside portal hinting direction
            for i in 0..<3 {
                let ay = sr.minY + sr.height * (0.3 + CGFloat(i) * 0.2)
                let arrPath = Path { p in
                    p.move(to: CGPoint(x: sr.minX + 4,  y: ay))
                    p.addLine(to: CGPoint(x: sr.midX,    y: ay - 8))
                    p.addLine(to: CGPoint(x: sr.maxX - 4, y: ay))
                }
                ctx.drawLayer { c in
                    c.opacity = 0.8
                    c.stroke(arrPath, with: .color(.white), lineWidth: 1.5)
                }
            }

        case .jumpPad:
            // Yellow/green chevron shape on ground
            let padCol = Color(red: 1, green: 0.85, blue: 0)
            let chevron = Path { p in
                p.move(to: CGPoint(x: sr.minX,       y: sr.maxY))
                p.addLine(to: CGPoint(x: sr.midX,     y: sr.minY))
                p.addLine(to: CGPoint(x: sr.maxX,     y: sr.maxY))
                p.addLine(to: CGPoint(x: sr.maxX - 8, y: sr.maxY))
                p.addLine(to: CGPoint(x: sr.midX,     y: sr.minY + 8))
                p.addLine(to: CGPoint(x: sr.minX + 8, y: sr.maxY))
                p.closeSubpath()
            }
            ctx.drawLayer { c in
                c.opacity = 0.45
                c.fill(Path(sr.insetBy(dx: -5, dy: -5)), with: .color(padCol))
            }
            ctx.fill(chevron, with: .color(padCol))
            ctx.stroke(chevron, with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
    }
}

fileprivate func drawPlayer(ctx: GraphicsContext, engine: GDEngine) {
    let cx = engine.playerX + playerW / 2
    let cy = engine.playerY + playerH / 2
    let angleRad = engine.cubeAngle * CGFloat.pi / 180

    // Draw cube in a rotated layer
    ctx.drawLayer { c in
        // Rotate around cube centre
        c.concatenate(CGAffineTransform(translationX: cx, y: cy))
        c.concatenate(CGAffineTransform(rotationAngle: angleRad))
        c.concatenate(CGAffineTransform(translationX: -cx, y: -cy))

        let r = CGRect(x: engine.playerX, y: engine.playerY, width: playerW, height: playerH)

        // Outer glow (larger box, low opacity)
        c.drawLayer { g in
            g.opacity = 0.4
            g.fill(Path(r.insetBy(dx: -6, dy: -6)),
                   with: .color(Color(red: 0.1, green: 1, blue: 0.5)))
        }

        // Cube body — lime-green gradient feel via two overlapping fills
        c.fill(Path(r), with: .color(Color(red: 0.05, green: 0.75, blue: 0.35)))
        c.drawLayer { g in
            g.opacity = 0.55
            let topHalf = CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.5)
            g.fill(Path(topHalf), with: .color(Color(red: 0.2, green: 1, blue: 0.55)))
        }

        // Inner square detail
        let inset: CGFloat = 6
        let ir = r.insetBy(dx: inset, dy: inset)
        c.stroke(Path(ir), with: .color(.white.opacity(0.55)), lineWidth: 1.5)

        // Diagonal line detail
        let diagPath = Path { p in
            p.move(to: CGPoint(x: r.minX + inset, y: r.minY + inset))
            p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY - inset))
        }
        c.stroke(diagPath, with: .color(.white.opacity(0.3)), lineWidth: 1)

        // Bright white outline
        c.stroke(Path(r), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
    }
}

fileprivate func drawShip(ctx: GraphicsContext, engine: GDEngine) {
    let cx = engine.playerX + playerW / 2
    let cy = engine.playerY + playerH / 2
    // Ship tilts slightly based on vertical velocity
    let tilt = max(-25, min(25, engine.velY * 2.0))
    let angleRad = tilt * CGFloat.pi / 180

    ctx.drawLayer { c in
        c.concatenate(CGAffineTransform(translationX: cx, y: cy))
        c.concatenate(CGAffineTransform(rotationAngle: angleRad))
        c.concatenate(CGAffineTransform(translationX: -cx, y: -cy))

        let r = CGRect(x: engine.playerX, y: engine.playerY, width: playerW, height: playerH)
        // Ship body: horizontal diamond / arrow
        let shipPath = Path { p in
            p.move(to: CGPoint(x: r.maxX,      y: r.midY))        // nose
            p.addLine(to: CGPoint(x: r.minX + 6, y: r.minY + 6))  // top-left
            p.addLine(to: CGPoint(x: r.minX,     y: r.midY))      // tail
            p.addLine(to: CGPoint(x: r.minX + 6, y: r.maxY - 6))  // bottom-left
            p.closeSubpath()
        }
        let shipCol = Color(red: 0.2, green: 0.8, blue: 1)
        // Outer glow
        c.drawLayer { g in
            g.opacity = 0.4
            g.fill(Path(r.insetBy(dx: -6, dy: -6)), with: .color(shipCol))
        }
        c.fill(shipPath, with: .color(shipCol))
        // Highlight
        c.drawLayer { g in
            g.opacity = 0.5
            let hiPath = Path { p in
                p.move(to: CGPoint(x: r.maxX,       y: r.midY))
                p.addLine(to: CGPoint(x: r.minX + 6, y: r.minY + 6))
                p.addLine(to: CGPoint(x: r.midX,     y: r.midY))
            }
            g.stroke(hiPath, with: .color(.white), lineWidth: 2)
        }
        c.stroke(shipPath, with: .color(.white.opacity(0.85)), lineWidth: 1.5)

        // Thrust flame when holding
        if engine.holding {
            c.drawLayer { g in
                g.opacity = CGFloat.random(in: 0.6...1.0)
                let flame = Path { p in
                    p.move(to: CGPoint(x: r.minX,     y: r.midY - 5))
                    p.addLine(to: CGPoint(x: r.minX - CGFloat.random(in: 10...18), y: r.midY))
                    p.addLine(to: CGPoint(x: r.minX,     y: r.midY + 5))
                    p.closeSubpath()
                }
                g.fill(flame, with: .color(Color(red: 1, green: 0.6, blue: 0)))
            }
        }
    }
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

    // Mode indicator
    let modeLabel = engine.mode == .ship ? "✈ SHIP" : "▣ CUBE"
    let modeColor: Color = engine.mode == .ship ?
        Color(red: 0.2, green: 0.8, blue: 1) : Color(red: 0.1, green: 1, blue: 0.5)
    let modeText = Text(modeLabel)
        .font(.system(size: 12, weight: .bold, design: .monospaced))
        .foregroundColor(modeColor)
    ctx.draw(modeText, at: CGPoint(x: size.width / 2, y: 32), anchor: .top)

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
