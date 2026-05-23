import SwiftUI
import AppKit

/// Dramatic boot sequence. Borderless transparent window in the centre of the
/// screen. The orb spins up, breathes once, fires an expanding ring, then
/// settles into the Spotlight prompt.
///
/// Timing (rare, first-time animation — Emil rule allows longer):
///   0.00   sound fires, orb fades in at scale 0.92
///   0.18   spin starts, accelerates
///   0.60   breathing pulse + first ring
///   1.05   second ring, peak glow
///   1.50   orb deflates 1.04→1.0, hands off to Spotlight
///   1.65   window closes
struct LaunchOrbView: View {
    @State private var rotation: Double = 0
    @State private var petalScale: CGFloat = 0.6
    @State private var coreOpacity: Double = 0
    @State private var coreScale: CGFloat = 0.92
    @State private var ring1Scale: CGFloat = 0.4
    @State private var ring1Opacity: Double = 0
    @State private var ring2Scale: CGFloat = 0.4
    @State private var ring2Opacity: Double = 0
    @State private var captionOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: () -> Void

    var body: some View {
        ZStack {
            // Expanding rings (decorative shockwave)
            ring(scale: ring1Scale, opacity: ring1Opacity, lineWidth: 1.5)
            ring(scale: ring2Scale, opacity: ring2Opacity, lineWidth: 1)

            // Outer halo — bigger, more dramatic
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.55),
                                 Color.accentColor.opacity(0.15),
                                 .clear],
                        center: .center,
                        startRadius: 4,
                        endRadius: 320
                    )
                )
                .frame(width: 640, height: 640)
                .opacity(coreOpacity)
                .blur(radius: 28)

            // The mark itself — much bigger
            AsteriskBurst(rotation: rotation, petalScale: petalScale, glowRadius: 60)
                .frame(width: 280, height: 280)
                .opacity(coreOpacity)
                .scaleEffect(coreScale)
                .shadow(color: .accentColor.opacity(0.6), radius: 30, y: 0)

            // Caption
            Text("ITHURIEL")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .tracking(14)
                .foregroundStyle(.primary.opacity(0.92))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .offset(y: 220)
                .opacity(captionOpacity)
        }
        .frame(width: 700, height: 700)
        .task { await runSequence() }
    }

    private func ring(scale: CGFloat, opacity: Double, lineWidth: CGFloat) -> some View {
        Circle()
            .strokeBorder(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: lineWidth
            )
            .frame(width: 520, height: 520)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private func runSequence() async {
        SoundPlayer.shared.play(.launch, volume: 0.55)

        // 0.00 — fade in
        withAnimation(.easeOut(duration: 0.32)) {
            coreOpacity = 1
            coreScale = 1
            petalScale = 1
        }
        await sleep(0.18)

        // 0.18 — spin up (accelerating)
        if reduceMotion {
            rotation = 360
        } else {
            withAnimation(.timingCurve(0.5, 0, 0.2, 1, duration: 1.2)) {
                rotation = 540
            }
        }

        await sleep(0.42)

        // 0.60 — breathing pulse + first ring fires
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)) {
            petalScale = 1.18
        }
        if !reduceMotion {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.0)) {
                ring1Scale = 1.7
                ring1Opacity = 0.0
            }
            ring1Opacity = 0.8
        }
        await sleep(0.18)

        // 0.78 — caption appears
        withAnimation(.easeOut(duration: 0.42)) { captionOpacity = 0.9 }

        await sleep(0.27)

        // 1.05 — second ring
        if !reduceMotion {
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.95)) {
                ring2Scale = 2.0
                ring2Opacity = 0.0
            }
            ring2Opacity = 0.55
        }

        // Petal settle
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)) {
            petalScale = 1.04
        }
        await sleep(0.45)

        // 1.50 — handoff
        withAnimation(.easeOut(duration: 0.28)) {
            coreOpacity = 0
            coreScale = 1.08
            captionOpacity = 0
        }
        await sleep(0.30)
        onComplete()
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
