import AVFoundation
import Foundation
import FluidAudio
import Speech

/// One engine's result, timed identically so the numbers are comparable.
struct EngineRun: Codable {
    let engine: String
    let detail: String
    /// Seconds to get models ready. Apple's are OS-managed and usually already resident;
    /// Parakeet's are downloaded once then loaded from disk.
    let loadSeconds: Double
    /// Seconds of wall clock spent turning the audio into final text.
    let processSeconds: Double
    /// Audio seconds processed per wall-clock second. Higher is faster.
    let realtimeFactor: Double
    let text: String
    var wer: Double?
    var cer: Double?
}

// MARK: - Apple SpeechAnalyzer

enum AppleEngine {
    static func run(url: URL, audioDuration: Double) async throws -> EngineRun {
        let loadStart = Date()

        guard SpeechTranscriber.isAvailable else {
            throw BenchError.message("SpeechTranscriber unavailable on this Mac")
        }
        let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
            ?? Locale(identifier: "en-US")

        // `.transcription` rather than a volatile preset: we want the committed result, and
        // partial revisions would only add work that Parakeet's batch path never does.
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)

        let installed = await SpeechTranscriber.installedLocales
        if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: nil)
        let loadSeconds = Date().timeIntervalSince(loadStart)

        let processStart = Date()
        let collector = Task { () -> String in
            var committed = ""
            for try await result in transcriber.results where result.isFinal {
                committed += String(result.text.characters)
            }
            return committed
        }

        let file = try AVAudioFile(forReading: url)
        try await analyzer.start(inputAudioFile: file, finishAfterFile: true)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value
        let processSeconds = Date().timeIntervalSince(processStart)

        return EngineRun(
            engine: "Apple SpeechTranscriber",
            detail: "macOS 26 · on-device · \(locale.identifier(.bcp47))",
            loadSeconds: loadSeconds,
            processSeconds: processSeconds,
            realtimeFactor: audioDuration / max(processSeconds, 0.0001),
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Parakeet via FluidAudio

enum ParakeetEngine {
    static func run(
        url: URL,
        audioDuration: Double,
        version: AsrModelVersion,
        precision: ParakeetEncoderPrecision
    ) async throws -> EngineRun {
        let loadStart = Date()

        // First call downloads ~1.1 GB of CoreML packages from the FluidInference HF repo
        // into ~/Library/Application Support/FluidAudio/Models/; later runs load from disk.
        let models = try await AsrModels.downloadAndLoad(
            version: version,
            encoderPrecision: precision
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        // Allocated before the timer starts — this is setup, and charging it to transcription
        // would flatter Apple's side, whose equivalent allocation happens inside `prepareToAnalyze`.
        var decoderState = try TdtDecoderState()
        let loadSeconds = Date().timeIntervalSince(loadStart)

        let processStart = Date()
        let result = try await manager.transcribe(url, decoderState: &decoderState)
        let processSeconds = Date().timeIntervalSince(processStart)

        let versionName = version == .v3 ? "v3" : "v2"
        return EngineRun(
            engine: "Parakeet TDT 0.6B \(versionName)",
            detail: "FluidAudio · CoreML on ANE · \(precision.rawValue) encoder",
            loadSeconds: loadSeconds,
            processSeconds: processSeconds,
            realtimeFactor: audioDuration / max(processSeconds, 0.0001),
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Shared

enum Audio {
    static func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
