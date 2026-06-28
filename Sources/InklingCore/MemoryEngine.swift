/// A confident memory completion plus whether it is an *exact repeat*
/// (completing a word the user is typing from a known word) rather than a
/// speculative next-word prediction. The tiered UI trusts exact repeats over
/// the LLM; speculative predictions get upgraded by the LLM.
public struct MemoryHit: Equatable, Sendable {
    public let text: String
    public let isExactRepeat: Bool
    public init(text: String, isExactRepeat: Bool) {
        self.text = text
        self.isExactRepeat = isExactRepeat
    }
}

/// Confidence-gated deterministic completion from a PersonalMemory. Pure.
public enum MemoryEngine {
    public struct Gates {
        public var minSightings: Double
        public var minPrefixLength: Int
        public var dominanceRatio: Double
        public var maxChainWords: Int
        public init(minSightings: Double = 3, minPrefixLength: Int = 2,
                    dominanceRatio: Double = 2.0, maxChainWords: Int = 3) {
            self.minSightings = minSightings
            self.minPrefixLength = minPrefixLength
            self.dominanceRatio = dominanceRatio
            self.maxChainWords = maxChainWords
        }
    }

    /// The inline text to show after the caret, or nil if nothing is confident.
    /// Thin wrapper over `hit` for callers that don't need the exact-repeat flag.
    public static func completion(
        currentWord: String,
        precedingWords: [String],
        memory: PersonalMemory,
        gates: Gates = Gates()
    ) -> String? {
        hit(currentWord: currentWord, precedingWords: precedingWords,
            memory: memory, gates: gates)?.text
    }

    /// Like `completion`, but reports whether the hit is an exact word-completion
    /// (`isExactRepeat == true`) or a speculative next-word chain (`false`).
    /// With a non-empty `currentWord`, completes that word (exact repeat);
    /// otherwise predicts the next word(s) from `precedingWords` (speculative).
    public static func hit(
        currentWord: String,
        precedingWords: [String],
        memory: PersonalMemory,
        gates: Gates = Gates()
    ) -> MemoryHit? {
        if currentWord.isEmpty {
            guard let text = nextWords(precedingWords: precedingWords, memory: memory, gates: gates)
            else { return nil }
            return MemoryHit(text: text, isExactRepeat: false)
        }
        guard let text = wordCompletion(currentWord: currentWord, memory: memory, gates: gates)
        else { return nil }
        return MemoryHit(text: text, isExactRepeat: true)
    }

    private static func wordCompletion(currentWord: String, memory: PersonalMemory, gates: Gates) -> String? {
        guard currentWord.count >= gates.minPrefixLength else { return nil }
        let cands = memory.wordCandidates(withPrefix: currentWord)
        guard let top = cands.first, passesGates(cands, gates: gates) else { return nil }
        return String(top.word.dropFirst(currentWord.count))
    }

    private static func nextWords(precedingWords: [String], memory: PersonalMemory, gates: Gates) -> String? {
        var ctx = precedingWords
        var out: [String] = []
        for _ in 0..<gates.maxChainWords {
            let cands = memory.nextWordCandidates(after: ctx)
            guard let top = cands.first, passesGates(cands, gates: gates) else { break }
            out.append(top.word)
            ctx.append(top.word)
            if ctx.count > 2 { ctx.removeFirst() }
        }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }

    private static func passesGates(_ cands: [(word: String, count: Double)], gates: Gates) -> Bool {
        guard let top = cands.first, top.count >= gates.minSightings else { return false }
        let runnerUp = cands.dropFirst().first?.count ?? 0
        return runnerUp == 0 || top.count >= gates.dominanceRatio * runnerUp
    }
}
