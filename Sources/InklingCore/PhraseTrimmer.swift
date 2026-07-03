import Foundation

/// Knobs for the post-hoc trimmer. Two sweepable dials (`lengthBonus`,
/// `minMeanLogProb`) plus the show/no-show frequency dial replace the old
/// three-way online gate (first/min/dominance).
public struct TrimConfig: Equatable, Sendable {
    /// Probability floor for the FIRST token — the show/no-show frequency dial.
    public var firstTokenMinProb: Double
    /// Length bonus per kept token, added to the mean log-probability. Larger
    /// values prefer longer suggestions — effectively the "suggestion length"
    /// preference.
    public var lengthBonus: Double
    /// Reject the whole suggestion when the best candidate's mean log-prob is
    /// below this floor (log scale; -1.2 ≈ mean prob 0.30).
    public var minMeanLogProb: Double
    /// Hard ceiling on how many tokens a shown suggestion may keep — the
    /// "don't paint half a paragraph" backstop the length bonus alone can't
    /// guarantee when every token is confident.
    public var maxShownTokens: Int
    /// Flat score bonus for candidates ending in phrase punctuation, so a
    /// clean "…headache." beats a capped mid-phrase stub like "…for a".
    public var punctuationBonus: Double

    public init(
        firstTokenMinProb: Double = 0.15,
        lengthBonus: Double = 0.04,
        minMeanLogProb: Double = -1.2,
        maxShownTokens: Int = 16,
        punctuationBonus: Double = 0.25
    ) {
        self.firstTokenMinProb = firstTokenMinProb
        self.lengthBonus = lengthBonus
        self.minMeanLogProb = minMeanLogProb
        self.maxShownTokens = maxShownTokens
        self.punctuationBonus = punctuationBonus
    }
}

/// Post-hoc phrase-boundary trimming for a greedily-decoded continuation.
///
/// An online per-token gate must decide with zero lookahead, so it stops at
/// every healthy branch point of natural language (every few tokens) — which
/// is why gated suggestions came out 1-2 words long. The trimmer instead sees
/// the whole decoded trajectory and picks the cutoff over candidate word/phrase
/// boundaries by maximizing `mean(log p) + lengthBonus·tokens`. Pure logic —
/// no MLX, no I/O.
public enum PhraseTrimmer {
    /// - `prefixes[i]`: decoded text of tokens 0...i (cumulative, so multi-token
    ///   UTF-8 sequences — Cyrillic especially — are always whole strings).
    /// - `probs[i]`: top-1 probability of the RAW (unpenalized) distribution
    ///   that produced token i.
    /// - `endedNaturally`: the decode stopped because the model closed the text
    ///   (EOS/newline), so the final token is a valid cut point even without a
    ///   trailing boundary character.
    /// Returns the text to show (leading whitespace preserved — the string is
    /// inserted at the caret verbatim), or "" to show nothing.
    public static func trim(
        prefixes: [String],
        probs: [Double],
        endedNaturally: Bool,
        config: TrimConfig = TrimConfig()
    ) -> String {
        guard !prefixes.isEmpty, prefixes.count == probs.count else { return "" }
        guard probs[0] >= config.firstTokenMinProb else { return "" }

        var cumLog: [Double] = []
        var running = 0.0
        for p in probs {
            running += log(max(p, 1e-9))
            cumLog.append(running)
        }

        // Candidate cut points: after token i, when the cut cannot split a word.
        var candidates: [Int] = []
        let n = prefixes.count
        let limit = min(n, max(1, config.maxShownTokens))
        for i in 0..<limit {
            if i + 1 < n {
                let delta = String(prefixes[i + 1].dropFirst(prefixes[i].count))
                if let f = delta.first, f.isWhitespace || f.isPunctuation {
                    candidates.append(i)
                } else if let l = prefixes[i].last, l.isPunctuation || l.isWhitespace {
                    candidates.append(i)
                }
            } else if endedNaturally {
                candidates.append(i)
            } else if let l = prefixes[i].last, l.isPunctuation || l.isWhitespace {
                candidates.append(i)
            }
        }
        guard !candidates.isEmpty else { return "" }

        func meanLog(_ i: Int) -> Double { cumLog[i] / Double(i + 1) }
        func score(_ i: Int) -> Double {
            var s = meanLog(i) + config.lengthBonus * Double(i + 1)
            if let l = prefixes[i].last, ".!?…,;:".contains(l) { s += config.punctuationBonus }
            return s
        }
        let best = candidates.max { score($0) < score($1) }!
        guard meanLog(best) >= config.minMeanLogProb else { return "" }

        var out = prefixes[best]
        while let l = out.last, l.isWhitespace { out.removeLast() }
        return out
    }
}
