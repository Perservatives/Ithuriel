import Foundation

/// Heuristic gate for casual chat vs computer-use tasks. Only consulted when
/// `UserPrefs.agentEnabled` is true.
enum ConversationalTurn {
    private static let actionSignals = [
        "run ", "open ", "fix ", "write ", "delete ", "click", "refactor",
        "commit", "build ", "test ", "install", "create ", "update ",
        "screenshot", "terminal", "shell", "execute", "launch ", "quit ",
        "read file", "write file", "press ", "type ", "navigate", "browse",
        "download", "upload", "deploy", "debug ", "compile", "grep ",
        "find ", "search for", "look at", "check the", "in cursor",
        "in xcode", "in terminal", "folder", "directory", "workspace"
    ]

    private static let conversationalOpeners = [
        "hi", "hello", "hey", "yo", "howdy", "greetings",
        "good morning", "good afternoon", "good evening",
        "thanks", "thank you", "thx", "ty",
        "how are you", "how's it going", "how are things",
        "what's up", "whats up", "sup",
        "bye", "goodbye", "see you", "see ya",
        "who are you", "what are you", "what can you do",
        "nice to meet", "pleased to meet"
    ]

    static func matches(_ task: String) -> Bool {
        let trimmed = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.count > 220 { return false }

        let lower = trimmed.lowercased()
        if actionSignals.contains(where: { lower.contains($0) }) { return false }

        let normalized = lower
            .trimmingCharacters(in: CharacterSet(charactersIn: "!.?…"))
            .trimmingCharacters(in: .whitespaces)

        if conversationalOpeners.contains(where: { normalized == $0 || normalized.hasPrefix($0 + " ") }) {
            return true
        }

        // Short, question-shaped small talk without action verbs.
        if trimmed.count <= 80,
           trimmed.hasSuffix("?"),
           !lower.contains("file"),
           !lower.contains("code"),
           !lower.contains("app") {
            let social = ["how are", "what's up", "who are", "can you chat", "are you there"]
            if social.contains(where: { lower.contains($0) }) { return true }
        }

        return false
    }
}
