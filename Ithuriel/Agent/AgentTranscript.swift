import Foundation
import SwiftUI

/// Prefix convention for agent run transcripts (StatusBar, Spotlight, Chat).
/// UI maps each prefix to icon, color, and title/detail layout.
enum AgentTranscript {
    static let taskPrefix = "▶"
    static let thinkingPrefix = "·"
    static let actionPrefix = "→"
    static let donePrefix = "✓"
    static let errorPrefix = "✗"
    static let stoppedPrefix = "■"
    static let progressPrefix = "◌"
    /// Plain assistant chat reply (no "Finished:" wrapper).
    static let replyPrefix = "«"

    private static let outcomeSeparator = " — "

    // MARK: - Lines written by AgentLoop

    static func lineTaskStarted(_ task: String) -> String {
        "\(taskPrefix) \(String(format: NSLocalizedString("agent.transcript.task", comment: ""), task))"
    }

    static func lineThinking(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmed.count > 280 ? String(trimmed.prefix(277)) + "…" : trimmed
        return "\(thinkingPrefix) \(preview)"
    }

    static func lineReply(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmed.count > 4000 ? String(trimmed.prefix(3997)) + "…" : trimmed
        return "\(replyPrefix) \(preview)"
    }

    static func lineAction(name: String, args: [String: AnyJSON], result: String) -> String {
        let title = actionTitle(name: name, args: args)
        let outcome = outcomePhrase(result)
        return "\(actionPrefix) \(title)\(outcomeSeparator)\(outcome)"
    }

    static func lineDone(_ summary: String) -> String {
        "\(donePrefix) \(String(format: NSLocalizedString("agent.transcript.done", comment: ""), summary))"
    }

    static func lineGeminiError(_ error: String) -> String {
        "\(errorPrefix) \(String(format: NSLocalizedString("agent.transcript.geminiError", comment: ""), error))"
    }

    static func lineKilled() -> String {
        "\(stoppedPrefix) \(NSLocalizedString("agent.transcript.killed", comment: ""))"
    }

    static func lineStopRequested() -> String {
        "\(stoppedPrefix) \(NSLocalizedString("agent.transcript.stopRequested", comment: ""))"
    }

    static func lineStepComplete(step: Int, maxSteps: Int) -> String {
        "\(progressPrefix) \(String(format: NSLocalizedString("agent.transcript.stepComplete", comment: ""), step, maxSteps))"
    }

    static func lineNoToolCalls() -> String {
        "\(progressPrefix) \(NSLocalizedString("agent.transcript.noToolCalls", comment: ""))"
    }

    static func lineStepBudgetExhausted(maxSteps: Int) -> String {
        "\(progressPrefix) \(String(format: NSLocalizedString("agent.transcript.stepBudget", comment: ""), maxSteps))"
    }

    // MARK: - UI presentation

    enum Kind {
        case task, thinking, action, done, error, stopped, progress, reply, plain
    }

    struct Presentation {
        let symbol: String
        let title: String
        let detail: String?
        let kind: Kind
    }

    static func present(_ line: String) -> Presentation {
        let rest = dropKnownPrefix(line).trimmingCharacters(in: .whitespaces)
        if line.hasPrefix(taskPrefix) {
            return .init(symbol: taskPrefix, title: rest, detail: nil, kind: .task)
        }
        if line.hasPrefix(thinkingPrefix) {
            return .init(symbol: thinkingPrefix, title: rest, detail: nil, kind: .thinking)
        }
        if line.hasPrefix(actionPrefix) {
            let split = splitOutcome(rest)
            return .init(symbol: actionPrefix, title: split.title, detail: split.detail, kind: .action)
        }
        if line.hasPrefix(donePrefix) {
            return .init(symbol: donePrefix, title: rest, detail: nil, kind: .done)
        }
        if line.hasPrefix(errorPrefix) {
            return .init(symbol: errorPrefix, title: rest, detail: nil, kind: .error)
        }
        if line.hasPrefix(stoppedPrefix) {
            return .init(symbol: stoppedPrefix, title: rest, detail: nil, kind: .stopped)
        }
        if line.hasPrefix(progressPrefix) {
            return .init(symbol: progressPrefix, title: rest, detail: nil, kind: .progress)
        }
        if line.hasPrefix(replyPrefix) {
            return .init(symbol: replyPrefix, title: rest, detail: nil, kind: .reply)
        }
        return .init(symbol: " ", title: line, detail: nil, kind: .plain)
    }

    static func tint(for kind: Kind) -> Color {
        switch kind {
        case .task:      return .accentColor
        case .thinking:  return .secondary
        case .action:    return .blue
        case .done:      return .green
        case .error:     return .red
        case .stopped:   return .orange
        case .progress:  return .secondary
        case .reply:     return .primary
        case .plain:     return .secondary
        }
    }

    // MARK: - Private

