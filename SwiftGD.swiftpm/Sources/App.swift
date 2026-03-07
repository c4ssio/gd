import SwiftUI
import SpriteKit

// ─── Cross-platform colours (SKColor = UIColor on iOS, NSColor on macOS) ────
extension SKColor {
    static let bgCanvas = SKColor(red: 0.03, green: 0.06, blue: 0.09, alpha: 1)
    static let gridLine = SKColor(red: 0, green: 0.96, blue: 1, alpha: 0.04)
}
extension Color {
    static let bgDark     = Color(red: 0.03, green: 0.06, blue: 0.08)
    static let neonCyan   = Color(red: 0,    green: 0.96, blue: 1)
    static let neonPink   = Color(red: 1,    green: 0,    blue: 0.50)
    static let neonYellow = Color(red: 1,    green: 0.90, blue: 0)
}

// ─── Game constants ──────────────────────────────────────────────────────────
let GW: CGFloat = 480
let GH: CGFloat = 520

let BRICK_COLS  = 9
let BRICK_W: CGFloat  = 44
let BRICK_H: CGFloat  = 16
let BRICK_GAP: CGFloat = 4
// Left offset so the 9-column grid is centred in GW
let BRICK_OFFSET_X: CGFloat = (GW - CGFloat(BRICK_COLS) * (BRICK_W + BRICK_GAP) + BRICK_GAP) / 2
// Top offset in HTML coords (44 px from top of canvas)
let BRICK_OFFSET_Y_HTML: CGFloat = 44

// Paddle
let PADDLE_W: CGFloat = 90
let PADDLE_H: CGFloat = 10
// HTML: paddle.y = GH-36, occupies rows 484–494 from top → SpriteKit centre = 31
let PADDLE_Y_CENTER: CGFloat = 31

// ─── Brick colour table ──────────────────────────────────────────────────────
struct BrickColor {
    let fill: SKColor
    let pts:  Int
}

let BRICK_COLORS: [BrickColor] = [
    BrickColor(fill: SKColor(red:1,    green:0,    blue:0.50, alpha:1), pts:50), // 0 pink
    BrickColor(fill: SKColor(red:1,    green:0.40, blue:0,    alpha:1), pts:40), // 1 orange
    BrickColor(fill: SKColor(red:1,    green:0.90, blue:0,    alpha:1), pts:30), // 2 yellow
    BrickColor(fill: SKColor(red:0,    green:1,    blue:0.53, alpha:1), pts:20), // 3 green
    BrickColor(fill: SKColor(red:0,    green:0.96, blue:1,    alpha:1), pts:10), // 4 cyan
    BrickColor(fill: SKColor(red:0.73, green:0.27, blue:1,    alpha:1), pts:35), // 5 purple
    BrickColor(fill: SKColor(red:1,    green:0.53, blue:0.67, alpha:1), pts:25), // 6 light-pink
]

// ─── Brick definition (from level pattern) ───────────────────────────────────
struct BrickDef {
    let row: Int
    let col: Int
    let hp:  Int
    let colorIdx: Int
}

