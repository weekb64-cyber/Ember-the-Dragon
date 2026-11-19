import Foundation

struct RouteProgress {
    let checkpoints: [SIMD3<Float>]
    private(set) var completedCount = 0
    var complete: Bool { completedCount == checkpoints.count }
    private var hold: Float = 0
    init(checkpoints: [SIMD3<Float>]) { self.checkpoints = checkpoints }
    var fill: Float { Float(completedCount) + min(hold / 0.4, 1) }
    var next: SIMD3<Float>? { complete ? nil : checkpoints[completedCount] }
    mutating func update(_ point: SIMD3<Float>, held: Bool, radius: Float, deltaTime: Float) {
        guard held, let next else { hold = 0; return }
        let d = point-next
        guard d.x*d.x+d.y*d.y+d.z*d.z <= radius*radius else { hold = 0; return }
        hold += min(max(deltaTime,0),0.05)
        if hold >= 0.4 { completedCount += 1; hold = 0 }
    }
    mutating func visit(_ point: SIMD3<Float>, radius: Float) {
        guard let next else { return }
        let d = point-next
        if d.x*d.x+d.y*d.y+d.z*d.z <= radius*radius { completedCount += 1 }
    }
}

struct WingPractice {
    init(requiredCycles: Int) { self.requiredCycles = requiredCycles }
    let requiredCycles: Int
    private(set) var completedCycles = 0
    private(set) var returning = false
    private var heldTime: Float = 0
    var complete: Bool { completedCycles >= requiredCycles }
    func fill(progress: Float, threshold: Float) -> Float {
        if complete { return 1 }
        let movement = returning ? 1-min(max(progress,0),1) : min(max(progress/threshold,0),1)
        let half = (movement*0.8 + min(heldTime/0.4,1)*0.2)*0.5
        return (Float(completedCycles) + (returning ? 0.5 : 0) + half)/Float(requiredCycles)
    }
    mutating func update(progress: Float, isHeld: Bool, deltaTime: Float, threshold: Float) {
        guard !complete, isHeld else { heldTime = 0; return }
        let inPosition = returning ? progress <= 0.16 : progress >= threshold
        guard inPosition else { heldTime = 0; return }
        heldTime += min(max(deltaTime,0),0.05)
        guard heldTime >= 0.4 else { return }
        heldTime = 0
        if returning { completedCycles += 1 }
        returning.toggle()
    }
}

struct PaintAreaProgress {
    init(requiredDistance: Float, requiredCells: Int) { self.requiredDistance = requiredDistance; self.requiredCells = requiredCells }
    let requiredDistance: Float
    let requiredCells: Int
    private(set) var distance: Float = 0
    private var cells: Set<Int> = []
    var complete: Bool { distance >= requiredDistance && cells.count >= requiredCells }
    mutating func stroke(length: Float, cell: Int) {
        guard length > 0.0005, length < 0.12, (0..<4).contains(cell) else { return }
        distance += length
        cells.insert(cell)
    }
}

/// Movement stays on the paint plane; simulated depth cannot pull the brush off Ember.
func paintPlanePosition(_ candidate: SIMD3<Float>, surfaceZ: Float, minimum: SIMD3<Float>, maximum: SIMD3<Float>) -> SIMD3<Float> {
    [min(max(candidate.x,minimum.x-0.15),maximum.x+0.15),
     min(max(candidate.y,minimum.y-0.08),maximum.y), surfaceZ]
}

func scaleSocketFacesPlayer(yaw: Float, socketAngle: Float) -> Bool {
    cos(yaw + socketAngle) > 0.78
}

/// A repetition requires an outward turn and a held return; idle alignment never counts.
struct HornTurnPractice {
    let requiredCycles: Int
    let direction: Float
    var excursionDegrees: Float = 50
    private(set) var cycles = 0
    private(set) var returning = false
    private(set) var hold: Float = 0
    var complete: Bool { cycles >= requiredCycles }
    var targetDegrees: Float { returning || complete ? 0 : direction * (cycles.isMultiple(of: 2) ? excursionDegrees : -excursionDegrees) }
    var fill: Float { complete ? 1 : (Float(cycles) + (returning ? 0.5 : 0) + min(hold / 0.5, 1) * 0.5) / Float(requiredCycles) }
    mutating func update(angle: Float, held: Bool, deltaTime: Float) {
        guard !complete, held, abs(angle - targetDegrees) <= 9 else { hold = 0; return }
        hold += min(max(deltaTime, 0), 0.05)
        guard hold >= 0.5 else { return }
        hold = 0
        if returning { cycles += 1 }
        returning.toggle()
    }
}
