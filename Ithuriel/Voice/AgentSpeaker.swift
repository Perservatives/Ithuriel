import Foundation
import AVFoundation

/// Speaks the agent's final summary out loud. Cascading fallback so the user
/// never hears silence:
///
///   1. **OpenAI TTS** (`gpt-4o-mini-tts`) — primary. One `sk-…` key covers
///      both this and Whisper STT, so it's the default consumer path.
///   2. **Gemini TTS** (`gemini-2.5-flash-preview-tts`) — used when no OpenAI
///      key is set but a Gemini key is. Works without enabling any extra
///      GCP services.
///   3. **Google Cloud TTS** (`texttospeech.googleapis.com`) — Neural2 voices,
///      requires a key whose project has the service enabled.
///   4. **Apple `AVSpeechSynthesizer`** — free, offline, never silent.
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

        let openAIKey = prefs.openAIAPIKey
        let geminiKey = prefs.geminiApiKey
        let cloudKey  = prefs.googleCloudAPIKey.isEmpty ? geminiKey : prefs.googleCloudAPIKey

        inFlight = Task { [weak self] in
            guard let self else { return }

            // Path 1: OpenAI TTS — primary consumer path.
            if !openAIKey.isEmpty {
                do {
                    let audio = try await OpenAISpeech.synthesize(
                        text: cleaned, apiKey: openAIKey,
                        model: prefs.openAITTSModel, voice: prefs.openAITTSVoice,
                        speed: prefs.ttsRate
                    )
                    guard !Task.isCancelled else { return }
                    try self.playRawAudio(audio)
                    return
                } catch {
                    Log.info("OpenAI TTS unavailable (\(error)) — trying Gemini TTS")
                }
            }

            // Path 2: Gemini TTS via the Generative Language API.
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

            // Path 3: Google Cloud TTS (Neural2 voices).
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

            // Path 4: Apple on-device speech. Always available.
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
