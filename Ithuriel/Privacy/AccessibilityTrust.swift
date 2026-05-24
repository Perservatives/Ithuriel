import ApplicationServices
import CoreGraphics

/// Accessibility trust checks. `AXIsProcessTrusted()` often stays false for debug
/// builds even when control works; functional probes catch that case.
enum AccessibilityTrust {
    private static let cacheKey = "perm.accessibility"

    /// Sticky grant from a prior successful check — matches `PermissionsManager`.
    static func isGrantedCached() -> Bool {
        UserDefaults.standard.bool(forKey: cacheKey)
    }

    static func isGranted() -> Bool {
        if HackathonConfig.skipPermissionPrompts { return true }
        if isGrantedCached() { return true }
        if AXIsProcessTrusted() { return true }
        if functionalProbe() { return true }
        return eventTapProbe()
    }

    /// Persist a detected grant so flaky TCC probes stop nagging the user.
    static func markGranted() {
        UserDefaults.standard.set(true, forKey: cacheKey)
    }

    private static func functionalProbe() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedApplicationAttribute as CFString,
            &focused
        )
        return err == .success
    }

    /// Same capability HotkeyMonitor and keyboard/mouse control need.
    private static func eventTapProbe() -> Bool {
        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: nil
        ) else { return false }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        return true
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, _, event, _ in
        Unmanaged.passUnretained(event)
    }
}
