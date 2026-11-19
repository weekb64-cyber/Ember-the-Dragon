import RealityKit
import UIKit

@MainActor
final class FeedbackSystem {
    private let audioManager: AudioManager

    init(audioManager: AudioManager) {
        self.audioManager = audioManager
    }

    func success(at position: SIMD3<Float>, in parent: Entity) {
        let sparkle = ModelEntity(
            mesh: .generateSphere(radius: 0.025),
            materials: [SimpleMaterial(color: .emberGold, roughness: 0.2, isMetallic: false)]
        )
        sparkle.name = "Sparkle"
        sparkle.position = position
        parent.addChild(sparkle)
        sparkle.scale = [0.1, 0.1, 0.1]
        sparkle.move(to: Transform(scale: [1.8, 1.8, 1.8], rotation: .init(), translation: position + [0, 0.04, 0]), relativeTo: parent, duration: 0.35, timingFunction: .easeOut)
        audioManager.play(.sparkle, from: sparkle)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            sparkle.removeFromParent()
        }
    }

    func pulse(_ entity: Entity) {
        let original = entity.scale
        entity.scale = original * 1.08
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            entity.scale = original
        }
    }

    func snapCue(from entity: Entity?) {
        audioManager.play(.snap, from: entity)
    }
}
