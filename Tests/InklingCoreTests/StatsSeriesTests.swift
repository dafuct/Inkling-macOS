import XCTest
@testable import InklingCore

final class StatsSeriesTests: XCTestCase {
    // Fixed UTC calendar + a fixed "now" so bucketing is deterministic.
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    // 2026-06-15 12:00:00 UTC
    private let now = Date(timeIntervalSince1970: 1_781_524_800)

    private func event(_ iso: String, words: Int = 1, chars: Int = 5, first: Bool = true) -> CompletionEvent {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")!
        return CompletionEvent(timestamp: f.date(from: iso)!, appBundleID: nil,
                               words: words, chars: chars, isFirstChunk: first)
    }

    func test_series_groupsByDay_sumsWords() {
        let events = [
            event("2026-06-15T09:00:00Z", words: 2),
            event("2026-06-15T18:00:00Z", words: 3),
            event("2026-06-14T10:00:00Z", words: 1),
        ]
        let s = StatsAggregator.series(events: events, range: .all, groupBy: .day,
                                       metric: .words, now: now, calendar: cal)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].start, cal.startOfDay(for: event("2026-06-14T00:00:00Z").timestamp))
        XCTAssertEqual(s[0].value, 1)   // sorted ascending: the 14th first
        XCTAssertEqual(s[1].value, 5)   // 2 + 3 on the 15th
    }

    func test_series_completionsMetric_countsFirstChunksOnly() {
        let events = [
            event("2026-06-15T09:00:00Z", first: true),
            event("2026-06-15T09:00:01Z", first: false),
            event("2026-06-15T09:00:02Z", first: false),
        ]
        let s = StatsAggregator.series(events: events, range: .all, groupBy: .day,
                                       metric: .completions, now: now, calendar: cal)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].value, 1)   // one completion, three words
    }

    func test_series_range_excludesOlderThanCutoff() {
        let events = [
            event("2026-06-15T09:00:00Z"),   // today
            event("2026-06-01T09:00:00Z"),   // 14 days ago — outside last7Days
        ]
        let s = StatsAggregator.series(events: events, range: .last7Days, groupBy: .day,
                                       metric: .completions, now: now, calendar: cal)
        XCTAssertEqual(s.count, 1)
    }

    func test_series_groupsByWeekAndMonth() {
        let events = [
            event("2026-06-01T09:00:00Z"),   // June
            event("2026-06-15T09:00:00Z"),   // June, different week
            event("2026-05-30T09:00:00Z"),   // May
        ]
        let byMonth = StatsAggregator.series(events: events, range: .all, groupBy: .month,
                                             metric: .completions, now: now, calendar: cal)
        XCTAssertEqual(byMonth.count, 2)     // May + June
        let byWeek = StatsAggregator.series(events: events, range: .all, groupBy: .week,
                                            metric: .completions, now: now, calendar: cal)
        XCTAssertEqual(byWeek.count, 3)      // three distinct weeks
    }

    func test_series_empty_isEmpty() {
        XCTAssertTrue(StatsAggregator.series(events: [], range: .all, groupBy: .day,
                                             metric: .words, now: now, calendar: cal).isEmpty)
    }
}
