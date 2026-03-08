import SwiftUI
import Combine

// MARK: - Data Models
// These structs mirror the SQLite schema in market_data.db.
// Phase 2: replace seed arrays below with GRDB queries.

struct AssetInfo: Identifiable, Equatable {
    let id: String        // ticker — PRIMARY KEY in assets table
    let name: String
    let category: String  // matches assets.category column
    let parent: String?   // matches assets.parent column; nil = top-level
    let level: Int        // 1 = asset class, 2 = sector
    let emoji: String

    var ticker: String { id }
}

// Mirrors a row from the prices table (used by data pipeline, referenced in comments)
// struct PriceBar { ticker: String, date: String, open/high/low/close: Double, volume: Int }

// MARK: - Seed Data
// TODO Phase 2: replace with `SELECT * FROM assets WHERE level = 1`
fileprivate let topAssets: [AssetInfo] = [
    .init(id: "US_EQ", name: "US Equities",      category: "equity",      parent: nil, level: 1, emoji: "🏛"),
    .init(id: "TLT",   name: "Long Treasuries",   category: "bond",        parent: nil, level: 1, emoji: "📜"),
    .init(id: "SHV",   name: "Short T-Bills",     category: "bond",        parent: nil, level: 1, emoji: "💵"),
    .init(id: "GLD",   name: "Gold",              category: "commodity",   parent: nil, level: 1, emoji: "🥇"),
    .init(id: "DJP",   name: "Commodities",       category: "commodity",   parent: nil, level: 1, emoji: "⚡️"),
    .init(id: "UUP",   name: "USD Index",         category: "forex",       parent: nil, level: 1, emoji: "💱"),
    .init(id: "EFA",   name: "Intl Developed",    category: "equity",      parent: nil, level: 1, emoji: "🌍"),
    .init(id: "EEM",   name: "Emerging Markets",  category: "equity",      parent: nil, level: 1, emoji: "🌏"),
    .init(id: "VNQ",   name: "Real Estate",       category: "realestate",  parent: nil, level: 1, emoji: "🏢"),
    .init(id: "SGOV",  name: "Cash",              category: "cash",        parent: nil, level: 1, emoji: "💰"),
]

// TODO Phase 2: replace with `SELECT * FROM assets WHERE level = 2`
fileprivate let sectorAssets: [AssetInfo] = [
    .init(id: "XLK",  name: "Technology",         category: "equity_sector", parent: "US_EQ", level: 2, emoji: "💻"),
    .init(id: "XLV",  name: "Healthcare",          category: "equity_sector", parent: "US_EQ", level: 2, emoji: "🏥"),
    .init(id: "XLF",  name: "Financials",          category: "equity_sector", parent: "US_EQ", level: 2, emoji: "🏦"),
    .init(id: "XLY",  name: "Cons. Disc.",         category: "equity_sector", parent: "US_EQ", level: 2, emoji: "🛍"),
    .init(id: "XLP",  name: "Cons. Staples",       category: "equity_sector", parent: "US_EQ", level: 2, emoji: "🛒"),
    .init(id: "XLI",  name: "Industrials",         category: "equity_sector", parent: "US_EQ", level: 2, emoji: "⚙️"),
    .init(id: "XLE",  name: "Energy",              category: "equity_sector", parent: "US_EQ", level: 2, emoji: "🛢"),
    .init(id: "XLU",  name: "Utilities",           category: "equity_sector", parent: "US_EQ", level: 2, emoji: "💡"),
    .init(id: "XLB",  name: "Materials",           category: "equity_sector", parent: "US_EQ", level: 2, emoji: "⛏"),
    .init(id: "XLRE", name: "Sector RE",           category: "equity_sector", parent: "US_EQ", level: 2, emoji: "🏘"),
    .init(id: "XLC",  name: "Comm. Services",      category: "equity_sector", parent: "US_EQ", level: 2, emoji: "📡"),
]

