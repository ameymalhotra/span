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
        /// Every session on the day.
        let focus: TimeInterval
        /// Only the sessions that were actually reviewed. The honesty chart can
        /// speak for those and no others: an unreviewed session has no answer,
        /// and counting its time as "didn't feel real" would put words in the
        /// user's mouth.
        let reviewedClock: TimeInterval
        /// How much of `reviewedClock` the user called real work.
        let honest: TimeInterval
        var id: Date { day }
        /// The reviewed time they did not count — the top of each bar.
        var drifted: TimeInterval { max(0, reviewedClock - honest) }
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
            let split = DayReport.honestySplit(of: onDay)
            return DayTotal(
                day: day,
                focus: onDay.reduce(0) { $0 + $1.elapsed() },
                reviewedClock: split.clocked,
                honest: split.honest
            )
        }
    }

    private var totalFocus: TimeInterval { days.reduce(0) { $0 + $1.focus } }
    private var activeDays: Int { days.filter { $0.focus > 0 }.count }
    private var bestDay: DayTotal? { days.max { $0.focus < $1.focus } }
    private var reflected: [WorkSession] { sessions.filter(\.isReflected) }

    /// Totals across the reviewed sessions only, which is all the honesty
    /// chart claims to describe.
    private var reviewedClock: TimeInterval { days.reduce(0) { $0 + $1.reviewedClock } }
    private var honestTotal: TimeInterval { days.reduce(0) { $0 + $1.honest } }
    private var honestShare: Double { reviewedClock > 0 ? honestTotal / reviewedClock : 0 }

    private static let realLabel = "Felt like real work"
    private static let driftLabel = "The rest of the clock"

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
        section("How much of the clocked time felt real",
                note: reflected.isEmpty
                    ? nil
                    : "\(Format.percent(honestShare)) across \(reflected.count) reviewed \(reflected.count == 1 ? "session" : "sessions")") {
            if reflected.isEmpty {
                empty("Review a session to see how much of the time on the clock felt real.")
            } else {
                // One bar per day, split rather than overlaid. Two separate
                // BarMarks at the same x do not draw on top of each other in
                // Swift Charts — they stack — so plotting "on the clock" and
                // "felt real" as independent series made the bar as tall as
                // the two added together and stood the honest part above the
                // clock it came out of. Reading it literally, the time that
                // felt real looked like more time than was worked.
                //
                // The two parts here are complementary by construction: the
                // solid share plus the faint remainder is exactly the time
                // clocked, so stacking them says something true.
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Hours", day.honest / 3600)
                    )
                    .foregroundStyle(by: .value("Measure", Self.realLabel))
                    .cornerRadius(2)

                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Hours", day.drifted / 3600)
                    )
                    .foregroundStyle(by: .value("Measure", Self.driftLabel))
                    .cornerRadius(2)
                }
                // Domain and range rather than a dictionary: a dictionary has no
                // order, and the scale's order is what decides both the legend's
                // and which half of the bar sits at the bottom. The share that
                // felt real belongs at the base, growing up from the axis.
                .chartForegroundStyleScale(
                    domain: [Self.realLabel, Self.driftLabel],
                    range: [Theme.accent, Theme.accent.opacity(0.22)]
                )
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

                Text("Each bar is the time you clocked in sessions you reviewed. The solid part is how much of it you said felt like real work; the faint part is the rest. Sessions you never reviewed are left out — there is no answer to show for them.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
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
