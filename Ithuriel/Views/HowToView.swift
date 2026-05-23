import SwiftUI

/// A concise "How to use Ithuriel" reference rendered as cards. Surfaced
/// inside Settings → How To. Lives in its own view so it can also be
/// triggered on first launch / from a menu item later without duplication.
struct HowToView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(NSLocalizedString("howto.title", comment: ""))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(NSLocalizedString("howto.subtitle", comment: ""))
                .font(.callout).foregroundStyle(.secondary)

            tip(symbol: "command",
                title: NSLocalizedString("howto.hotkey.title", comment: ""),
                body:  NSLocalizedString("howto.hotkey.body",  comment: ""))

            tip(symbol: "waveform",
                title: NSLocalizedString("howto.voice.title", comment: ""),
                body:  NSLocalizedString("howto.voice.body",  comment: ""))

            tip(symbol: "rectangle.stack.fill",
                title: NSLocalizedString("howto.chat.title", comment: ""),
                body:  NSLocalizedString("howto.chat.body",  comment: ""))

            tip(symbol: "stop.circle",
                title: NSLocalizedString("howto.kill.title", comment: ""),
                body:  NSLocalizedString("howto.kill.body",  comment: ""))

            tip(symbol: "shield.lefthalf.filled",
                title: NSLocalizedString("howto.privacy.title", comment: ""),
                body:  NSLocalizedString("howto.privacy.body",  comment: ""))

            tip(symbol: "icloud",
                title: NSLocalizedString("howto.cloud.title", comment: ""),
                body:  NSLocalizedString("howto.cloud.body",  comment: ""))
        }
    }

    private func tip(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(body)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
