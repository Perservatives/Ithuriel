import AppKit
import SwiftData

/// Central navigation for windows and shared actions.
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    private(set) weak var container: ModelContainer?
    private(set) weak var agentLoop: AgentLoop?

    private init() {}

    func wire(container: ModelContainer, agentLoop: AgentLoop) {
        self.container = container
        self.agentLoop = agentLoop
    }

    func openSettings() {
        guard let container else { return }
        SettingsWindowController.shared.show(container: container)
    }

    func openChat() {
        guard let container, let agentLoop else { return }
        ChatWindowController.shared.show(container: container, agent: agentLoop)
    }

    func toggleSpotlight() {
        SpotlightCoordinator.shared.toggle()
    }

    func summonSpotlight() {
        SpotlightCoordinator.shared.summon()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    /// Copies the latest workspace context to the clipboard. Returns a user-facing status line.
    func copyContext(modelContext: ModelContext, prefs: UserPrefs) async -> String {
        let container = modelContext.container
        let snap: ContextSnapshot?
        if let cached = await CachedSnapshot.latest(in: container) {
            snap = cached
        } else {
            snap = await ContextSnapshot.captureFresh(prefs: prefs)
            if let snap {
                await CachedSnapshot.persist(snap, in: container)
            }
        }
        guard let snap else {
            return NSLocalizedString("status.copy.empty", comment: "")
        }
        let tool = AppDetector.currentFrontmostTool()
        let target = tool == .unknown ? AITool.claudeCodeTerminal : tool
        let formatted = ContextFormatter.format(snapshot: snap, for: target)
        InjectionEngine.shared.primaryInject(text: formatted, target: target)
        SoundPlayer.shared.play(.done, volume: 0.45)
        return NSLocalizedString("status.copy.done", comment: "")
    }
}
