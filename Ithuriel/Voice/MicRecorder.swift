import AVFoundation
import Foundation

/// Records microphone input to a temporary 16 kHz mono WAV file using
/// `AVAudioRecorder` — more reliable on macOS than manual AVAudioEngine taps.
final class MicRecorder: @unchecked Sendable {
    private var recorder: AVAudioRecorder?
    private var tempURL: URL?
    private(set) var isRecording = false

    func requestPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() throws {
        guard !isRecording else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ithuriel-voice-\(UUID().uuidString).wav")
        tempURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.isMeteringEnabled = false
        guard rec.prepareToRecord() else {
            throw MicRecorderError.prepareFailed
        }
        guard rec.record() else {
            throw MicRecorderError.recordFailed
        }
        recorder = rec
        isRecording = true
    }

    func stop() -> Data {
        guard isRecording, let rec = recorder, let url = tempURL else { return Data() }
        rec.stop()
        isRecording = false
        recorder = nil

        defer {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }
}

enum MicRecorderError: LocalizedError {
    case prepareFailed
    case recordFailed

    var errorDescription: String? {
        switch self {
        case .prepareFailed: return "Could not prepare the microphone."
        case .recordFailed:  return "Could not start recording."
        }
    }
}