// MARK: - Mock Market Returns
// TODO Phase 2: replace with:
//   SELECT close FROM prices WHERE ticker = ? ORDER BY date
//   weekly_return[i] = close[i] / close[i-1] - 1
fileprivate func mockReturn(ticker: String, week: Int) -> Double {
    let h = ticker.unicodeScalars.reduce(0) { $0 ^ Int($1.value) }
    let a = sin(Double(h) * 0.137 + Double(week) * 0.41)
    let b = cos(Double(h) * 0.073 + Double(week) * 0.67)
    return a * 0.015 + b * 0.008   // realistic-ish weekly vol (~1–2%)
}

// MARK: - Portfolio Engine

class PortfolioEngine: ObservableObject {

    // Allocation map: ticker -> fraction of total bag [0, 1]; sum of values ≤ 1.0
    @Published var allocations: [String: Double] = [:]

    // Drill-down navigation; nil = top-level asset classes
    @Published var drillParent: String? = nil

    // Playback state
    @Published var weekIndex: Int = 0
    @Published var isPlaying: Bool = false

    // Per-ticker returns for the most recent tick (drives flash overlay)
    @Published var weeklyReturn: [String: Double] = [:]

    // Cumulative value multiplier per ticker (1.0 = no gain/loss)
    @Published var cumMultiplier: [String: Double] = [:]

    let totalWeeks = 52
    private var timer: AnyCancellable?

    private let allAssets: [AssetInfo] = topAssets + sectorAssets

    var sandBagRemaining: Double {
        max(0, 1.0 - allocations.values.reduce(0, +))
    }

    var visibleAssets: [AssetInfo] {
        guard let p = drillParent else { return topAssets }
        return sectorAssets.filter { $0.parent == p }
    }

    init() {
        for a in allAssets {
            allocations[a.id]    = 0.0
            cumMultiplier[a.id]  = 1.0
        }
    }

    // MARK: Sand gestures

    /// Pour up to `amount` from the bag into `ticker`.
    func addSand(_ ticker: String, amount: Double = 0.05) {
        let pour = min(amount, sandBagRemaining)
        guard pour > 0.001 else { return }
        allocations[ticker] = (allocations[ticker] ?? 0) + pour
    }

    /// Drain all sand from `ticker` back to the bag.
    func drainSand(_ ticker: String) {
        allocations[ticker] = 0
    }

    // MARK: Drill navigation

    /// Drill into the equity-sector sub-grid for `parentId`.
    /// Distributes parent allocation evenly across child sectors.
    func drillIn(_ parentId: String) {
        let parentAlloc = allocations[parentId] ?? 0
        let children = sectorAssets.filter { $0.parent == parentId }
        guard !children.isEmpty else { drillParent = parentId; return }

        if parentAlloc > 0 {
            allocations[parentId] = 0
            let share = parentAlloc / Double(children.count)
            for c in children {
                allocations[c.id] = (allocations[c.id] ?? 0) + share
            }
        }
        drillParent = parentId
    }

    /// Collapse sector allocations back into the parent.
    func drillOut() {
        guard let p = drillParent else { return }
        let children = sectorAssets.filter { $0.parent == p }
        let total = children.reduce(0.0) { $0 + (allocations[$1.id] ?? 0) }
        for c in children { allocations[c.id] = 0 }
        allocations[p] = (allocations[p] ?? 0) + total
        drillParent = nil
    }

    // MARK: Playback

