import Foundation
import AVFoundation
import AppKit

/// Tiny sound effects for the agent. Bundled mp3s preferred; falls back to
/// macOS system sounds (`NSSound(named:)`) when an mp3 isn't shipped yet so
/// the launch sequence still has audio out of the box. Mute via UserDefaults
/// `Ithuriel.SoundsMuted`.
enum AgentSound: String, CaseIterable {
    case submit  = "enter"
    case tool    = "eshop"
    case done    = "agent-done"
    case launch  = "launch"
    case summon  = "summon"
    case dismiss = "dismiss"

    var resource: String { rawValue }

    /// System fallback played via `NSSound(named:)` when no bundled mp3 exists.
    /// Picked so the launch chord still feels intentional out of the box.
    var systemFallback: String? {
        switch self {
        case .launch:  return "Glass"
        case .summon:  return "Tink"
        case .dismiss: return "Pop"
        case .submit:  return "Morse"
        case .done:    return "Hero"
        case .tool:    return "Tink"
        }
    }
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
        for sound in AgentSound.allCases {
            _ = player(for: sound)
        }
    }

    func play(_ sound: AgentSound, volume: Float = 0.6) {
        guard !muted else { return }
        if let player = player(for: sound) {
            player.currentTime = 0
            player.volume = volume
            player.play()
            return
        }
        if let name = sound.systemFallback,
           let ns = NSSound(named: NSSound.Name(name)) {
            ns.volume = volume
            ns.stop()
            ns.play()
        }
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
