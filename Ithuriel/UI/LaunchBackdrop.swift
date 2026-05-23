import SwiftUI

/// Full-screen translucent launch backdrop — blurs the desktop beneath.
struct LaunchBackdropView: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color.black.opacity(0.28)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.06), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 480
            )
            .ignoresSafeArea()
        }
    }
}
