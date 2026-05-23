import AVFoundation
import AppKit
import SwiftData

/// Bridges the press-and-hold ⌥Space hotkey to the Google Speech-to-Text
/// → AgentLoop → Text-to-Speech pipeline.
///
/// While recording, a small "Listening…" pill appears at the top centre.
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

    private func showIndicator() {
        guard indicator == nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: 180, height: 44)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - 80,
            width: size.width, height: size.height
        )
        let w = NSWindow(contentRect: frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.level = .floating
        w.ignoresMouseEvents = true
        let host = NSHostingView(rootView: ListeningPill())
        w.contentView = host
        w.orderFrontRegardless()
        indicator = w
    }

    private func hideIndicator() {
        indicator?.orderOut(nil)
        indicator = nil
    }
}

import SwiftUI

private struct ListeningPill: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.35 : 1)
            Text("Listening…")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                LinearGradient(colors: [.white.opacity(0.04), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
