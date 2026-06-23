import CoreGraphics

/// Inserts text into the frontmost app by synthesizing Unicode key events.
/// Universal: works in any app that accepts typed keyboard input.
enum TextInserter {
    static func insert(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for unit in text.utf16 {
            var code = unit
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                down.post(tap: .cgSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
                up.post(tap: .cgSessionEventTap)
            }
        }
    }
}
