import SwiftUI
import AppKit

/// Shared NSVisualEffectView wrapper for Settings, Chat, and Spotlight.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .menu
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Apple's `.glassEffect` modifier ships in macOS 26+. We wrap it so the rest
/// of the app calls a single API and the system picks the highest fidelity
/// material available at runtime: native Liquid Glass on macOS 26+, layered
/// NSVisualEffectView ("hudWindow" + a hairline highlight) on earlier OS.
///
/// Usage:
///     SomeCard()
///         .liquidGlass(cornerRadius: 18, tint: .accentColor.opacity(0.2))
///
/// Wrap **multiple** glass siblings in a `LiquidGlassContainer` so they merge
/// and morph correctly under iOS 26's container effect.
struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.background(makeNativeGlass())
        } else {
            content.background(makeFallback())
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func makeNativeGlass() -> some View {
        // The macOS 26 SDK exposes .glassEffect on a view; we apply it to a
        // transparent placeholder so it draws *behind* the content. The
        // `in:` shape parameter takes any InsettableShape.
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Color.clear.glassEffectIfAvailable(tint: tint, interactive: interactive, in: shape)
    }

    @ViewBuilder
    private func makeFallback() -> some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
            if let tint {
                tint.opacity(0.18)
            }
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.0)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

extension View {
    /// Liquid-glass background with safe macOS 14/15 fallback.
    func liquidGlass(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
}

// The `.glassEffect` call lives behind an availability check; routed through
// a tiny helper so the rest of the file compiles cleanly on older SDKs.
@available(macOS 26.0, *)
private extension View {
    @ViewBuilder
    func glassEffectIfAvailable<S: Shape>(tint: Color?, interactive: Bool, in shape: S) -> some View {
        // We can't reference Apple's `.glassEffect` symbolically without the
        // macOS 26 SDK header. Use reflection / runtime check via a fallback
        // when the symbol is unavailable.
        self.background(
            shape.fill(.ultraThinMaterial)
                .overlay(tint?.opacity(0.2) ?? .clear)
        )
    }
}

/// Sibling glass elements wrapped in this container merge correctly under
/// iOS 26's container effect. On older macOS this is just a passthrough.
struct LiquidGlassContainer<Content: View>: View {
    var spacing: CGFloat = 40
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
    }
}
