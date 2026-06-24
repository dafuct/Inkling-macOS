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
}
