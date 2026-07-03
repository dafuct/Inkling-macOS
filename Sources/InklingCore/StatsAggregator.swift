import Foundation

/// One bar of the Statistics chart: the interval start and the summed metric.
public struct StatsBucket: Equatable, Sendable {
    public let start: Date
    public let value: Int
    public init(start: Date, value: Int) { self.start = start; self.value = value }
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
}
