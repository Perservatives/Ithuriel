import SwiftUI
import AppKit

/// Spinning 8-point brand mark — white AsteriskBurst at centre, wordmark beneath.
struct LaunchOrbView: View {
    @State private var rotation: Double = 0
    @State private var petalScale: CGFloat = 0.35
    @State private var haloScale: CGFloat = 0.5
    @State private var haloOpacity: Double = 0
    @State private var coreOpacity: Double = 1
    @State private var captionOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: () -> Void

    private let starPrimary = Color.white
    private let starSecondary = Color.white.opacity(0.62)

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [starPrimary.opacity(0.38), starPrimary.opacity(0.10), .clear],
                            center: .center, startRadius: 8, endRadius: 200
                        )
                    )
                    .frame(width: 380, height: 380)
                    .blur(radius: 28)
                    .scaleEffect(haloScale)
                    .opacity(haloOpacity)

                Circle()
                    .strokeBorder(starPrimary.opacity(0.22), lineWidth: 1)
                    .frame(width: 220, height: 220)
                    .scaleEffect(petalScale * 0.92)
                    .opacity(haloOpacity * 0.8)

                AsteriskBurst(
                    rotation: rotation,
                    petalScale: petalScale,
                    tint: starPrimary,
                    secondaryTint: starSecondary,
                    glowRadius: 22
                )
                .frame(width: 200, height: 200)
            }
            .frame(width: 340, height: 340)

            Text(NSLocalizedString("launch.caption", comment: ""))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(9)
                .foregroundStyle(starPrimary.opacity(0.92))
                .opacity(captionOpacity)
                .padding(.bottom, 4)
        }
        .frame(width: 400, height: 480)
        .opacity(coreOpacity)
        .task { await runSequence() }
    }

    private func runSequence() async {
        SoundPlayer.shared.play(.launch, volume: 0.5)

        if reduceMotion {
            rotation = 0
            petalScale = 1.0
            haloOpacity = 0.35
            captionOpacity = 0.9
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                coreOpacity = 0
                captionOpacity = 0
                haloOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onComplete()
            return
        }

        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
            rotation = 360
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            petalScale = 1.0
            haloScale = 1.0
            haloOpacity = 0.55
        }

        try? await Task.sleep(nanoseconds: 400_000_000)
        SoundPlayer.shared.play(.done, volume: 0.32)
        withAnimation(.easeOut(duration: 0.35)) { captionOpacity = 0.9 }

        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(.easeOut(duration: 0.30)) {
            coreOpacity = 0
            captionOpacity = 0
            haloOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 320_000_000)
        onComplete()
    }
}
