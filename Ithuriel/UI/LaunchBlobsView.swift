import SwiftUI

/// Arc-browser-inspired startup overlay. Full-screen black, then six soft
/// blurred color "blobs" bloom in from offscreen, drift and breathe, then
/// fade. Everything underneath reads as black-with-light during the show.
///
/// The blobs use the user's chosen `baseColor` (UserPrefs.launchColorHex)
/// plus two analogous hue siblings, so the palette feels intentional
/// regardless of which color the user picks.
struct LaunchBlobsView: View {
    let baseColor: Color

    @State private var phase: CGFloat = 0     // 0 → 1 over the run
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                ForEach(Array(blobs.enumerated()), id: \.offset) { _, blob in
                    Blob(spec: blob,
                         phase: phase,
                         canvas: geo.size,
                         rotation: rotation,
                         reduceMotion: reduceMotion)
                }

                // Subtle grain — keeps the blur from looking too plasticky.
                Color.white.opacity(0.015)
                    .blendMode(.overlay)
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .compositingGroup()
        .drawingGroup() // GPU-composite the whole stack; blur is expensive otherwise
        .onAppear { runSequence() }
    }

    private var palette: [Color] {
        // Base + two analogous siblings (±30° hue) — Arc-style trio.
        let ns = NSColor(baseColor).usingColorSpace(.sRGB) ?? NSColor(baseColor)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        let s2 = min(max(s, 0.55), 0.95)
        let b2 = min(max(br, 0.85), 1.0)
        let warm = NSColor(hue: rot(h, +30/360), saturation: s2, brightness: b2, alpha: 1)
        let cool = NSColor(hue: rot(h, -30/360), saturation: s2, brightness: b2, alpha: 1)
        let core = NSColor(hue: h,               saturation: s2, brightness: b2, alpha: 1)
        return [Color(core), Color(warm), Color(cool)]
    }

    private func rot(_ h: CGFloat, _ d: CGFloat) -> CGFloat {
        var x = h + d
        while x < 0 { x += 1 }
        while x > 1 { x -= 1 }
        return x
    }

    private var blobs: [BlobSpec] {
        let p = palette
        // Hand-tuned constellation. Normalised coords (0…1) so it scales
        // to any screen. Sizes are fractions of min(width,height).
        return [
            .init(color: p[0], home: .init(x: 0.50, y: 0.45), size: 0.95, delay: 0.00, drift: .init(x:  0.04, y: -0.03)),
            .init(color: p[1], home: .init(x: 0.18, y: 0.32), size: 0.72, delay: 0.10, drift: .init(x: -0.05, y:  0.04)),
            .init(color: p[2], home: .init(x: 0.82, y: 0.28), size: 0.70, delay: 0.14, drift: .init(x:  0.06, y:  0.05)),
            .init(color: p[1], home: .init(x: 0.28, y: 0.78), size: 0.62, delay: 0.22, drift: .init(x:  0.03, y: -0.06)),
            .init(color: p[2], home: .init(x: 0.78, y: 0.74), size: 0.66, delay: 0.18, drift: .init(x: -0.04, y: -0.05)),
            .init(color: p[0], home: .init(x: 0.50, y: 0.92), size: 0.55, delay: 0.30, drift: .init(x:  0.00, y: -0.07)),
        ]
    }

    private func runSequence() {
        guard !reduceMotion else { phase = 1; return }
        // Slow, intentional bloom. 1.4s to fill, then drift/breathe.
        withAnimation(.timingCurve(0.16, 0.7, 0.2, 1, duration: 1.4)) {
            phase = 1
        }
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

// MARK: - Blob

private struct BlobSpec {
    let color: Color
    let home: CGPoint        // normalised (0…1)
    let size: CGFloat        // fraction of min(width,height)
    let delay: Double        // seconds before this blob starts blooming
    let drift: CGPoint       // normalised drift vector during breathing
}

private struct Blob: View {
    let spec: BlobSpec
    let phase: CGFloat
    let canvas: CGSize
    let rotation: Double
    let reduceMotion: Bool

    @State private var bloomed: Bool = false
    @State private var breath: CGFloat = 0

    var body: some View {
        let minSide = min(canvas.width, canvas.height)
        let diameter = spec.size * minSide * 1.6 // oversize because the blur eats the edges
        let breatheScale = reduceMotion ? 1.0 : (1.0 + 0.06 * sin(breath))
        let driftX = (reduceMotion ? 0 : spec.drift.x * sin(breath * 0.7)) * canvas.width
        let driftY = (reduceMotion ? 0 : spec.drift.y * cos(breath * 0.8)) * canvas.height
        let cx = spec.home.x * canvas.width + driftX
        let cy = spec.home.y * canvas.height + driftY

        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        spec.color.opacity(0.95),
                        spec.color.opacity(0.55),
                        spec.color.opacity(0.18),
                        .clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(bloomed ? breatheScale : 0.55)
            .opacity(Double(bloomed ? 1.0 : 0.0))
            .blur(radius: minSide * 0.08) // softness scales with screen
            .blendMode(.plusLighter)      // colors add instead of muddying
            .rotationEffect(.degrees(rotation * 0.05)) // imperceptible turn
            .position(x: cx, y: cy)
            .task { await schedule() }
    }

    private func schedule() async {
        try? await Task.sleep(nanoseconds: UInt64(spec.delay * 1_000_000_000))
        withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.6)) {
            bloomed = true
        }
        guard !reduceMotion else { return }
        // Continuous slow breathing — drives both scale and drift via sin().
        withAnimation(.easeInOut(duration: 7).repeatForever(autoreverses: true)) {
            breath = .pi * 2
        }
    }
}
