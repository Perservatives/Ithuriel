import SwiftUI
import SwiftData
import AppKit

/// Settings UI for Ithuriel. Two-pane sidebar layout (Apple System Settings
/// style), liquid glass chrome, generous typography. Sections live as
/// dedicated views; the sidebar drives selection.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var section: Section = .agent

    enum Section: String, CaseIterable, Identifiable {
        case agent, voice, appearance, capture, privacy, integrations, permissions
        var id: String { rawValue }

        var title: String {
            switch self {
            case .agent:        return NSLocalizedString("settings.tab.agent", comment: "")
            case .voice:        return NSLocalizedString("settings.tab.voice", comment: "")
            case .appearance:   return NSLocalizedString("settings.tab.appearance", comment: "")
            case .capture:      return NSLocalizedString("settings.tab.capture", comment: "")
            case .privacy:      return NSLocalizedString("settings.tab.privacy", comment: "")
            case .integrations: return NSLocalizedString("settings.tab.integrations", comment: "")
            case .permissions:  return NSLocalizedString("settings.tab.permissions", comment: "")
            }
        }

        var symbol: String {
            switch self {
            case .agent:        return "wand.and.stars"
            case .voice:        return "waveform"
            case .appearance:   return "paintpalette"
            case .capture:      return "eye"
            case .privacy:      return "lock.shield"
            case .integrations: return "link"
            case .permissions:  return "checkmark.shield"
            }
        }
    }

    private var prefs: UserPrefs {
        if let existing = prefsList.first { return existing }
        let new = UserPrefs(activeWorkspace: WorkspaceMonitor.mostRecentEditorWorkspace() ?? "")
        context.insert(new)
        try? context.save()
        return new
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))

            Divider().opacity(0.5)

            ScrollView {
                content
                    .padding(28)
                    .frame(maxWidth: 520, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 760, minHeight: 540)
        .task { await permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await permissions.refresh() }
        }
        .onChange(of: permissions.needsRequired) { _, stillNeeded in
            if !stillNeeded, section == .permissions { section = .agent }
        }
    }

    private var visibleSections: [Section] {
        Section.allCases.filter { item in
            if item == .permissions { return permissions.needsRequired }
            return true
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ForEach(visibleSections) { item in
                sidebarRow(item)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarRow(_ item: Section) -> some View {
        Button {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)) { section = item }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(section == item ? .white : .primary.opacity(0.78))
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(section == item ? .white : .primary)
                Spacer()
                if item == .permissions, permissions.needsRequired {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(section == item ? Color.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch section {
        case .agent:        agentSection
        case .voice:        voiceSection
        case .appearance:   appearanceSection
        case .capture:      captureSection
        case .privacy:      privacySection
        case .integrations: integrationsSection
        case .permissions:  permissionsSection
        }
    }

    // MARK: - Sections

    private var agentSection: some View {
        sectionShell(title: section.title) {
            Toggle(NSLocalizedString("settings.agent.enabled", comment: ""), isOn: binding(\.agentEnabled))

            card(NSLocalizedString("settings.agent.brain", comment: "")) {
                labelledField(NSLocalizedString("settings.agent.geminiKey", comment: "")) {
                    SecureField("AIza…", text: binding(\.geminiApiKey)).textFieldStyle(.roundedBorder)
                }
                labelledField(NSLocalizedString("settings.agent.geminiModel", comment: "")) {
                    TextField("gemini-3.5-flash", text: binding(\.geminiModel)).textFieldStyle(.roundedBorder)
                }
                Text(NSLocalizedString("settings.agent.geminiHelp", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            card(NSLocalizedString("settings.agent.workspace", comment: "")) {
                labelledField(NSLocalizedString("settings.agent.workspacePath", comment: "")) {
                    HStack(spacing: 8) {
                        TextField("~/Developer/MyProject", text: binding(\.activeWorkspace))
                            .textFieldStyle(.roundedBorder)
                        Button(NSLocalizedString("settings.agent.workspacePick", comment: "")) { pickWorkspace() }
                    }
                }
                Text(NSLocalizedString("settings.agent.workspaceHelp", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            card(NSLocalizedString("settings.agent.safety", comment: "")) {
                Toggle(NSLocalizedString("settings.agent.confirmEvery", comment: ""), isOn: binding(\.confirmEveryAction))
                Toggle(NSLocalizedString("settings.agent.restrictWorkspace", comment: ""), isOn: binding(\.restrictToWorkspace))
                Text(NSLocalizedString("settings.agent.safetyHelp", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(NSLocalizedString("settings.agent.killSwitch", comment: ""))
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var voiceSection: some View {
        sectionShell(title: section.title) {
            card(NSLocalizedString("settings.voice.cloud", comment: "")) {
                labelledField(NSLocalizedString("settings.voice.key", comment: "")) {
                    SecureField("AIza…", text: binding(\.googleCloudAPIKey)).textFieldStyle(.roundedBorder)
                }
                Text(NSLocalizedString("settings.voice.help", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                Text(NSLocalizedString("settings.voice.shortcut", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appearanceSection: some View {
        sectionShell(title: section.title) {
            card(NSLocalizedString("settings.appearance.launch", comment: "")) {
                ColorPicker(NSLocalizedString("settings.appearance.launchColor", comment: ""),
                            selection: launchColorBinding,
                            supportsOpacity: false)
                Text(NSLocalizedString("settings.appearance.launchHelp", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(["#7B5BFF", "#FF5E8B", "#3DDC97", "#FFB23F", "#39C5FF"], id: \.self) { hex in
                        presetSwatch(hex: hex)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var captureSection: some View {
        sectionShell(title: section.title) {
            card("") {
                Toggle(NSLocalizedString("settings.capturing", comment: ""), isOn: binding(\.capturingEnabled))
                Toggle(NSLocalizedString("settings.localOnly", comment: ""), isOn: binding(\.localOnly))
                Text(NSLocalizedString("settings.localOnly.detail", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        sectionShell(title: section.title) {
            card("") {
                Toggle(NSLocalizedString("settings.redactKeys", comment: ""), isOn: binding(\.redactKeys))
                Text(NSLocalizedString("settings.excludePaths", comment: ""))
                TextEditor(text: binding(\.excludePathsRaw))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                    )
                Text(NSLocalizedString("settings.excludePaths.help", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var integrationsSection: some View {
        sectionShell(title: section.title) {
            card(NSLocalizedString("settings.targets", comment: "")) {
                labelledField(NSLocalizedString("settings.targets.field", comment: "")) {
                    TextField("claude-code,cursor,chatgpt", text: binding(\.targetToolsRaw))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                Text(NSLocalizedString("settings.targets.help", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            card(NSLocalizedString("settings.api", comment: "")) {
                labelledField(NSLocalizedString("settings.api.baseURL", comment: "")) {
                    TextField("https://api.ithuriel.dev", text: binding(\.apiBaseURL))
                        .textFieldStyle(.roundedBorder)
                }
                labelledField(NSLocalizedString("settings.api.firebaseWebKey", comment: "")) {
                    SecureField("AIza…", text: binding(\.firebaseWebAPIKey)).textFieldStyle(.roundedBorder)
                }
                labelledField(NSLocalizedString("settings.api.token", comment: "")) {
                    SecureField("", text: binding(\.apiToken)).textFieldStyle(.roundedBorder)
                }
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

    private var permissionsSection: some View {
        sectionShell(title: section.title) {
            PermissionsSettingsSection(permissions: permissions)
        }
    }

    // MARK: - Building blocks

    private func sectionShell<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.system(.title2, design: .rounded).weight(.semibold))
            VStack(alignment: .leading, spacing: 16) { content() }
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )
        }
    }

    private func labelledField<C: View>(_ label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Appearance helpers

    private func presetSwatch(hex: String) -> some View {
        Button {
            prefs.launchColorHex = hex
            try? context.save()
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(prefs.launchColorHex.uppercased() == hex.uppercased()
                                ? Color.primary.opacity(0.85) : Color.primary.opacity(0.12),
                                lineWidth: 2)
                )
                .shadow(color: Color(hex: hex).opacity(0.45), radius: 6)
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

    private func pickWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            prefs.activeWorkspace = url.path
            try? context.save()
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
