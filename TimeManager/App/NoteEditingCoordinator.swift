import AppKit
import Observation
import SwiftData

/// Buffers live outside the views. Switching projects or closing a window must
/// not discard text after a failed disk write. All windows edit the same buffer.
@MainActor
@Observable
final class NoteDocument {
    let id: UUID
    var title: String
    var richText: Data
    var plainText: String
    var isDirty = false
    var error: String?
    var selection = NSRange(location: 0, length: 0)
    var scrollOffset: CGFloat = 0

    init(_ note: ProjectNote) {
        id = note.id
        title = note.title
        richText = note.richText
        plainText = note.plainText
    }
}

@MainActor
@Observable
final class NoteEditingCoordinator {
    private(set) var documents: [UUID: NoteDocument] = [:]
    var selectedNotes: [UUID: UUID] = [:]
    private let context: ModelContext
    @ObservationIgnored private var pending: [UUID: Task<Void, Never>] = [:]

    init(context: ModelContext) { self.context = context }

    func document(for note: ProjectNote) -> NoteDocument {
        if let existing = documents[note.id] { return existing }
        let document = NoteDocument(note)
        documents[note.id] = document
        return document
    }

    func changed(_ document: NoteDocument) {
        document.isDirty = true
        document.error = nil
        pending[document.id]?.cancel()
        pending[document.id] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(450)) }
            catch { return }
            guard let self else { return }
            try? self.flush(document.id)
        }
    }

    func flush(_ id: UUID) throws {
        pending.removeValue(forKey: id)?.cancel()
        guard let document = documents[id], document.isDirty else { return }
        do {
            let notes = try context.fetch(FetchDescriptor<ProjectNote>())
            guard let note = notes.first(where: { $0.id == id && !$0.isDeleted }) else {
                throw NoteBook.WriteError.unavailable
            }
            try NoteBook.save(note, title: document.title, richText: document.richText,
                              plainText: document.plainText, in: context)
            document.isDirty = false
            document.error = nil
        } catch {
            document.error = error.localizedDescription
            throw error
        }
    }

    func flushAll() throws {
        var failure: Error?
        for id in Array(documents.keys) {
            do { try flush(id) } catch { failure = error }
        }
        if let failure { throw failure }
    }

    func forget(_ id: UUID) {
        pending.removeValue(forKey: id)?.cancel()
        documents.removeValue(forKey: id)
        selectedNotes = selectedNotes.filter { $0.value != id }
    }

    func reset() {
        for task in pending.values { task.cancel() }
        pending.removeAll()
        documents.removeAll()
        selectedNotes.removeAll()
    }
}
