import AppKit
import SwiftUI
import SwiftData

enum CaptureStatus {
    case capturing, paused, error
}

/// Left-click → dropdown popover under the menu bar icon.
/// Right-click → context menu. ⌘⇧Space → center-screen Spotlight.
final class MenuBarManager: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var rightClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var ignoreOutsideCloseUntil = Date.distantPast

    private var status: CaptureStatus = .capturing
    private var accessibilityGranted: Bool = false
    private let container: ModelContainer
    private let agentLoop: AgentLoop
    /// Retained separately — NSPopover alone can drop the hosting controller.
    private var popoverHost: NSViewController?

    init(container: ModelContainer, agentLoop: AgentLoop) {
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
            button.action = #selector(statusItemLeftClicked(_:))
            // Default sendAction mask is leftMouseDown — do not add rightMouseDown here;
            // it breaks left-click delivery on many macOS versions.
        }

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let button = self.statusItem?.button,
                  let buttonWindow = button.window,
                  event.window === buttonWindow else { return event }
            self.showContextMenu(from: button, event: event)
            return nil
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 480)
        popover.delegate = self
        self.popover = popover

        MainActor.assumeIsolated {
            ensurePopoverContent()
        }
    }

    deinit {
        if let rightClickMonitor { NSEvent.removeMonitor(rightClickMonitor) }
        stopOutsideClickMonitor()
    }

    func showSettings() {
        closePopover()

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

    // MARK: - Status item

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

    @objc private func statusItemLeftClicked(_ sender: Any?) {
        togglePopover()
    }

    private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else {
            Log.error("MenuBarManager: togglePopover missing popover or button")
            return
        }

        if popover.isShown {
            closePopover()
            return
        }

        // Full-screen Spotlight dimmer sits above normal popovers — hide it first.
        MainActor.assumeIsolated {
            SpotlightCoordinator.shared.dismissImmediately()
            ensurePopoverContent()
        }

        guard popover.contentViewController != nil else {
            Log.error("MenuBarManager: popover has no contentViewController after rebuild")
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        popover?.performClose(nil)
        statusItem?.button?.highlight(false)
        stopOutsideClickMonitor()
    }

    private func showContextMenu(from button: NSStatusBarButton, event: NSEvent) {
        let menu = NSMenu()
        let summon = menu.addItem(withTitle: NSLocalizedString("menubar.menu.summon", comment: ""),
                                  action: #selector(menuSummon), keyEquivalent: " ")
        summon.target = self
        summon.keyEquivalentModifierMask = [.command, .shift]

        let chatItem = menu.addItem(withTitle: "Open Chat…",
                                    action: #selector(menuOpenChat), keyEquivalent: "n")
        chatItem.target = self
        chatItem.keyEquivalentModifierMask = [.command]

        menu.addItem(.separator())
        let muteItem = menu.addItem(withTitle: SoundPlayer.isMuted
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
        closePopover()
        Task { @MainActor in SpotlightCoordinator.shared.summon() }
    }

    @objc private func menuToggleMute() { SoundPlayer.isMuted = !SoundPlayer.isMuted }
    @objc private func menuOpenSettings() { showSettings() }
    @objc private func menuOpenChat() {
        closePopover()
        Task { @MainActor in ChatWindowController.shared.show(container: container, agent: agentLoop) }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        ignoreOutsideCloseUntil = Date().addingTimeInterval(0.35)
        // Install after the opening click finishes so we don't instantly self-close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.installOutsideClickMonitor()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.highlight(false)
        stopOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil, popover?.isShown == true else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopoverIfClickedOutside()
        }
    }

    private func closePopoverIfClickedOutside() {
        guard let popover = popover, popover.isShown else { return }
        guard Date() >= ignoreOutsideCloseUntil else { return }

        if let button = statusItem?.button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(NSEvent.mouseLocation) {
                return
            }
        }

        if let popoverWindow = popover.contentViewController?.view.window {
            if popoverWindow.frame.contains(NSEvent.mouseLocation) {
                return
            }
        }

        closePopover()
    }

    private func stopOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    @MainActor
    private func ensurePopoverContent() {
        guard let popover else { return }
        if popoverHost != nil, popover.contentViewController != nil { return }

        let root = StatusBarView(
            agent: agentLoop,
            onOpenSettings: { [weak self] in self?.showSettings() },
            onQuit: { NSApp.terminate(nil) }
        )
        .modelContainer(container)

        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.preferredContentSize]
        popoverHost = host
        popover.contentViewController = host
    }
}
