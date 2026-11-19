import Foundation

/// A stage requests only the models it can display. Environment clones own their resources separately.
enum AssetResidency {
    static let environment: Set<String> = ["BushVisual", "RockVisual", "MushroomVisual"]
    static let portrait: Set<String> = ["EmberAwakeFullVisual", "MagicScaleVisual_Grey"]
    static func assets(for phase: GamePhase) -> Set<String> {
        switch phase {
        case .introduction: return ["EmberSleepingWinglessHornlessVisual"]
        case .magicSetup: return ["EmberAwakeWinglessHornlessVisual"]
        case .horns: return ["EmberAwakeWinglessHornlessVisual", "HornVisual"]
        case .wings, .bilateralSetup: return ["EmberAwakeWinglessHornlessVisual", "HornVisual", "WingVisual"]
        case .scales, .precisionSetup, .hornAlignment:
            return ["EmberAwakeWinglessHornlessVisual", "HornVisual", "WingVisual", "MagicScaleVisual_Grey"]
        case .painting:
            return ["EmberAwakeWinglessHornlessVisual", "HornVisual", "WingVisual", "MagicScaleVisual_Grey"]
        case .celebration, .complete: return portrait
        case .paused: return [] // Pausing preserves the existing stage; no new request is made.
        }
    }
}

struct AssetDemand {
    private var owners: [String:Set<String>] = [:]
    var wanted: Set<String> { owners.values.reduce(into:Set<String>()) { $0.formUnion($1) } }
    mutating func request(_ names: Set<String>, owner: String) { owners[owner] = names }
    mutating func release(_ owner: String) { owners.removeValue(forKey:owner) }
}
