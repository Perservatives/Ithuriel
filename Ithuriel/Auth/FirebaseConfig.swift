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
