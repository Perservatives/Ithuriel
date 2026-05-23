import SwiftUI
import AppKit

/// Shards-converging boot sequence. Eight petal shards fly in from outside
/// the screen, each from a different angle, converging on the centre and
/// snapping into formation as the 8-pointed Ithuriel mark. Then a single
/// spin and breath, and the orb hands off to the Spotlight.
///
/// Timing (rare/first-time animation):
///   0.00   shards spawn far from centre, transparent, large
///   0.05   travel inward with ease-out, rotating
///   0.85   all eight shards snap together — flash + scale pop
///   1.10   short spin + breath
///   1.55   fade and hand off
struct LaunchOrbView: View {
    @State private var convergence: Double = 0   // 0 = far out, 1 = snapped
    @State private var rotation: Double = 0
    @State private var petalScale: CGFloat = 1
    @State private var coreOpacity: Double = 0
    @State private var captionOpacity: Double = 0
    @State private var snapFlashOpacity: Double = 0
    @State private var snapFlashScale: CGFloat = 0.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color
    let onComplete: () -> Void

    init(tint: Color = .accentColor, onComplete: @escaping () -> Void) {
        self.tint = tint
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            // The expanding flash that fires the moment all shards meet.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.65), tint.opacity(0.1), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 280
                    )
                )
                .frame(width: 560, height: 560)
                .blur(radius: 30)
                .scaleEffect(snapFlashScale)
                .opacity(snapFlashOpacity)

            // The eight shards. Each renders independently with its own
            // off-screen origin so it sweeps in from a unique direction.
            ForEach(0..<8) { i in
                shard(index: i)
            }

            // Caption that fades in after the snap.
            Text("ITHURIEL")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .tracking(14)
                .foregroundStyle(.primary.opacity(0.92))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .offset(y: 240)
                .opacity(captionOpacity)
        }
        .frame(width: 700, height: 700)
        .task { await runSequence() }
    }

    // MARK: - Shard rendering

    private func shard(index i: Int) -> some View {
        let angle: Double = Double(i) * 45.0
        let invert: Double = 1.0 - convergence
        let travel: CGFloat = 520
        let dx: CGFloat = CGFloat(cos(angle * .pi / 180)) * travel * CGFloat(invert)
        let dy: CGFloat = CGFloat(sin(angle * .pi / 180)) * travel * CGFloat(invert)
        let fill: Color = i.isMultiple(of: 2) ? tint : tint.opacity(0.55)
        let extraRot: Double = -240.0 * invert
        let scale: CGFloat = CGFloat(0.6 + 0.4 * convergence) + (petalScale - 1) * 0.2
        let shadowAlpha: Double = 0.6 * convergence
        let alpha: Double = coreOpacity * (0.3 + 0.7 * convergence)

        return Petal()
            .fill(fill)
            .frame(width: 60, height: 200)
            .offset(y: -100 * petalScale)
            .rotationEffect(.degrees(angle - 90))
            .offset(x: dx, y: dy)
            .rotationEffect(.degrees(rotation + extraRot))
            .scaleEffect(scale)
            .opacity(alpha)
            .shadow(color: tint.opacity(shadowAlpha), radius: 18, y: 0)
    }

    // MARK: - Sequence

    private func runSequence() async {
        SoundPlayer.shared.play(.launch, volume: 0.55)

        // 0.00 — fade shards in (still far from centre)
        withAnimation(.easeOut(duration: 0.28)) {
            coreOpacity = 1
        }

        // 0.05 — converge. 0.80s for the shards to glide together.
        if reduceMotion {
            convergence = 1
            rotation = 0
        } else {
            withAnimation(.timingCurve(0.18, 0.9, 0.28, 1, duration: 0.80)) {
                convergence = 1
            }
            // Mid-flight rotation builds momentum, settles to 0 on snap.
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.80)) {
                rotation = 0  // baseline (we use invert-modulated extra rotation)
            }
        }

        await sleep(0.78)

        // 0.78 — snap! Flash + petal pop + brief over-spin.
        SoundPlayer.shared.play(.done, volume: 0.45)
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.55)) {
            snapFlashScale = 1.6
            snapFlashOpacity = 0
        }
        snapFlashOpacity = 0.85
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)) {
            petalScale = 1.18
        }
        await sleep(0.16)
        withAnimation(.easeOut(duration: 0.42)) { captionOpacity = 0.9 }

        // 1.10 — single graceful spin
        if !reduceMotion {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.6)) {
                rotation = 22  // tiny pleasing tilt
            }
        }
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.32)) {
            petalScale = 1.04
        }
        await sleep(0.45)

        // 1.55 — handoff
        withAnimation(.easeOut(duration: 0.28)) {
            coreOpacity = 0
            captionOpacity = 0
        }
        await sleep(0.30)
        onComplete()
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
