/// Produces the completion to show after the current text context.
/// Phase 2 will add an MLX-backed conformer; callers depend only on this.
public protocol SuggestionEngine {
    /// The text to show as ghost text after the caret, or "" for no suggestion.
    func suggestion(for context: TextContext) -> String
}

/// Phase 1 placeholder: a fixed completion whenever there's any preceding text.
public struct DummyEngine: SuggestionEngine {
    public init() {}
    public func suggestion(for context: TextContext) -> String {
        context.prefix.isEmpty ? "" : " hello"
    }
}
