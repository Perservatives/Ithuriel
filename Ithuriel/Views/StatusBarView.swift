import SwiftUI
import SwiftData
import AppKit

struct StatusBarView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @State private var lastSnapshotAt: Date?
    @State private var workspacePath: String = ""

    let onQuit: () -> Void

    private var prefs: UserPrefs? { prefsList.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ithuriel")
                    .font(.headline)
                Spacer()
                Toggle(NSLocalizedString("status.capturing", comment: ""), isOn: Binding(
                    get: { prefs?.capturingEnabled ?? true },
                    set: { newValue in
                        prefs?.capturingEnabled = newValue
                        try? context.save()
                    }
                ))
                .toggleStyle(.switch)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("status.workspace", comment: ""), systemImage: "folder")
                    .font(.caption).foregroundStyle(.secondary)
                Text(workspacePath.isEmpty ? NSLocalizedString("status.workspace.none", comment: "") : workspacePath)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("status.lastSnapshot", comment: ""), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                Text(lastSnapshotAt.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()) }
                     ?? NSLocalizedString("status.lastSnapshot.none", comment: ""))
            }

            if prefs?.agentControlEnabled == true {
                Label(NSLocalizedString("status.agentControl.armed", comment: ""), systemImage: "wand.and.stars")
                    .font(.caption).foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack {
                Button(action: copyContext) {
                    Label(NSLocalizedString("status.copy", comment: ""), systemImage: "doc.on.doc")
                }
                Spacer()
                Button(NSLocalizedString("status.settings", comment: "")) {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
                Button(NSLocalizedString("status.quit", comment: ""), action: onQuit)
            }
        }
        .padding(16)
        .frame(width: 320, height: 360, alignment: .topLeading)
        .task { await refresh() }
    }

    private func copyContext() {
        Task {
            guard let container = context.container as? ModelContainer else { return }
            _ = container
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
            lastSnapshotAt = snap.capturedAt
            workspacePath = snap.workspacePath
        } else {
            workspacePath = WorkspaceMonitor.mostRecentEditorWorkspace() ?? ""
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
