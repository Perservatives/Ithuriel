import Foundation
import AVFoundation

/// Google Cloud Speech-to-Text and Text-to-Speech REST clients.
/// Uses an API key (`UserPrefs.googleCloudAPIKey`) — same key works for
/// both endpoints when the project has the relevant APIs enabled.
enum GoogleSpeech {
    enum Error: Swift.Error, CustomStringConvertible {
        case missingKey
        case http(Int, String)
        case empty
        var description: String {
            switch self {
            case .missingKey: return "Google Cloud API key not set (Settings → Voice)."
            case .http(let code, let body): return "Google Cloud HTTP \(code): \(body.prefix(180))"
            case .empty: return "Empty response from Google Cloud."
            }
        }
    }

    // MARK: - Speech-to-Text

    /// Sends 16 kHz mono PCM-16 audio to Cloud Speech v1 `recognize`.
    static func transcribe(pcm16: Data, apiKey: String, languageCode: String = "en-US") async throws -> String {
        guard !apiKey.isEmpty else { throw Error.missingKey }
        let url = URL(string: "https://speech.googleapis.com/v1/speech:recognize?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "config": [
                "encoding": "LINEAR16",
                "sampleRateHertz": 16_000,
                "languageCode": languageCode,
                "model": "latest_short",
                "enableAutomaticPunctuation": true
            ],
            "audio": ["content": pcm16.base64EncodedString()]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Error.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                             String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return "" }
        var pieces: [String] = []
        for r in results {
            if let alt = (r["alternatives"] as? [[String: Any]])?.first,
               let text = alt["transcript"] as? String {
                pieces.append(text)
            }
        }
        return pieces.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Text-to-Speech

    /// Synthesizes speech as MP3, returns the audio bytes for playback.
    static func synthesize(text: String, apiKey: String,
                           voice: String = "en-US-Neural2-F",
                           rate: Double = 1.0) async throws -> Data {
        guard !apiKey.isEmpty else { throw Error.missingKey }
        let url = URL(string: "https://texttospeech.googleapis.com/v1/text:synthesize?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "input": ["text": text],
            "voice": ["languageCode": "en-US", "name": voice],
            "audioConfig": ["audioEncoding": "MP3", "speakingRate": rate]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Error.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                             String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let b64 = json["audioContent"] as? String,
              let audio = Data(base64Encoded: b64) else { throw Error.empty }
        return audio
    }
}
