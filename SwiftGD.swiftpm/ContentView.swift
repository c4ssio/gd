import SwiftUI

// MARK: - Constants
private let brickCols  = 9
private let brickGap:  CGFloat = 4
private let brickH:    CGFloat = 16
private let brickOffY: CGFloat = 44
private let ballR:     CGFloat = 7
private let baseSpeed: CGFloat = 4.5
private let paddleH:   CGFloat = 10
private let defPaddleW:CGFloat = 90
private let puW:       CGFloat = 28
private let puH:       CGFloat = 18
private let puSpeed:   CGFloat = 1.8

// MARK: - Brick color palette
private struct BrickStyle { let fill: Color; let pts: Int }
private let palette: [BrickStyle] = [
    BrickStyle(fill: Color(red:1,   green:0,    blue:0.5),  pts:50),
    BrickStyle(fill: Color(red:1,   green:0.4,  blue:0),    pts:40),
    BrickStyle(fill: Color(red:1,   green:0.9,  blue:0),    pts:30),
    BrickStyle(fill: Color(red:0,   green:1,    blue:0.53), pts:20),
    BrickStyle(fill: Color(red:0,   green:0.96, blue:1),    pts:10),
    BrickStyle(fill: Color(red:0.73,green:0.27, blue:1),    pts:35),
    BrickStyle(fill: Color(red:1,   green:0.53, blue:0.67), pts:25),
]

// MARK: - Models
struct Brick {
    var alive  = true
    var hp:    Int
    let row:   Int
    let col:   Int
    let styleIdx: Int
    var style: BrickStyle { palette[styleIdx % palette.count] }
}

struct Ball {
    var pos:      CGPoint
    var vel:      CGPoint
    var launched: Bool
    var primary:  Bool
    var color:    Color = .yellow
}

struct PowerUp {
    var pos:  CGPoint
    var kind: Kind
    var col:  Int
    enum Kind: CaseIterable {
        case laser, triball, wide, speed
        var label: String {
            switch self { case .laser:"ZAP"; case .triball:"×3"; case .wide:"↔"; case .speed:"▶▶" }
        }
        var color: Color {
            switch self {
            case .laser:   Color(red:1,   green:0.27, blue:0)
            case .triball: Color(red:0,   green:0.4,  blue:1)
            case .wide:    Color(red:0.67,green:0,    blue:1)
            case .speed:   Color(red:0,   green:1,    blue:0.53)
            }
        }
    }
}

struct Laser    { var x, y: CGFloat; var col: Int }
struct Particle { var pos, vel: CGPoint; var life, size: CGFloat; var color: Color }

// MARK: - Level definitions
private struct BrickDef { let r,c,hp,ci: Int }

private func levelDefs(_ lvl: Int) -> [BrickDef] {
    var out: [BrickDef] = []
    func add(_ r:Int,_ c:Int,_ hp:Int,_ ci:Int) {
        guard c >= 0, c < brickCols else { return }
        out.append(BrickDef(r:r,c:c,hp:hp,ci:ci))
    }
    switch lvl {
    case 1:
        for r in 0..<5 { for c in 0..<brickCols { add(r,c,r<2 ? 2:1,r) } }
    case 2:
        for r in 0..<5 {
            let n = (r+1)*2-1; let s = (brickCols-n)/2
            for c in s..<s+n { add(r,c,r==0 ? 2:1,r) }
        }
    case 3:
        let cx = 4
        for r in 0..<7 {
            let half = r<=3 ? r : 6-r
            for c in (cx-half)...(cx+half) {
                let edge = c==cx-half||c==cx+half||r==0||r==6
                add(r,c,edge ? 2:1,edge ? 0:3)
            }
        }
    case 4:
        for r in 0..<6 { for c in 0..<brickCols { if (r+c)%2==0 { add(r,c,r<2 ? 2:1,r%palette.count) } } }
    case 5:
        for r in 0..<6 {
            for c in 0..<brickCols {
                let gate = r==5 && (c==3||c==4||c==5)
                if (r==0||r==5||c==0||c==brickCols-1) && !gate { add(r,c,2,r==0 ? 0:1) }
            }
        }
        add(2,4,3,5); add(3,4,3,5)
    case 6:
        for r in 0..<6 { var c = r%2; while c < brickCols { add(r,c,2,r%palette.count); c+=2 } }
    case 7:
        for r in 0..<7 { for c in 0..<brickCols {
            let v = c==4, h = r==3
            if v||h { add(r,c,(v&&h) ? 3:2,(v&&h) ? 5:v ? 0:2) }
        } }
    case 8:
        for r in 0..<7 { for c in 0..<brickCols { add(r,c,r<4 ? 2:1,r%palette.count) } }
    default: break
    }
    return out
}

