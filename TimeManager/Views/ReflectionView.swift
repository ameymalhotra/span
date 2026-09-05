import SwiftUI
import SwiftData

/// The post-session honest review.
struct ReflectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: WorkSession

    @State private var focus = 3
    /// Starts unset rather than pre-filled. Defaulting this to the full elapsed
    /// time anchors the user on the flattering answer before they have thought
    /// about it, which is the opposite of what an honest review is for.
    @State private var honestMinutes: Int?
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
                HStack {
                    Stepper(
                        value: Binding(
                            get: { honestMinutes ?? maximumMinutes },
                            set: { honestMinutes = $0 }
                        ),
                        in: 0...maximumMinutes
                    ) {
                        Text(honestMinutes.map { "\($0) of \(maximumMinutes) minutes" }
                             ?? "Not set")
                            .foregroundStyle(honestMinutes == nil ? Theme.tertiaryLabel : Theme.label)
                    }
                    .accessibilityIdentifier("reflection.honestMinutes")
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

    private func save() {
        try? modelContext.save()
        dismiss()
    }
}
