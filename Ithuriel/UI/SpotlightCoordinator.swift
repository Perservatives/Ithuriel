import AppKit
import SwiftUI
import SwiftData
import Carbon.HIToolbox

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

    /// Called on app launch. Full-screen black backdrop fades in, the orb
    /// plays its sequence, then both fade out into the Spotlight prompt.
    func playLaunchThenSummon() {
        guard launchWindow == nil else { return }

        // Union all screen frames to find the centre of the entire display arrangement.
        let allBounds = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }

        // Small floating square — no full-screen backdrop, no screen blur.
        let size = NSSize(width: 220, height: 220)
        let frame = NSRect(
            x: allBounds.midX - size.width / 2,
            y: allBounds.midY - size.height / 2,
            width: size.width, height: size.height
        )
        let window = TransparentWindow(
            contentRect: frame,
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
            LaunchOrbView(tint: resolveLaunchColor(), onComplete: { [weak self] in
                self?.dismissLaunch()
            })
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
        spotlightWindow?.orderOut(nil)
        spotlightWindow?.alphaValue = 1
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
        launchWindow?.orderOut(nil)
        launchWindow = nil
        ChatWindowController.shared.toggle()
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
