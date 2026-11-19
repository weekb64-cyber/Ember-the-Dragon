import Foundation
import RealityKit

struct CalibrationEnvelope {
    var horizontalRange: ClosedRange<Float> = -0.34...0.34
    var verticalRange: ClosedRange<Float> = -0.12...0.28
    var interactionDistance: Float = 0.82

    func position(horizontal: Float, vertical: Float, depthOffset: Float = 0) -> SIMD3<Float> {
        let x = horizontalRange.lowerBound + (horizontalRange.upperBound - horizontalRange.lowerBound) * horizontal
        let y = verticalRange.lowerBound + (verticalRange.upperBound - verticalRange.lowerBound) * vertical
        return [x, y, -interactionDistance + depthOffset]
    }
}

@MainActor
final class CalibrationManager {
    private(set) var touchedTargetNames: Set<String> = []

    var hasEnoughInformation: Bool {
        touchedTargetNames.count >= 3
    }

    func recordTouch(named name: String) {
        touchedTargetNames.insert(name)
    }

    func reset() {
        touchedTargetNames.removeAll()
    }

    func envelope(configuration: GameConfiguration) -> CalibrationEnvelope {
        guard !touchedTargetNames.isEmpty else {
            return CalibrationEnvelope(interactionDistance: configuration.interactionDistance)
        }

        var horizontal: ClosedRange<Float> = -0.28...0.28
        var vertical: ClosedRange<Float> = -0.08...0.22

        if touchedTargetNames.contains("CalibrationLeft") {
            horizontal = -0.38...horizontal.upperBound
        }
        if touchedTargetNames.contains("CalibrationRight") {
            horizontal = horizontal.lowerBound...0.38
        }
        if touchedTargetNames.contains("CalibrationUpperLeft") || touchedTargetNames.contains("CalibrationUpperRight") {
            vertical = vertical.lowerBound...0.32
        }

        return CalibrationEnvelope(horizontalRange: horizontal, verticalRange: vertical, interactionDistance: configuration.interactionDistance)
    }
}
