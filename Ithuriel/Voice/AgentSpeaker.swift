import Foundation
import AVFoundation

/// Speaks the agent's final summary out loud. Three-tier strategy so the
/// consumer flow works with just a Gemini API key — no separate GCP enablement,
/// no service account, nothing else to set up.
///
///   1. **Gemini TTS** via `generativelanguage.googleapis.com/v1beta/models/
///      gemini-2.5-flash-preview-tts`. The Gemini key already speaks to this
///      endpoint, so it works the moment the user pastes a key.
///   2. **Google Cloud TTS** via `texttospeech.googleapis.com`. Higher-quality
///      Neural2 voices, but requires the user's key to have the
///      `texttospeech.googleapis.com` service enabled (most consumer keys
///      don't). Only used when path 1 fails.
///   3. **Apple `AVSpeechSynthesizer`**. Free, instant, offline. Final fallback
///      so the agent never goes silent.
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

        let geminiKey = prefs.geminiApiKey
        let cloudKey  = prefs.googleCloudAPIKey.isEmpty ? geminiKey : prefs.googleCloudAPIKey

        inFlight = Task { [weak self] in
            guard let self else { return }

            // Path 1: Gemini TTS — works with the consumer Gemini key.
            if !geminiKey.isEmpty {
                do {
                    let audio = try await GeminiTTS.synthesize(
                        text: cleaned, apiKey: geminiKey, voice: prefs.geminiTTSVoice
                    )
                    guard !Task.isCancelled else { return }
                    try self.playRawAudio(audio)
                    return
                } catch {
                    Log.info("Gemini TTS unavailable (\(error)) — trying Cloud TTS")
                }
            }

            // Path 2: Google Cloud TTS (Neural2 voices).
            if !cloudKey.isEmpty {
                do {
                    let audio = try await GoogleSpeech.synthesize(
                        text: cleaned, apiKey: cloudKey, voice: prefs.ttsVoice, rate: prefs.ttsRate
                    )
                    guard !Task.isCancelled else { return }
                    try self.playRawAudio(audio)
                    return
                } catch {
                    Log.info("Cloud TTS unavailable (\(error)) — falling back to AVSpeechSynthesizer")
                }
            }

            // Path 3: Apple on-device speech. Always available.
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

    private func playRawAudio(_ data: Data) throws {
        let p = try AVAudioPlayer(data: data)
        p.prepareToPlay()
        p.volume = 0.85
        p.play()
        self.player = p
    }
}