// MARK: - Game
class Game: ObservableObject {
    @Published var bricks:    [Brick]    = []
    @Published var balls:     [Ball]     = []
    @Published var powerups:  [PowerUp]  = []
    @Published var lasers:    [Laser]    = []
    @Published var particles: [Particle] = []
    @Published var paddleX:   CGFloat    = 0
    @Published var paddleW:   CGFloat    = defPaddleW
    @Published var score  = 0
    @Published var lives  = 3
    @Published var level  = 1
    @Published var phase: Phase = .menu
    @Published var wideTimer  = 0
    @Published var speedTimer = 0

    enum Phase { case menu, playing, levelClear, won, lost }

    private(set) var size: CGSize = .zero

    var brickW:  CGFloat { (size.width - brickGap * CGFloat(brickCols+1)) / CGFloat(brickCols) }
    var brickOX: CGFloat { brickGap }
    var paddleY: CGFloat { size.height - 60 }

    func brickRect(_ b: Brick) -> CGRect {
        CGRect(x: brickOX + CGFloat(b.col)*(brickW+brickGap),
               y: brickOffY + CGFloat(b.row)*(brickH+brickGap),
               width: brickW, height: brickH)
    }

    func currentSpeed() -> CGFloat {
        let s = baseSpeed + CGFloat(level-1)*0.35
        return speedTimer > 0 ? s*1.65 : s
    }

    func startGame(in sz: CGSize) {
        size = sz; score = 0; lives = 3; level = 1
        beginLevel()
    }

    private func beginLevel() {
        paddleW = defPaddleW; paddleX = size.width/2
        wideTimer = 0; speedTimer = 0
        powerups = []; lasers = []
        bricks = levelDefs(level).map { Brick(hp:$0.hp, row:$0.r, col:$0.c, styleIdx:$0.ci) }
        resetBall()
        phase = .playing
    }

    private func resetBall() {
        balls = [Ball(pos: CGPoint(x:paddleX, y:paddleY-ballR-2),
                      vel: .zero, launched: false, primary: true, color: .yellow)]
    }

    func launch() {
        guard let i = balls.indices.first(where: { !balls[$0].launched }) else { return }
        let angle = -CGFloat.pi/2 + CGFloat.random(in: -0.4...0.4)
        let s = currentSpeed()
        balls[i].vel = CGPoint(x: cos(angle)*s, y: sin(angle)*s)
        balls[i].launched = true
    }

    func movePaddle(to x: CGFloat) {
        paddleX = x.clamped(to: paddleW/2...size.width-paddleW/2)
    }

    func update() {
        guard phase == .playing else { return }
        tickTimers(); snapUnlaunched(); moveBalls()
        movePowerups(); moveLasers(); tickParticles()
        if bricks.allSatisfy({ !$0.alive }) { endLevel() }
    }

    private func tickTimers() {
        if wideTimer > 0 { wideTimer -= 1
            if wideTimer == 0 { let cx=paddleX; paddleW=defPaddleW; paddleX=cx.clamped(to:paddleW/2...size.width-paddleW/2) }
        }
        if speedTimer > 0 { speedTimer -= 1; if speedTimer == 0 { normalizeBalls() } }
    }

    private func snapUnlaunched() {
        if let i = balls.indices.first(where:{ !balls[$0].launched }) {
            balls[i].pos = CGPoint(x: paddleX, y: paddleY-ballR-2)
        }
    }

