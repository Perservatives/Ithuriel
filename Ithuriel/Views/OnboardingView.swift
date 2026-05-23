import SwiftUI
import SwiftData
import AppKit

/// First-run onboarding. Three-step flow framed by the 8-point burst:
///   1. Welcome + Sign in with Google (Firebase)
///   2. Grant only the permissions that aren't already granted
///   3. Drop the user into the app
///
/// Persists completion to `UserPrefs.onboardingComplete`. Lazy permission
/// requests — never asks for what's already granted.
struct OnboardingView: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @State private var step: Step = .welcome
    @State private var iconRotation: Double = 0

    let onFinish: () -> Void

    enum Step { case welcome, signIn, hotkey, permissions, done }

    private var prefs: UserPrefs? { prefsList.first }

    var body: some View {
        VStack(spacing: 0) {
            // Decorative top: the 8-point mark, always present, slowly orbiting.
            VStack(spacing: 14) {
                AsteriskMark(size: 64, tint: .accentColor)
                    .rotationEffect(.degrees(iconRotation))
                Text("Ithuriel")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .tracking(2)
            }
            .padding(.top, 56)
            .padding(.bottom, 32)

            Divider().opacity(0.25)

            ScrollView {
                content
                    .padding(40)
                    .frame(maxWidth: 480, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }

            footer
        }
        .frame(width: 540, height: 600)
        .background(VisualEffectBlur(material: .popover, blendingMode: .behindWindow))
        .onAppear {
            withAnimation(.linear(duration: 64).repeatForever(autoreverses: false)) {
                iconRotation = 360
            }
            Task { await permissions.refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcomeStep
        case .signIn:      signInStep
        case .hotkey:      hotkeyStep
        case .permissions: permissionsStep
        case .done:        Color.clear.onAppear { onFinish() }
        }
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick your shortcut")
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text("Press the key combination you want to use to summon Ithuriel from anywhere. The default is ⌃Space.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let prefs {
                HotkeyPickerView(
                    keyCode: Binding(get: { prefs.hotkeyKeyCode },
                                     set: { prefs.hotkeyKeyCode = $0; try? context.save(); pushHotkey() }),
                    modifiers: Binding(get: { prefs.hotkeyModifiers },
                                       set: { prefs.hotkeyModifiers = $0; try? context.save(); pushHotkey() })
                )
                .padding(.top, 4)
                Text("Hold the shortcut to talk; tap to type. You can change this any time in Settings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func pushHotkey() {
        guard let prefs else { return }
        HotkeyMonitor.shared.updateBinding(keyCode: prefs.hotkeyKeyCode, modifiers: prefs.hotkeyModifiers)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("onboarding.welcome.title", comment: ""))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(NSLocalizedString("onboarding.welcome.body", comment: ""))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            bullet("⌃Space", NSLocalizedString("onboarding.welcome.summon", comment: ""))
            bullet(NSLocalizedString("onboarding.welcome.holdLabel", comment: ""),
                   NSLocalizedString("onboarding.welcome.voice", comment: ""))
            bullet("⌃⌥⌘.", NSLocalizedString("onboarding.welcome.kill", comment: ""))
        }
    }

    private var signInStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("onboarding.signIn.title", comment: ""))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(NSLocalizedString("onboarding.signIn.body", comment: ""))
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if AuthService.shared.isSignedIn {
                Label(NSLocalizedString("onboarding.signIn.connected", comment: ""),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    AuthService.shared.beginGoogleSignIn()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "g.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                        Text(NSLocalizedString("onboarding.signIn.button", comment: ""))
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Text(NSLocalizedString("onboarding.signIn.optional", comment: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("onboarding.permissions.title", comment: ""))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(NSLocalizedString("onboarding.permissions.body", comment: ""))
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !permissions.accessibilityGranted {
                permissionCard(
                    title: NSLocalizedString("settings.permissions.accessibility.title", comment: ""),
                    detail: NSLocalizedString("settings.permissions.accessibility.detail", comment: ""),
                    symbol: "hand.tap.fill",
                    action: { permissions.requestAccessibility() }
                )
            }
            if !permissions.screenRecordingGranted {
                permissionCard(
                    title: NSLocalizedString("settings.permissions.screen.title", comment: ""),
                    detail: NSLocalizedString("settings.permissions.screen.detail", comment: ""),
                    symbol: "rectangle.dashed.badge.record",
                    action: { permissions.requestScreenRecording() }
                )
            }
            if !permissions.notificationsGranted {
                permissionCard(
                    title: NSLocalizedString("settings.permissions.notifications.title", comment: ""),
                    detail: NSLocalizedString("settings.permissions.notifications.detail", comment: ""),
                    symbol: "bell.badge",
                    action: { Task { await permissions.requestNotifications() } }
                )
            }
            if !permissions.needsRequired && permissions.notificationsGranted {
                Label(NSLocalizedString("settings.permissions.allGranted", comment: ""),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func permissionCard(title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(NSLocalizedString("settings.permissions.enable", comment: ""), action: action)
                .controlSize(.regular)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func bullet(_ chip: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(chip)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.primary.opacity(0.06))
                )
            Text(text).font(.system(size: 14))
        }
    }

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button(NSLocalizedString("onboarding.back", comment: "")) { back() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: forward) {
                Text(forwardLabel)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    private var forwardLabel: String {
        switch step {
        case .welcome:     return NSLocalizedString("onboarding.next", comment: "")
        case .signIn:      return AuthService.shared.isSignedIn
            ? NSLocalizedString("onboarding.next", comment: "")
            : NSLocalizedString("onboarding.skip", comment: "")
        case .hotkey:      return NSLocalizedString("onboarding.next", comment: "")
        case .permissions: return NSLocalizedString("onboarding.start", comment: "")
        case .done:        return ""
        }
    }

    private func forward() {
        switch step {
        case .welcome:     step = .signIn
        case .signIn:      step = .hotkey
        case .hotkey:      step = .permissions
        case .permissions: complete()
        case .done:        break
        }
    }

    private func back() {
        switch step {
        case .signIn:      step = .welcome
        case .hotkey:      step = .signIn
        case .permissions: step = .hotkey
        default: break
        }
    }

    private func complete() {
        if let prefs {
            prefs.onboardingComplete = true
            try? context.save()
        }
        step = .done
    }
}
