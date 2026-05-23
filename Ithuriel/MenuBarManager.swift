import AppKit

enum CaptureStatus {
    case capturing, paused, error
}

/// Menu bar asterisk — left-click opens the chat window; right-click shows a
/// context menu (Library, Quit). The context menu is built on demand so it
/// doesn't intercept left-clicks.
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
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            Task { @MainActor in AppRouter.shared.openChat() }
        }
    }

    /// Right-click context menu on the status item. Currently exposes the
    /// Library window so it lives outside the main chat sidebar.
    private func showContextMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()

        let library = NSMenuItem(title: "Library", action: #selector(openLibrary), keyEquivalent: "")
        library.target = self
        menu.addItem(library)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Ithuriel", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        item.button?.performClick(nil)
        // Reset so the next left-click triggers our action handler again
        // instead of opening this menu.
        item.menu = nil
    }

    @objc private func openLibrary() {
        Task { @MainActor in LibraryWindowController.shared.show() }
    }

    @objc private func quit() {
        Task { @MainActor in AppRouter.shared.quit() }
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
