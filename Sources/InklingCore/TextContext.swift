/// A snapshot of a text field: its full contents and the caret position,
/// expressed as a UTF-16 offset to match Accessibility's selected-range API.
public struct TextContext: Equatable {
    public let fullText: String
    public let caretIndex: Int

    public init(fullText: String, caretIndex: Int) {
        self.fullText = fullText
        self.caretIndex = max(0, min(caretIndex, fullText.utf16.count))
    }

    /// Everything from the start of the field up to the caret.
    public var prefix: String {
        let u16 = fullText.utf16
        let end = u16.index(u16.startIndex, offsetBy: caretIndex, limitedBy: u16.endIndex) ?? u16.endIndex
        guard let strEnd = end.samePosition(in: fullText) else { return fullText }
        return String(fullText[fullText.startIndex..<strEnd])
    }

    /// True if the caret sits at the end of its line — nothing follows, or the
    /// next character is a line break. Inline ghost text drawn at the caret would
    /// overlap any following text, so suggestions should only appear here.
    public var isAtLineEnd: Bool {
        let u16 = fullText.utf16
        let end = u16.index(u16.startIndex, offsetBy: caretIndex, limitedBy: u16.endIndex) ?? u16.endIndex
        guard let strEnd = end.samePosition(in: fullText), strEnd < fullText.endIndex else { return true }
        let next = fullText[strEnd]
        return next == "\n" || next == "\r"
    }

    /// The partial word (letters/digits) immediately before the caret, or "".
    public var currentWord: String {
        var chars: [Character] = []
        for ch in prefix.reversed() {
            if ch.isLetter || ch.isNumber { chars.append(ch) } else { break }
        }
        return String(chars.reversed())
    }
}
