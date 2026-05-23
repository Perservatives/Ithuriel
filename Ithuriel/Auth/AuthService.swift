import Foundation
import AppKit
import AuthenticationServices
import CryptoKit

/// Client-only Google sign-in for the macOS app.
///
/// End-to-end flow:
///   1. PKCE handshake: generate verifier+challenge, open Google's consent
///      page in `ASWebAuthenticationSession` with scopes
///      `openid email profile` + `cloud-platform.read-only`.
///   2. POST the auth code to `oauth2.googleapis.com/token` and capture both
///      the Google `id_token` AND the `access_token` (+ `expires_in`).
///   3. Forward the `id_token` to Identity Toolkit `signInWithIdp` for the
///      Firebase `idToken` / `refreshToken` pair (stored under `firebase.*`).
///   4. Persist the Google OAuth access token to Keychain under
///      `google.accessToken` so `SecretManagerClient` can read GCP secrets.
final class AuthService {
    static let shared = AuthService()
    private init() {}

    /// Cloud Run API base URL. Kept on the singleton because other code
    /// (e.g. `IthurielClient`) writes through this on prefs change.
    var apiBaseURL: String = FirebaseConfig.defaultAPIBaseURL

    /// Firebase web API key for Identity Toolkit. Plumbed from `UserPrefs`;
    /// falls back to `GoogleService-Info.plist` (`resolvedWebAPIKey`).
    var firebaseWebAPIKey: String = ""

    // MARK: - Token storage

    private let idTokenKey      = "firebase.idToken"
    private let refreshTokenKey = "firebase.refreshToken"
    private let idTokenExpiry   = "firebase.idToken.expiry"
    private let uidKey          = "firebase.uid"

    var idToken: String? { Keychain.get(idTokenKey) }
    var refreshToken: String? { Keychain.get(refreshTokenKey) }
    /// Cached human-facing identity for the signed-in user. Populated lazily
    /// via `accounts:lookup` after sign-in (and on demand from the UI). Stored
    /// in `UserDefaults` so window restoration doesn't show a stale "?".
    var displayName: String? {
        get { UserDefaults.standard.string(forKey: "firebase.displayName") }
        set { UserDefaults.standard.set(newValue, forKey: "firebase.displayName") }
    }
    var userEmail: String? {
        get { UserDefaults.standard.string(forKey: "firebase.email") }
        set { UserDefaults.standard.set(newValue, forKey: "firebase.email") }
    }
    /// Google OAuth access token from the most recent sign-in. Used by
    /// `SecretManagerClient` to talk to `secretmanager.googleapis.com`.
    /// Stored in Keychain under `google.accessToken`; populated by
    /// `exchangeCodeForGoogleIdToken` when the user signs in with the
    /// `cloud-platform.read-only` scope.
    var googleAccessToken: String? { Keychain.get(googleAccessTokenKey) }

    private let googleAccessTokenKey       = "google.accessToken"
    private let googleAccessTokenExpiryKey = "google.accessToken.expiry"
    var uid: String? { Keychain.get(uidKey) }
    var isSignedIn: Bool { idToken != nil }

    func signOut() {
        Keychain.remove(idTokenKey)
        Keychain.remove(refreshTokenKey)
        Keychain.remove(idTokenExpiry)
        Keychain.remove(uidKey)
        Keychain.remove(googleAccessTokenKey)
        Keychain.remove(googleAccessTokenExpiryKey)
        UserDefaults.standard.removeObject(forKey: "firebase.displayName")
        UserDefaults.standard.removeObject(forKey: "firebase.email")
    }

