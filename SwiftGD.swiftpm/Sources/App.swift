import SwiftUI

@main
struct SwiftGDApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var jumpCount = 0

    var body: some View {
        VStack(spacing: 32) {
            Text("GD Swift")
                .font(.largeTitle.bold())

            Text("Taps: \(jumpCount)")
                .font(.title2)
                .monospacedDigit()

            Button("JUMP") {
                jumpCount += 1
            }
            .font(.title.bold())
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .background(Color.yellow)
            .foregroundColor(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
    }
}
