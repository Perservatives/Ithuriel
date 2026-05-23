import Foundation

struct AgentRunRecord: Codable, Sendable {
    enum Status: String, Codable { case running, completed, failed, killed }

    let id: UUID
    let task: String
    let status: Status
    let startedAt: Date
    let finishedAt: Date?
    let transcript: [String]
    let error: String?
    let snapshotId: UUID?
}
