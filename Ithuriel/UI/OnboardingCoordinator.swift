import AppKit
import SwiftUI
import SwiftData
import QuartzCore

/// Hosts the first-run `OnboardingView` in a borderless, glass-tinted
/// window. The launch backdrop (LaunchBlobsView) stays alive behind it, so
/// the colour reads through the window's `NSVisualEffectView` as a soft
/// tinted bloom.
@MainActor
final class OnboardingCoordinator {
    static let shared = OnboardingCoordinator()
    private init() {}

    /// Canonical onboarding window size. Exposed so SpotlightCoordinator can
    /// position the orb's hero slot relative to it before presenting.
    static let windowSize = NSSize(width: 540, height: 640)

    private var window: NSWindow?
    /// Fires once when the user completes (or closes) onboarding. The app
    /// uses it to chain into the chat window so the user only ever sees one
    /// foreground surface at a time.
    var onFinish: (() -> Void)?

    /// Present the onboarding window. If `atFrame` is supplied (e.g. by
    /// `SpotlightCoordinator.handoffToOnboarding`), the window pins itself
    /// there so the hero orb above lands precisely on the header mark slot;
    /// otherwise it centres on the main screen.
    func present(container: ModelContainer, atFrame: NSRect? = nil) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        let view = OnboardingView { [weak self] in
            self?.dismiss()
        }
        .modelContainer(container)

        let host = NSHostingController(rootView: view)
        host.view.wantsLayer = true

        let frame: NSRect = atFrame ?? {
            let screen = NSScreen.main ?? NSScreen.screens.first!
            let visible = screen.visibleFrame
            return NSRect(
                x: visible.midX - Self.windowSize.width / 2,
                y: visible.midY - Self.windowSize.height / 2,
                width: Self.windowSize.width,
                height: Self.windowSize.height
            )
        }()

        let w = OnboardingWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.title = "Welcome to Ithuriel"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        // Sit above the launch backdrop (screenSaver - 1) but below the orb
        // (screenSaver), so the orb continues to read as the hero mark on
        // top of the onboarding glass.
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Glass surface: NSVisualEffectView hosts the SwiftUI content. The
        // material is .hudWindow with vibrantDark appearance so the blob
        // backdrop behind reads as a soft tinted bloom.
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true
        effect.appearance = NSAppearance(named: .vibrantDark)

        host.view.frame = effect.bounds
        host.view.autoresizingMask = [.width, .height]
        host.view.layer?.backgroundColor = .clear
        effect.addSubview(host.view)

        // Hairline highlight on the rim — keeps the glass from blending
        // into whatever sits behind it.
        let rim = CALayer()
        rim.frame = effect.bounds
        rim.cornerRadius = 22
        rim.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        rim.borderWidth = 0.5
        rim.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        effect.layer?.addSublayer(rim)

        w.contentView = effect
        window = w
        NSApp.activate(ignoringOtherApps: true)

        if reduceMotion {
            w.alphaValue = 1
            w.makeKeyAndOrderFront(nil)
            return
        }

        // Fade in with a small upward translation. Use a temporary frame
        // offset (16pt below the target) and animate to `frame`.
        let entryFrame = frame.offsetBy(dx: 0, dy: -16)
        w.setFrame(entryFrame, display: false)
        w.alphaValue = 0
        w.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            ctx.allowsImplicitAnimation = true
            w.animator().alphaValue = 1
            w.animator().setFrame(frame, display: true)
        }
    }

    private func dismiss() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let w = window
        let finalise: () -> Void = { [weak self] in
            w?.orderOut(nil)
            self?.window = nil
            let cb = self?.onFinish
            self?.onFinish = nil
            cb?()
        }

        guard let w, !reduceMotion else {
            finalise()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            w.animator().alphaValue = 0
        }, completionHandler: finalise)
    }
}

/// Borderless onboarding window that can still take key focus so its
/// controls (sign-in button, hotkey picker, footer buttons) respond.
final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
