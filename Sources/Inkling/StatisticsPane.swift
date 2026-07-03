import Charts
import InklingCore
import SwiftUI

/// Cotypist's Statistics screen: Today's Activity, a completion-statistics bar
/// chart with Time Range / Group By / Metric selectors, and Total / Daily
/// Average / Estimated Time Saved.
struct StatisticsPane: View {
    @Bindable var store = CompletionEventStore.shared
    @State private var range: StatsRange = .last30Days
    @State private var groupBy: StatsGroupBy = .day
    @State private var metric: StatsMetric = .words

    private var buckets: [StatsBucket] {
        StatsAggregator.series(events: store.allEvents(), range: range,
                               groupBy: groupBy, metric: metric,
                               now: Date(), calendar: .current)
    }
    private var summary: StatsSummary {
        StatsAggregator.summary(events: store.allEvents(), range: range,
                                metric: metric, now: Date(), calendar: .current)
    }
    private var today: (words: Int, completions: Int) {
        StatsAggregator.todayTotals(events: store.allEvents(), now: Date(), calendar: .current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                todaySection
                chartSection
            }
            .padding()
        }
        .navigationTitle("Statistics")
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's Activity").font(.headline)
            if today.words == 0 && today.completions == 0 {
                Text("No completions recorded today").foregroundStyle(.secondary)
            } else {
                Text("\(today.words) words · \(today.completions) completions today")
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completion Statistics").font(.headline)
            HStack(spacing: 16) {
                Picker("Time Range", selection: $range) {
                    Text("Last 7 Days").tag(StatsRange.last7Days)
                    Text("Last 30 Days").tag(StatsRange.last30Days)
                    Text("Last 90 Days").tag(StatsRange.last90Days)
                    Text("This Year").tag(StatsRange.thisYear)
                    Text("All").tag(StatsRange.all)
                }
                Picker("Group By", selection: $groupBy) {
                    Text("Day").tag(StatsGroupBy.day)
                    Text("Week").tag(StatsGroupBy.week)
                    Text("Month").tag(StatsGroupBy.month)
                }
                Picker("Metric", selection: $metric) {
                    Text("Words").tag(StatsMetric.words)
                    Text("Chars").tag(StatsMetric.chars)
                    Text("Completions").tag(StatsMetric.completions)
                }
            }
            if buckets.isEmpty {
                Text("No completions in this range yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(buckets, id: \.start) { b in
                    BarMark(x: .value("Date", b.start), y: .value(metric.rawValue, b.value))
                }
                .frame(height: 240)
            }
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 32) {
            stat("Total", "\(summary.total)")
            stat("Daily Average (Active Days)", "\(summary.dailyAverage)")
            stat("Estimated Time Saved", timeSavedText)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
    }

    private var timeSavedText: String {
        let r = summary.timeSavedMinutes
        if r == 0...0 { return "—" }
        return r.lowerBound == r.upperBound
            ? "≈\(r.lowerBound) min"
            : "≈\(r.lowerBound)–\(r.upperBound) min"
    }
}
