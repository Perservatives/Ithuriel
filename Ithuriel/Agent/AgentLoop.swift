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
    private let maxSteps = 25

    init(container: ModelContainer?) {
        self.container = container
    }

    func run(task userTask: String) async {
        guard !isRunning else { return }
        isRunning = true
        lastError = nil
        transcript.removeAll()
        AgentController.shared.arm()
        SoundPlayer.shared.play(.submit)
        defer { isRunning = false }

        guard let container = container else { return }
        let prefs = (try? await UserPrefs.load(in: container)) ?? UserPrefs.defaults()
        guard !prefs.geminiApiKey.isEmpty else {
            lastError = NSLocalizedString("agent.err.noKey", comment: "")
            return
        }

        let runId = UUID()
        let startedAt = Date()
        let apiClient = IthurielClient(prefs: prefs)
        let cloudSyncEnabled = !prefs.localOnly && AuthService.shared.isSignedIn
        if cloudSyncEnabled {
            try? await apiClient.postAgentRun(.init(
                id: runId, task: userTask, status: .running,
                startedAt: startedAt, finishedAt: nil,
                transcript: [], error: nil, snapshotId: nil
            ))
        }

        func uploadFinalState(_ status: AgentRunRecord.Status) async {
            guard cloudSyncEnabled else { return }
            try? await apiClient.postAgentRun(.init(
                id: runId, task: userTask, status: status,
                startedAt: startedAt, finishedAt: Date(),
                transcript: transcript, error: lastError, snapshotId: nil
            ))
        }

        let client = GeminiClient(apiKey: prefs.geminiApiKey)
        let tools = AgentTools.declarations
        let snapshot = await CachedSnapshot.latest(in: container)
        let systemPrompt = buildSystemPrompt(snapshot: snapshot, prefs: prefs)

        var convo: [GeminiClient.Content] = [
            .init(role: "user", parts: [.init(text: userTask, inlineData: nil, functionCall: nil, functionResponse: nil)])
        ]
        log("▶ task: \(userTask)")

        for step in 1...maxSteps {
            if AgentController.shared.killed {
                log("■ killed by user")
                await uploadFinalState(.killed)
                return
            }
            let modelTurn: GeminiClient.Content
            do {
                modelTurn = try await client.step(contents: convo, tools: tools, system: systemPrompt)
            } catch {
                lastError = "\(error)"
                log("✗ gemini error: \(error)")
                await uploadFinalState(.failed)
                return
            }
            convo.append(modelTurn)

            var functionResponses: [GeminiClient.Part] = []
            var sawDone = false

            for part in modelTurn.parts {
                if let text = part.text, !text.isEmpty {
                    log("· \(text)")
                }
                guard let call = part.functionCall else { continue }
                if call.name == "done" {
                    sawDone = true
                    let summary = call.args["summary"]?.stringValue ?? "done"
                    log("✓ \(summary)")
                    SoundPlayer.shared.play(.done)
                    continue
                }
                let result = await dispatch(call: call, prefs: prefs)
                log("→ \(call.name): \(result.prefix(120))")
                SoundPlayer.shared.play(.tool, volume: 0.4)
                let resp = GeminiClient.Part(
                    text: nil,
                    inlineData: nil,
                    functionCall: nil,
                    functionResponse: GeminiClient.Part.FunctionResponse(
                        name: call.name,
                        response: ["result": .string(result)]
                    )
                )
                functionResponses.append(resp)
            }

            if sawDone {
                await uploadFinalState(.completed)
                return
            }
            if functionResponses.isEmpty {
                log("(no tool calls — ending loop)")
                await uploadFinalState(.completed)
                return
            }
            convo.append(.init(role: "function", parts: functionResponses))
            log("step \(step)/\(maxSteps) complete")
        }

        log("◌ step budget exhausted")
        await uploadFinalState(.failed)
    }

    func stop() {
        AgentController.shared.kill()
        log("■ stop requested")
    }

    private func log(_ line: String) {
        transcript.append(line)
        Log.info("[agent] \(line)")
    }

    private func buildSystemPrompt(snapshot: ContextSnapshot?, prefs: UserPrefs) -> String {
        var s = """
        You are Ithuriel, a macOS computer-use agent with full project context.
        Use the provided tools to accomplish the user's task. Prefer keyboard
        shortcuts and direct file edits over GUI clicks when possible. When a
        task is complete, call the `done` function with a one-line summary.

        Hard rules:
          - File operations are sandboxed to the active workspace.
          - Destructive actions (write_file, delete_file, run_shell, quit_app)
            will prompt the user — that is expected, do not be deterred.
          - If a screenshot would help, call `screenshot` first.
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

        return s
    }

    // MARK: - Dispatch

    private func dispatch(call: GeminiClient.Part.FunctionCall, prefs: UserPrefs) async -> String {
        do {
            switch call.name {
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
            decl("quit_app", "Quit an app by bundle identifier. Destructive — user will confirm.",
                 ["bundle_id": .string("bundle id")]),
            decl("read_file", "Read a UTF-8 file inside the workspace sandbox.",
                 ["path": .string("absolute or workspace-relative path")]),
            decl("write_file", "Write/overwrite a UTF-8 file. Destructive — user will confirm.",
                 ["path": .string("path"), "content": .string("full file contents")]),
            decl("delete_file", "Delete a file. Destructive — user will confirm.",
                 ["path": .string("path")]),
            decl("run_shell", "Run a zsh command. Destructive — user will confirm. Returns stdout+stderr.",
                 ["command": .string("shell command")]),
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
