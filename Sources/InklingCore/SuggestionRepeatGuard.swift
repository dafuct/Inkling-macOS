/// Guards against the LLM *restating* recently-typed text instead of continuing
/// it. The eager gate surfaces low-confidence sentence-restarts (e.g. typing
/// "The new feature is ready" and getting back "The release feature is ready…"),
/// which the confidence floor can't catch because a fluent rephrase is
/// high-probability. This is a pure, content-level check: no MLX, no I/O.
public enum SuggestionRepeatGuard {
    /// True when `continuation` substantially repeats CONTENT words from the
    /// tail of `recentText` — i.e. the model is rephrasing what was already
    /// typed rather than adding something new.
    ///
    /// Overlap is measured over content words only (length ≥ `minWordLength`):
    /// stopwords ("the", "and", "і", "на") are shared by any fluent
    /// continuation, and counting them made the guard select for exactly the
    /// two failure modes it was meant to prevent — short suggestions and
    /// off-topic ones — while killing genuine topical half-sentences.
    /// The window is the last `recentWindow` RAW words (window first, then the
    /// content filter), so distant repetition still doesn't count.
    ///
    /// - `minWords`: continuations with fewer content words are always allowed.
    /// - `overlapThreshold`: fraction of the continuation's content words that
    ///   must already appear in the recent window to count as a restatement.
    /// - `recentWindow`: how many trailing raw words of `recentText` to compare against.
    /// - `minWordLength`: minimum character count for a word to be "content".
    public static func repeatsRecent(
        continuation: String,
        recentText: String,
        minWords: Int = 2,
        overlapThreshold: Double = 0.6,
        recentWindow: Int = 16,
        minWordLength: Int = 4
    ) -> Bool {
        let contWords = words(continuation).filter { $0.count >= minWordLength }
        guard contWords.count >= minWords else { return false }
        let recent = Set(words(recentText).suffix(recentWindow).filter { $0.count >= minWordLength })
        guard !recent.isEmpty else { return false }
        let overlap = contWords.filter { recent.contains($0) }.count
        return Double(overlap) / Double(contWords.count) >= overlapThreshold
    }

    /// Lowercased letter/number runs; punctuation and whitespace are separators.
    private static func words(_ s: String) -> [String] {
        s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
