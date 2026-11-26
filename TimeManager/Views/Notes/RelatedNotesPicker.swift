import SwiftData
import SwiftUI

/// Only project notes are offered. Linking never copies a note's contents
/// into an entry: its title opens the same living document later.
struct RelatedNotesPicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    let tab: LogTab
    @Binding var selection: Set<UUID>
    @State private var expanded = false
    @State private var error: String?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !tab.notes.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(NoteBook.ordered(tab.notes)) { note in
                                HStack {
                                    Toggle(note.displayTitle, isOn: Binding(
                                        get: { selection.contains(note.id) },
                                        set: { if $0 { selection.insert(note.id) } else { selection.remove(note.id) } }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .lineLimit(1)
                                    Button { openWindow(value: note.id) } label: { Image(systemName: "arrow.up.forward.square") }
                                        .buttonStyle(.borderless).help("Open Note")
                                }
                            }
                        }
                    }
                    .frame(height: min(140, CGFloat(tab.notes.count) * 28))
                }
                Button("Create Linked Note…") {
                    do {
                        let note = try NoteBook.create(in: tab, context: context)
                        selection.insert(note.id)
                        openWindow(value: note.id)
                    } catch { self.error = error.localizedDescription }
                }.disabled(tab.isArchived)
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }.padding(.top, 8)
        } label: {
            Text(selection.isEmpty ? "Related notes" : "Related notes (\(selection.count))")
                .font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("notes.related")
    }
}

struct RelatedNoteLinks: View {
    @Environment(\.openWindow) private var openWindow
    let notes: [ProjectNote]
    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(NoteBook.ordered(notes)) { note in
                    Button { openWindow(value: note.id) } label: {
                        Label(note.displayTitle, systemImage: "note.text")
                    }
                    .buttonStyle(.link).font(.callout)
                    .accessibilityIdentifier("notes.entryLink")
                }
            }
        }
    }
}
