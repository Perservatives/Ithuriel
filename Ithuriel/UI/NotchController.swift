import AppKit
import SwiftUI

/// Owns the borderless `NSPanel` that hosts the notch widget. The panel hugs
/// the camera housing area and persists across spaces. Safe to call
/// `install()` on non-notch Macs — it returns early.
@MainActor
final class NotchController {
    static let shared = NotchController()
    private init() {}

    private var window: NSPanel?

    /// True when the panel is currently installed and visible.
    var isInstalled: Bool { window != nil }

    func install() {
        guard window == nil, let notch = NotchDetector.notchRect() else { return }

        // Give the panel room to grow downward when the widget expands —
        // otherwise SwiftUI is clipped by the panel's content rect.
        let expandedHeight: CGFloat = 96
        let expandedWidth: CGFloat = 380
        let frame = NSRect(
            x: notch.midX - expandedWidth / 2,
            y: notch.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        let host = NSHostingView(rootView: NotchView())
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host

        panel.orderFrontRegardless()
        window = panel
    }

    func teardown() {
        window?.orderOut(nil)
        window = nil
    }
}
