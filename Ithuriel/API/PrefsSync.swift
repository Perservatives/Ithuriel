import Foundation
import SwiftData

/// Syncs UserPrefs to/from Firestore via the /v1/user/prefs API endpoint.
/// All operations are fire-and-forget safe: errors are logged but never thrown
/// to the caller so prefs sync never blocks or crashes the app.
final class PrefsSync {
    static let shared = PrefsSync()
    private init() {}

    // MARK: - Pull

    /// Fetch prefs from Firestore and merge non-nil/non-empty fields into the
    /// local SwiftData record. Only call when the user is signed in.
    @MainActor
    func pullRemote(container: ModelContainer) async {
        guard AuthService.shared.isSignedIn else { return }
        guard let baseURL = resolvedBaseURL() else { return }

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/user/prefs"))
        do {
            try await attachAuth(&req)
        } catch {
            Log.error("PrefsSync.pullRemote: auth failed – \(error)")
            return
        }

        let data: Data
        do {
            let (d, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Log.error("PrefsSync.pullRemote: non-2xx response")
                return
            }
            data = d
        } catch {
            Log.error("PrefsSync.pullRemote: transport error – \(error)")
            return
        }

        guard let remote = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !remote.isEmpty else { return }

        let prefs: UserPrefs
        do {
            prefs = try UserPrefs.load(in: container)
        } catch {
            Log.error("PrefsSync.pullRemote: failed to load local prefs – \(error)")
            return
        }

        applyRemote(remote, to: prefs)

        do {
            try container.mainContext.save()
        } catch {
            Log.error("PrefsSync.pullRemote: save failed – \(error)")
        }
    }

    // MARK: - Push

    /// Send the current local prefs to Firestore. Only call when signed in.
    /// Respects localOnly: if true, API keys are omitted from the payload.
    func pushLocal(prefs: UserPrefs) async {
        guard AuthService.shared.isSignedIn else { return }
        guard let baseURL = resolvedBaseURL() else { return }

        var req = URLRequest(url: baseURL.appendingPathComponent("/v1/user/prefs"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            try await attachAuth(&req)
        } catch {
            Log.error("PrefsSync.pushLocal: auth failed – \(error)")
            return
        }

        req.httpBody = buildBody(from: prefs)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                Log.error("PrefsSync.pushLocal: non-2xx response")
                return
            }
        } catch {
            Log.error("PrefsSync.pushLocal: transport error – \(error)")
        }
    }

    // MARK: - Helpers

    private func resolvedBaseURL() -> URL? {
        // AuthService holds the last-written API base URL from IthurielClient.
        let raw = AuthService.shared.apiBaseURL
        return URL(string: raw.isEmpty ? FirebaseConfig.defaultAPIBaseURL : raw)
    }

    private func attachAuth(_ req: inout URLRequest) async throws {
        let token = try await AuthService.shared.refreshIfNeeded()
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    /// Build the PUT body. If localOnly is true, omit API keys so they stay
    /// device-local only.
    private func buildBody(from prefs: UserPrefs) -> Data? {
        var dict: [String: Any] = [
            "excludePathsRaw":    prefs.excludePathsRaw,
            "targetToolsRaw":     prefs.targetToolsRaw,
            "redactKeys":         prefs.redactKeys,
            "localOnly":          prefs.localOnly,
            "capturingEnabled":   prefs.capturingEnabled,
            "agentEnabled":       prefs.agentEnabled,
            "geminiModel":        prefs.geminiModel,
            "activeWorkspace":    prefs.activeWorkspace,
            "confirmEveryAction": prefs.confirmEveryAction,
            "restrictToWorkspace": prefs.restrictToWorkspace,
            "launchColorHex":     prefs.launchColorHex,
            "hotkeyKeyCode":      prefs.hotkeyKeyCode,
            "hotkeyModifiers":    prefs.hotkeyModifiers,
            "onboardingComplete": prefs.onboardingComplete,
        ]

        // Only sync API keys when the user hasn't opted out of cloud storage.
        if !prefs.localOnly {
            dict["geminiApiKey"]     = prefs.geminiApiKey
            dict["googleCloudApiKey"] = prefs.googleCloudAPIKey
            dict["openaiApiKey"]     = prefs.openAIAPIKey
        }

        return try? JSONSerialization.data(withJSONObject: dict)
    }

    /// Merge non-nil/non-empty remote fields into the local prefs object.
    private func applyRemote(_ remote: [String: Any], to prefs: UserPrefs) {
        if let v = remote["excludePathsRaw"] as? String, !v.isEmpty {
            prefs.excludePathsRaw = v
        }
        if let v = remote["targetToolsRaw"] as? String, !v.isEmpty {
            prefs.targetToolsRaw = v
        }
        if let v = remote["redactKeys"] as? Bool {
            prefs.redactKeys = v
        }
        if let v = remote["localOnly"] as? Bool {
            prefs.localOnly = v
        }
        if let v = remote["capturingEnabled"] as? Bool {
            prefs.capturingEnabled = v
        }
        if let v = remote["agentEnabled"] as? Bool {
            prefs.agentEnabled = v
        }
        if let v = remote["geminiModel"] as? String, !v.isEmpty {
            prefs.geminiModel = v
        }
        if let v = remote["activeWorkspace"] as? String, !v.isEmpty {
            prefs.activeWorkspace = v
        }
        if let v = remote["confirmEveryAction"] as? Bool {
            prefs.confirmEveryAction = v
        }
        if let v = remote["restrictToWorkspace"] as? Bool {
            prefs.restrictToWorkspace = v
        }
        if let v = remote["launchColorHex"] as? String, !v.isEmpty {
            prefs.launchColorHex = v
        }
        if let v = remote["hotkeyKeyCode"] as? Int {
            prefs.hotkeyKeyCode = v
        }
        if let v = remote["hotkeyModifiers"] as? Int {
            prefs.hotkeyModifiers = v
        }
        if let v = remote["onboardingComplete"] as? Bool {
            prefs.onboardingComplete = v
        }

        // Only apply API keys when localOnly is off (respect device preference).
        if !prefs.localOnly {
            if let v = remote["geminiApiKey"] as? String, !v.isEmpty {
                prefs.geminiApiKey = v
            }
            if let v = remote["googleCloudApiKey"] as? String, !v.isEmpty {
                prefs.googleCloudAPIKey = v
            }
            if let v = remote["openaiApiKey"] as? String, !v.isEmpty {
                prefs.openAIAPIKey = v
            }
        }
    }
}
