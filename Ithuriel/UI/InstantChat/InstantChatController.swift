import AppKit
import SwiftUI
import SwiftData

/// ChatGPT-desktop-style ⌥Space popup. A small floating panel anchored at
/// roughly vertical 1/3 of the main screen; tapping the hotkey again or Esc
/// dismisses it. Uses a non-activating `NSPanel` so we do not steal focus
/// from the user's current app.
@MainActor
final class InstantChatController {
    static let shared = InstantChatController()
    private init() {}

    private weak var container: ModelContainer?
    private weak var agentLoop: AgentLoop?
    private var window: NSPanel?
    private var isOpen = false

    func configure(container: ModelContainer, agent: AgentLoop) {
        self.container = container
        self.agentLoop = agent
    }

    /// Toggle the popup. Called by HotkeyMonitor on ⌥Space tap.
    func toggle() {
        if isOpen { dismiss() } else { present() }
    }

    func present() {
        guard let container, let agentLoop else { return }
        if window == nil { buildWindow(container: container, agent: agentLoop) }
        positionAtScreenTop()
        window?.makeKeyAndOrderFront(nil)
        // Non-activating: bring the panel forward without yanking app focus
        // away from whatever the user was doing.
        NSApp.activate(ignoringOtherApps: false)
        isOpen = true
    }

    func dismiss() {
        window?.orderOut(nil)
        isOpen = false
    }

    private func buildWindow(container: ModelContainer, agent: AgentLoop) {
        let view = InstantChatView(
            agent: agent,
            onDismiss: { [weak self] in self?.dismiss() },
            onEscalate: { [weak self] in
                self?.dismiss()
                ChatWindowController.shared.show(container: container, agent: agent)
            },
            onHeightChange: { [weak self] newHeight in
                self?.animateHeight(to: newHeight)
            }
        )
        .modelContainer(container)

        let panel = InstantChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 96),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: AnyView(view))
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 96)
        panel.contentView = host
        window = panel
    }

    private func positionAtScreenTop() {
        guard let panel = window, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let w: CGFloat = 720
        let currentH = panel.frame.height
        let h: CGFloat = currentH > 0 ? currentH : 96
        // ChatGPT places it roughly 1/3 down from the top of the visible area.
        let topY = f.maxY - f.height * 0.33
        let origin = NSPoint(x: f.midX - w / 2, y: topY - h / 2)
        panel.setFrame(NSRect(origin: origin, size: CGSize(width: w, height: h)), display: true)
    }

    /// Smoothly grow/shrink the panel as the response area renders. Anchors
    /// the top edge so the input field stays put while content expands down.
    private func animateHeight(to newHeight: CGFloat) {
        guard let panel = window else { return }
        let current = panel.frame
        let topY = current.origin.y + current.size.height
        let clamped = max(96, min(newHeight, 620))
        let newFrame = NSRect(
            x: current.origin.x,
            y: topY - clamped,
            width: current.size.width,
            height: clamped
        )
        guard abs(newFrame.size.height - current.size.height) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            // cubic-bezier(0.23, 1, 0.32, 1) — Emil's strong ease-out.
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1.0, 0.32, 1.0)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(newFrame, display: true)
        }
    }
}

/// Borderless NSPanel that accepts keyboard focus but never becomes main —
/// keeps the user's underlying app in focus when the popup closes.
private final class InstantChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
