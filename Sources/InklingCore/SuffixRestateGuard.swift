import Foundation

/// Guards a MID-LINE continuation against restating the text that already
/// follows the caret (which would duplicate it on accept). Pure content-level
/// check. Unlike SuggestionRepeatGuard, `minWordLength` is 2 here: short words
/// like "the mat" ARE the restatement signal mid-line, but a single shared
/// leading stopword stays under the threshold.
public enum SuffixRestateGuard {
    public static func restates(
        continuation: String,
        suffix: String,
        leadWords: Int = 6,
        overlapThreshold: Double = 0.6,
        minWordLength: Int = 2
    ) -> Bool {
        let cont = Array(words(continuation).filter { $0.count >= minWordLength }.prefix(leadWords))
        guard !cont.isEmpty else { return false }
        let suf = Array(words(suffix).filter { $0.count >= minWordLength }.prefix(leadWords))
        guard !suf.isEmpty else { return false }
        let overlap = suf.filter { cont.contains($0) }.count
        return Double(overlap) / Double(suf.count) >= overlapThreshold
    }

    /// Lowercased letter/number runs; punctuation and whitespace are separators.
    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
