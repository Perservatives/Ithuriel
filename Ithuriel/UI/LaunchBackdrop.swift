import SwiftUI

/// Full-screen launch backdrop. A near-white wash with the faintest cool
/// vignette toward the centre — the screen "becomes paper" so the
/// 8-point shards converging onto the centre read cleanly. The tint is
/// only used to colour the petals, never the canvas.
struct LaunchBackdropView: View {
    let baseColor: Color

    init(baseColor: Color = .accentColor) {
        self.baseColor = baseColor
    }

    var body: some View {
        ZStack {
            // Off-white canvas. Apple's "graphite paper" feel: F8F8F7-ish.
            Color(red: 0.976, green: 0.974, blue: 0.969).ignoresSafeArea()
            // Subtle cool wash toward the centre so the shards' shadows
            // have somewhere to land.
            RadialGradient(
                colors: [Color.black.opacity(0.03), .clear],
                center: .center,
                startRadius: 80,
                endRadius: 520
            )
            .blendMode(.multiply)
            .ignoresSafeArea()
        }
    }
}
