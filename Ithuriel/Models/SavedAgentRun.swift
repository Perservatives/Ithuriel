import Foundation
import SwiftData

/// Persisted agent run for the chat history sidebar.
/// We mirror AgentRunRecord but as a SwiftData model so the UI can `@Query`.
@Model
final class SavedAgentRun {
    @Attribute(.unique) var id: UUID
    var task: String
    var statusRaw: String
    var startedAt: Date
    var finishedAt: Date?
    var transcript: [String]
    var errorText: String?
    var workspacePath: String
    var modelName: String

    var status: AgentRunRecord.Status {
        AgentRunRecord.Status(rawValue: statusRaw) ?? .running
    }

    init(id: UUID = UUID(),
         task: String,
         status: AgentRunRecord.Status,
         startedAt: Date,
         finishedAt: Date? = nil,
         transcript: [String] = [],
         errorText: String? = nil,
         workspacePath: String = "",
         modelName: String = "") {
        self.id = id
        self.task = task
        self.statusRaw = status.rawValue
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.transcript = transcript
        self.errorText = errorText
        self.workspacePath = workspacePath
        self.modelName = modelName
    }

    static func persist(id: UUID,
                        task: String,
                        status: AgentRunRecord.Status,
                        startedAt: Date,
                        finishedAt: Date?,
                        transcript: [String],
                        errorText: String?,
                        workspacePath: String,
                        modelName: String,
                        in container: ModelContainer?) async {
        guard let container else { return }
        await MainActor.run {
            let context = container.mainContext
            let descriptor = FetchDescriptor<SavedAgentRun>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(descriptor).first {
                existing.statusRaw = status.rawValue
                existing.finishedAt = finishedAt
                existing.transcript = transcript
                existing.errorText = errorText
            } else {
                context.insert(SavedAgentRun(
                    id: id,
                    task: task,
                    status: status,
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    transcript: transcript,
                    errorText: errorText,
                    workspacePath: workspacePath,
                    modelName: modelName
                ))
            }
            try? context.save()
        }
    }
}
