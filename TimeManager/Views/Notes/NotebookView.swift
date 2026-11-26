import AppKit
import SwiftData
import SwiftUI

struct NotebookView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    let tab: LogTab
    @State private var selectedID: UUID?
    @State private var query = ""
    @State private var error: String?
    @FocusState private var searching: Bool

    private var notes: [ProjectNote] { NoteBook.ordered(tab.notes, matching: query) }
    private var selected: ProjectNote? { tab.notes.first { $0.id == selectedID } }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search notes", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($searching)
                        .accessibilityIdentifier("notes.search")
                    Button(action: create) { Image(systemName: "square.and.pencil") }
                        .help("New Note (⌘N)")
                        .keyboardShortcut("n")
                        .disabled(tab.isArchived)
                        .accessibilityLabel("New Note")
                        .accessibilityIdentifier("notes.new")
                }
                .padding(12)
                Divider()
                ScrollViewReader { reader in
                    List(selection: $selectedID) {
                        ForEach(notes) { note in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(note.displayTitle).fontWeight(.medium).lineLimit(1)
                                    if note.isPinned { Image(systemName: "pin.fill").font(.caption2) }
                                }
                                Text(note.plainText.isEmpty ? "No text yet" : note.plainText)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(note.editedAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 5)
                            .tag(note.id)
                            .id(note.id)
                            .accessibilityIdentifier("notes.row")
                        }
                    }
                    .overlay {
                        if notes.isEmpty {
                            ContentUnavailableView(query.isEmpty ? "Your project notebook" : "No matching notes",
                                                   systemImage: "note.text",
                                                   description: Text(query.isEmpty ? "Keep ideas and reference material here." : "Try another word."))
                        }
                    }
                    .onChange(of: selectedID) { _, id in
                        if let id { reader.scrollTo(id, anchor: .top) }
                    }
                }
                Button("Find Notes") { searching = true }
                    .keyboardShortcut("f").hidden().frame(height: 0)
            }
            .frame(minWidth: 190, idealWidth: 230, maxWidth: 300)
            Group {
                if let selected {
                    ProjectNoteEditor(note: selected)
                        .id(selected.id)
                } else {
                    ContentUnavailableView {
                        Label("Choose a note", systemImage: "note.text")
                    } description: {
                        Text("Write here or open a note in its own window while you work.")
                    } actions: {
                        if !tab.isArchived { Button("New Note", action: create) }
                    }
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            let remembered = model.notebooks.selectedNotes[tab.id]
            selectedID = tab.notes.first(where: { $0.id == remembered })?.id ?? notes.first?.id
        }
        .onChange(of: selectedID) { _, id in model.notebooks.selectedNotes[tab.id] = id }
        .onChange(of: tab.notes.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = notes.first?.id }
        }
        .alert("Couldn’t create note", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func create() {
        do {
            query = ""
            selectedID = try NoteBook.create(in: tab, context: context).id
        } catch { self.error = error.localizedDescription }
    }
}

