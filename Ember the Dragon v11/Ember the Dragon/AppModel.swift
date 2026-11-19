import SwiftUI
import RealityKit

@MainActor
@Observable
final class AppModel {
    let launcherWindowID = "LauncherWindow"
    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
}

enum GamePhase: String, CaseIterable, Equatable {
    case introduction
    case magicSetup
    case bilateralSetup
    case precisionSetup
    case horns
    case wings
    case scales
    case hornAlignment
    case painting
    case celebration
    case complete
    case paused

    var instructionTitle: String {
        switch self {
        case .introduction: "Meet Ember"
        case .magicSetup: "Find your comfortable reach"
        case .bilateralSetup: "Open both wings"
        case .precisionSetup: "Create a pattern"
        case .horns: "Attach the horns"
        case .wings: "Open both wings"
        case .scales: "Create a pattern"
        case .hornAlignment: "Turn the horns"
        case .painting: "Paint your design"
        case .celebration: "Design complete"
        case .complete: "Design complete"
        case .paused: "Taking a break?"
        }
    }
}

enum ReachAreaSetting: String, CaseIterable, Hashable {
    case close = "Close"
    case calibrated = "Calibrated"
    case wide = "Wide"
}

enum MovementAmountSetting: String, CaseIterable, Hashable {
    case gentle = "Gentle"
    case standard = "Standard"
}

enum TextSizeSetting: String, CaseIterable, Hashable {
    case standard = "Standard"
    case large = "Large"
}

enum ParticleEffectsSetting: String, CaseIterable, Hashable {
    case normal = "Normal"
    case reduced = "Reduced"
}

struct ComfortSettings {
    var reachArea: ReachAreaSetting = .calibrated
    var movementAmount: MovementAmountSetting = .standard
    var textSize: TextSizeSetting = .standard
    var soundEnabled = true
    var particleEffects: ParticleEffectsSetting = .normal
}

struct SpatialLayoutConfiguration {
    var dragonLeftPosition = SIMD3<Float>(-0.48, 0.20, -0.03)
    var dragonCenterPosition = SIMD3<Float>(0, 0.23, 0)
    var dragonRightPosition = SIMD3<Float>(0.48, 0.20, -0.03)
    var nestPosition = SIMD3<Float>(0, -0.09, 0)
    var objectDepth: Float = 0.14
    var sparkDepth: Float = 0.08
    var brushSpawnPosition = SIMD3<Float>(0.42, -0.08, -0.02)
}

struct GameConfiguration {
    var layout = SpatialLayoutConfiguration()
    var snapDistance: Float = 0.22
    var scaleSnapDistance: Float = 0.2
    var rotationToleranceDegrees: Float = 15
    var wingCompletionThreshold: Float = 0.78
    var minimumPaintStroke: Float = 0.06
    var objectResetDistance: Float = 1.0
    var fineMotorHitTargetMultiplier: Float = 1
}

struct ReachEnvelope {
    var minX: Float = -0.36
    var maxX: Float = 0.36
    var minY: Float = -0.16
    var maxY: Float = 0.32

    func position(x fractionX: Float, y fractionY: Float, depth: Float) -> SIMD3<Float> {
        [
            minX + (maxX - minX) * fractionX,
            minY + (maxY - minY) * fractionY,
            -depth
        ]
    }
}

@MainActor
@Observable
final class GameModel {
    var currentPhase: GamePhase = .introduction
    var previousPhaseBeforePause: GamePhase = .introduction
    var configuration = GameConfiguration()
    var comfortSettings = ComfortSettings()
    var reachEnvelope = ReachEnvelope()
    var collectedSparkOriginalPositions: [SIMD3<Float>] = []
    var comfortableBilateralSpan: Float = 0.42
    var isSceneReady = false
    var isLoadingAssets = false
    var assetLoadError: String?
    var shouldOpenImmersiveSpace = false
    var shouldDismissImmersiveSpace = false
    var isPaused = false
    var phaseRevision = 0
    var restartRevision = 0
    var sessionRevision = 0
    var isRestartingStage = false
    var hasCompletedSetupThisSession = false

    var textScale: CGFloat {
        comfortSettings.textSize == .large ? 1.14 : 1
    }

    var setupButtonTitle: String {
        switch currentPhase {
        case .magicSetup: "Ready!"
        case .bilateralSetup: "That Feels Good"
        case .precisionSetup: "Continue"
        default: "Continue"
        }
    }

