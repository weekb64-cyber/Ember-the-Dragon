import SwiftUI

struct CompletionView: View {
    let playAgain: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Ember is ready!")
                .font(.title.bold())
            Text("Thanks for helping Ember fly.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(action: playAgain) {
                    Label("Play Again", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderedProminent)

                Button(action: finish) {
                    Label("Finish", systemImage: "checkmark")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 380)
    }
}
