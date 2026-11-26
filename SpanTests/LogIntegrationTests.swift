import Foundation
import SwiftData
import Testing
@testable import Span

/// The context shared by the start sheet, Focus, review and menu bar. Each
/// test has its own preferences as well as its own store.
@MainActor
@Suite("Log integration", .serialized)
struct LogIntegrationTests {
    private func withModel(_ body: (AppModel, ModelContext, UserDefaults) throws -> Void) throws {
        let name = "SpanTests.Log.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let container = try TestStore.inMemory()
        let model = AppModel(container: container, logPreferences: preferences)
        model.idleClock = { 0 }
        defer { model.stop() }
        try body(model, container.mainContext, preferences)
    }

    @Test("a fresh menu-bar form follows the running session after a previous entry")
    func freshFormFollowsRunningWork() throws {
        try withModel { model, context, preferences in
            let a = try #require(try LogBook.createTab(name: "Research", in: context))
            let b = try #require(try LogBook.createTab(name: "Internship", in: context))
            model.menuBarLogDraft = LogDraft(tabID: a.id, resumePoint: "Read paper")
            try model.saveLogDraft(model.menuBarLogDraft)
            model.menuBarLogDraft.clearText()
            model.startSession(title: "Onboarding", category: "Work", minutes: 25, logTabID: b.id)

            model.prepareMenuBarLogDraft()

            #expect(model.menuBarLogDraft.tabID == b.id)
            #expect(preferences.string(forKey: "log.lastTabID") == b.id.uuidString)
            model.finishSession()
        }
    }

    @Test("switching sessions does not retarget an unfinished handoff")
    func unfinishedFormKeepsItsTabAndText() throws {
        try withModel { model, context, _ in
            let a = try #require(try LogBook.createTab(name: "Research", in: context))
            let b = try #require(try LogBook.createTab(name: "Internship", in: context))
            let draft = LogDraft(tabID: a.id, resumePoint: "Next paragraph", done: "Read intro")
            model.menuBarLogDraft = draft
            model.startSession(title: "Work", category: "Work", minutes: 25, logTabID: b.id)
            model.prepareMenuBarLogDraft()
            #expect(model.menuBarLogDraft == draft)
            model.finishSession()
        }
    }