    private func moveBalls() {
        var remove: [Int] = []
        for i in balls.indices {
            guard balls[i].launched else { continue }
            balls[i].pos.x += balls[i].vel.x
            balls[i].pos.y += balls[i].vel.y
            wallBounce(i)
            if balls[i].pos.y - ballR > size.height {
                if balls[i].primary { loseLife(); return }
                else { remove.append(i) }
                continue
            }
            paddleBounce(i); brickCollide(i)
        }
        for i in remove.reversed() { balls.remove(at: i) }
    }

    private func wallBounce(_ i: Int) {
        var b = balls[i]
        if b.pos.x-ballR <= 0          { b.pos.x=ballR;             b.vel.x=abs(b.vel.x) }
        if b.pos.x+ballR >= size.width { b.pos.x=size.width-ballR;  b.vel.x = -abs(b.vel.x) }
        if b.pos.y-ballR <= 0          { b.pos.y=ballR;             b.vel.y=abs(b.vel.y) }
        balls[i] = b
    }

    private func paddleBounce(_ i: Int) {
        let b = balls[i]; let py = paddleY
        guard b.vel.y > 0,
              b.pos.y+ballR >= py-paddleH/2, b.pos.y-ballR <= py+paddleH/2,
              b.pos.x >= paddleX-paddleW/2,  b.pos.x <= paddleX+paddleW/2 else { return }
        balls[i].pos.y = py-paddleH/2-ballR
        balls[i].vel.y = -abs(b.vel.y)
        let rel = (b.pos.x-paddleX)/(paddleW/2)
        balls[i].vel.x = rel*baseSpeed*1.2
        normalise(i)
    }

    private func brickCollide(_ i: Int) {
        let br = CGRect(x:balls[i].pos.x-ballR, y:balls[i].pos.y-ballR, width:ballR*2, height:ballR*2)
        for j in bricks.indices {
            guard bricks[j].alive else { continue }
            let rect = brickRect(bricks[j])
            guard br.intersects(rect) else { continue }
            bricks[j].hp -= 1
            if bricks[j].hp <= 0 {
                bricks[j].alive = false
                score += bricks[j].style.pts * level
                spawn(at: CGPoint(x:rect.midX,y:rect.midY), color: bricks[j].style.fill)
                tryDrop(bricks[j])
            }
            let ol = br.maxX-rect.minX, or_ = rect.maxX-br.minX
            let ot = br.maxY-rect.minY, ob   = rect.maxY-br.minY
            if min(ot,ob) < min(ol,or_) { balls[i].vel.y *= -1 } else { balls[i].vel.x *= -1 }
            break
        }
    }

    private func movePowerups() {
        for i in powerups.indices.reversed() {
            powerups[i].pos.y += puSpeed
            let pu = powerups[i]
            if pu.pos.y+puH >= paddleY-paddleH/2,
               pu.pos.x+puW >= paddleX-paddleW/2,
               pu.pos.x     <= paddleX+paddleW/2 { collect(pu); powerups.remove(at: i); continue }
            if pu.pos.y > size.height { powerups.remove(at: i) }
        }
    }

    private func moveLasers() {
        for i in lasers.indices.reversed() {
            lasers[i].y -= 16
            let beam = lasers[i]
            for j in bricks.indices {
                guard bricks[j].alive, bricks[j].col == beam.col else { continue }
                let rect = brickRect(bricks[j])
                if beam.y < rect.maxY && beam.y > rect.minY-8 {
                    bricks[j].hp -= 1
                    if bricks[j].hp <= 0 {
                        bricks[j].alive = false
                        score += bricks[j].style.pts * level
                        spawn(at: CGPoint(x:rect.midX,y:rect.midY), color: bricks[j].style.fill)
                        tryDrop(bricks[j])
                    }
                }
            }
            if lasers[i].y < 0 { lasers.remove(at: i) }
        }
    }

    private func tickParticles() {
        for i in particles.indices.reversed() {
            particles[i].pos.x += particles[i].vel.x
            particles[i].pos.y += particles[i].vel.y
            particles[i].vel.y += 0.1
            particles[i].life  -= 0.04
            if particles[i].life <= 0 { particles.remove(at: i) }
        }
    }

