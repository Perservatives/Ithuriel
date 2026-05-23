import AppKit
import SwiftUI
import SwiftData

enum CaptureStatus {
    case capturing, paused, error
}

/// Menu bar item is now the launcher for the Spotlight (the headline UX).
/// Left-click → summon Spotlight. Right-click (or ⌥-click) → small menu
/// with Settings / Mute / Quit. The status icon still indicates capture state.
@MainActor
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var status: CaptureStatus = .capturing
    private var accessibilityGranted: Bool = false
    private weak var container: ModelContainer?
    private weak var agentLoop: AgentLoop?

    init(container: ModelContainer?, agentLoop: AgentLoop?) {
        self.container = container
        self.agentLoop = agentLoop
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshIcon()

        if let button = item.button {
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Opens the Settings UI in its own borderless-titled window. Preferred
    /// over `showSettingsWindow:` because we run with `LSUIElement` and the
    /// SwiftUI `Settings` scene doesn't always activate reliably from an
    /// accessory app.
    func showSettings() {
        guard let container = container else { return }
        if settingsWindow == nil {
            let root = SettingsView().modelContainer(container)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = NSLocalizedString("settings.window.title", comment: "")
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 560, height: 440))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func setAccessibilityState(granted: Bool) {
        accessibilityGranted = granted
        refreshIcon()
    }

    func setStatus(_ status: CaptureStatus) {
        self.status = status
        refreshIcon()
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName: String
        switch status {
        case .capturing: symbolName = accessibilityGranted ? "asterisk" : "circle.dotted"
        case .paused:    symbolName = "circle"
        case .error:     symbolName = "exclamationmark.circle"
        }
        button.image = NSImage(systemSymbolName: symbolName,
                               accessibilityDescription: NSLocalizedString("menubar.icon.a11y", comment: ""))
        button.image?.isTemplate = true
    }

    @objc private func buttonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp ||
                           (event?.modifierFlags.contains(.option) == true)
        if isRightClick {
            showContextMenu(from: sender)
        } else {
            SpotlightCoordinator.shared.toggle()
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let summon = menu.addItem(withTitle: NSLocalizedString("menubar.menu.summon", comment: ""),
                                  action: #selector(menuSummon), keyEquivalent: " ")
        summon.target = self
        summon.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        let muteItem = menu.addItem(withTitle: SoundPlayer.shared.muted
                                    ? NSLocalizedString("menubar.menu.unmute", comment: "")
                                    : NSLocalizedString("menubar.menu.mute", comment: ""),
                                    action: #selector(menuToggleMute), keyEquivalent: "")
        muteItem.target = self
        let settingsItem = menu.addItem(withTitle: NSLocalizedString("menubar.menu.settings", comment: ""),
                                        action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: NSLocalizedString("menubar.menu.quit", comment: ""),
                                    action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self

        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func menuSummon() { SpotlightCoordinator.shared.summon() }
    @objc private func menuToggleMute() { SoundPlayer.shared.muted.toggle() }
    @objc private func menuOpenSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}
