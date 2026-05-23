import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Full computer-use action surface. Inspired by openclaw — type, click,
/// take screenshots, launch apps, read/write files. The agent loop in
/// `Agent/AgentLoop.swift` drives this controller in response to Gemini's
/// function calls.
///
/// Non-destructive actions (type, click, keypress, screenshot, focus,
/// read_file) run silently when the agent is enabled.
///
/// Destructive actions (write_file, delete_file, run_shell, quit_app)
/// always require an NSAlert confirmation, regardless of settings.
enum AgentControlError: Error, CustomStringConvertible {
    case disabled
    case accessibilityDenied
    case targetNotFound(String)
    case userDeclined
    case fileOutsideSandbox(String)
    case ioFailure(String)

    var description: String {
        switch self {
        case .disabled: return "Agent is disabled."
        case .accessibilityDenied: return "Accessibility permission required."
        case .targetNotFound(let s): return "Target not found: \(s)"
        case .userDeclined: return "User declined the action."
        case .fileOutsideSandbox(let p): return "File path outside workspace sandbox: \(p)"
        case .ioFailure(let s): return "I/O failure: \(s)"
        }
    }
}

final class AgentController {
    static let shared = AgentController()
    private init() {}

    /// Killed by the kill-switch hotkey or a stop button. AgentLoop checks
    /// this after every step.
    @MainActor private(set) var killed: Bool = false
    @MainActor func arm()  { killed = false }
    @MainActor func kill() { killed = true }

    // MARK: - Keyboard

    /// Type arbitrary Unicode text via the HID event tap.
    func type(_ text: String) async throws {
        try preflightNonDestructive()
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var utf16 = Array(String(scalar).utf16)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                up.post(tap: .cghidEventTap)
            }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// Send a chord like ["cmd", "shift", "p"].
    func pressKeys(_ keys: [String]) async throws {
        try preflightNonDestructive()
        guard let mainKey = keys.last else { return }
        let modifiers = keys.dropLast()
        let flags = modifierFlags(from: Array(modifiers))
        guard let keyCode = virtualKeyCode(for: mainKey) else {
            throw AgentControlError.targetNotFound("key \(mainKey)")
        }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else {
            throw AgentControlError.accessibilityDenied
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Mouse

    func click(x: CGFloat, y: CGFloat, button: CGMouseButton = .left) async throws {
        try preflightNonDestructive()
        let src = CGEventSource(stateID: .hidSystemState)
        let point = CGPoint(x: x, y: y)
        let downType: CGEventType = (button == .left) ? .leftMouseDown : .rightMouseDown
        let upType:   CGEventType = (button == .left) ? .leftMouseUp   : .rightMouseUp
        guard let down = CGEvent(mouseEventSource: src, mouseType: downType, mouseCursorPosition: point, mouseButton: button),
              let up   = CGEvent(mouseEventSource: src, mouseType: upType,   mouseCursorPosition: point, mouseButton: button) else {
            throw AgentControlError.accessibilityDenied
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func moveCursor(x: CGFloat, y: CGFloat) async throws {
        try preflightNonDestructive()
        let src = CGEventSource(stateID: .hidSystemState)
        if let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                              mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Apps

    func focus(bundleId: String) async throws {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first {
            app.activate(options: [.activateAllWindows])
            return
        }
        try await launch(bundleId: bundleId)
    }

    func launch(bundleId: String) async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            throw AgentControlError.targetNotFound(bundleId)
        }
        let cfg = NSWorkspace.OpenConfiguration()
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: cfg)
    }

    func quit(bundleId: String, prefs: UserPrefs) async throws {
        try await confirmDestructive(
            title: NSLocalizedString("agent.confirm.quit.title", comment: ""),
            body: String(format: NSLocalizedString("agent.confirm.quit.body", comment: ""), bundleId),
            prefs: prefs
        )
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            throw AgentControlError.targetNotFound(bundleId)
        }
        app.terminate()
    }

    // MARK: - Screenshot

    /// Returns base64 JPEG of the main display.
    func screenshot() async throws -> String {
        try preflightNonDestructive()
        guard let b64 = ScreenCapture.mainDisplayJPEGBase64() else {
            throw AgentControlError.ioFailure("screen capture failed")
        }
        return b64
    }

    // MARK: - Files (sandboxed to current workspace)

    func readFile(_ path: String, prefs: UserPrefs) async throws -> String {
        try preflightNonDestructive()
        let resolved = try sandbox(path: path, prefs: prefs)
        do { return try String(contentsOf: resolved, encoding: .utf8) }
        catch { throw AgentControlError.ioFailure("\(error)") }
    }

    func writeFile(_ path: String, content: String, prefs: UserPrefs) async throws {
        try await confirmDestructive(
            title: NSLocalizedString("agent.confirm.write.title", comment: ""),
            body: String(format: NSLocalizedString("agent.confirm.write.body", comment: ""), path),
            prefs: prefs
        )
        let resolved = try sandbox(path: path, prefs: prefs)
        do {
            try FileManager.default.createDirectory(at: resolved.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try content.write(to: resolved, atomically: true, encoding: .utf8)
        } catch {
            throw AgentControlError.ioFailure("\(error)")
        }
    }

    func deleteFile(_ path: String, prefs: UserPrefs) async throws {
        try await confirmDestructive(
            title: NSLocalizedString("agent.confirm.delete.title", comment: ""),
            body: String(format: NSLocalizedString("agent.confirm.delete.body", comment: ""), path),
            prefs: prefs
        )
        let resolved = try sandbox(path: path, prefs: prefs)
        do { try FileManager.default.removeItem(at: resolved) }
        catch { throw AgentControlError.ioFailure("\(error)") }
    }

    // MARK: - Shell

    func runShell(_ command: String, prefs: UserPrefs) async throws -> String {
        try await confirmDestructive(
            title: NSLocalizedString("agent.confirm.shell.title", comment: ""),
            body: String(format: NSLocalizedString("agent.confirm.shell.body", comment: ""), command),
            prefs: prefs
        )
        return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.launchPath = "/bin/zsh"
                p.arguments = ["-lc", command]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch {
                    cont.resume(returning: "launch failed: \(error)")
                    return
                }
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
            }
        }
    }

