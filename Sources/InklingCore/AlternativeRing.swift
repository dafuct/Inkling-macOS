/// An ordered set of alternative completions with a current index that advances
/// with wrap-around. Pure value type.
public struct AlternativeRing: Equatable {
    private let candidates: [String]
    private var index: Int

    public init(_ candidates: [String]) {
        self.candidates = candidates
        self.index = 0
    }

    /// The currently-selected candidate, or nil when empty.
    public var current: String? { candidates.isEmpty ? nil : candidates[index] }
    public var count: Int { candidates.count }
    /// True when there is more than one candidate to cycle through.
    public var hasAlternatives: Bool { candidates.count >= 2 }

    /// Advance to the next candidate, wrapping past the end. No-op when empty.
    public mutating func next() {
        guard !candidates.isEmpty else { return }
        index = (index + 1) % candidates.count
    }
}
