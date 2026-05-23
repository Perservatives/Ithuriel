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

    /// Accessibility + screen recording — required for computer-use.
    var needsRequired: Bool {
        !(accessibilityGranted && screenRecordingGranted)
    }

    var needsAny: Bool {
        needsRequired || !notificationsGranted
    }

    private init() {}

    func refresh() async {
        accessibilityGranted = AXIsProcessTrusted()
        screenRecordingGranted = ScreenCapture.hasScreenRecordingAccess()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            notificationsGranted = true
        default:
            notificationsGranted = false
        }
        NotificationCenter.default.post(name: .ithurielPermissionsDidChange, object: nil)

        // TCC can lag briefly after returning from System Settings.
        if needsRequired {
            try? await Task.sleep(nanoseconds: 400_000_000)
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = ScreenCapture.hasScreenRecordingAccess()
            NotificationCenter.default.post(name: .ithurielPermissionsDidChange, object: nil)
        }
    }

    func requestAccessibility() {
        // Short-circuit if already granted — re-calling the prompt API
        // re-pops System Settings even when the checkbox is already on.
        if AXIsProcessTrusted() {
            accessibilityGranted = true
            NotificationCenter.default.post(name: .ithurielPermissionsDidChange, object: nil)
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
        if ScreenCapture.hasScreenRecordingAccess() {
            screenRecordingGranted = true
            NotificationCenter.default.post(name: .ithurielPermissionsDidChange, object: nil)
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
        // requestAuthorization only produces a prompt in .notDetermined.
        // Calling it after a denial just silently fails — feels like nagging.
        guard settings.authorizationStatus == .notDetermined else {
            await refresh()
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }

    private func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
