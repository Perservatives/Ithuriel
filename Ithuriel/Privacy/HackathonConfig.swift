import Foundation

/// Hackathon demo mode — flip `skipPermissionPrompts` to `false` after the demo.
///
/// When enabled:
///   - No Keychain reads or writes (no "confidential information" sheet)
///   - No TCC permission probes or system dialogs
///   - No in-app permission banners or onboarding permission step
///   - API keys come from SwiftData `UserPrefs` only (paste in Settings)
enum HackathonConfig {
    static let skipPermissionPrompts = true
}
