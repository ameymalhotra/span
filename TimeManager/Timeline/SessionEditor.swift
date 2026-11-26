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
    /// Handed in rather than read from the environment. The editor is always
    /// presented in a sheet, and setting an end that has not happened yet has
    /// to reach the one model every surface shares — a session that quietly
    /// failed to start again would look exactly like the bug this fixes.
    let model: AppModel
    var width: CGFloat = 300
    let onClose: () -> Void

    @State private var isConfirmingDelete = false
    @State private var deleteError: String?
    /// What is in the real-work field. Held apart from the stored number so a
    /// half-typed or emptied entry is not snapped to something else.
    @State private var honestDraft = ""
    /// A running session's new planned length, held until Done. Applied as it
    /// was typed, deleting "50" to write "40" passed through 5 and 4 — shorter
    /// than the time already worked — and the clock ended the session before
    /// the user had finished typing. Nil until the picker is touched.
    @State private var plannedDraft: Int?

    private var isRunning: Bool { session.status != .completed }

    private var plannedMinutes: Int { plannedDraft ?? session.plannedMinutes }

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
        .frame(width: width)
        .alert("Couldn’t delete session", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(deleteError ?? "") }
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
                Text(Format.compact(TimeInterval(plannedMinutes * 60)))
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            DurationPicker(minutes: Binding(
                get: { plannedMinutes },
                set: { plannedDraft = $0 }
            ), showsSummary: false)
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
                session.clampReviewToWorkedTime()
                save()
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { session.endedAt ?? .now },
            set: { moment in
                let end = max(moment, session.startedAt.addingTimeInterval(60))
                // An end that has not happened yet means the work has not
                // either: the session goes back to running rather than sitting
                // finished with time to come. The panel redraws as Running.
                if model.resumeSession(session, endingAt: end) { return }
                session.endedAt = min(end, .now)
                let last = session.segments
                    .max { ($0.endedAt ?? $0.startedAt) < ($1.endedAt ?? $1.startedAt) }
                last?.endedAt = session.endedAt
                // The review answered a longer session; it cannot claim more
                // real work than the session now holds.
                session.clampReviewToWorkedTime()
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
            .frame(width: min(170, max(100, width - 110)))
        }

        // The review's own question, editable here for the same reason the
        // rating is: a session whose times were corrected has an answer that no
        // longer fits it, and the sheet that asked is long gone.
        if !isRunning {
            HStack {
                Text("Real work")
                Spacer()
                TextField("Minutes", text: $honestDraft, prompt: Text("Not set"))
                    .accessibilityIdentifier("editor.honestMinutes")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onChange(of: honestDraft) { _, new in commitHonestMinutes(new) }
                Stepper("", value: Binding(
                    get: { session.honestWorkMinutes ?? session.workedMinutes() },
                    set: { setHonestMinutes($0) }
                ), in: 0...max(1, session.workedMinutes()))
                .labelsHidden()
                Text("of \(session.workedMinutes())m")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            .onAppear { honestDraft = session.honestWorkMinutes.map(String.init) ?? "" }
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

    private func commitHonestMinutes(_ text: String) {
        let digits = text.filter(\.isNumber)
        if digits != text { honestDraft = digits; return }
        guard let value = Int(digits) else {
            session.honestWorkMinutes = nil
            save()
            return
        }
        let clamped = min(max(value, 0), session.workedMinutes())
        session.honestWorkMinutes = clamped
        if clamped != value { honestDraft = "\(clamped)" }
        save()
    }

    private func setHonestMinutes(_ value: Int) {
        let clamped = min(max(value, 0), session.workedMinutes())
        session.honestWorkMinutes = clamped
        honestDraft = "\(clamped)"
        save()
    }

    private func delete() {
        do {
            try model.deleteSession(session)
            onClose()
        } catch { deleteError = error.localizedDescription }
    }

    private func commit() {
        if session.title.trimmingCharacters(in: .whitespaces).isEmpty {
            session.title = "Untitled session"
        }
        if isRunning, let minutes = plannedDraft, minutes != session.plannedMinutes {
            model.setPlannedMinutes(minutes, for: session)
        }
        save()
        onClose()
    }

    private func save() {
        try? context.save()
    }
}
