import AppKit

enum CaptureStatus {
    case capturing, paused, error
}

/// Menu bar asterisk — click opens the chat window. No popover, no context menu.
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?

    private var status: CaptureStatus = .capturing
    private var accessibilityGranted: Bool = false

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshIcon()

        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp])
        button.menu = nil
    }

    func setAccessibilityState(granted: Bool) {
        accessibilityGranted = granted
        refreshIcon()
    }

    func setStatus(_ status: CaptureStatus) {
        self.status = status
        refreshIcon()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        Task { @MainActor in AppRouter.shared.openChat() }
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
}
