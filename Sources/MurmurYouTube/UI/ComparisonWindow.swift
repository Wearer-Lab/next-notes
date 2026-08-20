import SwiftUI

/// Live-updating store behind the comparison window.
///
/// The window replaced a generated HTML file opened in the browser. That approach needed a
/// `file://` URL, spawned a fresh tab on every open, and left stale tabs showing old data
/// with no way to tell which was current. A window owned by the app has none of those
/// problems: one instance, always live, nothing to refresh.
@MainActor
@Observable
final class RunStore {
    static let shared = RunStore()

    private(set) var runs: [DictationRun] = []

    private init() { reload() }

    func reload() {
        runs = RunLog.load()
    }

    /// Recordings grouped by comparison, newest first.
    var comparisons: [[DictationRun]] {
        Dictionary(grouping: runs.filter { $0.group != nil }, by: { $0.group! })
            .values
            .sorted { ($0.first?.date ?? .distantPast) > ($1.first?.date ?? .distantPast) }
    }

    var singles: [DictationRun] {
        runs.filter { $0.group == nil }.reversed()
    }
}

struct ComparisonWindow: View {
    @Bindable var controller: DictationController
    @State private var store = RunStore.shared
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                recordBar

                if store.runs.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(store.comparisons.enumerated()), id: \.offset) { _, group in
                        ComparisonCard(runs: group)
                    }
                    ForEach(Array(store.singles.enumerated()), id: \.offset) { _, run in
                        SingleCard(run: run)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 420)
        .background(.background)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Engine comparison")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.gradient)
                Text("\(store.runs.count) recording\(store.runs.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.runs.isEmpty {
                Button("Clear") {
                    RunLog.clear()
                    store.reload()
                }
            }
        }
    }

    /// One button that records every engine at once — no hotkeys, and the results appear in
    /// this same window, so there's nowhere to go afterwards to read them.
    private var recordBar: some View {
        let isRecording = controller.state.isActive

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    if isRecording {
                        controller.stopButtonRecording()
                    } else {
                        controller.startButtonRecording()
                    }
                } label: {
                    Label(
                        isRecording ? "Stop" : "Record all three",
                        systemImage: isRecording ? "stop.circle.fill" : "record.circle"
                    )
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .accentColor)
                .controlSize(.large)
            }

            Text(statusLine(isRecording: isRecording))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 4)
    }

    private func statusLine(isRecording: Bool) -> String {
        if isRecording { return "Recording — click Stop when you're done talking." }
        if !controller.transcript.isEmpty { return controller.transcript }
        return WisprReader.isInstalled
            ? "Click Record, talk, click Stop. Apple, Parakeet and Wispr Flow all hear it."
            : "Click Record, talk, click Stop. Wispr Flow isn't installed, so it's Apple vs Parakeet."
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "waveform")
                .font(.system(size: 30))
                .foregroundStyle(Brand.gradient)
            Text("Hold \(settings.pushToTalkKey.displayName), say a sentence, let go.")
                .font(.system(size: 15, weight: .semibold))
            Text(settings.compareMode
                 ? "Both engines run on that one recording and appear here."
                 : "Turn on Compare mode in the menu bar to see both engines at once.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private struct ComparisonCard: View {
    let runs: [DictationRun]

    /// Fastest first. The engines are *measured* sequentially, so arrival order reflects
    /// which ran first, not which is quicker — sorting by measured time is what makes the
    /// winner readable at a glance.
    private var ranked: [DictationRun] {
        runs.sorted { $0.processSeconds < $1.processSeconds }
    }

    /// How much faster the winner was, once both are in.
    private var margin: String? {
        guard runs.count > 1,
              let best = ranked.first,
              let worst = ranked.last,
              best.processSeconds > 0
        else { return nil }
        let ratio = worst.processSeconds / best.processSeconds
        let delta = worst.processSeconds - best.processSeconds
        guard delta > 0.005 else { return "tied" }
        return String(format: "%@ %.1f× faster · %.2fs ahead", best.engine, ratio, delta)
    }

    /// Case and punctuation are normalized away: Apple auto-punctuates and Parakeet
    /// doesn't, and that's a formatting difference, not a recognition error.
    private var verdict: (String, Color) {
        if Set(runs.map(\.text)).count == 1 { return ("identical", .green) }
        let normalized = Set(runs.map {
            $0.text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        })
        return normalized.count == 1 ? ("same words", .green) : ("words differ", .purple)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(runs.first.map { "\($0.date.formatted(date: .omitted, time: .standard)) · held \($0.audioSeconds, format: .number.precision(.fractionLength(1)))s" } ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verdict.0)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(verdict.1.opacity(0.16), in: Capsule())
                    .foregroundStyle(verdict.1)

                // Deletes the whole group: every engine here transcribed one utterance, so
                // removing that utterance means removing all of its rows together.
                if let group = runs.first?.group {
                    Button {
                        withAnimation { RunLog.deleteGroup(group) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete this comparison")
                }
            }
            if let margin {
                HStack(spacing: 5) {
                    Image(systemName: margin == "tied" ? "equal.circle.fill" : "bolt.fill")
                    Text(margin)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
            } else if runs.count == 1 {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("running second engine…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()
            ForEach(Array(ranked.enumerated()), id: \.offset) { index, run in
                EngineRow(run: run, rank: index + 1, showRank: runs.count > 1)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct EngineRow: View {
    let run: DictationRun
    let rank: Int
    let showRank: Bool

    private var isWinner: Bool { showRank && rank == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.engine + (isWinner ? " · fastest" : ""))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((isWinner ? Color.green : Color.accentColor).opacity(0.16), in: Capsule())
                    .foregroundStyle(isWinner ? .green : Color.accentColor)
                Spacer()
                Text("\(run.processSeconds, format: .number.precision(.fractionLength(2)))s")
                    .font(.system(size: isWinner ? 20 : 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isWinner ? .green : .primary)
            }
            Text("\(run.realtimeFactor, format: .number.precision(.fractionLength(0)))× realtime · \(run.characters) chars")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(run.text.isEmpty ? "(nothing recognized)" : run.text)
                .font(.callout)
                .foregroundStyle(run.text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct SingleCard: View {
    let run: DictationRun

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(run.engine).font(.caption.weight(.semibold))
                Spacer()
                Text("\(run.processSeconds, format: .number.precision(.fractionLength(2)))s")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Text(run.text).font(.callout).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}
