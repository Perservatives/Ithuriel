import AppKit
import SwiftData

/// Central navigation for windows and shared actions (replaces the menu-bar popover).
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    weak var menuBarManager: MenuBarManager?
    private(set) weak var container: ModelContainer?
    private(set) weak var agentLoop: AgentLoop?

    private init() {}

    func wire(menuBarManager: MenuBarManager, container: ModelContainer, agentLoop: AgentLoop) {
        self.menuBarManager = menuBarManager
        self.container = container
        self.agentLoop = agentLoop
    }

    func openSettings() {
        menuBarManager?.showSettings()
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
