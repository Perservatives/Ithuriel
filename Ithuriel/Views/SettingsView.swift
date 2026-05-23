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
        case howto, agent, hotkey, voice, appearance, capture, privacy, integrations, permissions
        var id: String { rawValue }

        var title: String {
            switch self {
            case .howto:        return NSLocalizedString("settings.tab.howto", comment: "")
            case .agent:        return NSLocalizedString("settings.tab.agent", comment: "")
            case .hotkey:       return NSLocalizedString("settings.tab.hotkey", comment: "")
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
            case .howto:        return "questionmark.circle"
            case .agent:        return "wand.and.stars"
            case .hotkey:       return "command"
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
                    .padding(UILayout.spacingXL)
                    .frame(maxWidth: 540, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow))
        }
        .frame(minWidth: 760, minHeight: 540)
        .task { await permissions.refresh() }
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
                    .foregroundStyle(section == item ? Color.accentColor : .primary.opacity(0.78))
                Text(item.title)
                    .font(.system(size: 13, weight: section == item ? .medium : .regular))
                    .foregroundStyle(.primary)
                Spacer()
                if item == .permissions, permissions.needsRequired {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(section == item ? Color.accentColor.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch section {
        case .howto:        HowToView()
        case .agent:        agentSection
        case .hotkey:       hotkeySection
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

    private var hotkeySection: some View {
        sectionShell(title: section.title) {
            card(NSLocalizedString("settings.hotkey.title", comment: "")) {
                HotkeyPickerView(
                    keyCode: binding(\.hotkeyKeyCode),
                    modifiers: binding(\.hotkeyModifiers)
                )
                .onChange(of: prefs.hotkeyKeyCode) { _, _ in pushHotkey() }
                .onChange(of: prefs.hotkeyModifiers) { _, _ in pushHotkey() }
                Text(NSLocalizedString("settings.hotkey.help", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            card(NSLocalizedString("settings.hotkey.verbosity", comment: "")) {
                Picker("", selection: binding(\.transcriptVerbosity)) {
                    Text(NSLocalizedString("settings.hotkey.verbosity.summary", comment: "")).tag(0)
                    Text(NSLocalizedString("settings.hotkey.verbosity.normal",  comment: "")).tag(1)
                    Text(NSLocalizedString("settings.hotkey.verbosity.verbose", comment: "")).tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private func pushHotkey() {
        HotkeyMonitor.shared.updateBinding(
            keyCode: prefs.hotkeyKeyCode,
            modifiers: prefs.hotkeyModifiers
        )
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
            card(NSLocalizedString("settings.voice.spoken", comment: "")) {
                Toggle(NSLocalizedString("settings.voice.spokenEnabled", comment: ""),
                       isOn: binding(\.spokenResponsesEnabled))
                labelledField(NSLocalizedString("settings.voice.ttsVoice", comment: "")) {
                    Picker("", selection: binding(\.ttsVoice)) {
                        Text("Neural2 Female (en-US)").tag("en-US-Neural2-F")
                        Text("Neural2 Male (en-US)").tag("en-US-Neural2-D")
                        Text("Studio Female (en-US)").tag("en-US-Studio-O")
                        Text("Wavenet Female (en-GB)").tag("en-GB-Wavenet-A")
                    }
                    .labelsHidden()
                }
                .disabled(!prefs.spokenResponsesEnabled)
                labelledField(NSLocalizedString("settings.voice.ttsRate", comment: "")) {
                    HStack {
                        Slider(value: binding(\.ttsRate), in: 0.5...2.0, step: 0.05)
                        Text(String(format: "%.2fx", prefs.ttsRate))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .disabled(!prefs.spokenResponsesEnabled)
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

    /// Native-feeling Integrations panel. Apple System Settings pattern:
    /// stacked Form groups with header + helper footer, system-style key
    /// rows with a cloud-status pill on the right, account row at the top.
    private var integrationsSection: some View {
        sectionShell(title: section.title) {
            accountRow

            keysGroup

            handoffGroup

            developerDisclosure
        }
    }

    // MARK: - Integrations · pieces

    /// Account row — sits at the top like the "Apple ID" row in System Settings.
    private var accountRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Image(systemName: AuthService.shared.isSignedIn ? "person.fill.checkmark" : "icloud")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(AuthService.shared.isSignedIn ? "Signed in" : "Cloud account")
                    .font(.system(.headline, design: .rounded))
                Text(AuthService.shared.isSignedIn
                     ? "Cloud-synced API keys are pulled automatically. Your local prefs only override empty slots."
                     : "Sign in to pull your API keys from Google Cloud Secret Manager. Optional — local keys still work.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if AuthService.shared.isSignedIn {
                Button("Sign Out") { AuthService.shared.signOut() }
                    .controlSize(.regular)
            } else {
                Button {
                    AuthService.shared.apiBaseURL = prefs.apiBaseURL
                    AuthService.shared.firebaseWebAPIKey = prefs.firebaseWebAPIKey
                    AuthService.shared.beginGoogleSignIn()
                } label: {
                    Label("Sign in with Google", systemImage: "g.circle")
                }
                .controlSize(.regular)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    /// API keys group rendered as a native macOS settings list.
    private var keysGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("API KEYS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.bottom, 6)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                keyRow(
                    icon: "waveform.circle.fill",
                    tint: Color(red: 0.10, green: 0.65, blue: 0.45),
                    title: "OpenAI",
                    subtitle: "Whisper + TTS — drives voice in and out.",
                    binding: binding(\.openAIAPIKey),
                    placeholder: "sk-…",
                    helpURL: "platform.openai.com/api-keys"
                )
                Divider().padding(.leading, 60).opacity(0.4)
                keyRow(
                    icon: "sparkles",
                    tint: Color(red: 0.36, green: 0.50, blue: 0.95),
                    title: "Gemini",
                    subtitle: "Planning loop, tool calls, vector search.",
                    binding: binding(\.geminiApiKey),
                    placeholder: "AIza…",
                    helpURL: "aistudio.google.com/apikey — free"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            Text(AuthService.shared.isSignedIn
                 ? "Keys are stored in Google Cloud Secret Manager and pulled into this Mac on launch. Pasting here overrides for this device."
                 : "Keys live locally on this Mac. Sign in above to sync them across devices via Secret Manager.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 6).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func keyRow(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        binding: Binding<String>,
        placeholder: String,
        helpURL: String
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 20))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if !binding.wrappedValue.isEmpty {
                        statusBadge(text: AuthService.shared.isSignedIn ? "Cloud-synced" : "Set",
                                    color: AuthService.shared.isSignedIn ? .blue : .green)
                    } else {
                        statusBadge(text: "Empty", color: .orange)
                    }
                }
                Text(subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                SecureField(placeholder, text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(.callout, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                Text(helpURL)
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14)
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
            .foregroundStyle(color)
    }

    /// Handoff targets — which external AI tools should Ithuriel format
    /// context for. Rendered as native toggles, not a comma-separated
    /// text field.
    private var handoffGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HAND-OFF TARGETS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.bottom, 6)
                .padding(.horizontal, 4)
                .padding(.top, 18)

            VStack(spacing: 0) {
                ForEach(handoffOptions, id: \.id) { opt in
                    handoffToggle(opt)
                    if opt.id != handoffOptions.last?.id {
                        Divider().padding(.leading, 50).opacity(0.4)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            Text("When you switch to one of these apps, Ithuriel copies a fresh context block to your clipboard for that tool's preferred format.")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.top, 6).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var handoffOptions: [HandoffOption] {[
        .init(id: "claude-code",    label: "Claude Code",    icon: "terminal",       tint: Color(red: 0.50, green: 0.40, blue: 0.95)),
        .init(id: "claude-desktop", label: "Claude Desktop", icon: "macwindow",      tint: Color(red: 0.85, green: 0.60, blue: 0.40)),
        .init(id: "chatgpt",        label: "ChatGPT",        icon: "bubble.left",    tint: Color(red: 0.10, green: 0.65, blue: 0.45)),
        .init(id: "cursor",         label: "Cursor",         icon: "cursorarrow.square", tint: Color(red: 0.32, green: 0.85, blue: 0.70)),
        .init(id: "copilot-chat",   label: "Copilot Chat",   icon: "chevron.left.forwardslash.chevron.right", tint: Color(red: 0.95, green: 0.50, blue: 0.30)),
        .init(id: "gemini",         label: "Gemini",         icon: "sparkles",       tint: Color(red: 0.36, green: 0.50, blue: 0.95))
    ]}

    private func handoffToggle(_ opt: HandoffOption) -> some View {
        let enabled = Binding<Bool>(
            get: { prefs.targetToolsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(opt.id) },
            set: { isOn in
                var ids = prefs.targetToolsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if isOn {
                    if !ids.contains(opt.id) { ids.append(opt.id) }
                } else {
                    ids.removeAll { $0 == opt.id }
                }
                prefs.targetToolsRaw = ids.joined(separator: ",")
                try? context.save()
            }
        )
        return HStack(spacing: 14) {
            Image(systemName: opt.icon)
                .foregroundStyle(opt.tint)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
            Text(opt.label).font(.system(size: 13))
            Spacer()
            Toggle("", isOn: enabled).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// Developer disclosure — only the Cloud Run URL + Firebase web API key
    /// + static bearer. Most users never see this open.
    private var developerDisclosure: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                labelledField("Cloud Run URL") {
                    TextField("https://api.ithuriel.dev", text: binding(\.apiBaseURL))
                        .textFieldStyle(.roundedBorder)
                }
                labelledField("Firebase web API key") {
                    SecureField("AIza…", text: binding(\.firebaseWebAPIKey)).textFieldStyle(.roundedBorder)
                }
                labelledField("Static bearer") {
                    SecureField("", text: binding(\.apiToken)).textFieldStyle(.roundedBorder)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "hammer")
                Text("Developer overrides")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(.top, 18)
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
                let snapshot = prefs
                Task { await PrefsSync.shared.pushLocal(prefs: snapshot) }
            }
        )
    }
}

/// A row in the hand-off targets list.
struct HandoffOption: Identifiable {
    let id: String
    let label: String
    let icon: String
    let tint: Color
}
