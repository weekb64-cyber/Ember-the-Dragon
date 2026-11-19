import RealityKit
import UIKit

@MainActor
final class StretchChallenge: GameChallenge {
    private let root: Entity
    private let dragon: DragonController
    private let model: GameModel
    private let feedback: FeedbackSystem
    private var leftHandle: ModelEntity?
    private var rightHandle: ModelEntity?
    private var initialDistance: Float = 0.32
    private var completed = false

    var isComplete: Bool { completed }

    init(root: Entity, dragon: DragonController, model: GameModel, feedback: FeedbackSystem) {
        self.root = root
        self.dragon = dragon
        self.model = model
        self.feedback = feedback
    }

    func start() {
        reset()
        dragon.setWingStretch(0)
        leftHandle = makeHandle(name: "LeftWingStretchHandle", position: [-0.31, 0.08, -model.calibrationEnvelope.interactionDistance])
        rightHandle = makeHandle(name: "RightWingStretchHandle", position: [0.31, 0.08, -model.calibrationEnvelope.interactionDistance])
        if let leftHandle, let rightHandle {
            initialDistance = distance(leftHandle.position, rightHandle.position)
        }
    }

    func reset() {
        root.removeAllChildren()
        leftHandle = nil
        rightHandle = nil
        completed = false
    }

    func update(deltaTime: Float) {
        guard let leftHandle, let rightHandle, !completed else { return }
        let currentDistance = distance(leftHandle.position(relativeTo: root), rightHandle.position(relativeTo: root))
        let progress = clamped((currentDistance - initialDistance) / 0.24)
        dragon.setWingStretch(progress)
        model.updateProgress(progress)

        if progress >= model.configuration.wingStretchCompletionThreshold {
            completed = true
            leftHandle.disableInteraction()
            rightHandle.disableInteraction()
            feedback.success(at: [0, 0.14, -model.calibrationEnvelope.interactionDistance], in: root)
            dragon.wingFlutter()
            model.updateProgress(1)
            model.completeCurrentStage()
        }
    }

    private func makeHandle(name: String, position: SIMD3<Float>) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [SimpleMaterial(color: .emberSky, roughness: 0.25, isMetallic: false)])
        entity.name = name
        entity.position = position
        entity.setInteraction(radius: 0.09)
        root.addChild(entity)
        return entity
    }
}
