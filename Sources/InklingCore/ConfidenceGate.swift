/// Thresholds controlling when an LLM continuation token is "confident enough"
/// to surface as ghost text.
public struct ConfidenceThresholds: Equatable, Sendable {
    /// Probability floor for the FIRST token. The primary control over how often
    /// any suggestion appears at all.
    public var firstTokenMinProb: Double
    /// Probability floor for each subsequent token. Controls where a shown
    /// suggestion stops.
    public var minProb: Double
    /// The chosen token's probability must be at least `dominance ×` the
    /// runner-up's. Suppresses coin-flip continuations.
    public var dominance: Double

    public init(firstTokenMinProb: Double = 0.65, minProb: Double = 0.45, dominance: Double = 1.5) {
        self.firstTokenMinProb = firstTokenMinProb
        self.minProb = minProb
        self.dominance = dominance
    }
}

/// Pure confidence gating for the LLM suggestion path. No MLX, no I/O — given the
/// per-token top-1/top-2 probabilities of a greedy continuation, decides how many
/// leading tokens are confident enough to show.
public enum ConfidenceGate {
    /// Whether one token clears the gate. `top1`/`top2` are the highest and
    /// second-highest softmax probabilities at that step; `isFirst` selects the
    /// stricter first-token floor.
    public static func accepts(
        top1: Double, top2: Double, isFirst: Bool, thresholds: ConfidenceThresholds
    ) -> Bool {
        let floor = isFirst ? thresholds.firstTokenMinProb : thresholds.minProb
        guard top1 >= floor else { return false }
        guard top2 <= 0 || top1 >= thresholds.dominance * top2 else { return false }
        return true
    }

    /// Number of leading tokens to keep — stops at the first token that fails the
    /// gate. 0 means "show nothing".
    public static func acceptedTokenCount(
        probs: [(top1: Double, top2: Double)], thresholds: ConfidenceThresholds
    ) -> Int {
        var n = 0
        for (i, p) in probs.enumerated() {
            guard accepts(top1: p.top1, top2: p.top2, isFirst: i == 0, thresholds: thresholds)
            else { break }
            n += 1
        }
        return n
    }

    /// The two highest values in `values` as (top1, top2); top2 is 0 when there
    /// are fewer than two. Turns a softmax row into the (top1, top2) pair the
    /// gate needs in a single O(n) pass — no full-vocabulary sort.
    public static func top2(of values: [Float]) -> (top1: Double, top2: Double) {
        var t1: Float = -.infinity
        var t2: Float = -.infinity
        for v in values {
            if v > t1 { t2 = t1; t1 = v }
            else if v > t2 { t2 = v }
        }
        return (t1.isFinite ? Double(t1) : 0, t2.isFinite ? Double(t2) : 0)
    }
}
