import SwiftUI

/// Full-screen launch cutscene: translucent backdrop, frosted card, spinning mark.
struct LaunchSplashView: View {
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            LaunchBackdropView()

            LaunchOrbView(onComplete: onComplete)
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .background(cardBackground)
                .overlay(
                    Rectangle()
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 32, y: 14)
        }
        .ignoresSafeArea()
    }

    private var cardBackground: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .withinWindow)
            Color.black.opacity(0.18)
        }
    }
}
