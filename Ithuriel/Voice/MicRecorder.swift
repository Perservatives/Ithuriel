import AVFoundation
import Foundation

/// Captures the default input device at 16 kHz mono PCM-16 — the canonical
/// format Google Cloud Speech-to-Text accepts. Hands back a single linear
/// PCM buffer when `stop()` is called.
@MainActor
final class MicRecorder {
    private let engine = AVAudioEngine()
    private var samples: [Int16] = []
    private let targetSampleRate: Double = 16_000
    private var converter: AVAudioConverter?
    private(set) var isRecording = false

    func requestPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    func start() throws {
        guard !isRecording else { return }
        samples.removeAll(keepingCapacity: true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: targetSampleRate,
                                         channels: 1,
                                         interleaved: true) else {
            throw NSError(domain: "MicRecorder", code: -1)
        }
        converter = AVAudioConverter(from: inputFormat, to: target)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, to: target)
        }

        try engine.start()
        isRecording = true
    }

    func stop() -> Data {
        guard isRecording else { return Data() }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private func process(buffer src: AVAudioPCMBuffer, to target: AVAudioFormat) {
        guard let converter else { return }
        let ratio = target.sampleRate / src.format.sampleRate
        let capacity = AVAudioFrameCount(Double(src.frameLength) * ratio + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            status.pointee = .haveData
            return src
        }
        if let error { print("MicRecorder convert error: \(error)"); return }
        guard let channel = out.int16ChannelData else { return }
        let frames = Int(out.frameLength)
        let ptr = channel[0]
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: frames))
    }
}
