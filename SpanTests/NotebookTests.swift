import AppKit
import SwiftData
import Testing
@testable import Span

@MainActor
@Suite("Project notebooks", .serialized)
struct NotebookTests {
    private func project(_ context: ModelContext, _ name: String = "Research") throws -> LogTab {
        try #require(try LogBook.createTab(name: name, in: context))
    }

    @Test("notes are project documents and may start empty")
    func createNote() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        #expect(note.tab?.id == tab.id)
        #expect(tab.notes.map(\.id) == [note.id])
        #expect(note.displayTitle == "Untitled note")
        #expect(note.entries.isEmpty)
    }

    @Test("rich text, headings, links, lists and checkboxes survive encoding")
    func richTextRoundTrip() throws {
        let text = NSMutableAttributedString(string: "Research\n☑ Read paper\nSource\nItem")
        text.addAttribute(.font, value: NSFont.systemFont(ofSize: 20, weight: .bold), range: NSRange(location: 0, length: 8))
        let url = try #require(URL(string: "https://example.com/paper"))
        text.addAttribute(.link, value: url, range: NSRange(location: 22, length: 6))
        let style = NSMutableParagraphStyle()
        style.textLists = [NSTextList(markerFormat: .decimal, options: 0)]
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 29, length: 4))
        let restored = NoteBook.attributedText(try NoteBook.encode(text))
        #expect(restored.string == text.string)
        let font = try #require(restored.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 20)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        #expect(restored.attribute(.link, at: 22, effectiveRange: nil) != nil)
        let paragraph = try #require(restored.attribute(.paragraphStyle, at: 29, effectiveRange: nil) as? NSParagraphStyle)
        #expect(!paragraph.textLists.isEmpty)
    }

    @Test("pinned notes precede newest edits, and search includes contents")
    func orderingAndSearch() throws {
        let container = try TestStore.inMemory()
        let tab = try project(container.mainContext)
        let a = try NoteBook.create(in: tab, context: container.mainContext)
        let b = try NoteBook.create(in: tab, context: container.mainContext)
        a.title = "Paper ideas"
        a.plainText = "Vector databases"
        a.isPinned = true
        a.editedAt = Clock.reference
        b.title = "Course notes"
        b.editedAt = Clock.reference.addingTimeInterval(60)
        #expect(NoteBook.ordered(tab.notes).map(\.id) == [a.id, b.id])
        #expect(NoteBook.ordered(tab.notes, matching: "VECTOR").map(\.id) == [a.id])
        #expect(NoteBook.ordered(tab.notes, matching: "course").map(\.id) == [b.id])
        #expect(NoteBook.ordered(tab.notes, matching: "absent").isEmpty)
    }

    @Test("every editor gets the same draft and flushing writes the latest text")
    func sharedDraft() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let note = try NoteBook.create(in: project(context), context: context)
        let editor = NoteEditingCoordinator(context: context)
        let first = editor.document(for: note)
        let second = editor.document(for: note)
        #expect(first === second)
        first.title = "My notes"
        first.plainText = "First"
        editor.changed(first)
        second.plainText = "Latest"
        second.richText = try NoteBook.encode(NSAttributedString(string: "Latest"))
        editor.changed(second)
        try editor.flush(note.id)
        #expect(note.title == "My notes")
        #expect(note.plainText == "Latest")
        #expect(!first.isDirty)
        #expect(first.error == nil)
    }

    @Test("autosave commits after typing stops")
    func autosave() async throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let note = try NoteBook.create(in: project(context), context: context)
        let editor = NoteEditingCoordinator(context: context)
        let draft = editor.document(for: note)
        draft.title = "Autosaved"
        editor.changed(draft)
        try await Task.sleep(for: .milliseconds(800))
        #expect(note.title == "Autosaved")
        #expect(!draft.isDirty)
    }

    @Test("a failed write keeps the draft for retry after unarchiving")
    func failureRetainsDraft() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        let editor = NoteEditingCoordinator(context: context)
        let draft = editor.document(for: note)
        draft.title = "Keep me"
        editor.changed(draft)
        try LogBook.setArchived(tab, true, in: context)
        #expect(throws: NoteBook.WriteError.self) { try editor.flush(note.id) }
        #expect(draft.title == "Keep me")
        #expect(draft.isDirty)
        #expect(draft.error != nil)
        #expect(note.title.isEmpty)
        try LogBook.setArchived(tab, false, in: context)
        try editor.flush(note.id)
        #expect(note.title == "Keep me")
    }

    @Test("archived notebooks reject creating, pinning and deleting")
    func archiveReadOnly() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        try LogBook.setArchived(tab, true, in: context)
        #expect(throws: NoteBook.WriteError.self) { try NoteBook.create(in: tab, context: context) }
        #expect(throws: NoteBook.WriteError.self) { try NoteBook.pin(note, in: context) }
        #expect(throws: NoteBook.WriteError.self) { try NoteBook.delete(note, in: context) }
        #expect(tab.notes.count == 1)
    }

    @Test("entry links accept only notes from that project")
    func linkedNotes() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let a = try project(context)
        let b = try project(context, "Course")
        let own = try NoteBook.create(in: a, context: context)
        let other = try NoteBook.create(in: b, context: context)
        let entry = try #require(try LogBook.save(LogDraft(tabID: a.id, resumePoint: "Continue", noteIDs: [own.id, other.id]), in: context))
        #expect(entry.notes.map(\.id) == [own.id])
        #expect(own.entries.map(\.id) == [entry.id])
        #expect(other.entries.isEmpty)
    }

    @Test("a note alone cannot create an empty log entry")
    func noteIsNotHandoff() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        #expect(try LogBook.save(LogDraft(tabID: tab.id, noteIDs: [note.id]), in: context) == nil)
        #expect(tab.entries.isEmpty)
    }

    @Test("moving an entry removes links to the old project's notes")
    func moveEntry() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let a = try project(context)
        let b = try project(context, "Other")
        let note = try NoteBook.create(in: a, context: context)
        let entry = try #require(try LogBook.addEntry(to: a, resumePoint: "Next", done: "", noteIDs: [note.id], in: context))
        try LogBook.update(entry, resumePoint: "Next", done: "", recordedAt: .now, tab: b, in: context)
        #expect(entry.notes.isEmpty)
        #expect(note.entries.isEmpty)
    }

    @Test("deleting an entry keeps its linked note")
    func deletingEntryKeepsNote() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        let entry = try #require(try LogBook.addEntry(to: tab, resumePoint: "Next", done: "", noteIDs: [note.id], in: context))
        try LogBook.delete(entry, in: context)
        #expect(try context.fetch(FetchDescriptor<ProjectNote>()).count == 1)
        #expect(note.entries.isEmpty)
    }

    @Test("deleting a note removes links and preserves the entry")
    func deletingNoteKeepsEntry() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        let entry = try #require(try LogBook.addEntry(to: tab, resumePoint: "Next", done: "", noteIDs: [note.id], in: context))
        try NoteBook.delete(note, in: context)
        #expect(entry.notes.isEmpty)
        #expect(tab.notes.isEmpty)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).count == 1)
    }

    @Test("deleting a project cascades to notes and entries")
    func deletingProject() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        _ = try LogBook.addEntry(to: tab, resumePoint: "Next", done: "", noteIDs: [note.id], in: context)
        try LogBook.delete(tab, in: context)
        #expect(try context.fetch(FetchDescriptor<ProjectNote>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LogEntry>()).isEmpty)
    }

    @Test("notebook buffers are discarded explicitly after deletion or reset")
    func forgetAndReset() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let note = try NoteBook.create(in: project(context), context: context)
        let editor = NoteEditingCoordinator(context: context)
        let draft = editor.document(for: note)
        draft.title = "Pending"
        editor.changed(draft)
        editor.forget(note.id)
        #expect(editor.documents.isEmpty)
        #expect(editor.document(for: note).title.isEmpty)
        editor.reset()
        #expect(editor.documents.isEmpty)
    }

    @Test("copying the log keeps its original Doc layout despite note links")
    func logExportUnchanged() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        let tab = try project(context)
        let note = try NoteBook.create(in: tab, context: context)
        let entry = try #require(try LogBook.addEntry(to: tab, resumePoint: "Next", done: "Done", in: context))
        let original = LogBook.plainText(for: entry)
        entry.notes = [note]
        #expect(LogBook.plainText(for: entry) == original)
    }

    @Test("formatting toggles preserve selected text and its links")
    func nativeFormatting() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        view.string = "Paper ideas"
        view.font = .systemFont(ofSize: 14)
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let formatting = NoteFormatting()
        formatting.textView = view
        formatting.bold()
        let bold = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let url = try #require(URL(string: "https://example.com"))
        formatting.link(url)
        formatting.italic()
        #expect(view.string == "Paper ideas")
        #expect(view.textStorage?.attribute(.link, at: 0, effectiveRange: nil) != nil)
        let italic = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        #expect(view.selectedRange() == NSRange(location: 0, length: 5))
    }

    @Test("checklist toggling preserves existing rich text")
    func nativeChecklist() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        let url = try #require(URL(string: "https://example.com"))
        view.textStorage?.setAttributedString(NSAttributedString(string: "Read paper", attributes: [.link: url]))
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let formatting = NoteFormatting()
        formatting.textView = view
        formatting.checklist()
        #expect(view.string == "☐ Read paper")
        #expect(view.textStorage?.attribute(.link, at: 3, effectiveRange: nil) != nil)
        view.setSelectedRange(NSRange(location: 2, length: 0))
        formatting.checklist()
        #expect(view.string == "☑ Read paper")
        #expect(view.textStorage?.attribute(.link, at: 3, effectiveRange: nil) != nil)
    }

    @Test("headings and numbered lists apply to the current paragraph")
    func nativeParagraphs() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        view.string = "Heading\nBody"
        view.setSelectedRange(NSRange(location: 0, length: 7))
        let formatting = NoteFormatting()
        formatting.textView = view
        formatting.heading(true)
        let font = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == 20)
        view.setSelectedRange(NSRange(location: 8, length: 4))
        formatting.list(numbered: true)
        let paragraph = try #require(view.textStorage?.attribute(.paragraphStyle, at: 8, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.textLists.first?.markerFormat == .decimal)
        #expect(view.string == "Heading\nBody")
    }


    @Test("heading changes support native undo and redo")
    func formattingUndo() throws {
        let view = UndoableNoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        view.string = "Heading"
        view.font = .systemFont(ofSize: 14)
        view.setSelectedRange(NSRange(location: 0, length: 7))
        view.history.groupsByEvent = false
        let formatting = NoteFormatting()
        formatting.textView = view
        view.history.beginUndoGrouping()
        formatting.heading(true)
        view.history.endUndoGrouping()
        #expect(view.history.canUndo)
        view.history.undo()
        let original = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(original.pointSize == 14)
        view.history.redo()
        let heading = try #require(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(heading.pointSize == 20)
        #expect(view.string == "Heading")
    }


    @Test("text colour applies only to the selection and survives editor reload")
    func selectedTextColour() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        let url = try #require(URL(string: "https://example.com/paper"))
        let text = NSMutableAttributedString(string: "Read paper", attributes: [
            .foregroundColor: NSColor.textColor, .font: NSFont.boldSystemFont(ofSize: 16)
        ])
        text.addAttribute(.link, value: url, range: NSRange(location: 5, length: 5))
        view.textStorage?.setAttributedString(text)
        view.setSelectedRange(NSRange(location: 5, length: 5))
        let formatting = NoteFormatting()
        formatting.textView = view
        formatting.textColor(NSColor(srgbRed: 0.8, green: 0.2, blue: 0.3, alpha: 1))
        let storage = try #require(view.textStorage)
        #expect((storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.isEqual(NSColor.textColor) == true)
        #expect(storage.attribute(.link, at: 5, effectiveRange: nil) != nil)
        #expect(view.selectedRange() == NSRange(location: 5, length: 5))

        let container = try TestStore.inMemory()
        let note = try NoteBook.create(in: project(container.mainContext), context: container.mainContext)
        let editor = RichNoteEditor(document: NoteDocument(note),
            editing: NoteEditingCoordinator(context: container.mainContext), formatting: NoteFormatting(), isEditable: true)
        let restored = NSTextView(frame: view.frame)
        editor.makeCoordinator().load(try NoteBook.encode(storage), into: restored)
        let ink = try #require((restored.textStorage?.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
        #expect(abs(ink.redComponent - 0.8) < 0.01)
        #expect(abs(ink.greenComponent - 0.2) < 0.01)
        #expect(abs(ink.blueComponent - 0.3) < 0.01)
        #expect(restored.string == "Read paper")
        #expect(restored.textStorage?.attribute(.link, at: 5, effectiveRange: nil) != nil)
    }

    @Test("choosing a colour at the caret changes future typing and can reset to Automatic")
    func typingColour() throws {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        view.string = "Ideas"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        let formatting = NoteFormatting()
        formatting.textView = view
        formatting.textColor(NSColor(srgbRed: 0.1, green: 0.3, blue: 0.8, alpha: 1))
        let ink = try #require((view.typingAttributes[.foregroundColor] as? NSColor)?.usingColorSpace(.sRGB))
        #expect(abs(ink.blueComponent - 0.8) < 0.01)
        #expect(view.string == "Ideas")
        formatting.textColor(nil)
        #expect((view.typingAttributes[.foregroundColor] as? NSColor)?.isEqual(NSColor.textColor) == true)
    }

    @Test("text colour supports native undo and redo")
    func colourUndo() throws {
        let view = UndoableNoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.isRichText = true
        view.textStorage?.setAttributedString(NSAttributedString(string: "Ideas", attributes: [.foregroundColor: NSColor.textColor]))
        view.setSelectedRange(NSRange(location: 0, length: 5))
        view.history.groupsByEvent = false
        let formatting = NoteFormatting()
        formatting.textView = view
        view.history.beginUndoGrouping()
        formatting.textColor(NSColor(srgbRed: 0.8, green: 0.2, blue: 0.3, alpha: 1))
        view.history.endUndoGrouping()
        view.history.undo()
        let restored = try #require(view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        #expect(restored.isEqual(NSColor.textColor))
        view.history.redo()
        let redone = try #require((view.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
        #expect(abs(redone.redComponent - 0.8) < 0.01)
        #expect(view.string == "Ideas")
    }

}


@MainActor
private final class UndoableNoteTextView: NSTextView {
    let history = UndoManager()
    override var undoManager: UndoManager? { history }
}
