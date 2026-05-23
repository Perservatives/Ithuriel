import Foundation

enum IthurielAPIError: Error {
    case notAuthenticated
    case httpStatus(Int)
    case decoding(Error)
    case transport(Error)
}

final class IthurielClient {
    private let baseURL: URL
    private let staticToken: String?
    private let session: URLSession
    private let maxAttempts = 4

    init(prefs: UserPrefs, session: URLSession = .shared) {
        self.baseURL = URL(string: prefs.apiBaseURL) ?? URL(string: "https://api.ithuriel.dev")!
        // Fallback static bearer for dev/test. Production uses Firebase ID token via AuthService.
        self.staticToken = prefs.apiToken.isEmpty ? nil : prefs.apiToken
        self.session = session
        AuthService.shared.apiBaseURL = prefs.apiBaseURL
        AuthService.shared.firebaseWebAPIKey = prefs.firebaseWebAPIKey
    }

    func postAgentRun(_ run: AgentRunRecord) async throws {
        let url = baseURL.appendingPathComponent("/v1/agent/run")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await attachAuth(&req)
        req.httpBody = try JSONEncoder.ithuriel.encode(run)
        _ = try await sendWithRetry(req)
    }

    func postSnapshot(_ snapshot: ContextSnapshot) async throws {
        let url = baseURL.appendingPathComponent("/v1/context/snapshot")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try await attachAuth(&req)
        req.httpBody = try JSONEncoder.ithuriel.encode(snapshot)
        _ = try await sendWithRetry(req)
    }

    func fetchCurrent(format tool: AITool) async throws -> ContextSnapshot {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/context/current"),
                                       resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "format", value: tool.rawValue)]
        guard let url = components?.url else { throw IthurielAPIError.transport(URLError(.badURL)) }
        var req = URLRequest(url: url)
        try await attachAuth(&req)
        let data = try await sendWithRetry(req)
        do {
            return try JSONDecoder.ithuriel.decode(ContextSnapshot.self, from: data)
        } catch {
            throw IthurielAPIError.decoding(error)
        }
    }

    func openStream(onMessage: @escaping (ContextSnapshot) -> Void) throws -> URLSessionWebSocketTask {
        guard let token = staticToken else { throw IthurielAPIError.notAuthenticated }
        var components = URLComponents(url: baseURL.appendingPathComponent("/v1/context/stream"),
                                       resolvingAgainstBaseURL: false)
        if components?.scheme == "https" { components?.scheme = "wss" }
        if components?.scheme == "http" { components?.scheme = "ws" }
        guard let url = components?.url else { throw IthurielAPIError.transport(URLError(.badURL)) }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: req)
        task.resume()
        receive(task: task, onMessage: onMessage)
        return task
    }

    // MARK: - Internals

    private func attachAuth(_ req: inout URLRequest) async throws {
        if AuthService.shared.isSignedIn {
            let token = try await AuthService.shared.refreshIfNeeded()
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return
        }
        guard let token = staticToken else { throw IthurielAPIError.notAuthenticated }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func sendWithRetry(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        var lastError: Error?
        while attempt < maxAttempts {
            attempt += 1
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw IthurielAPIError.transport(URLError(.badServerResponse)) }
                if (200..<300).contains(http.statusCode) { return data }
                if http.statusCode == 401 || http.statusCode == 403 {
                    throw IthurielAPIError.httpStatus(http.statusCode)
                }
                lastError = IthurielAPIError.httpStatus(http.statusCode)
            } catch {
                lastError = error
            }
            let delay = pow(2.0, Double(attempt)) * 0.5
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        throw lastError ?? IthurielAPIError.transport(URLError(.unknown))
    }

    private func receive(task: URLSessionWebSocketTask, onMessage: @escaping (ContextSnapshot) -> Void) {
        task.receive { [weak self] result in
            switch result {
            case .failure(let error):
                Log.error("WebSocket error: \(error)")
            case .success(let message):
                let data: Data?
                switch message {
                case .data(let d): data = d
                case .string(let s): data = s.data(using: .utf8)
                @unknown default: data = nil
                }
                if let data = data,
                   let snap = try? JSONDecoder.ithuriel.decode(ContextSnapshot.self, from: data) {
                    onMessage(snap)
                }
                self?.receive(task: task, onMessage: onMessage)
            }
        }
    }
}

extension JSONEncoder {
    static let ithuriel: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let ithuriel: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