    func togglePlay() {
        isPlaying.toggle()
        if isPlaying {
            timer = Timer.publish(every: 0.6, on: .main, tolerance: 0.05, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.tick() }
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    func reset() {
        isPlaying = false
        timer?.cancel()
        timer = nil
        weekIndex = 0
        weeklyReturn = [:]
        for a in allAssets { cumMultiplier[a.id] = 1.0 }
    }

    private func tick() {
        guard weekIndex < totalWeeks else {
            isPlaying = false
            timer?.cancel()
            timer = nil
            return
        }

        var newReturns: [String: Double] = [:]
        for a in allAssets {
            let r = mockReturn(ticker: a.ticker, week: weekIndex)
            newReturns[a.id] = r
            let alloc = allocations[a.id] ?? 0
            if alloc > 0 {
                allocations[a.id] = max(0, alloc * (1 + r))
                cumMultiplier[a.id] = (cumMultiplier[a.id] ?? 1.0) * (1 + r)
            }
        }
        weeklyReturn = newReturns
        weekIndex += 1
    }
}

// MARK: - Sand Canvas
// Animated wave fill rendered with Canvas. `fillFraction` drives the water-line height.
// Uses a phase-animated @State so the wave oscillates continuously.

struct SandCanvas: View {
    let fillFraction: Double  // 0.0 = empty, 1.0 = full box
    let color: Color

    @State private var phase: Double = 0

    var body: some View {
        Canvas { ctx, size in
            guard fillFraction > 0.001 else { return }

            let fillY  = size.height * CGFloat(1.0 - min(1, fillFraction))
            let freq   = 2.0 * Double.pi / Double(size.width) * 1.5

            // Primary wave fill
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for xi in stride(from: 0.0, through: Double(size.width), by: 2) {
                let wave = 4.0 * sin(xi * freq + phase)
                path.addLine(to: CGPoint(x: xi, y: fillY + wave))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            ctx.fill(path, with: .color(color.opacity(0.82)))

            // Lighter shimmer strip at surface
            var shimmer = Path()
            shimmer.move(to: CGPoint(x: 0, y: fillY - 3))
            for xi in stride(from: 0.0, through: Double(size.width), by: 2) {
                let wave = 3.0 * sin(xi * freq + phase + 0.9)
                shimmer.addLine(to: CGPoint(x: xi, y: fillY + wave))
            }
            shimmer.addLine(to: CGPoint(x: size.width, y: fillY - 3))
            shimmer.closeSubpath()
            ctx.fill(shimmer, with: .color(color.opacity(0.35)))
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
}

// MARK: - Asset Box

struct AssetBox: View {
    let asset: AssetInfo
    @ObservedObject var engine: PortfolioEngine

    private var alloc: Double  { engine.allocations[asset.id] ?? 0 }
    private var ret: Double    { engine.weeklyReturn[asset.id] ?? 0 }
    // 25% allocation fills the box visually — keeps boxes readable even at lower weights
    private var fillFraction: Double { min(1.0, alloc / 0.25) }

    private var sandColor: Color {
        switch asset.category {
        case "bond":          return Color(red: 0.85, green: 0.82, blue: 0.62)
        case "commodity":     return Color(red: 0.78, green: 0.56, blue: 0.22)
        case "forex":         return Color(red: 0.55, green: 0.74, blue: 0.88)
        case "realestate":    return Color(red: 0.70, green: 0.54, blue: 0.38)
        case "cash":          return Color(red: 0.88, green: 0.86, blue: 0.72)
        case "equity_sector": return Color(red: 0.92, green: 0.66, blue: 0.28)
        default:              return Color(red: 0.88, green: 0.66, blue: 0.32) // equity
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.10))

            // Sand fill — animated
            SandCanvas(fillFraction: fillFraction, color: sandColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: fillFraction)

            // Weekly-return flash overlay
            if abs(ret) > 0.0005 {
                RoundedRectangle(cornerRadius: 14)
                    .fill((ret > 0 ? Color.green : Color.red).opacity(0.13))
                    .animation(.easeOut(duration: 0.4), value: ret)
            }

            // Border
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    alloc > 0.005 ? sandColor.opacity(0.55) : Color.white.opacity(0.08),
                    lineWidth: 1.5
                )

            // Label stack
            VStack(spacing: 3) {
                Text(asset.emoji).font(.system(size: 26))

                Text(asset.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                if alloc > 0.005 {
                    Text(String(format: "%.0f%%", alloc * 100))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(sandColor)
                }

                if abs(ret) > 0.0005 {
                    Text(String(format: "%+.1f%%", ret * 100))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(ret > 0 ? .green : Color(red: 1, green: 0.4, blue: 0.4))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
        }
        // Double-tap US Equities to drill into sectors
        .onTapGesture(count: 2) {
            if asset.id == "US_EQ" { engine.drillIn(asset.id) }
        }
        // Single tap = pour 5% from bag
        .onTapGesture {
            engine.addSand(asset.id)
        }
        // Long press = drain all sand back to bag
        .onLongPressGesture {
            engine.drainSand(asset.id)
        }
    }
}

// MARK: - Sand Bag Bar
// Visual indicator of unallocated buying power.

struct SandBagBar: View {
    @ObservedObject var engine: PortfolioEngine

    var body: some View {
        HStack(spacing: 10) {
            Text("🪣")
                .font(.system(size: 18))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(white: 0.18))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [
                                Color(red: 0.88, green: 0.68, blue: 0.32),
                                Color(red: 0.96, green: 0.84, blue: 0.54)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * CGFloat(engine.sandBagRemaining))
                        .animation(.spring(response: 0.4), value: engine.sandBagRemaining)
                }
            }
            .frame(height: 12)

            Text(String(format: "%.0f%% free", engine.sandBagRemaining * 100))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.07))
    }
}

// MARK: - Playback Bar

struct PlaybackBar: View {
    @ObservedObject var engine: PortfolioEngine

