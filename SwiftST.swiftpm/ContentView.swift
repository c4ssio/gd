import SwiftUI

// ============================================================
// MARK: - Data Models
// ============================================================

struct AssetSeries: Identifiable, Decodable {
    let ticker: String
    let code:   String   // 3-letter human code,  e.g. "TEC"
    let name:   String   // human display name,    e.g. "Technology"
    let group:  String   // display group,         e.g. "US Sectors"
    let color:  String   // hex color,             e.g. "#F59E0B"
    let closes: [Double] // one close per bar, index-aligned to GameData.bars
    var id: String { ticker }
}

struct GameData: Decodable {
    let bars:   [String]       // ISO-8601 timestamps, e.g. "2024-01-02T09:30:00"
    let assets: [AssetSeries]
}

struct AssetGroup: Identifiable {
    let name:   String
    let assets: [AssetSeries]
    var id: String { name }
}

// ============================================================
// MARK: - Portfolio
// ============================================================

struct Holding: Identifiable {
    let ticker:      String
    var shares:      Double   // units held (for CASH, 1 share = $1)
    var avgBuyPrice: Double   // weighted avg cost basis
    var buyBarIndex: Int      // bar when first purchased
    var id: String { ticker }
}

final class Portfolio: ObservableObject {
    static let startingCash: Double = 10_000

    @Published var holdings: [String: Holding] = [
        "CASH": Holding(ticker: "CASH", shares: startingCash,
                        avgBuyPrice: 1.0, buyBarIndex: 0)
    ]
    @Published private(set) var totalDividendsReceived: Double = 0

    // MARK: Computed helpers

    func currentValue(ticker: String, prices: [String: Double]) -> Double {
        guard let h = holdings[ticker] else { return 0 }
        return h.shares * (prices[ticker] ?? 1.0)
    }

    func totalValue(prices: [String: Double]) -> Double {
        holdings.keys.reduce(0) { $0 + currentValue(ticker: $1, prices: prices) }
    }

    func fraction(ticker: String, prices: [String: Double]) -> Double {
        let total = totalValue(prices: prices)
        guard total > 0 else { return 0 }
        return currentValue(ticker: ticker, prices: prices) / total
    }

    func returnSinceBuy(ticker: String, prices: [String: Double]) -> Double {
        guard let h = holdings[ticker],
              let price = prices[ticker],
              h.avgBuyPrice > 0 else { return 0 }
        return price / h.avgBuyPrice - 1.0
    }

    // MARK: Dividend accrual

    /// Called once per bar. Drips pro-rated annual yield into CASH.
    func accrueDiv(prices: [String: Double], totalBars: Int) {
        let perBarFactor = 1.0 / Double(totalBars)
        var cashGain = 0.0
        for (ticker, holding) in holdings {
            guard ticker != "CASH" else { continue }
            let yield = dividendYields[ticker] ?? 0.0
            guard yield > 0 else { continue }
            let price = prices[ticker] ?? 0.0
            cashGain += holding.shares * price * yield * perBarFactor
        }
        if cashGain > 0.001 {
            holdings["CASH"]?.shares += cashGain
            totalDividendsReceived += cashGain
        }
    }

    /// Dividends paid by a specific ticker since it was first held (approximate).
    func dividendsPaid(ticker: String, prices: [String: Double], totalBars: Int) -> Double {
        guard let h = holdings[ticker], ticker != "CASH" else { return 0 }
        let yield = dividendYields[ticker] ?? 0.0
        guard yield > 0 else { return 0 }
        let price = prices[ticker] ?? 0.0
        // Rough: current shares × current price × yield × fraction of year held
        let fractionHeld = min(1.0, Double(totalBars - h.buyBarIndex) / Double(totalBars))
        return h.shares * price * yield * fractionHeld
    }

    // MARK: Execute trade

    /// Buy `targetDollars` of `targetTicker` funded by `sources` (ticker → dollars).
    func invest(targetTicker: String, targetDollars: Double,
                sources: [String: Double], prices: [String: Double],
                barIndex: Int) {
        guard targetDollars > 0 else { return }

        // Sell from each source
        for (ticker, dollars) in sources where dollars > 0.01 {
            let price = prices[ticker] ?? 1.0
            guard price > 0 else { continue }
            holdings[ticker]?.shares -= dollars / price
            if let h = holdings[ticker], h.shares < 0.001 {
                holdings.removeValue(forKey: ticker)
            }
        }

        // Buy target — weighted-average cost basis if already held
        let targetPrice = prices[targetTicker] ?? 1.0
        guard targetPrice > 0 else { return }
        let newShares = targetDollars / targetPrice

        if var existing = holdings[targetTicker] {
            let oldCost = existing.shares * existing.avgBuyPrice
            let newCost = newShares * targetPrice
            existing.avgBuyPrice = (oldCost + newCost) / (existing.shares + newShares)
            existing.shares += newShares
            holdings[targetTicker] = existing
        } else {
            holdings[targetTicker] = Holding(ticker: targetTicker, shares: newShares,
                                             avgBuyPrice: targetPrice, buyBarIndex: barIndex)
        }
    }

    /// Sell `sourceDollars` from one holding and distribute across multiple target buckets.
    func reallocate(sourceTicker: String, sourceDollars: Double,
                    targets: [String: Double], prices: [String: Double],
                    barIndex: Int) {
        guard sourceDollars > 0 else { return }
        let srcPrice = prices[sourceTicker] ?? 1.0
        guard srcPrice > 0 else { return }
        holdings[sourceTicker]?.shares -= sourceDollars / srcPrice
        if let h = holdings[sourceTicker], h.shares < 0.001 {
            holdings.removeValue(forKey: sourceTicker)
        }
        for (targetTicker, targetDollars) in targets where targetDollars > 0.01 {
            let tPrice = prices[targetTicker] ?? 1.0
            guard tPrice > 0 else { continue }
            let newShares = targetDollars / tPrice
            if var existing = holdings[targetTicker] {
                let oldCost = existing.shares * existing.avgBuyPrice
                existing.avgBuyPrice = (oldCost + newShares * tPrice) / (existing.shares + newShares)
                existing.shares += newShares
                holdings[targetTicker] = existing
            } else {
                holdings[targetTicker] = Holding(ticker: targetTicker, shares: newShares,
                                                 avgBuyPrice: tPrice, buyBarIndex: barIndex)
            }
        }
    }
}

// ============================================================
// MARK: - Playback Speed
// ============================================================

enum GameSpeed: String, CaseIterable, Identifiable {
    case normal = "Normal"
    case fast   = "Fast"
    var id: String { rawValue }

