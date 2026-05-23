import SwiftUI

/// The Ithuriel mark — an 8-pointed burst inspired by the RuFlo asterisk.
/// Two interleaved 4-pointers, each petal a slim teardrop with a soft glow.
/// Used both as a brand icon and as the spinning core of the launch animation.
struct AsteriskBurst: View {
    /// Rotation in degrees, drives the orbiting effect when animated.
    var rotation: Double = 0
    /// Outer scale of each petal (used for the breathing/burst).
    var petalScale: CGFloat = 1
    /// Petal fill — accent by default.
    var tint: Color = .accentColor
    var secondaryTint: Color = .accentColor.opacity(0.55)
    var glowRadius: CGFloat = 18

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let petal = Petal()
            ZStack {
                ForEach(0..<8) { i in
                    petal
                        .fill(i.isMultiple(of: 2) ? tint : secondaryTint)
                        .frame(width: side * 0.18, height: side * 0.48 * petalScale)
                        .offset(y: -side * 0.18)
                        .rotationEffect(.degrees(Double(i) * 45))
                }
            }
            .frame(width: side, height: side)
            .rotationEffect(.degrees(rotation))
            .shadow(color: tint.opacity(0.55), radius: glowRadius)
            .shadow(color: tint.opacity(0.35), radius: glowRadius * 0.4)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

/// Compact 8-point asterisk for inline UI (sidebar header, message author).
/// Same Petal shape, no halo or glow. `size` is the total mark diameter.
struct AsteriskMark: View {
    var size: CGFloat = 12
    var tint: Color = .accentColor

    var body: some View {
        let petalLen = size * 0.5
        let petalWid = size * 0.22
        return ZStack {
            ForEach(0..<8) { i in
                Petal()
                    .fill(tint)
                    .frame(width: petalWid, height: petalLen)
                    .offset(y: -petalLen / 2)
                    .rotationEffect(.degrees(Double(i) * 45))
            }
        }
        .frame(width: size, height: size)
    }
}

/// A single teardrop-shaped petal. Wide at the centre, tapered at the tip.
struct Petal: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let cx = rect.midX
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addQuadCurve(
            to: CGPoint(x: cx, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.midY + h * 0.05)
        )
        p.addQuadCurve(
            to: CGPoint(x: cx, y: rect.minY),
            control: CGPoint(x: rect.maxX, y: rect.midY + h * 0.05)
        )
        p.closeSubpath()
        _ = w
        return p
    }
}
