import SwiftUI

/// Motion + interaction tokens borrowed from Emil Kowalski's design-engineering
/// playbook (animations.dev). The rules:
///
/// 1. UI animations stay under 300ms.
/// 2. Use strong custom ease-out curves, never built-in `ease-in`.
/// 3. Never animate from `scale(0)` — start at 0.95.
/// 4. Press feedback is `scale(0.97)` for ~160ms.
/// 5. Release is always faster than press.
enum Motion {
    /// Punchier than SwiftUI's default ease-out — matches `cubic-bezier(0.23, 1, 0.32, 1)`.
    static let easeOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
    /// Drawer/sheet motion, iOS-style.
    static let drawer = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.32)
    /// On-screen movement (toast, banner) — symmetric.
    static let easeInOut = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.24)
    /// Press feedback. Slightly faster than release so the button "settles".
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.12)
    /// Spring for elements that should feel alive.
    static let lively = Animation.spring(response: 0.45, dampingFraction: 0.78, blendDuration: 0.1)

    /// Stagger delays for cascading list entries (Emil rule: 30–80ms gap).
    static func staggerDelay(_ index: Int, step: Double = 0.04) -> Double {
        min(Double(index) * step, 0.32)
    }
}

// MARK: - Scale-on-press button style

struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var sound: AgentSound? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(configuration.isPressed ? Motion.press : Motion.easeOut, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed, let sound { SoundPlayer.shared.play(sound, volume: 0.35) }
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    static func pressable(scale: CGFloat = 0.97, sound: AgentSound? = nil) -> PressableButtonStyle {
        PressableButtonStyle(scale: scale, sound: sound)
    }
}

// MARK: - Stagger modifier

struct StaggeredEntry: ViewModifier {
    let index: Int
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.96, anchor: .leading)
            .offset(y: appeared ? 0 : 4)
            .onAppear {
                withAnimation(Motion.easeOut.delay(Motion.staggerDelay(index))) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredEntry(index: index)) }
}
