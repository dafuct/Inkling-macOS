import Foundation

/// One bar of the Statistics chart: the interval start and the summed metric.
public struct StatsBucket: Equatable, Sendable {
    public let start: Date
    public let value: Int
    public init(start: Date, value: Int) { self.start = start; self.value = value }
}

/// Footer stats for the Statistics screen.
public struct StatsSummary: Equatable, Sendable {
    public let total: Int
    public let activeDays: Int
    public let dailyAverage: Int
    public let timeSavedMinutes: ClosedRange<Int>
    public init(total: Int, activeDays: Int, dailyAverage: Int, timeSavedMinutes: ClosedRange<Int>) {
        self.total = total
        self.activeDays = activeDays
        self.dailyAverage = dailyAverage
        self.timeSavedMinutes = timeSavedMinutes
    }
}

/// Pure aggregation over completion events. All time reasoning uses the injected
/// `now` and `calendar` — no wall-clock calls here — so it is fully testable.
public enum StatsAggregator {
    public static let fastCPM = 300.0
    public static let slowCPM = 180.0

    /// Lower bound (inclusive) for a range, or nil for `.all`.
    public static func cutoff(_ range: StatsRange, now: Date, calendar: Calendar) -> Date? {
        let startToday = calendar.startOfDay(for: now)
        switch range {
        case .last7Days:  return calendar.date(byAdding: .day, value: -6, to: startToday)
        case .last30Days: return calendar.date(byAdding: .day, value: -29, to: startToday)
        case .last90Days: return calendar.date(byAdding: .day, value: -89, to: startToday)
        case .thisYear:   return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .all:        return nil
        }
    }

    public static func metricValue(_ e: CompletionEvent, _ metric: StatsMetric) -> Int {
        switch metric {
        case .words: return e.words
        case .chars: return e.chars
        case .completions: return e.isFirstChunk ? 1 : 0
        }
    }

    /// Start of the calendar interval (day/week/month) containing `date`.
    public static func bucketStart(_ date: Date, _ groupBy: StatsGroupBy, _ calendar: Calendar) -> Date {
        let component: Calendar.Component
        switch groupBy {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        return calendar.dateInterval(of: component, for: date)?.start
            ?? calendar.startOfDay(for: date)
    }

    static func filtered(_ events: [CompletionEvent], _ range: StatsRange,
                         now: Date, calendar: Calendar) -> [CompletionEvent] {
        guard let low = cutoff(range, now: now, calendar: calendar) else { return events }
        return events.filter { $0.timestamp >= low }
    }

    public static func series(events: [CompletionEvent], range: StatsRange,
                              groupBy: StatsGroupBy, metric: StatsMetric,
                              now: Date, calendar: Calendar = .current) -> [StatsBucket] {
        var sums: [Date: Int] = [:]
        for e in filtered(events, range, now: now, calendar: calendar) {
            let key = bucketStart(e.timestamp, groupBy, calendar)
            sums[key, default: 0] += metricValue(e, metric)
        }
        return sums.map { StatsBucket(start: $0.key, value: $0.value) }
            .sorted { $0.start < $1.start }
    }

    public static func summary(events: [CompletionEvent], range: StatsRange,
                               metric: StatsMetric,
                               now: Date, calendar: Calendar = .current) -> StatsSummary {
        let inRange = filtered(events, range, now: now, calendar: calendar)
        let total = inRange.reduce(0) { $0 + metricValue($1, metric) }
        let days = Set(inRange.map { calendar.startOfDay(for: $0.timestamp) })
        let activeDays = days.count
        let dailyAverage = activeDays == 0 ? 0 : total / activeDays
        let totalChars = inRange.reduce(0) { $0 + $1.chars }
        let saved = timeSaved(chars: totalChars)
        return StatsSummary(total: total, activeDays: activeDays,
                            dailyAverage: dailyAverage, timeSavedMinutes: saved)
    }

    /// Minute range from accepted chars: ceil(chars / cpm) for each bound.
    static func timeSaved(chars: Int) -> ClosedRange<Int> {
        guard chars > 0 else { return 0...0 }
        let fast = Int((Double(chars) / fastCPM).rounded(.up))   // fewer minutes
        let slow = Int((Double(chars) / slowCPM).rounded(.up))   // more minutes
        return min(fast, slow)...max(fast, slow)
    }

    public static func todayTotals(events: [CompletionEvent],
                                   now: Date, calendar: Calendar = .current)
        -> (words: Int, completions: Int) {
        let startToday = calendar.startOfDay(for: now)
        let today = events.filter { calendar.startOfDay(for: $0.timestamp) == startToday }
        let words = today.reduce(0) { $0 + $1.words }
        let completions = today.reduce(0) { $0 + ($1.isFirstChunk ? 1 : 0) }
        return (words, completions)
    }
}
