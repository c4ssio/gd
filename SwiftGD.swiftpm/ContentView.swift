import SwiftUI

struct ContentView: View {
    @State private var ballOffset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 60) {
            Circle()
                .fill(Color.yellow)
                .frame(width: 60, height: 60)
                .offset(y: ballOffset)
                .animation(.interpolatingSpring(stiffness: 120, damping: 8), value: ballOffset)

            Button {
                guard !isAnimating else { return }
                isAnimating = true
                ballOffset = -120
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    ballOffset = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isAnimating = false
                    }
                }
            } label: {
                Text("JUMP")
                    .font(.title.bold())
                    .padding(.horizontal, 40)
                    .padding(.vertical, 16)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
