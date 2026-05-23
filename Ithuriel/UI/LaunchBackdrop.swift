import SwiftUI

/// Full-screen takeover that sits behind the LaunchOrb. Heavy dim + accent
/// halo at the centre + animated vignette around the edges.
struct LaunchBackdropView: View {
    @State private var haloScale: CGFloat = 0.6
    @State private var haloOpacity: Double = 0
    @State private var vignetteOpacity: Double = 0

    var body: some View {
        ZStack {
            // Base dim layer — almost-black, but with a touch of accent for warmth.
            LinearGradient(
                colors: [Color.black.opacity(0.96),
                         Color(red: 0.05, green: 0.04, blue: 0.10).opacity(0.94)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Centre halo — pulses outward from where the orb lives.
            RadialGradient(
                colors: [Color.accentColor.opacity(0.30),
                         Color.accentColor.opacity(0.05),
                         .clear],
                center: .center, startRadius: 4, endRadius: 720
            )
            .ignoresSafeArea()
            .scaleEffect(haloScale)
            .opacity(haloOpacity)
            .blur(radius: 40)

            // Edge vignette — pulls the eye to the centre.
            RadialGradient(
                colors: [.clear, .clear, Color.black.opacity(0.55)],
                center: .center, startRadius: 280, endRadius: 1200
            )
            .ignoresSafeArea()
            .opacity(vignetteOpacity)
        }
        .onAppear {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 1.2)) {
                haloScale = 1.2
                haloOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.6)) {
                vignetteOpacity = 1
            }
        }
    }
}