struct ProjectNoteEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model
    let note: ProjectNote
    var isSeparateWindow = false
    @State private var formatting = NoteFormatting()
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var addingLink = false
    @State private var link = "https://"
    @State private var keepOnTop = false
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var readOnly: Bool { note.tab == nil || note.tab?.isArchived == true }

    var body: some View {
        let document = model.notebooks.document(for: note)
        VStack(spacing: 0) {
            HStack {
                Text(note.tab?.name ?? "Project unavailable").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if readOnly { Text("Archived · Read only").font(.caption).foregroundStyle(.secondary) }
                else {
                    Text(document.error != nil ? "Not saved" : document.isDirty ? "Saving…" : "Saved")
                        .font(.caption).foregroundStyle(document.error != nil ? .orange : .secondary)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(document.error != nil ? "Not saved" : document.isDirty ? "Saving" : "Saved")
                        .accessibilityIdentifier("notes.status")
                }
                if !isSeparateWindow {
                    Button { openWindow(value: note.id) } label: { Image(systemName: "arrow.up.forward.square") }
                        .help("Open in Separate Window")
                        .accessibilityLabel("Open in Separate Window")
                        .accessibilityIdentifier("notes.openWindow")
                }
                Menu {
                    Button(note.isPinned ? "Unpin" : "Pin") { perform { try NoteBook.pin(note, in: context) } }
                        .disabled(readOnly)
                    Button("Copy as Text") { copy(document) }
                    if isSeparateWindow { Toggle("Keep on Top", isOn: $keepOnTop) }
                    Divider()
                    Button("Delete Note…", role: .destructive) { confirmingDelete = true }.disabled(readOnly)
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Note actions")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            TextField("Untitled note", text: Binding(get: { document.title }, set: {
                document.title = $0
                model.notebooks.changed(document)
            }))
            .textFieldStyle(.plain).font(.system(size: 24, weight: .semibold))
            .padding(.horizontal, 24).padding(.vertical, 12)
            .disabled(readOnly).focused($titleFocused).accessibilityIdentifier("notes.title")
            HStack(spacing: 14) {
                Button(action: formatting.bold) { Image(systemName: "bold") }.keyboardShortcut("b").help("Bold (⌘B)")
                Button(action: formatting.italic) { Image(systemName: "italic") }.keyboardShortcut("i").help("Italic (⌘I)")
                Menu("Style") {
                    Button("Heading") { formatting.heading(true) }
                    Button("Body") { formatting.heading(false) }
                }.fixedSize()
                Menu { Button("Bulleted List") { formatting.list(numbered: false) }
                    Button("Numbered List") { formatting.list(numbered: true) }
                } label: { Image(systemName: "list.bullet") }.fixedSize()
                Button(action: formatting.checklist) { Image(systemName: "checklist") }.help("Add or toggle checklist item")
                Button { addingLink = true } label: { Image(systemName: "link") }.help("Add Link")
                Spacer()
                Button("Save") { perform { try model.notebooks.flush(note.id) } }
                    .keyboardShortcut("s").disabled(!document.isDirty)
            }
            .buttonStyle(.borderless).padding(.horizontal, 24).padding(.vertical, 8)
            .disabled(readOnly)
            Divider()
            if let message = document.error {
                HStack {
                    Text(message).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { perform { try model.notebooks.flush(note.id) } }
                    Button("Copy Text") { copy(document) }
                }.padding(12).background(.orange.opacity(0.1))
            }
            RichNoteEditor(document: document, editing: model.notebooks,
                           formatting: formatting, isEditable: !readOnly)
        }
        .background(Theme.canvas)
        .background {
            if isSeparateWindow {
                NoteWindowGuard(keepOnTop: keepOnTop, editing: model.notebooks, noteID: note.id)
            }
        }
        .onAppear { titleFocused = document.title.isEmpty && document.plainText.isEmpty }
        .onDisappear { try? model.notebooks.flush(note.id) }
        .confirmationDialog("Delete “\(note.displayTitle)”?", isPresented: $confirmingDelete) {
            Button("Delete Note", role: .destructive) {
                perform {
                    let id = note.id
                    try NoteBook.delete(note, in: context)
                    model.notebooks.forget(id)
                    if isSeparateWindow { dismiss() }
                }
            }
        } message: { Text("This removes the note and its links from log entries. This cannot be undone.") }
        .alert("Couldn’t update note", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .sheet(isPresented: $addingLink) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add Link").font(.headline)
                TextField("URL", text: $link).frame(width: 320)
                HStack {
                    Spacer()
                    Button("Cancel") { addingLink = false }.keyboardShortcut(.cancelAction)
                    Button("Add") {
                        if let url = URL(string: link), ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                            formatting.link(url)
                            addingLink = false
                        }
                    }.keyboardShortcut(.defaultAction)
                    .disabled(!validLink)
                }
            }.padding(20)
        }
    }

    private var validLink: Bool {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "mailto"].contains(scheme) && link.count > scheme.count + 3
    }

    private func copy(_ document: NoteDocument) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.title + "\n\n" + document.plainText, forType: .string)
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
}

/// A value scene gives each note a stable window identity, so opening an
/// already-open note focuses it instead of making a second copy.
struct ProjectNoteWindow: View {
    @Query private var notes: [ProjectNote]
    let id: UUID

    init(id: UUID) {
        self.id = id
        _notes = Query(filter: #Predicate<ProjectNote> { $0.id == id })
    }

    var body: some View {
        Group {
            if let note = notes.first {
                ProjectNoteEditor(note: note, isSeparateWindow: true)
                    .navigationTitle(note.displayTitle)
            } else {
                ContentUnavailableView("Note unavailable", systemImage: "note.text",
                                       description: Text("It may have been deleted along with its project."))
            }
        }
        .frame(minWidth: 440, minHeight: 320)
    }
}
