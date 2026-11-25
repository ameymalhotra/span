import Foundation
import SwiftData
import Testing
@testable import Span

/// Durability: everything here writes to a real SQLite store in a temporary
/// directory, closes the container, and reads it back through a new one.
@MainActor
@Suite("Persistence", .serialized)
struct PersistenceTests {

    /// Writes with one container, then reads with a fresh one over the same
    /// file. `verify` runs while that second container is still open — a model
    /// object must not outlive the context it came from.
    private func roundTrip(
        write: (ModelContext) throws -> Void,
        verify: (ModelContext) throws -> Void
    ) throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Round.store")
            do {
                let container = try TestStore.onDisk(at: url)
                try write(container.mainContext)
                try container.mainContext.save()
            }
            let reopened = try TestStore.onDisk(at: url)
            try verify(reopened.mainContext)
        }
    }

    // MARK: - Sessions

    @Test("a session survives a reopen with every field intact")
    func sessionRoundTrip() throws {
        let started = Clock.at(hour: 9)
        let ended = Clock.at(hour: 11)

        try roundTrip { context in
            let session = WorkSession(title: "Write the report", category: "Deep Work",
                                      plannedMinutes: 90)
            session.startedAt = started
            session.endedAt = ended
            session.totalPausedSeconds = 600
            session.statusRaw = SessionStatus.completed.rawValue
            session.focusRating = 4
            session.honestWorkMinutes = 75
            session.distractions = 2
            session.reflection = "Interrupted twice"
            session.reflectionStateRaw = ReflectionState.completed.rawValue
            context.insert(session)
        } verify: { context in
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            #expect(sessions.count == 1)
            let session = sessions[0]
            #expect(session.title == "Write the report")
            #expect(session.category == "Deep Work")
            #expect(session.plannedMinutes == 90)
            #expect(session.startedAt == started)
            #expect(session.endedAt == ended)
            #expect(session.totalPausedSeconds == 600)
            #expect(session.status == .completed)
            #expect(session.focusRating == 4)
            #expect(session.honestWorkMinutes == 75)
            #expect(session.distractions == 2)
            #expect(session.reflection == "Interrupted twice")
            #expect(session.reflectionState == .completed)
            #expect(session.isReflected)
        }
    }

    @Test("an unreviewed session keeps its blanks rather than defaulting them")
    func sessionOptionalsStayNil() throws {
        try roundTrip { context in
            context.insert(WorkSession(title: "Bare", plannedMinutes: 25))
        } verify: { context in
            let session = try context.fetch(FetchDescriptor<WorkSession>())[0]
            #expect(session.endedAt == nil)
            #expect(session.pausedAt == nil)
            #expect(session.focusRating == nil)
            #expect(session.honestWorkMinutes == nil)
            #expect(session.distractions == nil)
            #expect(session.reflection == nil)
            #expect(session.reflectionState == .pending)
        }
    }

    @Test("a session's runs come back attached, in order, with the open one still open")
    func segmentsRoundTrip() throws {
        try roundTrip { context in
            let session = WorkSession(title: "Paused twice", plannedMinutes: 120)
            session.startedAt = Clock.at(hour: 9)
            context.insert(session)
            for (start, end) in [(Clock.at(hour: 9), Clock.at(hour: 10) as Date?),
                                 (Clock.at(hour: 11), Clock.at(hour: 11.5)),
                                 (Clock.at(hour: 13), nil)] {
                let segment = SessionSegment(startedAt: start, session: session)
                segment.endedAt = end
                session.segments.append(segment)
            }
        } verify: { context in
            let session = try context.fetch(FetchDescriptor<WorkSession>())[0]
            #expect(session.segments.count == 3)
            let sorted = session.segments.sorted { $0.startedAt < $1.startedAt }
            #expect(sorted.map(\.startedAt) == [Clock.at(hour: 9), Clock.at(hour: 11), Clock.at(hour: 13)])
            #expect(sorted[2].endedAt == nil)
            #expect(session.openSegment?.startedAt == Clock.at(hour: 13))
            #expect(session.elapsed(at: Clock.at(hour: 14)) == Clock.hours(2.5))
        }
    }

    @Test("the inverse relationship is stored, not just the forward one")
    func segmentBackReferenceRoundTrips() throws {
        try roundTrip { context in
            let session = WorkSession(title: "Owner", plannedMinutes: 30)
            context.insert(session)
            session.segments.append(SessionSegment(startedAt: Clock.at(hour: 9), session: session))
        } verify: { context in
            let segment = try context.fetch(FetchDescriptor<SessionSegment>())[0]
            #expect(segment.session?.title == "Owner")
        }
    }

    @Test("deleting a session removes its runs from the store, not just from memory")
    func cascadeDeleteReachesTheStore() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Cascade.store")
            do {
                let container = try TestStore.onDisk(at: url)
                let context = container.mainContext
                let session = WorkSession(title: "Doomed", plannedMinutes: 30)
                context.insert(session)
                session.segments.append(SessionSegment(startedAt: Clock.at(hour: 9), session: session))
                session.segments.append(SessionSegment(startedAt: Clock.at(hour: 10), session: session))
                try context.save()

                context.delete(session)
                try context.save()
            }
            let reopened = try TestStore.onDisk(at: url)
            let segments = try reopened.mainContext.fetch(FetchDescriptor<SessionSegment>())
            let sessions = try reopened.mainContext.fetch(FetchDescriptor<WorkSession>())
            #expect(segments.isEmpty)
            #expect(sessions.isEmpty)
        }
    }

    // MARK: - Log

    @Test("a log tab and its entries survive a reopen")
    func logRoundTrip() throws {
        let sessionID = UUID()
        try roundTrip { context in
            let tab = LogTab(name: "Vector DB course", group: "Research", colorSlot: 3, sortIndex: 2)
            tab.isArchived = true
            context.insert(tab)
            let entry = LogEntry(tab: tab, recordedAt: Clock.at(hour: 23.5),
                                 resumePoint: "Continue the course", done: "Completed the quiz")
            entry.sessionID = sessionID
            entry.sessionTitle = "Quiz"
            entry.workedSeconds = 1500
            context.insert(entry)
            tab.entries.append(entry)
        } verify: { context in
            let tab = try #require(try context.fetch(FetchDescriptor<LogTab>()).first)
            #expect(tab.name == "Vector DB course")
            #expect(tab.group == "Research")
            #expect(tab.colorSlot == 3)
            #expect(tab.sortIndex == 2)
            #expect(tab.isArchived)
            #expect(tab.entries.count == 1)
            let entry = try #require(tab.entries.first)
            #expect(entry.tab?.id == tab.id)
            #expect(entry.recordedAt == Clock.at(hour: 23.5))
            #expect(entry.resumePoint == "Continue the course")
            #expect(entry.done == "Completed the quiz")
            #expect(entry.sessionID == sessionID)
            #expect(entry.sessionTitle == "Quiz")
            #expect(entry.workedSeconds == 1500)
        }
    }

    @Test("a session keeps the log tab it was started for")
    func sessionLogTabRoundTrip() throws {
        let tabID = UUID()
        try roundTrip { context in
            let session = WorkSession(title: "Lab", plannedMinutes: 25)
            session.logTabID = tabID
            context.insert(session)
        } verify: { context in
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            #expect(sessions.first?.logTabID == tabID)
        }
    }

    @Test("a store written before the log existed opens with it, data intact")
    func storeFromBeforeTheLog() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Old.store")
            do {
                let old = Schema([PreLogSchema.WorkSession.self, PreLogSchema.SessionSegment.self, ActivityRecord.self,
                                  TimeEntry.self, BreakRecord.self, TimeCategory.self,
                                  AppCategoryRule.self])
                let container = try ModelContainer(for: old, configurations: ModelConfiguration(url: url))
                let session = PreLogSchema.WorkSession(title: "Old session", startedAt: Clock.at(hour: 9))
                session.category = "Research"
                session.endedAt = Clock.at(hour: 10)
                session.statusRaw = "completed"
                session.reflection = "Keep these notes"
                session.reflectionStateRaw = "completed"
                container.mainContext.insert(session)
                let segment = PreLogSchema.SessionSegment(startedAt: Clock.at(hour: 9),
                                                          endedAt: Clock.at(hour: 10), session: session)
                container.mainContext.insert(segment)
                session.segments.append(segment)
                container.mainContext.insert(TimeEntry(title: "Walk", startedAt: Clock.at(hour: 12),
                                                       endedAt: Clock.at(hour: 13)))
                try container.mainContext.save()
            }
            let reopened = try TestStore.onDisk(at: url)
            let context = reopened.mainContext
            let sessions = try context.fetch(FetchDescriptor<WorkSession>())
            let session = try #require(sessions.first)
            #expect(sessions.count == 1)
            #expect(session.title == "Old session")
            #expect(session.category == "Research")
            #expect(session.reflection == "Keep these notes")
            #expect(session.logTabID == nil)
            #expect(session.segments.count == 1)
            #expect(session.segments.first?.session?.id == session.id)
            #expect(session.elapsed() == Clock.hours(1))
            #expect(try context.fetch(FetchDescriptor<TimeEntry>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<LogTab>()).isEmpty)
            context.insert(LogTab(name: "Course"))
            try context.save()
            #expect(try context.fetch(FetchDescriptor<LogTab>()).count == 1)
        }
    }

    // MARK: - Other models

    /// A real read-only store makes save fail without touching permissions,
    /// the user's store, or a mock that merely repeats the implementation.
    private func withReadOnlyLog(_ body: (ModelContext, LogTab, LogEntry) throws -> Void) throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("ReadOnly.store")
            do {
                let writable = try TestStore.onDisk(at: url)
                let tab = try #require(try LogBook.createTab(name: "Research", in: writable.mainContext))
                try LogBook.addEntry(to: tab, resumePoint: "Keep me", done: "", in: writable.mainContext)
            }
            let container = try ModelContainer(for: ModelStack.schema,
                configurations: ModelConfiguration(url: url, allowsSave: false))
            let context = container.mainContext
            context.autosaveEnabled = false
            let tab = try #require(try context.fetch(FetchDescriptor<LogTab>()).first)
            let entry = try #require(tab.entries.first)
            try body(context, tab, entry)
        }
    }

    @Test("a failed entry deletion restores the entry and its tab relationship")
    func failedEntryDeletion() throws {
        try withReadOnlyLog { context, tab, entry in
            #expect(throws: (any Error).self) { try LogBook.delete(entry, in: context) }
            #expect(tab.entries.count == 1)
            #expect(entry.tab?.id == tab.id)
            #expect(entry.resumePoint == "Keep me")
            #expect(!context.hasChanges)
        }
    }

    @Test("a failed tab deletion restores its history")
    func failedTabDeletion() throws {
        try withReadOnlyLog { context, _, _ in
            let tab = try #require(try context.fetch(FetchDescriptor<LogTab>()).first)
            #expect(throws: (any Error).self) { try LogBook.delete(tab, in: context) }
            let tabs = try context.fetch(FetchDescriptor<LogTab>())
            let entries = try context.fetch(FetchDescriptor<LogEntry>())
            #expect(tabs.count == 1)
            #expect(entries.count == 1)
            #expect(tabs.first?.entries.count == 1)
            #expect(!context.hasChanges)
        }
    }

    @Test("retrying a failed log save does not accumulate unsaved duplicate entries")
    func failedEntrySaveCanBeRetried() throws {
        try withReadOnlyLog { context, tab, _ in
            for _ in 0..<2 {
                #expect(throws: (any Error).self) {
                    try LogBook.addEntry(to: tab, resumePoint: "New draft", done: "", in: context)
                }
                let entries = try context.fetch(FetchDescriptor<LogEntry>())
                #expect(entries.count == 1)
                #expect(tab.entries.count == 1)
                #expect(!context.hasChanges)
            }
        }
    }

    @Test("a hand-written entry round-trips")
    func entryRoundTrip() throws {
        try roundTrip { context in
            context.insert(TimeEntry(title: "Walk", category: "Break",
                                     startedAt: Clock.at(hour: 12), endedAt: Clock.at(hour: 12.5),
                                     notes: "Around the block"))
        } verify: { context in
            let entry = try context.fetch(FetchDescriptor<TimeEntry>())[0]
            #expect(entry.title == "Walk")
            #expect(entry.category == "Break")
            #expect(entry.startedAt == Clock.at(hour: 12))
            #expect(entry.endedAt == Clock.at(hour: 12.5))
            #expect(entry.notes == "Around the block")
            #expect(entry.duration == 1800)
        }
    }

    @Test("a tracked activity record round-trips")
    func activityRoundTrip() throws {
        try roundTrip { context in
            context.insert(ActivityRecord(
                appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                windowTitle: "ModelStack.swift", url: nil,
                startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 10),
                isIdle: false, categoryName: "Building"))
        } verify: { context in
            let record = try context.fetch(FetchDescriptor<ActivityRecord>())[0]
            #expect(record.appName == "Xcode")
            #expect(record.bundleIdentifier == "com.apple.dt.Xcode")
            #expect(record.windowTitle == "ModelStack.swift")
            #expect(record.url == nil)
            #expect(record.isIdle == false)
            #expect(record.categoryName == "Building")
            #expect(record.duration == 3600)
        }
    }

    @Test("an idle record round-trips as a break")
    func idleRecordRoundTrip() throws {
        try roundTrip { context in
            context.insert(ActivityRecord(appName: "Away", bundleIdentifier: nil,
                                          startedAt: Clock.at(hour: 12), endedAt: Clock.at(hour: 13),
                                          isIdle: true, categoryName: "Away"))
        } verify: { context in
            let record = try context.fetch(FetchDescriptor<ActivityRecord>())[0]
            #expect(record.isIdle)
            #expect(record.bundleIdentifier == nil)
            #expect(record.windowTitle == nil)
        }
    }

    @Test("a category round-trips, custom colour included")
    func categoryRoundTrip() throws {
        try roundTrip { context in
            let preset = TimeCategory(name: "Deep Work", colorSlot: 4, sortIndex: 0)
            let custom = TimeCategory(name: "Bespoke", colorSlot: 0, sortIndex: 1)
            custom.colorHex = "#123456"
            context.insert(preset)
            context.insert(custom)
        } verify: { context in
            let categories = try context.fetch(FetchDescriptor<TimeCategory>())
                .sorted { $0.sortIndex < $1.sortIndex }
            #expect(categories.map(\.name) == ["Deep Work", "Bespoke"])
            #expect(categories[0].colorHex == nil)
            #expect(categories[1].colorHex == "#123456")
            #expect(categories[1].resolvedColor.hexString == "#123456")
        }
    }

    @Test("a user grouping rule round-trips")
    func appRuleRoundTrip() throws {
        try roundTrip { context in
            context.insert(AppCategoryRule(bundleIdentifier: "com.apple.Safari",
                                           appName: "Safari", categoryName: "Research"))
        } verify: { context in
            let rule = try context.fetch(FetchDescriptor<AppCategoryRule>())[0]
            #expect(rule.bundleIdentifier == "com.apple.Safari")
            #expect(rule.appName == "Safari")
            #expect(rule.categoryName == "Research")
        }
    }

    // MARK: - Fidelity

    @Test("sub-second precision is not rounded away")
    func subSecondPrecision() throws {
        let precise = Date(timeIntervalSinceReferenceDate: 780_000_000.123_456)
        try roundTrip { context in
            context.insert(TimeEntry(title: "Precise", startedAt: precise,
                                     endedAt: precise.addingTimeInterval(1)))
        } verify: { context in
            let entry = try context.fetch(FetchDescriptor<TimeEntry>())[0]
            #expect(abs(entry.startedAt.timeIntervalSince(precise)) < 0.001)
            #expect(entry.duration == 1)
        }
    }

    @Test("unicode and emoji survive the round trip")
    func unicodeSurvives() throws {
        let title = "Écrire le rapport 📝 — 日本語テスト"
        try roundTrip { context in
            context.insert(TimeEntry(title: title, category: "Ré·flexion",
                                     startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 10)))
        } verify: { context in
            let entry = try context.fetch(FetchDescriptor<TimeEntry>())[0]
            #expect(entry.title == title)
            #expect(entry.category == "Ré·flexion")
        }
    }

    @Test("a very long note is stored whole")
    func longStringsSurvive() throws {
        let note = String(repeating: "The day got away from me. ", count: 500)
        try roundTrip { context in
            context.insert(TimeEntry(title: "Long", startedAt: Clock.at(hour: 9),
                                     endedAt: Clock.at(hour: 10), notes: note))
        } verify: { context in
            let entry = try context.fetch(FetchDescriptor<TimeEntry>())[0]
            #expect(entry.notes == note)
            #expect(entry.notes?.count == note.count)
        }
    }

    @Test("an empty title is stored as empty, not lost")
    func emptyStringsSurvive() throws {
        try roundTrip { context in
            context.insert(TimeEntry(title: "", category: "",
                                     startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 10)))
        } verify: { context in
            let entry = try context.fetch(FetchDescriptor<TimeEntry>())[0]
            #expect(entry.title.isEmpty)
            #expect(entry.category.isEmpty)
        }
    }

    @Test("a day's worth of records all come back")
    func bulkRoundTrip() throws {
        try roundTrip { context in
            for index in 0..<200 {
                context.insert(ActivityRecord(
                    appName: "App\(index % 7)", bundleIdentifier: "com.example.app\(index % 7)",
                    startedAt: Clock.at(hour: Double(index) * 0.1),
                    endedAt: Clock.at(hour: Double(index + 1) * 0.1)))
            }
        } verify: { context in
            let records = try context.fetch(FetchDescriptor<ActivityRecord>())
            #expect(records.count == 200)
        }
    }

    @Test("an edit is durable once saved")
    func editsArePersisted() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Edit.store")
            do {
                let container = try TestStore.onDisk(at: url)
                container.mainContext.insert(TimeEntry(title: "Before",
                                                       startedAt: Clock.at(hour: 9),
                                                       endedAt: Clock.at(hour: 10)))
                try container.mainContext.save()
            }
            do {
                let container = try TestStore.onDisk(at: url)
                let entry = try container.mainContext.fetch(FetchDescriptor<TimeEntry>())[0]
                entry.title = "After"
                entry.endedAt = Clock.at(hour: 11)
                try container.mainContext.save()
            }
            let reopened = try TestStore.onDisk(at: url)
            let entry = try reopened.mainContext.fetch(FetchDescriptor<TimeEntry>())[0]
            #expect(entry.title == "After")
            #expect(entry.duration == Clock.hours(2))
        }
    }

    @Test("a delete is durable once saved")
    func deletesArePersisted() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Delete.store")
            do {
                let container = try TestStore.onDisk(at: url)
                container.mainContext.insert(TimeEntry(title: "Doomed",
                                                       startedAt: Clock.at(hour: 9),
                                                       endedAt: Clock.at(hour: 10)))
                try container.mainContext.save()
                let entry = try container.mainContext.fetch(FetchDescriptor<TimeEntry>())[0]
                container.mainContext.delete(entry)
                try container.mainContext.save()
            }
            let reopened = try TestStore.onDisk(at: url)
            let entries = try reopened.mainContext.fetch(FetchDescriptor<TimeEntry>())
            #expect(entries.isEmpty)
        }
    }

    // MARK: - The store on disk

    @Test("the store honours the directory override rather than Application Support")
    func storeURLRespectsOverride() {
        let url = ModelStack.storeURL()
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Span", isDirectory: true)
            .appendingPathComponent("Span.store")
        #expect(url != real, "tests must never open the real store")
        #expect(url.lastPathComponent == "Span.store")
    }

    @Test("a corrupt store is quarantined rather than bricking launch")
    func corruptStoreIsQuarantined() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("Span.store")
            try Data("this is not a database".utf8).write(to: url)

            setenv(ModelStack.storeDirectoryOverrideKey, directory.path, 1)
            defer { setenv(ModelStack.storeDirectoryOverrideKey, "/tmp/span-test-host-store", 1) }

            let container = ModelStack.makeContainer()
            container.mainContext.insert(TimeEntry(title: "Fresh start",
                                                   startedAt: Clock.at(hour: 9),
                                                   endedAt: Clock.at(hour: 10)))
            try container.mainContext.save()

            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(contents.contains { $0.hasPrefix("Recovered-") },
                    "the unreadable store should be kept for recovery, not deleted")
            let entries = try container.mainContext.fetch(FetchDescriptor<TimeEntry>())
            #expect(entries.count == 1)
        }
    }
}
