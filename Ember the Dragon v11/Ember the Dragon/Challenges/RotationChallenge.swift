import RealityKit

@MainActor
final class RotationChallenge: GameChallenge {
    private let root: Entity
    private let dragon: DragonController
    private let model: GameModel
    private let feedback: FeedbackSystem
    private var alignedNames: Set<String> = []
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
        configureHorn(dragon.parts.leftHorn, angle: -50)
        configureHorn(dragon.parts.rightHorn, angle: 45)
    }

    func reset() {
        alignedNames.removeAll()
        completed = false
        dragon.parts.leftHorn.orientation = .init()
        dragon.parts.rightHorn.orientation = .init()
        dragon.parts.leftHorn.setInteraction(boxSize: [0.09, 0.16, 0.09])
        dragon.parts.rightHorn.setInteraction(boxSize: [0.09, 0.16, 0.09])
    }

    func update(deltaTime: Float) {
        guard !completed else { return }
        check(dragon.parts.leftHorn)
        check(dragon.parts.rightHorn)
        model.updateProgress(Float(alignedNames.count) / 2)
        if alignedNames.count == 2 {
            completed = true
            dragon.happyBounce()
            model.completeCurrentStage()
        }
    }

    private func configureHorn(_ horn: Entity, angle: Float) {
        horn.isEnabled = true
        horn.orientation = simd_quatf(angle: degreesToRadians(angle), axis: [0, 0, 1])
        horn.setInteraction(boxSize: [0.09, 0.16, 0.09])
    }

    private func check(_ horn: Entity) {
        guard !alignedNames.contains(horn.name) else { return }
        let up = simd_act(horn.orientation, SIMD3<Float>(0, 1, 0))
        let angle = abs(radiansToDegrees(atan2(up.x, up.y)))
        if angle <= model.configuration.rotationToleranceDegrees {
            alignedNames.insert(horn.name)
            horn.orientation = .init()
            horn.disableInteraction()
            let position = horn.position(relativeTo: root)
            feedback.success(at: position, in: root)
            feedback.snapCue(from: horn)
        }
    }
}
