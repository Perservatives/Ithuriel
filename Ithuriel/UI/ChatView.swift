import SwiftUI
import SwiftData
import AppKit

/// Full chat GUI. Follows the patterns of ChatGPT-mac and Claude-mac:
///   - Asymmetric messages: user = right-aligned bubble, assistant = full-width
///     block with no avatar (the model's text is the focus).
///   - Composer pill at the bottom with model picker inside; send button morphs
///     into a square stop button while streaming.
///   - Sidebar grouped by Today / Yesterday / Previous 7 Days / Previous 30
///     Days / Older with single-line truncated titles and a hover ⋯ menu.
///   - Context Web inspector on the right (toggleable).
struct ChatView: View {
    @ObservedObject var agent: AgentLoop
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedAgentRun.startedAt, order: .reverse) private var runs: [SavedAgentRun]
    @Query private var prefsList: [UserPrefs]

    @State private var selectedRunID: UUID?
    @State private var prompt: String = ""
    @State private var showInspector: Bool = true
    @State private var searchQuery: String = ""
    @State private var isFullScreen: Bool = false
    @FocusState private var inputFocused: Bool

    private var prefs: UserPrefs? { prefsList.first }
    private var keyMissing: Bool { (prefs?.geminiApiKey ?? "").isEmpty }

    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 200, idealWidth: 240)
        } detail: {
            HSplitView {
                conversation.frame(minWidth: 380)
                if showInspector {
                    ContextWebView()
                        .frame(minWidth: isFullScreen ? 240 : 160,
                               idealWidth: isFullScreen ? 320 : 200)
                        .background(VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow))
                }
            }
        }
        .navigationTitle("Ithuriel")
        .toolbar { toolbarContent }
        .toolbarBackground(.regularMaterial, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .background(VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow))
        .frame(minWidth: 720, minHeight: 480)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            ZStack(alignment: .leading) {
                if searchQuery.isEmpty {
                    Text("Search")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 28)
                }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    let groups = groupRuns(filteredRuns)
                    if groups.isEmpty {
                        emptySidebar
                    }
                    ForEach(groups, id: \.0) { groupTitle, items in
                        Section {
                            ForEach(items) { run in
                                SidebarRow(
                                    run: run,
                                    selected: run.id == selectedRunID,
                                    onSelect: { selectedRunID = run.id },
                                    onDelete: {
                                        if selectedRunID == run.id { selectedRunID = nil }
                                        modelContext.delete(run)
                                    }
                                )
                            }
                        } header: {
                            Text(groupTitle)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))
    }

    private var sidebarHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "asterisk")
                .foregroundStyle(.tint)
                .font(.system(size: 13, weight: .semibold))
            Text("Ithuriel")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Spacer()
            Button {
                newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.pressable(sound: .summon))
            .help("New conversation (⌘N)")
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var emptySidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No runs yet").font(.subheadline).foregroundStyle(.secondary)
            Text("Start a conversation to see history here.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    private var filteredRuns: [SavedAgentRun] {
        guard !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return runs }
        let q = searchQuery.lowercased()
        return runs.filter { $0.task.lowercased().contains(q) }
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

    // MARK: - Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if let selected = selectedRun {
                            renderMessages(transcript: selected.transcript, header: selected.task)
                        } else if agent.isRunning || !agent.transcript.isEmpty {
                            renderMessages(transcript: agent.transcript, header: nil)
                        } else {
                            emptyConversation
                        }
                        Color.clear.frame(height: 60).id("bottom")
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 32)
                }
                .onChange(of: agent.transcript.count) { _, _ in
                    withAnimation(Motion.easeOut) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            composer.padding(20)
        }
    }

    @ViewBuilder
    private func renderMessages(transcript: [String], header: String?) -> some View {
        if let header {
            UserMessageRow(text: header, index: 0)
        }
        ForEach(Array(transcript.enumerated()), id: \.offset) { idx, line in
            messageRow(for: line, index: idx)
        }
    }

    @ViewBuilder
    private func messageRow(for line: String, index: Int) -> some View {
        let role = ChatBubble.agentForLine(line)
        let clean = ChatBubble.cleanLine(line)
        switch role {
        case .user:
            UserMessageRow(text: clean, index: index)
        case .assistant:
            AssistantMessageRow(text: clean, index: index)
        case .tool:
            ToolUseCard(call: clean, result: nil, index: index)
        case .toolResult:
            // Appended to the previous tool card if possible — for now, render
            // inline so the timeline is still complete.
            ToolUseCard(call: "", result: clean, index: index)
        case .error:
            ErrorRow(text: clean, index: index)
        case .system:
            SystemRow(text: clean, index: index)
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.30), .clear],
                            center: .center, startRadius: 4, endRadius: 90
                        )
                    )
                    .frame(width: 220, height: 220)
                    .blur(radius: 36)
                Image(systemName: "asterisk")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(.tint)
                    .shadow(color: .accentColor.opacity(0.6), radius: 18)
            }
            Text("What's on your mind?")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text(keyMissing
                             ? "Add your Gemini API key in Settings…"
                             : "Message Ithuriel…")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $prompt, axis: .vertical)
                        .lineLimit(1...8)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($inputFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .onSubmit(runAgent)
                }
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                ModelPicker(selection: Binding(
                    get: { prefs?.geminiModel ?? "gemini-2.5-flash" },
                    set: { newValue in
                        prefs?.geminiModel = newValue
                        try? modelContext.save()
                    }
                ))

                Spacer()

                Text(keyMissing ? "no key" : "ready")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(keyMissing ? Color.orange : Color.secondary.opacity(0.6))

                sendOrStopButton
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(inputFocused ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(inputFocused ? 0.18 : 0.10), lineWidth: 0.5)
        )
        .animation(Motion.easeOut, value: inputFocused)
    }

    /// Single button that morphs between Send (arrow.up) and Stop (square.fill)
    /// — Claude/ChatGPT pattern.
    private var sendOrStopButton: some View {
        Button {
            if agent.isRunning {
                agent.stop()
            } else {
                runAgent()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(buttonFill)
                    .frame(width: 32, height: 32)
                    .shadow(color: canSubmit ? Color(red: 1, green: 0.45, blue: 0.32).opacity(0.5) : .clear,
                            radius: canSubmit ? 8 : 0, y: 3)
                Image(systemName: agent.isRunning ? "square.fill" : "arrow.up")
                    .font(.system(size: agent.isRunning ? 11 : 13, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.pressable(scale: 0.92, sound: .submit))
        .keyboardShortcut(.return, modifiers: [])
        .disabled(!agent.isRunning && !canSubmit)
        .animation(Motion.easeOut, value: agent.isRunning)
    }

    private var buttonFill: AnyShapeStyle {
        if agent.isRunning {
            return AnyShapeStyle(Color.primary.opacity(0.85))
        }
        if canSubmit {
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1, green: 0.45, blue: 0.32),
                         Color(red: 0.94, green: 0.30, blue: 0.22)],
                startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Color.secondary.opacity(0.18))
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !agent.isRunning && !keyMissing
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { newConversation() } label: { Label("New", systemImage: "square.and.pencil") }
                .help("New conversation (⌘N)")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                withAnimation(Motion.easeOut) { showInspector.toggle() }
            } label: {
                Label("Context Web", systemImage: showInspector ? "circle.grid.hex.fill" : "circle.grid.hex")
            }
            .help("Toggle context graph")
        }
    }

    // MARK: - Actions

    private var selectedRun: SavedAgentRun? {
        guard let id = selectedRunID else { return nil }
        return runs.first { $0.id == id }
    }

    private func newConversation() {
        selectedRunID = nil
        prompt = ""
        inputFocused = true
    }

    private func runAgent() {
        let task = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isEmpty, !agent.isRunning else { return }
        prompt = ""
        selectedRunID = nil
        Task { await agent.run(task: task) }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    let run: SavedAgentRun
    let selected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(run.task)
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
                          ? Color.accentColor.opacity(0.16)
                          : (hovering ? Color.primary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }

    private var statusColor: Color {
        switch run.status {
        case .running:   return .accentColor
        case .completed: return .green
        case .failed:    return .red
        case .killed:    return .orange
        }
    }
}