// ─── Level patterns (8 levels, same logic as HTML) ───────────────────────────
func levelPattern(_ lvl: Int) -> [BrickDef] {
    var out: [BrickDef] = []
    func add(_ r: Int, _ c: Int, _ hp: Int, _ ci: Int) {
        guard c >= 0 && c < BRICK_COLS else { return }
        out.append(BrickDef(row: r, col: c, hp: hp, colorIdx: ci))
    }

    switch lvl {
    case 1: // CLASSIC — 5 full rows
        for r in 0..<5 { for c in 0..<BRICK_COLS { add(r, c, r < 2 ? 2 : 1, r) } }

    case 2: // PYRAMID
        for r in 0..<5 {
            let count = (r + 1) * 2 - 1
            let start = (BRICK_COLS - count) / 2
            for c in start..<(start + count) { add(r, c, r == 0 ? 2 : 1, r) }
        }

    case 3: // DIAMOND
        for r in 0..<7 {
            let half = r <= 3 ? r : 6 - r
            for c in (4 - half)...(4 + half) {
                let edge = (c == 4 - half || c == 4 + half || r == 0 || r == 6)
                add(r, c, edge ? 2 : 1, edge ? 0 : 3)
            }
        }

    case 4: // CHECKERBOARD
        for r in 0..<6 { for c in 0..<BRICK_COLS {
            if (r + c) % 2 == 0 { add(r, c, r < 2 ? 2 : 1, r % BRICK_COLORS.count) }
        } }

    case 5: // FORTRESS
        for r in 0..<6 { for c in 0..<BRICK_COLS {
            let isGate = (r == 5 && (c == 3 || c == 4 || c == 5))
            if (r == 0 || r == 5 || c == 0 || c == BRICK_COLS-1) && !isGate {
                add(r, c, 2, r == 0 ? 0 : 1)
            }
        } }
        add(2, 4, 3, 5); add(3, 4, 3, 5)

    case 6: // HERRINGBONE
        for r in 0..<6 {
            let offset = r % 2 == 0 ? 0 : 1
            var c = 0
            while c < BRICK_COLS - offset { add(r, c + offset, 2, r % BRICK_COLORS.count); c += 2 }
        }

    case 7: // CROSS
        for r in 0..<7 { for c in 0..<BRICK_COLS {
            let v = c == 4, h = r == 3
            if v || h { add(r, c, (v && h) ? 3 : 2, (v && h) ? 5 : (v ? 0 : 2)) }
        } }

    default: // GAUNTLET (lvl 8)
        for r in 0..<7 { for c in 0..<BRICK_COLS { add(r, c, r < 4 ? 2 : 1, r % BRICK_COLORS.count) } }
    }
    return out
}

// Converts HTML-style top-left row/col to SpriteKit scene Y (bottom-left origin)
func brickSceneY(row: Int) -> CGFloat {
    let htmlY = BRICK_OFFSET_Y_HTML + CGFloat(row) * (BRICK_H + BRICK_GAP)
    return GH - htmlY - BRICK_H
}

// ─── Shared game model ───────────────────────────────────────────────────────
enum GameState { case idle, playing, levelClear, dead, win }

class GameModel: ObservableObject {
    @Published var score: Int      = 0
    @Published var level: Int      = 1
    @Published var lives: Int      = 3
    @Published var state: GameState = .idle
}

// ─── Live brick info stored per node ─────────────────────────────────────────
struct BrickLive {
    var hp:       Int
    var colorIdx: Int
    var row:      Int
    var col:      Int
}

// Paddle colours depending on active power-up
enum PaddleStyle { case normal, wide, speed }

func paddleColors(_ style: PaddleStyle) -> (fill: SKColor, stroke: SKColor) {
    switch style {
    case .normal: return (SKColor(red:0,    green:0.96, blue:1,  alpha:1),
                          SKColor(red:0,    green:0.96, blue:1,  alpha:0.5))
    case .wide:   return (SKColor(red:0.8,  green:0.27, blue:1,  alpha:1),
                          SKColor(red:0.8,  green:0.27, blue:1,  alpha:0.5))
    case .speed:  return (SKColor(red:0,    green:1,    blue:0.53, alpha:1),
                          SKColor(red:0,    green:1,    blue:0.53, alpha:0.5))
    }
}

// ─── Scene ───────────────────────────────────────────────────────────────────
class BrickBreakerScene: SKScene {
    weak var model: GameModel?

    // brick nodes; name = "b_row_col"
    private(set) var brickLive: [SKNode: BrickLive] = [:]

    // ── Paddle state ─────────────────────────────────────────────────────────
    private var paddleNode: SKShapeNode!
    // left-edge X of paddle in scene coords
    var paddleX: CGFloat = GW / 2 - PADDLE_W / 2
    var paddleWidth: CGFloat = PADDLE_W

    // drag tracking
    private var dragStartTouchX:  CGFloat = 0
    private var dragStartPaddleX: CGFloat = 0
    private var dragMoved = false

    // callback so ContentView can react to a "tap" (future ball launch)
    var onTap: (() -> Void)?

    override func didMove(to view: SKView) {
        backgroundColor = .bgCanvas
        drawGrid()
        buildPaddle()
    }

