import AppKit
import Foundation

/// Wired up by AppDelegate to handle `ithuriel://` URLs. We use this for
/// the OAuth callback: `ithuriel://auth/callback?token=<custom>`.
final class URLSchemeHandler {
    static let shared = URLSchemeHandler()
    private init() {}

    func install() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc func handleAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        handle(url)
    }

    func handle(_ url: URL) {
        guard url.scheme == "ithuriel" else { return }
        switch url.host {
        case "auth":
            handleAuth(url)
        default:
            Log.info("Unhandled deep link: \(url)")
        }
    }

    private func handleAuth(_ url: URL) {
        guard url.path == "/callback",
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "token" })?.value else { return }
        Task {
            do {
                try await AuthService.shared.completeSignIn(customToken: token)
                Log.info("Sign-in complete")
            } catch {
                Log.error("Sign-in failed: \(error)")
            }
        }
    }
}
