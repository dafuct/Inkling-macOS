import Foundation

/// One accepted completion chunk (one backtick press). The canonical unit the
/// Statistics screen aggregates. Holds only counts + timestamp + bundle ID —
/// no typed text — so it is stored plaintext.
public struct CompletionEvent: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var appBundleID: String?
    public var words: Int          // 1 per accepted chunk
    public var chars: Int          // characters inserted by this accept
    public var isFirstChunk: Bool  // first accept of a given ghost-text suggestion

    public init(timestamp: Date, appBundleID: String?, words: Int, chars: Int,
                isFirstChunk: Bool) {
        self.timestamp = timestamp
        self.appBundleID = appBundleID
        self.words = words
        self.chars = chars
        self.isFirstChunk = isFirstChunk
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID)
        words = try c.decodeIfPresent(Int.self, forKey: .words) ?? 0
        chars = try c.decodeIfPresent(Int.self, forKey: .chars) ?? 0
        isFirstChunk = try c.decodeIfPresent(Bool.self, forKey: .isFirstChunk) ?? false
    }
}

/// The metric plotted on the Statistics chart.
public enum StatsMetric: String, CaseIterable, Sendable { case words, chars, completions }

/// Chart bucket granularity.
public enum StatsGroupBy: String, CaseIterable, Sendable { case day, week, month }

/// Chart time window.
public enum StatsRange: String, CaseIterable, Sendable {
    case last7Days, last30Days, last90Days, thisYear, all
}
