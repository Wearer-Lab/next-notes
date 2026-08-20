import Foundation

/// Accuracy scoring against a reference transcript.
///
/// Both engines are compared on *normalized* text: lowercased, punctuation stripped,
/// whitespace collapsed. Without that, Apple's automatic punctuation would be scored as
/// dozens of errors against an unpunctuated reference and the comparison would be
/// meaningless — we're measuring what words were heard, not how they were formatted.
enum Metrics {
    static func normalize(_ text: String) -> String {
        let stripped = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) { return Character(scalar) }
            if CharacterSet.whitespacesAndNewlines.contains(scalar) { return " " }
            if scalar == "'" { return "'" }   // keep contractions intact
            return " "
        }
        return String(stripped)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Word error rate: (substitutions + insertions + deletions) / reference words.
    static func wer(reference: String, hypothesis: String) -> Double? {
        let ref = normalize(reference).split(separator: " ").map(String.init)
        let hyp = normalize(hypothesis).split(separator: " ").map(String.init)
        guard !ref.isEmpty else { return nil }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    /// Character error rate — catches near-misses that WER scores as a whole wrong word.
    static func cer(reference: String, hypothesis: String) -> Double? {
        let ref = Array(normalize(reference))
        let hyp = Array(normalize(hypothesis))
        guard !ref.isEmpty else { return nil }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    /// Levenshtein distance, two-row rolling buffer.
    private static func editDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,      // deletion
                    current[j - 1] + 1,   // insertion
                    previous[j - 1] + cost // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    /// Word-level diff against the reference, for highlighting in the dashboard.
    static func diff(reference: String, hypothesis: String) -> [DiffToken] {
        let ref = normalize(reference).split(separator: " ").map(String.init)
        let hyp = normalize(hypothesis).split(separator: " ").map(String.init)
        guard !ref.isEmpty else { return hyp.map { DiffToken(text: $0, kind: .match) } }

        // Full Levenshtein matrix, then walk back to recover the alignment.
        var d = Array(repeating: Array(repeating: 0, count: hyp.count + 1), count: ref.count + 1)
        for i in 0...ref.count { d[i][0] = i }
        for j in 0...hyp.count { d[0][j] = j }
        if !hyp.isEmpty {
            for i in 1...ref.count {
                for j in 1...hyp.count {
                    let cost = ref[i - 1] == hyp[j - 1] ? 0 : 1
                    d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                }
            }
        }

        var tokens: [DiffToken] = []
        var i = ref.count
        var j = hyp.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, ref[i - 1] == hyp[j - 1], d[i][j] == d[i - 1][j - 1] {
                tokens.append(DiffToken(text: hyp[j - 1], kind: .match)); i -= 1; j -= 1
            } else if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + 1 {
                tokens.append(DiffToken(text: hyp[j - 1], kind: .substitution(expected: ref[i - 1]))); i -= 1; j -= 1
            } else if j > 0, d[i][j] == d[i][j - 1] + 1 {
                tokens.append(DiffToken(text: hyp[j - 1], kind: .insertion)); j -= 1
            } else if i > 0 {
                tokens.append(DiffToken(text: ref[i - 1], kind: .deletion)); i -= 1
            } else {
                break
            }
        }
        return tokens.reversed()
    }
}

struct DiffToken {
    enum Kind {
        case match
        case substitution(expected: String)
        case insertion
        case deletion
    }
    let text: String
    let kind: Kind
}
