import Foundation

/// Gemini-flavoured text-to-speech via the Generative Language API.
///
/// Why this exists alongside `GoogleSpeech.synthesize` (Cloud TTS):
///   - A Gemini API key (the one a user pastes from aistudio.google.com)
///     normally has Service restrictions that block `texttospeech.googleapis.com`
///     with `API_KEY_SERVICE_BLOCKED`.
///   - `generativelanguage.googleapis.com/models/gemini-2.5-flash-preview-tts`
///     is part of the Generative Language surface that the key already has
///     access to, so it works out of the box with zero GCP setup.
///   - Returns raw 24 kHz mono PCM — we wrap a minimal WAV header so
///     `AVAudioPlayer(data:)` can play the result.
enum GeminiTTS {
    enum Failure: Error, CustomStringConvertible {
        case missingKey
        case http(Int, String)
        case empty
        case decodeFailed
        var description: String {
            switch self {
            case .missingKey: return "Gemini API key not set."
            case .http(let code, let body): return "Gemini TTS HTTP \(code): \(body.prefix(180))"
            case .empty: return "Gemini TTS returned no audio."
            case .decodeFailed: return "Gemini TTS audio could not be base64 decoded."
            }
        }
    }

    /// Synthesizes `text` and returns playable WAV bytes.
    /// Default voice is "Kore" — neutral, conversational. Other voices:
    /// "Puck", "Charon", "Zephyr", "Algieba", etc. (see Gemini TTS docs).
    static func synthesize(text: String,
                           apiKey: String,
                           voice: String = "Kore",
                           model: String = "gemini-2.5-flash-preview-tts") async throws -> Data {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpoint) else { throw Failure.empty }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "contents": [["parts": [["text": text]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": [
                        "prebuiltVoiceConfig": ["voiceName": voice]
                    ]
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]]
        else { throw Failure.empty }

        var pcm = Data()
        var sampleRate = 24_000
        for part in parts {
            guard let inline = part["inlineData"] as? [String: Any],
                  let b64 = inline["data"] as? String,
                  let chunk = Data(base64Encoded: b64) else { continue }
            pcm.append(chunk)
            // mimeType looks like: audio/L16;codec=pcm;rate=24000
            if let mime = inline["mimeType"] as? String,
               let rateMatch = mime.split(separator: ";").first(where: { $0.contains("rate=") }),
               let rate = Int(rateMatch.split(separator: "=").last ?? "") {
                sampleRate = rate
            }
        }
        guard !pcm.isEmpty else { throw Failure.empty }
        return wrapPCMAsWAV(pcm: pcm, sampleRate: sampleRate, channels: 1, bitsPerSample: 16)
    }

    /// Prepend a 44-byte RIFF/WAVE header so AVAudioPlayer accepts the bytes.
    private static func wrapPCMAsWAV(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcm.count
        let chunkSize = 36 + dataSize

        var header = Data()
        header.append("RIFF".data(using: .ascii)!)
        header.append(UInt32(chunkSize).leBytes)
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(UInt32(16).leBytes)                            // subchunk size
        header.append(UInt16(1).leBytes)                             // PCM
        header.append(UInt16(channels).leBytes)
        header.append(UInt32(sampleRate).leBytes)
        header.append(UInt32(byteRate).leBytes)
        header.append(UInt16(blockAlign).leBytes)
        header.append(UInt16(bitsPerSample).leBytes)
        header.append("data".data(using: .ascii)!)
        header.append(UInt32(dataSize).leBytes)
        header.append(pcm)
        return header
    }
}

private extension UInt32 {
    var leBytes: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
private extension UInt16 {
    var leBytes: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
