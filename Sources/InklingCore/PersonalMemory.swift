import Foundation

/// The learned model of how the user writes: word frequencies plus a
/// bigram/trigram next-word model. Pure logic with no AppKit/MLX dependency.
/// Not thread-safe — the app drives it from the main actor.
public final class PersonalMemory {
    /// Counts are Doubles so decay can scale them multiplicatively.
    public private(set) var wordCounts: [String: Double] = [:]
    /// prev1(lowercased) -> nextWord(as typed) -> count
    public private(set) var bigrams: [String: [String: Double]] = [:]
    /// "prev2 prev1"(lowercased) -> nextWord(as typed) -> count
    public private(set) var trigrams: [String: [String: Double]] = [:]

    let limits: Limits

    public init(limits: Limits = Limits()) {
        self.limits = limits
    }

    /// Record one completed word, given the words that preceded it (most recent
    /// last; only the last two are used).
    public func learn(word: String, previous: [String]) {
        guard !word.isEmpty else { return }
        wordCounts[word, default: 0] += 1
        guard let p1 = previous.last else { return }
        bigrams[p1.lowercased(), default: [:]][word, default: 0] += 1
        if previous.count >= 2 {
            let p2 = previous[previous.count - 2]
            let key = "\(p2.lowercased()) \(p1.lowercased())"
            trigrams[key, default: [:]][word, default: 0] += 1
        }
    }

    /// Learned words that extend `prefix` (case-insensitive), longest-count
    /// first. The exact prefix itself is excluded (no zero-length completion).
    public func wordCandidates(withPrefix prefix: String) -> [(word: String, count: Double)] {
        let lp = prefix.lowercased()
        return wordCounts
            .filter { $0.key.lowercased().hasPrefix(lp) && $0.key.count > prefix.count }
            .map { (word: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    /// Likely next words given recent context (trigram, backing off to bigram),
    /// highest-count first.
    public func nextWordCandidates(after context: [String]) -> [(word: String, count: Double)] {
        if context.count >= 2 {
            let key = "\(context[context.count - 2].lowercased()) \(context[context.count - 1].lowercased())"
            if let m = trigrams[key], !m.isEmpty { return sorted(m) }
        }
        if let last = context.last, let m = bigrams[last.lowercased()], !m.isEmpty {
            return sorted(m)
        }
        return []
    }

    private func sorted(_ m: [String: Double]) -> [(word: String, count: Double)] {
        m.map { (word: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    /// Fade and bound the model: scale every count by `decayFactor`, drop
    /// entries below `pruneFloor`, then cap to the size limits. Call sparingly
    /// (e.g. once per launch).
    public func decay() {
        scale(&wordCounts)
        wordCounts = capByValue(wordCounts, max: limits.maxWords)
        scaleNested(&bigrams)
        bigrams = capContexts(bigrams, max: limits.maxContexts)
        scaleNested(&trigrams)
        trigrams = capContexts(trigrams, max: limits.maxContexts)
    }

    private func scale(_ map: inout [String: Double]) {
        for k in map.keys { map[k]! *= limits.decayFactor }
        map = map.filter { $0.value >= limits.pruneFloor }
    }

    private func scaleNested(_ map: inout [String: [String: Double]]) {
        for ctx in map.keys {
            var inner = map[ctx]!
            for w in inner.keys { inner[w]! *= limits.decayFactor }
            inner = inner.filter { $0.value >= limits.pruneFloor }
            if inner.isEmpty { map[ctx] = nil } else { map[ctx] = inner }
        }
    }

    private func capByValue(_ map: [String: Double], max: Int) -> [String: Double] {
        guard map.count > max else { return map }
        let kept = map.sorted { $0.value > $1.value }.prefix(max)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    private func capContexts(_ map: [String: [String: Double]], max: Int) -> [String: [String: Double]] {
        guard map.count > max else { return map }
        let kept = map.sorted { ($0.value.values.max() ?? 0) > ($1.value.values.max() ?? 0) }.prefix(max)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
    }

    /// Top frequent words suitable as an LLM vocabulary hint: at least 3 chars,
    /// seen at least 3 times, not a common stopword. Highest-count first.
    public func frequentVocabulary(max: Int) -> [String] {
        wordCounts
            .filter { $0.key.count >= 3 && $0.value >= 3 && !Self.stopwords.contains($0.key.lowercased()) }
            .sorted { $0.value > $1.value }
            .prefix(max)
            .map { $0.key }
    }

    /// Replace this model's contents from a decoded snapshot.
    public func restore(from snapshot: Snapshot) {
        wordCounts = snapshot.wordCounts
        bigrams = snapshot.bigrams
        trigrams = snapshot.trigrams
    }

    /// A Codable copy of the model's contents.
    public var snapshot: Snapshot {
        Snapshot(wordCounts: wordCounts, bigrams: bigrams, trigrams: trigrams)
    }

    static let stopwords: Set<String> = [
        "the", "and", "you", "that", "this", "for", "are", "was", "but", "not",
        "with", "have", "your", "from", "they", "she", "him", "her", "his",
        "can", "all", "would", "there", "their", "what", "out", "about", "who",
        "get", "which", "when", "make", "like", "time", "just", "know", "people",
        "into", "year", "good", "some", "could", "them", "see", "other", "than",
        "then", "now", "look", "only", "come", "its", "over", "think", "also",
    ]
}

public extension PersonalMemory {
    /// Tunable size and freshness knobs.
    struct Limits {
        public var maxWords: Int
        public var maxContexts: Int   // max context keys kept per n-gram map
        public var decayFactor: Double
        public var pruneFloor: Double
        public init(maxWords: Int = 5_000, maxContexts: Int = 20_000,
                    decayFactor: Double = 0.9, pruneFloor: Double = 1.0) {
            self.maxWords = maxWords
            self.maxContexts = maxContexts
            self.decayFactor = decayFactor
            self.pruneFloor = pruneFloor
        }
    }

    /// Serializable contents of the model.
    struct Snapshot: Codable {
        public var wordCounts: [String: Double]
        public var bigrams: [String: [String: Double]]
        public var trigrams: [String: [String: Double]]
        public init(wordCounts: [String: Double] = [:],
                    bigrams: [String: [String: Double]] = [:],
                    trigrams: [String: [String: Double]] = [:]) {
            self.wordCounts = wordCounts
            self.bigrams = bigrams
            self.trigrams = trigrams
        }
    }
}
