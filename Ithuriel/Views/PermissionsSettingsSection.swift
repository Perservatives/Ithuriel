import SwiftUI

/// Required permission rows — hidden when accessibility and screen recording are granted.
struct PermissionsSettingsSection: View {
    @ObservedObject var permissions: PermissionsManager

    var body: some View {
        if permissions.needsRequired {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("settings.permissions.intro", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !permissions.accessibilityGranted {
                    PermissionRow(
                        title: NSLocalizedString("settings.permissions.accessibility.title", comment: ""),
                        detail: NSLocalizedString("settings.permissions.accessibility.detail", comment: ""),
                        systemImage: "hand.point.up.left.fill",
                        actionTitle: NSLocalizedString("settings.permissions.enable", comment: ""),
                        secondaryTitle: NSLocalizedString("settings.permissions.openSettings", comment: ""),
                        onPrimary: { permissions.requestAccessibility() },
                        onSecondary: { permissions.openAccessibilitySettings() }
                    )
                }

                if !permissions.screenRecordingGranted {
                    PermissionRow(
                        title: NSLocalizedString("settings.permissions.screen.title", comment: ""),
                        detail: NSLocalizedString("settings.permissions.screen.detail", comment: ""),
                        systemImage: "rectangle.on.rectangle",
                        actionTitle: NSLocalizedString("settings.permissions.enable", comment: ""),
                        secondaryTitle: NSLocalizedString("settings.permissions.openSettings", comment: ""),
                        onPrimary: { permissions.requestScreenRecording() },
                        onSecondary: { permissions.openScreenRecordingSettings() }
                    )
                }
            }
        } else {
            Label(NSLocalizedString("settings.permissions.allGranted", comment: ""),
                  systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String
    let secondaryTitle: String?
    let onPrimary: () -> Void
    let onSecondary: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 12) {
                Button(actionTitle, action: onPrimary)
                    .controlSize(.small)
                if let secondaryTitle, let onSecondary {
                    Button(secondaryTitle, action: onSecondary)
                        .controlSize(.small)
                        .buttonStyle(.link)
                }
            }
            .padding(.leading, 30)
        }
        .padding(.vertical, 4)
    }
}
