import SwiftUI
import SwiftData
import AppKit

/// The headline product surface. A floating pill at the centre of the screen.
/// Liquid-glass background, asterisk-burst icon, prompt, submit button.
/// While the agent runs, the pill expands downward to reveal the transcript.
struct SpotlightView: View {
    @ObservedObject var agent: AgentLoop
    @ObservedObject private var statusBus = AgentStatusBus.shared
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
    @ObservedObject private var permissions = PermissionsManager.shared

    private var spotlightMaxHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? 800
        return screen * UILayout.spotlightMaxHeightRatio
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UILayout.spacingM) {
            if permissions.hasRefreshed && permissions.needsRequired {
                PermissionsBanner()
            }
            promptPill
            if showsTranscript {
                transcriptPanel
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.97, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
            AppChromeBar(placement: .spotlight, compact: true)
                .padding(.horizontal, UILayout.spacingXS)
        }
        .padding(UILayout.spacingM)
        .frame(width: UILayout.spotlightWidth)
        .frame(maxHeight: spotlightMaxHeight)
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
        .task { await PermissionsManager.shared.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await PermissionsManager.shared.refresh() }
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
                Button(action: openFullChat) {
                    Text(NSLocalizedString("chrome.openChat", comment: ""))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(0.85)

                submitButton
            }
        }
        .padding(.leading, UILayout.spacingL)
        .padding(.trailing, UILayout.spacingM)
        .padding(.vertical, UILayout.spacingM)
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
            Color(nsColor: .windowBackgroundColor).opacity(0.72)
            VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
            LinearGradient(
                colors: [Color.primary.opacity(0.06), Color.primary.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
        // Single light shadow — the heavy two-layer drop shadow was reading
        // as a halo on screen. Keeping it subtle so the pill feels weightless.
        .shadow(color: .black.opacity(0.16), radius: 12, y: 6)
    }

    // MARK: - Transcript

    private var transcriptPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UILayout.spacingS) {
                TranscriptChip(transcript: agent.transcript,
                               verbosity: prefs?.transcriptVerbosity ?? 1)
                if let err = agent.lastError {
                    Text(err)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.top, UILayout.spacingXS)
                }
            }
            .padding(UILayout.spacingL)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 280)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.65)
                VisualEffectBlur(material: .popover, blendingMode: .behindWindow)
            }
            .clipShape(RoundedRectangle(cornerRadius: UILayout.radiusM, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UILayout.radiusM, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private var headlineText: String {
        // When the agent is working, surface its most recent plain-English
        // narration (via the `say` tool) so the user reads what it's
        // thinking, not a static "Working on it…". Fall back to the static
        // copy until the first `say` arrives.
        if agent.isRunning {
            if let spoken = statusBus.lastSpoken, !spoken.isEmpty {
                return spoken
            }
            return NSLocalizedString("spotlight.headline.running", comment: "")
        }
        // After a run finishes, briefly keep the agent's last spoken summary
        // visible so the user reads it instead of jumping back to the idle
        // greeting.
        if let spoken = statusBus.lastSpoken, !spoken.isEmpty,
           !agent.transcript.isEmpty {
            return spoken
        }
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

    private func openFullChat() {
        requestDismiss()
        AppRouter.shared.openChat()
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
        let p = AgentTranscript.present(line)
        HStack(alignment: .top, spacing: 8) {
            Text(p.symbol)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AgentTranscript.tint(for: p.kind))
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .font(.system(size: 12.5, design: .rounded))
                    .fontWeight(p.kind == .task || p.kind == .done ? .semibold : .regular)
                    .foregroundStyle(.primary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(p.detail == nil ? 3 : 2)
                if let detail = p.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(detail.lowercased().hasPrefix("error") ? .red : .secondary)
                        .lineLimit(2)
                }
            }
        }
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
