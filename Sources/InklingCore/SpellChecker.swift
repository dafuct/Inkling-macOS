/// A source of single-best spelling corrections. Kept as a protocol so
/// `InklingCore` stays free of AppKit; the app supplies an `NSSpellChecker`
/// backing, tests supply a fake.
public protocol SpellChecker {
    /// The single best autocorrection for `word`, or nil when there is no
    /// confident correction (e.g. the word is already spelled correctly).
    /// Callers pass a lowercased word; the returned candidate is lowercased.
    func correction(for word: String) -> String?
}

/// A proposed replacement of a mistyped word: delete `original`, type `replacement`.
public struct Correction: Equatable {
    public let original: String
    public let replacement: String
    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }
}
