import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]

    private var prefs: UserPrefs {
        if let existing = prefsList.first { return existing }
        let new = UserPrefs()
        context.insert(new)
        try? context.save()
        return new
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(NSLocalizedString("settings.tab.general", comment: ""), systemImage: "gear") }
            privacyTab
                .tabItem { Label(NSLocalizedString("settings.tab.privacy", comment: ""), systemImage: "lock.shield") }
            integrationsTab
                .tabItem { Label(NSLocalizedString("settings.tab.integrations", comment: ""), systemImage: "link") }
            advancedTab
                .tabItem { Label(NSLocalizedString("settings.tab.advanced", comment: ""), systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 520, height: 380)
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Toggle(NSLocalizedString("settings.capturing", comment: ""), isOn: binding(\.capturingEnabled))
            Toggle(NSLocalizedString("settings.localOnly", comment: ""), isOn: binding(\.localOnly))
            Text(NSLocalizedString("settings.localOnly.detail", comment: ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

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
            if !AppDetector.isAccessibilityTrusted {
                accessibilityWarning
            }
        }
    }

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

    private var advancedTab: some View {
        Form {
            Toggle(isOn: binding(\.agentControlEnabled)) {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("settings.agentControl", comment: ""))
                    Text(NSLocalizedString("settings.agentControl.help", comment: ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
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
