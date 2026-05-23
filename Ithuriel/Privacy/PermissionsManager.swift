import AppKit
import ApplicationServices
import UserNotifications

extension Notification.Name {
    static let ithurielPermissionsDidChange = Notification.Name("IthurielPermissionsDidChange")
}

/// Tracks macOS permissions and requests them only when the user asks in Settings.
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var notificationsGranted = false
    /// False until the first `refresh()` finishes — avoids flashing “missing” UI on launch.
    @Published private(set) var hasRefreshed = false

    /// Accessibility + screen recording — required for computer-use.
    var needsRequired: Bool {
        !(accessibilityGranted && screenRecordingGranted)
    }

    private init() {}

    func refresh() async {
        await measureAndPublish(retryIfMissing: true)
        hasRefreshed = true
    }

    func requestAccessibility() {
        if AccessibilityTrust.isGranted() {
            apply(accessibility: true, screen: screenRecordingGranted, notifications: notificationsGranted)
            return
        }
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        Task { await refresh() }
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        if ScreenCapture.hasScreenRecordingAccessNow() {
            apply(accessibility: accessibilityGranted, screen: true, notifications: notificationsGranted)
            return
        }
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }
        Task { await refresh() }
    }

    func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    func requestNotifications() async {
        if notificationsGranted { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            await measureAndPublish(retryIfMissing: false)
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await measureAndPublish(retryIfMissing: false)
    }

    // MARK: - Private

    private func measureAndPublish(retryIfMissing: Bool) async {
        var a11y = AccessibilityTrust.isGranted()
        var screen = await ScreenCapture.hasScreenRecordingAccess()
        let notifications = await measureNotifications()

        apply(accessibility: a11y, screen: screen, notifications: notifications)

        guard retryIfMissing, needsRequired else { return }

        // TCC can lag briefly after returning from System Settings.
        for _ in 0..<3 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            a11y = AccessibilityTrust.isGranted()
            screen = await ScreenCapture.hasScreenRecordingAccess()
            apply(accessibility: a11y, screen: screen, notifications: notifications)
            if !needsRequired { break }
        }
    }

    private func measureNotifications() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private func apply(accessibility: Bool, screen: Bool, notifications: Bool) {
        let changed = accessibilityGranted != accessibility
            || screenRecordingGranted != screen
            || notificationsGranted != notifications
        accessibilityGranted = accessibility
        screenRecordingGranted = screen
        notificationsGranted = notifications
        if changed {
            NotificationCenter.default.post(name: .ithurielPermissionsDidChange, object: nil)
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
