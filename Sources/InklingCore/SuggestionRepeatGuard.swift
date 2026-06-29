/// Guards against the LLM *restating* recently-typed text instead of continuing
/// it. The eager gate surfaces low-confidence sentence-restarts (e.g. typing
/// "The new feature is ready" and getting back "The release feature is ready…"),
/// which the confidence floor can't catch because a fluent rephrase is
/// high-probability. This is a pure, content-level check: no MLX, no I/O.
public enum SuggestionRepeatGuard {
    /// True when `continuation` substantially repeats words from the tail of
    /// `recentText` — i.e. the model is rephrasing what was already typed rather
    /// than adding something new.
    ///
    /// Only multi-word continuations are considered (a short completion like
    /// "questions" or "helping" is never flagged), and the overlap is measured
    /// against the last `recentWindow` words so distant repetition doesn't count.
    ///
    /// - `minWords`: continuations shorter than this are always allowed.
    /// - `overlapThreshold`: fraction of the continuation's words that must
    ///   already appear in the recent window to count as a restatement.
    /// - `recentWindow`: how many trailing words of `recentText` to compare against.
    public static func repeatsRecent(
        continuation: String,
        recentText: String,
        minWords: Int = 3,
        overlapThreshold: Double = 0.6,
        recentWindow: Int = 16
    ) -> Bool {
        let contWords = words(continuation)
        guard contWords.count >= minWords else { return false }
        let recent = Set(words(recentText).suffix(recentWindow))
        guard !recent.isEmpty else { return false }
        let overlap = contWords.filter { recent.contains($0) }.count
        return Double(overlap) / Double(contWords.count) >= overlapThreshold
    }

    /// Lowercased letter/number runs; punctuation and whitespace are separators.
    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
