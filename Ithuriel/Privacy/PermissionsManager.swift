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

    var needsAny: Bool {
        !(accessibilityGranted && screenRecordingGranted && notificationsGranted)
    }

    private init() {}

    func refresh() async {
        accessibilityGranted = AXIsProcessTrusted()
        if #available(macOS 10.15, *) {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        } else {
            screenRecordingGranted = true
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsGranted = true
        default:
            notificationsGranted = false
        }
        NotificationCenter.default.post(name: .ithurielPermissionsDidChange, object: nil)
    }

    func requestAccessibility() {
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        Task { await refresh() }
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }
        Task { await refresh() }
    }

    func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    func requestNotifications() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
