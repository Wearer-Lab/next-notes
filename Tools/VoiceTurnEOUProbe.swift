import AVFoundation
import CoreML
import CryptoKit
import FluidAudio
import Foundation

/// Diagnostic only: observe the existing recognizer's native EOU on the original
/// unmodified PCM. Unpaced sample positions are NOT wall-clock endpoint latency.
@main
enum VoiceTurnEOUProbe {
    struct Fixture: Decodable {
        let id: String; let wav: String; let audioSHA256: String
        let speechEndMS: Double; let protectedIntervalsMS: [[Double]]
    }
    struct Manifest: Decodable { let fixtures: [Fixture] }
    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var sampleEnd = 0
        private var events: [[String: Any]] = []
        func position(_ sample: Int) { lock.lock(); sampleEnd = sample; lock.unlock() }
        func record(_ kind: String, text: String) {
            lock.lock(); defer { lock.unlock() }
            events.append(["kind": kind, "sample_end": sampleEnd, "text": text])
        }
        func take() -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return events }
    }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = URL(fileURLWithPath: args[1])
        let root = URL(fileURLWithPath: args[2])
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(".nextnotes-turn-fixture").path),
              ModelNames.ParakeetEOU.requiredModels.allSatisfy({
                  FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
              }),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                  sampleRate: 16_000, channels: 1, interleaved: false) else { throw CocoaError(.fileReadNoPermission) }
        let manifest = try JSONDecoder().decode(Manifest.self,
            from: Data(contentsOf: root.appendingPathComponent("fixtures.json")))
        var rows: [[String: Any]] = []
        for debounce in [0, 320] {
            let config = MLModelConfiguration() // Same default .all as LocalVoiceTurnDetector.
            let manager = StreamingEouAsrManager(configuration: config, chunkSize: .ms160, eouDebounceMs: debounce)
            try await manager.loadModels(from: directory)
            for fixture in manifest.fixtures {
                await manager.reset()
                let events = Events()
                await manager.setPartialCallback { events.record("partial", text: $0) }
                await manager.setEouCallback { events.record("eou", text: $0) }
                let digest = SHA256.hash(data: try Data(contentsOf: root.appendingPathComponent(fixture.wav)))
                    .map { String(format: "%02x", $0) }.joined()
                guard digest == fixture.audioSHA256 else { throw CocoaError(.fileReadCorruptFile) }
                let file = try AVAudioFile(forReading: root.appendingPathComponent(fixture.wav),
                    commonFormat: .pcmFormatFloat32, interleaved: false)
                guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
                      file.length < 16_000 * 60,
                      let full = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
                    throw CocoaError(.coderInvalidValue)
                }
                try file.read(into: full)
                let pcm = Array(UnsafeBufferPointer(start: full.floatChannelData![0], count: Int(full.frameLength)))
                    + [Float](repeating: 0, count: 32_000)
                for start in stride(from: 0, to: pcm.count, by: 160) {
                    let end = min(start + 160, pcm.count)
                    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - start))!
                    buffer.frameLength = AVAudioFrameCount(end - start)
                    pcm.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress! + start, count: end - start) }
                    events.position(end)
                    _ = try await manager.process(audioBuffer: buffer)
                }
                rows.append(["case": fixture.id, "debounce_ms": debounce,
                    "events": events.take(), "audio_sha256": fixture.audioSHA256,
                    "speech_end_ms": fixture.speechEndMS,
                    "protected_intervals_ms": fixture.protectedIntervalsMS])
            }
            await manager.cleanup()
        }
        let report: [String: Any] = ["rows": rows,
            "scope": "Native streaming EOU evidence on original PCM, unpaced160-sample ingestion; sample positions only, no app commit, playback or latency claim."]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    }
}
