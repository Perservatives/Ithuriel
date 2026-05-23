import Foundation

/// Lightweight Gemini API client with function-calling support.
/// Uses the v1beta `generateContent` endpoint so we get tool-use.
final class GeminiClient {
    struct Part: Codable {
        var text: String?
        var inlineData: InlineData?
        var functionCall: FunctionCall?
        var functionResponse: FunctionResponse?
        /// Required by Gemini 3.x thinking models — must round-trip on functionCall parts.
        var thoughtSignature: String?
        /// Marks reasoning text parts returned alongside tool calls.
        var thought: Bool?

        init(text: String? = nil,
             inlineData: InlineData? = nil,
             functionCall: FunctionCall? = nil,
             functionResponse: FunctionResponse? = nil,
             thoughtSignature: String? = nil,
             thought: Bool? = nil) {
            self.text = text
            self.inlineData = inlineData
            self.functionCall = functionCall
            self.functionResponse = functionResponse
            self.thoughtSignature = thoughtSignature
            self.thought = thought
        }

        struct InlineData: Codable {
            let mimeType: String
            let data: String  // base64
        }

        struct FunctionCall: Codable {
            let name: String
            let args: [String: AnyJSON]
        }

        struct FunctionResponse: Codable {
            let name: String
            let response: [String: AnyJSON]
        }
    }

    struct Content: Codable {
        let role: String  // "user" | "model"
        var parts: [Part]

        init(role: String, parts: [Part]) {
            self.role = role
            self.parts = parts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            role = try c.decodeIfPresent(String.self, forKey: .role) ?? "model"
            parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
        }
    }

    struct Tool: Codable {
        let functionDeclarations: [FunctionDeclaration]
    }

    struct FunctionDeclaration: Codable {
        let name: String
        let description: String
        let parameters: Schema
    }

    struct Schema: Codable {
        let type: String  // "OBJECT", "STRING", etc.
        var properties: [String: Schema]?
        var items: SchemaBox?
        var required: [String]?
        var description: String?
    }

    /// Indirect wrapper so `items: Schema` can self-reference inside arrays.
    final class SchemaBox: Codable {
        let schema: Schema
        init(_ schema: Schema) { self.schema = schema }
        init(from decoder: Decoder) throws {
            self.schema = try Schema(from: decoder)
        }
        func encode(to encoder: Encoder) throws {
            try schema.encode(to: encoder)
        }
    }

    struct GenerateRequest: Codable {
        let contents: [Content]
        let tools: [Tool]?
        let systemInstruction: Content?
    }

    struct GenerateResponse: Codable {
        struct PromptFeedback: Codable {
            let blockReason: String?
        }
        struct Candidate: Codable {
            let content: Content?
            let finishReason: String?
        }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = GeminiModels.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = GeminiModels.normalize(model)
        self.session = session
    }

    /// One round-trip: send the running conversation, get the next model turn.
    func step(contents: [Content], tools: [Tool], system: String) async throws -> Content {
        guard !apiKey.isEmpty else { throw GeminiError.missingKey }
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = GenerateRequest(
            contents: contents,
            tools: tools.isEmpty ? nil : tools,
            systemInstruction: Content(role: "user", parts: [Part(text: system)])
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GeminiError.http(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = Self.apiErrorMessage(from: data) ?? String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http(http.statusCode, snippet)
        }

        let decoded: GenerateResponse
        do {
            decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        } catch {
            let snippet = Self.apiErrorMessage(from: data) ?? String(data: data, encoding: .utf8)?.prefix(240).description ?? "\(error)"
            throw GeminiError.decode(snippet)
        }

        if let block = decoded.promptFeedback?.blockReason, !block.isEmpty {
            throw GeminiError.blocked(block)
        }

        guard let candidate = decoded.candidates?.first else {
            throw GeminiError.noCandidate
        }

        guard let content = candidate.content else {
            if let reason = candidate.finishReason, !reason.isEmpty {
                throw GeminiError.finishReason(reason)
            }
            throw GeminiError.noCandidate
        }

        guard !content.parts.isEmpty else {
            if let reason = candidate.finishReason, !reason.isEmpty {
                throw GeminiError.finishReason(reason)
            }
            throw GeminiError.emptyResponse
        }

        return content
    }

    /// Pull a human-readable message out of a Google API error envelope.
    private static func apiErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}

// MARK: - Supported models (Google AI `generateContent` model IDs)

enum GeminiModels {
    static let pickerOptions: [(id: String, label: String)] = [
        ("gemini-2.5-flash", "Flash 2.5 · fast"),
        ("gemini-2.5-flash-lite", "Flash 2.5 · lite"),
        ("gemini-2.5-pro", "Pro 2.5"),
        ("gemini-3.5-flash", "Flash 3.5"),
        ("gemini-3-flash-preview", "Flash 3 · preview"),
        ("gemini-3.1-pro-preview", "Pro 3.1 · preview"),
    ]

    static let defaultModel = "gemini-2.5-flash"

    private static let validIDs = Set(pickerOptions.map(\.id))

    /// Maps saved prefs / legacy picker values to a real API model id.
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if validIDs.contains(trimmed) { return trimmed }
        switch trimmed {
        case "gemini-2.5-flash-thinking": return defaultModel
        case "gemini-3.0-flash", "gemini-3-flash": return "gemini-3-flash-preview"
        case "gemini-3.0-pro", "gemini-3-pro", "gemini-3-pro-preview": return "gemini-3.1-pro-preview"
        default: return defaultModel
        }
    }
}

enum GeminiError: Error, CustomStringConvertible {
    case missingKey
    case http(Int, String)
    case decode(String)
    case noCandidate
    case emptyResponse
    case blocked(String)
    case finishReason(String)
    var description: String {
        switch self {
        case .missingKey: return "Gemini API key not set (Settings → Agent)."
        case .http(let code, let body): return "Gemini HTTP \(code): \(body.prefix(200))"
        case .decode(let detail): return "Gemini response parse error: \(detail.prefix(200))"
        case .noCandidate: return "Gemini returned no candidates."
        case .emptyResponse: return "Gemini returned an empty response. Try again or switch models."
        case .blocked(let reason): return "Gemini blocked the request (\(reason))."
        case .finishReason(let reason): return "Gemini stopped early (\(reason))."
        }
    }
}

/// Type-erased JSON value so Codable can round-trip arbitrary args.
enum AnyJSON: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyJSON])
    case array([AnyJSON])
    case null

    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var numberValue: Double? { if case .number(let n) = self { return n } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var arrayValue: [AnyJSON]? { if case .array(let a) = self { return a } else { return nil } }
    var objectValue: [String: AnyJSON]? { if case .object(let o) = self { return o } else { return nil } }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyJSON].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }
}
