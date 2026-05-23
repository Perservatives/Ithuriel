import SwiftUI
import SwiftData

/// Shared controls formerly in the menu-bar popover: chat, copy, mute, settings, quit.
struct AppChromeBar: View {
    @Environment(\.modelContext) private var context
    @Query private var prefsList: [UserPrefs]
    @ObservedObject private var permissions = PermissionsManager.shared
    @State private var copyStatus: String?

    var compact: Bool = false

    private var prefs: UserPrefs? { prefsList.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: compact ? 10 : 12) {
                Button(action: { AppRouter.shared.openChat() }) {
                    if compact {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    } else {
                        Label(NSLocalizedString("spotlight.openChat", comment: ""), systemImage: "bubble.left.and.bubble.right.fill")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: copyContext) {
                    Label(NSLocalizedString("status.copy", comment: ""), systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(NSLocalizedString("status.copy", comment: ""))

                Button(action: { SoundPlayer.shared.muted.toggle() }) {
                    Image(systemName: SoundPlayer.shared.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(SoundPlayer.shared.muted
                      ? NSLocalizedString("menubar.menu.unmute", comment: "")
                      : NSLocalizedString("menubar.menu.mute", comment: ""))

                Spacer(minLength: 0)

                Text(NSLocalizedString("status.killSwitch", comment: ""))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Button(action: { AppRouter.shared.openSettings() }) {
                    if compact {
                        Image(systemName: "gearshape.fill")
                    } else {
                        Label(NSLocalizedString("status.settings", comment: ""), systemImage: "gearshape.fill")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button(action: { AppRouter.shared.quit() }) {
                    Text(NSLocalizedString("status.quit", comment: ""))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlSize(.small)
            }
            .font(compact ? .caption : .callout)

            if let copyStatus {
                Text(copyStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func copyContext() {
        Task {
            let userPrefs = prefs ?? UserPrefs.defaults()
            copyStatus = await AppRouter.shared.copyContext(modelContext: context, prefs: userPrefs)
        }
    }
}

/// Orange callout when required macOS permissions are missing.
struct PermissionsBanner: View {
    @ObservedObject var permissions = PermissionsManager.shared

    var body: some View {
        if permissions.hasRefreshed && permissions.needsRequired {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(NSLocalizedString("status.needPermissions.title", comment: ""))
                        .font(.subheadline.bold())
                    Text(missingDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(NSLocalizedString("status.needPermissions.open", comment: "")) {
                        AppRouter.shared.openSettings()
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private var missingDetail: String {
        var missing: [String] = []
        if !permissions.accessibilityGranted {
            missing.append(NSLocalizedString("settings.permissions.accessibility.title", comment: ""))
        }
        if !permissions.screenRecordingGranted {
            missing.append(NSLocalizedString("settings.permissions.screen.title", comment: ""))
        }
        guard !missing.isEmpty else {
            return NSLocalizedString("status.needPermissions.body", comment: "")
        }
        return String(format: NSLocalizedString("status.needPermissions.missing", comment: ""), missing.joined(separator: ", "))
    }
}
