import SwiftUI
import SwiftData

/// The post-session honest review.
struct ReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: WorkSession
    /// True when Span ended the session because it was left running, so the
    /// sheet can account for a session the user never finished themselves.
    var endedAutomatically = false

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

    private var maximumMinutes: Int { max(1, Int(session.elapsed() / 60)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            form
            Divider()
            footer
        }
        .frame(width: 420)
        // No silent third exit: the sheet is dismissed by Save or by Skip, both
        // of which record what happened.
        .interactiveDismissDisabled()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("How did it go?")
                .font(.system(size: 15, weight: .semibold))
            Text("Be kind and honest — this is for you, not a scorecard.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.secondaryLabel)
            if endedAutomatically {
                Label("Finished for you at \(Format.timeOfDay(session.endedAt ?? .now)), where you stopped — it was left running.",
                      systemImage: "moon.zzz")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.secondaryLabel)
                    .accessibilityIdentifier("reflection.autoFinished")
            }
        }
        .padding(Theme.Space.l)
    }

    private var form: some View {
        Form {
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
                .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .frame(height: 340)
    }

    private var footer: some View {
        HStack {
            Button("Skip for now") {
                session.reflectionState = .skipped
                save()
            }
            .accessibilityIdentifier("reflection.skip")
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") {
                session.focusRating = focus
                session.honestWorkMinutes = honestMinutes ?? maximumMinutes
                session.distractions = distractions
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                session.reflection = trimmed.isEmpty ? nil : trimmed
                session.reflectionState = .completed
                save()
            }
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
        try? modelContext.save()
        dismiss()
    }
}
