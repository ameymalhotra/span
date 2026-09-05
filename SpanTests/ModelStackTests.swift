import Foundation
import SwiftData
import Testing
@testable import Span

@MainActor
@Suite("ModelStack recovery and seeding", .serialized)
struct ModelStackTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws { container = try TestStore.inMemory() }

    private func sessions() throws -> [WorkSession] {
        try context.fetch(FetchDescriptor<WorkSession>())
    }

    // MARK: - recoverStaleSessions

    @Test("a session left running overnight is closed at its last known good moment")
    func staleSessionIsClosed() throws {
        let now = Clock.at(hour: 9)
        let yesterday = now.addingTimeInterval(-Clock.hours(20))
        let session = Fixture.session(
            in: context, startedAt: yesterday, status: .active,
            segments: [(yesterday, yesterday.addingTimeInterval(Clock.hours(2)))])

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(session.status == .completed)
        #expect(session.endedAt == yesterday.addingTimeInterval(Clock.hours(2)))
    }

    @Test("a session paused moments ago is left alone")
    func recentSessionSurvives() throws {
        let now = Clock.at(hour: 9)
        let session = Fixture.session(
            in: context, startedAt: now.addingTimeInterval(-Clock.minutes(30)), status: .active,
            segments: [(now.addingTimeInterval(-Clock.minutes(30)),
                        now.addingTimeInterval(-Clock.minutes(2)))])

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(session.status == .active)
        #expect(session.endedAt == nil)
    }

    @Test("a session goes stale once it passes the grace period")
    func gracePeriodBoundary() throws {
        let now = Clock.at(hour: 9)
        let session = Fixture.session(
            in: context, startedAt: now.addingTimeInterval(-Clock.hours(2)), status: .active,
            segments: [(now.addingTimeInterval(-Clock.hours(2)),
                        now.addingTimeInterval(-Clock.minutes(20)))])

        ModelStack.recoverStaleSessions(in: context, now: now, grace: 15 * 60)
        #expect(session.status == .completed)
    }

    @Test("the grace period is configurable")
    func customGrace() throws {
        let now = Clock.at(hour: 9)
        let session = Fixture.session(
            in: context, startedAt: now.addingTimeInterval(-Clock.hours(2)), status: .active,
            segments: [(now.addingTimeInterval(-Clock.hours(2)),
                        now.addingTimeInterval(-Clock.minutes(20)))])

        ModelStack.recoverStaleSessions(in: context, now: now, grace: 60 * 60)
        #expect(session.status == .active)
    }

    @Test("a session recent in clock terms but from yesterday is still closed")
    func recencyRequiresTheSameDay() throws {
        // 00:05, with the session last seen at 23:58 the night before: seven
        // minutes ago, but a different day, so it is not resumable.
        let now = Clock.date(2025, 9, 4, 0, 5)
        let lastSeen = Clock.date(2025, 9, 3, 23, 58)
        let session = Fixture.session(
            in: context, startedAt: Clock.date(2025, 9, 3, 22, 0), status: .active,
            segments: [(Clock.date(2025, 9, 3, 22, 0), lastSeen)])

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(session.status == .completed)
        #expect(session.endedAt == lastSeen)
    }

    @Test("a paused session is closed at the moment it was paused")
    func pausedSessionClosesAtPause() throws {
        let now = Clock.at(hour: 9)
        let pausedAt = now.addingTimeInterval(-Clock.hours(3))
        let session = Fixture.session(
            in: context, startedAt: now.addingTimeInterval(-Clock.hours(5)),
            pausedAt: pausedAt, status: .paused,
            segments: [(now.addingTimeInterval(-Clock.hours(5)), pausedAt)])

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(session.status == .completed)
        #expect(session.endedAt == pausedAt)
    }

    @Test("a completed session is never touched")
    func completedSessionsUntouched() throws {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 1), endedAt: Clock.at(hour: 2),
            status: .completed, segments: [(Clock.at(hour: 1), Clock.at(hour: 2))])

        ModelStack.recoverStaleSessions(in: context, now: Clock.at(hour: 20))

        #expect(session.endedAt == Clock.at(hour: 2))
    }

    @Test("several stale sessions are all closed")
    func manyStaleSessions() throws {
        let now = Clock.at(hour: 20)
        for hour in [1.0, 3.0, 5.0] {
            Fixture.session(in: context, startedAt: Clock.at(hour: hour), status: .active,
                            segments: [(Clock.at(hour: hour), Clock.at(hour: hour + 1))])
        }

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(try sessions().allSatisfy { $0.status == .completed })
    }

    @Test("an empty store is handled without complaint")
    func emptyStoreRecovers() throws {
        ModelStack.recoverStaleSessions(in: context, now: Clock.at(hour: 9))
        #expect(try sessions().isEmpty)
    }

    @Test("a session predating segments gets one synthesised so it still draws")
    func legacySessionGetsASegment() throws {
        let now = Clock.at(hour: 20)
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), pausedAt: Clock.at(hour: 10),
            status: .paused)
        #expect(session.segments.isEmpty)

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(session.segments.count == 1)
        #expect(session.segments[0].startedAt == Clock.at(hour: 9))
        #expect(session.segments[0].endedAt == Clock.at(hour: 10))
        #expect(session.status == .completed)
    }

    @Test("a segment-less running session is closed at its start and records no time")
    func legacyRunningSessionRecordsNothing() throws {
        // An active session from before segments existed has neither endedAt nor
        // pausedAt, so there is no moment recovery can vouch for beyond the
        // start. It is closed there: the run is properly closed — no open
        // segment is left behind — but the session ends up recording zero time
        // however long it actually ran. Only stores predating segments can
        // reach this, and the alternative would be inventing a duration.
        let now = Clock.at(hour: 20)
        let session = Fixture.session(in: context, startedAt: Clock.at(hour: 9), status: .active)

        ModelStack.recoverStaleSessions(in: context, now: now)

        #expect(session.status == .completed)
        #expect(session.endedAt == Clock.at(hour: 9))
        #expect(session.segments.count == 1)
        #expect(session.openSegment == nil, "the synthesised run must not stay open")

        // The point of recovery: elapsed no longer grows against the wall clock.
        #expect(session.elapsed(at: Clock.at(hour: 21)) == 0)
        #expect(session.elapsed(at: Clock.at(hour: 23)) == 0)

        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 23))
        #expect(blocks[0].end == Clock.at(hour: 9))
    }

    @Test("recovery survives a reopen of the context")
    func recoveryIsSaved() throws {
        let now = Clock.at(hour: 20)
        Fixture.session(in: context, startedAt: Clock.at(hour: 9), status: .active,
                        segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])

        ModelStack.recoverStaleSessions(in: context, now: now)

        let fresh = ModelContext(container)
        let reloaded = try fresh.fetch(FetchDescriptor<WorkSession>())
        #expect(reloaded.count == 1)
        #expect(reloaded[0].status == .completed)
    }

    // MARK: - seedCategoriesIfNeeded

    @Test("first launch seeds the default categories")
    func seedsOnFirstLaunch() throws {
        ModelStack.seedCategoriesIfNeeded(in: context)
        let categories = try context.fetch(FetchDescriptor<TimeCategory>())
        #expect(categories.count == TimeCategory.defaults.count)
        #expect(Set(categories.map(\.name)) == Set(TimeCategory.defaults.map(\.0)))
    }

    @Test("seeded categories keep the defined colour and order")
    func seedsWithOrderAndColour() throws {
        ModelStack.seedCategoriesIfNeeded(in: context)
        let categories = try context.fetch(FetchDescriptor<TimeCategory>())
            .sorted { $0.sortIndex < $1.sortIndex }
        #expect(categories.map(\.sortIndex) == Array(0..<TimeCategory.defaults.count))
        for (category, expected) in zip(categories, TimeCategory.defaults) {
            #expect(category.name == expected.0)
            #expect(category.colorSlot == expected.1)
        }
    }

    @Test("seeding a second time changes nothing")
    func seedingIsIdempotent() throws {
        ModelStack.seedCategoriesIfNeeded(in: context)
        ModelStack.seedCategoriesIfNeeded(in: context)
        #expect(try context.fetch(FetchDescriptor<TimeCategory>()).count == TimeCategory.defaults.count)
    }

    @Test("an existing category set is never overwritten")
    func doesNotOverwriteExisting() throws {
        context.insert(TimeCategory(name: "Mine", colorSlot: 3, sortIndex: 0))
        try context.save()

        ModelStack.seedCategoriesIfNeeded(in: context)

        let categories = try context.fetch(FetchDescriptor<TimeCategory>())
        #expect(categories.count == 1)
        #expect(categories[0].name == "Mine")
    }

    @Test("seeding registers the colours for drawing")
    func seedingUpdatesTheRegistry() throws {
        CategoryPalette.updateRegistry([])
        ModelStack.seedCategoriesIfNeeded(in: context)
        #expect(CategoryPalette.color(for: "Deep Work").hexString
                == CategoryPalette.color(slot: 4).hexString)
        CategoryPalette.updateRegistry([])
    }

    @Test("an existing set is registered too, not just a freshly seeded one")
    func existingCategoriesAreRegistered() throws {
        context.insert(TimeCategory(name: "Mine", colorSlot: 3, sortIndex: 0))
        try context.save()
        CategoryPalette.updateRegistry([])

        ModelStack.seedCategoriesIfNeeded(in: context)

        #expect(CategoryPalette.color(for: "Mine").hexString
                == CategoryPalette.color(slot: 3).hexString)
        CategoryPalette.updateRegistry([])
    }

    // MARK: - App rules

    @Test("a user rule overrides the built-in table")
    func appRuleOverridesBuiltIn() throws {
        AppCategorizer.updateOverrides([])
        #expect(AppCategorizer.category(forBundleIdentifier: "com.apple.Safari", appName: "Safari")
                == "Browsing")

        AppCategoryRule.assign("Deep Work", bundleIdentifier: "com.apple.Safari",
                               appName: "Safari", in: context)

        #expect(AppCategorizer.category(forBundleIdentifier: "com.apple.Safari", appName: "Safari")
                == "Deep Work")
        AppCategorizer.updateOverrides([])
    }

    @Test("assigning twice replaces the rule rather than duplicating it")
    func appRuleIsReplaced() throws {
        AppCategorizer.updateOverrides([])
        AppCategoryRule.assign("Deep Work", bundleIdentifier: "com.apple.Safari",
                               appName: "Safari", in: context)
        AppCategoryRule.assign("Off Task", bundleIdentifier: "com.apple.Safari",
                               appName: "Safari", in: context)

        let rules = try context.fetch(FetchDescriptor<AppCategoryRule>())
        #expect(rules.count == 1)
        #expect(AppCategorizer.category(forBundleIdentifier: "com.apple.Safari", appName: "Safari")
                == "Off Task")
        AppCategorizer.updateOverrides([])
    }

    @Test("loadAppRules restores the overrides from the store")
    func loadAppRules() throws {
        context.insert(AppCategoryRule(bundleIdentifier: "com.example.tool",
                                       appName: "Tool", categoryName: "Admin"))
        try context.save()
        AppCategorizer.updateOverrides([])

        ModelStack.loadAppRules(in: context)

        #expect(AppCategorizer.category(forBundleIdentifier: "com.example.tool", appName: "Tool")
                == "Admin")
        AppCategorizer.updateOverrides([])
    }

    @Test("an app filed only under its own name counts as ungrouped")
    func isUngrouped() {
        AppCategorizer.updateOverrides([])
        #expect(AppCategorizer.isUngrouped(bundleIdentifier: "com.example.tool", appName: "Tool"))
        #expect(!AppCategorizer.isUngrouped(bundleIdentifier: "com.apple.Safari", appName: "Safari"))
    }
}
