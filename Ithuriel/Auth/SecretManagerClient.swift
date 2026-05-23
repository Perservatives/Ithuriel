import Foundation

/// Reads versioned secrets out of GCP Secret Manager on the Ithuriel project
/// using the signed-in user's Firebase OAuth token.
///
/// Why this exists:
/// The user requested API keys live in the cloud, not on every Mac. After
/// they sign in with Google (Firebase → Identity Toolkit), we exchange the
/// Firebase refresh token for an OAuth access token with the
/// `cloud-platform.read-only` scope and hit the Secret Manager REST API
/// directly. No service-account JSON ships with the app.
///
/// Falls back silently if the user isn't signed in — `UserPrefs.geminiApiKey`
/// / `.openAIAPIKey` still work as local-only paste-in fields.
@MainActor
final class SecretManagerClient {
    static let shared = SecretManagerClient()
    private init() {}

    private let projectId = FirebaseConfig.projectId
    private var cache: [String: (value: String, fetchedAt: Date)] = [:]
    private let ttl: TimeInterval = 60 * 15   // 15 min

    enum Failure: Error, CustomStringConvertible {
        case notSignedIn
        case http(Int, String)
        case noVersion
        var description: String {
            switch self {
            case .notSignedIn:        return "Not signed in — can't fetch cloud secrets."
            case .http(let c, let b): return "Secret Manager HTTP \(c): \(b.prefix(180))"
            case .noVersion:          return "Secret has no enabled version."
            }
        }
    }

    /// Resolve `ithuriel-gemini-key` / `ithuriel-openai-key` (or any other
    /// project secret). Cached for 15 min. Use `forceRefresh: true` to bypass.
    func accessSecret(_ name: String, forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let hit = cache[name],
           Date().timeIntervalSince(hit.fetchedAt) < ttl {
            return hit.value
        }
        guard AuthService.shared.isSignedIn else { throw Failure.notSignedIn }
        let bearer = try await firebaseOAuthAccessToken()

        let url = URL(string:
            "https://secretmanager.googleapis.com/v1/projects/\(projectId)/secrets/\(name)/versions/latest:access"
        )!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let b64 = payload["data"] as? String,
              let bytes = Data(base64Encoded: b64),
              let value = String(data: bytes, encoding: .utf8) else {
            throw Failure.noVersion
        }
        cache[name] = (value: value, fetchedAt: Date())
        return value
    }

    /// Bring local prefs in sync with cloud secrets. Best-effort: never
    /// throws — failures (no sign-in, network, secret not present) leave
    /// the existing local values alone.
    func sync(into prefs: UserPrefs, save: () -> Void) async {
        if prefs.geminiApiKey.isEmpty,
           let gemini = try? await accessSecret("ithuriel-gemini-key"),
           !gemini.isEmpty {
            prefs.geminiApiKey = gemini
            save()
        }
        if prefs.openAIAPIKey.isEmpty,
           let openai = try? await accessSecret("ithuriel-openai-key"),
           !openai.isEmpty {
            prefs.openAIAPIKey = openai
            save()
        }
    }

    // MARK: - Token exchange (Firebase refresh → Google OAuth access)

    /// Firebase's `securetoken.googleapis.com` endpoint returns a Google
    /// OAuth access token alongside the refreshed ID token, and that access
    /// token has the user's cloud-platform scopes. AuthService already
    /// handles ID-token refresh; we just call it and reuse the response.
    private func firebaseOAuthAccessToken() async throws -> String {
        // For most flows we want the user's *Google* access token, not the
        // Firebase ID token. AuthService stores the refresh token; trade
        // it for a fresh Google OAuth access token.
        let _ = try await AuthService.shared.refreshIfNeeded()
        guard let access = AuthService.shared.googleAccessToken, !access.isEmpty else {
            throw Failure.notSignedIn
        }
        return access
    }
}