    // ── Grid ────────────────────────────────────────────────────────────────
    private func drawGrid() {
        let step: CGFloat = 30
        var x: CGFloat = 0
        while x <= GW {
            let l = SKShapeNode(rect: CGRect(x: x, y: 0, width: 1, height: GH))
            l.fillColor = .gridLine; l.strokeColor = .clear; l.zPosition = 0; addChild(l); x += step
        }
        var y: CGFloat = 0
        while y <= GH {
            let l = SKShapeNode(rect: CGRect(x: 0, y: y, width: GW, height: 1))
            l.fillColor = .gridLine; l.strokeColor = .clear; l.zPosition = 0; addChild(l); y += step
        }
    }

    // ── Paddle ───────────────────────────────────────────────────────────────
    private func buildPaddle() {
        let rect = CGRect(x: -paddleWidth/2, y: -PADDLE_H/2, width: paddleWidth, height: PADDLE_H)
        paddleNode = SKShapeNode(rect: rect, cornerRadius: PADDLE_H/2)
        let c = paddleColors(.normal)
        paddleNode.fillColor   = c.fill
        paddleNode.strokeColor = c.stroke
        paddleNode.lineWidth   = 4
        paddleNode.position    = CGPoint(x: paddleX + paddleWidth/2, y: PADDLE_Y_CENTER)
        paddleNode.zPosition   = 5
        paddleNode.name        = "paddle"
        addChild(paddleNode)
    }

    func updatePaddleNode(style: PaddleStyle = .normal) {
        let rect = CGRect(x: -paddleWidth/2, y: -PADDLE_H/2, width: paddleWidth, height: PADDLE_H)
        paddleNode.path = CGPath(roundedRect: rect, cornerWidth: PADDLE_H/2,
                                 cornerHeight: PADDLE_H/2, transform: nil)
        let c = paddleColors(style)
        paddleNode.fillColor   = c.fill
        paddleNode.strokeColor = c.stroke
        paddleNode.position    = CGPoint(x: paddleX + paddleWidth/2, y: PADDLE_Y_CENTER)
    }

    // Clamp paddle left-edge inside canvas
    private func clampPaddle() {
        paddleX = max(0, min(GW - paddleWidth, paddleX))
        paddleNode.position = CGPoint(x: paddleX + paddleWidth/2, y: PADDLE_Y_CENTER)
    }

    // ── Touch input ──────────────────────────────────────────────────────────
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        dragStartTouchX  = p.x
        dragStartPaddleX = paddleX
        dragMoved = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        let delta = p.x - dragStartTouchX
        if abs(delta) > 4 { dragMoved = true }
        paddleX = dragStartPaddleX + delta
        clampPaddle()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !dragMoved { onTap?() }
        dragMoved = false
    }

    // ── Build bricks ─────────────────────────────────────────────────────────
    func buildBricks() {
        guard let lvl = model?.level else { return }
        // Remove existing bricks
        brickLive.keys.forEach { $0.removeFromParent() }
        brickLive.removeAll()

        for def in levelPattern(lvl) {
            let color = BRICK_COLORS[def.colorIdx % BRICK_COLORS.count]
            let x = BRICK_OFFSET_X + CGFloat(def.col) * (BRICK_W + BRICK_GAP)
            let y = brickSceneY(row: def.row)

            // Brick body (rect centred at node position)
            let node = SKShapeNode(
                rect: CGRect(x: -BRICK_W/2, y: -BRICK_H/2, width: BRICK_W, height: BRICK_H),
                cornerRadius: 2
            )
            node.position   = CGPoint(x: x + BRICK_W/2, y: y + BRICK_H/2)
            node.fillColor  = def.hp < 2 ? color.fill : color.fill.withAlphaComponent(0.7)
            node.strokeColor = color.fill.withAlphaComponent(0.35)
            node.lineWidth  = 1
            node.zPosition  = 1
            node.name       = "brick"
            addChild(node)

            // White dot = HP indicator (only for 2+ HP bricks)
            if def.hp >= 2 {
                let dot = SKShapeNode(circleOfRadius: 2.5)
                dot.fillColor   = SKColor.white.withAlphaComponent(0.6)
                dot.strokeColor = .clear
                dot.position    = CGPoint(x: BRICK_W/2 - 6, y: 0)
                dot.zPosition   = 2
                dot.name        = "hpDot"
                node.addChild(dot)
            }

            brickLive[node] = BrickLive(hp: def.hp, colorIdx: def.colorIdx, row: def.row, col: def.col)
        }
    }

    // Damage a brick; returns true if destroyed
    func damageBrick(_ node: SKNode, by amount: Int = 1) -> Bool {
        guard var live = brickLive[node] else { return false }
        live.hp -= amount
        brickLive[node] = live
        if live.hp <= 0 {
            node.removeFromParent()
            brickLive.removeValue(forKey: node)
            return true
        }
        // Update appearance for reduced-HP brick (remove dot, full opacity)
        if let shape = node as? SKShapeNode {
            let color = BRICK_COLORS[live.colorIdx % BRICK_COLORS.count]
            shape.fillColor = color.fill
            node.childNode(withName: "hpDot")?.removeFromParent()
        }
        return false
    }

    var allBricksCleared: Bool { brickLive.isEmpty }

    func resetPaddle() {
        paddleWidth = PADDLE_W
        paddleX     = GW / 2 - PADDLE_W / 2
        updatePaddleNode()
    }
}

