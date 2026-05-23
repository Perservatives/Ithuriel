import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]

    private var prefs: UserPrefs {
        if let existing = prefsList.first { return existing }
        let new = UserPrefs(activeWorkspace: WorkspaceMonitor.mostRecentEditorWorkspace() ?? "")
        context.insert(new)
        try? context.save()
        return new
    }

    var body: some View {
        TabView {
            agentTab
                .tabItem { Label(NSLocalizedString("settings.tab.agent", comment: ""), systemImage: "wand.and.stars") }
            captureTab
                .tabItem { Label(NSLocalizedString("settings.tab.capture", comment: ""), systemImage: "eye") }
            privacyTab
                .tabItem { Label(NSLocalizedString("settings.tab.privacy", comment: ""), systemImage: "lock.shield") }
            integrationsTab
                .tabItem { Label(NSLocalizedString("settings.tab.integrations", comment: ""), systemImage: "link") }
        }
        .frame(width: 560, height: 440)
        .padding(20)
    }

    // MARK: - Agent (primary)

    private var agentTab: some View {
        Form {
            Toggle(NSLocalizedString("settings.agent.enabled", comment: ""), isOn: binding(\.agentEnabled))

            Section(NSLocalizedString("settings.agent.brain", comment: "")) {
                SecureField(NSLocalizedString("settings.agent.geminiKey", comment: ""),
                            text: binding(\.geminiApiKey))
                TextField(NSLocalizedString("settings.agent.geminiModel", comment: ""),
                          text: binding(\.geminiModel))
                Text(NSLocalizedString("settings.agent.geminiHelp", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(NSLocalizedString("settings.agent.workspace", comment: "")) {
                TextField(NSLocalizedString("settings.agent.workspacePath", comment: ""),
                          text: binding(\.activeWorkspace))
                Text(NSLocalizedString("settings.agent.workspaceHelp", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(NSLocalizedString("settings.agent.safety", comment: "")) {
                Toggle(NSLocalizedString("settings.agent.confirmEvery", comment: ""),
                       isOn: binding(\.confirmEveryAction))
                Text(NSLocalizedString("settings.agent.killSwitch", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !AppDetector.isAccessibilityTrusted {
                accessibilityWarning
            }
        }
    }

    // MARK: - Capture (context feedstock)

    private var captureTab: some View {
        Form {
            Toggle(NSLocalizedString("settings.capturing", comment: ""), isOn: binding(\.capturingEnabled))
            Toggle(NSLocalizedString("settings.localOnly", comment: ""), isOn: binding(\.localOnly))
            Text(NSLocalizedString("settings.localOnly.detail", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Privacy

    private var privacyTab: some View {
        Form {
            Toggle(NSLocalizedString("settings.redactKeys", comment: ""), isOn: binding(\.redactKeys))
            VStack(alignment: .leading) {
                Text(NSLocalizedString("settings.excludePaths", comment: ""))
                TextEditor(text: binding(\.excludePathsRaw))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                    .border(.secondary.opacity(0.3))
                Text(NSLocalizedString("settings.excludePaths.help", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Integrations (context-bridge backend)

    private var integrationsTab: some View {
        Form {
            Section(NSLocalizedString("settings.targets", comment: "")) {
                TextField(NSLocalizedString("settings.targets.field", comment: ""), text: binding(\.targetToolsRaw))
                    .font(.system(.body, design: .monospaced))
                Text(NSLocalizedString("settings.targets.help", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(NSLocalizedString("settings.api", comment: "")) {
                TextField(NSLocalizedString("settings.api.baseURL", comment: ""), text: binding(\.apiBaseURL))
                SecureField(NSLocalizedString("settings.api.token", comment: ""), text: binding(\.apiToken))
            }
        }
    }

    private var accessibilityWarning: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading) {
                Text(NSLocalizedString("settings.accessibility.title", comment: "")).font(.subheadline.bold())
                Text(NSLocalizedString("settings.accessibility.body", comment: "")).font(.caption)
                Button(NSLocalizedString("settings.accessibility.open", comment: "")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<UserPrefs, T>) -> Binding<T> {
        Binding(
            get: { prefs[keyPath: keyPath] },
            set: { newValue in
                prefs[keyPath: keyPath] = newValue
                try? context.save()
            }
        )
    }
}
