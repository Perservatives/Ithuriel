import Foundation
import AppKit

/// Handles the OAuth dance against the Ithuriel Cloud Run API and the
/// subsequent Firebase custom-token → ID-token exchange. Stores tokens
/// in the Keychain. All purely Foundation/URLSession — no Firebase SDK.
final class AuthService {
    static let shared = AuthService()
    private init() {}

    /// Set by the user in Settings → Integrations (Cloud Run public URL).
    var apiBaseURL: String = "https://api.ithuriel.dev"

    /// Firebase web API key (lives in Settings; can be read from the
    /// Firebase console). Required to exchange custom token → ID token
    /// via the Identity Toolkit REST endpoint.
    var firebaseWebAPIKey: String = ""

    // MARK: - Token storage

    private let idTokenKey      = "firebase.idToken"
    private let refreshTokenKey = "firebase.refreshToken"
    private let idTokenExpiry   = "firebase.idToken.expiry"

    var idToken: String? { Keychain.get(idTokenKey) }
    var refreshToken: String? { Keychain.get(refreshTokenKey) }
    var isSignedIn: Bool { idToken != nil }

    func signOut() {
        Keychain.remove(idTokenKey)
        Keychain.remove(refreshTokenKey)
        Keychain.remove(idTokenExpiry)
    }

    // MARK: - Sign-in via system browser

    /// Step 1: open `<api>/auth/google?redirect=ithuriel://auth/callback` in
    /// the user's default browser. The browser bounces to Google, then
    /// back to our API, which redirects to `ithuriel://auth/callback?token=`.
    /// `URLSchemeHandler.handle(_:)` finishes the flow.
    func beginGoogleSignIn() {
        var components = URLComponents(string: "\(apiBaseURL)/auth/google")!
        components.queryItems = [URLQueryItem(name: "redirect", value: "ithuriel://auth/callback")]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    /// Step 2: API hands us a Firebase *custom token* via deep link. Exchange
    /// it for an ID token using Identity Toolkit `signInWithCustomToken`.
    func completeSignIn(customToken: String) async throws {
        guard !firebaseWebAPIKey.isEmpty else { throw AuthError.missingWebAPIKey }
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=\(firebaseWebAPIKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "token": customToken,
            "returnSecureToken": true
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.exchangeFailed(String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(SignInResponse.self, from: data)
        try Keychain.set(decoded.idToken, key: idTokenKey)
        try Keychain.set(decoded.refreshToken, key: refreshTokenKey)
        try Keychain.set(String(Int(Date().timeIntervalSince1970) + (Int(decoded.expiresIn) ?? 3600)), key: idTokenExpiry)
    }

    /// Refresh an expired ID token using the stored refresh token.
    func refreshIfNeeded() async throws -> String {
        if let token = idToken, !isExpired() { return token }
        guard let rt = refreshToken else { throw AuthError.notSignedIn }
        guard !firebaseWebAPIKey.isEmpty else { throw AuthError.missingWebAPIKey }

        let url = URL(string: "https://securetoken.googleapis.com/v1/token?key=\(firebaseWebAPIKey)")!
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
        try Keychain.set(String(Int(Date().timeIntervalSince1970) + (Int(refreshed.expiresIn) ?? 3600)), key: idTokenExpiry)
        return refreshed.idToken
    }

    private func isExpired() -> Bool {
        guard let raw = Keychain.get(idTokenExpiry), let ts = Int(raw) else { return true }
        return Date().timeIntervalSince1970 >= Double(ts) - 60
    }

    // MARK: - Responses

    private struct SignInResponse: Decodable {
        let idToken: String
        let refreshToken: String
        let expiresIn: String
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

enum AuthError: Error, CustomStringConvertible {
    case missingWebAPIKey
    case notSignedIn
    case exchangeFailed(String)

    var description: String {
        switch self {
        case .missingWebAPIKey: return "Firebase web API key not configured (Settings → Integrations)."
        case .notSignedIn:      return "Not signed in."
        case .exchangeFailed(let body): return "Auth exchange failed: \(body.prefix(200))"
        }
    }
}