// MARK: - Message rows (asymmetric layout)

private struct UserMessageRow: View {
    let text: String
    let index: Int

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                )
                .frame(maxWidth: 520, alignment: .trailing)
                .textSelection(.enabled)
        }
        .staggered(index)
    }
}

private struct AssistantMessageRow: View {
    let text: String
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "asterisk")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tint)
                Text("Ithuriel")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
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
                .fill(Color.blue.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.blue.opacity(0.18), lineWidth: 0.5)
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

// MARK: - Model picker

private struct ModelPicker: View {
    @Binding var selection: String

    private let options: [(id: String, label: String)] = [
        ("gemini-2.5-flash",          "Flash 2.5 · fast"),
        ("gemini-2.5-flash-thinking", "Flash 2.5 · thinking"),
        ("gemini-2.5-pro",            "Pro 2.5"),
        ("gemini-3.0-flash",          "Flash 3.0"),
        ("gemini-3.0-pro",            "Pro 3.0")
    ]

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { opt in
                Button(opt.label) { selection = opt.id }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.system(size: 10))
                Text(label(for: selection))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func label(for id: String) -> String {
        options.first(where: { $0.id == id })?.label ?? id
    }
}

// MARK: - Transcript line decoder (used by parent ChatView)

enum ChatBubble {
    enum Role { case user, assistant, tool, toolResult, error, system }

    static func agentForLine(_ line: String) -> Role {
        switch AgentTranscript.present(line).kind {
        case .task:      return .user
        case .thinking:  return .assistant
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
