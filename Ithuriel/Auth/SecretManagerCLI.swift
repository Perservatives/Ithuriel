#if SECRETMANAGER_CLI
import Foundation

/// One-shot CLI harness to verify the Google OAuth → Secret Manager flow.
///
/// Build & run (outside the normal app target):
///
///     swiftc -DSECRETMANAGER_CLI \
///         Ithuriel/Auth/AuthService.swift \
///         Ithuriel/Auth/Keychain.swift \
///         Ithuriel/Auth/SecretManagerClient.swift \
///         Ithuriel/Auth/FirebaseConfig.swift \
///         Ithuriel/Auth/SecretManagerCLI.swift \
///         -o /tmp/secretmgr-cli
///     /tmp/secretmgr-cli
///
/// Preconditions:
///   • The signed-in user has already run the GUI sign-in flow so that
///     `google.accessToken` is in the Keychain.
///   • GCP project `synthesis-hack26svl-121` has the secrets
///     `ithuriel-gemini-key` and `ithuriel-openai-key`.
///
/// Behaviour: reads both secrets via `SecretManagerClient`, prints whether
/// each one came back non-empty, and exits non-zero on failure.
@main
struct SecretManagerCLI {
    static func main() async {
        guard AuthService.shared.isSignedIn else {
            FileHandle.standardError.write(Data("not signed in — run the app once first\n".utf8))
            exit(2)
        }
        guard let access = AuthService.shared.googleAccessToken, !access.isEmpty else {
            FileHandle.standardError.write(Data("no google.accessToken in keychain — sign in again\n".utf8))
            exit(3)
        }
        print("google.accessToken present (\(access.count) chars)")

        do {
            let gemini = try await SecretManagerClient.shared.accessSecret("ithuriel-gemini-key")
            print("ithuriel-gemini-key: \(gemini.isEmpty ? "EMPTY" : "OK (\(gemini.count) chars)")")

            let openai = try await SecretManagerClient.shared.accessSecret("ithuriel-openai-key")
            print("ithuriel-openai-key: \(openai.isEmpty ? "EMPTY" : "OK (\(openai.count) chars)")")
        } catch {
            FileHandle.standardError.write(Data("secret fetch failed: \(error)\n".utf8))
            exit(1)
        }
        exit(0)
    }
}
#endif
