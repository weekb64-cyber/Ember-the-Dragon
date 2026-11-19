import Foundation
import RealityKit

@MainActor
final class AudioManager {
    enum Cue: String {
        case grab
        case snap
        case sparkle
        case stretch
        case rotateSuccess
        case brushing
        case dragonHappy
        case finalCelebration
    }

    private var resources: [Cue: AudioFileResource] = [:]

    init() {
        loadOptionalAudio()
    }

    func play(_ cue: Cue, from entity: Entity?) {
        guard let resource = resources[cue], let entity else { return }
        entity.playAudio(resource)
    }

    private func loadOptionalAudio() {
        for cue in Cue.allCases {
            if let resource = try? AudioFileResource.load(named: cue.rawValue) {
                resources[cue] = resource
            }
        }
    }
}

extension AudioManager.Cue: CaseIterable {}
