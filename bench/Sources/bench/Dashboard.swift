import Foundation

/// Renders a self-contained HTML comparison — no external assets, opens straight from disk.
enum Dashboard {
    static func render(
        runs: [EngineRun],
        audioFile: String,
        audioDuration: Double,
        reference: String?,
        machine: String
    ) -> String {
        let fastest = runs.min(by: { $0.processSeconds < $1.processSeconds })?.engine
        let mostAccurate = runs
            .compactMap { run -> (String, Double)? in run.wer.map { (run.engine, $0) } }
            .min(by: { $0.1 < $1.1 })?.0

        let cards = runs.map { run in
            card(run, isFastest: run.engine == fastest, isMostAccurate: run.engine == mostAccurate, reference: reference)
        }.joined(separator: "\n")

        let refBlock = reference.map { ref in
            """
            <section class="panel">
              <h2>Reference</h2>
              <p class="ref">\(escape(ref))</p>
            </section>
            """
        } ?? """
            <section class="panel note">
              <h2>No reference transcript</h2>
              <p>Accuracy wasn't scored. Write down what you actually said and re-run with
              <code>--ref transcript.txt</code> to get WER and CER.</p>
            </section>
            """

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Speech engine benchmark</title>
        <style>
        :root {
          --bg:#fbfbfd; --panel:#fff; --ink:#1d1d1f; --muted:#6e6e73;
          --line:#e3e3e8; --accent:#6b8cff; --accent2:#c278ff;
          --good:#1a9c5b; --bad:#d1344b; --warn:#c07800;
        }
        @media (prefers-color-scheme: dark) {
          :root { --bg:#0f0f12; --panel:#18181d; --ink:#f2f2f5; --muted:#9a9aa3;
                  --line:#2c2c34; --good:#3ecf8e; --bad:#ff6b81; --warn:#e0a33a; }
        }
        :root[data-theme="dark"] { --bg:#0f0f12; --panel:#18181d; --ink:#f2f2f5; --muted:#9a9aa3;
                  --line:#2c2c34; --good:#3ecf8e; --bad:#ff6b81; --warn:#e0a33a; }
        :root[data-theme="light"] { --bg:#fbfbfd; --panel:#fff; --ink:#1d1d1f; --muted:#6e6e73;
                  --line:#e3e3e8; --good:#1a9c5b; --bad:#d1344b; --warn:#c07800; }
        * { box-sizing:border-box; }
        body { margin:0; padding:40px 24px 72px; background:var(--bg); color:var(--ink);
               font:15px/1.6 ui-rounded,-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }
        .wrap { max-width:1040px; margin:0 auto; }
        header { margin-bottom:32px; }
        h1 { margin:0 0 6px; font-size:30px; letter-spacing:-.02em;
             background:linear-gradient(90deg,var(--accent),var(--accent2));
             -webkit-background-clip:text; background-clip:text; color:transparent; }
        .sub { color:var(--muted); font-size:14px; }
        .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(420px,1fr)); gap:20px; }
        .panel { background:var(--panel); border:1px solid var(--line); border-radius:16px;
                 padding:22px; margin-bottom:20px; }
        .card h2 { margin:0; font-size:18px; letter-spacing:-.01em; }
        .detail { color:var(--muted); font-size:12.5px; margin:4px 0 18px; }
        .badges { display:flex; gap:6px; flex-wrap:wrap; margin-bottom:14px; }
        .badge { font-size:11px; font-weight:600; padding:3px 9px; border-radius:999px;
                 background:color-mix(in srgb, var(--accent) 16%, transparent); color:var(--accent); }
        .badge.win { background:color-mix(in srgb, var(--good) 18%, transparent); color:var(--good); }
        .stats { display:grid; grid-template-columns:repeat(3,1fr); gap:12px; margin-bottom:18px; }
        .stat { border:1px solid var(--line); border-radius:11px; padding:11px 12px; }
        .stat .k { font-size:11px; color:var(--muted); text-transform:uppercase; letter-spacing:.05em; }
        .stat .v { font-size:21px; font-weight:600; letter-spacing:-.02em; margin-top:3px;
                   font-variant-numeric:tabular-nums; }
        .transcript { border-top:1px solid var(--line); padding-top:14px; font-size:14px; }
        .transcript .k { font-size:11px; color:var(--muted); text-transform:uppercase;
                         letter-spacing:.05em; margin-bottom:7px; }
        .sub-w { color:var(--bad); text-decoration:underline wavy var(--bad) 1px; }
        .ins-w { color:var(--warn); }
        .del-w { color:var(--muted); text-decoration:line-through; opacity:.65; }
        .ref { font-size:14px; color:var(--muted); margin:0; }
        .note p { color:var(--muted); font-size:13.5px; margin:6px 0 0; }
        code { background:color-mix(in srgb, var(--ink) 8%, transparent); padding:1px 5px;
               border-radius:5px; font-size:12.5px; }
        .legend { display:flex; gap:16px; flex-wrap:wrap; color:var(--muted); font-size:12px; margin-top:10px; }
        footer { margin-top:28px; color:var(--muted); font-size:12px; }
        </style>
        </head>
        <body><div class="wrap">
        <header>
          <h1>Speech engine benchmark</h1>
          <div class="sub">
            \(escape(audioFile)) · \(String(format: "%.1f", audioDuration))s of audio · \(escape(machine))
          </div>
        </header>
        <div class="grid">
        \(cards)
        </div>
        \(refBlock)
        <footer>
          RTF = audio seconds processed per wall-clock second; higher is faster.
          Load time is excluded from RTF — Parakeet pays it once per process, Apple's models
          are resident in the OS. Accuracy is scored on normalized text (lowercased,
          punctuation stripped) so automatic punctuation isn't counted as error.
        </footer>
        </div></body></html>
        """
    }

    private static func card(
        _ run: EngineRun,
        isFastest: Bool,
        isMostAccurate: Bool,
        reference: String?
    ) -> String {
        var badges = ""
        if isFastest { badges += #"<span class="badge win">fastest</span>"# }
        if isMostAccurate { badges += #"<span class="badge win">most accurate</span>"# }
        badges += #"<span class="badge">\#(escape(run.detail))</span>"#

        let werCell = run.wer.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
        let cerCell = run.cer.map { String(format: "%.1f%%", $0 * 100) } ?? "—"

        let body: String
        if let reference {
            let tokens = Metrics.diff(reference: reference, hypothesis: run.text)
            body = tokens.map { token in
                switch token.kind {
                case .match: escape(token.text)
                case .substitution(let expected):
                    #"<span class="sub-w" title="expected: \#(escape(expected))">\#(escape(token.text))</span>"#
                case .insertion: #"<span class="ins-w" title="inserted">\#(escape(token.text))</span>"#
                case .deletion: #"<span class="del-w" title="missed">\#(escape(token.text))</span>"#
                }
            }.joined(separator: " ")
        } else {
            body = escape(run.text)
        }

        return """
        <section class="panel card">
          <h2>\(escape(run.engine))</h2>
          <div class="detail">load \(String(format: "%.2f", run.loadSeconds))s</div>
          <div class="badges">\(badges)</div>
          <div class="stats">
            <div class="stat"><div class="k">Process</div><div class="v">\(String(format: "%.2f", run.processSeconds))s</div></div>
            <div class="stat"><div class="k">RTF</div><div class="v">\(String(format: "%.0f", run.realtimeFactor))×</div></div>
            <div class="stat"><div class="k">WER</div><div class="v">\(werCell)</div></div>
          </div>
          <div class="transcript">
            <div class="k">Transcript · CER \(cerCell)</div>
            <div>\(body)</div>
          </div>
        </section>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
