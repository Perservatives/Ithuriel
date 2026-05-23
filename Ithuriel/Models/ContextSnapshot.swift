import Foundation
import SwiftData

enum SnapshotSource: String, Codable, Sendable {
    case vscode, xcode, cursor, terminal, unknown

    static func detect(for path: String) -> SnapshotSource {
        let lower = path.lowercased()
        if lower.hasSuffix(".xcodeproj") || lower.hasSuffix(".xcworkspace") { return .xcode }
        // Heuristic fallback — we can't tell vscode vs cursor from the path alone.
        return .vscode
    }
}

struct ContextSnapshot: Codable, Identifiable, Sendable {
    struct EditRecord: Codable, Sendable {
        let path: String
        let linesAdded: Int
        let linesRemoved: Int
        let summary: String
    }

    let id: UUID
    let capturedAt: Date
    let source: SnapshotSource
    let workspacePath: String
    let gitState: GitState?
    let recentEdits: [EditRecord]
    let terminalHistory: [String]
    let activeFiles: [String]

    // Ambient capture fields (optional)
    /// Clipboard contents — set only when the pasteboard holds code-shaped text.
    var clipboard: String?
    /// Bundle identifiers of regular (non-agent/accessory) running applications.
    var openApps: [String] = []
    /// Bundle identifier of the frontmost application.
    var frontmostApp: String?
}

extension ContextSnapshot {
    /// Builds a fresh workspace snapshot when the periodic capture cache is empty.
    @MainActor
    static func captureFresh(prefs: UserPrefs) async -> ContextSnapshot {
        let workspacePath: String
        if !prefs.activeWorkspace.isEmpty {
            workspacePath = prefs.activeWorkspace
        } else if let recent = WorkspaceMonitor.mostRecentEditorWorkspace() {
            workspacePath = recent
        } else {
            workspacePath = FileManager.default.homeDirectoryForCurrentUser.path
        }

        let git = await GitCapture.capture(at: workspacePath)
        let terminal = await TerminalCapture.recentCommands(limit: 20)
        let raw = ContextSnapshot(
            id: UUID(),
            capturedAt: Date(),
            source: SnapshotSource.detect(for: workspacePath),
            workspacePath: workspacePath,
            gitState: git,
            recentEdits: [],
            terminalHistory: terminal,
            activeFiles: WorkspaceMonitor.openFiles(in: workspacePath)
        )
        let (redacted, _) = Redactor.redact(snapshot: raw, prefs: prefs)
        return redacted
    }
}

@Model
final class CachedSnapshot {
    @Attribute(.unique) var id: UUID
    var capturedAt: Date
    var payload: Data

    init(id: UUID, capturedAt: Date, payload: Data) {
        self.id = id
        self.capturedAt = capturedAt
        self.payload = payload
    }

    @MainActor
    static func persist(_ snapshot: ContextSnapshot, in container: ModelContainer) async {
        guard let data = try? JSONEncoder.ithuriel.encode(snapshot) else { return }
        let context = container.mainContext
        let row = CachedSnapshot(id: snapshot.id, capturedAt: snapshot.capturedAt, payload: data)
        context.insert(row)
        do {
            try pruneOldEntries(in: context, keeping: 50)
            try context.save()
        } catch {
            Log.error("CachedSnapshot persist failed: \(error)")
        }
    }

    @MainActor
    static func latest(in container: ModelContainer) async -> ContextSnapshot? {
        let context = container.mainContext
        var descriptor = FetchDescriptor<CachedSnapshot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let row = try? context.fetch(descriptor).first else { return nil }
        return try? JSONDecoder.ithuriel.decode(ContextSnapshot.self, from: row.payload)
    }

    @MainActor
    private static func pruneOldEntries(in context: ModelContext, keeping limit: Int) throws {
        let descriptor = FetchDescriptor<CachedSnapshot>(sortBy: [SortDescriptor(\.capturedAt, order: .reverse)])
        let rows = try context.fetch(descriptor)
        guard rows.count > limit else { return }
        for row in rows.dropFirst(limit) {
            context.delete(row)
        }
    }
}
