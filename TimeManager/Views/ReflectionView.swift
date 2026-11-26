import AppKit
import SwiftUI
import SwiftData

/// The post-session honest review.
struct ReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var model
    let session: WorkSession
    /// How the session ended, so the sheet can account for one the user did not
    /// finish themselves.
    var ending: SessionEnding = .byHand

    @State private var focus = 3
    /// Starts unset rather than pre-filled. Defaulting this to the full elapsed
    /// time anchors the user on the flattering answer before they have thought
    /// about it, which is the opposite of what an honest review is for.
    @State private var honestMinutes: Int?
    /// What is actually in the field. Kept alongside the number so a
    /// half-typed or emptied entry is not snapped to something else under the
    /// cursor.
    @State private var honestDraft = ""
    @State private var distractions = 0
    @State private var note = ""

    /// Whether the review also asks where you left off. A setting, because not
    /// every session ends a stretch of work worth a handoff.
    @AppStorage("log.promptAtSessionEnd") private var asksForLog = true
    @Query(sort: \LogTab.sortIndex) private var logTabs: [LogTab]
    @State private var logDraft = LogDraft()
    @State private var logError: String?

    /// Keep an unfinished handoff reachable even if its tab is archived in
    /// another window or the prompt setting changes while the sheet is open.
    private var showsLog: Bool {
        logDraft.hasText || (asksForLog && logTabs.contains { !$0.isArchived })
    }

    init(session: WorkSession, ending: SessionEnding = .byHand) {
        self.session = session
        self.ending = ending
        // Seeded here rather than on appear, so the cursor can land in the
        // resume field the moment the sheet opens.
        _logDraft = State(initialValue: LogDraft(tabID: session.logTabID))
    }

    private var maximumMinutes: Int { max(1, Int(session.elapsed() / 60)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 480)
        // No silent third exit: the sheet is dismissed by Save or by Skip, both
        // of which record what happened.
        .interactiveDismissDisabled()
        .onAppear {
            // The tab the session was started for, if it is still around.
            if LogBook.activeTab(id: logDraft.tabID, in: logTabs) == nil { logDraft.tabID = nil }
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { logError != nil },
            set: { if !$0 { logError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(logError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("How did it go?")
                .font(.system(size: 15, weight: .semibold))
            Text("Be kind and honest — this is for you, not a scorecard.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
            if let note = endingNote {
                Label(note.text, systemImage: note.symbol)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityIdentifier("reflection.autoFinished")
            }
        }
        .padding(Theme.Space.l)
    }

    /// Why this session is over, when the user was not the one who ended it.
    private var endingNote: (text: String, symbol: String)? {
        let at = Format.timeOfDay(session.endedAt ?? .now)
        switch ending {
        case .byHand: return nil
        case .plannedEnd:
            return ("Finished at \(at), when its planned time ran out.", "checkmark.circle")
        case .abandoned:
            return ("Finished for you at \(at), where you stopped — it was left running.", "moon.zzz")
        }
    }

    private var form: some View {
        Form {
            if showsLog {
                logSection
            }

            Section("How focused were you?") {
                Picker("Focus", selection: $focus) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("reflection.focus")
            }

            Section("How much of it felt like real work?") {
                // A field first, arrows second. Stepping to 40 of 95 minutes is
                // forty presses; the number is quicker to type than to nudge.
                HStack(spacing: Theme.Space.s) {
                    TextField("Minutes", text: $honestDraft, prompt: Text("Not set"))
                        .accessibilityIdentifier("reflection.honestMinutes")
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                        .onChange(of: honestDraft) { _, new in commitHonestMinutes(new) }
                    Stepper("", value: Binding(
                        get: { honestMinutes ?? maximumMinutes },
                        set: { setHonestMinutes($0) }
                    ), in: 0...maximumMinutes)
                    .labelsHidden()
                    .accessibilityIdentifier("reflection.honestMinutesStepper")
                    Text("of \(maximumMinutes) minutes")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.secondaryLabel)
                    Spacer(minLength: 0)
                }
            }

            Section("Meaningful distractions") {
                Stepper("\(distractions)", value: $distractions, in: 0...20)
                    .accessibilityIdentifier("reflection.distractions")
            }

            Section("Anything worth noting?") {
                // See the note in StartSessionView: a Form row's first string
                // is its label, not its placeholder.
                TextField(text: $note, prompt: Text("Optional"), axis: .vertical) {
                    Text("Note")
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reflection.note")
                .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .frame(height: min(showsLog ? 500 : 340, max(240, (NSScreen.main?.visibleFrame.height ?? 800) - 200)))
    }

    /// First, because it is the part you will read again: where you stopped
    /// and what is next. Saved by either button, so skipping the ratings never
    /// throws away the handoff.
    private var logSection: some View {
        Section {
            LogTabPicker(selection: $logDraft.tabID, identifier: "reflection.logTab")
            if let tab = LogBook.activeTab(id: logDraft.tabID, in: logTabs),
               let last = LogBook.latestResumePoint(for: tab) {
                Text("Last time: \(last.resumePoint)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .lineLimit(2)
            }
            LogEntryFields(
                resumePoint: $logDraft.resumePoint,
                done: $logDraft.done,
                focusOnAppear: logDraft.tabID != nil,
                onSubmit: submitReview,
                identifier: "reflection.log"
            )
            .disabled(logDraft.tabID == nil && !logDraft.hasText)
            if let tab = LogBook.activeTab(id: logDraft.tabID, in: logTabs) {
                RelatedNotesPicker(tab: tab, selection: $logDraft.noteIDs)
            }
            if let logError {
                Label(logError, systemImage: "exclamationmark.triangle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Where did you leave off?")
        } footer: {
            if logDraft.tabID == nil {
                Text("Choose a Log tab to write a handoff, or leave it and nothing is logged.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.tertiaryLabel)
            }
        }
    }

    /// Writes the handoff, if there is one. False when it could not be saved,
    /// so the sheet stays open with the text still in it.
    private func saveLog() -> Bool {
        guard showsLog || logDraft.hasText else { return true }
        do {
            let entry = try model.saveLogDraft(logDraft, session: session)
            guard !logDraft.hasText || entry != nil else {
                logError = "Choose an active tab or clear the text before continuing. Your text has been kept."
                return false
            }
            // The handoff is already on disk. A retry after the review fails
            // to save must not create a second copy of it.
            logDraft.clearText()
            return true
        } catch {
            logError = "Not saved: \(error.localizedDescription)"
            return false
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                guard saveLog() else { return }
                session.reflectionState = .skipped
                save()
            }
            .accessibilityIdentifier("reflection.skip")
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save", action: submitReview)
            .accessibilityIdentifier("reflection.save")
            .keyboardShortcut(.defaultAction)
        }
        .padding(Theme.Space.l)
    }

    /// Takes what has been typed, without fighting the typist: an empty field
    /// is "not set" rather than zero, and anything that is not a number leaves
    /// the last good value alone instead of snapping to it mid-keystroke.
    private func commitHonestMinutes(_ text: String) {
        let digits = text.filter(\.isNumber)
        if digits != text { honestDraft = digits; return }
        guard let value = Int(digits) else { honestMinutes = nil; return }
        let clamped = min(max(value, 0), maximumMinutes)
        honestMinutes = clamped
        if clamped != value { honestDraft = "\(clamped)" }
    }

    private func setHonestMinutes(_ value: Int) {
        let clamped = min(max(value, 0), maximumMinutes)
        honestMinutes = clamped
        honestDraft = "\(clamped)"
    }

    private func save() {
        do {
            try modelContext.save()
            dismiss()
        } catch {
            logError = "Review not saved: \(error.localizedDescription)"
        }
    }

    private func submitReview() {
        guard saveLog() else { return }
        session.focusRating = focus
        session.honestWorkMinutes = honestMinutes ?? maximumMinutes
        session.distractions = distractions
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        session.reflection = trimmed.isEmpty ? nil : trimmed
        session.reflectionState = .completed
        save()
    }
}