    /// Seconds between bar advances (Timer interval)
    var tickInterval: Double {
        switch self {
        case .normal: return 1.0          // 1 bar/sec  → 1 hr/sec in sim time
        case .fast:   return 1.0 / 7.0   // 7 bars/sec → 1 day/sec in sim time
        }
    }

    var label: String {
        switch self {
        case .normal: return "1 hr / sec"
        case .fast:   return "1 day / sec"
        }
    }
}

// ============================================================
// MARK: - Game Engine
// ============================================================

final class GameEngine: ObservableObject {
    @Published private(set) var barIndex:  Int       = 0
    @Published private(set) var isRunning: Bool      = false
    @Published              var speed:     GameSpeed = .normal {
        didSet { if isRunning { restartTimer() } }
    }

    let data:   GameData
    let groups: [AssetGroup]
    private var timer: Timer?

    /// Called once per bar advance. Wire up portfolio dividend accrual here.
    var onTick: (() -> Void)?

    init(data: GameData) {
        self.data = data
        // Build ordered groups preserving the JSON asset order
        var seen = [String]()
        var map  = [String: [AssetSeries]]()
        for a in data.assets {
            if map[a.group] == nil { seen.append(a.group); map[a.group] = [] }
            map[a.group]!.append(a)
        }
        groups = seen.map { AssetGroup(name: $0, assets: map[$0]!) }
    }

    // MARK: Derived state

    var totalBars:  Int    { data.bars.count }
    var currentBar: String { data.bars[min(barIndex, totalBars - 1)] }
    var progress:   Double { Double(barIndex) / Double(max(1, totalBars - 1)) }

    func ytdReturn(for s: AssetSeries) -> Double {
        guard !s.closes.isEmpty, s.closes[0] != 0 else { return 0 }
        let now = s.closes[min(barIndex, s.closes.count - 1)]
        return (now - s.closes[0]) / s.closes[0]
    }

    func currentPrice(for s: AssetSeries) -> Double {
        s.closes.isEmpty ? 0 : s.closes[min(barIndex, s.closes.count - 1)]
    }

    func series(for ticker: String) -> AssetSeries? {
        data.assets.first { $0.ticker == ticker }
    }

    /// Unique trading days remaining after the current bar (inclusive of today).
    var tradingDaysRemaining: Int {
        let remaining = data.bars[barIndex...]
        var seen = Set<String>()
        for bar in remaining {
            seen.insert(String(bar.prefix(10)))  // "2024-MM-DD"
        }
        return seen.count
    }

    /// Unique trading days elapsed so far (inclusive of today).
    var tradingDaysElapsed: Int {
        var seen = Set<String>()
        for bar in data.bars[...barIndex] {
            seen.insert(String(bar.prefix(10)))
        }
        return seen.count
    }

    var totalTradingDays: Int {
        var seen = Set<String>()
        for bar in data.bars { seen.insert(String(bar.prefix(10))) }
        return seen.count
    }

    /// Current prices for all market assets + CASH (always 1.0).
    var prices: [String: Double] {
        var d: [String: Double] = ["CASH": 1.0]
        for a in data.assets { d[a.ticker] = currentPrice(for: a) }
        return d
    }

    // MARK: Playback controls

    func togglePlayPause() { isRunning ? pause() : play() }

    func play() {
        guard barIndex < totalBars - 1 else { return }
        isRunning = true
        restartTimer()
    }

    func pause() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func reset() { pause(); barIndex = 0 }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: speed.tickInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let next = self.barIndex + 1
            if next >= self.totalBars - 1 {
                self.barIndex = self.totalBars - 1
                self.pause()
            } else {
                self.barIndex = next
            }
            self.onTick?()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

// ============================================================
// MARK: - Dividend Yields (approximate 2024 trailing 12-month)
// ============================================================

/// Annual dividend / distribution yield for each ticker.
/// Tickers not listed (VXX, GLD, DJP, currency ETFs) pay no dividends.
let dividendYields: [String: Double] = [
    "XLK":      0.007,   // Technology          ~0.7%
    "XLV":      0.016,   // Healthcare          ~1.6%
    "XLF":      0.018,   // Financials          ~1.8%
    "XLY":      0.008,   // Discretionary       ~0.8%
    "XLP":      0.028,   // Staples             ~2.8%
    "XLI":      0.015,   // Industrials         ~1.5%
    "XLE":      0.035,   // Energy              ~3.5%
    "XLU":      0.032,   // Utilities           ~3.2%
    "XLB":      0.020,   // Materials           ~2.0%
    "XLRE":     0.035,   // RE Sector           ~3.5%
    "XLC":      0.009,   // Comm. Svcs          ~0.9%
    "TLT":      0.038,   // Long Bonds          ~3.8% (monthly distributions)
    "SHV":      0.052,   // T-Bills             ~5.2% (Fed funds rate)
    "TIP":      0.025,   // Infl. Bonds         ~2.5%
    "HYG":      0.060,   // Junk Bonds          ~6.0%
    "LQD":      0.045,   // Corp Bonds          ~4.5%
    "EFA":      0.030,   // Intl Stocks         ~3.0%
    "EEM":      0.025,   // Emerging            ~2.5%
    "VNQ":      0.040,   // REITs               ~4.0%
    "SGOV":     0.052,   // Cash                ~5.2% (T-bill rate)
]

// ============================================================
// MARK: - Data Loader
// ============================================================

func loadGameData() -> GameData {
    guard
        let url  = Bundle.main.url(forResource: "game_data", withExtension: "json"),
        let raw  = try? Data(contentsOf: url),
        let data = try? JSONDecoder().decode(GameData.self, from: raw)
    else {
        // Minimal stub so the app renders something useful if data is missing
        return GameData(bars: ["2024-01-02T09:30:00"], assets: [])
    }
    return data
}

// ============================================================
// MARK: - Utilities
// ============================================================

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        self.init(
            red:   Double((n >> 16) & 0xFF) / 255,
            green: Double((n >>  8) & 0xFF) / 255,
            blue:  Double( n        & 0xFF) / 255
        )
    }
}

