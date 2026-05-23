import Foundation

/// Direct Firestore REST writer. Lets the macOS agent push snapshots and
/// agent runs straight to the `synthesis-hack26svl-121` Firestore database
/// without the Cloud Run API being deployed first. Authenticates with the
/// Firebase ID token held by `AuthService`.
///
/// The Cloud Run API is still preferred (it also runs the snapshot-processor
/// pipeline through Pub/Sub → Vertex AI for embeddings) — this client is a
/// graceful fallback that keeps "snapshot landed in Firebase" true even when
/// the API URL isn't reachable.
final class DirectFirestoreClient {
    static let shared = DirectFirestoreClient()
    private init() {}

    enum Failure: Error, CustomStringConvertible {
        case notSignedIn
        case http(Int, String)
        var description: String {
            switch self {
            case .notSignedIn: return "not signed in to Firebase"
            case .http(let c, let b): return "firestore HTTP \(c): \(b.prefix(160))"
            }
        }
    }

    func writeSnapshot(_ snapshot: ContextSnapshot, userId: String) async throws {
        let token = try await AuthService.shared.refreshIfNeeded()
        let id    = snapshot.id.uuidString
        let url   = URL(string: "\(FirebaseConfig.firestoreBaseURL)/snapshots/\(id)?updateMask.fieldPaths=*")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: Self.encode(snapshot: snapshot, userId: userId))
        try await Self.send(req)
    }

    func writeAgentRun(_ run: AgentRunRecord, userId: String) async throws {
        let token = try await AuthService.shared.refreshIfNeeded()
        let id    = run.id.uuidString
        let url   = URL(string: "\(FirebaseConfig.firestoreBaseURL)/agentRuns/\(id)?updateMask.fieldPaths=*")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: Self.encode(run: run, userId: userId))
        try await Self.send(req)
    }

    // MARK: - Wire

    private static func send(_ req: URLRequest) async throws {
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Firestore document encoding
    // Firestore REST wants values in its tagged form: { stringValue: "..." }, etc.

    static func encode(snapshot s: ContextSnapshot, userId: String) -> [String: Any] {
        var fields: [String: Any] = [
            "userId":        ["stringValue": userId],
            "id":            ["stringValue": s.id.uuidString],
            "capturedAt":    ["timestampValue": iso(s.capturedAt)],
            "source":        ["stringValue": s.source.rawValue],
            "workspacePath": ["stringValue": s.workspacePath],
        ]
        if let g = s.gitState {
            fields["gitBranch"]      = ["stringValue": g.branch]
            fields["gitCommit"]      = ["stringValue": g.lastCommit]
            fields["changedFiles"]   = arrayOfStrings(g.changedFiles)
            fields["recentCommits"]  = arrayOfStrings(g.recentCommits)
        }
        fields["activeFiles"]     = arrayOfStrings(s.activeFiles)
        fields["terminalHistory"] = arrayOfStrings(s.terminalHistory)
        fields["editCount"]       = ["integerValue": String(s.recentEdits.count)]
        return ["fields": fields]
    }

    static func encode(run r: AgentRunRecord, userId: String) -> [String: Any] {
        var fields: [String: Any] = [
            "userId":     ["stringValue": userId],
            "id":         ["stringValue": r.id.uuidString],
            "task":       ["stringValue": r.task],
            "status":     ["stringValue": r.status.rawValue],
            "startedAt":  ["timestampValue": iso(r.startedAt)],
            "transcript": arrayOfStrings(r.transcript),
        ]
        if let f = r.finishedAt { fields["finishedAt"] = ["timestampValue": iso(f)] }
        if let e = r.error      { fields["error"]      = ["stringValue": e] }
        return ["fields": fields]
    }

    private static func arrayOfStrings(_ items: [String]) -> [String: Any] {
        ["arrayValue": ["values": items.map { ["stringValue": $0] }]]
    }

    private static let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static func iso(_ d: Date) -> String { isoFmt.string(from: d) }
}
