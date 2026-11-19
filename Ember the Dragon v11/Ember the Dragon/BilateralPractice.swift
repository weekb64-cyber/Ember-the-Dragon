import Foundation

/// Both sides must reach and hold each endpoint; lost tracking cannot finish a repetition.
struct BilateralPractice {
    let requiredCycles = 10
    private(set) var cycles = 0
    private(set) var returning = false
    private(set) var hold: Float = 0
    var complete: Bool { cycles >= requiredCycles }
    var fill: Float { complete ? 1 : (Float(cycles) + (returning ? 0.5 : 0) + min(hold,1)*0.5)/Float(requiredCycles) }
    mutating func resetPosition() { hold = 0; returning = false }
    mutating func update(left: Float, right: Float, engaged: Bool, deltaTime: Float) {
        guard !complete else { return }
        guard engaged else { return }
        let atTarget = returning ? (left <= 0.25 && right <= 0.25) : (left >= 0.94 && right >= 0.94)
        guard atTarget else { hold = max(0,hold-min(max(deltaTime,0),0.05)*2); return }
        hold += min(max(deltaTime,0),0.05)
        if hold >= 1 { hold = 0; if returning { cycles += 1 }; returning.toggle() }
    }
}

extension GameModel {
    /// Stay inside 90% in Standard (75% in Gentle) of measured excursions; do not expand a user's smaller reach.
    func reachTarget(_ direction: SIMD3<Float>) -> SIMD3<Float> {
        guard reachSamples.count == 7 else { return SIMD3<Float>(0,0.2,0.22) + direction * SIMD3<Float>(0.32,0.20,0.18) }
        let center = reachSamples[0]
        let lo = reachSamples.reduce(center) { SIMD3(min($0.x,$1.x),min($0.y,$1.y),min($0.z,$1.z)) }
        let hi = reachSamples.reduce(center) { SIMD3(max($0.x,$1.x),max($0.y,$1.y),max($0.z,$1.z)) }
        var result = center
        for axis in 0..<3 { result[axis] += direction[axis] * (direction[axis] < 0 ? center[axis]-lo[axis] : hi[axis]-center[axis]) * (comfortSettings.movementAmount == .gentle ? 0.75 : 0.90) }
        return result
    }
    func wingTravel(startX: Float, left: Bool) -> Float {
        guard reachSamples.count == 7 else { return 0.24 }
        let endpoint = reachTarget([left ? -1 : 1,0,0]).x
        let distance = left ? startX-endpoint : endpoint-startX
        return max(0.025,distance)
    }
    var wingExcursion: Float {
        guard reachSamples.count == 7 else { return 0.16 }
        return max(0.025,min(abs(reachSamples[2].x-reachSamples[0].x),abs(reachSamples[3].x-reachSamples[0].x))*(comfortSettings.movementAmount == .gentle ? 0.75 : 0.90))
    }
}
