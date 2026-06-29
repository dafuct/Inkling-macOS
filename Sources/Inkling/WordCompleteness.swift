import Foundation
import InklingCore

/// Decides whether the word under the caret is a *complete* word (so a new-word
/// continuation should be space-separated: "ready" + "release" -> "ready
/// release") versus a *partial* word still being typed (so the continuation
/// completes it, glued: "contri" + "bute" -> "contribute").
///
/// A word is complete if it's in the macOS system word list OR in the user's
/// learned vocabulary. The latter covers technical terms the system list omits
/// ("debounce", "keystrokes") once the user has typed them — important since the
/// system list is plain English. (`NSSpellChecker` was tried and rejected: it
/// accepts fragments like "contri" as correctly spelled.)
enum WordCompleteness {
    /// `/usr/share/dict/words`, lowercased, loaded once. Empty if unavailable
    /// (then completeness falls back to learned vocabulary only).
    private static let systemWords: Set<String> = {
        guard let text = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8)
        else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }()

    static func isComplete(_ word: String, memory: PersonalMemory) -> Bool {
        // Single letters ("a", "I"): treat as mid-word -> glue ("a"+"pproach"),
        // never space ("a pproach").
        guard word.count >= 2 else { return false }
        return systemWords.contains(word.lowercased()) || memory.knows(word: word)
    }
}
