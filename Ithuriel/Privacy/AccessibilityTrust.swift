import ApplicationServices

/// Accessibility trust checks. `AXIsProcessTrusted()` often stays false for debug
/// builds even when control works; a functional AX probe catches that case.
enum AccessibilityTrust {
    static func isGranted() -> Bool {
        if AXIsProcessTrusted() { return true }
        return functionalProbe()
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
}
