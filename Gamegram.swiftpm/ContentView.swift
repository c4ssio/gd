import SwiftUI
import CryptoKit

// ============================================================
// MARK: - Configuration
// ============================================================

let kAPIBase = "http://100.51.90.226"

// ============================================================
// MARK: - Models
// ============================================================

struct Game: Identifiable, Codable {
    let trackId:      Int
    let name:         String
    let developer:    String
    let genre:        String
    let rating:       Double
    let ratingCount:  Int
    let iconUrl:      String
    let storeUrl:     String
    let adScore:      Double
    let qualityScore: Double
    let signals:      [String]
    let curatorNote:  String
    var voteScore:    Int

    var id: Int { trackId }

    enum CodingKeys: String, CodingKey {
        case trackId      = "track_id"
        case name, developer, genre, rating
        case ratingCount  = "rating_count"
        case iconUrl      = "icon_url"
        case storeUrl     = "store_url"
        case adScore      = "ad_score"
        case qualityScore = "quality_score"
        case signals
        case curatorNote  = "curator_note"
        case voteScore    = "vote_score"
    }
}

struct CatalogResponse: Codable {
    let games: [Game]
    let count: Int
}

struct VoteResponse: Codable {
    let status:    String
    let voteScore: Int
    enum CodingKeys: String, CodingKey {
        case status
        case voteScore = "vote_score"
    }
}

// ============================================================
// MARK: - Vote Token (anonymous, stored locally)
// ============================================================

/// Generates a random UUID on first launch, stores it in UserDefaults,
/// and exposes a SHA-256 hash to send to the server.
/// The server never sees the raw token — only the hash.
struct VoteToken {
    static let key = "gg_vote_token"

    static var raw: String {
        if let t = UserDefaults.standard.string(forKey: key) { return t }
        let t = UUID().uuidString
        UserDefaults.standard.set(t, forKey: key)
        return t
    }

    static var hash: String {
        let data = Data(raw.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// ============================================================
// MARK: - Store
// ============================================================

@MainActor
final class CatalogStore: ObservableObject {
    @Published var games:     [Game]   = []
    @Published var isLoading: Bool     = false
    @Published var error:     String?
    @Published var myVotes:   [Int: Int] = [:]   // trackId → 1 or -1

    func fetch() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        guard let url = URL(string: "\(kAPIBase)/api/catalog.json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(CatalogResponse.self, from: data)
            games = resp.games
        } catch {
            self.error = error.localizedDescription
        }
    }

    func vote(game: Game, value: Int) async {
        // Toggle: voting same way again cancels the vote
        let current = myVotes[game.trackId]
        let newValue = (current == value) ? -value : value

        guard let url = URL(string: "\(kAPIBase)/api/vote") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "token_hash": VoteToken.hash,
            "track_id":   game.trackId,
            "vote":       newValue
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let resp = try JSONDecoder().decode(VoteResponse.self, from: data)
            myVotes[game.trackId] = newValue
            // Update vote score in-place
            if let idx = games.firstIndex(where: { $0.trackId == game.trackId }) {
                games[idx].voteScore = resp.voteScore
            }
        } catch {
            // Vote failed silently — optimistic UI not applied
        }
    }
}

// ============================================================
// MARK: - Content View
// ============================================================

struct ContentView: View {
    @StateObject private var store = CatalogStore()
    @State private var searchText = ""
    @State private var selectedGenre: String? = nil

    var genres: [String] {
        let all = store.games.map(\.genre)
        return Array(Set(all)).sorted()
    }