    // MARK: - Helpers

    private func preflightNonDestructive() throws {
        guard AppDetector.isAccessibilityTrusted else { throw AgentControlError.accessibilityDenied }
    }

    private func sandbox(path: String, prefs: UserPrefs) throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        let workspace = URL(fileURLWithPath: prefs.activeWorkspace.isEmpty
                            ? FileManager.default.homeDirectoryForCurrentUser.path
                            : prefs.activeWorkspace).standardizedFileURL
        if !url.path.hasPrefix(workspace.path) {
            throw AgentControlError.fileOutsideSandbox(url.path)
        }
        if Redactor.isSensitivePath(url.path) {
            throw AgentControlError.fileOutsideSandbox(url.path)
        }
        return url
    }

    @MainActor
    private func confirmDestructive(title: String, body: String, prefs: UserPrefs) async throws {
        if prefs.confirmEveryAction == false && prefs.autoApproveSafeOnly == false {
            // Should never happen — keep the gate strict by default.
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: NSLocalizedString("agent.confirm.allow", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("agent.confirm.cancel", comment: ""))
        if alert.runModal() != .alertFirstButtonReturn {
            throw AgentControlError.userDeclined
        }
    }

    // MARK: - Key mapping

    private func modifierFlags(from mods: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for m in mods.map({ $0.lowercased() }) {
            switch m {
            case "cmd", "command":   flags.insert(.maskCommand)
            case "shift":            flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control":  flags.insert(.maskControl)
            case "fn":               flags.insert(.maskSecondaryFn)
            default: break
            }
        }
        return flags
    }

    private func virtualKeyCode(for key: String) -> CGKeyCode? {
        let k = key.lowercased()
        if let direct = AgentController.keyMap[k] { return direct }
        if k.count == 1, let scalar = k.unicodeScalars.first {
            return AgentController.charMap[Character(scalar)]
        }
        return nil
    }

    static let keyMap: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53, "esc": 53,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]

    static let charMap: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47
    ]
}
