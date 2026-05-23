import AppKit
import SwiftUI
import SwiftData

enum CaptureStatus {
    case capturing, paused, error
}

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
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 460)
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
        case .capturing: symbolName = accessibilityGranted ? "circle.fill" : "circle.dotted"
        case .paused:    symbolName = "circle"
        case .error:     symbolName = "exclamationmark.circle"
        }
        button.image = NSImage(systemSymbolName: symbolName,
                               accessibilityDescription: NSLocalizedString("menubar.icon.a11y", comment: ""))
        button.image?.isTemplate = true
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

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
