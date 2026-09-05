import SwiftUI
import SwiftData

struct DaySummaryView: View {
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]

    private var todaysSessions: [WorkSession] {
        sessions.filter { Calendar.current.isDateInToday($0.startedAt) && $0.status == .completed }
    }
    private var timerMinutes: Int { todaysSessions.reduce(0) { $0 + Int($1.elapsed() / 60) } }
    private var honestMinutes: Int { todaysSessions.compactMap(\.honestWorkMinutes).reduce(0, +) }
    private var distractions: Int { todaysSessions.compactMap(\.distractions).reduce(0, +) }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    HStack { SummaryMetric(title: "Timer", value: minutes(timerMinutes)); Spacer(); SummaryMetric(title: "Honest work", value: minutes(honestMinutes)); Spacer(); SummaryMetric(title: "Distractions", value: "\(distractions)") }
                        .padding(.vertical, 8)
                }
                Section("Completed sessions") {
                    if todaysSessions.isEmpty {
                        Text("Your completed sessions will appear here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(todaysSessions, id: \.id) { session in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.title).font(.headline)
                            Text("\(session.category) · \(minutes(Int(session.elapsed() / 60)))")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let focus = session.focusRating {
                                Text("Focus \(focus)/5 · \(session.distractions ?? 0) distractions")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Day")
        }
    }

    private func minutes(_ value: Int) -> String { "\(value)m" }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 3) { Text(value).font(.title3.bold()); Text(title).font(.caption).foregroundStyle(.secondary) }
    }
}
