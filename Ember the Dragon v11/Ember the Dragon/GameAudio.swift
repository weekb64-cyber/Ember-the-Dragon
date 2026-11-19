import AVFoundation
import UIKit

/// Quiet, original UI sounds, including Moonlit Shimmer and tactile scale/paint effects. Eight short, lazily cached clips; no music or additional spatial renderers.
@MainActor
final class GameAudio {
    enum Cue: String { case tap = "EmberTap", success = "EmberSuccess", complete = "EmberComplete", shutter = "EmberShutter", scalePickup = "EmberScalePickup", scalePlace = "EmberScalePlace", paintDip = "EmberPaintDip", brushStroke = "EmberBrushStroke" }
    static let shared = GameAudio()
    var isEnabled = UserDefaults.standard.object(forKey:"EmberSoundEffects") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(isEnabled,forKey:"EmberSoundEffects")
            if !isEnabled { players.values.forEach { $0.stop() } }
        }
    }
    private var players: [Cue:AVAudioPlayer] = [:]
    private var lastPlayed: [Cue:TimeInterval] = [:]
    private var configured = false
    func stop(_ cue: Cue) { players[cue]?.stop() }
    func play(_ cue: Cue) {
        guard isEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Brush cues are already gated once per deliberate directional sweep.
        guard cue == .brushStroke || now-(lastPlayed[cue] ?? -1) >= 0.10 else { return }
        do {
            if !configured {
                try AVAudioSession.sharedInstance().setCategory(.ambient,mode:.default,options:[.mixWithOthers])
                configured = true
            }
            if players[cue] == nil {
                guard let asset = NSDataAsset(name:cue.rawValue) else { return }
                let player = try AVAudioPlayer(data:asset.data)
                player.volume = cue == .brushStroke ? 0.32 : (cue == .scalePickup || cue == .paintDip ? 0.42 : 0.55); player.prepareToPlay(); players[cue] = player
            }
            if cue == .complete { players[.success]?.stop() }
            let player = players[cue]!
            player.currentTime = 0
            if player.play() { lastPlayed[cue] = now }
        } catch {
            // Audio is optional: a busy or interrupted audio session must never block gameplay.
        }
    }
}