    var filtered: [Game] {
        store.games.filter { game in
            let matchesSearch = searchText.isEmpty ||
                game.name.localizedCaseInsensitiveContains(searchText) ||
                game.developer.localizedCaseInsensitiveContains(searchText)
            let matchesGenre = selectedGenre == nil || game.genre == selectedGenre
            return matchesSearch && matchesGenre
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()

                if store.isLoading {
                    ProgressView()
                        .tint(.purple)
                } else if let err = store.error {
                    ErrorView(message: err) {
                        Task { await store.fetch() }
                    }
                } else if store.games.isEmpty {
                    EmptyStateView()
                } else {
                    gameList
                }
            }
            .navigationTitle("Gamegram")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(red: 0.1, green: 0.1, blue: 0.13), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.fetch() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.purple)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search games…")
            .preferredColorScheme(.dark)
        }
        .task { await store.fetch() }
    }

    var gameList: some View {
        ScrollView {
            // Genre filter chips
            if !genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        GenreChip(label: "All", selected: selectedGenre == nil) {
                            selectedGenre = nil
                        }
                        ForEach(genres, id: \.self) { genre in
                            GenreChip(label: genre, selected: selectedGenre == genre) {
                                selectedGenre = (selectedGenre == genre) ? nil : genre
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
            }

            LazyVStack(spacing: 12) {
                ForEach(filtered) { game in
                    GameCard(game: game, myVote: store.myVotes[game.trackId]) { value in
                        Task { await store.vote(game: game, value: value) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }
}

// ============================================================
// MARK: - Game Card
// ============================================================

struct GameCard: View {
    let game:   Game
    let myVote: Int?
    let onVote: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                AsyncImage(url: URL(string: game.iconUrl)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(white: 0.15))
                        .overlay(Image(systemName: "gamecontroller.fill")
                            .foregroundColor(.gray))
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    Text(game.developer)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.55))

                    HStack(spacing: 6) {
                        Label(String(format: "%.1f", game.rating), systemImage: "star.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)

                        Text("(\(game.ratingCount.formatted()))")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.45))

                        Spacer()

                        VerdictBadge(adScore: game.adScore)
                    }
                }
            }
            .padding(14)

            // Genre + curator note
            if !game.curatorNote.isEmpty || true {
                HStack(spacing: 8) {
                    Text(game.genre)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(white: 0.12))
                        .clipShape(Capsule())

                    if !game.curatorNote.isEmpty {
                        Text(game.curatorNote)
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider().background(Color(white: 0.15))

            // Action row
            HStack(spacing: 0) {
                // Vote up
                VoteButton(
                    icon: "hand.thumbsup.fill",
                    count: max(0, game.voteScore),
                    active: myVote == 1,
                    activeColor: .green
                ) { onVote(1) }

                Divider().frame(width: 1).background(Color(white: 0.15))

                // Vote down
                VoteButton(
                    icon: "hand.thumbsdown.fill",
                    count: max(0, -game.voteScore),
                    active: myVote == -1,
                    activeColor: .red
                ) { onVote(-1) }

                Divider().frame(width: 1).background(Color(white: 0.15))

                // Open in App Store
                Button {
                    if let url = URL(string: game.storeUrl) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                        Text("App Store")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.purple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(Color(red: 0.1, green: 0.1, blue: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(white: 0.18), lineWidth: 1)
        )
    }
}

// ============================================================
// MARK: - Supporting Views
// ============================================================

struct VerdictBadge: View {
    let adScore: Double
    var isRewarded: Bool { adScore >= 0.25 }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: isRewarded ? "play.rectangle.fill" : "star.fill")
                .font(.system(size: 9))
            Text(isRewarded ? "Watch & Earn" : "Quality F2P")
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(isRewarded ? .green : .cyan)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isRewarded ? Color.green : Color.cyan).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct VoteButton: View {
    let icon:        String
    let count:       Int
    let active:      Bool
    let activeColor: Color
    let action:      () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundColor(active ? activeColor : Color(white: 0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

struct GenreChip: View {
    let label:    String
    let selected: Bool
    let action:   () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : Color(white: 0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selected ? Color.purple : Color(white: 0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        selected ? Color.purple : Color(white: 0.2),
                        lineWidth: 1
                    )
                )
        }
    }
}

struct ErrorView: View {
    let message: String
    let retry:   () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundColor(Color(white: 0.4))
            Text("Couldn't load games")
                .font(.headline)
                .foregroundColor(.white)
            Text(message)
                .font(.caption)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
        }
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 48))
                .foregroundColor(Color(white: 0.25))
            Text("No games yet")
                .font(.headline)
                .foregroundColor(Color(white: 0.5))
            Text("Games approved by the curator\nwill appear here.")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.35))
                .multilineTextAlignment(.center)
        }
    }
}
