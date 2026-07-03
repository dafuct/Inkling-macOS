import Foundation

/// Pure per-session bookkeeping for input capture: tracks whether a completion
/// was accepted during the session and decides whether the session's final
/// text is worth storing. The app owns the AX plumbing; this owns the decision.
public struct InputSessionState: Equatable, Sendable {
    public private(set) var hadAcceptedCompletion: Bool

    public init() { hadAcceptedCompletion = false }

    public mutating func noteAccepted() { hadAcceptedCompletion = true }

    /// Store when the text is non-trivial (>= 3 non-whitespace chars) AND either
    /// we keep all inputs or this session had an accepted completion.
    public func shouldStore(text: String, storeWithoutAccepted: Bool) -> Bool {
        let meaningful = text.reduce(into: 0) { count, ch in
            if !ch.isWhitespace { count += 1 }
        }
        guard meaningful >= 3 else { return false }
        return storeWithoutAccepted || hadAcceptedCompletion
    }

    public mutating func reset() { hadAcceptedCompletion = false }
}
