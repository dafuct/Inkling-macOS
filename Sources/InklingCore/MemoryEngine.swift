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
    /// With a non-empty `currentWord`, completes that word; otherwise predicts
    /// the next word(s) from `precedingWords` (joined with spaces).
    public static func completion(
        currentWord: String,
        precedingWords: [String],
        memory: PersonalMemory,
        gates: Gates = Gates()
    ) -> String? {
        if currentWord.isEmpty {
            return nextWords(precedingWords: precedingWords, memory: memory, gates: gates)
        }
        return wordCompletion(currentWord: currentWord, memory: memory, gates: gates)
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
