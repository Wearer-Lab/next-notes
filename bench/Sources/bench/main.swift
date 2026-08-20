import AppKit
import Foundation
import FluidAudio

let usage = """
Speech engine benchmark — Apple SpeechTranscriber vs Parakeet (FluidAudio/CoreML)

  swift run bench record <out.wav>
      Record 16 kHz mono from the microphone until you press RETURN.

  swift run bench run <audio.wav> [--ref reference.txt] [--v2] [--int4]
      Transcribe with both engines, score them, and write a dashboard.

      --ref FILE   Score accuracy (WER/CER) against what you actually said.
      --v2         Use Parakeet TDT v2 (English-only, higher recall) instead of v3.
      --int4       Use the INT4 encoder (smaller/faster, slightly less accurate).
"""

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print(usage)
    exit(0)
}

func flag(_ name: String) -> Bool { args.contains(name) }
func value(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

do {
    switch command {
    case "record":
        guard args.count > 1 else { throw BenchError.message("usage: bench record <out.wav>") }
        try await Recorder.record(to: URL(fileURLWithPath: args[1]))

    case "run":
        guard args.count > 1 else { throw BenchError.message("usage: bench run <audio.wav>") }
        let url = URL(fileURLWithPath: args[1])
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BenchError.message("no such file: \(url.path)")
        }

        let reference = try value("--ref").map {
            try String(contentsOf: URL(fileURLWithPath: $0), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let duration = try Audio.duration(of: url)
        print(String(format: "audio: %@ (%.1fs)\n", url.lastPathComponent, duration))

        var runs: [EngineRun] = []

        print("▸ Apple SpeechTranscriber…")
        runs.append(try await AppleEngine.run(url: url, audioDuration: duration))

        print("▸ Parakeet (first run downloads ~1.1 GB of CoreML models)…")
        runs.append(try await ParakeetEngine.run(
            url: url,
            audioDuration: duration,
            version: flag("--v2") ? .v2 : .v3,
            precision: flag("--int4") ? .int4 : .int8
        ))

        // Score after both have run so a scoring bug can't be mistaken for an engine failure.
        for i in runs.indices {
            guard let reference else { continue }
            runs[i].wer = Metrics.wer(reference: reference, hypothesis: runs[i].text)
            runs[i].cer = Metrics.cer(reference: reference, hypothesis: runs[i].text)
        }

        print("")
        for run in runs {
            let wer = run.wer.map { String(format: "  WER %.1f%%", $0 * 100) } ?? ""
            print(String(
                format: "%-28@  %6.2fs  %5.0f× realtime%@",
                run.engine as NSString, run.processSeconds, run.realtimeFactor, wer as NSString
            ))
            print("    \(run.text.prefix(160))\(run.text.count > 160 ? "…" : "")\n")
        }

        let stem = url.deletingPathExtension().lastPathComponent
        let jsonURL = URL(fileURLWithPath: "\(stem)-results.json")
        let htmlURL = URL(fileURLWithPath: "\(stem)-dashboard.html")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(runs).write(to: jsonURL)

        let html = Dashboard.render(
            runs: runs,
            audioFile: url.lastPathComponent,
            audioDuration: duration,
            reference: reference,
            machine: machineDescription()
        )
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)

        print("wrote \(jsonURL.lastPathComponent) and \(htmlURL.lastPathComponent)")
        NSWorkspace.shared.open(htmlURL)

    default:
        print(usage)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

func machineDescription() -> String {
    var size = 0
    sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var chars = [CChar](repeating: 0, count: size)
    sysctlbyname("machdep.cpu.brand_string", &chars, &size, nil, 0)
    let chip = String(cString: chars)
    let cores = ProcessInfo.processInfo.processorCount
    let ram = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
    return "\(chip) · \(cores) cores · \(ram) GB"
}
