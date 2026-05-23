import Foundation

/// Lightweight Gemini API client with function-calling support.
/// Uses the v1beta `generateContent` endpoint so we get tool-use.
final class GeminiClient {
    struct Part: Codable {
        var text: String?
        var inlineData: InlineData?
        var functionCall: FunctionCall?
        var functionResponse: FunctionResponse?

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
        let role: String  // "user" | "model" | "function"
        var parts: [Part]
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
        struct Candidate: Codable { let content: Content }
        let candidates: [Candidate]?
    }

    private let apiKey: String
    private let model: String
    private let session: URLSession

    init(apiKey: String, model: String = "gemini-2.0-flash-exp", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
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
            systemInstruction: Content(role: "user", parts: [Part(text: system, inlineData: nil, functionCall: nil, functionResponse: nil)])
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data, encoding: .utf8) ?? ""
            throw GeminiError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, snippet)
        }
        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        guard let first = decoded.candidates?.first?.content else {
            throw GeminiError.noCandidate
        }
        return first
    }
}

enum GeminiError: Error, CustomStringConvertible {
    case missingKey
    case http(Int, String)
    case noCandidate
    var description: String {
        switch self {
        case .missingKey: return "Gemini API key not set (Settings → Agent)."
        case .http(let code, let body): return "Gemini HTTP \(code): \(body.prefix(200))"
        case .noCandidate: return "Gemini returned no candidates."
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
