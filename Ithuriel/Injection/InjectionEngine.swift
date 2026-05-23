import Foundation
import AppKit
import UserNotifications

final class InjectionEngine {
    static let shared = InjectionEngine()
    private init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Writes formatted context to the system pasteboard and posts a notification.
    func primaryInject(text: String, target: AITool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        notify(title: NSLocalizedString("inject.ready.title", comment: "Notification title"),
               body: String(format: NSLocalizedString("inject.ready.body", comment: "Notification body"), target.rawValue))
        Log.info("Context injected to clipboard for \(target.rawValue) (\(text.count) chars)")
    }

    /// Simulates keystrokes to paste text directly. Allowlisted apps only.
    func typeInject(text: String) {
        guard AppDetector.isAccessibilityTrusted else {
            Log.info("Type-inject skipped: Accessibility not granted")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var utf16 = Array(String(scalar).utf16)
            if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyDown.post(tap: .cghidEventTap)
            }
            if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

/// Tool-specific formatting for injected context.
enum ContextFormatter {
    static func format(snapshot: ContextSnapshot, for tool: AITool) -> String {
        switch tool {
        case .claudeCodeTerminal, .claudeDesktop:
            return claudeMd(snapshot)
        case .cursor, .copilotChat:
            return cursorRules(snapshot)
        case .chatgpt, .gemini, .unknown:
            return systemMessage(snapshot)
        }
    }

    private static func claudeMd(_ s: ContextSnapshot) -> String {
        var out = "# Project context\n\n"
        out += "Workspace: \(s.workspacePath)\n"
        if let g = s.gitState {
            out += "Branch: \(g.branch)\n"
            out += "Last commit: \(g.lastCommit)\n"
            if !g.changedFiles.isEmpty {
                out += "Changed files:\n"
                for f in g.changedFiles.prefix(10) { out += "  - \(f)\n" }
            }
        }
        if !s.recentEdits.isEmpty {
            out += "\nRecent edits:\n"
            for e in s.recentEdits.prefix(10) { out += "  - \(e.path)\n" }
        }
        if !s.terminalHistory.isEmpty {
            out += "\nRecent terminal commands:\n"
            for c in s.terminalHistory.prefix(10) { out += "  $ \(c)\n" }
        }
        return out
    }

    private static func cursorRules(_ s: ContextSnapshot) -> String {
        var out = "You are working in: \(s.workspacePath)\n"
        if let g = s.gitState { out += "Active branch: \(g.branch). Changes in progress: \(g.changedFiles.count) files.\n" }
        if !s.recentEdits.isEmpty {
            out += "Recently edited: " + s.recentEdits.prefix(5).map { ($0.path as NSString).lastPathComponent }.joined(separator: ", ") + "\n"
        }
        return out
    }

    private static func systemMessage(_ s: ContextSnapshot) -> String {
        var out = "I am working on \(s.workspacePath). "
        if let g = s.gitState {
            out += "On branch \(g.branch) with \(g.changedFiles.count) uncommitted files. "
        }
        if !s.recentEdits.isEmpty {
            out += "Recently edited: " + s.recentEdits.prefix(3).map { ($0.path as NSString).lastPathComponent }.joined(separator: ", ") + ". "
        }
        return out
    }
}