    var soundEffectsEnabled = UserDefaults.standard.object(forKey:"EmberSoundEffects") as? Bool ?? true
    var sceneSize: Float = 1
    var isPhotoBoothPresented = false
    var hornGripRequest: Int? = nil
    var hornGripRevision = 0
    func requestHornGrip(_ side: Int?) { hornGripRequest = side; hornGripRevision += 1 }
    func preparePhotoBooth() {
        guard activePhase == .celebration || activePhase == .complete else { return }
        if currentPhase == .celebration { advanceSetupOrStage() }
        isPhotoBoothPresented = true
    }
    var recenterRevision = 0
    var reachSamples: [SIMD3<Float>] = []
    var hasPhysicalCalibration = false
    var calibrationIsSimulated = false
    var calibrationIsPreparing = false
    var calibrationMessage = "Rest one open hand comfortably."
    var simulatedHandDepth: Float = 0
    var stageReady = false
    var activityHint = ""
    var paintingComplete = false
    var hornLeftFill: Float = 0
    var hornRightFill: Float = 0
    var hornLeftCue = "Follow lights"
    var hornRightCue = "Follow lights"
    var scaleDesign: [ScaleDecoration] = []
    var scaleShape: ScaleShape = .leaf
    var scaleTurn = 0
    var scaleUndoRevision = 0
    var photoSessionID = UUID()
    var wingLeftFill: Float = 0
    var wingRightFill: Float = 0
    var wingLeftCue = "Open"
    var wingRightCue = "Open"
    var calibrationStep = 0
    var calibrationHold: Float = 0
    var scaleRotation: Float = 0
    var paletteRevision = 0
    var paletteIndex = 0
    var palette: [PaintChoice] { PaintChoice.palettes[paletteIndex] }
    func randomizePalette() {
        paletteIndex = PaintChoice.nextPalette(after: paletteIndex)
        selectedPaint = palette[0]
        paletteRevision += 1
    }
    var selectedPaint: PaintChoice = .teal
    var regionPaint: [PaintRegion:PaintChoice] = [:]
    var paintingFill: Float = 0
    var paintingRegion = "Head"
    var appliedPaint: PaintChoice?
    var isReachSetupReady: Bool { reachSamples.count >= 7 }
    static let playablePhases: [GamePhase] = [.introduction, .magicSetup, .horns, .wings, .scales, .hornAlignment, .painting, .celebration, .complete]
    var activePhase: GamePhase { isPaused ? previousPhaseBeforePause : currentPhase }
    var canGoBack: Bool { (Self.playablePhases.firstIndex(of: activePhase) ?? 0) > 0 }
    func goBackStage() {
        guard let index = Self.playablePhases.firstIndex(of: activePhase), index > 0 else { return }
        isRestartingStage = true
        transition(to: Self.playablePhases[index-1])
    }

    func markStageReady(_ message: String) {
        guard !stageReady else { return }
        stageReady = true
        activityHint = message
    }

    func startGame() {
        guard !shouldOpenImmersiveSpace, !isSceneReady else { return }
        sessionRevision += 1
        scaleDesign = []
        photoSessionID = UUID()
        appliedPaint = nil; regionPaint = [:]
        paintingComplete = false
        shouldOpenImmersiveSpace = true
        transition(to: hasCompletedSetupThisSession ? .horns : .introduction)
    }

    /// Publish readiness from asset completion as well as frame updates; launch must not depend on another frame.
    func scenePrepared(placedForViewer: Bool) {
        guard !isSceneReady, placedForViewer, !isLoadingAssets, assetLoadError == nil else { return }
        isSceneReady = true
    }

    func immersiveSpaceOpened() {
        shouldOpenImmersiveSpace = false
    }

    func immersiveSpaceDismissed() {
        shouldDismissImmersiveSpace = false
    }

    func transition(to phase: GamePhase) {
        stageReady = false
        activityHint = ""
        isPaused = false
        currentPhase = phase
        phaseRevision += 1
    }

    func advanceSetupOrStage() {
        switch currentPhase {
        case .introduction:
            transition(to: .magicSetup)
        case .magicSetup:
            // Simulator samples never become physical calibration data.
            if !calibrationIsSimulated && isReachSetupReady {
                collectedSparkOriginalPositions = reachSamples
                finalizeReachEnvelope()
            }
            hasCompletedSetupThisSession = true
            transition(to: .horns)
        case .bilateralSetup:
            transition(to: .precisionSetup)
        case .precisionSetup:
            hasCompletedSetupThisSession = true
            transition(to: .horns)
        case .horns:
            transition(to: .wings)
        case .wings:
            transition(to: .scales)
        case .scales:
            transition(to: .hornAlignment)
        case .hornAlignment:
            transition(to: .painting)
        case .painting:
            transition(to: .celebration)
        case .celebration:
            transition(to: .complete)
        case .complete, .paused:
            break
        }
    }

    func recordCollectedSpark(originalPosition: SIMD3<Float>) {
        collectedSparkOriginalPositions.append(originalPosition)
    }

    func skipSetup() {
        hasPhysicalCalibration = false
        reachSamples = []
        collectedSparkOriginalPositions.removeAll()
        reachEnvelope = ReachEnvelope()
        hasCompletedSetupThisSession = true
        transition(to: .horns)
    }

    func recordBilateralSpan(_ span: Float) {
        comfortableBilateralSpan = max(comfortableBilateralSpan, span)
        applyComfortSettings()
    }

    func markFineMotorNeedsHelp() {
        configuration.fineMotorHitTargetMultiplier = 1.35
    }

    func recordFineMotorSuccess() {
        configuration.fineMotorHitTargetMultiplier = 1
    }

