import AppKit
import SwiftUI
import SwiftData

/// Hosts the first-run `OnboardingView` in a borderless titled window.
/// AppDelegate computes whether onboarding is needed (it has to gate the
/// chat-window opening on this), so this coordinator is intentionally
/// simple: a singleton that owns the window and exposes `present(...)`
/// plus an `onFinish` callback for chaining.
@MainActor
final class OnboardingCoordinator {
    static let shared = OnboardingCoordinator()
    private init() {}

    private var window: NSWindow?
    /// Fires once when the user completes (or closes) onboarding. The app
    /// uses it to chain into the chat window so the user only ever sees one
    /// foreground surface at a time.
    var onFinish: (() -> Void)?

    func present(container: ModelContainer) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }
        let view = OnboardingView { [weak self] in
            self?.dismiss()
        }
        .modelContainer(container)

        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Welcome to Ithuriel"
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.setContentSize(NSSize(width: 540, height: 600))
        w.minSize = NSSize(width: 540, height: 600)
        w.center()
        w.isMovableByWindowBackground = true
        w.backgroundColor = .clear
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        let cb = onFinish
        onFinish = nil
        cb?()
    }
}
