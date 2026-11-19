import Foundation
import simd

/// Resolve the shortest twist about the held forearm, then preserve its direction as seen by the wearer.
func signedWristTurnDegrees(current: simd_quatf, initial: simd_quatf, forearmAxis: SIMD3<Float>, towardViewer: SIMD3<Float>) -> Float {
    var delta = current * initial.inverse
    if delta.real < 0 { delta = simd_quatf(vector:-delta.vector) }
    let facing: Float = simd_dot(forearmAxis,towardViewer) < 0 ? -1 : 1
    return 2 * atan2(simd_dot(delta.imag,forearmAxis),delta.real) * facing * 180 / .pi
}

func relaxedGripDetected(distances: [Float?], palmLength: Float) -> Bool {
    let visible = distances.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
    guard visible.count >= 2, palmLength.isFinite, palmLength > 0.02 else { return false }
    return visible.filter { $0 < palmLength * 1.35 }.count >= 2
}

/// Positive grip evidence engages once; an explicit release ends it. Occluded fingertips do not release a held horn.
struct WristGripLatch {
    private(set) var isHeld = false
    mutating func engage() { isHeld = true }
    mutating func observe(isGrip: Bool, near: Bool) { if isGrip && near { engage() } }
    mutating func release() { isHeld = false }
}
