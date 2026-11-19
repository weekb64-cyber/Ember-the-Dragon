import Foundation
import SwiftUI

@MainActor
@Observable
final class GameModel {
    var currentPhase: GamePhase = .welcome
    var configuration = GameConfiguration()
    var calibrationEnvelope = CalibrationEnvelope()
    var stageProgress: Float = 0
    var instructionsVisible = true
    var isDragonAnimating = false
    var shouldOpenImmersiveSpace = false
    var shouldDismissImmersiveSpace = false

    let calibrationManager = CalibrationManager()

    var instructionTitle: String {
        currentPhase.childTitle
    }

    var instructionSubtitle: String {
        currentPhase.childSubtitle
    }

    var progressDotCount: Int {
        switch currentPhase {
        case .reach:
            3
        case .stretch:
            4
        case .pinch:
            configuration.scalePieceCount
        case .rotate:
            2
        case .sweep:
            6
        default:
            0
        }
    }

    var completedDots: Int {
        guard progressDotCount > 0 else { return 0 }
        return min(progressDotCount, Int((stageProgress * Float(progressDotCount)).rounded(.up)))
    }

    func startFromWelcome() {
        shouldOpenImmersiveSpace = true
        transition(to: .calibration)
    }

    func immersiveSpaceOpened() {
        shouldOpenImmersiveSpace = false
    }

    func finish() {
        shouldDismissImmersiveSpace = true
        transition(to: .welcome)
    }

    func immersiveSpaceDismissed() {
        shouldDismissImmersiveSpace = false
    }

    func recordCalibrationTarget(named name: String) {
        calibrationManager.recordTouch(named: name)
        stageProgress = min(1, Float(calibrationManager.touchedTargetNames.count) / 3)
    }

    func completeCalibration() {
        calibrationEnvelope = calibrationManager.envelope(configuration: configuration)
        transition(to: .introduction)
        scheduleAdvance(after: 3.0, to: .reach)
    }

    func skipCalibration() {
        calibrationEnvelope = CalibrationEnvelope(interactionDistance: configuration.interactionDistance)
        transition(to: .introduction)
        scheduleAdvance(after: 3.0, to: .reach)
    }

    func completeCurrentStage() {
        switch currentPhase {
        case .reach:
            transitionWithPause(to: .stretch)
        case .stretch:
            transitionWithPause(to: .pinch)
        case .pinch:
            transitionWithPause(to: .rotate)
        case .rotate:
            transitionWithPause(to: .sweep)
        case .sweep:
            transitionWithPause(to: .celebration, delay: 1.2)
            scheduleAdvance(after: 5.4, to: .complete)
        default:
            break
        }
    }

    func skipCurrentStageForTesting() {
        switch currentPhase {
        case .calibration:
            skipCalibration()
        case .introduction:
            transition(to: .reach)
        case .reach:
            transition(to: .stretch)
        case .stretch:
            transition(to: .pinch)
        case .pinch:
            transition(to: .rotate)
        case .rotate:
            transition(to: .sweep)
        case .sweep:
            transition(to: .celebration)
            scheduleAdvance(after: 4.0, to: .complete)
        case .celebration:
            transition(to: .complete)
        case .welcome, .complete:
            break
        }
    }

    func replay() {
        calibrationManager.reset()
        calibrationEnvelope = CalibrationEnvelope(interactionDistance: configuration.interactionDistance)
        transition(to: .calibration)
    }

    func transition(to phase: GamePhase) {
        currentPhase = phase
        stageProgress = 0
        instructionsVisible = true
    }

    func updateProgress(_ progress: Float) {
        stageProgress = min(max(progress, 0), 1)
    }

    private func transitionWithPause(to phase: GamePhase, delay: TimeInterval = 1.6) {
        instructionsVisible = false
        scheduleAdvance(after: delay, to: phase)
    }

    private func scheduleAdvance(after delay: TimeInterval, to phase: GamePhase) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            transition(to: phase)
        }
    }
}
