import AppKit
import SwiftUI
import SwiftData

/// Owns the standalone Settings window (formerly opened from the menu bar).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    private var window: NSWindow?

    func show(container: ModelContainer) {
        if window == nil {
            let root = SettingsView().modelContainer(container)
            let hosting = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: hosting)
            w.title = NSLocalizedString("settings.window.title", comment: "")
            w.styleMask = [.titled, .closable, .resizable]
            w.setContentSize(NSSize(width: 760, height: 540))
            w.minSize = NSSize(width: 760, height: 540)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
