import Foundation

@MainActor
protocol GameChallenge: AnyObject {
    var isComplete: Bool { get }
    func start()
    func reset()
    func update(deltaTime: Float)
}
