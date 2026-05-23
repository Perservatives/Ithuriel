import SwiftUI
import SwiftData
import AppKit

/// ChatGPT-desktop-style layout. NavigationSplitView with a collapsible sidebar
/// on the left and the conversation pane on the right. The right pane shows the
/// empty hero when there's no active conversation and a stack of message rows
/// otherwise. Composer is pinned to the bottom of the right pane.
struct ChatView: View {
    @ObservedObject var agent: AgentLoop
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedAgentRun.startedAt, order: .reverse) private var runs: [SavedAgentRun]
    @Query private var prefsList: [UserPrefs]

    @State private var selectedRunID: UUID?
    @State private var prompt: String = ""
    @State private var searchQuery: String = ""
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @FocusState private var inputFocused: Bool
    @ObservedObject private var permissions = PermissionsManager.shared

    private var prefs: UserPrefs? { prefsList.first }
    private var keyMissing: Bool { (prefs?.geminiApiKey ?? "").isEmpty }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            ChatSidebar(
                runs: runs,
                searchQuery: $searchQuery,
                selectedRunID: $selectedRunID,
                onNew: newConversation,
                onDelete: deleteRun
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            chatPane
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 720, minHeight: 480)
        .background(SplashWindowBackground())
        .background(
            Group {
                Button("New", action: newConversation)
                    .keyboardShortcut("n", modifiers: .command)
                    .hidden().frame(width: 0, height: 0)
                Button("Temp", action: temporaryConversation)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .hidden().frame(width: 0, height: 0)
                Button("Stop", action: stopAgentIfRunning)
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden().frame(width: 0, height: 0)
            }
        )
        .task { await PermissionsManager.shared.refresh() }
    }

    // MARK: - Right pane

    private var chatPane: some View {
        VStack(spacing: 0) {
            ChatTopBar(workspaceLabel: workspaceLabel)

            if permissions.hasRefreshed && permissions.needsRequired && !agent.isRunning {
                PermissionsBanner()
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if let selected = selectedRun {
                            renderMessages(transcript: selected.transcript, header: selected.task)
                        } else if agent.isRunning || !agent.transcript.isEmpty {
                            renderMessages(transcript: agent.transcript, header: nil)
                        } else {
                            ChatEmptyState(
                                prompt: $prompt,
                                onFocusComposer: { inputFocused = true }
                            )
                                .padding(.top, 80)
                        }
                        Color.clear.frame(height: 40).id("bottom")
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                }
                .onChange(of: agent.transcript.count) { _, _ in
                    withAnimation(Motion.easeOut) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }

            ChatComposer(
                prompt: $prompt,
                inputFocused: $inputFocused,
                placeholder: keyMissing ? "Add your Gemini API key in Settings…" : "Ask anything",
                canSubmit: canSubmit,
                isRunning: agent.isRunning,
                onSubmit: runAgent,
                onStop: stopAgentIfRunning,
                onMic: toggleVoice
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SplashWindowBackground())
    }

    private var workspaceLabel: String? {
        if let selected = selectedRun, !selected.workspacePath.isEmpty {
            return URL(fileURLWithPath: selected.workspacePath).lastPathComponent
        }
        if let recent = WorkspaceMonitor.mostRecentEditorWorkspace() {
            return URL(fileURLWithPath: recent).lastPathComponent
        }
        return nil
    }

    @ViewBuilder
    private func renderMessages(transcript: [String], header: String?) -> some View {
        if let header {
            ChatBubbleView(role: .user, text: stripTaskPrefix(header), index: 0)
        }
        if prefs?.transcriptVerbosity ?? 1 == 0 {
            ForEach(Array(transcript.enumerated()), id: \.offset) { idx, line in
                let role = ChatBubble.agentForLine(line)
                if role == .assistant || role == .user || role == .error {
                    messageRow(for: line, index: idx, transcript: transcript)
                }
            }
            ThinkingSpinner(agent: agent).padding(.leading, 4)
        } else {
            ForEach(Array(transcript.enumerated()), id: \.offset) { idx, line in
                messageRow(for: line, index: idx, transcript: transcript)
            }
            ThinkingSpinner(agent: agent).padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func messageRow(for line: String, index: Int, transcript: [String]) -> some View {
        let role = ChatBubble.agentForLine(line)
        let clean = ChatBubble.cleanLine(line)
        switch role {
        case .user:
            ChatBubbleView(role: .user, text: stripTaskPrefix(clean), index: index)
        case .assistant:
            ChatBubbleView(
                role: .assistant,
                text: clean,
                index: index,
                showHeader: showAssistantHeader(in: transcript, at: index)
            )
        case .tool:
            ToolUseCard(call: clean, result: nil, index: index)
        case .toolResult:
            ToolUseCard(call: "", result: clean, index: index)
        case .error:
            ErrorRow(text: clean, index: index)
        case .system:
            SystemRow(text: clean, index: index)
        }
    }

    // Defensive: strip an inherited "Task: " prefix in case any code path still
    // emits one. The Localizable.strings template is already "%@".
    private func stripTaskPrefix(_ s: String) -> String {
        if s.hasPrefix("Task: ") { return String(s.dropFirst("Task: ".count)) }
        return s
    }

    /// Show the Ithuriel mark only at the start of a consecutive assistant run.
    private func showAssistantHeader(in transcript: [String], at index: Int) -> Bool {
        guard ChatBubble.agentForLine(transcript[index]) == .assistant else { return false }
        if index == 0 { return true }
        return ChatBubble.agentForLine(transcript[index - 1]) != .assistant
    }

    // MARK: - Actions

    private var selectedRun: SavedAgentRun? {
        guard let id = selectedRunID else { return nil }
        return runs.first { $0.id == id }
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !agent.isRunning && !keyMissing
    }

    private func newConversation() {
        selectedRunID = nil
        prompt = ""
        inputFocused = true
    }

    private func temporaryConversation() {
        UserDefaults.standard.set(true, forKey: "Ithuriel.NextRunTemporary")
        selectedRunID = nil
        prompt = ""
        inputFocused = true
    }

    private func stopAgentIfRunning() {
        if agent.isRunning { agent.stop() }
    }

    private func runAgent() {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !agent.isRunning else { return }
        prompt = ""
        selectedRunID = nil
        Task { await agent.run(task: task) }
    }

    private func toggleVoice() {
        // Tap to start, tap again to stop+submit. Mirrors the hold-to-talk
        // hotkey but as a click affordance in the composer.
        Task { @MainActor in
            VoiceController.shared.start()
        }
    }

    private func deleteRun(_ run: SavedAgentRun) {
        if selectedRunID == run.id { selectedRunID = nil }
        modelContext.delete(run)
    }
}

// MARK: - Sidebar

private struct ChatSidebar: View {
    let runs: [SavedAgentRun]
    @Binding var searchQuery: String
    @Binding var selectedRunID: UUID?
    let onNew: () -> Void
    let onDelete: (SavedAgentRun) -> Void

    private var filteredRuns: [SavedAgentRun] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return runs }
        let q = searchQuery.lowercased()
        return runs.filter { $0.task.lowercased().contains(q) }
    }

    private var projectFolders: [String] {
        // Distinct workspace paths from recent runs (most recent first).
        var seen = Set<String>()
        var out: [String] = []
        for run in runs where !run.workspacePath.isEmpty {
            if !seen.contains(run.workspacePath) {
                seen.insert(run.workspacePath)
                out.append(run.workspacePath)
                if out.count == 5 { break }
            }
        }
        if out.isEmpty, let recent = WorkspaceMonitor.mostRecentEditorWorkspace() {
            out = [recent]
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            topItems
                .padding(.horizontal, 8)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if !projectFolders.isEmpty {
                        sectionHeader("Projects")
                        VStack(spacing: 2) {
                            ForEach(projectFolders, id: \.self) { path in
                                ProjectRow(path: path)
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    let groups = groupRuns(filteredRuns)
                    if groups.isEmpty {
                        sectionHeader("Recents")
                        emptyHint
                    }
                    ForEach(groups, id: \.0) { groupTitle, items in
                        VStack(alignment: .leading, spacing: 2) {
                            sectionHeader(groupTitle)
                            ForEach(items) { run in
                                SidebarRow(
                                    run: run,
                                    selected: run.id == selectedRunID,
                                    onSelect: { selectedRunID = run.id },
                                    onDelete: { onDelete(run) }
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 10)
            }

            Divider().opacity(0.3)
            UserFooterRow()
        }
        .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))
    }

    private var header: some View {
        HStack(spacing: 8) {
            AsteriskMark(size: 14, tint: .accentColor)
            Text("Ithuriel")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            Button(action: onNew) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.pressable(sound: .summon))
            .help("New conversation (⌘N)")
        }
        .padding(.horizontal, 14)
        .padding(.top, 38)   // clear macOS traffic lights
        .padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private var topItems: some View {
        VStack(spacing: 2) {
            TopItemRow(icon: .asterisk,      label: "Ithuriel", isAccent: true, action: onNew)
            TopItemRow(icon: .system("books.vertical"),  label: "Library",    action: onNew)
            TopItemRow(icon: .system("square.grid.2x2"), label: "Workspaces", action: onNew)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.7)
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyHint: some View {
        Text("Start a conversation to see history here.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
    }

    private func groupRuns(_ runs: [SavedAgentRun]) -> [(String, [SavedAgentRun])] {
        let cal = Calendar.current
        let now = Date()
        var buckets: [(String, [SavedAgentRun])] = [
            ("Today", []), ("Yesterday", []),
            ("Previous 7 Days", []), ("Previous 30 Days", []), ("Older", [])
        ]
        for run in runs {
            if cal.isDateInToday(run.startedAt) {
                buckets[0].1.append(run)
            } else if cal.isDateInYesterday(run.startedAt) {
                buckets[1].1.append(run)
            } else if let days = cal.dateComponents([.day], from: run.startedAt, to: now).day {
                if days <= 7      { buckets[2].1.append(run) }
                else if days <= 30 { buckets[3].1.append(run) }
                else              { buckets[4].1.append(run) }
            }
        }
        return buckets.filter { !$0.1.isEmpty }
    }
}

private enum SidebarIcon {
    case system(String)
    case asterisk
}

private struct TopItemRow: View {
    let icon: SidebarIcon
    let label: String
    var isAccent: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    switch icon {
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                    case .asterisk:
                        AsteriskMark(size: 13, tint: isAccent ? .accentColor : .secondary)
                            .frame(width: 18)
                    }
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(Motion.easeOut) { hovering = h }
        }
    }
}

private struct ProjectRow: View {
    let path: String
    @State private var hovering = false

    private var name: String { URL(fileURLWithPath: path).lastPathComponent }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { h in
            withAnimation(Motion.easeOut) { hovering = h }
        }
        .help(path)
    }
}

private struct SidebarRow: View {
    let run: SavedAgentRun
    let selected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Text(truncate(run.task, max: 30))
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hovering {
                    Menu {
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 11))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 18)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected
                          ? Color.primary.opacity(0.10)
                          : (hovering ? Color.primary.opacity(0.06) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(Motion.easeOut) { hovering = h }
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        if s.count <= max { return s }
        return String(s.prefix(max - 1)) + "…"
    }
}

// MARK: - User footer

private struct UserFooterRow: View {
    @State private var hovering = false

    private var initials: String {
        guard AuthService.shared.isSignedIn,
              let uid = AuthService.shared.uid,
              !uid.isEmpty
        else { return "?" }
        // No display name in AuthService — fall back to first two chars of uid.
        return String(uid.prefix(2)).uppercased()
    }

    private var label: String {
        AuthService.shared.isSignedIn ? "Account" : "Sign in"
    }

    private var subtitle: String {
        AuthService.shared.isSignedIn ? "Settings & preferences" : "Configure Ithuriel"
    }

    var body: some View {
        Button(action: { AppRouter.shared.openSettings() }) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 28, height: 28)
                    Text(initials)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(hovering ? 0.06 : 0))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(Motion.easeOut) { hovering = h }
        }
    }
}

