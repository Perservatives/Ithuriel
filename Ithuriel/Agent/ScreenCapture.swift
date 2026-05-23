import Foundation
import CoreGraphics
import AppKit

/// Lightweight screenshot helper that returns a JPEG-encoded base64 string
/// for inline upload to Gemini. Uses CGDisplayCreateImage which is widely
/// available across macOS versions (deprecated in macOS 15 but functional).
enum ScreenCapture {
    /// `CGPreflightScreenCaptureAccess` can stay false after the user grants access
    /// (common with ad-hoc debug builds). Probe with a real capture when preflight fails.
    static func hasScreenRecordingAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return CGDisplayCreateImage(CGMainDisplayID()) != nil
    }

    static func mainDisplayJPEGBase64(maxWidth: CGFloat = 1280, quality: Double = 0.7) -> String? {
        let displayId = CGMainDisplayID()
        guard let cgImage = CGDisplayCreateImage(displayId) else { return nil }

        let original = NSBitmapImageRep(cgImage: cgImage)
        let scaled = downsample(original, maxWidth: maxWidth) ?? original

        let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: quality]
        guard let jpeg = scaled.representation(using: .jpeg, properties: props) else { return nil }
        return jpeg.base64EncodedString()
    }

    private static func downsample(_ rep: NSBitmapImageRep, maxWidth: CGFloat) -> NSBitmapImageRep? {
        let width = CGFloat(rep.pixelsWide)
        guard width > maxWidth else { return nil }
        let scale = maxWidth / width
        let newSize = NSSize(width: maxWidth, height: CGFloat(rep.pixelsHigh) * scale)
        let image = NSImage(size: newSize)
        image.lockFocus()
        rep.draw(in: NSRect(origin: .zero, size: newSize))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let newRep = NSBitmapImageRep(data: tiff) else { return nil }
        return newRep
    }
}