    func pause() {
        guard !isPaused else { return }
        previousPhaseBeforePause = currentPhase
        isPaused = true
        currentPhase = .paused
        phaseRevision += 1
    }

    func resume() {
        isPaused = false
        currentPhase = previousPhaseBeforePause
        phaseRevision += 1
    }

    func restartCurrentStage() {
        let phase = activePhase
        isRestartingStage = true
        if phase == .painting { appliedPaint = nil; regionPaint = [:]; paintingComplete = false }
        restartRevision += 1
        transition(to: phase)
    }

    func skipCurrentStage() {
        guard currentPhase != .complete else { return }
        if currentPhase == .paused {
            currentPhase = previousPhaseBeforePause
            isPaused = false
        }
        advanceSetupOrStage()
    }

    func startOver() {
        sessionRevision += 1
        scaleDesign = []
        photoSessionID = UUID()
        appliedPaint = nil; regionPaint = [:]
        paintingComplete = false
        reachSamples = []
        hasPhysicalCalibration = false
        hasCompletedSetupThisSession = false
        collectedSparkOriginalPositions.removeAll()
        reachEnvelope = ReachEnvelope()
        comfortableBilateralSpan = 0.42
        isPaused = false
        transition(to: .introduction)
    }

    func replay() {
        sessionRevision += 1
        scaleDesign = []
        photoSessionID = UUID()
        appliedPaint = nil; regionPaint = [:]
        paintingComplete = false
        isPaused = false
        transition(to: hasCompletedSetupThisSession ? .horns : .introduction)
    }

    func finish() {
        isPaused = false
        shouldDismissImmersiveSpace = true
        transition(to: .introduction)
    }

    func applyComfortSettings() {
        switch comfortSettings.movementAmount {
        case .gentle:
            configuration.snapDistance = 0.28
            configuration.scaleSnapDistance = 0.26
            configuration.minimumPaintStroke = 0.045
            configuration.wingCompletionThreshold = 0.62
        case .standard:
            configuration.snapDistance = 0.22
            configuration.scaleSnapDistance = 0.2
            configuration.minimumPaintStroke = 0.07
            configuration.wingCompletionThreshold = min(0.86, max(0.68, comfortableBilateralSpan / 0.72))
        }

        switch comfortSettings.reachArea {
        case .close:
            configuration.layout.objectDepth = 0.08
        case .calibrated:
            configuration.layout.objectDepth = 0.14
        case .wide:
            configuration.layout.objectDepth = 0.22
        }
    }

    private func finalizeReachEnvelope() {
        guard !collectedSparkOriginalPositions.isEmpty else {
            reachEnvelope = ReachEnvelope()
            return
        }
        let xs = collectedSparkOriginalPositions.map(\.x)
        let ys = collectedSparkOriginalPositions.map(\.y)
        let minX = max((xs.min() ?? -0.28) - 0.08, -0.5)
        let maxX = min((xs.max() ?? 0.28) + 0.08, 0.5)
        let minY = max((ys.min() ?? -0.12) - 0.06, -0.22)
        let maxY = min((ys.max() ?? 0.28) + 0.06, 0.38)
        reachEnvelope = ReachEnvelope(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }
}


enum PaintChoice: String, CaseIterable, Codable {
    case orange = "Orange"
    case teal = "Teal"
    case white = "White"
    case coral = "Coral"
    case lavender = "Lavender"
    case blue = "Blue"
    case mint = "Mint"
    case gold = "Gold"
    case rose = "Rose"
    static let palettes: [[PaintChoice]] = [
        [.orange,.teal,.white], [.coral,.mint,.gold], [.lavender,.blue,.rose],
        [.teal,.gold,.coral], [.blue,.orange,.white], [.rose,.lavender,.mint]
    ]
    static func nextPalette(after index: Int) -> Int {
        (index + Int.random(in:1..<palettes.count)) % palettes.count
    }
    var assetSuffix: String { rawValue }
}

extension GamePhase {
    var movementHint: String {
        switch self {
        case .introduction: "Ember is sleeping. Wake him when you are ready."
        case .magicSetup: "Move an open hand through comfortable space, then hold. No touching or pinching."
        case .horns: "Follow each horn’s lights and hold at each stop. Then hold its base in the head outline."
        case .wings, .bilateralSetup: "Pinch with both hands. Open together, hold, then return together. Complete ten repetitions."
        case .scales, .precisionSetup: "Drag scales from the right tray onto Ember. Pinch with both hands and turn them together to rotate Ember."
        case .hornAlignment: "Make a loose fist beside a horn, or select Grip. Turn your whole forearm to the outline, hold, then return. Repeat until both rings fill."
        case .painting: "Choose a palette colour, then pick up the brush. Sweep left and right across the outlined part to fill its ring."
        case .celebration: "Design complete. Tap anywhere in the scene to open the photobooth."
        case .complete: "Tap anywhere in the scene to open the photobooth."
        case .paused: "Resume, restart, go back or skip using the controls."
        }
    }
}
