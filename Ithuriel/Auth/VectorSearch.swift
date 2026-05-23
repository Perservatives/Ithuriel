import Foundation

/// Client-side semantic search over the user's snapshot subcollection in
/// Firestore. Embeds the query with Gemini (768-d, `RETRIEVAL_QUERY` task
/// type so it pairs with the `RETRIEVAL_DOCUMENT` vectors written on
/// capture), then runs Firestore's `findNearest` operator against the
/// composite vector index keyed on the `embedding` field.
///
/// This is the local, no-backend path. It hits Firestore directly with the
/// user's Firebase ID token — no Cloud Run hop, no Pub/Sub processor — and
/// returns the top-k snapshot ids ranked by EUCLIDEAN distance to the query.
enum VectorSearch {
    enum Failure: Error, CustomStringConvertible {
        case notSignedIn
        case missingKey
        case http(Int, String)
        case decoding(String)
        var description: String {
            switch self {
            case .notSignedIn: return "VectorSearch: not signed in"
            case .missingKey:  return "VectorSearch: Gemini key missing"
            case .http(let c, let b): return "VectorSearch HTTP \(c): \(b.prefix(180))"
            case .decoding(let s):    return "VectorSearch decode: \(s)"
            }
        }
    }

    /// Returns the top-`k` nearest snapshot ids + their EUCLIDEAN distance
    /// scores. Caller passes a natural-language query; the function embeds
    /// it and asks Firestore for the closest documents in the user's
    /// subcollection. Throws on auth / key / transport / decode failures —
    /// callers should treat any error as "no related context".
    static func nearest(query: String,
                        k: Int = 5,
                        prefs: UserPrefs) async throws -> [(id: String, score: Double)] {
        guard AuthService.shared.isSignedIn else { throw Failure.notSignedIn }
        guard !prefs.geminiApiKey.isEmpty else { throw Failure.missingKey }

        // 1) Embed the query (asymmetric: RETRIEVAL_QUERY pairs with the
        //    RETRIEVAL_DOCUMENT vectors written at capture time).
        let vector = try await GeminiEmbed.embed(
            text: query,
            apiKey: prefs.geminiApiKey,
            dimensions: 768,
            taskType: .retrievalQuery
        )

        // 2) Resolve the user's Firebase uid (sub claim of the ID token).
        let token = try await AuthService.shared.refreshIfNeeded()
        guard let uid = decodeUID(from: token) else { throw Failure.notSignedIn }

        // 3) POST a runQuery with a findNearest clause against the user's
        //    snapshots subcollection. The composite index `CICAgJiUsZIK`
        //    covers `embedding` with 768 dims + EUCLIDEAN, so this matches
        //    without further configuration.
        let parent = "projects/\(FirebaseConfig.projectId)/databases/(default)/documents/users/\(uid)"
        let url = URL(string: "https://firestore.googleapis.com/v1/\(parent):runQuery")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let queryVector: [[String: Any]] = vector.map { ["doubleValue": Double($0)] }
        let body: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": "snapshots"]],
                "findNearest": [
                    "vectorField": ["fieldPath": "embedding"],
                    "queryVector": ["vectorValue": ["values": queryVector]],
                    "distanceMeasure": "EUCLIDEAN",
                    "limit": k
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }

        // 4) Decode the runQuery response. Each element is `{ document: { name, fields }, ... }`.
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure.decoding("expected array")
        }
        var out: [(id: String, score: Double)] = []
        for entry in arr {
            guard let doc = entry["document"] as? [String: Any],
                  let name = doc["name"] as? String else { continue }
            let id = (name as NSString).lastPathComponent
            // findNearest doesn't return a distance by default; we surface
            // the rank ordering as the score (0 = closest) when absent.
            let score: Double
            if let s = entry["distance"] as? Double { score = s }
            else if let s = (entry["distance"] as? NSNumber)?.doubleValue { score = s }
            else { score = Double(out.count) }
            out.append((id: id, score: score))
        }
        return out
    }

    /// Pulls the `sub` / `user_id` claim out of a Firebase ID token without
    /// dragging in a JWT library. Mirrors `IthurielClient.currentFirebaseUID`.
    private static func decodeUID(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        while payload.count % 4 != 0 { payload.append("=") }
        payload = payload.replacingOccurrences(of: "-", with: "+")
                         .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["user_id"] as? String) ?? (json["sub"] as? String)
    }
}
