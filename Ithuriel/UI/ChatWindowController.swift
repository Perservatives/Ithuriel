import AppKit
import SwiftUI
import SwiftData

/// Owns the standalone chat window. Lazy — opened from the menu bar context
/// menu and via ⌘N when any Ithuriel window is key.
@MainActor
final class ChatWindowController {
    static let shared = ChatWindowController()
    private init() {}

    private var window: NSWindow?

    func show(container: ModelContainer?, agent: AgentLoop?) {
        guard let container, let agent else { return }
        if window == nil { build(container: container, agent: agent) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build(container: ModelContainer, agent: AgentLoop) {
        let root = ChatView(agent: agent).modelContainer(container)
        let host = NSHostingController(rootView: root)

        let w = NSWindow(contentViewController: host)
        w.title = "Ithuriel"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.toolbarStyle = .unified
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 1180, height: 720))
        w.center()
        w.minSize = NSSize(width: 900, height: 560)
        w.backgroundColor = .clear
        window = w
    }
}
