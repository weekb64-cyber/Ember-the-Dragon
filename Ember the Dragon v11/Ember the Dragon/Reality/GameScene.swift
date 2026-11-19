import RealityKit
import SwiftUI
import UIKit

@MainActor
final class GameScene {
    private let model: GameModel
    private let audioManager = AudioManager()
    private lazy var feedback = FeedbackSystem(audioManager: audioManager)

    private let gameRoot = Entity()
    private let dragonRoot = Entity()
    private let interactionRoot = Entity()
    private let effectsRoot = Entity()
    private let targetRoot = Entity()
    private let environmentRoot = Entity()
    private var subscriptions: [EventSubscription] = []

    private var dragon: DragonController?
    private var activeChallenge: GameChallenge?
    private var activePhase: GamePhase?
    private var calibrationTargets: [ModelEntity] = []
    private var calibrationTargetStartPositions: [String: SIMD3<Float>] = [:]
    private var celebrationStarted = false

    init(model: GameModel) {
        self.model = model
    }

    func install(in content: inout RealityViewContent) {
        gameRoot.name = "GameRoot"
        dragonRoot.name = "DragonRootContainer"
        interactionRoot.name = "InteractionRoot"
        effectsRoot.name = "EffectsRoot"
        targetRoot.name = "TargetRoot"
        environmentRoot.name = "EnvironmentRoot"

        gameRoot.position = [0, 1.2, 0]
        gameRoot.addChild(environmentRoot)
        gameRoot.addChild(dragonRoot)
        gameRoot.addChild(targetRoot)
        gameRoot.addChild(interactionRoot)
        gameRoot.addChild(effectsRoot)
        content.add(gameRoot)

        makeEnvironment()
        makeDragon()

        subscriptions.append(content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            Task { @MainActor in
                self?.update(deltaTime: Float(event.deltaTime))
            }
        })
    }

    func synchronize() {
        guard activePhase != model.currentPhase else { return }
        activePhase = model.currentPhase
        configure(for: model.currentPhase)
    }

    private func update(deltaTime: Float) {
        synchronize()
        dragon?.updateIdle(deltaTime: deltaTime, enabled: model.currentPhase != .welcome)
        activeChallenge?.update(deltaTime: deltaTime)
        updateCalibration()
    }

    private func configure(for phase: GamePhase) {
        interactionRoot.removeAllChildren()
        targetRoot.removeAllChildren()
        activeChallenge = nil
        celebrationStarted = false

        switch phase {
        case .welcome:
            dragonRoot.isEnabled = false
        case .calibration:
            dragonRoot.isEnabled = false
            makeCalibrationTargets()
        case .introduction:
            dragonRoot.isEnabled = true
            feedback.success(at: [0, 0.1, -model.calibrationEnvelope.interactionDistance], in: effectsRoot)
            dragon?.happyBounce()
        case .reach:
            dragonRoot.isEnabled = true
            if let dragon {
                let challenge = ReachChallenge(root: interactionRoot, dragon: dragon, model: model, feedback: feedback)
                activeChallenge = challenge
                challenge.start()
            }
        case .stretch:
            if let dragon {
                let challenge = StretchChallenge(root: interactionRoot, dragon: dragon, model: model, feedback: feedback)
                activeChallenge = challenge
                challenge.start()
            }
        case .pinch:
            if let dragon {
                let challenge = PinchPlacementChallenge(root: interactionRoot, dragon: dragon, model: model, feedback: feedback)
                activeChallenge = challenge
                challenge.start()
            }
        case .rotate:
            if let dragon {
                let challenge = RotationChallenge(root: interactionRoot, dragon: dragon, model: model, feedback: feedback)
                activeChallenge = challenge
                challenge.start()
            }
        case .sweep:
            if let dragon {
                let challenge = SweepChallenge(root: interactionRoot, dragon: dragon, model: model, feedback: feedback)
                activeChallenge = challenge
                challenge.start()
            }
        case .celebration:
            dragonRoot.isEnabled = true
            if !celebrationStarted {
                celebrationStarted = true
                dragon?.celebrate()
                feedback.success(at: [0, 0.16, -model.calibrationEnvelope.interactionDistance], in: effectsRoot)
            }
        case .complete:
            dragonRoot.isEnabled = true
        }
    }

    private func makeEnvironment() {
        let platform = ModelEntity(mesh: .generateSphere(radius: 0.24), materials: [SimpleMaterial(color: UIColor.emberTeal.withAlphaComponent(0.45), roughness: 0.8, isMetallic: false)])
        platform.name = "CloudPlatform"
        platform.position = [0, -0.22, -0.82]
        platform.scale = [1.35, 0.22, 0.75]
        environmentRoot.addChild(platform)
    }

    private func makeDragon() {
        let parts = DragonFactory.makePlaceholderDragon()
        parts.root.position = [0, 0, -model.configuration.interactionDistance]
        dragonRoot.addChild(parts.root)
        dragon = DragonController(parts: parts, basePosition: parts.root.position)
    }

    private func makeCalibrationTargets() {
        calibrationTargets.removeAll()
        calibrationTargetStartPositions.removeAll()
        let positions: [(String, SIMD3<Float>)] = [
            ("CalibrationCenter", [0, 0.02, -model.configuration.interactionDistance]),
            ("CalibrationUpperLeft", [-0.24, 0.2, -model.configuration.interactionDistance]),
            ("CalibrationUpperRight", [0.24, 0.2, -model.configuration.interactionDistance]),
            ("CalibrationLeft", [-0.3, -0.02, -model.configuration.interactionDistance]),
            ("CalibrationRight", [0.3, -0.02, -model.configuration.interactionDistance])
        ]

        for (name, position) in positions {
            let star = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [SimpleMaterial(color: .emberGold, roughness: 0.2, isMetallic: false)])
            star.name = name
            star.position = position
            star.setInteraction(radius: 0.11)
            targetRoot.addChild(star)
            calibrationTargets.append(star)
            calibrationTargetStartPositions[name] = position
        }
    }

    private func updateCalibration() {
        guard model.currentPhase == .calibration else { return }
        for target in calibrationTargets where target.isEnabled {
            let start = calibrationTargetStartPositions[target.name] ?? target.position
            let movedFromStart = simd_length(target.position - start)
            if movedFromStart > 0.025 {
                model.recordCalibrationTarget(named: target.name)
                feedback.success(at: target.position(relativeTo: effectsRoot), in: effectsRoot)
                target.isEnabled = false
            }
        }
    }
}
