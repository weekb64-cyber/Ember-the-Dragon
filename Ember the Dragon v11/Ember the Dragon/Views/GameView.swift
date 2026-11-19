import SwiftUI

struct GameView: View {
    @Environment(GameModel.self) private var gameModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 18) {
                if gameModel.currentPhase == .complete {
                    CompletionView {
                        gameModel.replay()
                    } finish: {
                        gameModel.finish()
                    }
                } else if gameModel.currentPhase != .welcome {
                    InstructionOverlay(
                        title: gameModel.instructionTitle,
                        subtitle: gameModel.instructionSubtitle,
                        isVisible: gameModel.instructionsVisible,
                        completedDots: gameModel.completedDots,
                        dotCount: gameModel.progressDotCount
                    )

                    if gameModel.currentPhase == .calibration {
                        HStack(spacing: 12) {
                            Button {
                                gameModel.completeCalibration()
                            } label: {
                                Label("Continue", systemImage: "arrow.right.circle.fill")
                            }
                            .disabled(gameModel.stageProgress < 1)

                            Button {
                                gameModel.skipCalibration()
                            } label: {
                                Label("Skip", systemImage: "forward.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .padding()

            if gameModel.currentPhase != .welcome && gameModel.currentPhase != .complete {
                Button {
                    gameModel.skipCurrentStageForTesting()
                } label: {
                    Label("Skip Stage", systemImage: "forward.end.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .padding(20)
                .accessibilityLabel("Skip current stage for testing")
            }
        }
    }
}
