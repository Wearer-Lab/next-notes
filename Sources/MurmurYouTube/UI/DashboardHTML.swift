import Foundation

/// Renders the live comparison page. Self-contained, theme-aware, auto-refreshing.
enum DashboardHTML {
    static func render(runs: [DictationRun], compareMode: Bool = false, key: String = "Right \u{2325}") -> String {
        let byEngine = Dictionary(grouping: runs, by: \.engine)
        let summary = byEngine
            .map { engine, runs in EngineSummary(engine: engine, runs: runs) }
            .sorted { $0.engine < $1.engine }

        // Comparison groups first — they're the reason this page exists.
        let groups = Dictionary(grouping: runs.filter { $0.group != nil }, by: { $0.group! })
            .sorted { ($0.value.first?.date ?? .distantPast) > ($1.value.first?.date ?? .distantPast) }
        let ungrouped = runs.filter { $0.group == nil }

        let body = runs.isEmpty
            ? emptyState(compareMode: compareMode, key: key)
            : """
              \(groups.isEmpty ? "" : "<h2 class=\"sec\">Head to head</h2>")
              \(groups.map { comparisonBlock(runs: $0.value) }.joined())
              \(summary.isEmpty ? "" : "<h2 class=\"sec\">Overall</h2>")
              <div class="grid">\(summary.map(summaryCard).joined())</div>
              \(ungrouped.isEmpty ? "" : runsTable(ungrouped.reversed()))
              """

        return """
        <!doctype html>
        <html lang="en"><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <!-- The app rewrites this file after every dictation; the page just reloads. -->
        <meta http-equiv="refresh" content="3">
        <title>Murmur YouTube — engine comparison</title>
        <style>
        :root{--bg:#fbfbfd;--panel:#fff;--ink:#1d1d1f;--muted:#6e6e73;--line:#e3e3e8;
              --accent:#6b8cff;--accent2:#c278ff;--good:#1a9c5b;}
        @media (prefers-color-scheme:dark){:root{--bg:#0f0f12;--panel:#18181d;--ink:#f2f2f5;
              --muted:#9a9aa3;--line:#2c2c34;--good:#3ecf8e;}}
        :root[data-theme="dark"]{--bg:#0f0f12;--panel:#18181d;--ink:#f2f2f5;--muted:#9a9aa3;--line:#2c2c34;--good:#3ecf8e;}
        :root[data-theme="light"]{--bg:#fbfbfd;--panel:#fff;--ink:#1d1d1f;--muted:#6e6e73;--line:#e3e3e8;--good:#1a9c5b;}
        *{box-sizing:border-box}
        body{margin:0;padding:36px 22px 64px;background:var(--bg);color:var(--ink);
             font:15px/1.6 ui-rounded,-apple-system,BlinkMacSystemFont,system-ui,sans-serif}
        .wrap{max-width:1000px;margin:0 auto}
        h1{margin:0 0 4px;font-size:27px;letter-spacing:-.02em;
           background:linear-gradient(90deg,var(--accent),var(--accent2));
           -webkit-background-clip:text;background-clip:text;color:transparent}
        .sub{color:var(--muted);font-size:13px}
        .bar{display:flex;justify-content:space-between;align-items:center;
             gap:12px;margin-bottom:26px;flex-wrap:wrap}
        .btn{font-size:12.5px;font-weight:600;text-decoration:none;padding:6px 14px;
             border-radius:999px;border:1px solid var(--line);color:var(--ink);
             background:var(--panel);white-space:nowrap}
        .btn:hover{border-color:var(--accent);color:var(--accent)}
        .dot{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--good);
             margin-right:5px;vertical-align:middle;animation:p 2s infinite}
        @keyframes p{0%,100%{opacity:1}50%{opacity:.35}}
        .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(300px,1fr));gap:16px;margin-bottom:26px}
        .panel{background:var(--panel);border:1px solid var(--line);border-radius:15px;padding:20px}
        .panel h2{margin:0 0 2px;font-size:17px;letter-spacing:-.01em}
        .n{color:var(--muted);font-size:12px;margin-bottom:15px}
        .stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}
        .stat{border:1px solid var(--line);border-radius:10px;padding:9px 10px}
        .stat .k{font-size:10.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.05em}
        .stat .v{font-size:19px;font-weight:600;margin-top:2px;font-variant-numeric:tabular-nums;letter-spacing:-.02em}
        table{width:100%;border-collapse:collapse;font-size:13.5px}
        .scroll{overflow-x:auto;border:1px solid var(--line);border-radius:15px;background:var(--panel)}
        th{text-align:left;font-size:10.5px;text-transform:uppercase;letter-spacing:.05em;
           color:var(--muted);font-weight:600;padding:12px 14px;border-bottom:1px solid var(--line)}
        td{padding:11px 14px;border-bottom:1px solid var(--line);vertical-align:top}
        tr:last-child td{border-bottom:none}
        .num{font-variant-numeric:tabular-nums;white-space:nowrap}
        .pill{font-size:11px;font-weight:600;padding:2px 8px;border-radius:999px;white-space:nowrap;
              background:color-mix(in srgb,var(--accent) 16%,transparent);color:var(--accent)}
        .txt{color:var(--muted);max-width:460px}
        .empty{text-align:center;padding:60px 20px;color:var(--muted)}
        .empty .lead{font-size:19px;color:var(--ink);font-weight:600;margin-bottom:10px}
        .empty .hint{font-size:12.5px;opacity:.75}
        kbd{background:color-mix(in srgb,var(--ink) 12%,transparent);border:1px solid var(--line);
            border-radius:6px;padding:2px 8px;font:inherit;font-weight:600}
        code{background:color-mix(in srgb,var(--ink) 8%,transparent);padding:1px 5px;border-radius:5px;font-size:12.5px}
        footer{margin-top:22px;color:var(--muted);font-size:12px}
        .sec{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
             margin:26px 0 12px;font-weight:600}
        .cmp{margin-bottom:14px}
        .cmphead{display:flex;justify-content:space-between;align-items:center;
                 padding-bottom:12px;margin-bottom:14px;border-bottom:1px solid var(--line);
                 color:var(--muted);font-size:12px}
        .verdict{font-size:11px;font-weight:600;padding:2px 9px;border-radius:999px}
        .verdict.same{background:color-mix(in srgb,var(--good) 16%,transparent);color:var(--good)}
        .verdict.diff{background:color-mix(in srgb,var(--accent2) 18%,transparent);color:var(--accent2)}
        .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}
        .col{min-width:0}
        .colhead{display:flex;align-items:baseline;justify-content:space-between;gap:8px;margin-bottom:3px}
        .big{font-size:20px;font-weight:600;letter-spacing:-.02em}
        .pill.win{background:color-mix(in srgb,var(--good) 18%,transparent);color:var(--good)}
        .meta{color:var(--muted);font-size:11.5px;margin-bottom:9px}
        .out{font-size:14px;line-height:1.55;overflow-wrap:anywhere}
        </style></head><body><div class="wrap">
        <h1>Engine comparison</h1>
        <div class="bar">
          <div class="sub"><span class="dot"></span>live — reloads every 3s · \(runs.count) dictation\(runs.count == 1 ? "" : "s") recorded</div>
          \(runs.isEmpty ? "" : "<a class=\"btn\" href=\"murmuryt://clear\">Clear results</a>")
        </div>
        \(body)
        <footer>
          Process time is release → text ready: the latency you actually feel. RTF is hold
          duration ÷ process time. Apple streams text while you talk, so its felt latency is
          lower than these numbers suggest; Parakeet resolves everything on release.
        </footer>
        </div></body></html>
        """
    }

