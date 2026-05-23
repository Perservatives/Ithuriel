import AppKit
import SwiftUI
import SwiftData

/// Owns the standalone chat window — primary app surface. Opened on launch,
/// from AppChromeBar, the global hotkey, or when the user clicks the Dock icon.
@MainActor
final class ChatWindowController {
    static let shared = ChatWindowController()
    private init() {}

    private weak var pendingContainer: ModelContainer?
    private weak var pendingAgent: AgentLoop?
    private var window: NSWindow?

    /// Cache references so toggle() / hotkeys can summon without arguments.
    func configure(container: ModelContainer, agent: AgentLoop) {
        pendingContainer = container
        pendingAgent = agent
    }

    func show(container: ModelContainer?, agent: AgentLoop?) {
        guard let container, let agent else { return }
        pendingContainer = container
        pendingAgent = agent
        if window == nil { build(container: container, agent: agent) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func toggle() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        show(container: pendingContainer, agent: pendingAgent)
    }

    private func build(container: ModelContainer, agent: AgentLoop) {
        let root = ChatView(agent: agent).modelContainer(container)
        let host = NSHostingController(rootView: root)

        let w = NSWindow(contentViewController: host)
        w.title = "Ithuriel"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 960, height: 640))
        w.center()
        w.minSize = NSSize(width: 520, height: 420)
        // Transparent so the SwiftUI VisualEffectBlur shows through under the
        // title bar — no white strip behind the traffic lights.
        w.backgroundColor = .clear
        w.isOpaque = false
        window = w
    }
}
