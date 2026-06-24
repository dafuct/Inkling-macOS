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

    /// Decide the exact text to insert at the caret, given the model's raw
    /// continuation, the partial word under the caret, and whether the prefix
    /// ends with whitespace.
    ///
    /// Cases handled:
    /// - The model restates the word being typed (caret after "h", model says
    ///   "how are you") → insert only the new part ("ow are you").
    /// - The caret is in/after a word (no trailing space) → the continuation
    ///   completes it; inserted with no leading space (so "a"+"pproach"="approach",
    ///   never "a pproach"). Trade-off: a complete word followed by a paused new
    ///   word can glue, which self-corrects once a space is typed.
    /// - After whitespace → a new word; inserted as-is.
    public static func inlineSuggestion(
        continuation: String,
        currentWord: String,
        prefixEndsWithSpace: Bool
    ) -> String {
        guard !continuation.isEmpty else { return "" }
        if !currentWord.isEmpty,
            continuation.lowercased().hasPrefix(currentWord.lowercased()) {
            return String(continuation.dropFirst(currentWord.count))
        }
        if currentWord.isEmpty {
            return prefixEndsWithSpace ? continuation : " " + continuation
        }
        return continuation
    }
}
