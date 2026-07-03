/// Mid-word completion via prompt backup: when the caret sits inside a word
/// that isn't dictionary-complete ("impl", "loadModelContai"), continuing the
/// raw prefix lets the model treat the fragment as a finished token and bolt a
/// new word onto it ("impl" → " Trait for a function return type"). Instead,
/// the decode prompt backs up to the word boundary so the model regenerates
/// the word WHOLE ("implement …"), and the result is accepted only when it
/// prefix-matches what the user actually typed — otherwise we show nothing,
/// because a mid-word suggestion that fights the user's word is worse than
/// silence. Pure string logic — no MLX, no I/O.
public enum MidWordCompletion {
    /// The decode prompt for completing `currentWord`: the prefix with the
    /// partial word removed, so the model regenerates the word from its start.
    public static func decodePrompt(prefix: String, currentWord: String) -> String {
        guard !currentWord.isEmpty, prefix.hasSuffix(currentWord) else { return prefix }
        return String(prefix.dropLast(currentWord.count))
    }

    /// Resolves a continuation generated from the backed-up prompt against the
    /// partial word. Returns the caret-ready remainder when the model
    /// regenerated the typed word (case-insensitive; one leading space
    /// tolerated — tokenizers differ on whether the word token carries it), or
    /// nil when the model wanted a different word.
    public static func resolve(candidate: String, currentWord: String) -> String? {
        guard !currentWord.isEmpty else { return candidate }
        var c = Substring(candidate)
        if c.first == " " { c = c.dropFirst() }
        guard c.lowercased().hasPrefix(currentWord.lowercased()) else { return nil }
        return String(c.dropFirst(currentWord.count))
    }
}
