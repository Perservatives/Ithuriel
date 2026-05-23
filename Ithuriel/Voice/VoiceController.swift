import AVFoundation
import AppKit
import SwiftData

/// Bridges the press-and-hold ⌥Space hotkey to the Google Speech-to-Text
/// → AgentLoop → Text-to-Speech pipeline.
///
/// While recording, a full-width "Listening" pill appears at the bottom of the
/// chat window — matching the ChatGPT mobile composer composition (X · waveform
/// + label · send arrow).
@MainActor
final class VoiceController {
    static let shared = VoiceController()
    private init() {}

    private let recorder = MicRecorder()
    private var player: AVAudioPlayer?
    private weak var container: ModelContainer?
    private weak var agentLoop: AgentLoop?
    private var indicator: NSWindow?

    func configure(container: ModelContainer, agentLoop: AgentLoop) {
        self.container = container
        self.agentLoop = agentLoop
    }

    func start() {
        Task {
            let ok = await recorder.requestPermission()
            guard ok else { return }
            do {
                try recorder.start()
                showIndicator()
                SoundPlayer.shared.play(.summon, volume: 0.3)
            } catch {
                Log.error("MicRecorder start failed: \(error)")
            }
        }
    }

    func stopAndSubmit() {
        let data = recorder.stop()
        hideIndicator()
        SoundPlayer.shared.play(.submit, volume: 0.5)
        guard !data.isEmpty,
              let container = container,
              let loop = agentLoop else { return }
        Task {
            let prefs = (try? UserPrefs.load(in: container)) ?? UserPrefs.defaults()
            guard let text = await Self.transcribe(pcm16: data, prefs: prefs), !text.isEmpty else {
                Log.error("STT: no key configured or all backends failed.")
                return
            }
            Log.info("STT: \(text)")
            await loop.run(task: text)
        }
    }

    /// Cancels an in-flight recording without transcribing or submitting.
    /// Hides the pill and plays the dismiss sound.
    func cancel() {
        _ = recorder.stop()
        hideIndicator()
        SoundPlayer.shared.play(.dismiss, volume: 0.4)
    }

    /// Two-tier STT. Primary: OpenAI Whisper. Fallback: Google Cloud Speech.
    private static func transcribe(pcm16: Data, prefs: UserPrefs) async -> String? {
        if !prefs.openAIAPIKey.isEmpty {
            do {
                return try await OpenAISpeech.transcribe(pcm16: pcm16, apiKey: prefs.openAIAPIKey)
            } catch {
                Log.info("OpenAI Whisper unavailable (\(error)) — trying Google STT")
            }
        }
        let googleKey = prefs.googleCloudAPIKey.isEmpty ? prefs.geminiApiKey : prefs.googleCloudAPIKey
        guard !googleKey.isEmpty else { return nil }
        do {
            return try await GoogleSpeech.transcribe(pcm16: pcm16, apiKey: googleKey)
        } catch {
            Log.error("All STT backends failed: \(error)")
            return nil
        }
    }

    private func speak(_ text: String, apiKey: String) async throws {
        let audio = try await GoogleSpeech.synthesize(text: text, apiKey: apiKey)
        try await MainActor.run {
            let p = try AVAudioPlayer(data: audio)
            p.prepareToPlay()
            p.volume = 0.8
            p.play()
            self.player = p
        }
    }

    // MARK: - Listening pill

    private static let pillHeight: CGFloat = 64
    private static let sidePadding: CGFloat = 12
    private static let bottomOffset: CGFloat = 24

    private func showIndicator() {
        guard indicator == nil else { return }
        let frame = pillFrame()
        let w = NSWindow(contentRect: frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        // Need mouse events for the X / send buttons.
        w.ignoresMouseEvents = false
        let host = NSHostingView(rootView: ListeningPill())
        w.contentView = host
        w.orderFrontRegardless()
        indicator = w
    }

    private func hideIndicator() {
        indicator?.orderOut(nil)
        indicator = nil
    }

    /// Anchor the pill to the chat window's bottom (full width minus 24pt
    /// padding). Falls back to bottom-centre of the main screen, ~720pt wide.
    private func pillFrame() -> NSRect {
        let height = Self.pillHeight
        let sidePad = Self.sidePadding
        let bottomPad = Self.bottomOffset

        // Try to find the chat window first.
        if let chat = NSApp.windows.first(where: { $0.title == "Ithuriel" && $0.isVisible }) {
            let f = chat.frame
            let width = max(320, f.width - sidePad * 2)
            let x = f.minX + (f.width - width) / 2
            let y = f.minY + bottomPad
            return NSRect(x: x, y: y, width: width, height: height)
        }

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let width: CGFloat = 720
        let x = screen.frame.midX - width / 2
        let y = screen.frame.minY + 96
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

import SwiftUI

/// Full-width "Listening" pill: leading X (cancel), centred animated waveform
/// + label, trailing dark send button. Matches the ChatGPT mobile composer.
private struct ListeningPill: View {
    var body: some View {
        HStack(spacing: 14) {
            CancelButton()
            Spacer(minLength: 8)
            WaveformLabel()
            Spacer(minLength: 8)
            SendButton()
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color.white.opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 8)
        .padding(.horizontal, 0)
    }
}

private struct CancelButton: View {
    @State private var hover = false
    var body: some View {
        Button {
            VoiceController.shared.cancel()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .resizable()
                .renderingMode(.template)
                .frame(width: 32, height: 32)
                .foregroundStyle(Color.black.opacity(hover ? 0.85 : 0.65))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Cancel")
    }
}

private struct SendButton: View {
    @State private var hover = false
    var body: some View {
        Button {
            VoiceController.shared.stopAndSubmit()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(hover ? 0.85 : 1.0))
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Send")
    }
}

/// Centred set of pulsing bars + bold "Listening" label.
private struct WaveformLabel: View {
    var body: some View {
        HStack(spacing: 10) {
            Waveform()
            Text("Listening")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.85))
        }
    }
}

private struct Waveform: View {
    private let barCount = 8
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<barCount, id: \.self) { i in
                WaveBar(delay: Double(i) * 0.08)
            }
        }
        .frame(height: 24)
    }
}

private struct WaveBar: View {
    let delay: Double
    @State private var tall = false
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.black.opacity(0.78))
            .frame(width: 3, height: tall ? 22 : 8)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    tall = true
                }
            }
    }
}
