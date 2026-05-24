import AppKit

/// Brings Ithuriel to the foreground after launch or when opening a window.
@MainActor
enum AppForeground {
    static func activate(bringing window: NSWindow? = nil) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
