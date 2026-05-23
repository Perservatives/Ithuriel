import Foundation

/// OpenAI Audio API client — text-to-speech (`/v1/audio/speech`) and
/// speech-to-text (`/v1/audio/transcriptions`, Whisper).
///
/// One API key handles both, billed per character (TTS) / per minute (STT).
/// Consumer flow: paste an `sk-…` key in Settings → Integrations and the
/// agent speaks + listens out of the box.
enum OpenAISpeech {
    enum Failure: Error, CustomStringConvertible {
        case missingKey
        case http(Int, String)
        case empty
        var description: String {
            switch self {
            case .missingKey:           return "OpenAI API key not set (Settings → Integrations)."
            case .http(let c, let b):   return "OpenAI HTTP \(c): \(b.prefix(180))"
            case .empty:                return "Empty response from OpenAI."
            }
        }
    }

    // MARK: - Text-to-speech

    /// Returns MP3 audio bytes ready for `AVAudioPlayer(data:)`.
    /// Model: `tts-1` (fast), `tts-1-hd` (higher quality), `gpt-4o-mini-tts`.
    /// Voices: alloy / ash / ballad / coral / echo / fable / nova / onyx /
    /// sage / shimmer.
    static func synthesize(text: String,
                           apiKey: String,
                           model: String = "gpt-4o-mini-tts",
                           voice: String = "alloy",
                           speed: Double = 1.0) async throws -> Data {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { throw Failure.empty }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "model": model,
            "input": text,
            "voice": voice,
            "response_format": "mp3",
            "speed": speed
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }
        guard !data.isEmpty else { throw Failure.empty }
        return data
    }

    // MARK: - Speech-to-text (Whisper)

    /// Transcribes 16 kHz mono PCM-16 audio via Whisper.
    /// Wraps the raw PCM in a WAV header and posts as multipart form-data
    /// so the upload looks like a normal audio file.
    static func transcribe(pcm16: Data,
                           apiKey: String,
                           model: String = "whisper-1",
                           language: String = "en") async throws -> String {
        guard !apiKey.isEmpty else { throw Failure.missingKey }
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else { throw Failure.empty }
        let wav = wrapPCMAsWAV(pcm: pcm16, sampleRate: 16_000, channels: 1, bitsPerSample: 16)

        let boundary = "----IthurielBoundary\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("language", language)
        field("response_format", "text")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.http((resp as? HTTPURLResponse)?.statusCode ?? -1,
                               String(data: data, encoding: .utf8) ?? "")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WAV header helper

    private static func wrapPCMAsWAV(pcm: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = pcm.count
        let chunkSize = 36 + dataSize

        var h = Data()
        h.append("RIFF".data(using: .ascii)!)
        h.append(UInt32(chunkSize).leBytes)
        h.append("WAVE".data(using: .ascii)!)
        h.append("fmt ".data(using: .ascii)!)
        h.append(UInt32(16).leBytes)
        h.append(UInt16(1).leBytes)
        h.append(UInt16(channels).leBytes)
        h.append(UInt32(sampleRate).leBytes)
        h.append(UInt32(byteRate).leBytes)
        h.append(UInt16(blockAlign).leBytes)
        h.append(UInt16(bitsPerSample).leBytes)
        h.append("data".data(using: .ascii)!)
        h.append(UInt32(dataSize).leBytes)
        h.append(pcm)
        return h
    }
}

private extension UInt32 {
    var leBytes: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
private extension UInt16 {
    var leBytes: Data { withUnsafeBytes(of: littleEndian) { Data($0) } }
}
