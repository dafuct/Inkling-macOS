import MLX
import MLXLMCommon
import InklingCore

/// Records the top-1 / top-2 softmax probability at each decode step so the
/// caller can confidence-gate the greedy continuation. Returns the logits
/// unchanged, so token sampling is unaffected.
///
/// A `class` (reference type) on purpose: `LogitProcessor.process(logits:)` is
/// non-mutating, but we must accumulate `recorded` across steps.
final class ConfidenceLogitProcessor: LogitProcessor {
    /// One entry per generated step, in order. `recorded[i]` is the distribution
    /// that produced the i-th generated token.
    private(set) var recorded: [(top1: Double, top2: Double)] = []

    func prompt(_ prompt: MLXArray) {}

    func process(logits: MLXArray) -> MLXArray {
        assert(logits.shape.count == 2 && logits.shape[0] == 1,
               "ConfidenceLogitProcessor expects [1, vocab] logits, got \(logits.shape)")
        // logits arrive shaped [1, vocab]; softmax over the vocab axis, force to
        // float32 so asArray is dtype-safe, then read the row to the CPU once.
        let probs = softmax(logits, axis: -1).asType(.float32)
        eval(probs)
        let row = probs.asArray(Float.self)
        recorded.append(ConfidenceGate.top2(of: row))
        return logits
    }

    func didSample(token: MLXArray) {}
}
