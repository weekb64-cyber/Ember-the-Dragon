import Foundation

enum PaintRegion: Int, CaseIterable, Codable {
    case head = 1, body, back, arms, legs, leftWing, rightWing, tail
    var title: String {
        switch self { case .head: "Head"; case .body: "Body"; case .back: "Back"; case .arms: "Arms"; case .legs: "Legs"; case .leftWing: "Left wing"; case .rightWing: "Right wing"; case .tail: "Tail" }
    }
}

/// A stroke must cross the panel and reverse direction. Jitter and stationary holds do not count.
struct BrushRepetitions {
    private(set) var halfStrokes = 0
    private var edge: Int?
    let requiredHalfStrokes = 8
    var fill: Float { min(1,Float(halfStrokes)/Float(requiredHalfStrokes)) }
    var complete: Bool { halfStrokes >= requiredHalfStrokes }
    mutating func update(horizontal: Float, inside: Bool) {
        guard inside else { return }
        let next = horizontal < -0.025 ? -1 : (horizontal > 0.025 ? 1 : 0)
        guard next != 0 else { return }
        if let edge, edge != next { halfStrokes += 1 }
        edge = next
    }
    mutating func release() { edge = nil }
}

/// One cue per directional sweep. Another cue requires a deliberate reversal,
/// not more distance or elapsed time in the same direction.
struct BrushSoundMotion {
    private var extreme: Float?
    private var direction = 0
    private let minimumTravel: Float = 0.018
    mutating func reset() { extreme = nil; direction = 0 }
    mutating func update(horizontal: Float, touching: Bool, deltaTime: Float) -> Bool {
        guard touching, horizontal.isFinite, deltaTime.isFinite, deltaTime > 0 else { reset(); return false }
        guard let extreme else { self.extreme = horizontal; return false }
        if direction == 0 {
            let travel = horizontal-extreme
            guard abs(travel)>=minimumTravel else { return false }
            direction = travel > 0 ? 1 : -1
            self.extreme = horizontal
            return true
        }
        if direction > 0 {
            if horizontal > extreme { self.extreme = horizontal }
            else if extreme-horizontal >= minimumTravel {
                direction = -1; self.extreme = horizontal; return true
            }
        } else {
            if horizontal < extreme { self.extreme = horizontal }
            else if horizontal-extreme >= minimumTravel {
                direction = 1; self.extreme = horizontal; return true
            }
        }
        return false
    }
}
