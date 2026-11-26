import Foundation
import SwiftData
import Testing
@testable import Span

/// Record removal and timer state must agree across every window. Nothing in
/// this suite uses the real store or calls either resetEverything method.
@MainActor
@Suite("Timer lifecycle", .serialized)
struct TimerLifecycleTests {
    private func withModel(_ body: (AppModel, ModelContainer) throws -> Void) throws {
        let name = "SpanTests.Timers.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let container = try TestStore.inMemory()
        let model = AppModel(container: container, logPreferences: preferences)
        model.idleClock = { 0 }
        defer {
            model.reconcileTimerState()
            if let session = model.activeSession { NotificationService.cancelReminder(for: session) }
            model.endBreak(resumingWork: false)
            model.stop()
        }
        try body(model, container)
    }

    @Test("saving a direct session deletion clears every cached timer immediately")
    func directDeletion() throws {
        try withModel { model, container in
            let context = container.mainContext
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            #expect(NotificationService.armedSessionID == session.id)
            context.delete(session)
            try context.save()
            #expect(model.activeSession == nil)
            #expect(model.sessionClock == "00:00")
            #expect(!model.sessionIsOvertime)
            #expect(NotificationService.armedSessionID == nil)
            #expect(model.pendingReflection == nil)
            #expect(!model.offersBreakAfterReview)
        }
    }

    @Test("deleting work in a second context stops the first context's timer")
    func deletionInAnotherContext() throws {
        try withModel { model, container in
            _ = model.startSession(title: "Read", category: "Work", minutes: 25)
            let other = ModelContext(container)
            let session = try #require(try other.fetch(FetchDescriptor<WorkSession>()).first)
            other.delete(session)
            try other.save()
            #expect(model.activeSession == nil)
            #expect(model.sessionClock == "00:00")
            #expect(NotificationService.armedSessionID == nil)
        }
    }

    @Test("a removed session cannot be extended, finished, or reopened by stale controls")
    func staleControlsCannotReviveWork() throws {
        try withModel { model, container in
            let context = container.mainContext
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            context.delete(session)
            try context.save()
            model.extendSession(byMinutes: 5)
            model.pauseSession()
            model.resumeSession()
            #expect(model.finishSession() == nil)
            #expect(!model.resumeSession(session, endingAt: .now.addingTimeInterval(600)))
            #expect(try context.fetch(FetchDescriptor<WorkSession>()).isEmpty)
            #expect(model.pendingReflection == nil)
        }
    }

    @Test("removing a finished session clears its pending review and break offer")
    func deletedReview() throws {
        try withModel { model, container in
            _ = model.startSession(title: "Read", category: "Work", minutes: 25)
            let session = try #require(model.finishSession())
            #expect(model.pendingReflection != nil)
            #expect(model.offersBreakAfterReview)
            container.mainContext.delete(session)
            try container.mainContext.save()
            #expect(model.pendingReflection == nil)
            #expect(!model.offersBreakAfterReview)
        }
    }

    @Test("removing an editor's time block clears its pending presentation")
    func deletedBlockEditor() throws {
        try withModel { model, container in
            model.addBlock(on: .now)
            let entry = try #require(model.pendingBlockEdit)
            container.mainContext.delete(entry)
            try container.mainContext.save()
            #expect(model.pendingBlockEdit == nil)
            model.startSession(from: entry)
            #expect(model.activeSession == nil)
            #expect(try container.mainContext.fetch(FetchDescriptor<WorkSession>()).isEmpty)
        }
    }

    @Test("removing a running break cancels it without resuming paused work")
    func directBreakDeletion() throws {
        try withModel { model, container in
            let context = container.mainContext
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            model.startBreak(minutes: 5)
            let record = try #require(try context.fetch(FetchDescriptor<BreakRecord>()).first)
            context.delete(record)
            try context.save()
            #expect(!model.isOnBreak)
            #expect(model.breakClock == "00:00")
            #expect(model.breakLength == 0)
            #expect(!model.sessionPausedForBreak)
            #expect(session.status == .paused)
            model.endBreak()
            #expect(session.status == .paused)
        }
    }

    @Test("a break deleted in a second context cannot keep counting down")
    func breakDeletionInAnotherContext() throws {
        try withModel { model, container in
            model.startBreak(minutes: 5)
            let other = ModelContext(container)
            let record = try #require(try other.fetch(FetchDescriptor<BreakRecord>()).first)
            other.delete(record)
            try other.save()
            #expect(!model.isOnBreak)
            #expect(model.breakClock == "00:00")
            model.finishBreakIfDue(at: .now.addingTimeInterval(600))
            #expect(model.activeSession == nil)
        }
    }

    @Test("resuming work ends and records its break instead of running both timers")
    func resumeEndsBreak() throws {
        try withModel { model, container in
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            model.startBreak(minutes: 5)
            let record = try #require(try container.mainContext.fetch(FetchDescriptor<BreakRecord>()).first)
            model.resumeSession()
            #expect(session.status == .active)
            #expect(!model.isOnBreak)
            #expect(!model.sessionPausedForBreak)
            #expect(model.breakClock == "00:00")
            #expect(record.endedAt != nil)
            #expect(NotificationService.armedSessionID == session.id)
        }
    }

