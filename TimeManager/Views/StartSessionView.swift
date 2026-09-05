import SwiftData
import SwiftUI

struct StartSessionView: View {
    @Environment(\.dismiss) private var dismiss

    /// Categories already used, newest first, so the free-text field gains the
    /// convenience of a picker without the model needing a category entity.
    @Query(sort: \WorkSession.startedAt, order: .reverse) private var sessions: [WorkSession]

    @State private var title = ""
    @State private var category = "Deep Work"
    @State private var minutes = 50

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
            Text("New session")
                .font(.system(size: 15, weight: .semibold))
                .padding(Theme.Space.l)

            Divider()

            Form {
                Section("What are you working on?") {
                    TextField("e.g. Rebuild the timeline", text: $title)
                    HStack(spacing: Theme.Space.s) {
                        TextField("Category", text: $category)
                        if !knownCategories.isEmpty {
                            Menu {
                                ForEach(knownCategories, id: \.self) { name in
                                    Button(name) { category = name }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .frame(width: 20)
                        }
                    }
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
                    Picker("Duration", selection: $minutes) {
                        ForEach([25, 50, 75, 90], id: \.self) { value in
                            Text("\(value)m").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
