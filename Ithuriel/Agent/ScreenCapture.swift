import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

/// Lightweight screenshot helper that returns a JPEG-encoded base64 string
/// for inline upload to Gemini. Uses CGDisplayCreateImage which is widely
/// available across macOS versions (deprecated in macOS 15 but functional).
enum ScreenCapture {
    /// Same key as `PermissionsManager` — one source of truth for cached screen-recording grant.
    private static let verifiedKey = "perm.screenRecording"

    /// Non-intrusive — safe to call from periodic UI refresh. Never opens a TCC dialog.
    static func hasScreenRecordingAccessPassive() -> Bool {
        if HackathonConfig.skipPermissionPrompts { return true }
        if CGPreflightScreenCaptureAccess() { return true }
        let ud = UserDefaults.standard
        if ud.bool(forKey: verifiedKey) { return true }
        // Legacy key from earlier builds.
        return ud.bool(forKey: "perm.screenRecordingVerified")
    }

    /// Full probe for Settings "Enable" and first-time verification. May trigger TCC once.
    static func hasScreenRecordingAccess() async -> Bool {
        if HackathonConfig.skipPermissionPrompts { return true }
        if CGPreflightScreenCaptureAccess() { return true }
        if captureMainDisplayImage() != nil {
            markVerified()
            return true
        }
        if #available(macOS 12.3, *) {
            let ok = await screenCaptureKitProbe()
            if ok { markVerified() }
            return ok
        }
        return false
    }

    /// Synchronous check before an agent screenshot — no `CGRequestScreenCaptureAccess`.
    static func hasScreenRecordingAccessNow() -> Bool {
        hasScreenRecordingAccessPassive()
    }

    static func mainDisplayJPEGBase64(maxWidth: CGFloat = 1280, quality: Double = 0.7) -> String? {
        if !HackathonConfig.skipPermissionPrompts,
           !hasScreenRecordingAccessNow() { return nil }
        guard let cgImage = captureMainDisplayImage() else { return nil }
        markVerified()

        let original = NSBitmapImageRep(cgImage: cgImage)
        let scaled = downsample(original, maxWidth: maxWidth) ?? original

        let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: quality]
        guard let jpeg = scaled.representation(using: .jpeg, properties: props) else { return nil }
        return jpeg.base64EncodedString()
    }

    private static func captureMainDisplayImage() -> CGImage? {
        CGDisplayCreateImage(CGMainDisplayID())
    }

    private static func markVerified() {
        UserDefaults.standard.set(true, forKey: verifiedKey)
    }

    @available(macOS 12.3, *)
    private static func screenCaptureKitProbe() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
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
