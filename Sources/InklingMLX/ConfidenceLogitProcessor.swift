import MLX
import MLXLMCommon
import InklingCore

/// Records the top-1 / top-2 softmax probability at each decode step so the
/// caller can confidence-gate the greedy continuation.
///
/// Optionally wraps an `inner` processor (e.g. MLX's repetition penalty). The
/// inner penalty is applied to the logits FIRST, then we record — and the sampler
/// then uses — the same penalized distribution. This matters: a model echoing the
/// prefix loops with *high* confidence, which confidence gating alone cannot stop;
/// the penalty is what actually breaks the loop, and recording the penalized
/// probabilities keeps the gate honest about what was really sampled.
///
/// A `class` (reference type) on purpose: `LogitProcessor.process(logits:)` is
/// non-mutating, but we must accumulate `recorded` across steps.
final class ConfidenceLogitProcessor: LogitProcessor {
    /// One entry per generated step, in order. `recorded[i]` is the distribution
    /// that produced the i-th generated token.
    private(set) var recorded: [(top1: Double, top2: Double)] = []

    /// Penalty (or other) processor applied before recording/sampling. `var` so we
    /// can forward the protocol's `mutating` hooks to it.
    private var inner: LogitProcessor?

    init(inner: LogitProcessor? = nil) { self.inner = inner }

    func prompt(_ prompt: MLXArray) { inner?.prompt(prompt) }

    func process(logits: MLXArray) -> MLXArray {
        assert(logits.shape.count == 2 && logits.shape[0] == 1,
               "ConfidenceLogitProcessor expects [1, vocab] logits, got \(logits.shape)")
        // Apply the inner penalty first; record/sample the SAME adjusted logits.
        let adjusted = inner?.process(logits: logits) ?? logits
        // softmax over the vocab axis, force to float32 so asArray is dtype-safe,
        // then read the row to the CPU once.
        let probs = softmax(adjusted, axis: -1).asType(.float32)
        eval(probs)
        let row = probs.asArray(Float.self)
        recorded.append(ConfidenceGate.top2(of: row))
        return adjusted
    }

    func didSample(token: MLXArray) { inner?.didSample(token: token) }
}
