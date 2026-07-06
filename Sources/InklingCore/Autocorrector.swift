import Foundation

/// Pure acceptance policy for current-word autocorrect. Given a candidate from a
/// `SpellChecker`, decides whether a correction is worth offering and transfers
/// the original word's capitalization onto the replacement. No AppKit, no I/O.
public struct Autocorrector {
    private let checker: SpellChecker
    private let isRealWord: (String) -> Bool
    private let isPrefixOfWord: (String) -> Bool
    private let minLength: Int
    private let maxEditDistance: Int

    /// - Parameters:
    ///   - checker: the correction source (lowercased in, lowercased out).
    ///   - isRealWord: membership in the system dictionary (called with a
    ///     lowercased word). A correctly-spelled word is never "corrected".
    ///   - isPrefixOfWord: true when the (lowercased) fragment is a valid prefix
    ///     of one or more longer real words — i.e. the user is still mid-word.
    ///     Such fragments ("hel" → "hello"/"help") are unfinished, not typos, so
    ///     they must never be corrected. Defaults to always-false so callers that
    ///     don't supply a prefix source keep the old behaviour.
    public init(checker: SpellChecker,
                isRealWord: @escaping (String) -> Bool,
                isPrefixOfWord: @escaping (String) -> Bool = { _ in false },
                minLength: Int = 3,
                maxEditDistance: Int = 2) {
        self.checker = checker
        self.isRealWord = isRealWord
        self.isPrefixOfWord = isPrefixOfWord
        self.minLength = minLength
        self.maxEditDistance = maxEditDistance
    }

    public func correction(for word: String, memory: PersonalMemory) -> Correction? {
        guard word.count >= minLength else { return nil }
        let lower = word.lowercased()
        guard !isRealWord(lower) else { return nil }        // real word: leave it
        guard !memory.knows(word: word) else { return nil }  // learned jargon/name: leave it
        guard !isPrefixOfWord(lower) else { return nil }     // unfinished word, not a typo
        guard let candidate = checker.correction(for: lower) else { return nil }
        let candLower = candidate.lowercased()
        guard candLower != lower else { return nil }                       // identity
        guard Self.editDistance(lower, candLower) <= maxEditDistance else { return nil }
        return Correction(original: word, replacement: Self.transferCase(from: word, to: candidate))
    }

    /// Carry the original word's casing onto the replacement:
    /// "TEH" -> "THE", "Teh" -> "The", "teh" -> "the".
    static func transferCase(from original: String, to replacement: String) -> String {
        if original.count > 1, original == original.uppercased(), original != original.lowercased() {
            return replacement.uppercased()
        }
        if let first = original.first, first.isUppercase {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    /// Classic Levenshtein distance over Characters.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        var prev = Array(0...t.count)
        var curr = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            curr[0] = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[t.count]
    }
}
