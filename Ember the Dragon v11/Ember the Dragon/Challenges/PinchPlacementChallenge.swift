import RealityKit
import UIKit

@MainActor
final class PinchPlacementChallenge: GameChallenge {
    private struct ScalePiece {
        let entity: ModelEntity
        var placed = false
        let startPosition: SIMD3<Float>
    }

    private let root: Entity
    private let dragon: DragonController
    private let model: GameModel
    private let feedback: FeedbackSystem
    private var pieces: [ScalePiece] = []
    private var occupiedSocketNames: Set<String> = []
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
        let colors: [UIColor] = [.emberTeal, .emberGold, .emberLavender, .emberSky, .emberCream]
        let starts: [SIMD3<Float>] = [
            [-0.28, -0.12, -model.calibrationEnvelope.interactionDistance],
            [-0.14, -0.17, -model.calibrationEnvelope.interactionDistance],
            [0, -0.2, -model.calibrationEnvelope.interactionDistance],
            [0.14, -0.17, -model.calibrationEnvelope.interactionDistance],
            [0.28, -0.12, -model.calibrationEnvelope.interactionDistance]
        ]

        for index in 0..<min(model.configuration.scalePieceCount, dragon.parts.scaleSockets.count) {
            let entity = ModelEntity(mesh: .generateSphere(radius: 0.032), materials: [SimpleMaterial(color: colors[index % colors.count], roughness: 0.35, isMetallic: false)])
            entity.name = "MagicScale\(index + 1)"
            entity.scale = [1.15, 0.55, 0.25]
            entity.position = starts[index]
            entity.setInteraction(radius: 0.075)
            root.addChild(entity)
            dragon.parts.scaleSockets[index].isEnabled = true
            pieces.append(ScalePiece(entity: entity, startPosition: starts[index]))
        }
    }

    func reset() {
        root.removeAllChildren()
        pieces.removeAll()
        occupiedSocketNames.removeAll()
        completed = false
        dragon.parts.scaleSockets.forEach { $0.isEnabled = false }
    }

    func update(deltaTime: Float) {
        guard !completed else { return }
        for index in pieces.indices where !pieces[index].placed {
            let position = pieces[index].entity.position(relativeTo: root)
            if let socket = nearestOpenSocket(to: position), distance(position, socket.position(relativeTo: root)) <= model.configuration.scaleSnapDistance {
                place(pieceIndex: index, socket: socket)
            } else if distance(position, pieces[index].startPosition) > model.configuration.objectResetDistance {
                pieces[index].entity.position = pieces[index].startPosition
            }
        }

        model.updateProgress(Float(pieces.filter(\.placed).count) / Float(max(pieces.count, 1)))
        if !pieces.isEmpty && pieces.allSatisfy(\.placed) {
            completed = true
            dragon.happyBounce()
            model.completeCurrentStage()
        }
    }

    private func nearestOpenSocket(to position: SIMD3<Float>) -> Entity? {
        dragon.parts.scaleSockets
            .filter { !occupiedSocketNames.contains($0.name) }
            .min { distance(position, $0.position(relativeTo: root)) < distance(position, $1.position(relativeTo: root)) }
    }

    private func place(pieceIndex: Int, socket: Entity) {
        pieces[pieceIndex].placed = true
        occupiedSocketNames.insert(socket.name)
        socket.isEnabled = false
        let entity = pieces[pieceIndex].entity
        entity.disableInteraction()
        let target = socket.position(relativeTo: root)
        entity.move(to: Transform(scale: entity.scale, rotation: .init(), translation: target), relativeTo: root, duration: 0.22, timingFunction: .easeInOut)
        feedback.success(at: target, in: root)
        feedback.snapCue(from: entity)
    }
}
