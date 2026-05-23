import AVFoundation
import AppKit
import Combine
import SwiftData

/// Bridges press-and-hold hotkeys and composer mic buttons to OpenAI Whisper
/// → AgentLoop.
///
/// While recording, a full-width "Listening" pill appears at the bottom of the
/// chat window — matching the ChatGPT mobile composer composition (X · waveform
/// + label · send arrow).
@MainActor
final class VoiceController: ObservableObject {
    static let shared = VoiceController()
    private init() {}

    @Published private(set) var isListening = false

    private let recorder = MicRecorder()
    private var player: AVAudioPlayer?
    private weak var container: ModelContainer?
    private weak var agentLoop: AgentLoop?
    private var indicator: NSWindow?
    private var isStarting = false

    func configure(container: ModelContainer, agentLoop: AgentLoop) {
        self.container = container
        self.agentLoop = agentLoop
    }

    /// Starts recording. Returns false if permission or hardware setup failed.
    @discardableResult
    func start() async -> Bool {
        guard !isListening, !isStarting else { return isListening }
        isStarting = true
        defer { isStarting = false }

        let ok = await recorder.requestPermission()
        guard ok else {
            showVoiceError(NSLocalizedString("voice.error.permission", comment: ""))
            return false
        }
        do {
            try recorder.start()
            isListening = true
            showIndicator()
            SoundPlayer.shared.play(.summon, volume: 0.3)
            return true
        } catch {
            isListening = false
            Log.error("MicRecorder start failed: \(error)")
            showVoiceError(error.localizedDescription)
            return false
        }
    }

    /// Hotkey release — transcribe and hand the text straight to the agent.
    func stopAndSubmit() {
        Task { @MainActor in
            SoundPlayer.shared.play(.submit, volume: 0.5)
            guard let text = await stopAndTranscribe(showErrors: false), !text.isEmpty,
                  let loop = agentLoop else { return }
            await loop.run(task: text)
        }
    }

    /// Cancels an in-flight recording without transcribing or submitting.
    func cancel() {
        guard isListening else { return }
        _ = recorder.stop()
        hideIndicator()
        isListening = false
        SoundPlayer.shared.play(.dismiss, volume: 0.4)
    }

    /// Composer mic — stop recording and return transcribed text via Whisper.
    func stopAndTranscribe(showErrors: Bool = true) async -> String? {
        let data = stopRecording()
        guard data.count > 512 else {
            if showErrors {
                showVoiceError(NSLocalizedString("voice.error.empty", comment: ""))
            }
            return nil
        }
        guard let container else { return nil }
        let prefs = (try? UserPrefs.load(in: container)) ?? UserPrefs.defaults()
        let apiKey = prefs.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            if showErrors {
                showVoiceError(NSLocalizedString("voice.error.noOpenAIKey", comment: ""))
            }
            return nil
        }
        do {
            let text = try await OpenAISpeech.transcribe(audioFile: data, apiKey: apiKey)
            guard !text.isEmpty else {
                if showErrors {
                    showVoiceError(NSLocalizedString("voice.error.empty", comment: ""))
                }
                return nil
            }
            Log.info("Whisper: \(text)")
            return text
        } catch {
            Log.error("Whisper failed: \(error)")
            if showErrors {
                let detail = (error as? OpenAISpeech.Failure).map(\.description) ?? error.localizedDescription
                showVoiceError(String(format: NSLocalizedString("voice.error.whisper", comment: ""), detail))
            }
            return nil
        }
    }

    @discardableResult
    private func stopRecording() -> Data {
        guard isListening else { return Data() }
        let data = recorder.stop()
        hideIndicator()
        isListening = false
        return data
    }

    private func showVoiceError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("voice.error.title", comment: "")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
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

    private func pillFrame() -> NSRect {
        let height = Self.pillHeight
        let sidePad = Self.sidePadding
        let bottomPad = Self.bottomOffset

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
