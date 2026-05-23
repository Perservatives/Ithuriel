import Foundation

/// LLM-assisted intent gate that sits in front of `AgentLoop.run`. Catches the
/// long tail of casual messages that the regex-only `ConversationalTurn` would
/// otherwise route into a 100-step computer-use loop (typos like "hellow",
/// "wsup", "helo", random questions, etc.).
///
/// Order of decision:
///   1. If `ConversationalTurn.matches` says yes, trust it (cheap, sync).
///   2. If the input is obviously long enough to be a task (>240 chars), skip
///      the LLM and let the agent run.
///   3. Otherwise, ask the cheapest fast Gemini model for a one-shot
///      classification. Failures fall back to `.task` so we never accidentally
///      eat a real instruction.
@MainActor
enum IntentClassifier {
    enum Kind { case conversational, task }

    static func classify(_ input: String, prefs: UserPrefs) async -> Kind {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .conversational }

        // Fast path: existing regex says yes? trust it.
        if ConversationalTurn.matches(trimmed) { return .conversational }

        // Skip the LLM round-trip when the input is obviously a task.
        if trimmed.count > 240 { return .task }

        // No key — fall back to the conservative "treat as task" default.
        guard !prefs.geminiApiKey.isEmpty else { return .task }

        let client = GeminiClient(apiKey: prefs.geminiApiKey, model: "gemini-2.0-flash")
        let system = """
        Classify the user message as exactly one JSON object:
          {"kind":"conversational"}  if it's small talk, greetings, typos like 'hellow' or 'wsup', or any question that doesn't ask you to do something on their computer.
          {"kind":"task"}            if it's an instruction to act on the computer (edit a file, run a command, open an app, fix code, etc.).
        Reply with ONLY the JSON object, no prose.
        """

        do {
            let content: [GeminiClient.Content] = [
                .init(role: "user", parts: [.init(text: trimmed)])
            ]
            let resp = try await client.step(contents: content, tools: [], system: system)
            let text = resp.parts.compactMap(\.text).joined()
            if let data = text.data(using: .utf8),
               let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               obj["kind"] == "conversational" {
                return .conversational
            }
        } catch {
            Log.info("[intent] classifier failed, defaulting to task: \(error)")
        }
        return .task
    }
}
