import SwiftUI

struct InstructionOverlay: View {
    let title: String
    let subtitle: String
    let isVisible: Bool
    let completedDots: Int
    let dotCount: Int

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if dotCount > 0 {
                HStack(spacing: 8) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        Circle()
                            .fill(index < completedDots ? Color.yellow : Color.white.opacity(0.28))
                            .frame(width: 10, height: 10)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(22)
        .frame(maxWidth: 360)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isVisible)
    }
}
