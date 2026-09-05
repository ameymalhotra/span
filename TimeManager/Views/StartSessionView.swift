import SwiftData
import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss

    /// Categories already used, newest first, so the free-text field gains the
    /// convenience of a picker without the model needing a category entity.
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]

    @AppStorage("personalNote") private var personalNote = ""
    @State private var title = ""
    @State private var category = "Deep Work"
    @AppStorage("defaultSessionMinutes") private var minutes = 60

    let onStart: (String, String, Int) -> Void

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var knownCategories: [String] {
        var seen: [String] = []
        for session in sessions {
            let name = session.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !seen.contains(name) else { continue }
            seen.append(name)
            if seen.count == 8 { break }
        }
        return seen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("New session")
                    .font(.system(size: 15, weight: .semibold))
                if !personalNote.isEmpty {
                    Text(personalNote)
                        .font(Theme.Font.caption)
                        .italic()
                        .foregroundStyle(Theme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.l)

            Divider()

            Form {
                Section("What are you working on?") {
                    // `prompt`, not the label: inside a grouped Form the
                    // first string is the row's *label*, which macOS lays out
                    // on the left and pushes the field itself to the trailing
                    // edge — leaving the caret parked at the far right of the
                    // row while the example text sat where a placeholder looks
                    // like it should be.
                    TextField(text: $title, prompt: Text("e.g. Rebuild the timeline")) {
                        Text("Session title")
                    }
                    .labelsHidden()
                    CategoryPicker(selection: $category)
                    HStack(spacing: Theme.Space.xs) {
                        Circle()
                            .fill(CategoryPalette.color(for: category))
                            .frame(width: 8, height: 8)
                        Text("This category's colour on the timeline")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                }

                Section("How long?") {
                    DurationPicker(minutes: $minutes)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") {
                    onStart(trimmedTitle, category.trimmingCharacters(in: .whitespacesAndNewlines), minutes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
            }
            .padding(Theme.Space.l)
        }
        .frame(width: 420)
    }
}
