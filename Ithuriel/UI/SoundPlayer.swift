import Foundation
import AVFoundation

/// Tiny sound effects for the agent loop. Sourced from the Blink companion
/// repo so the two apps share an audio identity. Mute via UserDefaults
/// `Ithuriel.SoundsMuted`.
enum AgentSound: String, CaseIterable {
    case submit = "enter"
    case tool = "eshop"
    case done = "agent-done"

    var resource: String { rawValue }
}

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private var players: [String: AVAudioPlayer] = [:]
    private let mutedKey = "Ithuriel.SoundsMuted"

    var muted: Bool {
        get { UserDefaults.standard.bool(forKey: mutedKey) }
        set { UserDefaults.standard.set(newValue, forKey: mutedKey) }
    }

    private init() {
        // Pre-warm players to avoid first-play latency.
        for sound in AgentSound.allCases {
            _ = player(for: sound)
        }
    }

    func play(_ sound: AgentSound, volume: Float = 0.6) {
        guard !muted, let player = player(for: sound) else { return }
        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    private func player(for sound: AgentSound) -> AVAudioPlayer? {
        if let cached = players[sound.resource] { return cached }
        guard let url = Bundle.main.url(forResource: sound.resource, withExtension: "mp3") else {
            return nil
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[sound.resource] = player
        return player
    }
}