/// Converts "2024-01-02T09:30:00" → "Jan 2, 2024 · 9:30 AM"
func formatBar(_ bar: String) -> String {
    let parts = bar.split(separator: "T")
    guard parts.count == 2 else { return bar }
    let d = parts[0].split(separator: "-")
    let t = parts[1].split(separator: ":")
    guard d.count == 3, t.count >= 2 else { return bar }

    let months = ["","Jan","Feb","Mar","Apr","May","Jun",
                  "Jul","Aug","Sep","Oct","Nov","Dec"]
    let moIdx = Int(d[1]) ?? 0
    let mo    = moIdx < months.count ? months[moIdx] : ""
    let day   = Int(d[2]) ?? 0
    let yr    = String(d[0])
    var hr    = Int(t[0]) ?? 9
    let mn    = String(t[1])
    let ap    = hr >= 12 ? "PM" : "AM"
    if hr == 0 { hr = 12 } else if hr > 12 { hr -= 12 }

    return "\(mo) \(day), \(yr) · \(hr):\(mn) \(ap)"
}

// ============================================================
// MARK: - Intro Screen
// ============================================================

struct IntroView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#060A12"), Color(hex: "#10172A")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 52) {
                Spacer()

                VStack(spacing: 16) {
                    Text("Sand Trader")
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .yellow, Color(hex: "#E8943A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: .orange.opacity(0.3), radius: 20)

                    Text("Watch 2024's markets unfold in real time")
                        .font(.title3)
                        .foregroundColor(.gray)

                    Text("26 instruments · 261 trading days · hourly bars")
                        .font(.subheadline)
                        .foregroundColor(Color.gray.opacity(0.55))
                }

                Button(action: onStart) {
                    Text("Start Game")
                        .font(.title2.bold())
                        .foregroundColor(.black)
                        .padding(.horizontal, 60)
                        .padding(.vertical, 20)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Capsule())
                        .shadow(color: .orange.opacity(0.55), radius: 24, y: 6)
                }

                Spacer()

                Text("Synthetic data for educational purposes only")
                    .font(.caption2)
                    .foregroundColor(Color.gray.opacity(0.35))
                    .padding(.bottom, 8)
            }
            .padding()
        }
    }
}

// ============================================================
// MARK: - Game Header
// ============================================================

struct GameHeader: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        VStack(spacing: 10) {

            // Title + current timestamp
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Sand Trader")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundColor(.orange)

                Spacer()

                Text(formatBar(engine.currentBar))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Year progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * engine.progress)
                        .animation(
                            .linear(duration: engine.speed.tickInterval * 0.85),
                            value: engine.progress
                        )
                }
            }
            .frame(height: 4)

            // Controls row
            HStack(spacing: 14) {

                // Play / Pause
                Button(action: { engine.togglePlayPause() }) {
                    Image(systemName: engine.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.orange)
                }

                // Back to start
                Button(action: { engine.reset() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 15))
                        .foregroundColor(Color.gray.opacity(0.65))
                }

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 22)

                // Speed label
                Text(engine.speed.label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.gray)

                // Speed picker
                Picker("Speed", selection: $engine.speed) {
                    ForEach(GameSpeed.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)

                Spacer()

                // Bar counter
                Text("\(engine.barIndex + 1) / \(engine.totalBars)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Color.gray.opacity(0.45))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "#0A0F1C"))
    }
}

// ============================================================
// MARK: - Asset Tile
// ============================================================

struct AssetTile: View {
    let series:    AssetSeries
    let ytdReturn: Double

    /// Sand fill level: 0% return = 50% full; ±40% return = 0%/100%.
    /// Ensures a visible sliver even when completely empty.
    var fillRatio: Double {
        max(0.025, min(1.0, 0.5 + ytdReturn / 0.8))
    }

    var returnColor: Color {
        ytdReturn >= 0
            ? Color(red: 0.20, green: 0.90, blue: 0.48)
            : Color(red: 0.95, green: 0.28, blue: 0.32)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // ── Dark tile background ───────────────────────────────────
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "#0D1521"))

            // ── Sand fill rising from the bottom ──────────────────────
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(
                        colors: [
                            Color(hex: series.color).opacity(0.90),
                            Color(hex: series.color).opacity(0.28),
                        ],
                        startPoint: .bottom,
                        endPoint:   .top
                    )
                    .frame(height: geo.size.height * fillRatio)
                    .animation(.spring(duration: 0.38), value: fillRatio)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // ── Label: 3-letter code + return % ───────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Text(series.code)
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.85), radius: 3)

                Text(String(format: "%+.1f%%", ytdReturn * 100))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(returnColor)
                    .shadow(color: .black.opacity(0.85), radius: 2)
            }
            .padding(7)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// ============================================================
// MARK: - Asset Detail Sheet
// ============================================================

