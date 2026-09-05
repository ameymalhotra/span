import SwiftData
import SwiftUI

/// Editor for a hand-made time block: what it was, and exactly when.
struct TimeEntryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var entry: TimeEntry
    /// Categories already in use, so the field behaves like a picker without
    /// the model needing a category entity.
    let knownCategories: [String]

    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            TextField("What was this?", text: $entry.title)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($titleFocused)
                .onSubmit { commit() }

            HStack(spacing: Theme.Space.s) {
                Circle()
                    .fill(CategoryPalette.color(for: entry.category))
                    .frame(width: 8, height: 8)
                TextField("Category", text: $entry.category)
                    .textFieldStyle(.roundedBorder)
                if !knownCategories.isEmpty {
                    Menu {
                        ForEach(knownCategories, id: \.self) { name in
                            Button(name) { entry.category = name }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 18)
                }
            }

            Divider()

            // Exact times, so a block is never stuck at whatever the drag
            // happened to land on.
            DatePicker("Starts", selection: $entry.startedAt, displayedComponents: [.hourAndMinute])
            DatePicker("Ends", selection: $entry.endedAt, displayedComponents: [.hourAndMinute])
            HStack {
                Text("Duration")
                Spacer()
                Text(Format.compact(entry.duration))
                    .foregroundStyle(Theme.secondaryLabel)
                    .monospacedDigit()
            }
            .font(Theme.Font.body)

            Divider()

            HStack {
                Button(role: .destructive) {
                    context.delete(entry)
                    try? context.save()
                    dismiss()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button("Done") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(Theme.Font.body)
        .padding(Theme.Space.l)
        .frame(width: 300)
        .onAppear { titleFocused = true }
        .onChange(of: entry.startedAt) { _, _ in clampEnd() }
    }

    /// An end before its start would render as a zero-height block that can
    /// never be grabbed again.
    private func clampEnd() {
        if entry.endedAt <= entry.startedAt {
            entry.endedAt = entry.startedAt.addingTimeInterval(15 * 60)
        }
    }

    private func commit() {
        clampEnd()
        if entry.title.trimmingCharacters(in: .whitespaces).isEmpty {
            entry.title = "Untitled block"
        }
        try? context.save()
        dismiss()
    }
}
