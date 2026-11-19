import Foundation
import RealityKit

func distance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
    simd_length(lhs - rhs)
}

func degreesToRadians(_ degrees: Float) -> Float {
    degrees * .pi / 180
}

func radiansToDegrees(_ radians: Float) -> Float {
    radians * 180 / .pi
}

func clamped(_ value: Float, lower: Float = 0, upper: Float = 1) -> Float {
    min(max(value, lower), upper)
}
