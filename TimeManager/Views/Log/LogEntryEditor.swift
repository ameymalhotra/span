import SwiftData
import SwiftUI

/// Edits one entry: its text, when it was written, and which tab it is in.
///
/// The date is editable so entries carried over from the old Google Doc keep
/// the day they were written rather than the day they were typed in again.
struct LogEntryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LogTab.sortIndex) private var tabs: [LogTab]

    let entry: LogEntry

    @State private var resumePoint = ""
    @State private var done = ""
    @State private var noteIDs: Set<UUID> = []
    @State private var recordedAt = Date.now
    @State private var tabID: UUID?
    @State private var confirmingDelete = false
    @State private var saveError: String?

    /// Active tabs, plus the entry's own tab even when it is archived — an
    /// entry must be able to stay where it is.
    private var choices: [LogTab] {
        tabs.filter { !$0.isArchived || $0.id == entry.tab?.id }
    }

    private var canSave: Bool {
        !LogBook.clean(resumePoint).isEmpty || !LogBook.clean(done).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit entry")
                .font(.system(size: 15, weight: .semibold))
                .padding(Theme.Space.l)

            Divider()

            VStack(alignment: .leading, spacing: Theme.Space.l) {
                HStack(spacing: Theme.Space.m) {
                    DatePicker("Written", selection: $recordedAt,
                               displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("log.editor.date")
                    Spacer()
                    Picker("Tab", selection: $tabID) {
                        ForEach(choices) { tab in
                            Text(tab.name).tag(UUID?.some(tab.id))
                        }
                    }
                    .accessibilityIdentifier("log.editor.tab")
                    .frame(maxWidth: 200)
                }
                LogEntryFields(resumePoint: $resumePoint, done: $done, onSubmit: save,
                               identifier: "log.editor")
                if let tab = choices.first(where: { $0.id == tabID }) {
                    RelatedNotesPicker(tab: tab, selection: $noteIDs)
                }
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle")
                        .font(Theme.Font.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(Theme.Space.l)

            Divider()

            HStack {
                Button("Delete…", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("log.editor.delete")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .accessibilityIdentifier("log.editor.save")
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(Theme.Space.l)
        }
        .frame(width: 480)
        .onAppear {
            resumePoint = entry.resumePoint
            done = entry.done
            recordedAt = entry.recordedAt
            tabID = entry.tab?.id
            noteIDs = Set(entry.notes.map(\.id))
        }
        .confirmationDialog("Delete this entry?", isPresented: $confirmingDelete) {
            Button("Delete Entry", role: .destructive) {
                do {
                    try LogBook.delete(entry, in: context)
                    dismiss()
                } catch {
                    saveError = "Not deleted: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            let target = tabs.first { $0.id == tabID }
            try LogBook.update(entry, resumePoint: resumePoint, done: done,
                               recordedAt: recordedAt, tab: target, noteIDs: noteIDs, in: context)
            dismiss()
        } catch {
            saveError = "Not saved: \(error.localizedDescription)"
        }
    }
}
