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

    /// Sign-in now runs entirely inside `ASWebAuthenticationSession` (see
    /// `AuthService.beginGoogleSignIn`); the Google redirect goes to the
    /// `com.googleusercontent.apps.…` scheme, not `ithuriel://`. This stub
    /// stays so old deep links don't crash and so we can add other auth
    /// callbacks here later.
    private func handleAuth(_ url: URL) {
        Log.info("Ignoring legacy ithuriel://auth deep link: \(url)")
    }
}
