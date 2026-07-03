/// Exact, output-side detection of degenerate repetition in a generated token
/// stream. Replaces the distribution-warping repetition penalty: instead of
/// down-weighting every recently-seen token (which steers the model away from
/// the user's own topical vocabulary), generation runs on the raw distribution
/// and is cut the moment it demonstrably loops.
public enum LoopDetector {
    /// True when the stream shows a tight loop: the same token three times in a
    /// row, or a token trigram recurring with its start within `maxGap` of the
    /// previous occurrence (periods 1-4: "the the the", "Look at this Look at
    /// this", …). Legitimate reuse further apart — "of the … of the" across a
    /// long clause — does not trip it.
    public static func hasLoop(_ tokens: [Int], maxGap: Int = 4) -> Bool {
        let n = tokens.count
        guard n >= 3 else { return false }
        for i in 2..<n where tokens[i] == tokens[i - 1] && tokens[i - 1] == tokens[i - 2] {
            return true
        }
        guard n >= 6 else { return false }
        var lastStart: [Int: Int] = [:]  // trigram hash -> most recent start index
        for i in 0...(n - 3) {
            var h = Hasher()
            h.combine(tokens[i]); h.combine(tokens[i + 1]); h.combine(tokens[i + 2])
            let key = h.finalize()
            if let prev = lastStart[key], i - prev <= maxGap,
               tokens[prev] == tokens[i], tokens[prev + 1] == tokens[i + 1],
               tokens[prev + 2] == tokens[i + 2] {
                return true
            }
            lastStart[key] = i
        }
        return false
    }
}
