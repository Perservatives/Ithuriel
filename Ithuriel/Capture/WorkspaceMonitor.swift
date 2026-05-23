import Foundation
import AppKit
import SwiftData

enum AITool: String, Codable, CaseIterable, Sendable {
    case claudeCodeTerminal = "claude-code"
    case cursor
    case chatgpt
    case claudeDesktop = "claude-desktop"
    case copilotChat = "copilot-chat"
    case gemini
    case unknown

    var bundleIdentifiers: [String] {
        switch self {
        case .claudeCodeTerminal:
            return ["com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "co.zeit.hyper"]
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92"]
        case .chatgpt:
            return ["com.openai.chat"]
        case .claudeDesktop:
            return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .copilotChat:
            return ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"]
        case .gemini:
            return ["com.google.Gemini"]
        case .unknown:
            return []
        }
    }

    static func from(bundleId: String) -> AITool {
        for tool in AITool.allCases where tool != .unknown {
            if tool.bundleIdentifiers.contains(bundleId) { return tool }
        }
        return .unknown
    }
}

final class WorkspaceMonitor {
    private weak var container: ModelContainer?
    private var observer: NSObjectProtocol?
    private var lastInjectionAt: [AITool: Date] = [:]
    private let cooldown: TimeInterval = 20

    init(container: ModelContainer?) {
        self.container = container
    }

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observer = nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                  object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundle = app.bundleIdentifier else { return }
            self?.handleActivation(bundleId: bundle, app: app)
        }
        Log.info("WorkspaceMonitor started")
    }

    func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func handleActivation(bundleId: String, app: NSRunningApplication) {
        let tool = AITool.from(bundleId: bundleId)
        guard tool != .unknown else {
            Log.debug("Activation: \(bundleId) — not a target AI tool")
            return
        }
        if let last = lastInjectionAt[tool], Date().timeIntervalSince(last) < cooldown {
            Log.debug("Activation: \(tool.rawValue) — cooldown active, skipping")
            return
        }
        lastInjectionAt[tool] = Date()
        Log.info("Activation: \(tool.rawValue) — preparing context injection")
        Task { await injectContext(for: tool) }
    }

    @MainActor
    private func injectContext(for tool: AITool) async {
        guard let container = container else { return }
        let prefs = (try? UserPrefs.load(in: container)) ?? UserPrefs.defaults()

        let snapshot: ContextSnapshot?
        if prefs.localOnly || kIthurielDebug {
            snapshot = await CachedSnapshot.latest(in: container)
        } else {
            let client = IthurielClient(prefs: prefs)
            if let fetched = try? await client.fetchCurrent(format: tool) {
                snapshot = fetched
            } else {
                snapshot = await CachedSnapshot.latest(in: container)
            }
        }

        guard let snap = snapshot else {
            Log.info("No context snapshot available for injection")
            return
        }

        let formatted = ContextFormatter.format(snapshot: snap, for: tool)
        InjectionEngine.shared.primaryInject(text: formatted, target: tool)
    }

    // MARK: - Workspace discovery helpers

    static func mostRecentEditorWorkspace() -> String? {
        for candidate in editorRecentsCandidates() {
            if let path = readRecentWorkspace(from: candidate) {
                return path
            }
        }
        return nil
    }

    static func openFiles(in workspace: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: workspace) else { return [] }
        var result: [String] = []
        var seen = 0
        while let rel = enumerator.nextObject() as? String {
            seen += 1
            if seen > 5_000 { break }
            let lower = rel.lowercased()
            if rel.hasPrefix(".git/") || lower.contains("node_modules") || lower.contains("derivedata") {
                enumerator.skipDescendants()
                continue
            }
            let full = (workspace as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue {
                result.append(full)
                if result.count >= 50 { break }
            }
        }
        return result
    }

    private static func editorRecentsCandidates() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/Code/storage.json"),
            home.appendingPathComponent("Library/Application Support/Cursor/storage.json"),
            home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json")
        ]
    }

    private static func readRecentWorkspace(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let openedPaths = json["openedPathsList"] as? [String: Any],
           let entries = openedPaths["entries"] as? [[String: Any]] {
            for entry in entries {
                if let folder = entry["folderUri"] as? String, let url = URL(string: folder), url.isFileURL {
                    return url.path
                }
            }
        }
        if let openedPaths = json["openedPathsList"] as? [String: Any],
           let workspaces = openedPaths["workspaces"] as? [[String: Any]] {
            for entry in workspaces {
                if let folder = entry["folderUri"] as? String, let url = URL(string: folder), url.isFileURL {
                    return url.path
                }
            }
        }
        return nil
    }
}
