import AppKit
import SwiftUI
import SwiftData

enum CaptureStatus {
    case capturing, paused, error
}

final class MenuBarManager {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var status: CaptureStatus = .capturing
    private var accessibilityGranted: Bool = false
    private weak var container: ModelContainer?
    private weak var agentLoop: AgentLoop?

    init(container: ModelContainer?, agentLoop: AgentLoop?) {
        self.container = container
        self.agentLoop = agentLoop
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
            let root = StatusBarView(agent: loop, onQuit: { NSApp.terminate(nil) })
                .modelContainer(container)
            popover.contentViewController = NSHostingController(rootView: root)
        }
        self.popover = popover
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
}
