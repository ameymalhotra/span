import Foundation
import SwiftData
import Testing
@testable import Span

/// The Log's rules, against an in-memory store: what counts as an entry, what
/// the "Pick up here" card shows, how tabs group and order, and that the plain
/// text matches the Google Doc it replaces.
@MainActor
@Suite("Log", .serialized)
struct LogBookTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try TestStore.inMemory()
    }

    @discardableResult
    private func tab(_ name: String, group: String = "") throws -> LogTab {
        try #require(try LogBook.createTab(name: name, group: group, in: context))
    }

    private func entries() throws -> [LogEntry] {
        try context.fetch(FetchDescriptor<LogEntry>())
    }

    // MARK: - Entries

    @Test("a resume point on its own is a complete entry")
    func resumePointAlone() throws {
        let course = try tab("Vector DB course")
        let entry = try LogBook.addEntry(to: course, resumePoint: "Continue the course", done: "",
                                         at: Clock.reference, in: context)
        #expect(entry?.resumePoint == "Continue the course")
        #expect(entry?.done == "")
        #expect(entry?.recordedAt == Clock.reference)
        #expect(try entries().count == 1)
    }

    @Test("what was done on its own is also an entry")
    func doneAlone() throws {
        let course = try tab("Course")
        #expect(try LogBook.addEntry(to: course, resumePoint: "", done: "Did the lab",
                                     in: context) != nil)
    }

    @Test("an entry with nothing in it is not saved")
    func emptyEntry() throws {
        let course = try tab("Course")
        let entry = try LogBook.addEntry(to: course, resumePoint: "  \n", done: "\t", in: context)
        #expect(entry == nil)
        #expect(try entries().isEmpty)
    }

    @Test("surrounding whitespace is trimmed, line breaks inside are kept")
    func trimming() throws {
        let course = try tab("Course")
        let entry = try #require(try LogBook.addEntry(
            to: course, resumePoint: "\n  Start at part 4  \n",
            done: "Read the article\nDid the lab", in: context))
        #expect(entry.resumePoint == "Start at part 4")
        #expect(entry.done == "Read the article\nDid the lab")
    }

    @Test("an entry written without a timer carries no duration")
    func noTimerNoDuration() throws {
        let course = try tab("Course")
        let entry = try #require(try LogBook.addEntry(to: course, resumePoint: "Next", done: "",
                                                      in: context))
        #expect(entry.sessionID == nil)
        #expect(entry.sessionTitle == nil)
        #expect(entry.workedSeconds == nil)
    }

    @Test("an entry written about a session keeps its title and the time worked")
    func sessionSnapshot() throws {
        let course = try tab("Course")
        let session = Fixture.session(
            in: context, title: "Lab part 3",
            startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 9.5),
            segments: [(Clock.at(hour: 9), Clock.at(hour: 9.5))]
        )
        let entry = try #require(try LogBook.addEntry(
            to: course, resumePoint: "Start at part 4", done: "Did lab till part 3",
            session: session, at: Clock.at(hour: 10), in: context))
        #expect(entry.sessionID == session.id)
        #expect(entry.sessionTitle == "Lab part 3")
        #expect(entry.workedSeconds == Clock.minutes(30))
    }

    @Test("a draft with no tab, or no text, saves nothing")
    func draftNeedsTabAndText() throws {
        let course = try tab("Course")
        #expect(try LogBook.save(LogDraft(tabID: nil, resumePoint: "Next"), in: context) == nil)
        #expect(try LogBook.save(LogDraft(tabID: course.id), in: context) == nil)
        #expect(try LogBook.save(LogDraft(tabID: course.id, resumePoint: "Next"), in: context) != nil)
        #expect(try entries().count == 1)
    }

    @Test("a draft aimed at an archived tab saves nothing")
    func draftArchivedTab() throws {
        let course = try tab("Course")
        try LogBook.setArchived(course, true, in: context)
        #expect(try LogBook.save(LogDraft(tabID: course.id, resumePoint: "Next"), in: context) == nil)
    }

    // MARK: - History and the resume card

    @Test("history reads newest first, like the Doc")
    func historyOrder() throws {
        let course = try tab("Course")
        try LogBook.addEntry(to: course, resumePoint: "first", done: "", at: Clock.at(hour: 9), in: context)
        try LogBook.addEntry(to: course, resumePoint: "third", done: "", at: Clock.at(hour: 11), in: context)
        try LogBook.addEntry(to: course, resumePoint: "second", done: "", at: Clock.at(hour: 10), in: context)
        #expect(LogBook.history(for: course).map(\.resumePoint) == ["third", "second", "first"])
    }

    @Test("the card shows the newest resume point, skipping entries that only record what was done")
    func latestSkipsDoneOnly() throws {
        let course = try tab("Course")
        try LogBook.addEntry(to: course, resumePoint: "Finish part 6", done: "",
                             at: Clock.at(hour: 9), in: context)
        try LogBook.addEntry(to: course, resumePoint: "", done: "Tidied notes",
                             at: Clock.at(hour: 10), in: context)
        #expect(LogBook.latestResumePoint(for: course)?.resumePoint == "Finish part 6")
    }

    @Test("a tab with nothing logged has no resume point")
    func emptyTabCard() throws {
        #expect(LogBook.latestResumePoint(for: try tab("Course")) == nil)
    }

    @Test("editing an entry's date moves it in the history")
    func editingDateReorders() throws {
        let course = try tab("Course")
        let old = try #require(try LogBook.addEntry(to: course, resumePoint: "old", done: "",
                                                    at: Clock.at(hour: 9), in: context))
        try LogBook.addEntry(to: course, resumePoint: "new", done: "", at: Clock.at(hour: 10), in: context)

        let changed = try LogBook.update(old, resumePoint: "old", done: "",
                                         recordedAt: Clock.at(hour: 11), in: context)
        #expect(changed)
        #expect(old.editedAt != nil)
        #expect(LogBook.history(for: course).first?.resumePoint == "old")
        #expect(LogBook.latestResumePoint(for: course)?.resumePoint == "old")
    }

    @Test("an edit cannot empty both fields")
    func editCannotEmpty() throws {
        let course = try tab("Course")
        let entry = try #require(try LogBook.addEntry(to: course, resumePoint: "keep", done: "",
                                                      in: context))
        let changed = try LogBook.update(entry, resumePoint: " ", done: "",
                                         recordedAt: entry.recordedAt, in: context)
        #expect(!changed)
        #expect(entry.resumePoint == "keep")
    }

    @Test("an entry can be moved to another tab")
    func moveEntry() throws {
        let a = try tab("A")
        let b = try tab("B")
        let entry = try #require(try LogBook.addEntry(to: a, resumePoint: "x", done: "", in: context))
        try LogBook.update(entry, resumePoint: "x", done: "", recordedAt: entry.recordedAt,
                           tab: b, in: context)
        #expect(entry.tab?.id == b.id)
        #expect(LogBook.history(for: a).isEmpty)
        #expect(LogBook.history(for: b).count == 1)
    }

    @Test("deleting the newest entry hands the card back to the one before")
    func deleteFallsBack() throws {
        let course = try tab("Course")
        try LogBook.addEntry(to: course, resumePoint: "earlier", done: "", at: Clock.at(hour: 9), in: context)
        let latest = try #require(try LogBook.addEntry(to: course, resumePoint: "latest", done: "",
                                                       at: Clock.at(hour: 10), in: context))
        try LogBook.delete(latest, in: context)
        #expect(LogBook.latestResumePoint(for: course)?.resumePoint == "earlier")
        #expect(try entries().count == 1)
    }

    // MARK: - Tabs

    @Test("deleting a tab deletes its entries from the store")
    func deleteTabCascades() throws {
        let course = try tab("Course")
        let other = try tab("Other")
        try LogBook.addEntry(to: course, resumePoint: "a", done: "", in: context)
        try LogBook.addEntry(to: course, resumePoint: "b", done: "", in: context)
        try LogBook.addEntry(to: other, resumePoint: "c", done: "", in: context)

        try LogBook.delete(course, in: context)

        #expect(try LogBook.allTabs(in: context).map(\.name) == ["Other"])
        #expect(try entries().map(\.resumePoint) == ["c"])
    }

    @Test("a tab needs a name")
    func tabNeedsName() throws {
        #expect(try LogBook.createTab(name: "   ", in: context) == nil)
    }

    @Test("new tabs get different colours while any are free")
    func distinctColours() throws {
        let slots = try (0..<4).map { try tab("Tab \($0)").colorSlot }
        #expect(Set(slots).count == 4)
    }

    @Test("the sidebar lists ungrouped tabs first, then each group in order")
    func sectionsOrder() throws {
        try tab("Vector DB course", group: "Research")
        try tab("Business")
        try tab("Onboarding", group: "Internship")
        try tab("LC vs LI paper", group: "Research")

        let sections = LogBook.sections(try LogBook.allTabs(in: context))
        #expect(sections.map(\.group) == ["", "Research", "Internship"])
        #expect(sections[1].tabs.map(\.name) == ["Vector DB course", "LC vs LI paper"])
    }

    @Test("a group typed in a different case joins the existing one")
    func groupCaseInsensitive() throws {
        try tab("A", group: "Research")
        let b = try tab("B", group: "  research ")
        #expect(b.group == "Research")
    }

    @Test("renaming a group moves every tab under it, and their entries stay")
    func renameGroup() throws {
        let a = try tab("A", group: "Research")
        let b = try tab("B", group: "Research")
        let c = try tab("C", group: "Business")
        try LogBook.addEntry(to: a, resumePoint: "x", done: "", in: context)

        try LogBook.renameGroup("Research", to: "Studies", in: context)

        #expect(a.group == "Studies")
        #expect(b.group == "Studies")
        #expect(c.group == "Business")
        #expect(LogBook.history(for: a).count == 1)
    }

    @Test("moving a tab out of its group puts it under no heading")
    func ungroup() throws {
        let a = try tab("A", group: "Research")
        try LogBook.move(a, toGroup: "", in: context)
        #expect(a.group == "")
        #expect(LogBook.sections(try LogBook.allTabs(in: context)).first?.group == "")
    }

    @Test("archived tabs leave the sidebar sections but keep their history")
    func archive() throws {
        let a = try tab("A")
        try tab("B")
        try LogBook.addEntry(to: a, resumePoint: "x", done: "", in: context)
        try LogBook.setArchived(a, true, in: context)

        let all = try LogBook.allTabs(in: context)
        #expect(LogBook.sections(all).flatMap(\.tabs).map(\.name) == ["B"])
        #expect(LogBook.archived(all).map(\.name) == ["A"])
        #expect(LogBook.activeTab(id: a.id, in: all) == nil)
        #expect(LogBook.history(for: a).count == 1)
    }

    @Test("reordering one section leaves the others where they were")
    func reorderWithinSection() throws {
        let x = try tab("X")
        let a = try tab("A", group: "G")
        let b = try tab("B", group: "G")
        let c = try tab("C", group: "G")
        let xIndex = x.sortIndex

        try LogBook.reorder([a, b, c], fromOffsets: IndexSet(integer: 2), toOffset: 0, in: context)

        let sections = LogBook.sections(try LogBook.allTabs(in: context))
        #expect(sections[1].tabs.map(\.name) == ["C", "A", "B"])
        #expect(x.sortIndex == xIndex)
    }

    @Test("known groups lists each heading once")
    func knownGroups() throws {
        try tab("A", group: "Research")
        try tab("B", group: "Research")
        let c = try tab("C", group: "Old")
        try tab("D")
        try LogBook.setArchived(c, true, in: context)
        #expect(LogBook.knownGroups(try LogBook.allTabs(in: context)) == ["Research", "Old"])
    }

    // MARK: - Sessions

    @Test("a session started for a tab remembers it")
    func sessionRemembersTab() throws {
        let course = try tab("Course")
        let name = "SpanTests.Log.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let model = AppModel(container: container, logPreferences: preferences)
        model.idleClock = { 0 }
        let session = model.startSession(title: "Lab", category: "Learning", minutes: 25,
                                         logTabID: course.id)
        #expect(session?.logTabID == course.id)
        model.finishSession()
    }

    @Test("a session started without a tab has none")
    func sessionWithoutTab() throws {
        let model = AppModel(container: container)
        model.idleClock = { 0 }
        let session = model.startSession(title: "Lab", category: "Learning", minutes: 25)
        #expect(session?.logTabID == nil)
        model.finishSession()
    }

    // MARK: - Plain text

    @Test("an entry copies out exactly as the Doc laid it out")
    func plainTextMatchesDoc() throws {
        let course = try tab("Course")
        let entry = try #require(try LogBook.addEntry(
            to: course, resumePoint: "Continue the course",
            done: "Completed the quiz\nStarted next course on vector databases",
            at: Clock.date(2026, 7, 14, 23, 30), in: context))
        #expect(LogBook.plainText(for: entry) == """
        Date: 14 July 2026
        Time: 11:30 PM

        Resume Point / Things to do
        Continue the course
        What was done in this session
        Completed the quiz
        Started next course on vector databases
        """)
    }

    @Test("copying a tab puts the newest entry first")
    func plainTextOrder() throws {
        let course = try tab("Course")
        try LogBook.addEntry(to: course, resumePoint: "Start at part 4", done: "",
                             at: Clock.date(2026, 7, 2, 1, 39), in: context)
        try LogBook.addEntry(to: course, resumePoint: "Finish part 6", done: "",
                             at: Clock.date(2026, 7, 3, 2, 0), in: context)
        let text = LogBook.plainText(for: course.entries)
        let first = try #require(text.range(of: "3 July 2026"))
        let second = try #require(text.range(of: "2 July 2026"))
        #expect(first.lowerBound < second.lowerBound)
    }
}
