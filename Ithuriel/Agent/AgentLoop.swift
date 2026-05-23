import Foundation
import SwiftData
import AppKit

/// The agentic loop. User issues a task → we gather full context →
/// hand it to Gemini → execute its function calls → feed results back →
/// repeat until Gemini calls `done` or the kill-switch fires.
@MainActor
final class AgentLoop: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var transcript: [String] = []
    @Published private(set) var lastError: String?

    private weak var container: ModelContainer?
    private let maxSteps = 100

    // MARK: - Conversation threading
    // A "conversation" persists across multiple user turns until the user
    // explicitly starts a new chat (pencil button / ⌘N). All turns share
    // the same runId so they upsert into one SavedAgentRun row in the
    // sidebar instead of spawning a new chat per message.
    private var currentConversationId: UUID?
    private var currentConversationStartedAt: Date?
    private var conversationHistory: [GeminiClient.Content] = []

    init(container: ModelContainer?) {
        self.container = container
    }

    /// Reset threading state so the NEXT `run(task:)` starts a fresh
    /// conversation with a new id, empty transcript, empty model history.
    func startNewConversation() {
        currentConversationId = nil
        currentConversationStartedAt = nil
        conversationHistory.removeAll()
        transcript.removeAll()
    }

    func run(task userTask: String) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        // Only clear transcript for a brand-new conversation; otherwise we
        // append to the existing one so the chat reads as a continuous
        // thread instead of separate "Task" rows.
        if currentConversationId == nil { transcript.removeAll() }
        AgentController.shared.arm()
        SoundPlayer.shared.play(.submit)
        AgentStatusBus.shared.publish(.started(task: userTask))
        defer { isRunning = false }

        guard let container = container else { return }
        let prefs = (try? UserPrefs.load(in: container)) ?? UserPrefs.defaults()
        guard prefs.agentEnabled else {
            lastError = NSLocalizedString("agent.err.disabled", comment: "")
            return
        }
        guard !prefs.geminiApiKey.isEmpty else {
            lastError = NSLocalizedString("agent.err.noKey", comment: "")
            return
        }

        if ConversationalTurn.matches(userTask) {
            await runConversational(userTask: userTask, prefs: prefs, container: container)
            return
        }

        // Temporary-chat opt-out: ⌘⇧N in ChatView sets this flag so the next
        // run skips cloud sync + persistence. One-shot — consumed and cleared.
        let temporary = UserDefaults.standard.bool(forKey: "Ithuriel.NextRunTemporary")
        if temporary { UserDefaults.standard.set(false, forKey: "Ithuriel.NextRunTemporary") }

        // Reuse the existing conversation id if we're mid-thread; only mint
        // a new one when starting a fresh chat. Same for startedAt.
        let runId = currentConversationId ?? UUID()
        let startedAt = currentConversationStartedAt ?? Date()
        currentConversationId = runId
        currentConversationStartedAt = startedAt
        let apiClient = IthurielClient(prefs: prefs)
        let cloudSyncEnabled = !temporary && !prefs.localOnly && AuthService.shared.isSignedIn
        if cloudSyncEnabled {
            try? await apiClient.postAgentRun(.init(
                id: runId, task: userTask, status: .running,
                startedAt: startedAt, finishedAt: nil,
                transcript: [], error: nil, snapshotId: nil
            ))
        }

        let containerRef = container
        let workspacePath = prefs.activeWorkspace
        let modelName = GeminiModels.normalize(prefs.geminiModel)
        await SavedAgentRun.persist(
            id: runId, task: userTask, status: .running,
            startedAt: startedAt, finishedAt: nil,
            transcript: [], errorText: nil,
            workspacePath: workspacePath, modelName: modelName,
            in: containerRef
        )

        func uploadFinalState(_ status: AgentRunRecord.Status) async {
            await SavedAgentRun.persist(
                id: runId, task: userTask, status: status,
                startedAt: startedAt, finishedAt: Date(),
                transcript: transcript, errorText: lastError,
                workspacePath: workspacePath, modelName: modelName,
                in: containerRef
            )
            guard cloudSyncEnabled else { return }
            try? await apiClient.postAgentRun(.init(
                id: runId, task: userTask, status: status,
                startedAt: startedAt, finishedAt: Date(),
                transcript: transcript, error: lastError, snapshotId: nil
            ))
        }

        let client = GeminiClient(apiKey: prefs.geminiApiKey, model: GeminiModels.normalize(prefs.geminiModel))
        let tools = AgentTools.declarations
        let snapshot = await CachedSnapshot.latest(in: container)
        let related: [IthurielClient.RelatedSnapshot]
        if !prefs.localOnly, AuthService.shared.isSignedIn {
            related = await apiClient.searchContext(query: userTask, k: 5)
        } else {
            related = []
        }
        // Local KNN over the Firestore vector index. Independent of the
        // Cloud Run RAG path above — uses the same `embedding` field shape
        // and is wrapped so any failure (no key, no network, no index)
        // silently omits the section instead of breaking the run.
        let localNeighbours = await fetchLocalNeighbours(userTask: userTask, prefs: prefs, container: container)
        let systemPrompt = buildSystemPrompt(
            snapshot: snapshot,
            prefs: prefs,
            related: related,
            localNeighbours: localNeighbours
        )

        // Carry prior turns in the same thread forward so Gemini sees the
        // full conversation, not just the latest user message.
        var convo: [GeminiClient.Content] = conversationHistory
        convo.append(.init(role: "user", parts: [.init(text: userTask)]))
        log(AgentTranscript.lineTaskStarted(userTask))

        for step in 1...maxSteps {
            if AgentController.shared.killed {
                log(AgentTranscript.lineKilled())
                AgentStatusBus.shared.publish(.stopped)
                await uploadFinalState(.killed)
                return
            }
            let modelTurn: GeminiClient.Content
            do {
                modelTurn = try await client.step(contents: convo, tools: tools, system: systemPrompt)
            } catch {
                lastError = "\(error)"
                log(AgentTranscript.lineGeminiError("\(error)"))
                AgentStatusBus.shared.publish(.failed(error: "\(error)"))
                await uploadFinalState(.failed)
                return
            }
            convo.append(modelTurn)

            var functionResponses: [GeminiClient.Part] = []
            var sawDone = false

            for part in modelTurn.parts {
                if let text = part.text, !text.isEmpty {
                    log(AgentTranscript.lineThinking(text))
                }
                guard let call = part.functionCall else { continue }
                if call.name == "done" {
                    sawDone = true
                    let summary = call.args["summary"]?.stringValue ?? "done"
                    log(AgentTranscript.lineDone(summary))
                    SoundPlayer.shared.play(.done)
                    AgentStatusBus.shared.publish(.finished(summary: summary))
                    AgentSpeaker.shared.speakAsync(summary, prefs: prefs)
                    continue
                }
                let result = await dispatch(call: call, prefs: prefs)
                // `say` is narration, not an action — skip the symbol-prefixed
                // transcript line and the tool sound effect for it. The
                // headline-binding in SpotlightView surfaces it directly.
                if call.name != "say" {
                    log(AgentTranscript.lineAction(name: call.name, args: call.args, result: result))
                    SoundPlayer.shared.play(.tool, volume: 0.4)
                }
                let resp = GeminiClient.Part(
                    functionResponse: GeminiClient.Part.FunctionResponse(
                        name: call.name,
                        response: ["result": .string(result)]
                    )
                )
                functionResponses.append(resp)
            }

            if sawDone {
                conversationHistory = convo
                await uploadFinalState(.completed)
                return
            }
            if functionResponses.isEmpty {
                log(AgentTranscript.lineNoToolCalls())
                let summary = transcript.last(where: { $0.hasPrefix("·") }).map {
                    String($0.dropFirst()).trimmingCharacters(in: .whitespaces)
                } ?? "done"
                AgentStatusBus.shared.publish(.finished(summary: summary))
                AgentSpeaker.shared.speakAsync(summary, prefs: prefs)
                conversationHistory = convo
                await uploadFinalState(.completed)
                return
            }
            convo.append(.init(role: "user", parts: functionResponses))
            log(AgentTranscript.lineStepComplete(step: step, maxSteps: maxSteps))
        }

        log(AgentTranscript.lineStepBudgetExhausted(maxSteps: maxSteps))
        AgentStatusBus.shared.publish(.failed(error: "step budget exhausted"))
        await uploadFinalState(.failed)
    }

    func stop() {
        AgentController.shared.kill()
        log(AgentTranscript.lineStopRequested())
    }

    // MARK: - Casual chat (agent enabled, no computer-use tools)

    private func runConversational(userTask: String, prefs: UserPrefs, container: ModelContainer) async {
        let temporary = UserDefaults.standard.bool(forKey: "Ithuriel.NextRunTemporary")
        if temporary { UserDefaults.standard.set(false, forKey: "Ithuriel.NextRunTemporary") }

        // Same conversation-id reuse as the full agent loop so the chat reads
        // as one thread instead of a new sidebar row per turn.
        let runId = currentConversationId ?? UUID()
        let startedAt = currentConversationStartedAt ?? Date()
        currentConversationId = runId
        currentConversationStartedAt = startedAt
        let apiClient = IthurielClient(prefs: prefs)
        let cloudSyncEnabled = !temporary && !prefs.localOnly && AuthService.shared.isSignedIn
        if cloudSyncEnabled {
            try? await apiClient.postAgentRun(.init(
                id: runId, task: userTask, status: .running,
                startedAt: startedAt, finishedAt: nil,
                transcript: [], error: nil, snapshotId: nil
            ))
        }

        let workspacePath = prefs.activeWorkspace
        let modelName = GeminiModels.normalize(prefs.geminiModel)
        await SavedAgentRun.persist(
            id: runId, task: userTask, status: .running,
            startedAt: startedAt, finishedAt: nil,
            transcript: transcript, errorText: nil,
            workspacePath: workspacePath, modelName: modelName,
            in: container
        )

        func uploadFinalState(_ status: AgentRunRecord.Status) async {
            await SavedAgentRun.persist(
                id: runId, task: userTask, status: status,
                startedAt: startedAt, finishedAt: Date(),
                transcript: transcript, errorText: lastError,
                workspacePath: workspacePath, modelName: modelName,
                in: container
            )
            guard cloudSyncEnabled else { return }
            try? await apiClient.postAgentRun(.init(
                id: runId, task: userTask, status: status,
                startedAt: startedAt, finishedAt: Date(),
                transcript: transcript, error: lastError, snapshotId: nil
            ))
        }

        let client = GeminiClient(apiKey: prefs.geminiApiKey, model: GeminiModels.normalize(prefs.geminiModel))
        let snapshot = await CachedSnapshot.latest(in: container)
        let systemPrompt = buildConversationalSystemPrompt(snapshot: snapshot, prefs: prefs)
        log(AgentTranscript.lineTaskStarted(userTask))

        do {
            // Thread prior turns in so casual chat remembers context.
            var convo = conversationHistory
            convo.append(.init(role: "user", parts: [.init(text: userTask)]))
            let modelTurn = try await client.step(
                contents: convo,
                tools: [],
                system: systemPrompt
            )
            let reply = Self.displayText(from: modelTurn)
            guard !reply.isEmpty else {
                lastError = NSLocalizedString("agent.err.emptyReply", comment: "")
                log(AgentTranscript.lineGeminiError(lastError ?? ""))
                AgentStatusBus.shared.publish(.failed(error: lastError ?? ""))
                await uploadFinalState(.failed)
                return
            }
            log(AgentTranscript.lineReply(reply))
            SoundPlayer.shared.play(.done, volume: 0.35)
            AgentStatusBus.shared.publish(.replied(message: reply))
            AgentSpeaker.shared.speakAsync(reply, prefs: prefs)
            convo.append(modelTurn)
            conversationHistory = convo
            await uploadFinalState(.completed)
        } catch {
            lastError = "\(error)"
            log(AgentTranscript.lineGeminiError("\(error)"))
            AgentStatusBus.shared.publish(.failed(error: "\(error)"))
            await uploadFinalState(.failed)
        }
    }

    private func buildConversationalSystemPrompt(snapshot: ContextSnapshot?, prefs: UserPrefs) -> String {
        var s = """
        You are Ithuriel — a friendly macOS assistant the user chats with from the menu bar.
        This turn is casual conversation, not a computer-use task.

        Reply naturally, like a helpful colleague:
          - If they greet you, greet them back briefly.
          - Answer questions about yourself or what you can do in plain language.
          - Keep replies concise (usually 1–3 sentences) unless they ask for more.
          - Do not say you "finished", "completed", or "greeted" a task.
          - Do not use bullet lists or status-report tone unless they asked for detail.
          - You are not driving their Mac on this turn — just talk.

        If they clearly want you to do something on their computer (edit files, run commands,
        click apps), tell them to ask in a direct task sentence and you will take over.
        """

        if let snap = snapshot, !snap.workspacePath.isEmpty {
            s += "\n\n(Context: their active workspace is \(snap.workspacePath).)"
        }
        return s
    }

    private static func displayText(from content: GeminiClient.Content) -> String {
        content.parts.compactMap { part -> String? in
            if part.thought == true { return nil }
            guard let text = part.text else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.joined(separator: "\n")
    }

    private func log(_ line: String) {
        transcript.append(line)
        Log.info("[agent] \(line)")
    }

    /// Local vector-DB lookup. Embeds the user's task with Gemini and asks
    /// Firestore for the nearest snapshots in the user's subcollection.
    /// Returns up to 3 short summaries; any failure yields `[]` so the
    /// agent runs unaugmented when the local KNN path is unavailable.
    private func fetchLocalNeighbours(userTask: String,
                                      prefs: UserPrefs,
                                      container: ModelContainer) async -> [String] {
        guard !prefs.localOnly, AuthService.shared.isSignedIn,
              !prefs.geminiApiKey.isEmpty else { return [] }
        do {
            let hits = try await VectorSearch.nearest(query: userTask, k: 3, prefs: prefs)
            var out: [String] = []
            for hit in hits.prefix(3) {
                guard let uuid = UUID(uuidString: hit.id) else {
                    out.append("snapshot \(hit.id) (score \(String(format: "%.3f", hit.score)))")
                    continue
                }
                if let snap = await CachedSnapshot.find(id: uuid, in: container) {
                    let branch = snap.gitState?.branch ?? "?"
                    let commit = snap.gitState?.lastCommit ?? ""
                    let shortCommit = commit.isEmpty ? "" : " — \(commit.prefix(80))"
                    out.append("[\(branch)] \(snap.workspacePath)\(shortCommit)")
                } else {
                    out.append("snapshot \(hit.id) (score \(String(format: "%.3f", hit.score)))")
                }
            }
            return out
        } catch {
            Log.debug("Local VectorSearch failed (omitting section): \(error)")
            return []
        }
    }

    private func buildSystemPrompt(snapshot: ContextSnapshot?,
                                   prefs: UserPrefs,
                                   related: [IthurielClient.RelatedSnapshot] = [],
                                   localNeighbours: [String] = []) -> String {
        var s = """
        You are Ithuriel — a macOS computer-use agent that lives in the menu
        bar and acts as a real collaborator, not a silent script runner. You
        have full context on the user's active project and full control of
        their Mac through the provided tools.

        ## Voice — talk like a person

        The user reads your `say` messages live on screen. Sound like a
        thoughtful friend pair-programming with them, not a status console.

          - Use first person, contractions, plain words. "I'll start by…",
            "Found it — looks like…", "One sec, reading the config…".
          - Always narrate *before* you act with a one-sentence `say` call
            explaining what you're about to do and why.
          - When you discover something interesting or surprising, say so
            in plain English before deciding what to do next.
          - When something fails, explain what broke and what you'll try
            instead — don't just retry silently.
          - Keep `say` messages short: one sentence, ideally under 90 chars.
            They appear as the headline of the prompt, not a paragraph.
          - Never repeat the user's task back at them. Never say "Sure!" or
            "Of course!" or "Certainly!". Just start working.

        ## How to work (Claude-style task flow)

          1. Read the request once. If anything is genuinely ambiguous and
             would change your approach, `say` your interpretation in one
             line and proceed with the most-likely reading. Don't ask
             permission for obvious work.
          2. Make a brief plan in your head (2–4 steps for non-trivial work).
             You don't need to dump the plan unless it's complex.
          3. Narrate the first step with `say`, then execute. Tool result
             comes back; if interesting, narrate the takeaway with `say`
             before the next step.
          4. Prefer reading + editing files directly over driving the GUI.
             Use `read_file` / `write_file` / `run_shell` whenever you can.
             Only fall back to `click` / `type` / `press_keys` for things
             the user must see happen visually (browsers, focused apps).
          5. When you're done, call `done` with a one-sentence summary
             ("Fixed the off-by-one in chunkSize and re-ran the tests —
             all 47 pass."). This becomes the user's at-a-glance result.

        \(relatedContextBlock(related))## Hard rules

          - File paths under .env, .ssh/, secrets/, and private/ are refused.
          - \(prefs.restrictToWorkspace
              ? "File operations are restricted to the active workspace."
              : "File operations may use any path on this Mac (except blocked secret paths).")
          - Shell commands run in the user's login zsh with full environment.
          - If a screenshot would help you decide what to do, call
            `screenshot` first.
          - Never narrate a tool call in `say` AFTER you've already made it
            (the action is visible in the transcript); narrate it BEFORE so
            the user knows what to expect.
        """

        if let snap = snapshot {
            s += "\n\nActive workspace: \(snap.workspacePath)"
            if let g = snap.gitState {
                s += "\nGit branch: \(g.branch). Last commit: \(g.lastCommit)."
                if !g.changedFiles.isEmpty {
                    s += "\nUncommitted files: \(g.changedFiles.prefix(8).joined(separator: ", "))"
                }
            }
            if !snap.recentEdits.isEmpty {
                let names = snap.recentEdits.prefix(5).map { ($0.path as NSString).lastPathComponent }
                s += "\nRecently edited: \(names.joined(separator: ", "))"
            }
            if !snap.terminalHistory.isEmpty {
                s += "\nRecent terminal commands: \(snap.terminalHistory.suffix(5).joined(separator: " | "))"
            }
        } else {
            s += "\n\n(No workspace context yet — capture is still warming up.)"
        }

        if !localNeighbours.isEmpty {
            s += "\n\nRelated past snapshots:"
            for line in localNeighbours.prefix(3) {
                s += "\n  - \(line)"
            }
        }

        return s
    }

    /// Renders the RAG block injected into the system prompt. Returns an
    /// empty string when there's nothing useful to show, which collapses
    /// cleanly into the surrounding template.
    private func relatedContextBlock(_ related: [IthurielClient.RelatedSnapshot]) -> String {
        let usable = related.prefix(5).filter { $0.summaryMedium != nil || $0.summaryShort != nil }
        guard !usable.isEmpty else { return "" }
        let iso = ISO8601DateFormatter()
        var lines: [String] = []
        for item in usable {
            let summary = item.summaryMedium ?? item.summaryShort ?? ""
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let capped = trimmed.count > 280 ? String(trimmed.prefix(280)) : trimmed
            let branch = item.gitBranch ?? "?"
            let date = item.capturedAt.map { iso.string(from: $0) } ?? "?"
            lines.append("  - [\(branch) @ \(date)] \(capped)")
        }
        guard !lines.isEmpty else { return "" }
        var s = "## Related context from past sessions\n\n"
        s += "The user has worked on this project before. Here's what they were doing\n"
        s += "in past snapshots most relevant to today's task — use this background if\n"
        s += "it helps; ignore if not relevant.\n\n"
        s += lines.joined(separator: "\n")
        s += "\n\n"
        return s
    }

    // MARK: - Dispatch

    private func dispatch(call: GeminiClient.Part.FunctionCall, prefs: UserPrefs) async -> String {
        do {
            switch call.name {
            case "say":
                // Plain-English narration. Surfaces as the Spotlight headline
                // so the user reads what the agent is thinking in real time.
                let message = call.args["message"]?.stringValue ?? ""
                let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    AgentStatusBus.shared.publish(.said(message: trimmed))
                }
                return "ok"
            case "type":
                let text = call.args["text"]?.stringValue ?? ""
                try await AgentController.shared.type(text)
                return "ok"
            case "press_keys":
                let keys = (call.args["keys"]?.arrayValue ?? []).compactMap { $0.stringValue }
                try await AgentController.shared.pressKeys(keys)
                return "ok"
            case "click":
                let x = CGFloat(call.args["x"]?.numberValue ?? 0)
                let y = CGFloat(call.args["y"]?.numberValue ?? 0)
                try await AgentController.shared.click(x: x, y: y)
                return "ok"
            case "move_cursor":
                let x = CGFloat(call.args["x"]?.numberValue ?? 0)
                let y = CGFloat(call.args["y"]?.numberValue ?? 0)
                try await AgentController.shared.moveCursor(x: x, y: y)
                return "ok"
            case "screenshot":
                let b64 = try await AgentController.shared.screenshot()
                return "screenshot captured (\(b64.count) base64 chars) — describe what you see and act on it"
            case "focus_app":
                let id = call.args["bundle_id"]?.stringValue ?? ""
                try await AgentController.shared.focus(bundleId: id)
                return "ok"
            case "launch_app":
                let id = call.args["bundle_id"]?.stringValue ?? ""
                try await AgentController.shared.launch(bundleId: id)
                return "ok"
            case "quit_app":
                let id = call.args["bundle_id"]?.stringValue ?? ""
                try await AgentController.shared.quit(bundleId: id, prefs: prefs)
                return "ok"
            case "read_file":
                let path = call.args["path"]?.stringValue ?? ""
                return try await AgentController.shared.readFile(path, prefs: prefs)
            case "write_file":
                let path = call.args["path"]?.stringValue ?? ""
                let content = call.args["content"]?.stringValue ?? ""
                try await AgentController.shared.writeFile(path, content: content, prefs: prefs)
                return "ok"
            case "delete_file":
                let path = call.args["path"]?.stringValue ?? ""
                try await AgentController.shared.deleteFile(path, prefs: prefs)
                return "ok"
            case "run_shell":
                let cmd = call.args["command"]?.stringValue ?? ""
                return try await AgentController.shared.runShell(cmd, prefs: prefs)
            default:
                return "error: unknown tool \(call.name)"
            }
        } catch {
            return "error: \(error)"
        }
    }
}