// ─── HUD bar ─────────────────────────────────────────────────────────────────
struct HUDView: View {
    let score: Int
    let level: Int
    let lives: Int

    var body: some View {
        HStack(spacing: 32) {
            hudItem(label: "SCORE", value: "\(score)")
            hudItem(label: "LEVEL", value: "\(level)")
            hudItem(label: "LIVES", value: String(repeating: "♥", count: lives))
        }
        .padding(.vertical, 6)
    }

    private func hudItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .kerning(2)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.neonYellow)
                .shadow(color: .neonYellow.opacity(0.6), radius: 6)
        }
    }
}

// ─── Overlay ─────────────────────────────────────────────────────────────────
struct OverlayView: View {
    let title:       String
    let subtitle:    String
    let buttonLabel: String
    let titleColor:  Color
    let onTap:       () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(title)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(titleColor)
                    .shadow(color: titleColor.opacity(0.8), radius: 16)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .kerning(1.5)
                    .multilineTextAlignment(.center)
                Button(action: onTap) {
                    Text(buttonLabel)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(3)
                        .foregroundColor(.neonCyan)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.neonCyan, lineWidth: 1))
                        .shadow(color: .neonCyan.opacity(0.4), radius: 10)
                }
            }
            .padding(32)
        }
    }
}

// ─── Root view ────────────────────────────────────────────────────────────────
struct ContentView: View {
    @StateObject private var model = GameModel()

    @State private var scene: BrickBreakerScene = {
        let s = BrickBreakerScene(size: CGSize(width: GW, height: GH))
        s.scaleMode = .aspectFit
        return s
    }()

    var body: some View {
        ZStack {
            Color.bgDark.ignoresSafeArea()
            VStack(spacing: 0) {
                Text("BRICK BREAKER")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .kerning(4)
                    .foregroundColor(.neonCyan)
                    .shadow(color: .neonCyan.opacity(0.6), radius: 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                HUDView(score: model.score, level: model.level, lives: model.lives)
                    .padding(.bottom, 6)

                ZStack {
                    SpriteView(scene: scene)
                        .frame(width: GW, height: GH)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.neonCyan.opacity(0.2), lineWidth: 1))
                        .shadow(color: .neonCyan.opacity(0.1), radius: 20)

                    if model.state == .idle {
                        OverlayView(
                            title: "BRICK BREAKER",
                            subtitle: "DRAG TO MOVE  ·  TAP TO LAUNCH",
                            buttonLabel: "START GAME",
                            titleColor: .neonCyan
                        ) { startGame() }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: GW, height: GH)

                Spacer(minLength: 4)
            }
            .frame(maxWidth: GW)
        }
        .onAppear {
            scene.model = model
            scene.buildBricks()   // preview bricks before game starts
        }
    }

    private func startGame() {
        model.score = 0
        model.lives = 3
        model.level = 1
        model.state = .playing
        scene.resetPaddle()
        scene.buildBricks()
    }
}

// ─── App ─────────────────────────────────────────────────────────────────────
@main
struct SwiftGDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
