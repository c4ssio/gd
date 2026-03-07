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
    var body: some View {
        VStack {
            Image(systemName: "gamecontroller")
                .imageScale(.large)
                .foregroundColor(.accentColor)
            Text("GD Swift")
        }
    }
}
