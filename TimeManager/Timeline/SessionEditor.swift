import SwiftData
import SwiftUI

/// Edits a session — what it was, when it ran, and how it went.
///
/// Available whether or not the session is still running: a session in progress
/// is the one you are most likely to have mislabelled, so nothing here is gated
/// on it having finished.
struct SessionEditor: View {
    @Environment(\.modelContext) private var context

    @Bindable var session: WorkSession
    let onClose: () -> Void

    @State private var isConfirmingDelete = false

    private var isRunning: Bool { session.status != .completed }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            header
            TextField("What are you working on?", text: $session.title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .onSubmit(commit)

            CategoryPicker(selection: $session.category)

            Divider()

            timing

            Divider()

            review

            Divider()

            footer
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.l)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: Theme.Space.s) {
            Circle()
                .fill(CategoryPalette.color(for: session.category))
                .frame(width: 8, height: 8)
            Text(isRunning ? (session.status == .paused ? "Paused" : "Running") : "Session")
                .font(Theme.Font.caption)
                .foregroundStyle(isRunning ? Theme.accent : Theme.secondaryLabel)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.tertiaryLabel)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Timing

    @ViewBuilder
    private var timing: some View {
        DatePicker("Started", selection: startBinding, displayedComponents: [.hourAndMinute])

        if isRunning {
            // A running session has no recorded end, so what is editable is how
            // long it is meant to run — which is what the countdown shows.
            HStack {
                Text("Planned")
                Spacer()
                Text(Format.compact(session.plannedDuration))
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            DurationPicker(minutes: $session.plannedMinutes, showsSummary: false)
                .onChange(of: session.plannedMinutes) { _, _ in
                    NotificationService.scheduleEndReminder(for: session)
                    save()
                }
        } else {
            DatePicker("Ended", selection: endBinding, displayedComponents: [.hourAndMinute])
        }

        HStack {
            Text("Worked")
            Spacer()
            Text(Format.compact(session.elapsed()))
                .foregroundStyle(Theme.secondaryLabel)
                .monospacedDigit()
        }
    }

    /// A session's extent lives in its segments, so both ends write through to
    /// the first and last of them — the timeline is drawn from those, and would
    /// otherwise snap back on the next redraw.
    private var startBinding: Binding<Date> {
        Binding(
            get: { session.startedAt },
            set: { moment in
                session.startedAt = moment
                if let first = session.segments.min(by: { $0.startedAt < $1.startedAt }) {
                    first.startedAt = moment
                }
                save()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { session.endedAt ?? .now },
            set: { moment in
                let end = max(moment, session.startedAt.addingTimeInterval(60))
                session.endedAt = end
                let last = session.segments
                    .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
                last?.endedAt = end
                save()
            }
        )
    }

    // MARK: - Review

    @ViewBuilder
    private var review: some View {
        HStack {
            Text("Focus")
            Spacer()
            Picker("", selection: Binding(
                get: { session.focusRating ?? 0 },
                set: {
                    session.focusRating = $0 == 0 ? nil : $0
                    if $0 != 0 { session.reflectionState = .completed }
                    save()
                }
            )) {
                Text("—").tag(0)
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 170)
        }

        HStack {
            Text("Distractions")
            Spacer()
            Stepper("\(session.distractions ?? 0)", value: Binding(
                get: { session.distractions ?? 0 },
                set: { session.distractions = $0; save() }
            ), in: 0...50)
            .labelsHidden()
            Text("\(session.distractions ?? 0)")
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryLabel)
                .frame(width: 22, alignment: .trailing)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .confirmationDialog("Delete this session?",
                                isPresented: $isConfirmingDelete) {
                Button("Delete session", role: .destructive, action: delete)
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("\(Format.compact(session.elapsed())) of recorded work will be removed. This cannot be undone.")
            }

            Spacer()

            Button("Done", action: commit)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func delete() {
        NotificationService.cancelReminder(for: session)
        context.delete(session)
        try? context.save()
        onClose()
    }

    private func commit() {
        if session.title.trimmingCharacters(in: .whitespaces).isEmpty {
            session.title = "Untitled session"
        }
        save()
        onClose()
    }

    private func save() {
        try? context.save()
    }
}
