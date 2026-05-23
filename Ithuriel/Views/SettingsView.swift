import SwiftUI
import SwiftData
import AppKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @ObservedObject private var permissions = PermissionsManager.shared

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
            appearanceTab
                .tabItem { Label(NSLocalizedString("settings.tab.appearance", comment: ""), systemImage: "paintpalette") }
            captureTab
                .tabItem { Label(NSLocalizedString("settings.tab.capture", comment: ""), systemImage: "eye") }
            privacyTab
                .tabItem { Label(NSLocalizedString("settings.tab.privacy", comment: ""), systemImage: "lock.shield") }
            integrationsTab
                .tabItem { Label(NSLocalizedString("settings.tab.integrations", comment: ""), systemImage: "link") }
        }
        .frame(width: 560, height: 480)
        .padding(20)
        .task { await permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissions.refresh() }
        }
    }

    // MARK: - Appearance (launch animation color)

    private var appearanceTab: some View {
        scrollableTab {
            Form {
                Section(NSLocalizedString("settings.appearance.launch", comment: "")) {
                    ColorPicker(NSLocalizedString("settings.appearance.launchColor", comment: ""),
                                selection: launchColorBinding,
                                supportsOpacity: false)
                    Text(NSLocalizedString("settings.appearance.launchHelp", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach(["#7B5BFF", "#FF5E8B", "#3DDC97", "#FFB23F", "#39C5FF"], id: \.self) { hex in
                            presetSwatch(hex: hex)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func presetSwatch(hex: String) -> some View {
        Button {
            prefs.launchColorHex = hex
            try? context.save()
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(prefs.launchColorHex.uppercased() == hex.uppercased()
                                ? Color.primary.opacity(0.7) : Color.primary.opacity(0.12),
                                lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
        .help(hex)
    }

    private var launchColorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: prefs.launchColorHex, fallback: .accentColor) },
            set: { newColor in
                prefs.launchColorHex = newColor.hexString
                try? context.save()
            }
        )
    }

    private func scrollableTab<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    // MARK: - Agent (primary)

    private var agentTab: some View {
        scrollableTab {
            Form {
                PermissionsSettingsSection(permissions: permissions)

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
                    Toggle(NSLocalizedString("settings.agent.restrictWorkspace", comment: ""),
                           isOn: binding(\.restrictToWorkspace))
                    Text(NSLocalizedString("settings.agent.safetyHelp", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(NSLocalizedString("settings.agent.killSwitch", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Capture (context feedstock)

    private var captureTab: some View {
        scrollableTab {
            Form {
                Toggle(NSLocalizedString("settings.capturing", comment: ""), isOn: binding(\.capturingEnabled))
                Toggle(NSLocalizedString("settings.localOnly", comment: ""), isOn: binding(\.localOnly))
                Text(NSLocalizedString("settings.localOnly.detail", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Privacy

    private var privacyTab: some View {
        scrollableTab {
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
    }

    // MARK: - Integrations (context-bridge backend)

    private var integrationsTab: some View {
        scrollableTab {
            Form {
                Section(NSLocalizedString("settings.targets", comment: "")) {
                    TextField(NSLocalizedString("settings.targets.field", comment: ""), text: binding(\.targetToolsRaw))
                        .font(.system(.body, design: .monospaced))
                    Text(NSLocalizedString("settings.targets.help", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section(NSLocalizedString("settings.api", comment: "")) {
                    TextField(NSLocalizedString("settings.api.baseURL", comment: ""), text: binding(\.apiBaseURL))
                    SecureField(NSLocalizedString("settings.api.firebaseWebKey", comment: ""), text: binding(\.firebaseWebAPIKey))
                    SecureField(NSLocalizedString("settings.api.token", comment: ""), text: binding(\.apiToken))
                    HStack {
                        if AuthService.shared.isSignedIn {
                            Label(NSLocalizedString("settings.api.signedIn", comment: ""), systemImage: "checkmark.seal")
                                .foregroundStyle(.green)
                            Spacer()
                            Button(NSLocalizedString("settings.api.signOut", comment: "")) { AuthService.shared.signOut() }
                        } else {
                            Button(NSLocalizedString("settings.api.signIn", comment: "")) {
                                AuthService.shared.apiBaseURL = prefs.apiBaseURL
                                AuthService.shared.firebaseWebAPIKey = prefs.firebaseWebAPIKey
                                AuthService.shared.beginGoogleSignIn()
                            }
                            .disabled(prefs.firebaseWebAPIKey.isEmpty)
                        }
                    }
                    Text(NSLocalizedString("settings.api.help", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
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
