import SwiftUI

// MARK: - Config
private let rows = 6
private let cols = 7
private let brickPad: CGFloat = 5
private let brickH: CGFloat = 26
private let topInset: CGFloat = 100
private let paddleW: CGFloat = 110
private let paddleH: CGFloat = 14
private let ballD: CGFloat = 18
private let ballSpeed: CGFloat = 6

// MARK: - Model
struct Brick {
    var alive = true
    let color: Color
}

// MARK: - Game Logic
class Game: ObservableObject {
    @Published var bricks: [[Brick]] = []
    @Published var ballPos: CGPoint = .zero
    @Published var ballVel: CGPoint = .zero
    @Published var paddleX: CGFloat = 0
    @Published var score = 0
    @Published var lives = 3
    @Published var phase: Phase = .idle

    enum Phase { case idle, playing, won, lost }

    private let rowColors: [Color] = [.red, .orange, .yellow, .green, .cyan, .purple]

    func setup(in size: CGSize) {
        paddleX = size.width / 2
        ballPos = CGPoint(x: size.width / 2, y: size.height - 120)
        ballVel = CGPoint(x: 3, y: -ballSpeed)
        score = 0
        lives = 3
        bricks = (0..<rows).map { row in
            (0..<cols).map { _ in Brick(color: rowColors[row % rowColors.count]) }
        }
        phase = .idle
    }

    func movePaddle(to x: CGFloat, in size: CGSize) {
        paddleX = min(max(x, paddleW / 2), size.width - paddleW / 2)
        if phase == .idle { phase = .playing }
    }

    func update(in size: CGSize) {
        guard phase == .playing else { return }

        var p = ballPos
        var v = ballVel
        let r = ballD / 2

        p.x += v.x
        p.y += v.y

        // Walls
        if p.x - r <= 0       { p.x = r;              v.x =  abs(v.x) }
        if p.x + r >= size.width  { p.x = size.width - r; v.x = -abs(v.x) }
        if p.y - r <= 0       { p.y = r;              v.y =  abs(v.y) }

        // Bottom — lose a life
        if p.y + r >= size.height {
            lives -= 1
            if lives <= 0 {
                phase = .lost
            } else {
                p = CGPoint(x: size.width / 2, y: size.height - 120)
                v = CGPoint(x: v.x > 0 ? 3 : -3, y: -ballSpeed)
                phase = .idle
            }
            ballPos = p; ballVel = v; return
        }

        // Paddle
        let py = paddleY(in: size)
        if v.y > 0,
           p.y + r >= py - paddleH / 2,
           p.y - r <= py + paddleH / 2,
           p.x >= paddleX - paddleW / 2,
           p.x <= paddleX + paddleW / 2 {
            p.y = py - paddleH / 2 - r
            v.y = -abs(v.y)
            let hit = (p.x - paddleX) / (paddleW / 2)   // -1…1
            v.x = hit * 6
        }

        // Bricks
        let brickW = brickWidth(in: size)
        outer: for row in 0..<rows {
            for col in 0..<cols {
                guard bricks[row][col].alive else { continue }
                let brick = brickRect(row: row, col: col, w: brickW)
                let ball  = CGRect(x: p.x - r, y: p.y - r, width: ballD, height: ballD)
                guard ball.intersects(brick) else { continue }

                bricks[row][col].alive = false
                score += 10

                let ol = ball.maxX - brick.minX
                let or_ = brick.maxX - ball.minX
                let ot = ball.maxY - brick.minY
                let ob = brick.maxY - ball.minY
                if min(ot, ob) < min(ol, or_) { v.y = -v.y } else { v.x = -v.x }
                break outer
            }
        }

        if bricks.allSatisfy({ $0.allSatisfy { !$0.alive } }) { phase = .won }

        ballPos = p
        ballVel = v
    }

    // MARK: - Geometry helpers
    func paddleY(in size: CGSize) -> CGFloat { size.height - 60 }

    func brickWidth(in size: CGSize) -> CGFloat {
        (size.width - CGFloat(cols + 1) * brickPad) / CGFloat(cols)
    }

    func brickRect(row: Int, col: Int, w: CGFloat) -> CGRect {
        CGRect(
            x: brickPad + CGFloat(col) * (w + brickPad),
            y: topInset + CGFloat(row) * (brickH + brickPad),
            width: w,
            height: brickH
        )
    }
}

// MARK: - View
struct ContentView: View {
    @StateObject private var game = Game()
    let timer = Timer.publish(every: 1 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Bricks
                let w = game.brickWidth(in: geo.size)
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<cols, id: \.self) { col in
                        if game.bricks.indices.contains(row),
                           game.bricks[row][col].alive {
                            let rect = game.brickRect(row: row, col: col, w: w)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(game.bricks[row][col].color)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                }

                // Ball
                Circle()
                    .fill(Color.white)
                    .frame(width: ballD, height: ballD)
                    .position(game.ballPos)

                // Paddle
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.cyan)
                    .frame(width: paddleW, height: paddleH)
                    .position(x: game.paddleX, y: game.paddleY(in: geo.size))

                // HUD
                VStack {
                    HStack {
                        Text("Score: \(game.score)")
                        Spacer()
                        Text("Lives: \(game.lives)")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }

                // Overlay
                if game.phase != .playing {
                    overlay(in: geo.size)
                }
            }
            .onAppear { game.setup(in: geo.size) }
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                game.movePaddle(to: v.location.x, in: geo.size)
            })
            .onReceive(timer) { _ in game.update(in: geo.size) }
        }
    }

    @ViewBuilder
    func overlay(in size: CGSize) -> some View {
        VStack(spacing: 20) {
            switch game.phase {
            case .idle:
                Text("BRICK BREAKER").font(.largeTitle.bold())
                Text("Drag to move the paddle")
            case .won:
                Text("YOU WIN! 🎉").font(.largeTitle.bold())
                Text("Score: \(game.score)")
                Button("Play Again") { game.setup(in: size) }.buttonStyle(.borderedProminent)
            case .lost:
                Text("GAME OVER").font(.largeTitle.bold())
                Text("Score: \(game.score)")
                Button("Try Again") { game.setup(in: size) }.buttonStyle(.borderedProminent)
            case .playing:
                EmptyView()
            }
        }
        .foregroundColor(.white)
        .padding(40)
        .background(.black.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
