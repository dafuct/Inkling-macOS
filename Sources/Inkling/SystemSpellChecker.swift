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
}
