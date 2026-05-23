import SwiftUI
import SwiftData
import AppKit

struct StatusBarView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @ObservedObject var agent: AgentLoop
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var prompt: String = ""
    @State private var workspacePath: String = ""
    @State private var promptFieldFocused: Bool = false
    @State private var copyStatus: String?
    @FocusState private var fieldFocus: Bool

    let onOpenSettings: () -> Void
    let onOpenChat: () -> Void
    let onQuit: () -> Void

    private var prefs: UserPrefs? { prefsList.first }
    private var keyMissing: Bool { (prefs?.geminiApiKey ?? "").isEmpty }
    private var permissionsMissing: Bool { permissions.hasRefreshed && permissions.needsRequired }

    var body: some View {
        VStack(alignment: .leading, spacing: UILayout.spacingM) {
            header

            if permissionsMissing {
                missingPermissionsBanner.transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            if keyMissing {
                missingKeyBanner.transition(.asymmetric(
                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            promptField

            transcriptPane

            footer

            if let copyStatus {
                Text(copyStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(UILayout.spacingL)
        .frame(minWidth: 360, idealWidth: UILayout.popoverWidth, minHeight: UILayout.popoverMinHeight, alignment: .topLeading)
        .background(
            VisualEffectBlur(material: .menu, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .animation(Motion.easeOut, value: keyMissing)
        .animation(Motion.easeOut, value: permissionsMissing)
        .animation(Motion.easeOut, value: agent.isRunning)
        .task {
            await refresh()
            await permissions.refresh()
            fieldFocus = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissions.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ithurielPermissionsDidChange)) { _ in
            Task { await permissions.refresh() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    statusDot
                    Text("Ithuriel").font(.system(.headline, design: .rounded))
                }
                Text(workspacePath.isEmpty
                     ? NSLocalizedString("status.workspace.none", comment: "")
                     : (workspacePath as NSString).lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.pressable(sound: .tool))
            .controlSize(.small)
            .help(NSLocalizedString("status.settings", comment: ""))

            if agent.isRunning {
                ProgressView().controlSize(.small)
                Button(role: .destructive) {
                    agent.stop()
                } label: {
                    Label(NSLocalizedString("status.stop", comment: ""), systemImage: "stop.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.pressable(sound: .tool))
                .controlSize(.small)
                .tint(.red)
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(agent.isRunning ? Color.green : (permissionsMissing || keyMissing ? Color.orange : Color.secondary))
            .frame(width: 6, height: 6)
            .scaleEffect(agent.isRunning ? 1.15 : 1)
            .animation(agent.isRunning
                       ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                       : Motion.easeOut, value: agent.isRunning)
    }

    // MARK: - Banners

    private var missingKeyBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("status.needKey.title", comment: "")).font(.subheadline.bold())
                Text(NSLocalizedString("status.needKey.body", comment: "")).font(.caption)
                    .foregroundStyle(.secondary)
                Button(NSLocalizedString("status.needKey.open", comment: ""), action: onOpenSettings)
                    .buttonStyle(.pressable(sound: .tool))
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var missingPermissionsBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("status.needPermissions.title", comment: "")).font(.subheadline.bold())
                Text(missingPermissionsDetail).font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(NSLocalizedString("status.needPermissions.open", comment: ""), action: onOpenSettings)
                    .buttonStyle(.pressable(sound: .tool))
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var missingPermissionsDetail: String {
        var missing: [String] = []
        if !permissions.accessibilityGranted {
            missing.append(NSLocalizedString("settings.permissions.accessibility.title", comment: ""))
        }
        if !permissions.screenRecordingGranted {
            missing.append(NSLocalizedString("settings.permissions.screen.title", comment: ""))
        }
        guard !missing.isEmpty else {
            return NSLocalizedString("status.needPermissions.body", comment: "")
        }
        return String(format: NSLocalizedString("status.needPermissions.missing", comment: ""), missing.joined(separator: ", "))
    }

    // MARK: - Prompt

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("status.prompt.label", comment: ""))
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField(NSLocalizedString("status.prompt.placeholder", comment: ""), text: $prompt, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(fieldFocus ? 0.08 : 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(fieldFocus ? 0.55 : 0), lineWidth: 1)
                    )
                    .focused($fieldFocus)
                    .onSubmit(runAgent)
                    .disabled(agent.isRunning || keyMissing)
                    .animation(Motion.easeOut, value: fieldFocus)

                Button(action: runAgent) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(canSubmit ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .buttonStyle(.pressable(scale: 0.93, sound: .submit))
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!canSubmit)
            }
        }
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !agent.isRunning && !keyMissing
    }

    // MARK: - Transcript

    private var transcriptPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if agent.transcript.isEmpty {
                        Text(NSLocalizedString("status.transcript.empty", comment: ""))
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                    ForEach(Array(agent.transcript.enumerated()), id: \.offset) { idx, line in
                        TranscriptLineView(line: line)
                            .id(idx)
                            .staggered(idx)
                    }
                    if let err = agent.lastError {
                        Text("error: \(err)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                            .padding(.top, 4)
                    }
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 260)
            .layoutPriority(1)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .onChange(of: agent.transcript.count) { _, count in
                withAnimation(Motion.easeOut) { proxy.scrollTo(max(0, count - 1), anchor: .bottom) }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: openChat) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
            }
            .buttonStyle(.pressable(sound: .tool))
            .help("Open Chat Window")

            Button(action: copyContext) {
                Label(NSLocalizedString("status.copy", comment: ""), systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.pressable(sound: .tool))
            .help(NSLocalizedString("status.copy", comment: ""))

            Button(action: toggleMute) {
                Image(systemName: SoundPlayer.shared.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.pressable())
            .help(SoundPlayer.shared.muted ? "Unmute sounds" : "Mute sounds")

            Spacer()

            Text(NSLocalizedString("status.killSwitch", comment: ""))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button(NSLocalizedString("status.settings", comment: ""), action: onOpenSettings)
                .buttonStyle(.pressable(sound: .tool))
                .controlSize(.small)

            Button(NSLocalizedString("status.quit", comment: ""), action: onQuit)
                .buttonStyle(.pressable())
                .controlSize(.small)
        }
        .font(.caption)
    }

    // MARK: - Actions

    private func openChat() {
        onOpenChat()
    }

    private func runAgent() {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !agent.isRunning else { return }
        prompt = ""
        Task { await agent.run(task: task) }
    }

    private func copyContext() {
        Task {
            let userPrefs = prefs ?? UserPrefs.defaults()
            let snap: ContextSnapshot?
            if let cached = await CachedSnapshot.latest(in: context.container) {
                snap = cached
            } else {
                snap = await ContextSnapshot.captureFresh(prefs: userPrefs)
                if let snap {
                    await CachedSnapshot.persist(snap, in: context.container)
                }
            }

            guard let snap else {
                copyStatus = NSLocalizedString("status.copy.empty", comment: "")
                return
            }

            let tool = AppDetector.currentFrontmostTool()
            let target = tool == .unknown ? AITool.claudeCodeTerminal : tool
            let formatted = ContextFormatter.format(snapshot: snap, for: target)
            InjectionEngine.shared.primaryInject(text: formatted, target: target)
            SoundPlayer.shared.play(.done, volume: 0.45)
            copyStatus = NSLocalizedString("status.copy.done", comment: "")
            workspacePath = snap.workspacePath
        }
    }

    private func toggleMute() {
        SoundPlayer.shared.muted.toggle()
    }

    private func refresh() async {
        if let snap = await CachedSnapshot.latest(in: context.container) {
            workspacePath = snap.workspacePath
        } else {
            workspacePath = WorkspaceMonitor.mostRecentEditorWorkspace() ?? ""
        }
    }
}

// MARK: - Transcript line styling

private struct TranscriptLineView: View {
    let line: String

    var body: some View {
        let p = AgentTranscript.present(line)
        HStack(alignment: .top, spacing: 6) {
            Text(p.symbol)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(AgentTranscript.tint(for: p.kind))
                .frame(width: 12, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title)
                    .font(.system(.caption, design: p.kind == .action ? .rounded : .default))
                    .fontWeight(p.kind == .task || p.kind == .done ? .medium : .regular)
                    .foregroundStyle(.primary.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(p.detail == nil ? 3 : 2)
                if let detail = p.detail {
                    Text(detail)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(detail.lowercased().hasPrefix("error") ? .red : .secondary)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Vibrancy background

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
