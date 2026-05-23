import SwiftUI

extension Color {
    /// Parses `#RRGGBB` or `#RRGGBBAA`. Falls back to the supplied default on
    /// malformed input — the launch animation should never crash because the
    /// user typed garbage into the color field.
    init(hex: String, fallback: Color = .accentColor) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let stripped = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard let value = UInt64(stripped, radix: 16),
              stripped.count == 6 || stripped.count == 8 else {
            self = fallback
            return
        }
        let r, g, b, a: Double
        if stripped.count == 6 {
            r = Double((value & 0xFF0000) >> 16) / 255.0
            g = Double((value & 0x00FF00) >>  8) / 255.0
            b = Double( value & 0x0000FF       ) / 255.0
            a = 1.0
        } else {
            r = Double((value & 0xFF000000) >> 24) / 255.0
            g = Double((value & 0x00FF0000) >> 16) / 255.0
            b = Double((value & 0x0000FF00) >>  8) / 255.0
            a = Double( value & 0x000000FF       ) / 255.0
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// `#RRGGBB`. Falls back to a sane default on conversion failure.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(ns.redComponent   * 255)).clamped(0, 255)
        let g = Int(round(ns.greenComponent * 255)).clamped(0, 255)
        let b = Int(round(ns.blueComponent  * 255)).clamped(0, 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.max(low, Swift.min(high, self)) }
}
