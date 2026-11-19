import RealityKit
import UIKit

@MainActor
final class SweepChallenge: GameChallenge {
    private struct DustRegion {
        let entity: ModelEntity
        let position: SIMD3<Float>
        var cleaned = false
    }

    private let root: Entity
    private let dragon: DragonController
    private let model: GameModel
    private let feedback: FeedbackSystem
    private var regions: [DustRegion] = []
    private var brush: ModelEntity?
    private var previousBrushPosition: SIMD3<Float>?
    private var accumulatedSweepDistance: Float = 0
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
        makeDustRegions()
        let brush = ModelEntity(mesh: .generateSphere(radius: 0.07), materials: [SimpleMaterial(color: .emberTeal, roughness: 0.22, isMetallic: false)])
        brush.name = "MagicBrush"
        brush.position = [0.0, -0.18, -model.calibrationEnvelope.interactionDistance]
        brush.scale = [1.0, 0.65, 0.35]
        brush.setInteraction(radius: 0.11)
        root.addChild(brush)
        self.brush = brush
        previousBrushPosition = brush.position(relativeTo: root)
    }

    func reset() {
        root.removeAllChildren()
        regions.removeAll()
        brush = nil
        previousBrushPosition = nil
        accumulatedSweepDistance = 0
        completed = false
    }

    func update(deltaTime: Float) {
        guard let brush, !completed else { return }
        let current = brush.position(relativeTo: root)
        if let previous = previousBrushPosition {
            let moved = distance(current, previous)
            if moved > 0.006 {
                accumulatedSweepDistance += moved
            }
        }
        previousBrushPosition = current

        guard accumulatedSweepDistance >= model.configuration.minimumSweepDistance else { return }

        for index in regions.indices where !regions[index].cleaned {
            if distance(current, regions[index].position) <= 0.16 {
                clean(index: index)
                accumulatedSweepDistance = 0
            }
        }

        let fraction = Float(regions.filter(\.cleaned).count) / Float(max(regions.count, 1))
        model.updateProgress(fraction)
        if fraction >= model.configuration.requiredCleanFraction {
            completed = true
            brush.disableInteraction()
            dragon.celebrate()
            model.completeCurrentStage()
        }
    }

    private func makeDustRegions() {
        let positions: [SIMD3<Float>] = [
            [-0.14, 0.08, -model.calibrationEnvelope.interactionDistance],
            [0.0, 0.12, -model.calibrationEnvelope.interactionDistance],
            [0.14, 0.08, -model.calibrationEnvelope.interactionDistance],
            [-0.19, -0.02, -model.calibrationEnvelope.interactionDistance],
            [0.0, -0.04, -model.calibrationEnvelope.interactionDistance],
            [0.19, -0.02, -model.calibrationEnvelope.interactionDistance],
            [-0.11, -0.14, -model.calibrationEnvelope.interactionDistance],
            [0.11, -0.14, -model.calibrationEnvelope.interactionDistance]
        ]

        for (index, position) in positions.enumerated() {
            let dust = ModelEntity(mesh: .generateSphere(radius: 0.055), materials: [SimpleMaterial(color: UIColor(white: 0.72, alpha: 0.65), roughness: 0.9, isMetallic: false)])
            dust.name = "DustRegion\(index + 1)"
            dust.position = position
            dust.scale = [1.25, 0.65, 0.18]
            root.addChild(dust)
            regions.append(DustRegion(entity: dust, position: position))
        }
    }

    private func clean(index: Int) {
        regions[index].cleaned = true
        let entity = regions[index].entity
        let start = entity.position
        entity.move(to: Transform(scale: [0.05, 0.05, 0.05], rotation: .init(), translation: start + [0, 0.03, 0]), relativeTo: root, duration: 0.25, timingFunction: .easeOut)
        feedback.success(at: regions[index].position, in: root)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(260))
            entity.removeFromParent()
        }
    }
}