    private static func dropKnownPrefix(_ line: String) -> String {
        guard let first = line.first else { return line }
        let known: Set<Character> = [Character(taskPrefix), Character(thinkingPrefix), Character(actionPrefix),
                                     Character(donePrefix), Character(errorPrefix), Character(stoppedPrefix),
                                     Character(progressPrefix), Character(replyPrefix)]
        if known.contains(first) {
            return String(line.dropFirst())
        }
        return line
    }

    private static func splitOutcome(_ rest: String) -> (title: String, detail: String?) {
        guard let range = rest.range(of: outcomeSeparator) else {
            return (rest, nil)
        }
        let title = String(rest[..<range.lowerBound])
        let detail = String(rest[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (title, detail.isEmpty ? nil : detail)
    }

    private static func actionTitle(name: String, args: [String: AnyJSON]) -> String {
        switch name {
        case "type":
            let text = args["text"]?.stringValue ?? ""
            let preview = text.count > 48 ? String(text.prefix(45)) + "…" : text
            return String(format: NSLocalizedString("agent.transcript.action.type", comment: ""), preview)
        case "press_keys":
            let keys = (args["keys"]?.arrayValue ?? []).compactMap { $0.stringValue }
            let chord = keys.map { displayKey($0) }.joined(separator: "+")
            return String(format: NSLocalizedString("agent.transcript.action.pressKeys", comment: ""), chord)
        case "click":
            let x = Int(args["x"]?.numberValue ?? 0)
            let y = Int(args["y"]?.numberValue ?? 0)
            return String(format: NSLocalizedString("agent.transcript.action.click", comment: ""), x, y)
        case "move_cursor":
            let x = Int(args["x"]?.numberValue ?? 0)
            let y = Int(args["y"]?.numberValue ?? 0)
            return String(format: NSLocalizedString("agent.transcript.action.moveCursor", comment: ""), x, y)
        case "screenshot":
            return NSLocalizedString("agent.transcript.action.screenshot", comment: "")
        case "focus_app":
            return String(format: NSLocalizedString("agent.transcript.action.focusApp", comment: ""),
                          displayBundle(args["bundle_id"]?.stringValue ?? ""))
        case "launch_app":
            return String(format: NSLocalizedString("agent.transcript.action.launchApp", comment: ""),
                          displayBundle(args["bundle_id"]?.stringValue ?? ""))
        case "quit_app":
            return String(format: NSLocalizedString("agent.transcript.action.quitApp", comment: ""),
                          displayBundle(args["bundle_id"]?.stringValue ?? ""))
        case "read_file":
            return String(format: NSLocalizedString("agent.transcript.action.readFile", comment: ""),
                          shortPath(args["path"]?.stringValue ?? ""))
        case "write_file":
            return String(format: NSLocalizedString("agent.transcript.action.writeFile", comment: ""),
                          shortPath(args["path"]?.stringValue ?? ""))
        case "delete_file":
            return String(format: NSLocalizedString("agent.transcript.action.deleteFile", comment: ""),
                          shortPath(args["path"]?.stringValue ?? ""))
        case "run_shell":
            let cmd = args["command"]?.stringValue ?? ""
            let preview = cmd.count > 72 ? String(cmd.prefix(69)) + "…" : cmd
            return String(format: NSLocalizedString("agent.transcript.action.runShell", comment: ""), preview)
        default:
            return String(format: NSLocalizedString("agent.transcript.action.unknown", comment: ""), name)
        }
    }

    private static func outcomePhrase(_ result: String) -> String {
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "ok" {
            return NSLocalizedString("agent.transcript.outcome.ok", comment: "")
        }
        if trimmed.lowercased().hasPrefix("error:") {
            return trimmed
        }
        if trimmed.lowercased().contains("screenshot captured") {
            return NSLocalizedString("agent.transcript.outcome.screenshot", comment: "")
        }
        if trimmed.count > 100 {
            return String(format: NSLocalizedString("agent.transcript.outcome.long", comment: ""), trimmed.count)
        }
        return trimmed
    }

    private static func shortPath(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        let expanded = (path as NSString).expandingTildeInPath
        return (expanded as NSString).lastPathComponent
    }

    private static func displayBundle(_ bundleId: String) -> String {
        guard !bundleId.isEmpty else { return bundleId }
        if let last = bundleId.split(separator: ".").last {
            return String(last)
        }
        return bundleId
    }

    private static func displayKey(_ key: String) -> String {
        switch key.lowercased() {
        case "cmd", "command": return "⌘"
        case "shift": return "⇧"
        case "alt", "option": return "⌥"
        case "ctrl", "control": return "⌃"
        case "return", "enter": return "↩"
        case "tab": return "⇥"
        case "escape", "esc": return "⎋"
        case "space": return "Space"
        case "delete": return "⌫"
        default:
            if key.count == 1 { return key.uppercased() }
            return key
        }
    }
}
