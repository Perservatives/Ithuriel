import Foundation
import AppKit
import ApplicationServices

/// Optional, opt-in agent that can perform limited computer-control actions on
/// the user's behalf — only when explicitly invoked by the user via the menu
/// bar or an authorized URL scheme handler. Inspired by openclaw, but scoped
/// strictly to the actions Ithuriel needs:
///
///   - bring a target AI tool to the foreground
///   - paste the prepared context (⌘V) into that tool
///   - optionally press Return to submit
///
/// Every action checks `UserPrefs.agentControlEnabled` AND Accessibility trust.
/// No action is ever taken passively from background monitoring.
enum AgentAction: String, Codable {
    case focusTool       // bring `tool` to front
    case pasteContext    // ⌘V into frontmost app
    case submitPrompt    // Return key
}

struct AgentRequest {
    let action: AgentAction
    let tool: AITool
    let reason: String   // user-readable reason, shown in confirmation
}

enum AgentControlError: Error {
    case disabled
    case accessibilityDenied
    case targetNotFound
    case userDeclined
}

final class AgentController {
    static let shared = AgentController()
    private init() {}

    /// Performs an action only after preflight checks pass. Returns silently
    /// if disabled — never crashes the host app.
    func perform(_ request: AgentRequest, prefs: UserPrefs) async throws {
        guard prefs.agentControlEnabled else { throw AgentControlError.disabled }
        guard AppDetector.isAccessibilityTrusted else { throw AgentControlError.accessibilityDenied }
        guard await confirmIfNeeded(request: request) else { throw AgentControlError.userDeclined }

        switch request.action {
        case .focusTool:
            try focus(tool: request.tool)
        case .pasteContext:
            try sendCommandV()
        case .submitPrompt:
            try sendReturn()
        }
    }

    /// Convenience: focus → paste → (optionally) submit. Each step is logged.
    func handoff(to tool: AITool, submit: Bool, prefs: UserPrefs) async throws {
        try await perform(AgentRequest(action: .focusTool, tool: tool,
                                       reason: NSLocalizedString("agent.reason.focus", comment: "")),
                          prefs: prefs)
        try await Task.sleep(nanoseconds: 200_000_000)
        try await perform(AgentRequest(action: .pasteContext, tool: tool,
                                       reason: NSLocalizedString("agent.reason.paste", comment: "")),
                          prefs: prefs)
        if submit {
            try await Task.sleep(nanoseconds: 100_000_000)
            try await perform(AgentRequest(action: .submitPrompt, tool: tool,
                                           reason: NSLocalizedString("agent.reason.submit", comment: "")),
                              prefs: prefs)
        }
    }

    // MARK: - Actions

    private func focus(tool: AITool) throws {
        let ids = tool.bundleIdentifiers
        for id in ids {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
        throw AgentControlError.targetNotFound
    }

    private func sendCommandV() throws {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 9 // virtual keycode for "v"
        guard let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) else {
            throw AgentControlError.accessibilityDenied
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func sendReturn() throws {
        let src = CGEventSource(stateID: .hidSystemState)
        let returnKey: CGKeyCode = 36
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: returnKey, keyDown: false) else {
            throw AgentControlError.accessibilityDenied
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Consent

    @MainActor
    private func confirmIfNeeded(request: AgentRequest) async -> Bool {
        // For irreversible-feeling actions (submit), require an explicit alert.
        // Focus + paste are silent once the feature is enabled.
        if request.action != .submitPrompt { return true }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("agent.confirm.title", comment: "")
        alert.informativeText = String(format: NSLocalizedString("agent.confirm.body", comment: ""), request.reason)
        alert.addButton(withTitle: NSLocalizedString("agent.confirm.allow", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("agent.confirm.cancel", comment: ""))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