struct AssetDetailSheet: View {
    let series:    AssetSeries
    let ytdReturn: Double
    let price:     Double

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#080D18").ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Colour swatch + names
                        HStack(spacing: 16) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: series.color).opacity(0.25))
                                    .frame(width: 60, height: 60)
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color(hex: series.color).opacity(0.6), lineWidth: 1.5)
                                    .frame(width: 60, height: 60)
                                Text(series.code)
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(series.name)
                                    .font(.title2.bold())
                                    .foregroundColor(.white)
                                Text(series.group)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }

                        // Stats row
                        HStack(spacing: 0) {
                            StatBox(
                                label: "YTD Return",
                                value: String(format: "%+.2f%%", ytdReturn * 100),
                                color: ytdReturn >= 0 ? Color(red: 0.2, green: 0.85, blue: 0.5) : .red
                            )
                            Divider().frame(height: 48).opacity(0.2)
                            StatBox(
                                label: "Price",
                                value: String(format: "%.2f", price),
                                color: .white
                            )
                            Divider().frame(height: 48).opacity(0.2)
                            StatBox(
                                label: "Symbol",
                                value: series.ticker,
                                color: .gray
                            )
                        }
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Ticker description
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(series.ticker)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: series.color))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: series.color).opacity(0.15))
                                    .clipShape(Capsule())
                                Text(series.group.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.gray)
                                    .tracking(0.8)
                            }
                            Text(tickerDescription(series.ticker))
                                .font(.body)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Sand fill explanation
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sand level")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.gray.opacity(0.7))

                            Text("The coloured fill rises when year-to-date return is positive and drains when negative. "
                               + "The midpoint (50% fill) represents 0% return. "
                               + "Full = +40% or more. Empty = -40% or worse.")
                                .font(.callout)
                                .foregroundColor(.gray)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(20)
                }
            }
            .navigationTitle(series.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func tickerDescription(_ ticker: String) -> String {
        switch ticker {
        // ── US Sectors ───────────────────────────────────────────────────
        case "XLK":
            return "The S&P 500's largest sector by weight, dominated by Apple, Microsoft, Nvidia, and Meta. Surged through 2024 on AI enthusiasm and blowout earnings. High beta — when the market rips, TEC rips harder; when it sells off, buckle up."
        case "XLV":
            return "Pharma giants, biotech, medical devices, and managed-care insurers. Defensive by nature — people don't stop needing drugs in a recession — but politically sensitive to any noise around drug pricing or insurance reform."
        case "XLF":
            return "Banks, brokerages, insurers, and asset managers. Loves a steep yield curve (cheap to borrow short, profitable to lend long). Watches credit quality closely — a spike in loan defaults hits this sector first."
        case "XLY":
            return "What consumers want but don't need: Amazon, Tesla, Home Depot, restaurants, hotels. Thrives when jobs are plentiful and consumers feel flush. One of the first sectors to crack when recession fears rise."
        case "XLP":
            return "Things people buy no matter what: Procter & Gamble, Coca-Cola, Walmart, Costco. Boring in bull markets but a classic hiding spot when volatility spikes. Steady dividends, predictable cash flows."
        case "XLI":
            return "Aerospace, defense, machinery, railroads, and logistics. Tracks the economic cycle closely and benefits from government infrastructure spending. Union Pacific, Caterpillar, and Boeing are major weights."
        case "XLE":
            return "Oil majors (Exxon, Chevron), refiners, and pipeline operators. Basically a leveraged bet on crude oil prices. Inflation hedge in commodity bull markets, vulnerable when global demand slows or OPEC opens the taps."
        case "XLU":
            return "Electric, gas, and water utilities. Slow revenue growth but fat, reliable dividends make them behave like bonds. Rising interest rates crush this sector (bonds become more attractive competition); falling rates lift it."
        case "XLB":
            return "Mining companies, chemical producers, and packaging firms. A pure cyclical play on global manufacturing and commodity prices. First to rally on a China stimulus headline, first to sell off on recession fears."
        case "XLRE":
            return "Real estate companies and REITs within the S&P 500 — office, retail, data centers, and cell towers. Extremely rate-sensitive: higher rates mean higher cap rates, lower property valuations, and tighter refinancing conditions."
        case "XLC":
            return "A hybrid sector: half growth (Alphabet, Meta dominate through digital advertising) and half legacy value (AT&T, Verizon). Ad revenue is cyclical; telecom is defensive. The two halves often pull in opposite directions."
        // ── Fixed Income ─────────────────────────────────────────────────
        case "TLT":
            return "20+ year US Treasury bonds — the longest duration safe haven available. A 1% drop in long-term yields moves the price roughly +15%; a 1% rise does the opposite. When the market panics, money floods here. When inflation fears dominate, this bleeds."
        case "SHV":
            return "Ultra short-term Treasury bills maturing in 1–3 months. Basically cash with a tiny yield. Almost zero price volatility. In 2024, earning ~5% annualized with zero drama while equity investors rode a rollercoaster."
        case "TIP":
            return "Treasury Inflation-Protected Securities: principal adjusts with CPI, so your real return is preserved. Rallies when inflation expectations rise and when real yields fall. The market's real-time inflation thermometer."
        // ── Credit ───────────────────────────────────────────────────────
        case "HYG":
            return "Bonds from below-investment-grade ('junk') companies — higher yields, higher default risk. In calm markets it quietly pays its coupon; in stress, credit spreads blow out and it sells off nearly as hard as equities. Watch the spread versus Treasuries as a recession indicator."
        case "LQD":
            return "Investment-grade corporate bonds from blue-chip companies like Apple, Microsoft, and JPMorgan. Offers more yield than Treasuries with less risk than junk. Falls when rates rise (duration) and when credit spreads widen (credit risk) — a double threat in stress events."
        // ── Volatility ───────────────────────────────────────────────────
        case "VXX":
            return "Tracks short-term VIX futures — the market's 'fear gauge'. Spikes violently when stocks crash (VIX can double overnight), but bleeds steadily in calm markets due to the cost of rolling futures in contango. Expensive to hold long-term, explosive as a short-term hedge."
        // ── Commodities ──────────────────────────────────────────────────
        case "GLD":
            return "Physical gold held in trust. The oldest store of value on earth — 5,000 years and counting. Rallies on fear, dollar weakness, and real yield declines. Pays no dividends, but protects purchasing power when paper currency looks shaky. Central banks bought record amounts in 2023–24."
        case "DJP":
            return "A broad basket of commodities: energy, metals, and agriculture. A bet on global industrial demand and inflation. China reopening or accelerating tends to be rocket fuel; a US slowdown drains it. Also benefits when the dollar weakens."
        // ── Forex ────────────────────────────────────────────────────────
        case "UUP":
            return "Tracks the US Dollar Index (DXY) against a basket of major currencies. Strengthens when US rates are high relative to peers, or when global panic sends everyone scrambling for dollars. A rising dollar is headwind for commodities, gold, and emerging markets."
        case "EURUSD=X":
            return "Euros per US dollar — the world's most traded currency pair. Weakens when the ECB lags behind the Fed on rates, or when European growth disappoints. Sensitive to energy prices (Europe imports most of its energy) and geopolitical stress on the continent."
        case "JPY=X":
            return "Japanese Yen — the classic carry-trade funding currency. Japan's near-zero rates made the Yen cheap to borrow for years. When carry trades unwind in a global panic, everyone rushes to buy back Yen, causing sharp spikes. A sudden Yen surge is often a signal that risk is being unwound globally."
        // ── International ────────────────────────────────────────────────
        case "EFA":
            return "Developed-market stocks in Europe, Australasia, and the Far East — think Nestlé, Toyota, HSBC, SAP. Broadly tracks US equities with a lag, but currency moves matter. A strong dollar is a headwind; a weak dollar amplifies returns for US investors."
        case "EEM":
            return "Emerging-market stocks spanning China, India, Brazil, Taiwan, South Korea, and more. Higher long-run growth potential than developed markets, but with political risk, currency volatility, and deep sensitivity to US interest rates and dollar strength. When the Fed hikes, money flows out; when it cuts, money pours in."
        // ── Alternatives ─────────────────────────────────────────────────
        case "VNQ":
            return "A broad REIT fund owning apartments, offices, data centers, cell towers, shopping malls, and warehouses. Generous dividend yields, but duration risk is real — higher interest rates directly increase the discount rate on future rental income. Watched carefully as a leading indicator of the commercial real estate cycle."
        // ── Cash ─────────────────────────────────────────────────────────
        case "SGOV":
            return "0–3 month Treasury bills — as close to risk-free as it gets. With the Fed funds rate above 5% in 2024, this 'do nothing' trade was quietly earning more than many active strategies. No drama, no drawdowns, just steady compounding while you wait for a better entry elsewhere."
        default:
            return "Watch how this instrument correlates with the others to identify the current macro regime: risk-on, risk-off, reflation, or flight-to-safety."
        }
    }
}

