import Charts
import SwiftData
import SwiftUI

/// Day-over-day focus time for the seven days ending on the selected day.
struct WeekReviewView: View {
    let anchor: Date

    @Query private var sessions: [WorkSession]

    private let calendar = Calendar.current

    init(anchor: Date) {
        self.anchor = anchor
        let end = Calendar.current.date(
            byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: anchor)
        ) ?? anchor
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        _sessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
    }

    private struct DayTotal: Identifiable {
        let day: Date
        let focus: TimeInterval
        var id: Date { day }
    }

    /// Every day in the window is present, including empty ones — a week with a
    /// missing Wednesday should show a gap, not silently close up.
    private var totals: [DayTotal] {
        let end = calendar.startOfDay(for: anchor)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: -6 + $0, to: end) }
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return days.map { day in
            DayTotal(day: day, focus: grouped[day, default: []].reduce(0) { $0 + $1.elapsed() })
        }
    }

    private var busiest: TimeInterval { totals.map(\.focus).max() ?? 0 }
    private var weekTotal: TimeInterval { totals.reduce(0) { $0 + $1.focus } }
    private var activeDays: Int { totals.filter { $0.focus > 0 }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                chart
            }
            .padding(Theme.Space.xl)
        }
        .background(Theme.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Last 7 days")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.label)
            HStack(spacing: Theme.Space.m) {
                MetricTile(label: "Total focus", value: Format.compact(weekTotal))
                MetricTile(label: "Daily average", value: Format.compact(weekTotal / 7))
                MetricTile(label: "Days worked", value: "\(activeDays) of 7")
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if weekTotal == 0 {
            Text("No focus sessions in this week.")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.tertiaryLabel)
                .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            // One series, so no legend: the heading names it. Values are written
            // on the bars and the y-axis is dropped, rather than encoding the
            // same number twice.
            Chart(totals) { total in
                BarMark(
                    x: .value("Day", total.day, unit: .day),
                    y: .value("Focus", total.focus / 3600)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(4)
                .annotation(position: .top, spacing: 4) {
                    if total.focus > 0 {
                        Text(Format.compact(total.focus))
                            .font(Theme.Font.micro)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            VStack(spacing: 1) {
                                Text(Format.weekdayInitial(date))
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(
                                        calendar.isDateInToday(date) ? Theme.accent : Theme.secondaryLabel
                                    )
                                Text(date, format: .dateTime.day())
                                    .font(Theme.Font.micro)
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                    }
                    AxisGridLine().foregroundStyle(Theme.hairlineFaint)
                }
            }
            .frame(height: 220)
            .padding(.top, Theme.Space.s)
        }
    }
}
