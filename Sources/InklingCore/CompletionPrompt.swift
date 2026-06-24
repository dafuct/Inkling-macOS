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

    /// Decide the exact text to insert at the caret.
    /// - midWord: the caret is inside a partial word, so the continuation
    ///   completes it — inserted with no leading space.
    /// - otherwise the continuation is a new word — inserted with a single
    ///   leading space, unless the prefix already ends with whitespace.
    public static func inlineSuggestion(
        continuation: String, midWord: Bool, prefixEndsWithSpace: Bool
    ) -> String {
        guard !continuation.isEmpty else { return "" }
        if midWord { return continuation }
        return prefixEndsWithSpace ? continuation : " " + continuation
    }
}