    private static func emptyState(compareMode: Bool, key: String) -> String {
        """
        <div class="panel empty">
          <p class="lead">Hold <kbd>\(escape(key))</kbd>, say a sentence, let go.</p>
          <p>\(compareMode
              ? "Both engines will run on that one recording and appear here side by side."
              : "Compare mode is off — turn it on in the menu bar to see both engines at once.")</p>
          <p class="hint">Nothing to click here. This page fills in on its own.</p>
        </div>
        """
    }

    /// One recording, every engine's take on it, laid out for direct reading.
    private static func comparisonBlock(runs: [DictationRun]) -> String {
        guard let first = runs.first else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let fastest = runs.min(by: { $0.processSeconds < $1.processSeconds })?.engine

        // Compared on normalized text — case and punctuation differences aren't recognition
        // errors, and Apple auto-punctuates while Parakeet doesn't. Hence "same words"
        // rather than "identical text": the rendered strings can still look different.
        let sameWords = Set(runs.map { normalized($0.text) }).count == 1
        let exact = Set(runs.map(\.text)).count == 1
        let verdict = exact ? "identical" : (sameWords ? "same words" : "words differ")

        let columns = runs.map { run -> String in
            let win = run.engine == fastest && runs.count > 1
            return """
            <div class="col">
              <div class="colhead">
                <span class="pill\(win ? " win" : "")">\(escape(run.engine))\(win ? " · fastest" : "")</span>
                <span class="num big">\(fmt(run.processSeconds, 2))s</span>
              </div>
              <div class="meta">\(fmt(run.realtimeFactor, 0))× realtime · \(run.characters) chars</div>
              <div class="out">\(escape(run.text))</div>
            </div>
            """
        }.joined()

        return """
        <section class="panel cmp">
          <div class="cmphead">
            <span class="num">\(formatter.string(from: first.date)) · held \(fmt(first.audioSeconds, 1))s</span>
            <span class="verdict \(sameWords ? "same" : "diff")">\(verdict)</span>
          </div>
          <div class="cols">\(columns)</div>
        </section>
        """
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    private struct EngineSummary {
        let engine: String
        let runs: [DictationRun]

        var medianProcess: Double { median(runs.map(\.processSeconds)) }
        var medianRTF: Double { median(runs.map(\.realtimeFactor)) }
        var totalChars: Int { runs.reduce(0) { $0 + $1.characters } }

        /// Median rather than mean — one cold-start outlier shouldn't define the number.
        private func median(_ values: [Double]) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
    }

    private static func summaryCard(_ s: EngineSummary) -> String {
        """
        <section class="panel">
          <h2>\(escape(s.engine))</h2>
          <div class="n">\(s.runs.count) run\(s.runs.count == 1 ? "" : "s") · median of all</div>
          <div class="stats">
            <div class="stat"><div class="k">Process</div><div class="v">\(fmt(s.medianProcess, 2))s</div></div>
            <div class="stat"><div class="k">RTF</div><div class="v">\(fmt(s.medianRTF, 0))×</div></div>
            <div class="stat"><div class="k">Chars</div><div class="v">\(s.totalChars)</div></div>
          </div>
        </section>
        """
    }

    private static func runsTable(_ runs: [DictationRun]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let rows = runs.map { run in
            """
            <tr>
              <td class="num">\(formatter.string(from: run.date))</td>
              <td><span class="pill">\(escape(run.engine))</span></td>
              <td class="num">\(fmt(run.audioSeconds, 1))s</td>
              <td class="num">\(fmt(run.processSeconds, 2))s</td>
              <td class="num">\(fmt(run.realtimeFactor, 0))×</td>
              <td class="txt">\(escape(run.text))</td>
            </tr>
            """
        }.joined()

        return """
        <div class="scroll"><table>
          <thead><tr><th>Time</th><th>Engine</th><th>Held</th><th>Process</th><th>RTF</th><th>Transcript</th></tr></thead>
          <tbody>\(rows)</tbody>
        </table></div>
        """
    }

    private static func fmt(_ value: Double, _ places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
