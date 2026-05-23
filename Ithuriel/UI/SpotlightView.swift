import SwiftUI
import SwiftData
import AppKit

/// The headline product surface. A floating pill at the centre of the screen.
/// Liquid-glass background, asterisk-burst icon, prompt, submit button.
/// While the agent runs, the pill expands downward to reveal the transcript.
struct SpotlightView: View {
    @ObservedObject var agent: AgentLoop
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @FocusState private var fieldFocus: Bool
    @State private var prompt: String = ""
    @State private var iconRotation: Double = 0
    @State private var enterProgress: Double = 0

    let onDismiss: () -> Void

    private var prefs: UserPrefs? { prefsList.first }
    private var keyMissing: Bool { (prefs?.geminiApiKey ?? "").isEmpty }
    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !agent.isRunning && !keyMissing
    }
    private var showsTranscript: Bool { agent.isRunning || !agent.transcript.isEmpty || agent.lastError != nil }

    var body: some View {
        VStack(spacing: 0) {
            promptPill
            if showsTranscript {
                transcriptPanel
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .frame(width: 620)
        .scaleEffect(0.96 + 0.04 * enterProgress, anchor: .center)
        .opacity(enterProgress)
        .blur(radius: (1 - enterProgress) * 6)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.45), value: showsTranscript)
        .onAppear {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.42)) {
                enterProgress = 1
            }
            // Slow continuous orbit — decorative, alive.
            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                iconRotation = 360
            }
            fieldFocus = true
        }
        .background(
            KeyEventCatcher { event in
                if event.keyCode == 53 { // escape
                    requestDismiss()
                    return true
                }
                return false
            }
        )
    }

    // MARK: - Pill

    private var promptPill: some View {
        HStack(spacing: 14) {
            AsteriskBurst(rotation: iconRotation,
                          petalScale: agent.isRunning ? 1.12 : 1.0,
                          tint: keyMissing ? .orange : .accentColor,
                          glowRadius: agent.isRunning ? 16 : 10)
                .frame(width: 34, height: 34)
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5), value: agent.isRunning)

            VStack(alignment: .leading, spacing: 1) {
                Text(headlineText)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                if keyMissing {
                    Text(NSLocalizedString("spotlight.subhead.needsKey", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let workspace = workspaceTagline {
                    Text(workspace)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(height: 38, alignment: .center)
            .opacity(prompt.isEmpty ? 1 : 0)
            .allowsHitTesting(false)
            .overlay(alignment: .leading) { promptField }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: newConversation) {
                    Text(NSLocalizedString("spotlight.newChat", comment: ""))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.85)

                submitButton
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(pillBackground)
    }

    private var promptField: some View {
        TextField("", text: $prompt, axis: .vertical)
            .lineLimit(1...3)
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .focused($fieldFocus)
            .onSubmit(runAgent)
            .disabled(agent.isRunning || keyMissing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
    }

    private var submitButton: some View {
        Button(action: runAgent) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(canSubmit
                          ? LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.31),
                                                   Color(red: 0.94, green: 0.30, blue: 0.22)],
                                           startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.secondary.opacity(0.25),
                                                   Color.secondary.opacity(0.15)],
                                           startPoint: .top, endPoint: .bottom))
                    .frame(width: 36, height: 32)
                    .shadow(color: canSubmit ? Color(red: 1, green: 0.45, blue: 0.32).opacity(0.6) : .clear,
                            radius: canSubmit ? 10 : 0)
                Image(systemName: agent.isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.pressable(scale: 0.92, sound: .submit))
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!canSubmit && !agent.isRunning)
        .onTapGesture { if agent.isRunning { agent.stop() } }
    }

    @ViewBuilder
    private var pillBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            // Soft inner glow gradient
            LinearGradient(
                colors: [Color.white.opacity(0.06), Color.white.opacity(0.0)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    // MARK: - Transcript

    private var transcriptPanel: some View {
        VStack(spacing: 8) {
            Rectangle().fill(.clear).frame(height: 8)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(agent.transcript.suffix(8).enumerated()), id: \.offset) { idx, line in
                    SpotlightTranscriptLine(line: line)
                        .staggered(idx)
                }
                if let err = agent.lastError {
                    Text(err)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                    LinearGradient(colors: [Color.white.opacity(0.03), .clear],
                                   startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        }
    }

    // MARK: - Helpers

    private var headlineText: String {
        if agent.isRunning { return NSLocalizedString("spotlight.headline.running", comment: "") }
        return NSLocalizedString("spotlight.headline.idle", comment: "")
    }

    private var workspaceTagline: String? {
        guard let ws = prefs?.activeWorkspace, !ws.isEmpty else { return nil }
        return (ws as NSString).lastPathComponent
    }

    private func runAgent() {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !agent.isRunning else { return }
        prompt = ""
        Task { await agent.run(task: task) }
    }

    private func newConversation() {
        prompt = ""
        fieldFocus = true
    }

    private func requestDismiss() {
        SoundPlayer.shared.play(.dismiss, volume: 0.35)
        withAnimation(.easeOut(duration: 0.16)) { enterProgress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { onDismiss() }
    }
}

// MARK: - Transcript line

private struct SpotlightTranscriptLine: View {
    let line: String

    var body: some View {
        let parts = decompose(line)
        HStack(alignment: .top, spacing: 8) {
            Text(parts.symbol)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(parts.tint)
                .frame(width: 14, alignment: .leading)
            Text(parts.content)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.88))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
    }

    private func decompose(_ line: String) -> (symbol: String, content: String, tint: Color) {
        let rest = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("▶") { return ("▶", rest, .accentColor) }
        if line.hasPrefix("→") { return ("→", rest, .blue) }
        if line.hasPrefix("✓") { return ("✓", rest, .green) }
        if line.hasPrefix("✗") { return ("✗", rest, .red) }
        if line.hasPrefix("■") { return ("■", rest, .orange) }
        if line.hasPrefix("◌") { return ("◌", rest, .secondary) }
        if line.hasPrefix("·") { return ("·", rest, .secondary) }
        return (" ", line, .secondary)
    }
}

// MARK: - Key event catcher (ESC to dismiss without stealing first responder)

struct KeyEventCatcher: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = CatcherView()
        view.onKey = onKey
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? CatcherView)?.onKey = onKey
    }

    private class CatcherView: NSView {
        var onKey: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard self?.window?.isKeyWindow == true else { return event }
                    if self?.onKey?(event) == true { return nil }
                    return event
                }
            } else if window == nil, let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
    }
}