    /// Hits Identity Toolkit `accounts:lookup` to grab the display name + email
    /// for the current user. Safe to call repeatedly — short-circuits if we
    /// already have a cached display name.
    func refreshUserProfileIfNeeded() {
        guard isSignedIn else { return }
        if (displayName?.isEmpty == false) { return }
        Task { @MainActor in
            do {
                let token = try await refreshIfNeeded()
                let apiKey = resolvedWebAPIKey()
                guard !apiKey.isEmpty else { return }
                let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(apiKey)")!
                var req = URLRequest(url: url)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": token])
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
                struct LookupResp: Decodable {
                    struct User: Decodable { let displayName: String?; let email: String? }
                    let users: [User]?
                }
                let decoded = try JSONDecoder().decode(LookupResp.self, from: data)
                if let user = decoded.users?.first {
                    self.displayName = user.displayName
                    self.userEmail = user.email
                    NotificationCenter.default.post(name: .authProfileDidUpdate, object: nil)
                }
            } catch {
                Log.info("accounts:lookup failed: \(error)")
            }
        }
    }

    // MARK: - Sign-in (ASWebAuthenticationSession + PKCE + signInWithIdp)

    /// Holds the in-flight session so it isn't deallocated mid-flow.
    private var pendingSession: ASWebAuthenticationSession?
    private var presentationProvider: WebAuthPresentationProvider?

    func beginGoogleSignIn() {
        Task { @MainActor in
            do {
                try await runGoogleSignIn()
                Log.info("Google sign-in complete uid=\(uid ?? "?")")
                refreshUserProfileIfNeeded()
            } catch {
                Log.error("Google sign-in failed: \(error)")
            }
        }
    }

