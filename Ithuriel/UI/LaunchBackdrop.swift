import SwiftUI

/// Full-screen launch backdrop. Pure black with the faintest vignette toward
/// the centre — the screen "goes dark" so the shards assembling into the
/// 8-point Ithuriel mark are the only thing the eye is drawn to.
struct LaunchBackdropView: View {
    let baseColor: Color

    init(baseColor: Color = .accentColor) {
        self.baseColor = baseColor
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.04), .clear],
                center: .center,
                startRadius: 60,
                endRadius: 540
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()
        }
    }
}
