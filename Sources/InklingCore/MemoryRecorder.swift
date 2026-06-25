/// Accumulates typed characters into the current word and a short history of
/// recently completed words, emitting `onWord` whenever a word boundary is
/// typed. Pure: the app feeds it characters; it never touches AppKit.
public final class MemoryRecorder {
    public private(set) var currentWord: String = ""
    public private(set) var recentWords: [String] = []   // most recent last
    private let historyLimit = 2

    /// Called when a word is completed. The array is the context BEFORE this
    /// word (most recent last), suitable for n-gram learning.
    public var onWord: ((String, [String]) -> Void)?

    public init() {}

    public func append(_ s: String) { for ch in s { appendChar(ch) } }

    private func appendChar(_ ch: Character) {
        if ch.isLetter || ch.isNumber || ch == "'" {
            currentWord.append(ch)
        } else {
            commit()
        }
    }

    public func backspace() {
        if !currentWord.isEmpty { currentWord.removeLast() }
        // We intentionally do not un-commit across a boundary in v1.
    }

    public func reset() {
        currentWord = ""
        recentWords = []
    }

    private func commit() {
        guard !currentWord.isEmpty else { return }
        let word = currentWord
        onWord?(word, recentWords)
        recentWords.append(word)
        if recentWords.count > historyLimit { recentWords.removeFirst() }
        currentWord = ""
    }
}
