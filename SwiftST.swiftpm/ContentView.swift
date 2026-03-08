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
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

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

                        // Group context
                        VStack(alignment: .leading, spacing: 10) {
                            Text("About \(series.group)")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color.gray.opacity(0.7))

                            Text(groupDescription(series.group))
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

    private func groupDescription(_ g: String) -> String {
        switch g {
        case "US Sectors":
            return "S&P 500 sector ETFs reveal rotation: risk-on money flows into Technology, Financials, and Discretionary; risk-off rotates into Utilities, Staples, and Healthcare."
        case "Fixed Income":
            return "Government bond ETFs are the classic safe haven. When stocks fall, investors pile in, driving prices up (yields down). Long Bonds (LTB) are most rate-sensitive."
        case "Credit":
            return "Corporate bonds sit between stocks and Treasuries on the risk spectrum. In stress, spreads widen: Junk Bonds (JNK) fall hard while Long Bonds (LTB) rise — the flight-to-safety trade in action."
        case "Volatility":
            return "'Panic' tracks VIX futures and spikes sharply when fear enters the market. In quiet years it decays from contango — it's expensive to hold but invaluable as a crash hedge."
        case "Commodities":
            return "Gold (GLD) is the original safe haven and benefits from fear and dollar weakness. The broad commodity basket (CMD) reflects global growth, energy demand, and inflation expectations."
        case "Forex":
            return "In global risk-off events, investors buy US Dollars (USD) and Japanese Yen (JPY) — both historically safe-haven currencies. The Euro (EUR) often weakens relative to USD in these periods."
        case "International":
            return "Non-US equities. Developed markets (DEV) roughly track US with a lag; Emerging Markets (EMG) add currency and political risk. Both underperform in strong-dollar environments."
        case "Alternatives":
            return "Real Estate Investment Trusts (REI) own income-producing property. They're sensitive to interest rates — they struggle as rates rise but recover strongly when rates fall."
        case "Cash":
            return "Near-cash short-term Treasuries. Earns a small yield with essentially zero duration risk. The 'do nothing' trade — always available as a harbour when everything else is volatile."
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
// MARK: - Game View
// ============================================================

struct GameView: View {
    @ObservedObject var engine: GameEngine
    @State private var selected: AssetSeries? = nil

    let columns = [GridItem(.adaptive(minimum: 82, maximum: 140), spacing: 8)]

    var body: some View {
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
                                    .onTapGesture { selected = series }
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
        .sheet(item: $selected) { s in
            AssetDetailSheet(
                series:    s,
                ytdReturn: engine.ytdReturn(for: s),
                price:     engine.currentPrice(for: s)
            )
            .presentationDetents([.medium, .large])
        }
    }
}

// ============================================================
// MARK: - Root
// ============================================================

struct ContentView: View {
    @StateObject private var engine = GameEngine(data: loadGameData())
    @State private var started = false

    var body: some View {
        Group {
            if started {
                GameView(engine: engine)
            } else {
                IntroView(onStart: { started = true })
            }
        }
        .preferredColorScheme(.dark)
    }
}
