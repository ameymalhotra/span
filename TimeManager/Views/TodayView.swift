import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]
    @State private var showingStart = false
    @State private var sessionToReflect: WorkSession?

    private var activeSession: WorkSession? {
        sessions.first { $0.status == .active || $0.status == .paused }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let activeSession {
                    RunningSessionView(session: activeSession, reflectSession: $sessionToReflect)
                } else {
                    emptyState
                }
            }
            .navigationTitle("Time Manager")
            .toolbar {
                if activeSession == nil {
                    Button("Start", systemImage: "plus") { showingStart = true }
                }
            }
            .sheet(isPresented: $showingStart) {
                StartSessionView { title, category, minutes in
                    let session = WorkSession(title: title, category: category, plannedMinutes: minutes)
                    modelContext.insert(session)
                    Task {
                        _ = await NotificationService.requestAuthorization()
                        NotificationService.scheduleEndReminder(for: session)
                    }
                }
            }
            .sheet(item: $sessionToReflect) { session in
                ReflectionView(session: session)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Make time intentional", systemImage: "target")
        } description: {
            Text("Start a focused session, then give yourself an honest review when it ends.")
        } actions: {
            Button("Start a session") { showingStart = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct RunningSessionView: View {
    @Environment(\.modelContext) private var modelContext
    let session: WorkSession
    @Binding var reflectSession: WorkSession?
    @State private var now = Date.now

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = session.remaining(at: context.date)
            VStack(spacing: 28) {
                Text(session.category.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(session.title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(timeString(remaining))
                    .font(.system(size: 68, weight: .thin, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("\(Int(remaining / 60)) minutes remaining")
                if remaining == 0 && session.status == .active {
                    Text("Time’s up. Take an honest look at the session.")
                        .foregroundStyle(.orange)
                } else if session.status == .paused {
                    Text("Paused")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(session.status == .paused ? "Resume" : "Pause") {
                        if session.status == .paused {
                            session.resume()
                            NotificationService.scheduleEndReminder(for: session)
                        } else {
                            session.pause()
                            NotificationService.cancelReminder(for: session)
                        }
                        try? modelContext.save()
                    }
                    .buttonStyle(.bordered)

                    Button("Finish") {
                        NotificationService.cancelReminder(for: session)
                        session.complete()
                        try? modelContext.save()
                        reflectSession = session
                    }
                    .buttonStyle(.borderedProminent)
                }
                if remaining == 0 && session.status == .active {
                    Button("Add 5 minutes") {
                        session.plannedMinutes += 5
                        NotificationService.scheduleEndReminder(for: session)
                        try? modelContext.save()
                    }
                    .font(.subheadline)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func timeString(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
