import Foundation
import SwiftData

@Model
final class UserPrefs {
    @Attribute(.unique) var id: String
    var redactKeys: Bool
    var localOnly: Bool
    var capturingEnabled: Bool
    var excludePathsRaw: String
    var targetToolsRaw: String
    var apiBaseURL: String
    var apiToken: String
    var firebaseWebAPIKey: String

    // Agent (primary feature)
    var agentEnabled: Bool
    var geminiApiKey: String
    var geminiModel: String
    var activeWorkspace: String
    var confirmEveryAction: Bool
    var autoApproveSafeOnly: Bool
    /// When false, file ops may touch any path (except Redactor-blocked secrets paths).
    var restrictToWorkspace: Bool

    init(id: String = "default",
         redactKeys: Bool = true,
         localOnly: Bool = false,
         capturingEnabled: Bool = true,
         excludePathsRaw: String = ".env,secrets/,private/,.ssh/",
         targetToolsRaw: String = "claude-code,cursor,chatgpt,claude-desktop",
         apiBaseURL: String = "https://api.ithuriel.dev",
         apiToken: String = "",
         firebaseWebAPIKey: String = "",
         agentEnabled: Bool = true,
         geminiApiKey: String = "",
         geminiModel: String = "gemini-3.5-flash",
         activeWorkspace: String = "",
         confirmEveryAction: Bool = false,
         autoApproveSafeOnly: Bool = false,
         restrictToWorkspace: Bool = false) {
        self.id = id
        self.redactKeys = redactKeys
        self.localOnly = localOnly
        self.capturingEnabled = capturingEnabled
        self.excludePathsRaw = excludePathsRaw
        self.targetToolsRaw = targetToolsRaw
        self.apiBaseURL = apiBaseURL
        self.apiToken = apiToken
        self.firebaseWebAPIKey = firebaseWebAPIKey
        self.agentEnabled = agentEnabled
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel
        self.activeWorkspace = activeWorkspace
        self.confirmEveryAction = confirmEveryAction
        self.autoApproveSafeOnly = autoApproveSafeOnly
        self.restrictToWorkspace = restrictToWorkspace
    }

    var excludePaths: [String] {
        excludePathsRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var targetTools: [AITool] {
        targetToolsRaw
            .split(separator: ",")
            .compactMap { AITool(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
    }

    static func defaults() -> UserPrefs { UserPrefs() }

    static func load(in container: ModelContainer) async throws -> UserPrefs {
        try await MainActor.run {
            let context = container.mainContext
            let descriptor = FetchDescriptor<UserPrefs>()
            if let existing = try context.fetch(descriptor).first {
                if existing.activeWorkspace.isEmpty,
                   let path = WorkspaceMonitor.mostRecentEditorWorkspace() {
                    existing.activeWorkspace = path
                    try? context.save()
                }
                return existing
            }
            let prefs = UserPrefs(activeWorkspace: WorkspaceMonitor.mostRecentEditorWorkspace() ?? "")
            context.insert(prefs)
            try context.save()
            return prefs
        }
    }
}