struct StatBox: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }
}

// ============================================================
// MARK: - Portfolio Views
// ============================================================

struct HoldingRow: View {
    let ticker:    String
    let value:     Double   // current dollar value
    let fraction:  Double   // 0–1 share of total portfolio
    let returnPct: Double   // return since buy (0 for CASH)
    let color:     Color
    let name:      String
    let divPaid:   Double   // estimated dividends paid into cash so far

    private let green = Color(red: 0.2, green: 0.9, blue: 0.48)

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 5, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(ticker == "CASH" ? "Cash" : name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    if ticker != "CASH" {
                        Text(String(format: "%+.1f%% price", returnPct * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(returnPct >= 0 ? green : Color(red: 0.95, green: 0.28, blue: 0.32))
                    } else {
                        Text("Safe haven · always $1")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    if divPaid > 0.001 && value > 0 {
                        Text(String(format: "+%.1f%% div", divPaid / value * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(green.opacity(0.7))
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.0f", value))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text(String(format: "%.1f%%", fraction * 100))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 6)
    }
}

// ── Invest Sheet ─────────────────────────────────────────────

struct InvestSheet: View {
    let target:    AssetSeries
    @ObservedObject var engine:    GameEngine
    @ObservedObject var portfolio: Portfolio
    @Environment(\.dismiss) private var dismiss
    @State private var showDetail = false

    // Step 1: how much to invest (as % of total portfolio)
    @State private var targetPct: Double = 0    // 0–100

    // Step 2: frozen snapshot taken when the user taps "Next"
    @State private var step = 1
    @State private var sourceAlloc: [String: Double] = [:]
    // Optional override so the user can amend the target on step 2
    @State private var amendedTargetDollars: Double? = nil

    // Snapshot types — prices and source values frozen at step-2 entry so
    // live ticks don't shift the math while the user is allocating.
    private struct Snap {
        let prices:        [String: Double]
        let totalValue:    Double
        let targetDollars: Double
        let sources:       [(ticker: String, value: Double, name: String, color: Color)]
    }
    @State private var snap: Snap? = nil

    // Step 1 uses live prices (that's fine — the user hasn't committed yet)
    private var livePrices:        [String: Double] { engine.prices }
    private var liveTotalValue:    Double           { portfolio.totalValue(prices: livePrices) }
    private var liveTargetDollars: Double           { liveTotalValue * targetPct / 100 }

    // Step 2 uses the snapshot exclusively (or an amended override)
    private var targetDollars: Double {
        amendedTargetDollars ?? snap?.targetDollars ?? liveTargetDollars
    }

    private var sources: [(ticker: String, value: Double, name: String, color: Color)] {
        if let s = snap { return s.sources }
        return liveSources(prices: livePrices)
    }

    private func liveSources(prices: [String: Double])
        -> [(ticker: String, value: Double, name: String, color: Color)]
    {
        portfolio.holdings.keys
            .filter { $0 != target.ticker }
            .sorted { a, b in
                if a == "CASH" { return false }
                if b == "CASH" { return true }
                return portfolio.currentValue(ticker: a, prices: prices)
                     > portfolio.currentValue(ticker: b, prices: prices)
            }
            .map { t in
                let val  = portfolio.currentValue(ticker: t, prices: prices)
                let name = t == "CASH" ? "Cash" : (engine.series(for: t)?.name ?? t)
                let clr: Color = t == "CASH"
                    ? Color(hex: "#6B7280")
                    : Color(hex: engine.series(for: t)?.color ?? "#888")
                return (t, val, name, clr)
            }
    }

    private var allocatedTotal: Double {
        sourceAlloc.values.reduce(0, +)
    }

    private var canProceed: Bool {
        step == 1
            ? targetPct > 0
            : targetDollars > 0 && abs(allocatedTotal - targetDollars) < 1.0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#080D18").ignoresSafeArea()

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        Color.clear.frame(height: 0).id("top")
                        // ── Target bucket header (tap for detail) ─────
                        Button(action: { showDetail = true }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(hex: target.color).opacity(0.2))
                                        .frame(width: 52, height: 52)
                                    Text(target.code)
                                        .font(.system(size: 14, weight: .black, design: .monospaced))
                                        .foregroundColor(Color(hex: target.color))
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(target.name)
                                        .font(.title3.bold())
                                        .foregroundColor(.white)
                                    Text(String(format: "Current price: %.2f  ·  YTD %+.1f%%",
                                                engine.currentPrice(for: target),
                                                engine.ytdReturn(for: target) * 100))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "info.circle")
                                    .font(.system(size: 16))
                                    .foregroundColor(Color(hex: target.color).opacity(0.7))
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color(hex: target.color).opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showDetail) {
                            AssetDetailSheet(
                                series:    target,
                                ytdReturn: engine.ytdReturn(for: target),
                                price:     engine.currentPrice(for: target)
                            )
                            .presentationDetents([.medium, .large])
                        }

                        if step == 1 {
                            step1Body
                        } else {
                            step2Body
                        }
                    }
                    .padding(20)
                }
                .onChange(of: step) { _ in
                    withAnimation { proxy.scrollTo("top", anchor: .top) }
                }
                } // ScrollViewReader
            }
            .navigationTitle(step == 1 ? "How much?" : "Fund from")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(step == 1 ? "Cancel" : "Back") {
                        if step == 1 {
                            dismiss()
                        } else {
                            amendedTargetDollars = nil
                            step = 1
                        }
                    }
                    .foregroundColor(.gray)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(step == 1 ? "Next" : "Invest") {
                        if step == 1 {
                            // Freeze everything at this moment
                            let p = livePrices
                            let tv = liveTotalValue
                            snap = Snap(
                                prices:        p,
                                totalValue:    tv,
                                targetDollars: tv * targetPct / 100,
                                sources:       liveSources(prices: p)
                            )
                            sourceAlloc = [:]
                            step = 2
                        } else {
                            portfolio.invest(
                                targetTicker:  target.ticker,
                                targetDollars: targetDollars,
                                sources:       sourceAlloc,
                                prices:        snap?.prices ?? livePrices,
                                barIndex:      engine.barIndex
                            )
                            dismiss()
                        }
                    }
                    .disabled(!canProceed)
                    .foregroundColor(canProceed ? .orange : .gray)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // ── Step 1: pick investment size ─────────────────────────

    private var step1Body: some View {
        VStack(spacing: 20) {
            // Dollar display
            VStack(spacing: 6) {
                Text(String(format: "$%.0f", liveTargetDollars))
                    .font(.system(size: 48, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                Text(String(format: "%.0f%% of your $%.0f portfolio", targetPct, liveTotalValue))
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            // Percentage buttons
            VStack(spacing: 12) {
                ForEach([1.0, 5.0, 10.0, 25.0], id: \.self) { step in
                    HStack(spacing: 10) {
                        pctButton(label: "+\(Int(step))%", delta: step)
                        pctButton(label: "-\(Int(step))%", delta: -step)
                    }
                }
                Button(action: { targetPct = 100 }) {
                    Text("All In")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func pctButton(label: String, delta: Double) -> some View {
        Button(action: {
            targetPct = min(100, max(0, targetPct + delta))
        }) {
            Text(label)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(delta > 0 ? .white : Color(red: 0.95, green: 0.28, blue: 0.32))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // ── Step 2: pick funding sources ─────────────────────────

    private var step2Body: some View {
        VStack(spacing: 16) {
            // Allocation progress
            VStack(spacing: 8) {
                HStack {
                    Text("Allocated")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "$%.0f / $%.0f", allocatedTotal, targetDollars))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(abs(allocatedTotal - targetDollars) < 0.5 ? .green : .white)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule()
                            .fill(LinearGradient(
                                colors: [.orange, .yellow],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * min(1, allocatedTotal / max(1, targetDollars)))
                            .animation(.spring(duration: 0.25), value: allocatedTotal)
                    }
                }
                .frame(height: 5)

                // Accept current amount — lets the user reduce the target to what's already allocated
                if allocatedTotal > 0 && allocatedTotal < targetDollars - 1 {
                    Button(action: {
                        amendedTargetDollars = allocatedTotal
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 12))
                            Text(String(format: "Accept $%.0f", allocatedTotal))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.orange.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.easeInOut(duration: 0.2), value: allocatedTotal)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Source rows
            ForEach(sources, id: \.ticker) { src in
                SourceRow(
                    ticker:       src.ticker,
                    name:         src.name,
                    color:        src.color,
                    holdingValue: src.value,
                    allocated:    sourceAlloc[src.ticker] ?? 0,
                    onAdd: { dollars in
                        let cur   = sourceAlloc[src.ticker] ?? 0
                        // Can't exceed the holding, and can't exceed remaining target budget
                        let budget = targetDollars - allocatedTotal + cur  // budget available for this row
                        sourceAlloc[src.ticker] = min(src.value, min(budget, max(0, cur + dollars)))
                    }
                )
            }

            if sources.isEmpty {
                Text("Nothing to sell — your portfolio only holds this asset.")
                    .font(.callout)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(20)
            }
        }
    }
}

struct SourceRow: View {
    let ticker:       String
    let name:         String
    let color:        Color
    let holdingValue: Double
    let allocated:    Double
    let onAdd:        (Double) -> Void

    private let red = Color(red: 0.95, green: 0.28, blue: 0.32)

    var body: some View {
        VStack(spacing: 10) {
            // ── Header: name + allocated amount ──────────────
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 4, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ticker == "CASH" ? "Cash" : name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(String(format: "Available: $%.0f", holdingValue))
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Text(String(format: "$%.0f", allocated))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(allocated > 0 ? .orange : .gray)
            }

            // ── +/- buttons ──────────────────────────────────
            HStack(spacing: 6) {
                ForEach([5.0, 10.0, 25.0], id: \.self) { pct in
                    // Add
                    Button(action: { onAdd(holdingValue * pct / 100) }) {
                        Text("+\(Int(pct))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    // Subtract
                    Button(action: { onAdd(-(holdingValue * pct / 100)) }) {
                        Text("-\(Int(pct))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            // ── All / Clear ───────────────────────────────────
            HStack(spacing: 8) {
                Button(action: { onAdd(holdingValue) }) {
                    Text("All")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Button(action: { onAdd(-allocated) }) {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.red.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ── Destination Row (used in ReallocateSheet) ─────────────────

struct DestinationRow: View {
    let ticker:      String
    let name:        String
    let code:        String
    let color:       Color
    let curHolding:  Double   // existing position value
    let moveDollars: Double   // total $ being redistributed (for % calc)
    let allocated:   Double   // earmarked for this bucket
    let onAdd:       (Double) -> Void

    private let red = Color(red: 0.95, green: 0.28, blue: 0.32)

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Text(code)
                        .font(.system(size: ticker == "CASH" ? 16 : 10,
                                      weight: .black, design: .monospaced))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ticker == "CASH" ? "Cash" : name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if curHolding > 0.5 {
                        Text(String(format: "Holding: $%.0f", curHolding))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Text(allocated > 0.5 ? String(format: "$%.0f", allocated) : "—")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(allocated > 0.5 ? .orange : Color.gray.opacity(0.4))
            }

            // +/- buttons as % of moveDollars
            HStack(spacing: 6) {
                ForEach([10.0, 25.0, 50.0], id: \.self) { pct in
                    Button(action: { onAdd(moveDollars * pct / 100) }) {
                        Text("+\(Int(pct))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Button(action: { onAdd(-(moveDollars * pct / 100)) }) {
                        Text("-\(Int(pct))%")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(allocated > 0.5 ? red : red.opacity(0.3))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(allocated > 0.5 ? 0.07 : 0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack(spacing: 8) {
                // "Rest" — fills this bucket with all unallocated dollars
                Button(action: { onAdd(moveDollars) }) {
                    Text("Rest")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Button(action: { onAdd(-allocated) }) {
                    Text("Clear")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(allocated > 0.5 ? red : Color.gray.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.red.opacity(allocated > 0.5 ? 0.10 : 0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// ── Reallocate Sheet ──────────────────────────────────────────

struct ReallocateSheet: View {
    let sourceTicker: String
    @ObservedObject var engine:    GameEngine
    @ObservedObject var portfolio: Portfolio
    @Environment(\.dismiss) private var dismiss

    @State private var snapPrices:     [String: Double] = [:]
    @State private var snapSourceVal:  Double = 0
    @State private var movePct:        Double = 100
    @State private var targetAlloc:    [String: Double] = [:]
    @State private var amendedDollars: Double? = nil

    private var sourceColor: Color {
        sourceTicker == "CASH"
            ? Color(hex: "#6B7280")
            : Color(hex: engine.series(for: sourceTicker)?.color ?? "#888")
    }
    private var sourceName: String {
        sourceTicker == "CASH" ? "Cash" : (engine.series(for: sourceTicker)?.name ?? sourceTicker)
    }
    private var sourceCode: String {
        sourceTicker == "CASH" ? "$" : (engine.series(for: sourceTicker)?.code ?? sourceTicker)
    }

    private var moveDollars: Double {
        amendedDollars ?? snapSourceVal * movePct / 100
    }
    private var allocatedTotal: Double { targetAlloc.values.reduce(0, +) }
    private var remaining:      Double { max(0, moveDollars - allocatedTotal) }
    private var canConfirm:     Bool   {
        moveDollars > 0 && abs(allocatedTotal - moveDollars) < 1.0
    }

    private var groupedDests: [(group: String, assets: [AssetSeries])] {
        var seen = [String]()
        var map  = [String: [AssetSeries]]()
        for a in engine.data.assets where a.ticker != sourceTicker {
            if map[a.group] == nil { seen.append(a.group); map[a.group] = [] }
            map[a.group]!.append(a)
        }
        return seen.map { (group: $0, assets: map[$0]!) }
    }

    private let green = Color(red: 0.2, green: 0.9, blue: 0.48)
    private let red   = Color(red: 0.95, green: 0.28, blue: 0.32)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#080D18").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        sourceCard
                        moveCard
                        progressCard

                        // Cash destination (available when source is not CASH)
                        if sourceTicker != "CASH" {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("SAFE HAVEN")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.gray)
                                    .tracking(1)
                                    .padding(.horizontal, 2)
                                makeDestRow(ticker: "CASH", name: "Cash",
                                            code: "$", color: Color(hex: "#6B7280"))
                            }
                        }

                        // All asset groups
                        ForEach(groupedDests, id: \.group) { sec in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(sec.group.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.gray)
                                    .tracking(1)
                                    .padding(.horizontal, 2)
                                ForEach(sec.assets, id: \.ticker) { asset in
                                    makeDestRow(ticker: asset.ticker,
                                                name:   asset.name,
                                                code:   asset.code,
                                                color:  Color(hex: asset.color))
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Redistribute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.gray)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Confirm") {
                        portfolio.reallocate(
                            sourceTicker:  sourceTicker,
                            sourceDollars: moveDollars,
                            targets:       targetAlloc,
                            prices:        snapPrices,
                            barIndex:      engine.barIndex
                        )
                        dismiss()
                    }
                    .disabled(!canConfirm)
                    .foregroundColor(canConfirm ? .orange : .gray)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let p = engine.prices
                snapPrices    = p
                snapSourceVal = portfolio.currentValue(ticker: sourceTicker, prices: p)
            }
        }
    }

    // ── Source header card ────────────────────────────────────
    private var sourceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(sourceColor.opacity(0.18))
                    .frame(width: 50, height: 50)
                Text(sourceCode)
                    .font(.system(size: sourceTicker == "CASH" ? 20 : 13,
                                  weight: .black, design: .monospaced))
                    .foregroundColor(sourceColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sourceName)
                    .font(.title3.bold())
                    .foregroundColor(.white)
                let ret = portfolio.returnSinceBuy(ticker: sourceTicker, prices: snapPrices)
                if sourceTicker != "CASH" {
                    Text(String(format: "%+.1f%% return since buy", ret * 100))
                        .font(.caption)
                        .foregroundColor(ret >= 0 ? green : red)
                } else {
                    Text("Safe haven · always $1")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.0f", snapSourceVal))
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("position")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(sourceColor.opacity(0.2), lineWidth: 1))
    }

    // ── How much to move card ─────────────────────────────────
    private var moveCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Redistributing")
                    .font(.caption).foregroundColor(.gray)
                Spacer()
                Text(String(format: "$%.0f  (%.0f%% of position)", moveDollars, movePct))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
            HStack(spacing: 8) {
                ForEach([25.0, 50.0, 75.0, 100.0], id: \.self) { p in
                    let isActive = movePct == p && amendedDollars == nil
                    Button(action: {
                        amendedDollars = nil
                        movePct = p
                        clampAllocs(to: snapSourceVal * p / 100)
                    }) {
                        Text(p == 100 ? "All" : "\(Int(p))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isActive ? .black : (p == 100 ? .orange : .white))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isActive
                                ? (p == 100 ? Color.orange : Color.white.opacity(0.85))
                                : (p == 100 ? Color.orange.opacity(0.12) : Color.white.opacity(0.08)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // ── Allocation progress card ──────────────────────────────
    private var progressCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Distributed")
                    .font(.caption).foregroundColor(.gray)
                Spacer()
                Text(String(format: "$%.0f / $%.0f", allocatedTotal, moveDollars))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(canConfirm ? green : .white)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(colors: [.orange, .yellow],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(1, allocatedTotal / max(1, moveDollars)))
                        .animation(.spring(duration: 0.25), value: allocatedTotal)
                }
            }
            .frame(height: 5)
            if allocatedTotal > 0 && allocatedTotal < moveDollars - 1 {
                Button(action: { amendedDollars = allocatedTotal }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle").font(.system(size: 12))
                        Text(String(format: "Move only $%.0f", allocatedTotal))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.orange.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .animation(.easeInOut(duration: 0.2), value: allocatedTotal)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // ── Build a single DestinationRow ─────────────────────────
    @ViewBuilder
    private func makeDestRow(ticker: String, name: String,
                             code: String, color: Color) -> some View {
        let alloc  = targetAlloc[ticker] ?? 0
        let curVal = portfolio.currentValue(ticker: ticker, prices: snapPrices)
        DestinationRow(
            ticker:      ticker,
            name:        name,
            code:        code,
            color:       color,
            curHolding:  curVal,
            moveDollars: moveDollars,
            allocated:   alloc,
            onAdd: { delta in
                let cur    = targetAlloc[ticker] ?? 0
                let budget = remaining + cur
                let next   = min(budget, max(0, cur + delta))
                if next < 0.01 { targetAlloc.removeValue(forKey: ticker) }
                else            { targetAlloc[ticker] = next }
            }
        )
    }

    private func clampAllocs(to newMax: Double) {
        var used = 0.0
        var result: [String: Double] = [:]
        for (t, v) in targetAlloc {
            let take = min(v, max(0, newMax - used))
            if take > 0.01 { result[t] = take; used += take }
        }
        targetAlloc = result
    }
}

// ── Portfolio Page ────────────────────────────────────────────

struct PortfolioView: View {
    @ObservedObject var engine:    GameEngine
    @ObservedObject var portfolio: Portfolio

    @State private var reallocateTicker: String? = nil

    private var prices: [String: Double] { engine.prices }
    private var total:  Double           { portfolio.totalValue(prices: prices) }

    private var rows: [(ticker: String, value: Double, fraction: Double, ret: Double, color: Color, name: String)] {
        portfolio.holdings.keys
            .sorted { a, b in
                if a == "CASH" { return false }
                if b == "CASH" { return true }
                return portfolio.currentValue(ticker: a, prices: prices)
                     > portfolio.currentValue(ticker: b, prices: prices)
            }
            .map { t in
                let val  = portfolio.currentValue(ticker: t, prices: prices)
                let frac = total > 0 ? val / total : 0
                let ret  = t == "CASH" ? 0.0 : portfolio.returnSinceBuy(ticker: t, prices: prices)
                let name = t == "CASH" ? "Cash" : (engine.series(for: t)?.name ?? t)
                let clr: Color = t == "CASH"
                    ? Color(hex: "#6B7280")
                    : Color(hex: engine.series(for: t)?.color ?? "#888")
                return (t, val, frac, ret, clr, name)
            }
    }

    var body: some View {
        ZStack {
            Color(hex: "#070B12").ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Total value header ────────────────────────────
                VStack(spacing: 0) {
                    // Date + days remaining strip
                    HStack {
                        Text(formatBar(engine.currentBar))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.gray)
                        Spacer()
                        let daysLeft = engine.tradingDaysRemaining
                        let daysGone = engine.tradingDaysElapsed
                        let total2   = engine.totalTradingDays
                        Text("\(daysLeft) trading day\(daysLeft == 1 ? "" : "s") left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(daysLeft <= 20 ? .orange : .gray)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 10)

                    // Year progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.07))
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.orange, .yellow],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * engine.progress)
                                .animation(.linear(duration: engine.speed.tickInterval * 0.85),
                                           value: engine.progress)
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                    Divider().opacity(0.08)

                    // Portfolio value + P&L
                    VStack(spacing: 6) {
                        Text("Portfolio Value")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                            .tracking(1)
                        Text(String(format: "$%.0f", total))
                            .font(.system(size: 42, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .contentTransition(.numericText())

                        let pnl = total - Portfolio.startingCash
                        let ret = pnl / Portfolio.startingCash
                        let pnlColor: Color = ret >= 0
                            ? Color(red: 0.2, green: 0.9, blue: 0.48)
                            : Color(red: 0.95, green: 0.28, blue: 0.32)

                        HStack(spacing: 12) {
                            Text(String(format: "%+$%.0f", pnl))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(pnlColor)
                            Text(String(format: "(%+.2f%%)", ret * 100))
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(pnlColor.opacity(0.75))
                        }

                        // Dividends received
                        if portfolio.totalDividendsReceived > 0.5 {
                            HStack(spacing: 5) {
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(red: 0.2, green: 0.9, blue: 0.48))
                                Text(String(format: "%.2f%% yield collected",
                                            portfolio.totalDividendsReceived / Portfolio.startingCash * 100))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(Color(red: 0.2, green: 0.9, blue: 0.48).opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.2, green: 0.9, blue: 0.48).opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity)
                .background(Color(hex: "#0A0F1C"))

                // ── Allocation bar ────────────────────────────────
                if !rows.isEmpty {
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(rows, id: \.ticker) { row in
                                if row.fraction > 0.01 {
                                    row.color
                                        .frame(width: geo.size.width * row.fraction)
                                }
                            }
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                // ── Holdings list ─────────────────────────────────
                ZStack(alignment: .bottom) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(rows, id: \.ticker) { row in
                                Button(action: { reallocateTicker = row.ticker }) {
                                    HoldingRow(
                                        ticker:     row.ticker,
                                        value:      row.value,
                                        fraction:   row.fraction,
                                        returnPct:  row.ret,
                                        color:      row.color,
                                        name:       row.name,
                                        divPaid:    portfolio.dividendsPaid(
                                                        ticker:     row.ticker,
                                                        prices:     prices,
                                                        totalBars:  engine.totalBars)
                                    )
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .padding(.horizontal, 16)
                                Divider().opacity(0.1).padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                }
            }
        }
        .sheet(isPresented: Binding(
            get: { reallocateTicker != nil },
            set: { if !$0 { reallocateTicker = nil } }
        )) {
            if let t = reallocateTicker {
                ReallocateSheet(sourceTicker: t, engine: engine, portfolio: portfolio)
            }
        }
    }
}

// ============================================================
// MARK: - Game View
// ============================================================

struct GameView: View {
    @ObservedObject var engine:    GameEngine
    @ObservedObject var portfolio: Portfolio
    @State private var investTarget: AssetSeries? = nil

    let columns = [GridItem(.adaptive(minimum: 82, maximum: 140), spacing: 8)]

    var body: some View {
        TabView {
            // ── Tab 1: Market ─────────────────────────────────
            ZStack {
                Color(hex: "#070B12").ignoresSafeArea()

                VStack(spacing: 0) {
                    GameHeader(engine: engine)

                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(engine.groups) { group in
                                Section {
                                    ForEach(group.assets) { series in
                                        AssetTile(
                                            series:    series,
                                            ytdReturn: engine.ytdReturn(for: series)
                                        )
                                        .onTapGesture { investTarget = series }
                                    }
                                } header: {
                                    Text(group.name.uppercased())
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(Color.gray.opacity(0.55))
                                        .tracking(1.2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 16)
                                        .padding(.bottom, 2)
                                }
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .tabItem { Label("Market", systemImage: "chart.bar.fill") }

            // ── Tab 2: Portfolio ──────────────────────────────
            PortfolioView(engine: engine, portfolio: portfolio)
                .tabItem { Label("Portfolio", systemImage: "briefcase.fill") }
        }
        .sheet(item: $investTarget) { s in
            InvestSheet(target: s, engine: engine, portfolio: portfolio)
                .presentationDetents([.large])
        }
    }
}

// ============================================================
// MARK: - Root
// ============================================================

struct ContentView: View {
    @StateObject private var engine    = GameEngine(data: loadGameData())
    @StateObject private var portfolio = Portfolio()
    @State private var started = false

    var body: some View {
        Group {
            if started {
                GameView(engine: engine, portfolio: portfolio)
            } else {
                IntroView(onStart: { started = true })
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.onTick = { [weak engine] in
                guard let engine else { return }
                portfolio.accrueDiv(prices: engine.prices, totalBars: engine.totalBars)
            }
        }
    }
}