    private func endLevel() {
        powerups=[]; lasers=[]
        phase = level >= 8 ? .won : .levelClear
    }

    private func loseLife() {
        lives -= 1; powerups=[]; lasers=[]
        if lives <= 0 { phase = .lost }
        else { paddleW=defPaddleW; paddleX=size.width/2; wideTimer=0; resetBall() }
    }

    private func spawn(at pt: CGPoint, color: Color) {
        for _ in 0..<12 {
            let a = CGFloat.random(in:0...CGFloat.pi*2)
            let s = CGFloat.random(in:1.5...5)
            particles.append(Particle(pos:pt, vel:CGPoint(x:cos(a)*s,y:sin(a)*s),
                                      life:1, size:CGFloat.random(in:2...5), color:color))
        }
    }

    private func tryDrop(_ b: Brick) {
        guard Double.random(in:0...1) < 0.3 else { return }
        let rect = brickRect(b)
        let kind = PowerUp.Kind.allCases.randomElement()!
        powerups.append(PowerUp(pos:CGPoint(x:rect.midX-puW/2, y:rect.minY), kind:kind, col:b.col))
    }

    private func collect(_ pu: PowerUp) {
        switch pu.kind {
        case .wide:
            let cx = paddleX
            paddleW = min(defPaddleW*2, paddleW+55)
            paddleX = cx.clamped(to: paddleW/2...size.width-paddleW/2)
            wideTimer = 600
        case .triball:
            let ref = balls.first(where:{ $0.launched }) ?? balls[0]
            let spd = currentSpeed()
            let colors: [Color] = [.cyan, Color(red:1,green:0,blue:0.5), .green, Color(red:0.73,green:0.27,blue:1)]
            for i in 0..<2 {
                let angle = -CGFloat.pi/2 + (i==0 ? -0.6 : 0.6)
                balls.append(Ball(pos:ref.pos, vel:CGPoint(x:cos(angle)*spd, y:sin(angle)*spd),
                                  launched:true, primary:false,
                                  color:colors[(balls.count+i) % colors.count]))
            }
        case .laser:
            let lx = brickOX + CGFloat(pu.col)*(brickW+brickGap) + brickW/2
            lasers.append(Laser(x:lx, y:paddleY, col:pu.col))
        case .speed:
            speedTimer = 480; normalizeBalls()
        }
    }

    private func normalise(_ i: Int) {
        let s = hypot(balls[i].vel.x, balls[i].vel.y), t = currentSpeed()
        guard s > 0 else { return }
        balls[i].vel.x = balls[i].vel.x/s*t
        balls[i].vel.y = balls[i].vel.y/s*t
    }

    private func normalizeBalls() { for i in balls.indices { normalise(i) } }

    func nextLevel() { level += 1; beginLevel() }
    func restart(in sz: CGSize) { size = sz; startGame(in: sz) }
}

