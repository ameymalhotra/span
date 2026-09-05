import SwiftData
import SwiftUI

/// Where a day's time went, by category.
struct CategoryBreakdownView: View {
    let day: Date

    @Query private var sessions: [WorkSession]
    @Query private var entries: [TimeEntry]
    @Query private var activity: [ActivityRecord]

    init(day: Date) {
        self.day = day
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _sessions = Query(filter: #Predicate<WorkSession> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
        _entries = Query(filter: #Predicate<TimeEntry> { $0.startedAt >= start && $0.startedAt < end },
                         sort: \.startedAt)
        _activity = Query(filter: #Predicate<ActivityRecord> { $0.startedAt >= start && $0.startedAt < end },
                          sort: \.startedAt)
    }

    private var report: DayReport {
        DayReport(day: day, sessions: sessions, entries: entries, activity: activity)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Categories", subtitle: Format.dayTitle(day))
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if report.categories.isEmpty {
                    Text("Nothing tracked on this day yet.")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.tertiaryLabel)
                        .padding(.vertical, Theme.Space.m)
                } else {
                    ForEach(report.categories) { total in
                        CategoryRow(total: total)
                    }
                }
            }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        .background(Theme.canvas)
    }
}

private struct CategoryRow: View {
    let total: CategoryTotal

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(total.color)
                    .frame(width: 8, height: 8)
                // The name carries identity alongside the colour, so the two
                // closest hues in the palette never have to be told apart by
                // eye alone.
                Text(total.name)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.label)
                Spacer(minLength: Theme.Space.m)
                Text(Format.compact(total.duration))
                    .font(Theme.Font.body.monospacedDigit())
                    .foregroundStyle(Theme.label)
                Text(Format.percent(total.fraction))
                    .font(Theme.Font.caption.monospacedDigit())
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 42, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairlineFaint)
                    Capsule()
                        .fill(total.color)
                        .frame(width: max(2, proxy.size.width * total.fraction))
                }
            }
            .frame(height: 4)
        }
        .padding(Theme.Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}
