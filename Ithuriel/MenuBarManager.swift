import AppKit
import SwiftUI
import SwiftData

enum CaptureStatus {
    case capturing, paused, error
}

/// Left-click → dropdown popover. Right-click / control-click → context menu.
/// ⌘⇧Space still summons the center-screen Spotlight via SpotlightCoordinator.
@MainActor
final class MenuBarManager: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var outsideClickMonitor: Any?
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
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 480)
        if let container = container, let loop = agentLoop {
            let root = StatusBarView(
                agent: loop,
                onOpenSettings: { [weak self] in self?.showSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
            .modelContainer(container)
            popover.contentViewController = NSHostingController(rootView: root)
        }
        popover.delegate = self
        self.popover = popover
    }

    func showSettings() {
        guard let container = container else { return }
        popover?.performClose(nil)

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
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        let isRightClick = event.type == .rightMouseDown
            || event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)
        if isRightClick {
            showContextMenu(from: sender, event: event)
        } else {
            togglePopover()
        }
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton, event: NSEvent) {
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

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    @objc private func menuSummon() {
        popover?.performClose(nil)
        SpotlightCoordinator.shared.summon()
    }

    @objc private func menuToggleMute() { SoundPlayer.shared.muted.toggle() }
    @objc private func menuOpenSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopoverIfClickedOutside()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
    }

    private func closePopoverIfClickedOutside() {
        guard let popover = popover, popover.isShown else { return }

        if let button = statusItem?.button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(NSEvent.mouseLocation) {
                return
            }
        }

        popover.performClose(nil)
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
