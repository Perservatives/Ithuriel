import Foundation

/// Hard-coded Firebase project that ships with the build. Users can still
/// override the API base URL and web API key in Settings → Integrations for
/// custom deployments, but out-of-the-box the app talks to the project
/// referenced by these constants.
enum FirebaseConfig {
    /// Human-readable project name from the Firebase console.
    static let projectName  = "Synthesis Hackathon-121"
    /// Lowercase project id used in every URL.
    static let projectId    = "synthesis-hack26svl-121"
    /// Numeric project id (used in default Cloud Run hostnames).
    static let projectNumber = "596592790807"
    /// Region the Ithuriel API + Vertex AI live in.
    static let region       = "us-central1"

    /// Firebase Web API key (a.k.a. "browser key") used for Identity Toolkit
    /// REST calls. Matches `API_KEY` in `GoogleService-Info.plist`. Used as
    /// the default for `UserPrefs.firebaseWebAPIKey` and as a fallback when
    /// the user hasn't entered a custom value.
    static let defaultWebAPIKey = "AIzaSyDMtG-Tuzq5l_2siR93ONT4hKvEQN5OgRc"

    /// OAuth 2.0 iOS client id from `GoogleService-Info.plist` (CLIENT_ID).
    /// iOS-type OAuth clients have no secret — the PKCE flow proves the
    /// caller controls the redirect URI.
    static let iosOAuthClientId = "596592790807-d0eupdlaklbf415hajn3omigag0dvlsi.apps.googleusercontent.com"

    /// Reverse-DNS form of the iOS OAuth client id (REVERSED_CLIENT_ID in
    /// the plist). Used as the custom URL scheme Google redirects back to.
    static let reversedClientId = "com.googleusercontent.apps.596592790807-d0eupdlaklbf415hajn3omigag0dvlsi"

    /// Default Cloud Run service URL. Cloud Run v2 picks a hostname of the
    /// form `<service>-<projectNumber>.<region>.run.app`. Users can override
    /// in Settings if they redeploy with a custom domain.
    static var defaultAPIBaseURL: String {
        "https://ithuriel-api-\(projectNumber).\(region).run.app"
    }

    /// Direct Firestore REST root for the (default) database. Use when the
    /// Cloud Run API isn't reachable — see `DirectFirestoreClient`.
    static var firestoreBaseURL: String {
        "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    }

    /// Identity Toolkit endpoints used by `AuthService` for custom-token
    /// exchange and refresh.
    static var identityToolkitBase: String { "https://identitytoolkit.googleapis.com/v1" }
    static var secureTokenBase: String     { "https://securetoken.googleapis.com/v1" }
}
