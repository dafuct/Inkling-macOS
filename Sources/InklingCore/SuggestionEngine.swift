/// Produces the completion to show inline after the caret. The returned string
/// is appended directly at the caret (it continues the current word — no leading
/// space). Phase 2 will add an MLX-backed conformer; callers depend only on this.
public protocol SuggestionEngine {
    /// The text to show as ghost text after the caret, or "" for no suggestion.
    ///
    /// `currentWordIsComplete` tells the engine whether the word under the caret
    /// is a whole word (a continuation should be space-separated) or a partial
    /// word being typed (a continuation completes it, glued). The caller decides
    /// it (see the app's `WordCompleteness`).
    func suggestion(for context: TextContext, currentWordIsComplete: Bool) async -> String
}

public extension SuggestionEngine {
    /// Convenience for callers that don't track word completeness (e.g. tests):
    /// treats the current word as incomplete.
    func suggestion(for context: TextContext) async -> String {
        await suggestion(for: context, currentWordIsComplete: false)
    }
}

/// Phase 1 placeholder: completes the word currently being typed from a small
/// fixed word list, returning the missing suffix (e.g. "ho" -> "use"). Returns
/// "" when there's no partial word or no match. Phase 2 replaces this with a
/// real on-device model that predicts from full context.
public struct DummyEngine: SuggestionEngine {
    private static let words = [
        "hello", "house", "world", "because", "before", "function",
        "computer", "language", "available", "important", "different",
        "suggestion", "keyboard", "complete", "people", "should", "would",
    ]

    public init() {}

    public func suggestion(for context: TextContext, currentWordIsComplete: Bool) async -> String {
        let word = context.currentWord.lowercased()
        guard !word.isEmpty else { return "" }
        guard let match = Self.words.first(where: { $0.hasPrefix(word) && $0.count > word.count })
        else { return "" }
        return String(match.dropFirst(word.count))   // the suffix to append inline
    }
}
