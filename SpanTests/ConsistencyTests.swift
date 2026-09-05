import Foundation
import SwiftData
import Testing
@testable import Span

/// Where two parts of the app answer the same question, they should agree.
@MainActor
@Suite("Cross-surface consistency", .serialized)
struct ConsistencyTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws { container = try TestStore.inMemory() }

    @Test("re-filing an app also re-files the time already recorded for it")
    func rulesApplyRetroactively() throws {
        AppCategorizer.updateOverrides([])

        // A morning in Safari, recorded while Safari was still "Browsing".
        let record = Fixture.activity(
            in: context, appName: "Safari", bundleIdentifier: "com.apple.Safari",
            from: Clock.at(hour: 9), to: Clock.at(hour: 11), categoryName: "Browsing")
        try context.save()

        func breakdown() -> [String] {
            DayReport(day: Clock.dayStart, sessions: [], entries: [],
                      activity: [record], now: Clock.at(hour: 12)).categories.map(\.name)
        }
        #expect(breakdown() == ["Browsing"])

        // The user files Safari under Deep Work.
        AppCategoryRule.assign("Deep Work", bundleIdentifier: "com.apple.Safari",
                               appName: "Safari", in: context)

        let merged = TimelineBlock.mergedActivityBlocks([record], grouping: .category)
        #expect(merged[0].title == "Deep Work")
        #expect(breakdown() == ["Deep Work"], "the breakdown still reports the old category")
        #expect(TimelineBlock.block(for: record).category == "Deep Work")

        AppCategorizer.updateOverrides([])
    }

    @Test("the timeline and the breakdown name a category the same way")
    func timelineAndBreakdownAgree() throws {
        AppCategorizer.updateOverrides([])
        let records = [
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 10),
                             categoryName: "something stale"),
            Fixture.activity(in: context, appName: "Safari", bundleIdentifier: "com.apple.Safari",
                             from: Clock.at(hour: 10), to: Clock.at(hour: 11),
                             categoryName: "also stale"),
        ]
        try context.save()

        let report = DayReport(day: Clock.dayStart, sessions: [], entries: [],
                               activity: records, now: Clock.at(hour: 12))
        let rail = TimelineBlock.mergedActivityBlocks(records, grouping: .category)

        #expect(Set(report.categories.map(\.name)) == Set(rail.map(\.title)))
        #expect(Set(report.categories.map(\.name)) == ["Building", "Browsing"])
        AppCategorizer.updateOverrides([])
    }

    @Test("a record with no bundle identifier keeps the name it was filed under")
    func recordsWithoutAnIdentifierKeepTheirStoredCategory() throws {
        AppCategorizer.updateOverrides([])
        let record = Fixture.activity(
            in: context, appName: "Some Tool", bundleIdentifier: nil,
            from: Clock.at(hour: 9), to: Clock.at(hour: 10), categoryName: "Admin")
        try context.save()

        // There is nothing to re-resolve from, so the stored answer stands.
        #expect(ActivityRecord.currentCategory(for: record) == "Admin")
        let report = DayReport(day: Clock.dayStart, sessions: [], entries: [],
                               activity: [record], now: Clock.at(hour: 12))
        #expect(report.categories.map(\.name) == ["Admin"])
        AppCategorizer.updateOverrides([])
    }

    @Test("an idle record is still not a category")
    func idleIsNeverCategorised() throws {
        let away = Fixture.activity(in: context, appName: "Away", bundleIdentifier: nil,
                                    from: Clock.at(hour: 9), to: Clock.at(hour: 10), isIdle: true)
        try context.save()
        #expect(TimelineBlock.block(for: away).category == "Away")
        let report = DayReport(day: Clock.dayStart, sessions: [], entries: [],
                               activity: [away], now: Clock.at(hour: 12))
        #expect(report.categories.isEmpty)
    }

    @Test("the day's tracked total is unaffected by how it is grouped")
    func groupingDoesNotChangeTheTotal() throws {
        let records = [
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 10)),
            Fixture.activity(in: context, appName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty",
                             from: Clock.at(hour: 10), to: Clock.at(hour: 11)),
        ]
        let byCategory = TimelineBlock.mergedActivityBlocks(records, grouping: .category)
            .reduce(0) { $0 + $1.duration }
        let byApp = TimelineBlock.mergedActivityBlocks(records, grouping: .app)
            .reduce(0) { $0 + $1.duration }
        #expect(byCategory == byApp)
        #expect(byCategory == Clock.hours(2))
    }

    @Test("finishing queues the review, however the session was finished")
    func finishingQueuesTheReview() throws {
        // Every surface calls finishSession. The menu bar and the HUD have
        // nowhere to present a sheet, so the session is queued on the model and
        // the main window picks it up — rather than the review being dropped.
        let model = AppModel(container: container)
        model.startSession(title: "Write", category: "Deep Work", minutes: 30)

        let finished = try #require(model.finishSession())
        #expect(model.pendingReflection?.id == finished.id,
                "the finished session was not queued for review")
        #expect(finished.needsReflection)

        // Answering it clears the debt.
        finished.focusRating = 4
        finished.honestWorkMinutes = 20
        finished.reflectionState = .completed
        model.pendingReflection = nil

        let report = DayReport(day: Clock.dayStart, sessions: [finished], entries: [],
                               activity: [], now: Date.now)
        #expect(report.completedCount == 1)
        #expect(report.reflectedCount == 1)
        #expect(report.honestWorkTime == Clock.minutes(20))
        model.stop()
    }

    @Test("finishing nothing queues nothing")
    func finishingNothingQueuesNothing() {
        let model = AppModel(container: container)
        #expect(model.finishSession() == nil)
        #expect(model.pendingReflection == nil)
        model.stop()
    }

    @Test("a skipped review still clears the queue")
    func skippingClearsTheQueue() throws {
        let model = AppModel(container: container)
        model.startSession(title: "Write", category: "Deep Work", minutes: 30)
        let finished = try #require(model.finishSession())

        finished.reflectionState = .skipped
        model.pendingReflection = nil

        #expect(!finished.needsReflection)
        #expect(!finished.isReflected)
        model.stop()
    }
}

@Suite("IdleMonitor", .serialized)
struct IdleMonitorTests {

    private func withThreshold(_ minutes: Int?, _ body: () -> Void) {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "idleThresholdMinutes")
        if let minutes { defaults.set(minutes, forKey: "idleThresholdMinutes") }
        else { defaults.removeObject(forKey: "idleThresholdMinutes") }
        body()
        if let original { defaults.set(original, forKey: "idleThresholdMinutes") }
        else { defaults.removeObject(forKey: "idleThresholdMinutes") }
    }

    @Test("the default threshold is five minutes")
    func defaultThreshold() {
        withThreshold(nil) {
            #expect(IdleMonitor.threshold == 300)
        }
    }

    @Test("the threshold follows the setting")
    func configuredThreshold() {
        withThreshold(10) { #expect(IdleMonitor.threshold == 600) }
        withThreshold(2) { #expect(IdleMonitor.threshold == 120) }
        withThreshold(15) { #expect(IdleMonitor.threshold == 900) }
    }

    @Test("a nonsensical threshold is clamped to a minute rather than disabling breaks")
    func thresholdIsClamped() {
        withThreshold(0) { #expect(IdleMonitor.threshold == 60) }
        withThreshold(-5) { #expect(IdleMonitor.threshold == 60) }
    }

    @Test("the idle interval is a real, non-negative measurement")
    func idleIntervalIsSane() {
        let interval = IdleMonitor.idleInterval()
        #expect(interval >= 0)
        #expect(interval.isFinite)
    }
}
