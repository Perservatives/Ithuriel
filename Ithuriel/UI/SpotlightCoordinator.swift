import AppKit
import SwiftUI
import SwiftData
import Carbon.HIToolbox
import QuartzCore

/// Owns the launch-orb window and the floating Spotlight prompt. Registers the
/// user-configured global summon hotkey (default ⌃Space).
@MainActor
final class SpotlightCoordinator {
    static let shared = SpotlightCoordinator()
    private init() {}

    private weak var container: ModelContainer?
    private weak var agentLoop: AgentLoop?

    private var spotlightWindow: NSWindow?
    private var launchWindow: NSWindow?
    private var launchBackdropWindow: NSWindow?

    private var spotlightIsOpen = false
    private var outsideClickMonitor: Any?

    func configure(container: ModelContainer, agentLoop: AgentLoop) {
        self.container = container
        self.agentLoop = agentLoop
        NotificationCenter.default.addObserver(
            forName: .ithurielOpenChat, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SpotlightCoordinator.shared.summon() }
        }
    }

    // MARK: - Public entry points

    /// Called on app launch. Full-screen colour-blob backdrop blooms in,
    /// the 8-shard orb assembles centre-screen, then `onAssembled` fires.
    /// The caller decides whether to hand off to onboarding (keeping the
    /// surfaces alive) or dismiss into the chat window.
    ///
    /// - Parameter onAssembled: Fires when the orb has finished arriving,
    ///   with the orb still fully visible. If `nil`, the orb fades out and
    ///   the chat window is summoned as before.
    func playLaunchThenSummon(onAssembled: (() -> Void)? = nil) {
        guard launchWindow == nil else { return }

        let tint = resolveLaunchColor()

        // 1. Full-screen blob backdrop, behind everything else, click-through.
        let mainScreen = NSScreen.main ?? NSScreen.screens.first!
        let backdrop = TransparentWindow(
            contentRect: mainScreen.frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        backdrop.isOpaque = false
        backdrop.backgroundColor = .clear
        backdrop.hasShadow = false
        backdrop.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        backdrop.ignoresMouseEvents = true
        backdrop.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backdrop.contentView = NSHostingView(rootView: LaunchBlobsView(baseColor: tint))
        backdrop.alphaValue = 0
        backdrop.orderFrontRegardless()
        launchBackdropWindow = backdrop

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            backdrop.animator().alphaValue = 1
        }

        // 2. The orb sits centre-screen at 720x720, above the backdrop.
        let allBounds = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
        let orbSide: CGFloat = 720
        let orbFrame = NSRect(
            x: allBounds.midX - orbSide / 2,
            y: allBounds.midY - orbSide / 2,
            width: orbSide, height: orbSide
        )
        let window = TransparentWindow(
            contentRect: orbFrame,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let willHandoff = (onAssembled != nil)
        window.contentView = NSHostingView(rootView:
            LaunchOrbView(
                tint: tint,
                holdAfterAssembly: willHandoff,
                onComplete: { [weak self] in
                    if let onAssembled {
                        onAssembled()
                    } else {
                        self?.dismissLaunch()
                    }
                }
            )
        )
        window.orderFrontRegardless()
        launchWindow = window
    }

    /// Read the user's chosen launch color from `UserPrefs`. Falls back to
    /// the system accent on first run or if the model container isn't wired.
    private func resolveLaunchColor() -> Color {
        guard let container,
              let prefs = try? UserPrefs.load(in: container) else {
            return .accentColor
        }
        return Color(hex: prefs.launchColorHex, fallback: .accentColor)
    }

    /// Show the Spotlight prompt at screen centre. No screen dimming —
    /// only the launch sequence darkens the desktop.
    func summon() {
        guard let container, let agentLoop else { return }
        SoundPlayer.shared.play(.summon, volume: 0.4)

        if spotlightWindow == nil { buildSpotlightWindow(container: container, agentLoop: agentLoop) }
        positionWindows()
        spotlightWindow?.alphaValue = 0
        spotlightWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            spotlightWindow?.animator().alphaValue = 1
        }
        spotlightIsOpen = true

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    /// Hides Spotlight/launch UI immediately (e.g. before showing Settings).
    func dismissImmediately() {
        spotlightIsOpen = false
        removeOutsideClickMonitor()
        launchWindow?.orderOut(nil)
        launchWindow = nil
        launchBackdropWindow?.orderOut(nil)
        launchBackdropWindow = nil
        spotlightWindow?.orderOut(nil)
        spotlightWindow?.alphaValue = 1
    }

    // MARK: - Onboarding handoff

    /// Hand the launch surface off to the onboarding window. The blob
    /// backdrop stays on screen (dimmed) so the colour bleeds through the
    /// glass; the orb window shrinks and translates to sit as the onboarding
    /// header mark; the onboarding window fades in over the top.
    func handoffToOnboarding(container: ModelContainer) {
        guard let backdrop = launchBackdropWindow else {
            // Backdrop missing — fall back to a plain onboarding present.
            OnboardingCoordinator.shared.present(container: container)
            return
        }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        // 1. Dim the backdrop so the onboarding glass reads as the hero.
        if reduceMotion {
            backdrop.alphaValue = 0.7
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                backdrop.animator().alphaValue = 0.7
            }
        }

        // 2. Present the onboarding window first so we know where the hero
        //    mark should land. The orb shrinks into the slot we reserve at
        //    the top of the onboarding content area.
        let onboardingSize = OnboardingCoordinator.windowSize
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        let onboardingOrigin = NSPoint(
            x: visible.midX - onboardingSize.width / 2,
            y: visible.midY - onboardingSize.height / 2
        )
        let onboardingFrame = NSRect(origin: onboardingOrigin, size: onboardingSize)

        // Where the orb should sit, in screen coords. We place the mark
        // centred horizontally with its centre at the onboarding header.
        let markSide: CGFloat = 180
        let headerInset: CGFloat = 70 // distance from top of window to mark centre
        let markCentreY = onboardingFrame.maxY - headerInset
        let markFrame = NSRect(
            x: onboardingFrame.midX - markSide / 2,
            y: markCentreY - markSide / 2,
            width: markSide, height: markSide
        )

        // 3. Slide + shrink the orb window to the header slot. The orb scales
        //    uniformly with its container thanks to LaunchOrbView's
        //    GeometryReader, so this reads as one continuous transform.
        if let orb = launchWindow {
            if reduceMotion {
                orb.setFrame(markFrame, display: true)
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.55
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
                    ctx.allowsImplicitAnimation = true
                    orb.animator().setFrame(markFrame, display: true)
                }
            }
        }

        // 4. Show the onboarding window over the dimmed backdrop, below the
        //    orb's screenSaver level so the mark stays as the visual anchor.
        OnboardingCoordinator.shared.present(container: container, atFrame: onboardingFrame)
    }

    /// Tear down both launch surfaces (orb + backdrop) with a soft fade.
    /// Used after onboarding closes, before the chat window appears.
    func fadeOutLaunchSurfaces(_ completion: (() -> Void)? = nil) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let orb = launchWindow
        let backdrop = launchBackdropWindow

        let cleanup = { [weak self] in
            orb?.orderOut(nil)
            backdrop?.orderOut(nil)
            self?.launchWindow = nil
            self?.launchBackdropWindow = nil
            completion?()
        }

        guard orb != nil || backdrop != nil else { completion?(); return }

        if reduceMotion {
            cleanup()
            return
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            orb?.animator().alphaValue = 0
            backdrop?.animator().alphaValue = 0
        }, completionHandler: cleanup)
    }

    func dismiss() {
        guard spotlightIsOpen, let spot = spotlightWindow else { return }
        spotlightIsOpen = false
        removeOutsideClickMonitor()
        SoundPlayer.shared.play(.dismiss, volume: 0.3)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            spot.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                self?.spotlightWindow?.orderOut(nil)
                self?.spotlightWindow?.alphaValue = 1
            }
        })
    }

    /// Toggle visibility — used by the global hotkey and AppChromeBar.
    func toggle() {
        if spotlightIsOpen { dismiss() } else { summon() }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Hotkeys

    /// ⌥Space toggles the Spotlight prompt. Hold ⌥Space starts voice
    /// capture; release submits the captured utterance to the agent.
    func installSummonHotkey() {
        let monitor = HotkeyMonitor.shared
        monitor.onSummonTap  = { [weak self] in self?.toggle() }
        monitor.onVoiceStart = { Task { @MainActor in VoiceController.shared.start() } }
        monitor.onVoiceEnd   = { Task { @MainActor in VoiceController.shared.stopAndSubmit() } }
        monitor.install()
    }

    // MARK: - Internals

    private func dismissLaunch() {
        fadeOutLaunchSurfaces { [weak self] in
            _ = self
            ChatWindowController.shared.toggle()
        }
    }

    private func buildSpotlightWindow(container: ModelContainer, agentLoop: AgentLoop) {
        let view = SpotlightView(agent: agentLoop,
                                 onDismiss: { [weak self] in self?.dismiss() })
            .modelContainer(container)
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false

        let window = SpotlightWindow(
            contentRect: NSRect(x: 0, y: 0, width: UILayout.spotlightWidth, height: 96),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.contentView = host
        spotlightWindow = window
    }

    private func positionWindows() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let visible = screen.visibleFrame
        if let spot = spotlightWindow {
            let w = UILayout.spotlightWidth + UILayout.spacingM * 2
            let fitted = spot.contentView?.fittingSize ?? NSSize(width: w, height: 96)
            let maxH = visible.height * UILayout.spotlightMaxHeightRatio
            let h = min(max(fitted.height, 96), maxH)
            let origin = NSPoint(
                x: visible.midX - w / 2,
                y: visible.midY - h / 2 + visible.height * 0.06
            )
            spot.setFrame(NSRect(origin: origin, size: NSSize(width: w, height: h)), display: false)
        }
    }
}

// MARK: - Custom windows that accept key focus despite being borderless

final class SpotlightWindow: NSWindow {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}

final class TransparentWindow: NSWindow {
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Notification names

extension Notification.Name {
    /// Posted to summon the Spotlight prompt from anywhere in the app.
    /// SpotlightCoordinator observes this in `configure(...)`.
    static let ithurielOpenChat = Notification.Name("dev.ithuriel.openChat")
}