    @Test("saving a review to a different tab remembers where it was actually logged")
    func reviewRemembersDestination() throws {
        try withModel { model, context, preferences in
            let a = try #require(try LogBook.createTab(name: "Research", in: context))
            let b = try #require(try LogBook.createTab(name: "Internship", in: context))
            let session = try #require(model.startSession(title: "Work", category: "Work",
                                                          minutes: 25, logTabID: a.id))
            model.finishSession()
            let entry = try #require(try model.saveLogDraft(
                LogDraft(tabID: b.id, resumePoint: "Next"), session: session))
            #expect(entry.tab?.id == b.id)
            #expect(entry.sessionID == session.id)
            #expect(preferences.string(forKey: "log.lastTabID") == b.id.uuidString)
            model.prepareMenuBarLogDraft()
            #expect(model.menuBarLogDraft.tabID == b.id)
        }
    }

    @Test("an unlinked session does not erase the last actual Log tab")
    func unlinkedSessionKeepsLastTab() throws {
        try withModel { model, context, preferences in
            let tab = try #require(try LogBook.createTab(name: "Research", in: context))
            try model.saveLogDraft(LogDraft(tabID: tab.id, resumePoint: "Next"))
            model.startSession(title: "Other work", category: "Work", minutes: 25)
            #expect(preferences.string(forKey: "log.lastTabID") == tab.id.uuidString)
            model.prepareMenuBarLogDraft()
            #expect(model.menuBarLogDraft.tabID == tab.id)
            model.finishSession()
        }
    }

    @Test("an archived tab cannot become a new session's tab or an empty form's default")
    func archivedTabIsUnavailable() throws {
        try withModel { model, context, _ in
            let tab = try #require(try LogBook.createTab(name: "Research", in: context))
            try model.saveLogDraft(LogDraft(tabID: tab.id, resumePoint: "Next"))
            try LogBook.setArchived(tab, true, in: context)
            let session = model.startSession(title: "Work", category: "Work", minutes: 25,
                                             logTabID: tab.id)
            #expect(session?.logTabID == nil)
            model.menuBarLogDraft = LogDraft(tabID: tab.id)
            model.prepareMenuBarLogDraft()
            #expect(model.menuBarLogDraft.tabID == nil)
            model.finishSession()
        }
    }

    @Test("an unavailable draft saves nothing and does not change the remembered tab")
    func invalidDraftDoesNotChangeContext() throws {
        try withModel { model, context, preferences in
            let tab = try #require(try LogBook.createTab(name: "Research", in: context))
            try model.saveLogDraft(LogDraft(tabID: tab.id, resumePoint: "Next"))
            #expect(try model.saveLogDraft(LogDraft(tabID: UUID(), resumePoint: "Keep me")) == nil)
            #expect(preferences.string(forKey: "log.lastTabID") == tab.id.uuidString)
            let entries = try context.fetch(FetchDescriptor<LogEntry>())
            #expect(entries.count == 1)
        }
    }

    @Test("clearing transient Log state removes menu-bar and per-tab drafts")
    func resetClearsAllDrafts() throws {
        try withModel { model, _, _ in
            let id = UUID()
            model.menuBarLogDraft = LogDraft(tabID: id, resumePoint: "Private draft")
            model.logDrafts[id] = LogDraft(tabID: id, done: "Unfinished note")
            // Never call resetEverything here: it clears real preferences.
            model.clearLogDrafts()
            #expect(model.menuBarLogDraft == LogDraft())
            #expect(model.logDrafts.isEmpty)
        }
    }

    @Test("a rejected second session does not change the remembered tab")
    func rejectedSessionKeepsLastTab() throws {
        try withModel { model, context, preferences in
            let a = try #require(try LogBook.createTab(name: "Research", in: context))
            let b = try #require(try LogBook.createTab(name: "Internship", in: context))
            model.startSession(title: "Work", category: "Work", minutes: 25, logTabID: a.id)
            #expect(model.startSession(title: "Other", category: "Work", minutes: 25, logTabID: b.id) == nil)
            #expect(preferences.string(forKey: "log.lastTabID") == a.id.uuidString)
            model.finishSession()
        }
    }

    @Test("archiving a draft's tab keeps its unsaved text available to move elsewhere")
    func unavailableTabKeepsDraftText() throws {
        try withModel { model, context, _ in
            let tab = try #require(try LogBook.createTab(name: "Research", in: context))
            let draft = LogDraft(tabID: tab.id, resumePoint: "Do not lose this")
            model.menuBarLogDraft = draft
            try LogBook.setArchived(tab, true, in: context)
            model.prepareMenuBarLogDraft()
            #expect(model.menuBarLogDraft == draft)
            #expect(try model.saveLogDraft(draft) == nil)
            let other = try #require(try LogBook.createTab(name: "New project", in: context))
            model.menuBarLogDraft.tabID = other.id
            let entry = try model.saveLogDraft(model.menuBarLogDraft)
            #expect(entry?.resumePoint == draft.resumePoint)
            #expect(entry?.tab?.id == other.id)
        }
    }

    @Test("deleting active work immediately clears the timer and preserves linked writing")
    func deleteActiveSession() throws {
        try withModel { model, context, _ in
            let tab = try #require(try LogBook.createTab(name: "Research", in: context))
            let note = try NoteBook.create(in: tab, context: context)
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25, logTabID: tab.id))
            let id = session.id
            let entry = try #require(try model.saveLogDraft(LogDraft(tabID: tab.id, resumePoint: "Continue", noteIDs: [note.id]), session: session))
            try model.deleteSession(session)
            #expect(model.activeSession == nil)
            #expect(model.sessionClock == "00:00")
            #expect(model.pendingReflection == nil)
            #expect(!model.offersBreakAfterReview)
            #expect(try context.fetch(FetchDescriptor<WorkSession>()).isEmpty)
            #expect(entry.sessionID == id)
            #expect(entry.sessionTitle == "Read")
            #expect(entry.notes.first?.id == note.id)
        }
    }

    @Test("deleting a completed session leaves other running work alone")
    func deletePastSession() throws {
        try withModel { model, context, _ in
            let past = try #require(model.startSession(title: "Past", category: "Work", minutes: 25))
            model.finishSession()
            let current = try #require(model.startSession(title: "Current", category: "Work", minutes: 25))
            try model.deleteSession(past)
            #expect(model.activeSession?.id == current.id)
            #expect(model.pendingReflection == nil)
            #expect(!model.offersBreakAfterReview)
            #expect(try context.fetch(FetchDescriptor<WorkSession>()).count == 1)
            model.finishSession()
        }
    }

    @Test("deleting paused work leaves its break as a standalone timer")
    func deletePausedSessionDuringBreak() throws {
        try withModel { model, context, _ in
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            model.startBreak(minutes: 5)
            #expect(model.sessionPausedForBreak)
            try model.deleteSession(session)
            #expect(model.activeSession == nil)
            #expect(model.isOnBreak)
            #expect(!model.sessionPausedForBreak)
            model.endBreak()
            #expect(model.activeSession == nil)
            #expect(!model.isOnBreak)
            #expect(try context.fetch(FetchDescriptor<WorkSession>()).isEmpty)
        }
    }

}
