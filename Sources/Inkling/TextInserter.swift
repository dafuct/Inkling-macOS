import CoreGraphics

/// Inserts text into the frontmost app by synthesizing Unicode key events.
/// Universal: works in any app that accepts typed keyboard input. Each event is
/// tagged with `marker` so our own EventTapController ignores it — otherwise
/// accepting a word would re-trigger a suggestion query and replace the rest.
enum TextInserter {
    static let marker: Int64 = 0x494E4B  // "INK"

    static func insert(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for unit in text.utf16 {
            var code = unit
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                down.setIntegerValueField(.eventSourceUserData, value: marker)
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                up.setIntegerValueField(.eventSourceUserData, value: marker)
                up.post(tap: .cgSessionEventTap)
            }
        }
    }

    /// Replaces the `count` characters immediately before the caret with `text`:
    /// synthesizes `count` marker-tagged backspaces, then types `text`. Marker-
    /// tagged so our own EventTapController ignores the edits (same as `insert`).
    /// `count` is one backspace per unit, so the caller counts deletions in the
    /// same units the app deletes in: the autocorrect caller passes the Character
    /// count of a letters/digits-only word, which is grapheme-safe (no combining
    /// marks or emoji reach this path).
    static func replace(deleting count: Int, insert text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let backspace: CGKeyCode = 0x33  // kVK_Delete
        for _ in 0..<max(0, count) {
            if let down = CGEvent(keyboardEventSource: source, virtualKey: backspace, keyDown: true) {
                down.setIntegerValueField(.eventSourceUserData, value: marker)
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: backspace, keyDown: false) {
                up.setIntegerValueField(.eventSourceUserData, value: marker)
                up.post(tap: .cgSessionEventTap)
            }
        }
        insert(text)
    }
}
