/// What pressing the accept key (backtick) should do, given the modifier and the
/// current suggestion state. Pure decision so the event tap stays a thin adapter.
public enum AcceptKeyAction: Equatable {
    case accept       // backtick, no Option: accept the shown suggestion
    case cycle        // Option+backtick with ≥2 alternatives: show the next one
    case passThrough  // not our key / no suggestion / Option with no alternatives

    public static func classify(
        isAcceptKey: Bool,
        optionHeld: Bool,
        suggestionVisible: Bool,
        alternativesAvailable: Bool
    ) -> AcceptKeyAction {
        guard suggestionVisible, isAcceptKey else { return .passThrough }
        if optionHeld { return alternativesAvailable ? .cycle : .passThrough }
        return .accept
    }
}
