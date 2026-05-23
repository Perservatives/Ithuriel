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
    var agentControlEnabled: Bool

    init(id: String = "default",
         redactKeys: Bool = true,
         localOnly: Bool = false,
         capturingEnabled: Bool = true,
         excludePathsRaw: String = ".env,secrets/,private/,.ssh/",
         targetToolsRaw: String = "claude-code,cursor,chatgpt,claude-desktop",
         apiBaseURL: String = "https://api.ithuriel.dev",
         apiToken: String = "",
         agentControlEnabled: Bool = false) {
        self.id = id
        self.redactKeys = redactKeys
        self.localOnly = localOnly
        self.capturingEnabled = capturingEnabled
        self.excludePathsRaw = excludePathsRaw
        self.targetToolsRaw = targetToolsRaw
        self.apiBaseURL = apiBaseURL
        self.apiToken = apiToken
        self.agentControlEnabled = agentControlEnabled
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

    @MainActor
    static func load(in container: ModelContainer) throws -> UserPrefs {
        let context = container.mainContext
        let descriptor = FetchDescriptor<UserPrefs>()
        if let existing = try context.fetch(descriptor).first { return existing }
        let prefs = UserPrefs()
        context.insert(prefs)
        try context.save()
        return prefs
    }
}
