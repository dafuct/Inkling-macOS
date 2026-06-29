import Foundation

/// Pure helpers for turning a TextContext into the model prompt and turning the
/// model's raw output into a clean inline suggestion.
public enum CompletionPrompt {
    /// The text to feed the model: up to `maxChars` characters before the caret.
    public static func prompt(for context: TextContext, maxChars: Int) -> String {
        let p = context.prefix
        return p.count <= maxChars ? p : String(p.suffix(maxChars))
    }

    /// Clean raw model output into a single inline fragment: first line only,
    /// trimmed, with wrapping quotes removed.
    public static func clean(_ raw: String) -> String {
        var s = raw
        if let nl = s.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            s = String(s[..<nl])
        }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// Decide the exact text to insert at the caret, given the model's cleaned
    /// continuation, the partial word under the caret, and whether the prefix
    /// ends with whitespace.
    ///
    /// The hard case is a non-empty `currentWord` (the caret sits right after a
    /// run of word characters, e.g. "...is ready" or mid-typing "contri"). We
    /// cannot tell from the strings whether the model is *finishing that word*
    /// ("contri"+"bute" → "contribute") or *continuing with a new one*
    /// ("ready"+"release" → "ready release"): both are non-restatement, and the
    /// model drops the leading space either way (the "Continuation:" prompt format
    /// trains it to). `currentWordIsComplete` (whether `currentWord` is a whole
    /// dictionary word, decided by the caller — see the app's spell-check) breaks
    /// the tie:
    /// - The model RESTATES the word (caret after "hel", model says "help me") →
    ///   insert only the missing suffix, glued with no space → "p me".
    /// - `currentWord` is a complete word → the continuation is a NEW word →
    ///   space-separate it ("ready"+"release" → "ready release").
    /// - `currentWord` is a partial word still being typed → the continuation
    ///   completes it → glue with no space ("contri"+"bute" → "contribute").
    /// - After whitespace (`currentWord` empty) → a new word; inserted as-is, with
    ///   a leading space only if the prefix didn't already end with one.
    public static func inlineSuggestion(
        continuation: String,
        currentWord: String,
        prefixEndsWithSpace: Bool,
        currentWordIsComplete: Bool
    ) -> String {
        guard !continuation.isEmpty else { return "" }
        if !currentWord.isEmpty {
            // Model restated the whole word -> insert only the missing suffix.
            if continuation.lowercased().hasPrefix(currentWord.lowercased()) {
                return String(continuation.dropFirst(currentWord.count))
            }
            // Complete word -> new word (space); partial word -> completion (glue).
            return currentWordIsComplete ? " " + continuation : continuation
        }
        return prefixEndsWithSpace ? continuation : " " + continuation
    }
}
