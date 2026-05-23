import SwiftUI
import SwiftData
import AppKit

struct StatusBarView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @ObservedObject var agent: AgentLoop
    @State private var prompt: String = ""
    @State private var workspacePath: String = ""

    let onQuit: () -> Void

    private var prefs: UserPrefs? { prefsList.first }
    private var keyMissing: Bool { (prefs?.geminiApiKey ?? "").isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if keyMissing {
                missingKeyBanner
            }

            promptField

            transcriptPane

            footer
        }
        .padding(16)
        .frame(width: 380, height: 460, alignment: .topLeading)
        .task { await refresh() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ithuriel").font(.headline)
                Text(workspacePath.isEmpty
                     ? NSLocalizedString("status.workspace.none", comment: "")
                     : (workspacePath as NSString).lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if agent.isRunning {
                ProgressView().controlSize(.small)
                Button(NSLocalizedString("status.stop", comment: ""), role: .destructive) { agent.stop() }
            }
        }
    }

    private var missingKeyBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("status.needKey.title", comment: "")).font(.subheadline.bold())
                Text(NSLocalizedString("status.needKey.body", comment: "")).font(.caption)
                Button(NSLocalizedString("status.needKey.open", comment: "")) {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }.controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("status.prompt.label", comment: "")).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(NSLocalizedString("status.prompt.placeholder", comment: ""), text: $prompt, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(runAgent)
                    .disabled(agent.isRunning || keyMissing)
                Button(action: runAgent) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || agent.isRunning || keyMissing)
            }
        }
    }

    private var transcriptPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if agent.transcript.isEmpty {
                        Text(NSLocalizedString("status.transcript.empty", comment: ""))
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(Array(agent.transcript.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                    if let err = agent.lastError {
                        Text("error: \(err)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(6)
            .onChange(of: agent.transcript.count) { _, count in
                withAnimation { proxy.scrollTo(max(0, count - 1), anchor: .bottom) }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(action: copyContext) {
                Label(NSLocalizedString("status.copy", comment: ""), systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            Spacer()
            Text(NSLocalizedString("status.killSwitch", comment: ""))
                .font(.caption2).foregroundStyle(.tertiary)
            Button(NSLocalizedString("status.settings", comment: "")) {
                NSApp.activate(ignoringOtherApps: true)
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            }.controlSize(.small)
            Button(NSLocalizedString("status.quit", comment: ""), action: onQuit).controlSize(.small)
        }
    }

    private func runAgent() {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !agent.isRunning else { return }
        prompt = ""
        Task { await agent.run(task: task) }
    }

    private func copyContext() {
        Task {
            if let snap = await CachedSnapshot.latest(in: context.container) {
                let tool = AppDetector.currentFrontmostTool()
                let formatted = ContextFormatter.format(snapshot: snap, for: tool == .unknown ? .claudeCodeTerminal : tool)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(formatted, forType: .string)
            }
        }
    }

    private func refresh() async {
        if let snap = await CachedSnapshot.latest(in: context.container) {
            workspacePath = snap.workspacePath
        } else {
            workspacePath = WorkspaceMonitor.mostRecentEditorWorkspace() ?? ""
        }
    }
}
