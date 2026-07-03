import XCTest
@testable import InklingCore

final class StatsSummaryTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    private let now = Date(timeIntervalSince1970: 1_781_524_800)   // 2026-06-15 12:00 UTC

    private func event(_ iso: String, words: Int = 1, chars: Int = 5, first: Bool = true) -> CompletionEvent {
        let f = ISO8601DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")!
        return CompletionEvent(timestamp: f.date(from: iso)!, appBundleID: nil,
                               words: words, chars: chars, isFirstChunk: first)
    }

    func test_summary_totalAndActiveDaysAndAverage() {
        let events = [
            event("2026-06-15T09:00:00Z", words: 4),
            event("2026-06-15T10:00:00Z", words: 6),
            event("2026-06-13T10:00:00Z", words: 5),
        ]
        let s = StatsAggregator.summary(events: events, range: .all, metric: .words,
                                        now: now, calendar: cal)
        XCTAssertEqual(s.total, 15)
        XCTAssertEqual(s.activeDays, 2)         // the 13th and the 15th
        XCTAssertEqual(s.dailyAverage, 7)       // 15 / 2 = 7 (integer)
    }

    func test_summary_empty_isZeroed() {
        let s = StatsAggregator.summary(events: [], range: .all, metric: .words,
                                        now: now, calendar: cal)
        XCTAssertEqual(s.total, 0)
        XCTAssertEqual(s.activeDays, 0)
        XCTAssertEqual(s.dailyAverage, 0)
        XCTAssertEqual(s.timeSavedMinutes, 0...0)
    }

    func test_timeSaved_fromCharsRegardlessOfMetric() {
        // 900 chars: fast = ceil(900/300)=3, slow = ceil(900/180)=5.
        let events = [event("2026-06-15T09:00:00Z", words: 1, chars: 900)]
        let s = StatsAggregator.summary(events: events, range: .all, metric: .completions,
                                        now: now, calendar: cal)
        XCTAssertEqual(s.timeSavedMinutes, 3...5)
    }

    func test_timeSaved_ceils() {
        // 100 chars: fast=ceil(100/300)=1, slow=ceil(100/180)=1 -> 1...1.
        let events = [event("2026-06-15T09:00:00Z", chars: 100)]
        let s = StatsAggregator.summary(events: events, range: .all, metric: .words,
                                        now: now, calendar: cal)
        XCTAssertEqual(s.timeSavedMinutes, 1...1)
    }

    func test_todayTotals_onlyToday() {
        let events = [
            event("2026-06-15T01:00:00Z", words: 2, first: true),
            event("2026-06-15T02:00:00Z", words: 1, first: false),
            event("2026-06-14T23:00:00Z", words: 9, first: true),   // yesterday (UTC)
        ]
        let t = StatsAggregator.todayTotals(events: events, now: now, calendar: cal)
        XCTAssertEqual(t.words, 3)          // 2 + 1
        XCTAssertEqual(t.completions, 1)    // one first-chunk today
    }
}
