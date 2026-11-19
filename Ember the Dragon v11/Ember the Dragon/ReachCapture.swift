import Foundation

/// Four measured poses. Vertical/near excursions are conservative estimates, not extra required holds.
struct ReachCapture {
    static let directions: [SIMD3<Float>] = [.zero, [0,0,-1], [-1,0,0], [1,0,0]]
    static let prompts = ["Rest one open hand in front of you.", "Reach to your comfortable forward limit. Hold there.", "Reach to your comfortable left limit. Hold there.", "Reach to your comfortable right limit. Hold there."]
    private(set) var samples: [SIMD3<Float>] = []
    private var previous: SIMD3<Float>?
    private var stableTime: Float = 0
    private var stepTime: Float = 0
    private var filtered: SIMD3<Float>?
    var holdProgress: Float { let t = min(stableTime / 0.9,1); return t*t }
    var complete: Bool { samples.count == Self.directions.count }
    var instruction: String { complete ? "Reach saved. Continue when ready." : Self.prompts[samples.count] }
    var direction: SIMD3<Float> { complete ? .zero : Self.directions[samples.count] }
    var envelopeSamples: [SIMD3<Float>] {
        guard complete else { return [] }
        let c = samples[0]
        let vertical = min(0.09, max(0.025, min(abs(samples[2].x-c.x),abs(samples[3].x-c.x))*0.35))
        let near = min(0.07,max(0.02,abs(samples[1].z-c.z)*0.3))
        return samples + [c+[0,vertical,0],c-[0,vertical,0],c+[0,0,near]]
    }
    mutating func loseTracking() { previous = nil; filtered = nil; stableTime = 0 }
    mutating func update(position: SIMD3<Float>?, deltaTime: Float) -> Bool {
        guard !complete, let position, position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            loseTracking(); return false
        }
        let dt = min(max(deltaTime,0),0.05)
        guard dt > 0 else { return false }
        stepTime += dt
        let smoothed = filtered.map { $0+(position-$0)*min(dt*16,1) } ?? position
        filtered = smoothed
        defer { previous = smoothed }
        if let neutral = samples.first {
            let d = smoothed-neutral
            let projected = d.x*direction.x+d.y*direction.y+d.z*direction.z
            guard projected >= 0.04 else { stableTime = 0; return false }
        }
        guard let previous else { return false }
        let d = smoothed-previous
        let speed = sqrt(d.x*d.x+d.y*d.y+d.z*d.z)/dt
        guard speed < 0.16 else { stableTime = max(0,stableTime-dt*2); return false }
        guard samples.isEmpty || stepTime >= 1.4 else { stableTime = 0; return false }
        stableTime += dt
        guard stableTime >= 0.9 else { return false }
        samples.append(smoothed); stableTime = 0; stepTime = 0; self.previous = nil
        return true
    }
}