// MARK: - Top bar

private struct ChatTopBar: View {
    let workspaceLabel: String?

    var body: some View {
        HStack(spacing: 8) {
            if let workspaceLabel {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(workspaceLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )
            }
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(height: 44)
        .padding(.top, 30)   // clear traffic lights area
    }
}

// MARK: - Empty state

private struct ChatEmptyState: View {
    @Binding var prompt: String
    let onFocusComposer: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            SpinningBrandMark(size: 80, showRing: true, duration: 24)

            VStack(spacing: 8) {
                Text(Greeting.headline())
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.94))
                Text(Greeting.subtitle())
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }

            HStack(spacing: 8) {
                quickPromptChip(NSLocalizedString("chat.hint.git", comment: ""))
                quickPromptChip(NSLocalizedString("chat.hint.summarize", comment: ""))
                quickPromptChip(NSLocalizedString("chat.hint.open", comment: ""))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickPromptChip(_ text: String) -> some View {
        Button {
            prompt = text
            onFocusComposer()
        } label: {
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .splashChrome(cornerRadius: 20, strokeOpacity: 0.16)
    }
}

// MARK: - Bubbles

enum ChatRole { case user, assistant }

private struct ChatBubbleView: View {
    let role: ChatRole
    let text: String
    let index: Int
    var showHeader: Bool = true

    var body: some View {
        switch role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .frame(maxWidth: 520, alignment: .trailing)
                    .textSelection(.enabled)
            }
            .staggered(index)

        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                if showHeader {
                    HStack(spacing: 6) {
                        SpinningBrandMark(size: 14, showRing: false, duration: 32)
                        Text("Ithuriel")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                Text(text)
                    .font(.system(size: 15))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .staggered(index)
        }
    }
}

private struct ToolUseCard: View {
    let call: String
    let result: String?
    let index: Int

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.easeOut) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: result != nil ? "checkmark.circle.fill" : "wrench.and.screwdriver.fill")
                        .foregroundStyle(result != nil ? .green : .blue)
                        .font(.system(size: 11))
                    Text(headline)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().opacity(0.4)
                Text(detail)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .staggered(index)
    }

    private var headline: String {
        if !call.isEmpty { return call }
        if let result, !result.isEmpty { return result }
        return "tool"
    }

    private var detail: String {
        if !call.isEmpty, let result, !result.isEmpty { return "\(call)\n\n→ \(result)" }
        return call.isEmpty ? (result ?? "") : call
    }
}

