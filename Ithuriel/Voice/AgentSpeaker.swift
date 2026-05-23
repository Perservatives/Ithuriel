import Foundation
import AVFoundation

/// Speaks the agent's final summary out loud. Two-tier strategy so this works
/// for a consumer with zero GCP setup:
///   1. Try Google Cloud TTS (high-quality Neural2 voice) — only if the user
///      has a Google Cloud API key that the project has Text-to-Speech
///      enabled on.
///   2. On failure (no key, blocked by API restrictions, network error), fall
///      back to Apple's on-device `AVSpeechSynthesizer`. Free, instant,
///      offline, sounds fine.
@MainActor
final class AgentSpeaker {
    static let shared = AgentSpeaker()
    private init() {}

    private var player: AVAudioPlayer?
    private let appleSynth = AVSpeechSynthesizer()
    private var inFlight: Task<Void, Never>?

    /// Fire-and-forget. Speaks asynchronously; stops any current playback.
    func speakAsync(_ text: String, prefs: UserPrefs) {
        guard prefs.spokenResponsesEnabled else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        inFlight?.cancel()
        player?.stop()
        appleSynth.stopSpeaking(at: .immediate)

        let cloudKey = prefs.googleCloudAPIKey.isEmpty ? prefs.geminiApiKey : prefs.googleCloudAPIKey

        inFlight = Task { [weak self] in
            guard let self else { return }
            // Path 1: Google Cloud TTS, if we have any key at all.
            if !cloudKey.isEmpty {
                do {
                    let audio = try await GoogleSpeech.synthesize(
                        text: cleaned, apiKey: cloudKey, voice: prefs.ttsVoice, rate: prefs.ttsRate
                    )
                    guard !Task.isCancelled else { return }
                    let p = try AVAudioPlayer(data: audio)
                    p.prepareToPlay()
                    p.volume = 0.85
                    p.play()
                    self.player = p
                    return
                } catch {
                    Log.info("Google TTS unavailable (\(error)) — falling back to AVSpeechSynthesizer")
                }
            }
            // Path 2: Apple on-device speech. Always available.
            guard !Task.isCancelled else { return }
            let utterance = AVSpeechUtterance(string: cleaned)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(prefs.ttsRate)
            utterance.volume = 0.85
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            self.appleSynth.speak(utterance)
        }
    }

    func stop() {
        inFlight?.cancel()
        player?.stop()
        player = nil
        appleSynth.stopSpeaking(at: .immediate)
    }
}
