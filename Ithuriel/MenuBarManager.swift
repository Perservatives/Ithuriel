import AppKit
import SwiftUI
import SwiftData

enum CaptureStatus {
    case capturing, paused, error
}

/// Menu bar icon only — click toggles Spotlight. All controls live in Chat / Spotlight / Settings.
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private var status: CaptureStatus = .capturing
    private var accessibilityGranted: Bool = false
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        refreshIcon()

        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func showSettings() {
        if settingsWindow == nil {
            let root = SettingsView().modelContainer(container)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = NSLocalizedString("settings.window.title", comment: "")
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 540))
            window.minSize = NSSize(width: 760, height: 540)
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

    @objc private func statusItemClicked(_ sender: Any?) {
        Task { @MainActor in AppRouter.shared.toggleSpotlight() }
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