private struct ErrorRow: View {
    let text: String
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.red.opacity(0.9))
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .staggered(index)
    }
}

private struct SystemRow: View {
    let text: String
    let index: Int

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .staggered(index)
    }
}

// MARK: - Composer

private struct ChatComposer: View {
    @Binding var prompt: String
    @FocusState.Binding var inputFocused: Bool
    let placeholder: String
    let canSubmit: Bool
    let isRunning: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onMic: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Text row
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextField("", text: $prompt, axis: .vertical)
                    .lineLimit(1...8)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($inputFocused)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .onSubmit(onSubmit)
            }
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)

            // Controls row
            HStack(spacing: 6) {
                ComposerIconButton(system: "plus", help: "Attach") { }
                ComposerIconButton(system: "globe", help: "Search the web") { }
                ComposerIconButton(system: "character.textbox", help: "Style") { }

                Spacer()

                ComposerIconButton(system: "mic.fill", help: "Voice input", action: onMic)
                sendOrStopButton
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .padding(.top, 2)
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                Color.black.opacity(0.18)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(inputFocused ? 0.22 : 0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(Motion.easeOut, value: inputFocused)
    }

    private var sendOrStopButton: some View {
        Button {
            if isRunning { onStop() } else { onSubmit() }
        } label: {
            ZStack {
                Circle()
                    .fill(buttonFill)
                    .frame(width: 30, height: 30)
                Image(systemName: isRunning ? "square.fill" : "arrow.up")
                    .font(.system(size: isRunning ? 10 : 13, weight: .bold))
                    .foregroundStyle(isRunning ? .white : .black.opacity(0.85))
            }
        }
        .buttonStyle(.pressable(scale: 0.92, sound: .submit))
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!isRunning && !canSubmit)
        .animation(Motion.easeOut, value: isRunning)
    }

    private var buttonFill: AnyShapeStyle {
        if isRunning {
            return AnyShapeStyle(Color.white.opacity(0.22))
        }
        if canSubmit {
            return AnyShapeStyle(Color.white)
        }
        return AnyShapeStyle(Color.white.opacity(0.10))
    }
}

private struct ComposerIconButton: View {
    let system: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in
            withAnimation(Motion.easeOut) { hovering = h }
        }
    }
}

// MARK: - Transcript line decoder

enum ChatBubble {
    enum Role { case user, assistant, tool, toolResult, error, system }

    static func agentForLine(_ line: String) -> Role {
        switch AgentTranscript.present(line).kind {
        case .task:      return .user
        case .thinking, .reply: return .assistant
        case .action:    return .tool
        case .done:      return .assistant
        case .error:     return .error
        case .stopped, .progress, .plain: return .system
        }
    }

    static func cleanLine(_ line: String) -> String {
        let p = AgentTranscript.present(line)
        if let detail = p.detail {
            return "\(p.title)\n\(detail)"
        }
        return p.title
    }
}
