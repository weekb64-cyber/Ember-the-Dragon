import RealityKit

@MainActor
final class DragonController {
    let parts: DragonParts
    private var idleTime: Float = 0
    private let basePosition: SIMD3<Float>
    private let baseLeftWingScale: SIMD3<Float>
    private let baseRightWingScale: SIMD3<Float>
    private let baseLeftWingPosition: SIMD3<Float>
    private let baseRightWingPosition: SIMD3<Float>

    init(parts: DragonParts, basePosition: SIMD3<Float>) {
        self.parts = parts
        self.basePosition = basePosition
        baseLeftWingScale = parts.leftWing.scale
        baseRightWingScale = parts.rightWing.scale
        baseLeftWingPosition = parts.leftWing.position
        baseRightWingPosition = parts.rightWing.position
    }

    func reset() {
        parts.root.position = basePosition
        parts.root.orientation = .init()
        parts.root.scale = [1, 1, 1]
        setWingStretch(0)
        parts.leftHorn.orientation = .init()
        parts.rightHorn.orientation = .init()
        parts.tail.position = [0, -0.04, -0.19]
        parts.tail.isEnabled = true
    }

    func updateIdle(deltaTime: Float, enabled: Bool) {
        guard enabled else { return }
        idleTime += deltaTime
        let floatOffset = sin(idleTime * 1.4) * 0.018
        parts.root.position.y = basePosition.y + floatOffset
        parts.head.orientation = simd_quatf(angle: sin(idleTime * 0.7) * 0.08, axis: [0, 1, 0])
    }

    func setWingStretch(_ progress: Float) {
        let amount = clamped(progress)
        let scaleX = 1 + amount * 0.85
        parts.leftWing.scale = [baseLeftWingScale.x * scaleX, baseLeftWingScale.y, baseLeftWingScale.z]
        parts.rightWing.scale = [baseRightWingScale.x * scaleX, baseRightWingScale.y, baseRightWingScale.z]
        parts.leftWing.position = baseLeftWingPosition + [-amount * 0.075, amount * 0.025, 0]
        parts.rightWing.position = baseRightWingPosition + [amount * 0.075, amount * 0.025, 0]
    }

    func happyBounce() {
        let start = parts.root.transform
        var up = start
        up.translation.y += 0.08
        up.rotation = simd_quatf(angle: degreesToRadians(5), axis: [0, 0, 1])
        parts.root.move(to: up, relativeTo: parts.root.parent, duration: 0.22, timingFunction: .easeOut)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            self.parts.root.move(to: start, relativeTo: self.parts.root.parent, duration: 0.28, timingFunction: .easeInOut)
        }
    }

    func wingFlutter() {
        parts.leftWing.orientation *= simd_quatf(angle: degreesToRadians(-12), axis: [0, 0, 1])
        parts.rightWing.orientation *= simd_quatf(angle: degreesToRadians(12), axis: [0, 0, 1])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            self.parts.leftWing.orientation = simd_quatf(angle: degreesToRadians(-18), axis: [0, 0, 1])
            self.parts.rightWing.orientation = simd_quatf(angle: degreesToRadians(18), axis: [0, 0, 1])
        }
    }

    func celebrate() {
        setWingStretch(1)
        happyBounce()
        wingFlutter()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            let start = self.parts.root.transform
            var left = start
            left.translation.x -= 0.16
            left.translation.y += 0.07
            self.parts.root.move(to: left, relativeTo: self.parts.root.parent, duration: 1.0, timingFunction: .easeInOut)
            try? await Task.sleep(for: .seconds(1.0))
            var right = start
            right.translation.x += 0.16
            right.translation.y += 0.08
            self.parts.root.move(to: right, relativeTo: self.parts.root.parent, duration: 1.1, timingFunction: .easeInOut)
            try? await Task.sleep(for: .seconds(1.1))
            self.parts.root.move(to: start, relativeTo: self.parts.root.parent, duration: 1.0, timingFunction: .easeInOut)
        }
    }
}
