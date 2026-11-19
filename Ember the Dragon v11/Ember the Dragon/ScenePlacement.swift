import Foundation
import simd

/// Remove pitch and roll, including the near-vertical viewing case.
func levelSceneOrientation(_ head: simd_float4x4) -> simd_quatf {
    let back = head.columns.2
    let yaw: Float
    if back.x*back.x + back.z*back.z > 0.0001 { yaw = atan2(back.x,back.z) }
    else { yaw = atan2(-head.columns.0.z,head.columns.0.x) }
    return simd_quatf(angle:yaw,axis:[0,1,0])
}

struct SceneChromeLayout {
    let instruction: SIMD3<Float>
    let activity: SIMD3<Float>
    var scaleSupply: SIMD3<Float> { activity + [0,0.18,0] }
    /// The top Pause button, not the centre of the expanding attachment.
    let pause: SIMD3<Float>
    init(minimum: SIMD3<Float>, maximum: SIMD3<Float>) {
        let center = (minimum.x+maximum.x)/2
        let front = min(0.28,max(0.16,(minimum.z+maximum.z)/2+0.10))
        let side = max(0.38,min(0.52,maximum.x+0.12))
        activity = [side,0.14,front]
        instruction = [center-0.43,0.32,front+0.04]
        pause = [side,0.43,front+0.025]
    }
}

/// Keep the bar and its entire hit target ahead of the rendered garden, not under its footprint.
/// Bounds are expressed in gameRoot coordinates, after the environment's size/offset is applied.
enum SceneMoveHandleLayout {
    static let size = SIMD3<Float>(0.16,0.01,0.01)
    static let hitSize = SIMD3<Float>(0.22,0.065,0.07)

    static func position(nestMinimum: SIMD3<Float>, nestMaximum: SIMD3<Float>, gardenFront: Float) -> SIMD3<Float> {
        [(nestMinimum.x+nestMaximum.x)/2,
         nestMaximum.y + hitSize.y/2 + 0.015,
         max(nestMaximum.z,gardenFront) + hitSize.z/2 + 0.055]
    }
}

/// Find a reachable, clear hand location without pushing it closer than the measured near limit.
func clearReachPoint(_ preferred: SIMD3<Float>, minimum: SIMD3<Float>, maximum: SIMD3<Float>, obstacleMin: SIMD3<Float>, obstacleMax: SIMD3<Float>) -> SIMD3<Float>? {
    guard (0..<3).allSatisfy({ minimum[$0] <= maximum[$0] }) else { return nil }
    let lo = obstacleMin-SIMD3<Float>(repeating:0.10), hi = obstacleMax+SIMD3<Float>(repeating:0.10)
    let p = simd_clamp(preferred,minimum,maximum)
    func clear(_ q: SIMD3<Float>) -> Bool { (0..<3).contains { q[$0] <= lo[$0] || q[$0] >= hi[$0] } }
    if clear(p) { return p }
    var candidates: [SIMD3<Float>] = []
    for axis in 0..<3 {
        for boundary in [lo[axis],hi[axis]] where boundary >= minimum[axis] && boundary <= maximum[axis] {
            var q = p; q[axis] = boundary
            if clear(q) { candidates.append(q) }
        }
    }
    return candidates.min { simd_distance($0,p) < simd_distance($1,p) }
}

/// Plan all checkpoints in one clear corridor; every connecting segment stays outside the models.
func hornRoute(minimum: SIMD3<Float>, maximum: SIMD3<Float>, obstacleMin: SIMD3<Float>, obstacleMax: SIMD3<Float>, left: Bool) -> [SIMD3<Float>] {
    guard (0..<3).allSatisfy({ minimum[$0] <= maximum[$0] }) else { return [] }
    let clearance: Float = 0.085
    let middle = (obstacleMin.x+obstacleMax.x)/2
    var lo = minimum, hi = maximum
    if left { hi.x = min(hi.x,middle-0.025) } else { lo.x = max(lo.x,middle+0.025) }
    guard hi.x-lo.x >= 0.035 else { return [] }
    // Prefer a plane in front of the character. Fallback is strictly the matching side, never the other side.
    if obstacleMax.z+clearance <= hi.z && obstacleMax.z+clearance >= lo.z {
        lo.z = obstacleMax.z+clearance
        // Keep the remaining depth corridor: forward/back travel should not collapse into a plane.
    } else if left && obstacleMin.x-clearance >= lo.x {
        hi.x = min(hi.x,obstacleMin.x-clearance)
    } else if !left && obstacleMax.x+clearance <= hi.x {
        lo.x = max(lo.x,obstacleMax.x+clearance)
    } else { return [] }
    guard (0..<3).allSatisfy({ lo[$0] <= hi[$0] }) else { return [] }
    let pattern: [SIMD3<Float>] = [[0,0.15,0.90],[1,0.85,0.05],[0.05,0.90,0.80],[0.95,0.10,0.10],[0.05,0.30,0.95],[0.90,0.85,0.05]]
    return pattern.map { value in
        var t = value
        if !left { t.x = 1-t.x }
        return lo+(hi-lo)*t
    }
}

/// Place the character on the initial viewing ray while keeping the entire garden upright.
func initialEmberScenePosition(head: simd_float4x4, characterCenter: SIMD3<Float>, scale: Float) -> SIMD3<Float> {
    let eye = SIMD3<Float>(head.columns.3.x,head.columns.3.y,head.columns.3.z)
    let forward = -SIMD3<Float>(head.columns.2.x,head.columns.2.y,head.columns.2.z)
    return eye + forward * 1.10 - [0,0.03,0] - levelSceneOrientation(head).act(characterCenter*scale)
}

/// Keep the entire decoration footprint inside the moss disk, not just its centre.
func nestDecorationPosition(_ proposed: SIMD2<Float>, footprint: Float) -> SIMD2<Float> {
    let limit = max(0,0.435-footprint)
    let length = simd_length(proposed)
    return length > limit && length > 0 ? proposed*(limit/length) : proposed
}

/// Simulator has no tracked head anchor. Reuse its fixed viewpoint for initial placement and recenter.
struct EmberViewerPlacement {
    let position: SIMD3<Float>
    let orientation: simd_quatf
    let scale: Float

    static func resolve(head: simd_float4x4?, isSimulator: Bool, characterCenter: SIMD3<Float>) -> Self? {
        // The simulator starts with a standing camera. A floor-height root puts Ember below its view.
        var simulatorHead = matrix_identity_float4x4
        simulatorHead.columns.3 = [0,1.60,0,1]
        guard let head = isSimulator ? simulatorHead : head else { return nil }
        return Self(position:initialEmberScenePosition(head:head,characterCenter:characterCenter,scale:0.85),
                    orientation:levelSceneOrientation(head),scale:0.85)
    }
}
