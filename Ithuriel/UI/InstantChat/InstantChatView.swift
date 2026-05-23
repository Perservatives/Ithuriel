import SwiftUI
import AppKit

/// Compact ⌥Space popup. A single text field with attach/voice/send controls,
/// matching the OpenAI ChatGPT desktop spotlight. When the agent replies, the
/// popup grows downward to render the streamed answer inline. A small "Open
/// in full chat" link in the bottom-right escalates to the main window.
struct InstantChatView: View {
    @ObservedObject var agent: AgentLoop
    @ObservedObject private var bus = AgentStatusBus.shared
    @ObservedObject private var voice = VoiceController.shared

    let onDismiss: () -> Void
    let onEscalate: () -> Void
    /// Fired when the rendered content height changes — the panel owner
    /// animates the window to match. Heights are reported including the
    /// 12pt outer padding the view paints.
    let onHeightChange: (CGFloat) -> Void

    @State private var prompt: String = ""
    @State private var attachmentName: String? = nil
    @FocusState private var inputFocused: Bool

    private let cornerRadius: CGFloat = 18
    private let outerPadding: CGFloat = 12
    private let inputHeight: CGFloat = 72  // visual input row height
    private let responseMaxHeight: CGFloat = 420
    private var placeholder: String { NSLocalizedString("instantchat.placeholder", comment: "") }
    private var escalateLabel: String { NSLocalizedString("instantchat.escalate", comment: "") }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            if hasResponse {
                Divider()
                    .opacity(0.25)
                responsePane
            }
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.02))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 28, x: 0, y: 14)
        .padding(outerPadding)
        .background(InstantChatKeyCatcher(onEscape: onDismiss))
        .onAppear {
            // Defer focus until the next runloop tick so the panel finishes
            // becoming key first.
            DispatchQueue.main.async { inputFocused = true }
            reportHeight()
        }
        .onChange(of: hasResponse) { _, _ in reportHeight() }
        .onChange(of: bus.lastSpoken) { _, _ in reportHeight() }
        .onChange(of: agent.transcript.count) { _, _ in reportHeight() }
    }

    // MARK: - Input row

    private var inputRow: some View {
        HStack(spacing: 10) {
            attachButton

            ZStack(alignment: .leading) {
                if prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 18, weight: .regular, design: .default))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
                TextField("", text: $prompt, axis: .horizontal)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
                    .focused($inputFocused)
                    .onSubmit(submit)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let attachmentName {
                attachmentChip(name: attachmentName)
            }

            micButton
            sendButton
        }
        .padding(.horizontal, 18)
        .frame(height: inputHeight)
    }

    private var attachButton: some View {
        Button(action: pickAttachment) {
            Image(systemName: "paperclip")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.pressable(scale: 0.94))
        .help("Attach a file")
    }

    private var micButton: some View {
        Button(action: toggleVoice) {
            Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(voice.isListening ? Color.red.opacity(0.85) : .secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.primary.opacity(voice.isListening ? 0.12 : 0.06)))
        }
        .buttonStyle(.pressable(scale: 0.94))
        .help(voice.isListening ? "Stop and submit" : "Voice input")
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                Circle()
                    .fill(sendButtonFill)
                    .frame(width: 32, height: 32)
                Image(systemName: agent.isRunning ? "square.fill" : "arrow.up")
                    .font(.system(size: agent.isRunning ? 11 : 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.pressable(scale: 0.92, sound: .submit))
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!canSubmit && !agent.isRunning)
        .help(agent.isRunning ? "Stop" : "Send")
    }

    private var sendButtonFill: AnyShapeStyle {
        if agent.isRunning {
            return AnyShapeStyle(Color.primary.opacity(0.80))
        }
        if canSubmit {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1, green: 0.45, blue: 0.32),
                         Color(red: 0.94, green: 0.30, blue: 0.22)],
                startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Color.secondary.opacity(0.28))
    }

    private func attachmentChip(name: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc")
                .font(.system(size: 10))
            Text(name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            Button {
                attachmentName = nil
                stripAttachmentMarker()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    // MARK: - Response pane

    @ViewBuilder
    private var responsePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(displayedResponse)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("response")
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: responseMaxHeight)
                .onChange(of: displayedResponse) { _, _ in
                    withAnimation(Motion.easeOut) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            HStack {
                if agent.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action: onEscalate) {
                    HStack(spacing: 4) {
                        Text(escalateLabel)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Continue in the full chat window")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Derived state

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !agent.isRunning
    }

    /// Show the response area when the agent is mid-run, has produced any
    /// transcript output, or has narrated a reply via the status bus.
    private var hasResponse: Bool {
        agent.isRunning
            || !agent.transcript.isEmpty
            || (bus.lastSpoken?.isEmpty == false)
    }

    /// Prefer the agent's most recent human-readable narration; fall back to
    /// the last assistant-style transcript line so something is always shown
    /// while a task runs.
    private var displayedResponse: String {
        if let spoken = bus.lastSpoken, !spoken.isEmpty { return spoken }
        for line in agent.transcript.reversed() {
            let role = ChatBubble.agentForLine(line)
            if role == .assistant || role == .user {
                return ChatBubble.cleanLine(line)
            }
        }
        return ""
    }

    // MARK: - Height reporting

    /// Total panel height for the current state, in points. Mirrors the
    /// layout above so the owning window resizes in lockstep.
    private func reportHeight() {
        let response: CGFloat
        if hasResponse {
            // input + divider + response (clamped) + footer row.
            // Allow the scroll content up to responseMaxHeight; in practice
            // the response shrinks naturally when empty.
            let approxBody = min(responseMaxHeight, 240)
            response = 1 + approxBody + 40
        } else {
            response = 0
        }
        let total = inputHeight + response + (outerPadding * 2)
        onHeightChange(total)
    }

    // MARK: - Actions

    private func submit() {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !agent.isRunning else { return }
        prompt = ""
        attachmentName = nil
        Task { await agent.run(task: task) }
    }

    private func toggleVoice() {
        Task { @MainActor in
            if voice.isListening {
                if let text = await voice.stopAndTranscribe(showErrors: true), !text.isEmpty {
                    prompt = text
                    submit()
                }
            } else {
                _ = await voice.start()
            }
        }
    }

    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            let name = url.lastPathComponent
            attachmentName = name
            let marker = "[Attached: \(name)] "
            // Prepend if not already there.
            if !prompt.hasPrefix(marker) { prompt = marker + prompt }
            inputFocused = true
        }
    }

    private func stripAttachmentMarker() {
        // Drop any leading `[Attached: …] ` segment.
        if let range = prompt.range(of: #"^\[Attached: [^\]]+\] "#, options: .regularExpression) {
            prompt.removeSubrange(range)
        }
    }
}

// MARK: - Key catcher

/// Tiny NSViewRepresentable that swallows the Escape key while the popup is
/// key window and forwards it to `onEscape`. Avoids requiring macOS 14's
/// `.onKeyPress(.escape)`.
private struct InstantChatKeyCatcher: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let v = KeyView()
        v.onEscape = onEscape
        return v
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onEscape = onEscape
    }

    final class KeyView: NSView {
        var onEscape: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Register a local monitor scoped to this view's window. Carbon
            // would also work but a local monitor is simpler and tears down
            // when the panel goes away.
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, event.window === win else { return event }
                // 53 is the Escape keycode.
                if event.keyCode == 53 {
                    self.onEscape?()
                    return nil
                }
                return event
            }
        }
    }
}
