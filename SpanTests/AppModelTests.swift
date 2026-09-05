import Foundation
import SwiftData
import Testing
@testable import Span

/// `AppModel` is what every session button actually calls. These exercise it
/// against an in-memory store, the way `RootView`, the menu bar and the HUD do.
@MainActor
@Suite("AppModel", .serialized)
struct AppModelTests {

    private let container: ModelContainer
    private let model: AppModel
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try TestStore.inMemory()
        model = AppModel(container: container)
    }

    private func sessions() throws -> [WorkSession] {
        try context.fetch(FetchDescriptor<WorkSession>())
    }

    private func entries() throws -> [TimeEntry] {
        try context.fetch(FetchDescriptor<TimeEntry>())
    }

    /// The derived text only changes on the tick. `refreshStats` is private, so
    /// tests drive the real loop: ask for fast updates, let one tick land, stop.
    private func awaitStatsRefresh() async {
        model.beginFastUpdates()
        try? await Task.sleep(for: .milliseconds(80))
        model.stop()
    }

    // MARK: - Starting

    @Test("starting a session stores it, opens a run and makes it the active one")
    func startSession() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)

        let stored = try sessions()
        #expect(stored.count == 1)
        #expect(stored[0].title == "Write")
        #expect(stored[0].category == "Deep Work")
        #expect(stored[0].plannedMinutes == 45)
        #expect(stored[0].status == .active)
        #expect(stored[0].segments.count == 1)
        #expect(stored[0].openSegment != nil)
        #expect(model.activeSession?.id == stored[0].id)
    }

    @Test("a started session is saved, not just held in memory")
    func startSessionPersists() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<WorkSession>()).count == 1)
    }

    @Test("an empty category is stored as given rather than defaulted")
    func startSessionKeepsEmptyCategory() throws {
        model.startSession(title: "Untitled", category: "", minutes: 30)
        #expect(try sessions()[0].category.isEmpty)
    }

    @Test("a second session cannot be started while one is running")
    func startSessionRefusesASecond() throws {
        let first = try #require(model.startSession(title: "First", category: "Deep Work", minutes: 60))
        let second = model.startSession(title: "Second", category: "Admin", minutes: 30)

        #expect(second == nil, "a second session was started on top of a running one")

        let stored = try sessions()
        #expect(stored.count == 1)
        #expect(stored[0].title == "First")
        #expect(stored.filter { $0.status == .active }.count == 1)
        #expect(model.activeSession?.id == first.id, "the running session is still the reachable one")
    }

    @Test("a session already running in the store also blocks a new one")
    func startSessionRefusesWhenTheStoreAlreadyHasOne() throws {
        // A fresh model has not seen the store yet: `activeSession` is nil even
        // though one is running, which is the state after a relaunch.
        Fixture.session(in: context, title: "Recovered", startedAt: Date.now, status: .active,
                        segments: [(Date.now, nil)])
        try context.save()

        let started = model.startSession(title: "New", category: "Admin", minutes: 30)

        #expect(started == nil)
        #expect(try sessions().count == 1)
        #expect(model.activeSession?.title == "Recovered")
    }

    @Test("a session can be started again once the first has finished")
    func startSessionAllowedAfterFinishing() throws {
        model.startSession(title: "First", category: "Deep Work", minutes: 60)
        model.finishSession()

        let second = model.startSession(title: "Second", category: "Admin", minutes: 30)
        #expect(second != nil)
        #expect(try sessions().count == 2)
        #expect(model.activeSession?.title == "Second")
    }

    @Test("a paused session still blocks a new one")
    func startSessionRefusedWhilePaused() throws {
        model.startSession(title: "First", category: "Deep Work", minutes: 60)
        model.pauseSession()

        #expect(model.startSession(title: "Second", category: "Admin", minutes: 30) == nil)
        #expect(try sessions().count == 1)
    }

    // MARK: - Pause, resume, finish

    @Test("pause and resume move the session through its states")
    func pauseAndResume() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        let session = try #require(model.activeSession)

        model.pauseSession()
        #expect(session.status == .paused)
        #expect(session.openSegment == nil)

        model.resumeSession()
        #expect(session.status == .active)
        #expect(session.segments.count == 2)
        #expect(session.openSegment != nil)
    }

    @Test("pausing with nothing running is harmless")
    func pauseWithoutSession() {
        model.pauseSession()
        model.resumeSession()
        #expect(model.activeSession == nil)
    }

    @Test("finishing returns the session so the reflection sheet can be offered")
    func finishReturnsTheSession() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        let finished = model.finishSession()

        #expect(finished != nil)
        #expect(finished?.title == "Write")
        #expect(finished?.status == .completed)
        #expect(finished?.endedAt != nil)
        #expect(finished?.openSegment == nil)
        #expect(model.activeSession == nil)
        #expect(finished?.needsReflection == true)
    }

    @Test("finishing with nothing running returns nothing")
    func finishWithoutSession() {
        #expect(model.finishSession() == nil)
    }

    @Test("a finished session stays finished in the store")
    func finishPersists() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        model.finishSession()

        let fresh = ModelContext(container)
        let reloaded = try fresh.fetch(FetchDescriptor<WorkSession>())
        #expect(reloaded.count == 1)
        #expect(reloaded[0].status == .completed)
    }

    @Test("finishing a paused session banks the pause")
    func finishFromPaused() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        model.pauseSession()
        let finished = try #require(model.finishSession())
        #expect(finished.status == .completed)
        #expect(finished.pausedAt == nil)
    }

    // MARK: - Extending

    @Test("extending adds to the planned time")
    func extendSession() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        model.extendSession(byMinutes: 5)
        #expect(model.activeSession?.plannedMinutes == 50)

        model.extendSession(byMinutes: 15)
        #expect(model.activeSession?.plannedMinutes == 65)
    }

    @Test("extending with nothing running is harmless")
    func extendWithoutSession() {
        model.extendSession(byMinutes: 5)
        #expect(model.activeSession == nil)
    }

    @Test("an extension is saved")
    func extendPersists() throws {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        model.extendSession(byMinutes: 5)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<WorkSession>())[0].plannedMinutes == 50)
    }

    // MARK: - Adding a block by hand

    @Test("a block added today lands on a five-minute boundary")
    func addBlockToday() throws {
        model.addBlock(on: Date.now)

        let stored = try entries()
        #expect(stored.count == 1)
        let entry = stored[0]
        let secondsIntoTheHour = entry.startedAt.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 300)
        #expect(abs(secondsIntoTheHour) < 0.001, "the start should snap to five minutes")
        #expect(entry.duration == 1800)
        #expect(abs(entry.startedAt.timeIntervalSince(Date.now)) < 300)
    }

    @Test("a block added to a past day starts at nine in the morning")
    func addBlockOnAPastDay() throws {
        let pastDay = Calendar.current.date(byAdding: .day, value: -3, to: Date.now)!
        model.addBlock(on: pastDay)

        let entry = try #require(entries().first)
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: entry.startedAt)
        #expect(components.hour == 9)
        #expect(components.minute == 0)
        #expect(components.second == 0)
        #expect(Calendar.current.isDate(entry.startedAt, inSameDayAs: pastDay))
    }

    @Test("a new block is blank, so the editor opens on an empty form")
    func addBlockIsBlank() throws {
        model.addBlock(on: Date.now)
        let entry = try #require(entries().first)
        #expect(entry.title.isEmpty)
        #expect(entry.category.isEmpty)
    }

    @Test("the block length is configurable")
    func addBlockCustomLength() throws {
        model.addBlock(on: Date.now, minutes: 90)
        #expect(try entries()[0].duration == 5400)
    }

    @Test("a new block is handed to the timeline for editing")
    func addBlockRequestsAnEdit() throws {
        model.addBlock(on: Date.now)
        #expect(model.pendingBlockEdit != nil)
        #expect(model.pendingBlockEdit?.id == (try entries()[0].id))
    }

    @Test("a new block is saved immediately")
    func addBlockPersists() throws {
        model.addBlock(on: Date.now)
        let fresh = ModelContext(container)
        #expect(try fresh.fetch(FetchDescriptor<TimeEntry>()).count == 1)
    }

    // MARK: - Derived display values

    @Test("the clock reads zero with nothing running")
    func clockIdle() {
        #expect(model.sessionClock == "00:00")
    }

    @Test("the clock counts down from the planned time")
    func clockCountsDown() {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        // Just started, so the remaining time is the planned time bar a moment.
        #expect(model.sessionClock.hasPrefix("44:5") || model.sessionClock == "45:00")
    }

    @Test("finishing puts the clock back to zero")
    func clockResetsOnFinish() {
        model.startSession(title: "Write", category: "Deep Work", minutes: 45)
        model.finishSession()
        #expect(model.sessionClock == "00:00")
    }

    @Test("today's focus starts at nothing")
    func focusTodayStartsEmpty() {
        #expect(model.focusTodayText == "0m")
        #expect(model.percentOfTargetText == "0%")
        #expect(model.focusFraction == 0)
    }

    @Test("today's focus counts a session that has been running")
    func focusTodayCountsRunningSession() async throws {
        let started = Date.now.addingTimeInterval(-Clock.minutes(90))
        Fixture.session(in: context, startedAt: started, status: .active,
                        segments: [(started, nil)])
        try context.save()

        await awaitStatsRefresh()
        #expect(model.focusTodayText == "1h 30m")
    }

    @Test("the target percentage tracks the goal")
    func percentOfTarget() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "dailyFocusTargetMinutes")
        defer {
            if let original { defaults.set(original, forKey: "dailyFocusTargetMinutes") }
            else { defaults.removeObject(forKey: "dailyFocusTargetMinutes") }
        }

        model.dailyFocusTargetMinutes = 120
        let started = Date.now.addingTimeInterval(-Clock.minutes(60))
        Fixture.session(in: context, startedAt: started, status: .completed,
                        segments: [(started, Date.now)])
        try context.save()

        await awaitStatsRefresh()
        #expect(model.percentOfTargetText == "50%")
        #expect(abs(model.focusFraction - 0.5) < 0.01)
    }

    @Test("a zero target does not divide by zero")
    func zeroTargetIsGuarded() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "dailyFocusTargetMinutes")
        defer {
            if let original { defaults.set(original, forKey: "dailyFocusTargetMinutes") }
            else { defaults.removeObject(forKey: "dailyFocusTargetMinutes") }
        }

        model.dailyFocusTargetMinutes = 0
        let started = Date.now.addingTimeInterval(-Clock.minutes(60))
        Fixture.session(in: context, startedAt: started, status: .completed,
                        segments: [(started, Date.now)])
        try context.save()

        await awaitStatsRefresh()
        #expect(model.focusFraction.isFinite)
        #expect(model.percentOfTargetText.hasSuffix("%"))
    }

    @Test("the target ring moves in visible steps rather than every frame")
    func focusFractionIsQuantised() async throws {
        let started = Date.now.addingTimeInterval(-Clock.minutes(60))
        Fixture.session(in: context, startedAt: started, status: .completed,
                        segments: [(started, Date.now)])
        try context.save()
        await awaitStatsRefresh()

        let steps = model.focusFraction * 200
        #expect(abs(steps - steps.rounded()) < 0.000_001)
    }

    @Test("a session running across midnight counts its share of today")
    func focusTodayCountsTheShareAfterMidnight() async throws {
        // Begun 30 minutes before midnight, still running 30 minutes after it:
        // half belongs to today, and the number must not reset at midnight.
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date.now)
        let startedYesterday = todayStart.addingTimeInterval(-Clock.minutes(30))

        Fixture.session(in: context, startedAt: startedYesterday, status: .active,
                        segments: [(startedYesterday, nil)])
        try context.save()

        await awaitStatsRefresh()

        // Only the part since midnight, so the hours before it are not counted
        // twice. Compared loosely because the session is still running.
        #expect(model.focusTodayText != "0m", "the running session is not counted at all")
        let sinceMidnight = Date.now.timeIntervalSince(todayStart)
        #expect(model.focusTodayText == Format.compact(sinceMidnight))
    }

    @Test("a session finished before midnight does not leak into today")
    func focusTodayIgnoresYesterdaysSessions() async throws {
        let todayStart = Calendar.current.startOfDay(for: Date.now)
        let start = todayStart.addingTimeInterval(-Clock.hours(3))
        let end = todayStart.addingTimeInterval(-Clock.hours(1))
        Fixture.session(in: context, startedAt: start, endedAt: end, status: .completed,
                        segments: [(start, end)])
        try context.save()

        await awaitStatsRefresh()
        #expect(model.focusTodayText == "0m")
    }

    @Test("time since the last break reads as unknown with nothing tracked")
    func sinceBreakWithoutActivity() async {
        await awaitStatsRefresh()
        #expect(model.sinceBreakText == "—")
    }

    @Test("pausing tracking blanks the since-break stat")
    func sinceBreakWhileTrackingPaused() async {
        model.tracker.isPaused = true
        await awaitStatsRefresh()
        #expect(model.sinceBreakText == "—")
        model.tracker.isPaused = false
    }

    @Test("time since the last break is reported once there is activity")
    func sinceBreakWithActivity() async throws {
        let base = Date.now.addingTimeInterval(-Clock.minutes(45))
        Fixture.activity(in: context, from: base, to: Date.now.addingTimeInterval(-30))
        try context.save()

        await awaitStatsRefresh()
        #expect(model.sinceBreakText != "—")
    }

    // MARK: - The tick loop

    @Test("the fast-update count never goes negative")
    func fastUpdateRefcount() {
        model.endFastUpdates()
        model.endFastUpdates()
        model.beginFastUpdates()
        model.endFastUpdates()
        model.endFastUpdates()
        // No crash and no runaway loop; stop tears the loop down cleanly.
        model.stop()
    }

    @Test("the selected day starts at today, at midnight")
    func selectedDateDefault() {
        #expect(model.selectedDate == Calendar.current.startOfDay(for: Date.now))
    }
}
