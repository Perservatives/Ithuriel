import AppKit

/// Notch geometry helpers. On notch-equipped MacBooks the camera housing
/// reports as a non-zero `safeAreaInsets.top`. We use that as both the
/// presence signal and the height. Pre-notch Macs return `nil`.
enum NotchDetector {
    /// Notch height if the user's main screen has one, else nil.
    static func notchHeight(on screen: NSScreen? = .main) -> CGFloat? {
        guard let s = screen else { return nil }
        let inset = s.safeAreaInsets.top
        return inset > 0 ? inset : nil
    }

    /// Bounding rect of the notch in screen coordinates (Cocoa, origin
    /// bottom-left). Approximated as ~220pt wide centred on the screen top.
    static func notchRect(on screen: NSScreen? = .main) -> CGRect? {
        guard let s = screen, let h = notchHeight(on: s) else { return nil }
        let width: CGFloat = 220
        let frame = s.frame
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.maxY - h,
            width: width,
            height: h
        )
    }
}