/// Function declarations advertised to Gemini.
enum AgentTools {
    static let declarations: [GeminiClient.Tool] = [
        GeminiClient.Tool(functionDeclarations: [
            decl("say", "Narrate to the user in plain English what you're about to do or what you just discovered. Always call this BEFORE your next tool call. Keep it to one short sentence (<90 chars).",
                 ["message": .string("one short, conversational sentence")]),
            decl("type", "Type literal text at the current cursor position.",
                 ["text": .string("text to type")]),
            decl("press_keys", "Press a keyboard chord like ['cmd','c'] or ['cmd','shift','p'].",
                 ["keys": .stringArray("ordered list of keys; modifiers first, main key last")]),
            decl("click", "Mouse click at global screen coordinates (x, y).",
                 ["x": .number("x in screen pts"), "y": .number("y in screen pts")]),
            decl("move_cursor", "Move the mouse cursor to (x, y).",
                 ["x": .number("x"), "y": .number("y")]),
            decl("screenshot", "Take a screenshot of the main display. Returns base64 JPEG.",
                 [:]),
            decl("focus_app", "Bring an app to the front by bundle identifier.",
                 ["bundle_id": .string("e.g. com.apple.Terminal")]),
            decl("launch_app", "Launch an app by bundle identifier.",
                 ["bundle_id": .string("bundle id")]),
            decl("read_file", "Read a UTF-8 file (absolute or ~ path).",
                 ["path": .string("absolute or workspace-relative path")]),
            decl("write_file", "Write/overwrite a UTF-8 file.",
                 ["path": .string("path"), "content": .string("full file contents")]),
            decl("delete_file", "Delete a file.",
                 ["path": .string("path")]),
            decl("run_shell", "Run a zsh login-shell command. Returns stdout+stderr and exit code on failure.",
                 ["command": .string("shell command")]),
            decl("quit_app", "Quit an app by bundle identifier.",
                 ["bundle_id": .string("bundle id")]),
            decl("done", "Signal task complete with a one-line summary.",
                 ["summary": .string("what you accomplished")])
        ])
    ]

    private enum ParamKind {
        case string(String)
        case number(String)
        case stringArray(String)
    }

    private static func decl(_ name: String, _ desc: String, _ params: [String: ParamKind]) -> GeminiClient.FunctionDeclaration {
        var properties: [String: GeminiClient.Schema] = [:]
        var required: [String] = []
        for (key, kind) in params {
            switch kind {
            case .string(let d):
                properties[key] = .init(type: "STRING", properties: nil, items: nil, required: nil, description: d)
            case .number(let d):
                properties[key] = .init(type: "NUMBER", properties: nil, items: nil, required: nil, description: d)
            case .stringArray(let d):
                let inner = GeminiClient.Schema(type: "STRING", properties: nil, items: nil, required: nil, description: nil)
                properties[key] = .init(type: "ARRAY", properties: nil,
                                        items: GeminiClient.SchemaBox(inner),
                                        required: nil, description: d)
            }
            required.append(key)
        }
        let schema = GeminiClient.Schema(type: "OBJECT",
                                         properties: properties.isEmpty ? nil : properties,
                                         items: nil,
                                         required: required.isEmpty ? nil : required,
                                         description: nil)
        return GeminiClient.FunctionDeclaration(name: name, description: desc, parameters: schema)
    }
}
