import AppKit
import InklingCore

/// `NSSpellChecker`-backed autocorrection. Uses Apple's conservative single-best
/// `correction(forWordRange:…)` (the same engine as system-wide autocorrect),
/// NOT the looser `guesses(forWordRange:…)`. Must be called on the main actor;
/// Inkling calls it from the debounced refresh, which runs on `.main`.
struct SystemSpellChecker: SpellChecker {
    func correction(for word: String) -> String? {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.correction(
            forWordRange: range, in: word,
            language: checker.language(), inSpellDocumentWithTag: 0)
    }

    /// True when `fragment` is the start of one or more longer real words, so the
    /// user is still mid-word (e.g. "hel" → "hello"/"help"). Uses the same
    /// dictionary as system autocomplete. Guards against the corrector "fixing" an
    /// unfinished word into an unrelated one ("Hel" → "Hey").
    static func isPrefixOfWord(_ fragment: String) -> Bool {
        let checker = NSSpellChecker.shared
        let range = NSRange(location: 0, length: (fragment as NSString).length)
        let completions = checker.completions(
            forPartialWordRange: range, in: fragment,
            language: checker.language(), inSpellDocumentWithTag: 0) ?? []
        // A completion equal to the fragment itself doesn't prove it's a prefix of
        // anything longer; require a strictly longer continuation.
        let n = fragment.count
        return completions.contains { $0.count > n }
    }
}
