import SwiftUI
import AppKit

/// Spinning 8-point brand mark — white AsteriskBurst at centre, wordmark beneath.
struct LaunchOrbView: View {
    @State private var petalScale: CGFloat = 0.35
    @State private var haloOpacity: Double = 0
    @State private var coreOpacity: Double = 1
    @State private var captionOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            SpinningBrandMark(size: 200, showRing: true, duration: 2.4)
                .scaleEffect(petalScale)
                .opacity(haloOpacity > 0 ? 1 : 0.6)

            Text(NSLocalizedString("launch.caption", comment: ""))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .tracking(9)
                .foregroundStyle(Color.white.opacity(0.92))
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
            petalScale = 1.0
            haloOpacity = 1.0
            captionOpacity = 0.9
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                coreOpacity = 0
                captionOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onComplete()
            return
        }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
            petalScale = 1.0
            haloOpacity = 1.0
        }

        try? await Task.sleep(nanoseconds: 400_000_000)
        SoundPlayer.shared.play(.done, volume: 0.32)
        withAnimation(.easeOut(duration: 0.35)) { captionOpacity = 0.9 }

        try? await Task.sleep(nanoseconds: 700_000_000)
        withAnimation(.easeOut(duration: 0.30)) {
            coreOpacity = 0
            captionOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 320_000_000)
        onComplete()
    }
}
