import SwiftUI
import SpriteKit

// ─── Colours ────────────────────────────────────────────────────────────────
extension Color {
    static let bgDark     = Color(red: 0.03, green: 0.06, blue: 0.08)
    static let neonCyan   = Color(red: 0,    green: 0.96, blue: 1)
    static let neonPink   = Color(red: 1,    green: 0,    blue: 0.50)
    static let neonYellow = Color(red: 1,    green: 0.90, blue: 0)
}
extension UIColor {
    static let bgCanvas = UIColor(red: 0.03, green: 0.06, blue: 0.09, alpha: 1)
    static let gridLine = UIColor(red: 0, green: 0.96, blue: 1, alpha: 0.04)
}

// ─── Game constants ──────────────────────────────────────────────────────────
let GW: CGFloat = 480   // game canvas width
let GH: CGFloat = 520   // game canvas height

// ─── Scene ───────────────────────────────────────────────────────────────────
class BrickBreakerScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .bgCanvas
        drawGrid()
    }

    // Subtle cyan grid — matches HTML's rgba(0,245,255,0.04) lines every 30px
    private func drawGrid() {
        let step: CGFloat = 30
        var x: CGFloat = 0
        while x <= GW {
            let line = SKShapeNode(rect: CGRect(x: x, y: 0, width: 1, height: GH))
            line.fillColor = .gridLine
            line.strokeColor = .clear
            line.zPosition = 0
            addChild(line)
            x += step
        }
        var y: CGFloat = 0
        while y <= GH {
            let line = SKShapeNode(rect: CGRect(x: 0, y: y, width: GW, height: 1))
            line.fillColor = .gridLine
            line.strokeColor = .clear
            line.zPosition = 0
            addChild(line)
            y += step
        }
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

// ─── Start / Game-over overlay ────────────────────────────────────────────────
struct OverlayView: View {
    let title: String
    let subtitle: String
    let buttonLabel: String
    let titleColor: Color
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

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
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.neonCyan, lineWidth: 1)
                        )
                        .shadow(color: .neonCyan.opacity(0.4), radius: 10)
                }
            }
            .padding(32)
        }
    }
}

// ─── Root content view ────────────────────────────────────────────────────────
struct ContentView: View {
    @State private var score = 0
    @State private var level = 1
    @State private var lives = 3
    @State private var gameState: GameState = .idle

    enum GameState { case idle, playing }

    private var scene: BrickBreakerScene {
        let s = BrickBreakerScene(size: CGSize(width: GW, height: GH))
        s.scaleMode = .aspectFit
        return s
    }

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

                HUDView(score: score, level: level, lives: lives)
                    .padding(.bottom, 6)

                ZStack {
                    SpriteView(scene: scene)
                        .frame(width: GW, height: GH)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.neonCyan.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .neonCyan.opacity(0.1), radius: 20)

                    if gameState == .idle {
                        OverlayView(
                            title: "BRICK BREAKER",
                            subtitle: "DRAG TO MOVE  ·  TAP TO LAUNCH",
                            buttonLabel: "START GAME",
                            titleColor: .neonCyan
                        ) {
                            gameState = .playing
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: GW, height: GH)

                Spacer(minLength: 4)
            }
            .frame(maxWidth: GW)
        }
    }
}

// ─── App entry point ──────────────────────────────────────────────────────────
@main
struct SwiftGDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
