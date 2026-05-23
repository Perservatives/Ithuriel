import SwiftUI
import SwiftData
import AppKit

/// Full chat GUI. Three-pane layout inspired by Claude / ChatGPT macOS apps:
/// left sidebar = past runs (chronological), centre = current conversation,
/// right inspector = context web visualisation.
///
/// Opened via the menu bar context menu ("Open chat…") or ⌘N globally when
/// any Ithuriel window is key.
struct ChatView: View {
    @ObservedObject var agent: AgentLoop
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedAgentRun.startedAt, order: .reverse) private var runs: [SavedAgentRun]
    @Query private var prefsList: [UserPrefs]

    @State private var selectedRunID: UUID?
    @State private var prompt: String = ""
    @State private var showInspector: Bool = true
    @FocusState private var inputFocused: Bool

    private var prefs: UserPrefs? { prefsList.first }
    private var keyMissing: Bool { (prefs?.geminiApiKey ?? "").isEmpty }

    var body: some View {
        NavigationSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280)
        } detail: {
            HSplitView {
                conversation
                    .frame(minWidth: 480)
                if showInspector {
                    ContextWebView()
                        .frame(minWidth: 280, idealWidth: 360)
                        .background(VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow))
                }
            }
        }
        .navigationTitle("Ithuriel")
        .toolbar { toolbarContent }
        .background(VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow))
        .frame(minWidth: 1000, minHeight: 640)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "asterisk")
                    .foregroundStyle(.tint)
                    .font(.system(size: 13, weight: .semibold))
                Text("History")
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
            .padding(.vertical, 10)

            Divider().opacity(0.4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if runs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No runs yet").font(.subheadline).foregroundStyle(.secondary)
                            Text("Type a task to start your first conversation.")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                    }
                    ForEach(runs) { run in
                        runRow(run)
                            .staggered(min(runs.firstIndex(of: run) ?? 0, 12))
                    }
                }
                .padding(8)
            }
        }
        .background(VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow))
    }

    private func runRow(_ run: SavedAgentRun) -> some View {
        let selected = run.id == selectedRunID
        return Button {
            selectedRunID = run.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(statusColor(run.status))
                    .frame(width: 6, height: 6)
                    .offset(y: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.task)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(run.startedAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) {
                modelContext.delete(run)
                if selectedRunID == run.id { selectedRunID = nil }
            }
        }
    }

    private func statusColor(_ status: AgentRunRecord.Status) -> Color {
        switch status {
        case .running:   return .accentColor
        case .completed: return .green
        case .failed:    return .red
        case .killed:    return .orange
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if let selected = selectedRun {
                            messageList(for: selected.transcript, taskHeader: selected.task)
                        } else if agent.isRunning || !agent.transcript.isEmpty {
                            messageList(for: agent.transcript, taskHeader: nil)
                        } else {
                            emptyConversation
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                }
                .onChange(of: agent.transcript.count) { _, count in
                    withAnimation(Motion.easeOut) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            Divider().opacity(0.3)
            composer
                .padding(16)
        }
    }

    @ViewBuilder
    private func messageList(for transcript: [String], taskHeader: String?) -> some View {
        if let task = taskHeader {
            ChatBubble(role: .user, text: task, index: 0)
        }
        ForEach(Array(transcript.enumerated()), id: \.offset) { idx, line in
            ChatBubble(role: ChatBubble.agentForLine(line), text: ChatBubble.cleanLine(line), index: idx)
        }
        Color.clear.frame(height: 1).id("bottom")
    }

    private var emptyConversation: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.accentColor.opacity(0.35), .clear],
                            center: .center, startRadius: 4, endRadius: 80
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 30)
                Image(systemName: "asterisk")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(.tint)
            }
            Text("Ask Ithuriel anything")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
            Text("It already knows your workspace, git state, recent edits, and terminal history. Skip the preamble.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if prompt.isEmpty {
                    Text(keyMissing
                         ? "Add your Gemini API key in Settings…"
                         : "Message Ithuriel…")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 14)
                }
                TextField("", text: $prompt, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, design: .rounded))
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .onSubmit(runAgent)
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(inputFocused ? 0.08 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(inputFocused ? 0.5 : 0), lineWidth: 1)
            )
            .animation(Motion.easeOut, value: inputFocused)

            Button(action: runAgent) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(canSubmit
                              ? AnyShapeStyle(LinearGradient(
                                    colors: [Color(red: 1, green: 0.45, blue: 0.32),
                                             Color(red: 0.94, green: 0.30, blue: 0.22)],
                                    startPoint: .top, endPoint: .bottom))
                              : AnyShapeStyle(Color.secondary.opacity(0.18)))
                        .frame(width: 44, height: 44)
                        .shadow(color: canSubmit ? Color(red: 1, green: 0.45, blue: 0.32).opacity(0.55) : .clear,
                                radius: canSubmit ? 12 : 0, y: 4)
                    Image(systemName: agent.isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.pressable(scale: 0.93, sound: .submit))
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSubmit && !agent.isRunning)
        }
    }

    private var canSubmit: Bool {
        !prompt.trimmingCharacters(in: .whitespaces).isEmpty && !agent.isRunning && !keyMissing
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                newConversation()
            } label: {
                Label("New", systemImage: "square.and.pencil")
            }
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
        guard !task.isEmpty, !agent.isRunning else {
            if agent.isRunning { agent.stop() }
            return
        }
        prompt = ""
        selectedRunID = nil
        Task { await agent.run(task: task) }
    }
}

