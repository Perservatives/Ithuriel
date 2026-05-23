import Foundation
import AVFoundation

/// Speaks the agent's final summary via Google Cloud TTS. Singleton so we
/// can replace any in-flight playback before starting the next one. Falls back
/// silently if no Google Cloud / Gemini key is configured — the app still
/// works as a typing-only experience.
@MainActor
final class AgentSpeaker {
    static let shared = AgentSpeaker()
    private init() {}

    private var player: AVAudioPlayer?
    private var inFlight: Task<Void, Never>?

    /// Fire-and-forget. Speaks asynchronously; stops any current playback.
    func speakAsync(_ text: String, prefs: UserPrefs) {
        guard prefs.spokenResponsesEnabled else { return }
        let key = prefs.googleCloudAPIKey.isEmpty ? prefs.geminiApiKey : prefs.googleCloudAPIKey
        guard !key.isEmpty else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        inFlight?.cancel()
        player?.stop()

        inFlight = Task { [weak self] in
            guard let self else { return }
            do {
                let audio = try await GoogleSpeech.synthesize(
                    text: cleaned, apiKey: key, voice: prefs.ttsVoice, rate: prefs.ttsRate
                )
                guard !Task.isCancelled else { return }
                let p = try AVAudioPlayer(data: audio)
                p.prepareToPlay()
                p.volume = 0.85
                p.play()
                self.player = p
            } catch {
                Log.error("AgentSpeaker failed: \(error)")
            }
        }
    }

    func stop() {
        inFlight?.cancel()
        player?.stop()
        player = nil
    }
}
