import Foundation

/// Guards a MID-LINE continuation against restating the text that already
/// follows the caret (which would duplicate it on accept). Pure content-level
/// check: true when the continuation BEGINS by reproducing the suffix's opening
/// content words — a leading run of >= minRun identical words (case-insensitive).
/// Measured at the start (not an overlap fraction over the whole continuation),
/// so a continuation that restates the suffix's opening and then adds more text
/// still trips the guard. minWordLength 2 so short words like "the mat" count.
public enum SuffixRestateGuard {
    public static func restates(
        continuation: String,
        suffix: String,
        minRun: Int = 2,
        minWordLength: Int = 2
    ) -> Bool {
        let cont = words(continuation).filter { $0.count >= minWordLength }
        let suf = words(suffix).filter { $0.count >= minWordLength }
        guard !cont.isEmpty, !suf.isEmpty else { return false }
        var run = 0
        for (a, b) in zip(cont, suf) {
            if a == b { run += 1 } else { break }
        }
        return run >= min(minRun, suf.count)
    }

    /// Lowercased letter/number runs; punctuation and whitespace are separators.
    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
