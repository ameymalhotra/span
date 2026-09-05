import Charts
import SwiftData
import SwiftUI

/// How the work has actually been going: totals, trend, honesty, and where the
/// hours went.
struct InsightsView: View {
    let anchor: Date

    @AppStorage("dailyFocusTargetMinutes") private var targetMinutes = 300

    @Query private var sessions: [WorkSession]
    @Query private var activity: [ActivityRecord]

    private let calendar = Calendar.current
    private static let window = 14

    init(anchor: Date) {
        self.anchor = anchor
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: anchor)) ?? anchor
        let start = cal.date(byAdding: .day, value: -Self.window, to: end) ?? end
        _sessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
        _activity = Query(filter: #Predicate<ActivityRecord> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
    }

    private struct DayTotal: Identifiable {
        let day: Date
        let focus: TimeInterval
        let honest: TimeInterval
        var id: Date { day }
    }

    /// Every day in the window, including the empty ones — a missing Wednesday
    /// should read as a gap, not close up.
    private var days: [DayTotal] {
        let end = calendar.startOfDay(for: anchor)
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.startedAt) }
        return (0..<Self.window).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(Self.window - 1 - offset), to: end)
            else { return nil }
            let onDay = grouped[day, default: []]
            return DayTotal(
                day: day,
                focus: onDay.reduce(0) { $0 + $1.elapsed() },
                honest: onDay.reduce(0) { $0 + TimeInterval(($1.honestWorkMinutes ?? 0) * 60) }
            )
        }
    }

    private var totalFocus: TimeInterval { days.reduce(0) { $0 + $1.focus } }
    private var activeDays: Int { days.filter { $0.focus > 0 }.count }
    private var bestDay: DayTotal? { days.max { $0.focus < $1.focus } }
    private var reflected: [WorkSession] { sessions.filter(\.isReflected) }

    /// Consecutive days ending today that cleared the target.
    private var streak: Int {
        var count = 0
        for day in days.reversed() {
            guard day.focus >= TimeInterval(targetMinutes * 60) else { break }
            count += 1
        }
        return count
    }

    private var categories: [CategoryTotal] {
        var totals: [String: TimeInterval] = [:]
        for session in sessions {
            totals[session.category.isEmpty ? "Uncategorised" : session.category, default: 0] += session.elapsed()
        }
        for record in activity where !record.isIdle {
            totals[record.categoryName ?? record.appName, default: 0] += record.duration
        }
        let grand = totals.values.reduce(0, +)
        return totals
            .map { CategoryTotal(name: $0.key, duration: $0.value, fraction: grand > 0 ? $0.value / grand : 0) }
            .sorted { $0.duration > $1.duration }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Insights", subtitle: "Last \(Self.window) days")
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                header
                focusTrend
                honestyChart
                categoryChart
            }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        .background(Theme.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                MetricTile(label: "Total focus", value: Format.compact(totalFocus))
                MetricTile(label: "Daily average",
                           value: Format.compact(totalFocus / Double(Self.window)))
                MetricTile(label: "Days worked", value: "\(activeDays) of \(Self.window)")
                MetricTile(label: "Target streak",
                           value: streak == 0 ? "—" : "\(streak)",
                           caption: streak == 1 ? "day" : "days")
            }
        }
    }

    // MARK: - Charts

    @ViewBuilder
    private var focusTrend: some View {
        section("Focus per day", note: "Against your \(Format.compact(TimeInterval(targetMinutes * 60))) target") {
            if totalFocus == 0 {
                empty("No sessions yet in this window.")
            } else {
                // One series, so no legend — the heading names it. Fourteen bars
                // is too many to label individually, so the axis carries values.
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Focus", day.focus / 3600)
                    )
                    .foregroundStyle(Theme.accent)
                    .cornerRadius(3)

                    RuleMark(y: .value("Target", Double(targetMinutes) / 60))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.tertiaryLabel)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.hairlineFaint)
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(Theme.Font.micro)
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.day())
                                    .font(Theme.Font.micro)
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                    }
                }
                .frame(height: 190)
            }
        }
    }

    @ViewBuilder
    private var honestyChart: some View {
        section("Time on the clock vs time that felt real",
                note: reflected.isEmpty ? nil : "\(reflected.count) of \(sessions.count) sessions reviewed") {
            if reflected.isEmpty {
                empty("Review a session to see how the two compare.")
            } else {
                // Two series, so a legend is required; the honest bar sits
                // inside the wall-clock bar so the shortfall is the visual.
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Hours", day.focus / 3600)
                    )
                    .foregroundStyle(by: .value("Measure", "On the clock"))
                    .cornerRadius(3)

                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Hours", day.honest / 3600),
                        width: .ratio(0.45)
                    )
                    .foregroundStyle(by: .value("Measure", "Felt real"))
                    .cornerRadius(2)
                }
                .chartForegroundStyleScale([
                    "On the clock": Theme.accent.opacity(0.35),
                    "Felt real": Theme.accent,
                ])
                .chartLegend(position: .top, alignment: .leading, spacing: Theme.Space.m)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Theme.hairlineFaint)
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(Theme.Font.micro)
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.day())
                                    .font(Theme.Font.micro)
                                    .foregroundStyle(Theme.tertiaryLabel)
                            }
                        }
                    }
                }
                .frame(height: 190)
            }
        }
    }

    @ViewBuilder
    private var categoryChart: some View {
        section("Where the time went", note: nil) {
            if categories.isEmpty {
                empty("Nothing tracked in this window yet.")
            } else {
                // Directly labelled rows rather than a legend — the name sits
                // beside its colour, so the two closest hues never have to be
                // told apart by eye.
                VStack(spacing: Theme.Space.s) {
                    ForEach(categories) { total in
                        HStack(spacing: Theme.Space.s) {
                            Circle()
                                .fill(total.color)
                                .frame(width: 8, height: 8)
                            Text(total.name)
                                .font(Theme.Font.body)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.hairlineFaint)
                                    Capsule()
                                        .fill(total.color)
                                        .frame(width: max(2, proxy.size.width * total.fraction))
                                }
                            }
                            .frame(height: 8)
                            Text(Format.compact(total.duration))
                                .font(Theme.Font.body.monospacedDigit())
                                .frame(width: 64, alignment: .trailing)
                            Text(Format.percent(total.fraction))
                                .font(Theme.Font.caption.monospacedDigit())
                                .foregroundStyle(Theme.secondaryLabel)
                                .frame(width: 42, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Chrome

    private func section(_ title: String, note: String?,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                Text(title)
                    .font(Theme.Font.sectionHeader)
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.secondaryLabel)
                if let note {
                    Text(note)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.tertiaryLabel)
                }
            }
            content()
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.tertiaryLabel)
            .frame(maxWidth: .infinity, minHeight: 120)
    }
}