    @Test("finishing during a break leaves a standalone break with no work to resume")
    func finishDuringBreak() throws {
        try withModel { model, _ in
            _ = model.startSession(title: "Read", category: "Work", minutes: 25)
            model.startBreak(minutes: 5)
            _ = model.finishSession()
            #expect(model.isOnBreak)
            #expect(!model.sessionPausedForBreak)
            #expect(!model.offersBreakAfterReview)
            model.endBreak()
            #expect(model.activeSession == nil)
            #expect(NotificationService.armedSessionID == nil)
        }
    }

    @Test("extending paused work does not arm a countdown alert")
    func extendPausedWork() throws {
        try withModel { model, _ in
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            model.pauseSession()
            model.extendSession(byMinutes: 5)
            #expect(session.plannedMinutes == 30)
            #expect(session.status == .paused)
            #expect(NotificationService.armedSessionID == nil)
        }
    }

    @Test("changing a paused session's planned length does not arm an alert")
    func editPausedDuration() throws {
        try withModel { model, _ in
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            model.pauseSession()
            model.setPlannedMinutes(40, for: session)
            #expect(session.plannedMinutes == 40)
            #expect(NotificationService.armedSessionID == nil)
        }
    }

    @Test("cancelling a historical session's reminder leaves the current chime armed")
    func unrelatedReminderCancellation() throws {
        try withModel { model, _ in
            let past = try #require(model.startSession(title: "Past", category: "Work", minutes: 25))
            model.finishSession()
            let current = try #require(model.startSession(title: "Current", category: "Work", minutes: 25))
            NotificationService.cancelReminder(for: past)
            #expect(NotificationService.armedSessionID == current.id)
            model.setPlannedMinutes(40, for: past)
            #expect(NotificationService.armedSessionID == current.id)
        }
    }

    @Test("block conversion refuses a second session even when the cached timer is empty")
    func blockConversionFindsStoredWork() throws {
        try withModel { model, container in
            let context = container.mainContext
            let stored = WorkSession(title: "Existing", plannedMinutes: 25)
            stored.beginSegment()
            context.insert(stored)
            let entry = TimeEntry(title: "Block", startedAt: .now, endedAt: .now.addingTimeInterval(600))
            context.insert(entry)
            try context.save()
            #expect(model.activeSession == nil)
            model.startSession(from: entry)
            #expect(model.activeSession?.id == stored.id)
            #expect(try context.fetch(FetchDescriptor<WorkSession>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<TimeEntry>()).count == 1)
        }
    }

    @Test("read-only break deletion reports failure and preserves the record")
    func readOnlyBreakDeletion() throws {
        try TestStore.withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("ReadOnly.store")
            do {
                let container = try TestStore.onDisk(at: url)
                ModelStack.seedCategoriesIfNeeded(in: container.mainContext)
                let record = BreakRecord(startedAt: .now, plannedEnd: .now.addingTimeInterval(300))
                container.mainContext.insert(record)
                try container.mainContext.save()
            }
            let container = try ModelContainer(for: ModelStack.schema,
                configurations: ModelConfiguration(url: url, allowsSave: false))
            let model = AppModel(container: container)
            defer { model.stop() }
            let record = try #require(try container.mainContext.fetch(FetchDescriptor<BreakRecord>()).first)
            #expect(throws: CocoaError.self) { try model.deleteBreak(record) }
            #expect(try container.mainContext.fetch(FetchDescriptor<BreakRecord>()).count == 1)
        }
    }

    @Test("another window's deleted finished session cannot be reopened")
    func staleFinishedSessionFromAnotherContext() throws {
        try withModel { model, container in
            let session = try #require(model.startSession(title: "Read", category: "Work", minutes: 25))
            model.finishSession()
            let other = ModelContext(container)
            let copy = try #require(try other.fetch(FetchDescriptor<WorkSession>()).first)
            other.delete(copy)
            try other.save()
            #expect(!model.resumeSession(session, endingAt: .now.addingTimeInterval(600)))
            model.setPlannedMinutes(40, for: session)
            #expect(model.activeSession == nil)
            #expect(model.pendingReflection == nil)
            #expect(NotificationService.armedSessionID == nil)
            #expect(try other.fetch(FetchDescriptor<WorkSession>()).isEmpty)
        }
    }

    @Test("another window's deleted time block cannot be converted into work")
    func staleBlockFromAnotherContext() throws {
        try withModel { model, container in
            model.addBlock(on: .now)
            let entry = try #require(model.pendingBlockEdit)
            let other = ModelContext(container)
            let copy = try #require(try other.fetch(FetchDescriptor<TimeEntry>()).first)
            other.delete(copy)
            try other.save()
            model.startSession(from: entry)
            #expect(model.activeSession == nil)
            #expect(model.pendingBlockEdit == nil)
            #expect(try other.fetch(FetchDescriptor<WorkSession>()).isEmpty)
            #expect(try other.fetch(FetchDescriptor<TimeEntry>()).isEmpty)
        }
    }


    @Test("new work suppresses the previous session's delayed break offer")
    func newWorkClearsOldBreakOffer() throws {
        try withModel { model, _ in
            _ = model.startSession(title: "Past", category: "Work", minutes: 25)
            let past = try #require(model.finishSession())
            #expect(model.offersBreakAfterReview)
            let current = try #require(model.startSession(title: "Current", category: "Work", minutes: 25))
            #expect(!model.offersBreakAfterReview)
            #expect(model.pendingReflection?.id == past.id)
            #expect(model.activeSession?.id == current.id)
        }
    }

}
