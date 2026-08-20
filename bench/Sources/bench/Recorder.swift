import AVFoundation
import Foundation

/// Records the microphone to a 16 kHz mono WAV — the format both engines want, so no
/// resampling difference can bias the comparison.
enum Recorder {
    static func record(to url: URL) async throws {
        guard await requestMicrophone() else {
            throw BenchError.message("""
                Microphone access denied.

                A SwiftPM command-line binary isn't an app bundle, so macOS attributes the
                request to the terminal running it. Grant your terminal (Terminal, iTerm,
                Cursor, VS Code…) microphone access in:
                  System Settings ▸ Privacy & Security ▸ Microphone
                """)
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { throw BenchError.message("couldn't build 16 kHz mono format") }

        let file = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )

        let converter = nativeFormat == targetFormat ? nil : AVAudioConverter(from: nativeFormat, to: targetFormat)
        nonisolated(unsafe) let sink = file
        nonisolated(unsafe) let conv = converter

        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { buffer, _ in
            guard let conv else {
                try? sink.write(from: buffer)
                return
            }
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

            nonisolated(unsafe) let input = buffer
            var handed = false
            var error: NSError?
            _ = conv.convert(to: out, error: &error) { _, status in
                if handed { status.pointee = .noDataNow; return nil }
                handed = true
                status.pointee = .haveData
                return input
            }
            if error == nil, out.frameLength > 0 { try? sink.write(from: out) }
        }

        engine.prepare()
        try engine.start()

        print("🔴 Recording — press RETURN to stop.")
        _ = readLine()

        input.removeTap(onBus: 0)
        engine.stop()

        let duration = Double(file.length) / 16_000
        print(String(format: "✅ Saved %@ (%.1fs)", url.lastPathComponent, duration))
    }

    private static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}

struct BenchError: LocalizedError {
    let text: String
    static func message(_ text: String) -> BenchError { BenchError(text: text) }
    var errorDescription: String? { text }
}