    @MainActor
    private func runGoogleSignIn() async throws {
        let apiKey = resolvedWebAPIKey()
        guard !apiKey.isEmpty else { throw AuthError.missingWebAPIKey }

        // PKCE
        let verifier = Self.randomCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        let redirectScheme = FirebaseConfig.reversedClientId
        let redirectURI = "\(redirectScheme):/oauth2callback"

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            URLQueryItem(name: "client_id",             value: FirebaseConfig.iosOAuthClientId),
            URLQueryItem(name: "redirect_uri",          value: redirectURI),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "scope",                 value: "openid email profile https://www.googleapis.com/auth/cloud-platform.read-only"),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt",                value: "select_account"),
        ]
        guard let authURL = auth.url else { throw AuthError.exchangeFailed("bad auth URL") }

        // 1) Run the browser dance.
        let callback = try await presentWebAuth(url: authURL, scheme: redirectScheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.exchangeFailed("no code in callback: \(callback)") }

        // 2) Code -> Google tokens (no client secret for iOS clients).
        let googleIdToken = try await exchangeCodeForGoogleIdToken(
            code: code, verifier: verifier, redirectURI: redirectURI
        )

        // 3) Google id_token -> Firebase tokens via Identity Toolkit.
        try await signInWithGoogleIdToken(googleIdToken, apiKey: apiKey)
    }

    @MainActor
    private func presentWebAuth(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let error { cont.resume(throwing: error); return }
                guard let callbackURL else {
                    cont.resume(throwing: AuthError.exchangeFailed("empty callback"))
                    return
                }
                cont.resume(returning: callbackURL)
            }
            let provider = WebAuthPresentationProvider()
            self.presentationProvider = provider
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            self.pendingSession = session
            if !session.start() {
                cont.resume(throwing: AuthError.exchangeFailed("session.start() returned false"))
            }
        }
    }

    /// Exchange the auth code for Google tokens. Captures both the OIDC
    /// `id_token` (used to mint a Firebase session) and the OAuth
    /// `access_token` (used by `SecretManagerClient`). The access token + its
    /// absolute expiry are persisted to Keychain so they survive app restart.
    private func exchangeCodeForGoogleIdToken(code: String, verifier: String, redirectURI: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "code": code,
            "client_id": FirebaseConfig.iosOAuthClientId,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        req.httpBody = body
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.exchangeFailed("google token exchange: \(String(data: data, encoding: .utf8) ?? "")")
        }
        struct TokenResp: Decodable {
            let id_token: String
            let access_token: String?
            let expires_in: Int?
        }
        let decoded = try JSONDecoder().decode(TokenResp.self, from: data)
        if let access = decoded.access_token, !access.isEmpty {
            try Keychain.set(access, key: googleAccessTokenKey)
            let expiry = Int(Date().timeIntervalSince1970) + (decoded.expires_in ?? 3600)
            try Keychain.set(String(expiry), key: googleAccessTokenExpiryKey)
        }
        return decoded.id_token
    }

    private func signInWithGoogleIdToken(_ googleIdToken: String, apiKey: String) async throws {
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "postBody": "id_token=\(googleIdToken)&providerId=google.com",
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.exchangeFailed("signInWithIdp: \(String(data: data, encoding: .utf8) ?? "")")
        }
        let decoded = try JSONDecoder().decode(SignInResponse.self, from: data)
        try Keychain.set(decoded.idToken, key: idTokenKey)
        try Keychain.set(decoded.refreshToken, key: refreshTokenKey)
        try Keychain.set(decoded.localId, key: uidKey)
        try Keychain.set(
            String(Int(Date().timeIntervalSince1970) + (Int(decoded.expiresIn) ?? 3600)),
            key: idTokenExpiry
        )
    }

    // MARK: - Refresh

    /// Refresh an expired ID token using the stored refresh token.
    func refreshIfNeeded() async throws -> String {
        if let token = idToken, !isExpired() { return token }
        guard let rt = refreshToken else { throw AuthError.notSignedIn }
        let apiKey = resolvedWebAPIKey()
        guard !apiKey.isEmpty else { throw AuthError.missingWebAPIKey }

        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=refresh_token&refresh_token=\(rt)".data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.exchangeFailed(String(data: data, encoding: .utf8) ?? "")
        }
        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        try Keychain.set(refreshed.idToken, key: idTokenKey)
        try Keychain.set(refreshed.refreshToken, key: refreshTokenKey)
        try Keychain.set(
            String(Int(Date().timeIntervalSince1970) + (Int(refreshed.expiresIn) ?? 3600)),
            key: idTokenExpiry
        )
        return refreshed.idToken
    }

    private func isExpired() -> Bool {
        guard let raw = Keychain.get(idTokenExpiry), let ts = Int(raw) else { return true }
        return Date().timeIntervalSince1970 >= Double(ts) - 60
    }

    // MARK: - Helpers

    /// Use the user-configured key if present; otherwise fall back to the
    /// bundled `GoogleService-Info.plist`.
    private func resolvedWebAPIKey() -> String {
        if !firebaseWebAPIKey.isEmpty { return firebaseWebAPIKey }
        if let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let key = dict["API_KEY"] as? String {
            return key
        }
        return FirebaseConfig.defaultWebAPIKey
    }

    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - Responses

    private struct SignInResponse: Decodable {
        let idToken: String
        let refreshToken: String
        let expiresIn: String
        let localId: String
    }
    private struct RefreshResponse: Decodable {
        let idToken: String
        let refreshToken: String
        let expiresIn: String
        enum CodingKeys: String, CodingKey {
            case idToken = "id_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}

/// macOS needs a presentation anchor (an `NSWindow`) for
/// `ASWebAuthenticationSession`. The key window works; falling back to the
/// first window covers `LSUIElement` agent apps with no key window.
private final class WebAuthPresentationProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

private extension Data {
    /// RFC 7636 base64url: standard base64 with `+/` → `-_` and stripped `=`.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension Notification.Name {
    /// Fires after `AuthService.refreshUserProfileIfNeeded` writes a fresh
    /// `displayName` / `userEmail`. The chat sidebar listens to repaint the
    /// user footer without polling.
    static let authProfileDidUpdate = Notification.Name("dev.ithuriel.authProfileDidUpdate")
}

enum AuthError: Error, CustomStringConvertible {
    case missingWebAPIKey
    case notSignedIn
    case exchangeFailed(String)

    var description: String {
        switch self {
        case .missingWebAPIKey: return "Firebase web API key not configured."
        case .notSignedIn:      return "Not signed in."
        case .exchangeFailed(let body): return "Auth exchange failed: \(body.prefix(300))"
        }
    }
}
