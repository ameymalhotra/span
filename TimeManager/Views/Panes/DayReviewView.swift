import SwiftData
import SwiftUI

/// Totals and session list for one day.
struct DayReviewView: View {
    let day: Date

    @Environment(\.modelContext) private var context
    @State private var editing: WorkSession?

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
            PaneHeader(title: Format.dayTitle(day))
            Divider()
            ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                metrics
                completedSessions
            }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.xl)
                .padding(.bottom, Theme.Space.xxl)
            }
        }
        .background(Theme.canvas)
        .sheet(item: $editing) { session in
            SessionEditor(session: session) { editing = nil }
                .padding(.vertical, Theme.Space.s)
        }
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            HStack(spacing: Theme.Space.m) {
                MetricTile(label: "Focused", value: Format.compact(report.focusedTime))
                MetricTile(label: "Tracked", value: Format.compact(report.trackedTime))
                // The gap between what the timer counted and what the user said
                // was real work is the whole point of the reflection feature, so
                // the two are shown side by side rather than reconciled.
                MetricTile(
                    label: "Honest work",
                    value: report.reflectedCount > 0 ? Format.compact(report.honestWorkTime) : "—",
                    caption: unreflectedCaption
                )
                MetricTile(label: "Distractions", value: "\(report.distractions)")
            }
        }
    }

    private var unreflectedCaption: String? {
        let missing = report.completedCount - report.reflectedCount
        guard missing > 0 else { return nil }
        return "\(missing) unreviewed"
    }

    @ViewBuilder
    private var completedSessions: some View {
        let completed = sessions.filter { $0.status == .completed }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Sessions")
                .font(Theme.Font.sectionHeader)
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryLabel)

            if completed.isEmpty {
                Text("No finished sessions on this day.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.tertiaryLabel)
                    .padding(.vertical, Theme.Space.s)
            } else {
                ForEach(completed) { session in
                    SessionRow(session: session)
                        .onTapGesture { editing = session }
                        .contextMenu {
                            Button("Edit…") { editing = session }
                            Button("Delete", role: .destructive) {
                                NotificationService.cancelReminder(for: session)
                                context.delete(session)
                                try? context.save()
                            }
                        }
                }
            }
        }
    }
}

private struct SessionRow: View {
    let session: WorkSession

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Circle()
                .fill(CategoryPalette.color(for: session.category))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.label)
                Text("\(session.category) · \(Format.timeOfDay(session.startedAt))")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
            }

            Spacer(minLength: Theme.Space.m)

            if let rating = session.focusRating {
                FocusPips(rating: rating)
            } else {
                Text("Not reviewed")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }

            Text(Format.compact(session.elapsed()))
                .font(Theme.Font.body.monospacedDigit())
                .foregroundStyle(Theme.label)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(Theme.Space.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}

struct MetricTile: View {
    let label: String
    let value: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.Font.statValue)
                .foregroundStyle(Theme.label)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
            // Always rendered, even when empty: a tile with a caption would
            // otherwise be taller than the ones beside it.
            Text(caption ?? " ")
                .font(Theme.Font.micro)
                .foregroundStyle(Theme.tertiaryLabel)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .padding(Theme.Space.l)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
    }
}
