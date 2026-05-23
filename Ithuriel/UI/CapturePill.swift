import AppKit
import SwiftUI

/// Small top-right pill that flashes for 1.5s whenever a context capture lands.
/// Mirrors the NSWindow approach used by DoneBannerController but is positioned
/// at the top-right of the main screen and tinted with the user's launchColorHex.
@MainActor
final class CapturePillController {
    static let shared = CapturePillController()
    private init() {}

    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func flash(workspace: String, accentHex: String) {
        dismissTask?.cancel()

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = NSSize(width: 220, height: 32)
        let origin = NSPoint(
            x: screen.frame.maxX - size.width - 16,
            y: screen.frame.maxY - size.height - 16
        )

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless],
                backing: .buffered, defer: false
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.level = .floating
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            window = w
        }
        window?.setFrame(NSRect(origin: origin, size: size), display: false)
        window?.contentView = NSHostingView(
            rootView: CapturePillView(workspace: workspace, accentHex: accentHex)
        )
        window?.orderFrontRegardless()

        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.dismiss() }
        }
    }

    private func dismiss() {
        if let host = window?.contentView as? NSHostingView<CapturePillView> {
            host.rootView = CapturePillView(
                workspace: host.rootView.workspace,
                accentHex: host.rootView.accentHex,
                visible: false
            )
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }
}

struct CapturePillView: View {
    let workspace: String
    let accentHex: String
    var visible: Bool = true

    @State private var enter: Double = 0

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle().stroke(accent.opacity(0.4), lineWidth: 2).scaleEffect(1.6)
                )
            Text("Capturing…")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                accent.opacity(0.08)
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().strokeBorder(accent.opacity(0.22), lineWidth: 0.5))
        .shadow(color: accent.opacity(0.25), radius: 8, y: 3)
        .opacity(visible ? enter : 0)
        .scaleEffect(visible ? (0.96 + 0.04 * enter) : 0.94)
        .onAppear {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
                enter = 1
            }
        }
        .animation(.timingCurve(0.4, 0, 1, 1, duration: 0.25), value: visible)
    }

    private var accent: Color { Color(hex: accentHex, fallback: Color(red: 0.48, green: 0.36, blue: 1.0)) }
}
