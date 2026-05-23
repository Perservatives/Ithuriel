import SwiftUI
import AppKit

/// Calm boot sequence — eight shards of the 8-point star drift in slowly from
/// far outside the centre and assemble into the mark. The screen is fully
/// darkened (see LaunchBackdropView); there is no caption text and no
/// vibrant colour bloom. The whole sequence runs ~3.0s, biased toward slow
/// inward motion rather than dramatic flashes.
struct LaunchOrbView: View {
    @State private var convergence: Double = 0     // 0 = far, 1 = snapped
    @State private var petalScale: CGFloat = 1
    @State private var coreOpacity: Double = 0
    @State private var rotation: Double = 0
    @State private var snapHaloOpacity: Double = 0
    @State private var snapHaloScale: CGFloat = 0.6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color
    let onComplete: () -> Void

    init(tint: Color = .accentColor, onComplete: @escaping () -> Void) {
        self.tint = tint
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            // Subtle halo that blooms only when the shards meet.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0.06), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .blur(radius: 24)
                .scaleEffect(snapHaloScale)
                .opacity(snapHaloOpacity)

            // Eight shards converging.
            ForEach(0..<8) { i in
                shard(index: i)
            }
        }
        .frame(width: 700, height: 700)
        .task { await runSequence() }
    }

    private func shard(index i: Int) -> some View {
        let angle: Double = Double(i) * 45.0
        let invert: Double = 1.0 - convergence
        // Travel from well off-screen so the inward drift reads.
        let travel: CGFloat = 720
        let dx: CGFloat = CGFloat(cos(angle * .pi / 180)) * travel * CGFloat(invert)
        let dy: CGFloat = CGFloat(sin(angle * .pi / 180)) * travel * CGFloat(invert)
        let fill: Color = i.isMultiple(of: 2) ? tint : tint.opacity(0.65)
        // A tiny amount of extra rotation while travelling, settled to 0.
        let extraRot: Double = -90.0 * invert
        let scale: CGFloat = CGFloat(0.78 + 0.22 * convergence) + (petalScale - 1) * 0.2
        let alpha: Double = coreOpacity * (0.25 + 0.75 * convergence)

        return Petal()
            .fill(fill)
            .frame(width: 56, height: 200)
            .offset(y: -100 * petalScale)
            .rotationEffect(.degrees(angle - 90))
            .offset(x: dx, y: dy)
            .rotationEffect(.degrees(rotation + extraRot))
            .scaleEffect(scale)
            .opacity(alpha)
    }

    private func runSequence() async {
        SoundPlayer.shared.play(.launch, volume: 0.45)

        // 0.00 — shards fade in while still spread out.
        withAnimation(.easeOut(duration: 0.55)) { coreOpacity = 1 }

        // 0.10 — slow convergence. ~1.7 seconds of inward drift. The strong
        // late-bias curve keeps motion gentle, never abrupt.
        if reduceMotion {
            convergence = 1
        } else {
            withAnimation(.timingCurve(0.18, 0.7, 0.22, 1, duration: 1.7)) {
                convergence = 1
            }
        }
        await sleep(1.65)

        // 1.65 — soft snap. Halo blooms briefly, petals breathe out and in.
        SoundPlayer.shared.play(.done, volume: 0.35)
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.8)) {
            snapHaloScale = 1.45
            snapHaloOpacity = 0
        }
        snapHaloOpacity = 0.6
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.42)) {
            petalScale = 1.10
        }
        await sleep(0.35)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.38)) {
            petalScale = 1.0
        }

        // 2.40 — single gentle 12° tilt to give the mark life before handoff.
        if !reduceMotion {
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.55)) {
                rotation = 12
            }
        }
        await sleep(0.50)

        // 2.90 — fade out into Spotlight.
        withAnimation(.easeOut(duration: 0.32)) {
            coreOpacity = 0
        }
        await sleep(0.34)
        onComplete()
    }

    private func sleep(_ s: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
    }
}
