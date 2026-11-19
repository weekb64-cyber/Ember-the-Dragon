import RealityKit
import UIKit

@MainActor
final class ReachChallenge: GameChallenge {
    private struct Item {
        let entity: ModelEntity
        let target: Entity
        let finalParent: Entity
        let finalLocalPosition: SIMD3<Float>
        var attached = false
        let startPosition: SIMD3<Float>
    }

    private let root: Entity
    private let dragon: DragonController
    private let model: GameModel
    private let feedback: FeedbackSystem
    private var items: [Item] = []

    var isComplete: Bool { items.allSatisfy(\.attached) && !items.isEmpty }

    init(root: Entity, dragon: DragonController, model: GameModel, feedback: FeedbackSystem) {
        self.root = root
        self.dragon = dragon
        self.model = model
        self.feedback = feedback
    }

    func start() {
        reset()
        let envelope = model.calibrationEnvelope
        addItem(name: "LostLeftHorn", color: .emberGold, size: [0.04, 0.11, 0.04], start: envelope.position(horizontal: 0.15, vertical: 0.45), target: dragon.parts.leftHornSocket, finalParent: dragon.parts.head, finalLocalPosition: dragon.parts.leftHorn.position)
        addItem(name: "LostRightHorn", color: .emberGold, size: [0.04, 0.11, 0.04], start: envelope.position(horizontal: 0.85, vertical: 0.45), target: dragon.parts.rightHornSocket, finalParent: dragon.parts.head, finalLocalPosition: dragon.parts.rightHorn.position)
        addItem(name: "LostTailGem", color: .emberLavender, size: [0.08, 0.08, 0.08], start: envelope.position(horizontal: 0.5, vertical: 0.95), target: dragon.parts.tailSocket, finalParent: dragon.parts.tail, finalLocalPosition: [0, 0.01, -0.09])
        dragon.parts.leftHorn.isEnabled = false
        dragon.parts.rightHorn.isEnabled = false
    }

    func reset() {
        root.removeAllChildren()
        items.removeAll()
        dragon.parts.leftHorn.isEnabled = true
        dragon.parts.rightHorn.isEnabled = true
    }

    func update(deltaTime: Float) {
        for index in items.indices where !items[index].attached {
            let itemPosition = items[index].entity.position(relativeTo: root)
            if distance(itemPosition, items[index].target.position(relativeTo: root)) <= model.configuration.snapDistance {
                attach(index: index)
            } else if distance(itemPosition, items[index].startPosition) > model.configuration.objectResetDistance {
                items[index].entity.position = items[index].startPosition
            }
        }
        model.updateProgress(Float(items.filter(\.attached).count) / 3)
        if isComplete {
            dragon.parts.leftHorn.isEnabled = true
            dragon.parts.rightHorn.isEnabled = true
            dragon.happyBounce()
            model.completeCurrentStage()
        }
    }

    private func addItem(name: String, color: UIColor, size: SIMD3<Float>, start: SIMD3<Float>, target: Entity, finalParent: Entity, finalLocalPosition: SIMD3<Float>) {
        let entity = ModelEntity(mesh: .generateBox(size: size), materials: [SimpleMaterial(color: color, roughness: 0.45, isMetallic: false)])
        entity.name = name
        entity.position = start
        entity.setInteraction(radius: 0.09)
        root.addChild(entity)
        target.isEnabled = true
        items.append(Item(entity: entity, target: target, finalParent: finalParent, finalLocalPosition: finalLocalPosition, startPosition: start))
    }

    private func attach(index: Int) {
        guard !items[index].attached else { return }
        items[index].attached = true
        let entity = items[index].entity
        entity.disableInteraction()
        let targetPosition = items[index].target.position(relativeTo: root)
        entity.move(to: Transform(scale: entity.scale, rotation: .init(), translation: targetPosition), relativeTo: root, duration: 0.25, timingFunction: .easeInOut)
        feedback.success(at: targetPosition, in: root)
        feedback.snapCue(from: entity)
        items[index].target.isEnabled = false
    }
}