// MARK: - Chat bubble

struct ChatBubble: View {
    enum Role { case user, assistant, tool, toolResult, error, system }

    let role: Role
    let text: String
    let index: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(roleName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleColor)
                Text(text)
                    .font(role == .tool ? .system(.callout, design: .monospaced) : .body)
                    .foregroundStyle(.primary.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bgTint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(bgTint.opacity(0.18), lineWidth: 0.5)
        )
        .staggered(index)
    }

    @ViewBuilder
    private var avatar: some View {
        switch role {
        case .user:
            Circle()
                .fill(Color.secondary.opacity(0.18))
                .overlay(Image(systemName: "person.fill").font(.system(size: 13)).foregroundStyle(.secondary))
        case .assistant:
            Circle()
                .fill(RadialGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                     center: .center, startRadius: 2, endRadius: 14))
                .overlay(Image(systemName: "asterisk").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
        case .tool:
            Circle()
                .fill(Color.blue.opacity(0.18))
                .overlay(Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 11)).foregroundStyle(.blue))
        case .toolResult:
            Circle()
                .fill(Color.green.opacity(0.18))
                .overlay(Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.green))
        case .error:
            Circle()
                .fill(Color.red.opacity(0.18))
                .overlay(Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.red))
        case .system:
            Circle()
                .fill(Color.secondary.opacity(0.10))
                .overlay(Image(systemName: "circle.dotted").font(.system(size: 11)).foregroundStyle(.tertiary))
        }
    }

    private var roleName: String {
        switch role {
        case .user:       return "You"
        case .assistant:  return "Ithuriel"
        case .tool:       return "Tool call"
        case .toolResult: return "Result"
        case .error:      return "Error"
        case .system:     return "System"
        }
    }

    private var roleColor: Color {
        switch role {
        case .user:       return .secondary
        case .assistant:  return .accentColor
        case .tool:       return .blue
        case .toolResult: return .green
        case .error:      return .red
        case .system:     return .secondary
        }
    }

    private var bgTint: Color {
        switch role {
        case .user:       return .secondary
        case .assistant:  return .accentColor
        case .tool:       return .blue
        case .toolResult: return .green
        case .error:      return .red
        case .system:     return .secondary
        }
    }

    // Decode the AgentLoop transcript convention into a role.
    static func agentForLine(_ line: String) -> Role {
        if line.hasPrefix("▶") { return .user }
        if line.hasPrefix("·") { return .assistant }
        if line.hasPrefix("→") { return .tool }
        if line.hasPrefix("✓") { return .assistant }
        if line.hasPrefix("✗") { return .error }
        if line.hasPrefix("■") { return .system }
        if line.hasPrefix("◌") { return .system }
        return .system
    }

    static func cleanLine(_ line: String) -> String {
        let prefixes: Set<Character> = ["▶", "·", "→", "✓", "✗", "■", "◌"]
        if let first = line.first, prefixes.contains(first) {
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}
