import AppKit
import SwiftUI
import SwiftData

/// Owns the launch splash window shown once at app start.
@MainActor
final class LaunchCoordinator {
    static let shared = LaunchCoordinator()
    private init() {}

    private weak var container: ModelContainer?
    private var launchWindow: NSWindow?

    func configure(container: ModelContainer) {
        self.container = container
    }

    /// Full-screen translucent backdrop, frosted card, spinning mark.
    func playLaunchAnimation() {
        guard launchWindow == nil else { return }

        let allBounds = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
        let window = TransparentWindow(
            contentRect: allBounds,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView:
            LaunchSplashView(onComplete: { [weak self] in
                self?.dismiss()
            })
        )
        window.orderFrontRegardless()
        launchWindow = window

        // Hard timeout: dismiss after 10 s even if the animation never fires onComplete.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.dismiss()
        }
    }

    /// Dismiss the splash immediately (idempotent — safe to call multiple times).
    func dismiss() {
        guard let window = launchWindow else { return }
        launchWindow = nil          // nil out first so repeat calls are no-ops
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            window.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                window.alphaValue = 1
            }
        })
    }

    private func dismissLaunch() { dismiss() }
}

/// Borderless overlay window that never steals key focus.
final class TransparentWindow: NSWindow {
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
