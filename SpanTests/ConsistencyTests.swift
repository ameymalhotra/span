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

    @Test("BUG: re-filing an app does not re-file the time already recorded for it")
    func rulesDoNotApplyRetroactively() throws {
        AppCategorizer.updateOverrides([])

        // A morning in Safari, recorded while Safari was still "Browsing".
        let record = Fixture.activity(
            in: context, appName: "Safari", bundleIdentifier: "com.apple.Safari",
            from: Clock.at(hour: 9), to: Clock.at(hour: 11), categoryName: "Browsing")
        try context.save()

        // The user then files Safari under Deep Work.
        AppCategoryRule.assign("Deep Work", bundleIdentifier: "com.apple.Safari",
                               appName: "Safari", in: context)

        // The categoriser now agrees...
        #expect(AppCategorizer.category(forBundleIdentifier: "com.apple.Safari", appName: "Safari")
                == "Deep Work")

        // ...and the timeline's own grouping, which re-reads the rules, follows.
        let merged = TimelineBlock.mergedActivityBlocks([record], grouping: .category)
        #expect(merged[0].title == "Deep Work")

        // But the day's breakdown reads the category stored on the record, so
        // it still reports the old one. The rail and the breakdown now disagree
        // about the same two hours.
        let report = DayReport(day: Clock.dayStart, sessions: [], entries: [],
                               activity: [record], now: Clock.at(hour: 12))
        #expect(report.categories.map(\.name) == ["Browsing"])
        #expect(report.categories.first?.name != merged[0].title,
                "the breakdown and the timeline disagree about this record")

        AppCategorizer.updateOverrides([])
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

    @Test("finishing a session leaves a review owed, so a caller that drops it loses the prompt")
    func finishingOwesAReview() throws {
        // RootView keeps the returned session and presents the review sheet.
        // MenuBarPanelView and HUDPillView call the same method and discard the
        // result, so this is what they throw away.
        let model = AppModel(container: container)
        model.startSession(title: "Write", category: "Deep Work", minutes: 30)

        let finished = try #require(model.finishSession())
        #expect(finished.needsReflection, "the finished session still owes a review")
        #expect(finished.focusRating == nil)
        #expect(finished.honestWorkMinutes == nil)

        // Left unanswered, the day counts it as finished but unreviewed — the
        // honest-work number silently under-reports.
        let report = DayReport(day: Clock.dayStart, sessions: [finished], entries: [],
                               activity: [], now: Date.now)
        #expect(report.completedCount == 1)
        #expect(report.reflectedCount == 0)
        #expect(report.honestWorkTime == 0)
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
