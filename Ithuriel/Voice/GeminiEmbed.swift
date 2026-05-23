import Foundation

/// Gemini-flavoured text embedding via the Generative Language API.
///
/// Why this exists:
///   - A consumer Gemini API key (from aistudio.google.com) only has the
///     Generative Language surface enabled. The Vertex AI embedding endpoints
///     and the older `text-embedding-004` / `embedding-001` aliases all return
///     404 against this key.
///   - `models/gemini-embedding-001:embedContent` is part of that surface and
///     works with the same `?key=` auth shape as `GeminiTTS`.
///   - Default output is 3072-dim. We request `outputDimensionality: 768` to
///     match the tree-AH index provisioned in `infra/terraform/vector_search.tf`.
enum GeminiEmbed {
    enum Failure: Error, CustomStringConvertible {
        case missingKey
        case http(Int, String)
        case empty
        var description: String {
            switch self {
            case .missingKey: return "Gemini API key not set."
            case .http(let code, let body): return "Gemini Embed HTTP \(code): \(body.prefix(180))"
            case .empty: return "Gemini Embed returned no vector."
            }
        }
    }

    /// Task types supported by gemini-embedding-001. Pick `retrievalDocument`
    /// for indexed memory chunks and `retrievalQuery` for live lookups so the
    /// model produces asymmetric embeddings tuned for that direction.
    enum TaskType: String {
        case retrievalDocument = "RETRIEVAL_DOCUMENT"
        case retrievalQuery = "RETRIEVAL_QUERY"
        case semanticSimilarity = "SEMANTIC_SIMILARITY"
        case classification = "CLASSIFICATION"
        case clustering = "CLUSTERING"
        case questionAnswering = "QUESTION_ANSWERING"
        case factVerification = "FACT_VERIFICATION"
    }

    /// Embeds `text` and returns the vector as `[Float]`.
    static func embed(text: String,
                      apiKey: String,
                      model: String = "gemini-embedding-001",
                      dimensions: Int = 768,
                      taskType: TaskType = .retrievalDocument) async throws -> [Float] {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):embedContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw Failure.empty }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "models/\(model)",
            "content": ["parts": [["text": text]]],
            "taskType": taskType.rawValue,
            "outputDimensionality": dimensions
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let embedding = json["embedding"] as? [String: Any],
              let values = embedding["values"] as? [Double]
        else { throw Failure.empty }

        return values.map { Float($0) }
    }
}
