/// What is currently shown as ghost text, for the tiered replacement policy.
public enum ShownSuggestion: Equatable, Sendable {
    case none
    case memory(exactRepeat: Bool)
    case llm
}

/// The decision for a freshly-arrived LLM suggestion, given what is on screen.
public enum SuggestionDecision: Equatable, Sendable {
    case keep            // leave the visible suggestion as-is
    case replaceWithLLM  // swap in the LLM suggestion
    case dismiss         // hide everything
}

/// Pure replacement policy for the tiered (memory → LLM upgrade) UI. No AppKit,
/// no I/O. Given what is shown and the freshly-arrived LLM suggestion, decides
/// whether to keep, replace, or dismiss.
///
/// Policy:
/// - while the user is accepting word-by-word, never swap (`accepting`);
/// - a high-confidence exact memory repeat beats the LLM;
/// - an empty LLM result keeps a shown memory suggestion, else dismisses;
/// - an LLM suggestion identical to what is shown is a no-op (no flicker);
/// - otherwise the LLM upgrades the suggestion.
///
/// `visibleText` is the actual ghost text currently on screen (used only for the
/// no-flicker identity check), distinct from the structural `shown` state.
public enum SuggestionArbiter {
    public static func decide(
        shown: ShownSuggestion,
        visibleText: String,
        llmSuggestion: String,
        accepting: Bool
    ) -> SuggestionDecision {
        if accepting { return .keep }
        if case .memory(exactRepeat: true) = shown { return .keep }
        if llmSuggestion.isEmpty {
            if case .memory = shown { return .keep }
            return .dismiss
        }
        if llmSuggestion == visibleText { return .keep }
        return .replaceWithLLM
    }
}
