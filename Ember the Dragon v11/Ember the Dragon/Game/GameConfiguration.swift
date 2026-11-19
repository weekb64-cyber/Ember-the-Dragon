import Foundation

struct GameConfiguration {
    var snapDistance: Float = 0.16
    var rotationToleranceDegrees: Float = 15
    var horizontalReachMultiplier: Float = 0.85
    var verticalReachMultiplier: Float = 0.75
    var interactionDistance: Float = 0.82
    var wingStretchCompletionThreshold: Float = 0.82
    var scalePieceCount: Int = 5
    var scaleSnapDistance: Float = 0.12
    var requiredCleanFraction: Float = 0.84
    var minimumSweepDistance: Float = 0.08
    var objectResetDistance: Float = 0.75
    var developerModeEnabled: Bool = false
}
