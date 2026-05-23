import SwiftUI
import AppKit

/// 8-shard brand reveal for the Ithuriel mark, executed to the canonical
/// "thing arrives" timing model from Material's deceleration curve, with a
/// radial micro-stagger between petals (15 ms apart) so the assembly reads
/// as motion rather than a snap. Total run time ≈ 1.10s; idle hand-off
/// behind that.
///
/// References (see research brief):
///   • Material entering-element curve: cubic-bezier(0.0, 0.0, 0.2, 1.0)
///   • Stagger between siblings: ≤ 20 ms (we use 15 ms)
///   • Spring overshoot settle:   cubic-bezier(0.34, 1.56, 0.64, 1)
///   • Reduce Motion variant:     opacity-only cross-fade, no transform
struct LaunchOrbView: View {
    /// Phase 0 = pre-arrival (shards out), 1 = arrived.
    @State private var arrived = false
    /// Soft overshoot scale of the assembled mark (1.08 → 1.0 settle).
    @State private var petalScale: CGFloat = 0.0
    /// Halo bloom pulse — runs in parallel with the convergence.
    @State private var haloScale: CGFloat = 0.4
    @State private var haloOpacity: Double = 0
    /// Final fade-out before handoff.
    @State private var coreOpacity: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tint: Color
    let onComplete: () -> Void

    init(tint: Color = .accentColor, onComplete: @escaping () -> Void) {
        self.tint = tint
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            // Halo — parallel pulse layer behind the petals.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0.06), .clear],
                        center: .center, startRadius: 6, endRadius: 240
                    )
                )
                .frame(width: 480, height: 480)
                .blur(radius: 24)
                .scaleEffect(haloScale)
                .opacity(haloOpacity)

            ForEach(0..<8) { i in
                shard(index: i)
            }
        }
        .frame(width: 700, height: 700)
        .opacity(coreOpacity)
        .task { await runSequence() }
    }

    // MARK: - Shard geometry

    private func shard(index i: Int) -> some View {
        let angle: Double = Double(i) * 45.0
        // Far state: pulled outward by 1.6× the assembled radius.
        // r ≈ 100pt assembled → 160pt extra travel.
        let pulled: CGFloat = arrived ? 0 : 160
        let dx: CGFloat = CGFloat(cos(angle * .pi / 180)) * pulled
        let dy: CGFloat = CGFloat(sin(angle * .pi / 180)) * pulled
        let fill: Color = i.isMultiple(of: 2) ? tint : tint.opacity(0.65)
        let alpha: Double = arrived ? 1 : 0

        return Petal()
            .fill(fill)
            .frame(width: 56, height: 200)
            .offset(y: -100)
            .rotationEffect(.degrees(angle - 90))
            // Travel from the periphery.
            .offset(x: dx, y: dy)
            .scaleEffect(petalScale)
            .opacity(alpha)
            // Per-petal delay creates the radial micro-stagger.
            .animation(
                .timingCurve(0.0, 0.0, 0.2, 1.0, duration: 0.55)
                    .delay(Double(i) * 0.015),
                value: arrived
            )
            .animation(.easeOut(duration: 0.3).delay(Double(i) * 0.015), value: petalScale)
    }

    // MARK: - Sequence

    private func runSequence() async {
        SoundPlayer.shared.play(.launch, volume: 0.5)

        if reduceMotion {
            // Cross-fade only — no transform motion.
            petalScale = 1.0
            arrived = true
            withAnimation(.easeOut(duration: 0.35)) {
                haloOpacity = 0.25
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.easeOut(duration: 0.28)) {
                coreOpacity = 0
                haloOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
            onComplete()
            return
        }

        // T=0 — kick off convergence. The shards animate via their .animation
        // modifier on `arrived`; this single flip cascades through the
        // 15ms stagger inside `shard(index:)`.
        arrived = true
        // Overshoot scale arrives at 1.08, settles to 1.0 in the SETTLE phase.
        withAnimation(.timingCurve(0.0, 0.0, 0.2, 1.0, duration: 0.55)) {
            petalScale = 1.08
        }

        // T=0.30 — halo bloom (parallel for 0.8s).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeInOut(duration: 0.8)) {
                haloScale = 1.6
                haloOpacity = 0
            }
            haloOpacity = 0.55
        }

        // T=0.55 — soft snap chime.
        try? await Task.sleep(nanoseconds: 550_000_000)
        SoundPlayer.shared.play(.done, volume: 0.32)

        // T=0.55 → 0.75 — settle with a tiny spring overshoot.
        withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.2)) {
            petalScale = 1.0
        }

        // T=0.95 → 1.10 — hold for a beat, then fade for handoff.
        try? await Task.sleep(nanoseconds: 400_000_000)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.28)) {
            coreOpacity = 0
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        onComplete()
    }
}
