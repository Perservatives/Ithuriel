import AppKit
import SwiftUI

/// Apple-Intelligence-style screen-edge glow that lights up while the voice
/// hotkey is held (⌥Space). A click-through full-screen window paints animated
/// colour bands hugging the four edges of the active display.
@MainActor
final class EdgeGlowController {
    static let shared = EdgeGlowController()
    private init() {}

    private var window: NSWindow?
    private var hostingController: NSHostingController<EdgeGlowView>?

    func show(palette: EdgeGlowPalette = .siri) {
        if window == nil { build() }
        hostingController?.rootView = EdgeGlowView(visible: true, palette: palette)
        window?.orderFrontRegardless()
    }

    func hide() {
        hostingController?.rootView = EdgeGlowView(visible: false, palette: .siri)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    private func build() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let w = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let host = NSHostingController(rootView: EdgeGlowView(visible: false, palette: .siri))
        w.contentView = host.view
        w.contentView?.wantsLayer = true
        hostingController = host
        window = w
    }
}

struct EdgeGlowPalette {
    let colors: [Color]

    static let siri = EdgeGlowPalette(colors: [
        Color(red: 0.47, green: 0.36, blue: 1.00),   // violet
        Color(red: 1.00, green: 0.38, blue: 0.65),   // pink
        Color(red: 1.00, green: 0.62, blue: 0.32),   // orange
        Color(red: 0.34, green: 0.85, blue: 1.00),   // cyan
        Color(red: 0.47, green: 0.36, blue: 1.00)    // wrap
    ])

    static let success = EdgeGlowPalette(colors: [
        Color(red: 0.30, green: 0.85, blue: 0.50),
        Color(red: 0.34, green: 0.95, blue: 0.85),
        Color(red: 0.30, green: 0.85, blue: 0.50)
    ])
}

/// The visual itself: four edge-hugging blurred bands that rotate hue and
/// breathe. Hidden state is a faint <2% opacity so the fade-out reads smooth.
private struct EdgeGlowView: View {
    let visible: Bool
    let palette: EdgeGlowPalette

    @State private var phase: Double = 0
    @State private var breathe: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                edgeBand(.top,    width: proxy.size.width)
                edgeBand(.bottom, width: proxy.size.width)
                edgeBand(.leading,  width: proxy.size.height)
                edgeBand(.trailing, width: proxy.size.height)
            }
            .opacity(visible ? 1 : 0)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.32), value: visible)
            .onAppear {
                withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                    phase = 1
                }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    breathe = 1.08
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func edgeBand(_ edge: Edge, width: CGFloat) -> some View {
        let thickness: CGFloat = 80
        let gradient = LinearGradient(
            colors: palette.colors,
            startPoint: edge == .top || edge == .bottom ? .leading : .top,
            endPoint:   edge == .top || edge == .bottom ? .trailing : .bottom
        )
        let inner = RoundedRectangle(cornerRadius: thickness, style: .continuous)
            .fill(gradient)
            .blur(radius: 38)
            .scaleEffect(breathe)
            .hueRotation(.degrees(phase * 30))

        switch edge {
        case .top:
            inner
                .frame(height: thickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(y: -thickness * 0.55)
        case .bottom:
            inner
                .frame(height: thickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .offset(y: thickness * 0.55)
        case .leading:
            inner
                .frame(width: thickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .offset(x: -thickness * 0.55)
        case .trailing:
            inner
                .frame(width: thickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .offset(x: thickness * 0.55)
        }
    }
}