// MARK: - Helpers
extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { max(r.lowerBound, min(r.upperBound, self)) }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var game = Game()
    let timer = Timer.publish(every: 1/60, on: .main, in: .common).autoconnect()

    // Title flicker state
    @State private var titleOpacity: Double = 1.0

    // MARK: body
    var body: some View {
        VStack(spacing: 0) {
            titleHeader
            hudBar

            GeometryReader { geo in
                ZStack {
                    // Canvas background (slightly lighter than body — matches HTML #080f1e)
                    Color(red:0.031, green:0.059, blue:0.118)

                    Canvas { ctx, size in render(ctx:ctx, size:size) }

                    // Overlays
                    switch game.phase {
                    case .menu:
                        modal(title:"BRICK BREAKER", sub:"DRAG TO MOVE · TAP TO LAUNCH",
                              btn:"START GAME", color:.cyan) { game.startGame(in: geo.size) }
                    case .levelClear:
                        let names = ["","CLASSIC","PYRAMID","DIAMOND","CHECKERBOARD","FORTRESS","HERRINGBONE","CROSS","GAUNTLET"]
                        modal(title:"STAGE \(game.level) CLEAR!",
                              sub:"\(names[min(game.level,8)]) COMPLETE · SCORE: \(game.score)",
                              btn:"START STAGE \(game.level+1)", color:.cyan) { game.nextLevel() }
                    case .won:
                        modal(title:"YOU WIN!", sub:"ALL 8 STAGES · FINAL SCORE: \(game.score)",
                              btn:"PLAY AGAIN", color:Color(red:1,green:0.9,blue:0)) { game.restart(in:geo.size) }
                    case .lost:
                        modal(title:"GAME OVER", sub:"SCORE: \(game.score)",
                              btn:"PLAY AGAIN", color:Color(red:1,green:0,blue:0.5)) { game.restart(in:geo.size) }
                    case .playing:
                        EmptyView()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if game.phase == .menu { game.startGame(in: geo.size) }
                            game.movePaddle(to: v.location.x)
                        }
                )
                .simultaneousGesture(
                    TapGesture().onEnded { if game.phase == .playing { game.launch() } }
                )
                .onReceive(timer) { _ in game.update() }
            }
            // Canvas border + outer glow matching .canvas-wrap
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red:0,green:0.96,blue:1).opacity(0.2), lineWidth:1)
            )
            .shadow(color: Color(red:0,green:0.96,blue:1).opacity(0.1), radius:30)

            legendRow
            footerView
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(atmosphereBackground)
        // Title flicker loop
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_700_000_000)
                withAnimation(.linear(duration: 0.08)) { titleOpacity = 0.85 }
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.linear(duration: 0.08)) { titleOpacity = 1.0 }
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation(.linear(duration: 0.08)) { titleOpacity = 0.9 }
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.linear(duration: 0.08)) { titleOpacity = 1.0 }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }

    // MARK: - Atmospheric background (body::before radial glows + body::after scanlines)
    private var atmosphereBackground: some View {
        GeometryReader { geo in
            ZStack {
                // Base dark fill
                Color(red:0.02,green:0.04,blue:0.08)

                // body::before — two corner radial glows
                Canvas { ctx, size in
                    // Cyan glow top-left (20%, 20%)
                    let cyanCenter = CGPoint(x: size.width*0.2, y: size.height*0.2)
                    let cyanRadius = max(size.width, size.height) * 0.6
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: cyanCenter.x-cyanRadius, y: cyanCenter.y-cyanRadius,
                                               width: cyanRadius*2, height: cyanRadius*2)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red:0,green:0.96,blue:1,opacity:0.06), .clear]),
                            center: UnitPoint(x: 0.5, y: 0.5),
                            startRadius: 0, endRadius: cyanRadius)
                    )
                    // Pink glow bottom-right (80%, 80%)
                    let pinkCenter = CGPoint(x: size.width*0.8, y: size.height*0.8)
                    let pinkRadius = max(size.width, size.height) * 0.6
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pinkCenter.x-pinkRadius, y: pinkCenter.y-pinkRadius,
                                               width: pinkRadius*2, height: pinkRadius*2)),
                        with: .radialGradient(
                            Gradient(colors: [Color(red:1,green:0,blue:0.5,opacity:0.06), .clear]),
                            center: UnitPoint(x: 0.5, y: 0.5),
                            startRadius: 0, endRadius: pinkRadius)
                    )
                }

                // body::after — scanline stripe overlay
                Canvas { ctx, size in
                    var y: CGFloat = 3
                    while y < size.height {
                        ctx.fill(Path(CGRect(x:0, y:y, width:size.width, height:1)),
                                 with:.color(.black.opacity(0.15)))
                        y += 4
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Chrome views

    private var titleHeader: some View {
        Text("BRICK BREAKER")
            .font(.system(size: 22, weight: .black, design: .monospaced))
            .tracking(5)
            .foregroundColor(Color(red:0, green:0.96, blue:1))
            .shadow(color: Color(red:0, green:0.96, blue:1), radius: 10)
            .shadow(color: Color(red:0, green:0.96, blue:1).opacity(0.4), radius: 20)
            .opacity(titleOpacity)
            .padding(.bottom, 5)
    }

    private var hudBar: some View {
        HStack(spacing: 32) {
            hudItem("SCORE", "\(game.score)")
            hudItem("LEVEL", "\(game.level)")
            hudItem("LIVES", String(repeating:"♥ ", count:max(0,game.lives)).trimmingCharacters(in:.whitespaces))
        }
        .padding(.bottom, 6)
    }

    private var legendRow: some View {
        let items: [(Color, String)] = [
            (Color(red:1,   green:0.27, blue:0),    "ZAP — clears column"),
            (Color(red:0,   green:0.4,  blue:1),    "3-BALL"),
            (Color(red:0.67,green:0,    blue:1),    "WIDE paddle"),
            (Color(red:0,   green:1,    blue:0.53), "SPEED boost"),
        ]
        return HStack(spacing: 10) {
            ForEach(items.indices, id:\.self) { i in
                HStack(spacing: 4) {
                    Circle().fill(items[i].0).frame(width:7, height:7)
                    Text(items[i].1)
                }
            }
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundColor(.white.opacity(0.28))
        .padding(.top, 5)
    }

    private var footerView: some View {
        Text("DRAG TO MOVE PADDLE  |  TAP TO LAUNCH")
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.white.opacity(0.16))
            .tracking(1)
            .padding(.top, 4)
    }

    // MARK: - Canvas renderer
    func render(ctx: GraphicsContext, size: CGSize) {
        // Grid
        var grid = Path()
        var gx: CGFloat = 0
        while gx < size.width  { grid.move(to:.init(x:gx,y:0)); grid.addLine(to:.init(x:gx,y:size.height)); gx+=30 }
        var gy: CGFloat = 0
        while gy < size.height { grid.move(to:.init(x:0,y:gy)); grid.addLine(to:.init(x:size.width,y:gy)); gy+=30 }
        ctx.stroke(grid, with:.color(.cyan.opacity(0.04)), lineWidth:1)

        // Speed flash
        if game.speedTimer > 0 && (game.speedTimer % 20) < 10 {
            ctx.stroke(Path(CGRect(x:0,y:0,width:size.width,height:size.height)),
                       with:.color(Color(red:0,green:1,blue:0.53,opacity:0.18)), lineWidth:8)
        }

        // Bricks
        for b in game.bricks where b.alive {
            let rect = game.brickRect(b)
            ctx.drawLayer { c in
                c.opacity = b.hp < 2 ? 1.0 : 0.75
                c.addFilter(.shadow(color: b.style.fill.opacity(0.7), radius: 8))
                c.fill(Path(roundedRect:rect,cornerRadius:3), with:.color(b.style.fill))
                c.fill(Path(CGRect(x:rect.minX,y:rect.minY,width:rect.width,height:rect.height*0.45)),
                       with:.color(.white.opacity(0.18)))
                if b.hp >= 2 {
                    let d = Path(ellipseIn: CGRect(x:rect.maxX-8,y:rect.midY-2.5,width:5,height:5))
                    c.fill(d, with:.color(.white.opacity(0.7)))
                }
            }
        }

        // Lasers
        for beam in game.lasers {
            ctx.drawLayer { c in
                c.addFilter(.shadow(color:.orange, radius:12))
                var lp = Path()
                lp.move(to:.init(x:beam.x,y:beam.y)); lp.addLine(to:.init(x:beam.x,y:0))
                c.stroke(lp, with:.color(Color(red:1,green:0.4,blue:0)), lineWidth:3)
                c.stroke(lp, with:.color(Color(red:1,green:0.93,blue:0.53)), lineWidth:1)
            }
        }

        // Particles
        for p in game.particles {
            let r = p.size*p.life
            ctx.opacity = Double(p.life)
            ctx.fill(Path(ellipseIn:CGRect(x:p.pos.x-r,y:p.pos.y-r,width:r*2,height:r*2)),
                     with:.color(p.color))
        }
        ctx.opacity = 1

        // Power-ups
        for pu in game.powerups {
            let rect = CGRect(x:pu.pos.x, y:pu.pos.y, width:puW, height:puH)
            ctx.drawLayer { c in
                c.addFilter(.shadow(color:pu.kind.color, radius:10))
                c.fill(Path(roundedRect:rect,cornerRadius:5), with:.color(pu.kind.color))
                c.fill(Path(roundedRect:CGRect(x:rect.minX,y:rect.minY,
                                               width:rect.width,height:rect.height*0.45),
                            cornerRadius:5), with:.color(.white.opacity(0.25)))
                c.draw(Text(pu.kind.label)
                    .font(.system(size:9,weight:.bold)).foregroundColor(.white),
                       at:CGPoint(x:rect.midX,y:rect.midY))
            }
        }

        // Paddle
        let pc: Color = game.wideTimer>0  ? Color(red:0.8,green:0.27,blue:1) :
                        game.speedTimer>0 ? Color(red:0,green:1,blue:0.53) : .cyan
        let pr = CGRect(x:game.paddleX-game.paddleW/2, y:game.paddleY-paddleH/2,
                        width:game.paddleW, height:paddleH)
        ctx.drawLayer { c in
            c.addFilter(.shadow(color:pc, radius:14))
            c.fill(Path(roundedRect:pr,cornerRadius:paddleH/2), with:.color(pc))
        }

        // Balls
        for b in game.balls {
            let br = CGRect(x:b.pos.x-ballR,y:b.pos.y-ballR,width:ballR*2,height:ballR*2)
            ctx.drawLayer { c in
                c.addFilter(.shadow(color:b.color.opacity(0.9), radius:16))
                c.fill(Path(ellipseIn:br), with:.color(b.color))
            }
        }

        // Launch hint
        if game.phase == .playing, let first = game.balls.first, !first.launched {
            let alpha = 0.5 + 0.3 * sin(Date().timeIntervalSinceReferenceDate * 3.3)
            ctx.draw(Text("TAP TO LAUNCH")
                .font(.system(size:12,weight:.bold,design:.rounded))
                .foregroundColor(.white.opacity(alpha)),
                     at: CGPoint(x:size.width/2, y:game.paddleY-22))
        }

        // Timer bars
        let bh: CGFloat = 4
        if game.wideTimer > 0 {
            ctx.fill(Path(CGRect(x:0,y:size.height-bh,
                                 width:size.width*CGFloat(game.wideTimer)/600,height:bh)),
                     with:.color(Color(red:0.8,green:0.27,blue:1)))
        }
        if game.speedTimer > 0 {
            ctx.fill(Path(CGRect(x:0,y:size.height-bh,
                                 width:size.width*CGFloat(game.speedTimer)/480,height:bh)),
                     with:.color(Color(red:0,green:1,blue:0.53)))
        }

        // Level name watermark
        if game.phase == .playing {
            let names = ["","CLASSIC","PYRAMID","DIAMOND","CHECKERBOARD","FORTRESS","HERRINGBONE","CROSS","GAUNTLET"]
            ctx.opacity = 0.18
            ctx.draw(Text(names[min(game.level,8)])
                .font(.system(size:9,design:.monospaced)).foregroundColor(.white),
                     at:CGPoint(x:size.width-40,y:size.height-10))
            ctx.opacity = 1
        }
    }

    // MARK: - HUD / overlay helpers
    @ViewBuilder
    private func hudItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size:9, weight:.regular, design:.monospaced))
                .foregroundColor(.white.opacity(0.4))
                .tracking(2)
            Text(value)
                .font(.system(size:15, weight:.bold, design:.monospaced))
                .foregroundColor(Color(red:1,green:0.9,blue:0))
        }
    }

    @ViewBuilder
    private func modal(title:String, sub:String, btn:String, color:Color, action: @escaping ()->Void) -> some View {
        VStack(spacing:16) {
            Text(title)
                .font(.system(size:24,weight:.black,design:.rounded))
                .foregroundColor(color)
                .multilineTextAlignment(.center)
            Text(sub)
                .font(.system(size:11,design:.monospaced))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button(btn, action: action)
                .font(.system(size:12,weight:.bold,design:.rounded))
                .padding(.horizontal,24).padding(.vertical,10)
                .overlay(RoundedRectangle(cornerRadius:4).stroke(color,lineWidth:1))
                .foregroundColor(color)
        }
        .padding(40)
        .background(Color(red:0.02,green:0.04,blue:0.08).opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius:16))
    }
}
