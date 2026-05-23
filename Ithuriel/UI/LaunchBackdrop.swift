import SwiftUI

/// Full-screen translucent launch backdrop — blurs the desktop beneath.
struct LaunchBackdropView: View {
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()

            Color.black.opacity(0.28)
                .ignoresSafeArea()
        }
    }
}
