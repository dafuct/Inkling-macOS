/// Pure consistency check between the keystroke-recorder's current word and the
/// live text field's current word (read via Accessibility).
public enum SuggestionSync {
    /// Whether the recorder-tracked word is consistent with the live field word.
    ///
    /// The event tap sees keystrokes BEFORE the target app inserts them, so the
    /// recorder can be AHEAD of the AX value (which updates only after the app
    /// processes the key). We accept when the live word is a prefix of the
    /// recorded word — i.e. the recorder is the same or just ahead — and both are
    /// on the same boundary (both mid-word, or both at a word start). A genuine
    /// desync (the words diverge, or one is mid-word while the other isn't) is
    /// rejected so we never show a completion that wouldn't line up.
    public static func consistent(recorded: String, live: String) -> Bool {
        recorded.hasPrefix(live) && (recorded.isEmpty == live.isEmpty)
    }
}
