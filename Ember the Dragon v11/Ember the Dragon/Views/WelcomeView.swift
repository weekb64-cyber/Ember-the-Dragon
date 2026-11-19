import SwiftUI

struct WelcomeView: View {
    let startAction: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Text("Meet Ember")
                    .font(.largeTitle.bold())
                Text("Ember needs a little help getting ready.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(action: startAction) {
                Label("Let's Play", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(42)
        .frame(minWidth: 420, minHeight: 280)
    }
}
