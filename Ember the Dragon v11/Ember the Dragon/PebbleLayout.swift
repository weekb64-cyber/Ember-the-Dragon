import Foundation
import simd

/// Imported meshes face +Z. Offsets centre the torso instead of the asymmetric tail bounds.
enum PebbleForm: String {
    case sleeping, repair, complete
    var assetName: String {
        switch self {
        case .sleeping: "EmberSleepingWinglessHornlessVisual"
        case .repair: "EmberAwakeWinglessHornlessVisual"
        case .complete: "EmberAwakeFullVisual"
        }
    }
    static func forPhase(_ phase: GamePhase) -> PebbleForm {
        switch phase {
        case .introduction: .sleeping
        case .celebration, .complete: .complete
        default: .repair
        }
    }
    var normalizedSize: Float { self == .sleeping ? 0.70 : (self == .complete ? 0.73 : 0.62) }
    var offset: SIMD3<Float> {
        switch self {
        case .sleeping: [-0.02,0,0]
        case .repair: [-0.077,0,-0.03]
        case .complete: [-0.025,0.055,-0.03]
        }
    }
}


/// Fitted to the imported repair head and the flat cap of HornVisual at 0.15 m normalized length.
/// The old +Z extremity was the cap's rim, not its centre, leaving a visible hanging edge.
enum PebbleHornFit {
    static let normalizedLength: Float = 0.15
    static let baseCenter = SIMD3<Float>(0.000034,-0.029469,0.066620)
    static let orientation = simd_quatf(angle:0.10,axis:[0,1,0]) * simd_quatf(angle:1.12,axis:[1,0,0])
    // The first beige pair straddles x = -0.043. Both bases share one fore/aft line,
    // just beyond that pair toward the crown; only seating depth follows the sculpted scalp.
    static let headCenterX: Float = -0.043
    static let halfSpacing: Float = 0.050
    // The head roll is baked into the USDZ vertices, so the sockets need its rest frame.
    // Outward splay is applied within that frame, matching the marked front/rear silhouettes.
    static let headRoll: Float = 0.28
    static let outwardSplay: Float = 0.24
    static func restingOrientation(left: Bool) -> simd_quatf {
        simd_quatf(angle:headRoll + (left ? outwardSplay : -outwardSplay),axis:[0,0,1])
    }
    static func socketPosition(left: Bool) -> SIMD3<Float> {
        [headCenterX + (left ? -halfSpacing : halfSpacing),left ? 0.279 : 0.287,0.105]
    }
    static func finishedPose(for phase: GamePhase) -> Bool {
        [.painting,.celebration,.complete].contains(phase)
    }
    static func finishAmount(elapsed: Float) -> Float {
        let t = min(1,max(0,elapsed/1.25))
        return t*t*(3-2*t)
    }
    static func poseOrientation(left: Bool, finish: Float) -> simd_quatf {
        let rest = restingOrientation(left:left)
        return simd_slerp(rest,rest * simd_quatf(angle:-1.05,axis:[1,0,0]),min(1,max(0,finish)))
    }
    static func posePosition(left: Bool, finish: Float) -> SIMD3<Float> {
        var position = socketPosition(left:left)
        position.y += ((left ? Float(0.262) : Float(0.278))-position.y)*min(1,max(0,finish))
        return position
    }
    static func breathingPosition(left: Bool, scale: SIMD3<Float>, offset: SIMD3<Float>, finish: Float = 0) -> SIMD3<Float> {
        offset + posePosition(left:left,finish:finish)*scale
    }
}
