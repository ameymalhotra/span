import AppKit
import SwiftData

/// Persistence and ordering rules shared by every notebook window.
@MainActor
enum NoteBook {
    enum WriteError: LocalizedError {
        case readOnly, unavailable, archived
        var errorDescription: String? {
            switch self {
            case .readOnly: "This notebook is read-only. Your text has been kept."
            case .unavailable: "This note's project is no longer available."
            case .archived: "Unarchive this project before changing its notes."
            }
        }
    }

    static func requireWritable(_ tab: LogTab?, in context: ModelContext) throws {
        guard context.container.configurations.allSatisfy(\.allowsSave) else { throw WriteError.readOnly }
        guard let tab, !tab.isDeleted, tab.modelContext != nil else { throw WriteError.unavailable }
        guard !tab.isArchived else { throw WriteError.archived }
    }

    static func persist(in context: ModelContext) throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    static func create(in tab: LogTab, context: ModelContext) throws -> ProjectNote {
        try requireWritable(tab, in: context)
        let note = ProjectNote(tab: tab)
        context.insert(note)
        tab.notes.append(note)
        try persist(in: context)
        return note
    }

    static func save(_ note: ProjectNote, title: String, richText: Data, plainText: String,
                     in context: ModelContext, at date: Date = .now) throws {
        try requireWritable(note.tab, in: context)
        note.title = LogBook.clean(title)
        note.richText = richText
        note.plainText = plainText
        note.editedAt = date
        try persist(in: context)
    }

    static func pin(_ note: ProjectNote, in context: ModelContext) throws {
        try requireWritable(note.tab, in: context)
        note.isPinned.toggle()
        try persist(in: context)
    }

    static func delete(_ note: ProjectNote, in context: ModelContext) throws {
        try requireWritable(note.tab, in: context)
        note.tab?.notes.removeAll { $0.id == note.id }
        context.delete(note)
        try persist(in: context)
    }

    static func ordered(_ notes: [ProjectNote], matching query: String = "") -> [ProjectNote] {
        let query = LogBook.clean(query)
        return notes.filter {
            query.isEmpty || $0.title.localizedStandardContains(query) || $0.plainText.localizedStandardContains(query)
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            if $0.editedAt != $1.editedAt { return $0.editedAt > $1.editedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func attributedText(_ data: Data) -> NSAttributedString {
        (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf],
                                 documentAttributes: nil)) ?? NSAttributedString(string: "")
    }

    static func encode(_ text: NSAttributedString) throws -> Data {
        try text.data(from: NSRange(location: 0, length: text.length),
                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }
}
