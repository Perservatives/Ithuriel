import AppKit
import SwiftUI
import SwiftData
import Carbon.HIToolbox

/// Owns the launch-orb window, the full-screen backdrop dimmer, and the
/// floating Spotlight prompt window. Registers ⌘⇧Space as the global summon
/// hotkey. The menu bar still exists, but this is the headline UX.
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
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let tint = resolveLaunchColor()

        // Full-screen backdrop — Arc-style fuzzy color blobs over black.
        // Snapped on at full alpha (no fade) so the desktop never flashes
        // through while the bloom is ramping up.
        let backdrop = TransparentWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        backdrop.isOpaque = false
        backdrop.backgroundColor = .clear
        backdrop.hasShadow = false
        backdrop.level = .screenSaver - 1
        backdrop.ignoresMouseEvents = true
        backdrop.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backdrop.contentView = NSHostingView(rootView: LaunchBackdropView(baseColor: tint))
        backdrop.alphaValue = 1
        backdrop.orderFrontRegardless()
        launchBackdropWindow = backdrop

        // Bigger orb window — covers a generous swath of the screen.
        let size = NSSize(width: 720, height: 720)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
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
            LaunchOrbView(tint: tint, onComplete: { [weak self] in
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
    }

    /// Hides Spotlight/launch UI immediately so menu-bar popovers are not covered.
    func dismissImmediately() {
        spotlightIsOpen = false
        launchWindow?.orderOut(nil)
        launchWindow = nil
        spotlightWindow?.orderOut(nil)
        spotlightWindow?.alphaValue = 1
    }

    func dismiss() {
        guard spotlightIsOpen, let spot = spotlightWindow else { return }
        spotlightIsOpen = false
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

    /// Toggle visibility — used by the menu bar.
    func toggle() {
        if spotlightIsOpen { dismiss() } else { summon() }
    }

    // MARK: - Hotkeys

    /// ⌃Space toggles Spotlight. ⌥Space tap opens the full Chat window;
    /// hold ⌥Space starts voice capture and release submits.
    func installSummonHotkey() {
        let monitor = HotkeyMonitor.shared
        monitor.onSummonTap = { [weak self] in self?.toggle() }
        monitor.onChatTap   = { Task { @MainActor in ChatWindowController.shared.toggle() } }
        monitor.onVoiceStart = { Task { @MainActor in VoiceController.shared.start() } }
        monitor.onVoiceEnd   = { Task { @MainActor in VoiceController.shared.stopAndSubmit() } }
        monitor.install()
    }

    // MARK: - Internals

    private func dismissLaunch() {
        if let backdrop = launchBackdropWindow {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.40
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
                backdrop.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    self?.launchBackdropWindow?.orderOut(nil)
                    self?.launchBackdropWindow = nil
                }
            })
        }
        launchWindow?.orderOut(nil)
        launchWindow = nil
    }

    private func buildSpotlightWindow(container: ModelContainer, agentLoop: AgentLoop) {
        let view = SpotlightView(agent: agentLoop,
                                 onDismiss: { [weak self] in self?.dismiss() })
            .modelContainer(container)
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = false

        let window = SpotlightWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 80),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = false
        window.contentView = host
        spotlightWindow = window
    }

    private func positionWindows() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        if let spot = spotlightWindow {
            let size = spot.contentView?.fittingSize ?? NSSize(width: 640, height: 80)
            let w: CGFloat = 640
            let h = max(size.height, 80)
            let origin = NSPoint(
                x: screen.frame.midX - w / 2,
                y: screen.frame.midY - h / 2 + 60   // a touch above visual centre
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