    var body: some View {
        HStack(spacing: 14) {
            Button { engine.reset() } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16))
                    .foregroundColor(Color(white: 0.55))
            }

            Button { engine.togglePlay() } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(red: 0.92, green: 0.72, blue: 0.28))
            }

            Text("Wk \(engine.weekIndex) / \(engine.totalWeeks)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Color(white: 0.38))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.15))
                    Capsule()
                        .fill(Color(red: 0.92, green: 0.72, blue: 0.28))
                        .frame(
                            width: geo.size.width
                                * CGFloat(engine.weekIndex)
                                / CGFloat(max(1, engine.totalWeeks))
                        )
                        .animation(.linear(duration: 0.1), value: engine.weekIndex)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.07))
    }
}

// MARK: - Nav Bar

struct NavBar: View {
    @ObservedObject var engine: PortfolioEngine

    var body: some View {
        HStack {
            // Back button — only in drill-down
            if engine.drillParent != nil {
                Button { engine.drillOut() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(red: 0.92, green: 0.72, blue: 0.28))
                }
            } else {
                Spacer().frame(width: 70)
            }

            Spacer()

            Text(engine.drillParent == nil ? "Sand Portfolio" : "US Equities")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Spacer()

            // Blind mode badge (placeholder — wires up to mode picker in Phase 2)
            Text("◉ Blind")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.35))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(white: 0.13))
                .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.07))
    }
}

// MARK: - Portfolio Grid

struct PortfolioGrid: View {
    @ObservedObject var engine: PortfolioEngine

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(engine.visibleAssets) { asset in
                    AssetBox(asset: asset, engine: engine)
                        .frame(height: 130)
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Interaction Hint
// Shown once at launch; disappears after first tap.

struct HintBanner: View {
    @Binding var visible: Bool

    var body: some View {
        if visible {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap")
                Text("Tap to pour sand · Long-press to drain · Double-tap US Equities to drill in")
                    .font(.system(size: 11))
            }
            .foregroundColor(Color(white: 0.55))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.09))
            .onTapGesture { withAnimation { visible = false } }
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @StateObject private var engine = PortfolioEngine()
    @State private var showHint = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                NavBar(engine: engine)

                Divider().background(Color(white: 0.15))

                HintBanner(visible: $showHint)

                SandBagBar(engine: engine)

                Divider().background(Color(white: 0.12))

                PortfolioGrid(engine: engine)

                Divider().background(Color(white: 0.12))

                PlaybackBar(engine: engine)
            }
        }
        // Hide hint on first interaction
        .onTapGesture { withAnimation { showHint = false } }
    }
}
