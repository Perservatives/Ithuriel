import SwiftUI
import AppKit

/// Dark frosted window backdrop — matches the launch splash.
struct SplashWindowBackground: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .underWindowBackground, blendingMode: .behindWindow)
            Color.black.opacity(0.24)
        }
        .ignoresSafeArea()
    }
}

struct SplashChrome: ViewModifier {
    var cornerRadius: CGFloat = 18
    var strokeOpacity: Double = 0.14

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
                    Color.black.opacity(0.18)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 1)
            )
    }
}

extension View {
    func splashChrome(cornerRadius: CGFloat = 18, strokeOpacity: Double = 0.14) -> some View {
        modifier(SplashChrome(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }
}

/// Slowly rotating white 8-point mark — used in chat, sidebar, and launch.
struct SpinningBrandMark: View {
    var size: CGFloat = 72
    var showRing: Bool = true
    var duration: Double = 24

    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showRing {
                Circle()
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
                    .frame(width: size * 1.12, height: size * 1.12)
            }
            AsteriskBurst(
                rotation: rotation,
                tint: .white,
                secondaryTint: .white.opacity(0.62),
                glowRadius: max(4, size * 0.08)
            )
            .frame(width: size, height: size)
        }
        .onAppear { startSpinning() }
        .onChange(of: reduceMotion) { _, _ in startSpinning() }
    }

    private func startSpinning() {
        rotation = 0
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

enum Greeting {
    static func firstName() -> String? {
        let full = NSFullUserName().trimmingCharacters(in: .whitespacesAndNewlines)
        if !full.isEmpty, let part = full.split(separator: " ").first {
            let name = String(part)
            if !name.isEmpty { return name }
        }
        if let host = Host.current().localizedName?
            .split(separator: " ").first.map(String.init), !host.isEmpty {
            return host
        }
        return nil
    }

    static func headline() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let periodKey: String
        switch hour {
        case 5..<12:  periodKey = "greeting.morning"
        case 12..<17: periodKey = "greeting.afternoon"
        case 17..<22: periodKey = "greeting.evening"
        default:      periodKey = "greeting.night"
        }
        let period = NSLocalizedString(periodKey, comment: "")
        if let name = firstName() {
            return String(format: NSLocalizedString("greeting.named", comment: ""), period, name)
        }
        return period
    }

    static func subtitle() -> String {
        NSLocalizedString("greeting.subtitle", comment: "")
    }
}
