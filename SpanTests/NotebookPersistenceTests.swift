import AppKit
import SwiftData
import Testing
@testable import Span

@MainActor
@Suite("Notebook persistence", .serialized)
struct NotebookPersistenceTests {
    @Test("formatted notes and entry links survive reopening the store")
    func roundTrip() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Notebook.store")
            do {
                let container = try TestStore.onDisk(at: url)
                let context = container.mainContext
                let tab = try #require(try LogBook.createTab(name: "Research", in: context))
                tab.showsNotes = true
                let note = try NoteBook.create(in: tab, context: context)
                let text = NSAttributedString(string: "☑ Read paper", attributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
                try NoteBook.save(note, title: "Sources", richText: NoteBook.encode(text), plainText: text.string, in: context)
                try NoteBook.pin(note, in: context)
                _ = try LogBook.addEntry(to: tab, resumePoint: "Compare results", done: "", noteIDs: [note.id], in: context)
            }
            let container = try TestStore.onDisk(at: url)
            let context = container.mainContext
            let tab = try #require(try context.fetch(FetchDescriptor<LogTab>()).first)
            let note = try #require(tab.notes.first)
            #expect(tab.showsNotes)
            #expect(note.title == "Sources")
            #expect(note.isPinned)
            #expect(note.plainText == "☑ Read paper")
            #expect(NoteBook.attributedText(note.richText).string == note.plainText)
            #expect(tab.entries.first?.notes.first?.id == note.id)
            #expect(note.entries.first?.resumePoint == "Compare results")
        }
    }

    @Test("a released 1.9 store migrates without losing session history or log entries")
    func migrationFrom19() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("BeforeNotes.store")
            do {
                let schema = Schema([WorkSession.self, SessionSegment.self, ActivityRecord.self,
                    TimeEntry.self, BreakRecord.self, TimeCategory.self, AppCategoryRule.self,
                    PreNotebookSchema.LogTab.self, PreNotebookSchema.LogEntry.self])
                let container = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
                let context = container.mainContext
                let tab = PreNotebookSchema.LogTab(name: "Research", group: "Work", colorSlot: 2)
                let entry = PreNotebookSchema.LogEntry(tab: tab, recordedAt: Clock.reference,
                                                       resumePoint: "Continue paper", done: "Read abstract")
                context.insert(tab)
                context.insert(entry)
                tab.entries.append(entry)
                let session = WorkSession(title: "Reading", category: "Work", plannedMinutes: 25)
                session.startedAt = Clock.reference
                session.logTabID = tab.id
                session.endedAt = Clock.reference.addingTimeInterval(60)
                entry.sessionID = session.id
                entry.sessionTitle = session.title
                entry.workedSeconds = 60
                context.insert(session)
                try context.save()
            }
            let container = try TestStore.onDisk(at: url)
            let context = container.mainContext
            let tab = try #require(try context.fetch(FetchDescriptor<LogTab>()).first)
            let entry = try #require(tab.entries.first)
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            #expect(tab.name == "Research")
            #expect(tab.group == "Work")
            #expect(entry.resumePoint == "Continue paper")
            #expect(entry.done == "Read abstract")
            #expect(entry.workedSeconds == 60)
            #expect(entry.sessionID == sessions.first?.id)
            #expect(sessions.first?.logTabID == tab.id)
            #expect(tab.notes.isEmpty)
            #expect(entry.notes.isEmpty)
            #expect(!tab.showsNotes)
            let note = try NoteBook.create(in: tab, context: context)
            try NoteBook.save(note, title: "New notebook", richText: Data(), plainText: "", in: context)
            #expect(tab.entries.count == 1)
        }
    }

    @Test("read-only stores reject notebook changes before mutating persistent objects")
    func readOnlyFailureRetainsBuffer() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("ReadOnly.store")
            do {
                let container = try TestStore.onDisk(at: url)
                let context = container.mainContext
                let tab = try #require(try LogBook.createTab(name: "Research", in: context))
                _ = try NoteBook.create(in: tab, context: context)
            }
            let container = try ModelContainer(for: ModelStack.schema,
                configurations: ModelConfiguration(url: url, allowsSave: false))
            let context = container.mainContext
            let tab = try #require(try context.fetch(FetchDescriptor<LogTab>()).first)
            let note = try #require(tab.notes.first)
            let editor = NoteEditingCoordinator(context: context)
            let draft = editor.document(for: note)
            draft.title = "Unsaved text"
            editor.changed(draft)
            #expect(throws: NoteBook.WriteError.self) { try editor.flushAll() }
            #expect(draft.title == "Unsaved text")
            #expect(draft.isDirty)
            #expect(draft.error != nil)
            #expect(note.title.isEmpty)
            #expect(throws: NoteBook.WriteError.self) { try NoteBook.create(in: tab, context: context) }
            #expect(throws: NoteBook.WriteError.self) { try NoteBook.delete(note, in: context) }
            #expect(tab.notes.count == 1)
            editor.reset()
        }
    }
}
