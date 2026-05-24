import AppKit
import ApplicationServices
import UserNotifications

extension Notification.Name {
    static let ithurielPermissionsDidChange = Notification.Name("IthurielPermissionsDidChange")
}

/// Tracks macOS permissions. Never opens TCC dialogs except when the user taps
/// Enable in Settings or onboarding (unless `HackathonConfig.skipPermissionPrompts`).
@MainActor
final class PermissionsManager: ObservableObject {
    static let shared = PermissionsManager()

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var notificationsGranted = false
    /// False until the first `refresh()` finishes — avoids flashing "missing" UI on launch.
    @Published private(set) var hasRefreshed = false

    /// Accessibility + screen recording — required for computer-use.
    var needsRequired: Bool {
        if HackathonConfig.skipPermissionPrompts { return false }
        return !(accessibilityGranted && screenRecordingGranted)
    }

    private enum CacheKey {
        static let accessibility         = "perm.accessibility"
        static let accessibilityPrompted = "perm.accessibilityPrompted"
        static let screenRecording       = "perm.screenRecording"
        static let notifications         = "perm.notifications"
    }

    private var pollTask: Task<Void, Never>?
    private var lastPassiveRefresh = Date.distantPast
    private static let passiveRefreshMinInterval: TimeInterval = 45

    private init() {
        if HackathonConfig.skipPermissionPrompts {
            apply(accessibility: true, screen: true, notifications: true)
            hasRefreshed = true
            AccessibilityTrust.markGranted()
            return
        }

        let ud = UserDefaults.standard
        accessibilityGranted   = ud.bool(forKey: CacheKey.accessibility)
        screenRecordingGranted = ud.bool(forKey: CacheKey.screenRecording)
        notificationsGranted   = ud.bool(forKey: CacheKey.notifications)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                await PermissionsManager.shared.refresh(force: true)
            }
        }
    }

    /// Passive status check — no TCC prompts. Safe on a timer or `didBecomeActive`.
    func refresh(force: Bool = false) async {
        if HackathonConfig.skipPermissionPrompts {
            apply(accessibility: true, screen: true, notifications: true)
            hasRefreshed = true
            return
        }
        let now = Date()
        let firstRefresh = !hasRefreshed
        if !force, !firstRefresh,
           now.timeIntervalSince(lastPassiveRefresh) < Self.passiveRefreshMinInterval {
            return
        }
        lastPassiveRefresh = now
        await measureAndPublish(probeScreen: firstRefresh || force)
        hasRefreshed = true
    }

    /// After the user taps Enable — may show the system dialog once, then poll quietly.
    func refreshAfterUserRequest() async {
        if HackathonConfig.skipPermissionPrompts {
            apply(accessibility: true, screen: true, notifications: true)
            hasRefreshed = true
            return
        }
        lastPassiveRefresh = .distantPast
        await measureAndPublish(probeScreen: true)
        hasRefreshed = true
        startPermissionPolling()
    }

    func requestAccessibility() {
        if HackathonConfig.skipPermissionPrompts {
            apply(accessibility: true, screen: true, notifications: true)
            return
        }
        if accessibilityGranted || AccessibilityTrust.isGranted() {
            AccessibilityTrust.markGranted()
            apply(accessibility: true, screen: screenRecordingGranted, notifications: notificationsGranted)
            return
        }
        if UserDefaults.standard.bool(forKey: CacheKey.accessibilityPrompted) {
            openAccessibilitySettings()
            Task { await refreshAfterUserRequest() }
            return
        }
        UserDefaults.standard.set(true, forKey: CacheKey.accessibilityPrompted)
        let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
        Task { await refreshAfterUserRequest() }
    }

    func openAccessibilitySettings() {
        guard !HackathonConfig.skipPermissionPrompts else { return }
        openPrivacyPane("Privacy_Accessibility")
    }

    func requestScreenRecording() {
        if HackathonConfig.skipPermissionPrompts {
            apply(accessibility: true, screen: true, notifications: true)
            return
        }
        if screenRecordingGranted || ScreenCapture.hasScreenRecordingAccessPassive() {
            apply(accessibility: accessibilityGranted, screen: true, notifications: notificationsGranted)
            return
        }
        if #available(macOS 10.15, *) {
            if CGPreflightScreenCaptureAccess() {
                apply(accessibility: accessibilityGranted, screen: true, notifications: notificationsGranted)
                return
            }
            _ = CGRequestScreenCaptureAccess()
        }
        Task { await refreshAfterUserRequest() }
    }

    func openScreenRecordingSettings() {
        guard !HackathonConfig.skipPermissionPrompts else { return }
        openPrivacyPane("Privacy_ScreenCapture")
    }

    func requestNotifications() async {
        if HackathonConfig.skipPermissionPrompts {
            apply(accessibility: true, screen: true, notifications: true)
            return
        }
        if notificationsGranted { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            apply(accessibility: accessibilityGranted, screen: screenRecordingGranted, notifications: true)
            return
        case .denied:
            await measureAndPublish(probeScreen: false)
            return
        default:
            break
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await measureAndPublish(probeScreen: false)
    }

    // MARK: - Private

    private func measureAndPublish(probeScreen: Bool) async {
        let a11yCheck = AccessibilityTrust.isGranted()
        let screenCheck: Bool
        if probeScreen {
            screenCheck = await ScreenCapture.hasScreenRecordingAccess()
        } else {
            screenCheck = ScreenCapture.hasScreenRecordingAccessPassive()
        }
        let notifications = await measureNotifications()

        let a11y = a11yCheck || accessibilityGranted
        let screen = screenCheck || screenRecordingGranted
        if a11yCheck { AccessibilityTrust.markGranted() }

        apply(accessibility: a11y, screen: screen, notifications: notifications)
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

    private func startPermissionPolling() {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<15 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await measureAndPublish(probeScreen: true)
                if !needsRequired { break }
            }
        }
    }

    private func apply(accessibility: Bool, screen: Bool, notifications: Bool) {
        let changed = accessibilityGranted != accessibility
            || screenRecordingGranted != screen
            || notificationsGranted != notifications
        accessibilityGranted = accessibility
        screenRecordingGranted = screen
        notificationsGranted = notifications
        let ud = UserDefaults.standard
        ud.set(accessibility,   forKey: CacheKey.accessibility)
        ud.set(screen,          forKey: CacheKey.screenRecording)
        ud.set(notifications,   forKey: CacheKey.notifications)
        ud.synchronize()
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
