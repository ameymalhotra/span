import Foundation
import SwiftData
import Testing
@testable import Span

@MainActor
@Suite("DayReport")
struct DayReportTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let now = Clock.at(hour: 18)

    init() throws { container = try TestStore.inMemory() }

    private func report(
        sessions: [WorkSession] = [], entries: [TimeEntry] = [], activity: [ActivityRecord] = []
    ) -> DayReport {
        DayReport(day: Clock.dayStart, sessions: sessions, entries: entries,
                  activity: activity, now: now)
    }

    // MARK: - Empty

    @Test("an empty day reports nothing")
    func emptyDay() {
        let report = report()
        #expect(report.blocks.isEmpty)
        #expect(report.focusedTime == 0)
        #expect(report.trackedTime == 0)
        #expect(report.honestWorkTime == 0)
        #expect(report.completedCount == 0)
        #expect(report.reflectedCount == 0)
        #expect(report.distractions == 0)
        #expect(report.categories.isEmpty)
        #expect(report.dayFraction == 0)
    }

    @Test("the empty report is genuinely empty")
    func emptyConstant() {
        #expect(DayReport.empty.blocks.isEmpty)
        #expect(DayReport.empty.focusedTime == 0)
        #expect(DayReport.empty.categories.isEmpty)
    }

    // MARK: - Focused time

    @Test("focused time excludes the pauses inside a session")
    func focusedTimeExcludesPauses() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 11), Clock.at(hour: 11.5)),
        ])
        #expect(report(sessions: [session]).focusedTime == 5400)
    }

    @Test("focused time sums several sessions")
    func focusedTimeSumsSessions() {
        let a = Fixture.session(in: context, segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        let b = Fixture.session(in: context, segments: [(Clock.at(hour: 14), Clock.at(hour: 15))])
        #expect(report(sessions: [a, b]).focusedTime == 7200)
    }

    @Test("a running session counts up to now")
    func focusedTimeCountsRunningSession() {
        let session = Fixture.session(in: context, status: .active,
                                      segments: [(Clock.at(hour: 17), nil)])
        #expect(report(sessions: [session]).focusedTime == 3600)
    }

    // MARK: - Tracked time

    @Test("tracked time counts only time at the keyboard")
    func trackedTimeExcludesIdle() {
        let working = Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 10))
        let away = Fixture.activity(in: context, from: Clock.at(hour: 10), to: Clock.at(hour: 11),
                                    isIdle: true)
        #expect(report(activity: [working, away]).trackedTime == 3600)
    }

    @Test("dayFraction is tracked time over a whole day")
    func dayFraction() {
        let working = Fixture.activity(in: context, from: Clock.at(hour: 0), to: Clock.at(hour: 6))
        #expect(report(activity: [working]).dayFraction == 0.25)
    }

    // MARK: - Honest work and reviews

    @Test("honest work counts only what the user said was real work")
    func honestWorkTime() {
        let reviewed = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 9), Clock.at(hour: 11))],
            focusRating: 3, honestWorkMinutes: 75, reflectionState: .completed)
        let report = report(sessions: [reviewed])
        #expect(report.focusedTime == 7200)
        #expect(report.honestWorkTime == 4500)
    }

    @Test("an unreviewed session contributes no honest work but is not counted as reviewed")
    func unreviewedIsNotZeroRated() {
        let reviewed = Fixture.session(in: context, status: .completed, focusRating: 4,
                                       honestWorkMinutes: 30, reflectionState: .completed)
        let pending = Fixture.session(in: context, status: .completed)
        let report = report(sessions: [reviewed, pending])
        #expect(report.completedCount == 2)
        #expect(report.reflectedCount == 1)
        #expect(report.honestWorkTime == 1800)
    }

    @Test("a skipped review counts as finished but not as reviewed")
    func skippedIsNotReflected() {
        let skipped = Fixture.session(in: context, status: .completed, reflectionState: .skipped)
        let report = report(sessions: [skipped])
        #expect(report.completedCount == 1)
        #expect(report.reflectedCount == 0)
    }

    @Test("a running session is not yet a completed one")
    func runningIsNotCompleted() {
        let running = Fixture.session(in: context, status: .active,
                                      segments: [(Clock.at(hour: 17), nil)])
        let report = report(sessions: [running])
        #expect(report.completedCount == 0)
        #expect(report.focusedTime == 3600)
    }

    @Test("distractions sum over reviewed sessions and tolerate blanks")
    func distractionsSum() {
        let a = Fixture.session(in: context, status: .completed, distractions: 3,
                                reflectionState: .completed)
        let b = Fixture.session(in: context, status: .completed, distractions: nil)
        let c = Fixture.session(in: context, status: .completed, distractions: 2,
                                reflectionState: .completed)
        #expect(report(sessions: [a, b, c]).distractions == 5)
    }

    // MARK: - Categories

    @Test("category totals merge sessions, entries and tracked activity")
    func categoriesMergeSources() {
        let session = Fixture.session(in: context, category: "Deep Work",
                                      segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        let entry = Fixture.entry(in: context, category: "Deep Work",
                                  from: Clock.at(hour: 14), to: Clock.at(hour: 15))
        let activity = Fixture.activity(in: context, from: Clock.at(hour: 16), to: Clock.at(hour: 17),
                                        categoryName: "Building")
        let report = report(sessions: [session], entries: [entry], activity: [activity])

        let deepWork = report.categories.first { $0.name == "Deep Work" }
        #expect(deepWork?.duration == 7200)
        #expect(report.categories.first { $0.name == "Building" }?.duration == 3600)
    }

    @Test("categories are sorted longest first")
    func categoriesSorted() {
        let short = Fixture.entry(in: context, category: "Admin",
                                  from: Clock.at(hour: 9), to: Clock.at(hour: 9.25))
        let long = Fixture.entry(in: context, category: "Deep Work",
                                 from: Clock.at(hour: 10), to: Clock.at(hour: 13))
        let middle = Fixture.entry(in: context, category: "Meeting",
                                   from: Clock.at(hour: 14), to: Clock.at(hour: 15))
        let report = report(entries: [short, long, middle])
        #expect(report.categories.map(\.name) == ["Deep Work", "Meeting", "Admin"])
    }

    @Test("fractions are each category's share and add up to one")
    func categoryFractions() {
        let a = Fixture.entry(in: context, category: "A", from: Clock.at(hour: 9), to: Clock.at(hour: 12))
        let b = Fixture.entry(in: context, category: "B", from: Clock.at(hour: 12), to: Clock.at(hour: 13))
        let report = report(entries: [a, b])
        #expect(report.categories.first { $0.name == "A" }?.fraction == 0.75)
        #expect(report.categories.first { $0.name == "B" }?.fraction == 0.25)
        #expect(abs(report.categories.reduce(0) { $0 + $1.fraction } - 1) < 0.000_001)
    }

    @Test("uncategorised time gets its own named bucket")
    func uncategorisedBucket() {
        let entry = Fixture.entry(in: context, category: "",
                                  from: Clock.at(hour: 9), to: Clock.at(hour: 10))
        #expect(report(entries: [entry]).categories.map(\.name) == ["Uncategorised"])
    }

    @Test("idle time is left out of the category totals")
    func idleNotCategorised() {
        let away = Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 10),
                                    isIdle: true, categoryName: "Away")
        #expect(report(activity: [away]).categories.isEmpty)
    }

    @Test("a zero-length day of records produces no divide-by-zero")
    func zeroTotalFractions() {
        let moment = Clock.at(hour: 9)
        let entry = Fixture.entry(in: context, category: "A", from: moment, to: moment)
        let report = report(entries: [entry])
        #expect(report.categories.first?.fraction == 0)
    }

    @Test("a category total exposes a colour without touching the registry")
    func categoryTotalColour() {
        let entry = Fixture.entry(in: context, category: "Deep Work",
                                  from: Clock.at(hour: 9), to: Clock.at(hour: 10))
        #expect(report(entries: [entry]).categories.first?.color != nil)
    }

    // MARK: - Blocks

    @Test("blocks cover all three sources")
    func blocksCoverEverySource() {
        let session = Fixture.session(in: context, segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        let entry = Fixture.entry(in: context, from: Clock.at(hour: 11), to: Clock.at(hour: 12))
        let activity = Fixture.activity(in: context, from: Clock.at(hour: 13), to: Clock.at(hour: 14))
        let report = report(sessions: [session], entries: [entry], activity: [activity])
        #expect(Set(report.blocks.map(\.kind)) == [.session, .entry, .activity])
    }

    @Test("the report draws activity unmerged, unlike the timeline")
    func reportDoesNotMergeActivity() {
        // DayTimelineView merges adjacent records into readable bands; the
        // report keeps one block per record. Worth knowing when comparing the
        // two: the same day yields different block counts.
        let records = (0..<5).map { index in
            Fixture.activity(in: context,
                             from: Clock.at(hour: 9 + Double(index) * 0.1),
                             to: Clock.at(hour: 9 + Double(index + 1) * 0.1))
        }
        let report = report(activity: records)
        #expect(report.blocks.count == 5)
        #expect(TimelineBlock.mergedActivityBlocks(records).count == 1)
    }

    // MARK: - Edge cases

    @Test("a record whose end precedes its start contributes nothing")
    func backwardsRecord() {
        let record = Fixture.activity(in: context, from: Clock.at(hour: 10), to: Clock.at(hour: 9))
        let report = report(activity: [record])
        #expect(report.trackedTime == 0)
        #expect(report.blocks.first?.duration == 0)
    }

    @Test("a session running past midnight is counted in full on the day it started")
    func sessionAcrossMidnight() {
        // The caller filters by day; the report itself counts whatever it is
        // handed, so a late session's full length lands on the starting day.
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 23), Clock.at(hour: 25)),
        ])
        #expect(report(sessions: [session]).focusedTime == 7200)
    }

    // MARK: - lastBreakEnd

    @Test("with no activity there is no last break")
    func lastBreakEndEmpty() {
        #expect(DayReport.lastBreakEnd(in: [], threshold: 300) == nil)
    }

    @Test("an idle span ends at the moment work resumed")
    func lastBreakEndFromIdle() {
        let base = Date.now.addingTimeInterval(-3600)
        let away = Fixture.activity(in: context, from: base, to: base.addingTimeInterval(600),
                                    isIdle: true)
        let back = Fixture.activity(in: context, from: base.addingTimeInterval(600), to: Date.now)
        #expect(DayReport.lastBreakEnd(in: [away, back], threshold: 300) == away.endedAt)
    }

    @Test("a gap in the recording counts as a break too")
    func lastBreakEndFromRecordingGap() {
        let base = Date.now.addingTimeInterval(-7200)
        let before = Fixture.activity(in: context, from: base, to: base.addingTimeInterval(600))
        let after = Fixture.activity(in: context, from: base.addingTimeInterval(3600), to: Date.now)
        #expect(DayReport.lastBreakEnd(in: [before, after], threshold: 300) == after.startedAt)
    }

    @Test("a gap shorter than the threshold is not a break")
    func lastBreakEndIgnoresShortGap() {
        let base = Date.now.addingTimeInterval(-3600)
        let before = Fixture.activity(in: context, from: base, to: base.addingTimeInterval(600))
        let after = Fixture.activity(in: context, from: base.addingTimeInterval(700), to: Date.now)
        #expect(DayReport.lastBreakEnd(in: [before, after], threshold: 300) == nil)
    }

    @Test("a trailing gap means we cannot vouch for any recent work")
    func lastBreakEndTrailingGap() {
        let base = Date.now.addingTimeInterval(-7200)
        let stale = Fixture.activity(in: context, from: base, to: base.addingTimeInterval(600),
                                     isIdle: true)
        #expect(DayReport.lastBreakEnd(in: [stale], threshold: 300) == nil)
    }

    @Test("records are sorted before the gaps are measured")
    func lastBreakEndSortsInput() {
        let base = Date.now.addingTimeInterval(-7200)
        let before = Fixture.activity(in: context, from: base, to: base.addingTimeInterval(600))
        let after = Fixture.activity(in: context, from: base.addingTimeInterval(3600), to: Date.now)
        #expect(DayReport.lastBreakEnd(in: [after, before], threshold: 300) == after.startedAt)
    }

    @Test("the most recent break wins")
    func lastBreakEndTakesTheLatest() {
        let base = Date.now.addingTimeInterval(-10_800)
        let firstBreak = Fixture.activity(in: context, from: base,
                                          to: base.addingTimeInterval(600), isIdle: true)
        let work = Fixture.activity(in: context, from: base.addingTimeInterval(600),
                                    to: base.addingTimeInterval(3600))
        let secondBreak = Fixture.activity(in: context, from: base.addingTimeInterval(3600),
                                           to: base.addingTimeInterval(4200), isIdle: true)
        let back = Fixture.activity(in: context, from: base.addingTimeInterval(4200), to: Date.now)
        let result = DayReport.lastBreakEnd(in: [firstBreak, work, secondBreak, back], threshold: 300)
        #expect(result == secondBreak.endedAt)
    }

    @Test("overlapping records do not confuse the gap measurement")
    func lastBreakEndOverlapping() {
        let base = Date.now.addingTimeInterval(-3600)
        let long = Fixture.activity(in: context, from: base, to: Date.now)
        let nested = Fixture.activity(in: context, from: base.addingTimeInterval(600),
                                      to: base.addingTimeInterval(1200))
        #expect(DayReport.lastBreakEnd(in: [long, nested], threshold: 300) == nil)
    }
}

// MARK: - The honesty split

@MainActor
@Suite("Honesty split")
struct HonestySplitTests {

    @Test("only reviewed sessions are counted")
    func unreviewedSessionsAreLeftOut() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext

        // Reviewed: an hour worked, half of it called real.
        Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 10),
            segments: [(Clock.at(hour: 9), Clock.at(hour: 10))],
            focusRating: 3, honestWorkMinutes: 30, reflectionState: .completed
        )
        // Never reviewed. Counting its hour as time that didn't feel real would
        // be an answer the user never gave.
        Fixture.session(
            in: context, startedAt: Clock.at(hour: 11), endedAt: Clock.at(hour: 12),
            segments: [(Clock.at(hour: 11), Clock.at(hour: 12))]
        )

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let split = DayReport.honestySplit(of: sessions)

        #expect(split.clocked == Clock.hours(1))
        #expect(split.honest == Clock.minutes(30))
    }

    @Test("the honest share never exceeds the clock it came out of")
    func honestIsCappedAtClocked() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext

        // Twenty minutes worked, but the review says ninety — the session was
        // shortened after it was reviewed. Drawn as a whole and its part, an
        // uncapped answer puts the part above the whole, which is exactly how
        // "felt like work" came out taller than the hours recorded.
        Fixture.session(
            in: context, startedAt: Clock.at(hour: 9),
            endedAt: Clock.at(hour: 9).addingTimeInterval(Clock.minutes(20)),
            segments: [(Clock.at(hour: 9), Clock.at(hour: 9).addingTimeInterval(Clock.minutes(20)))],
            focusRating: 5, honestWorkMinutes: 90, reflectionState: .completed
        )

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let split = DayReport.honestySplit(of: sessions)

        #expect(split.clocked == Clock.minutes(20))
        #expect(split.honest == split.clocked)
        // The remainder drawn on top of the solid part is what makes the bar
        // add up to the time clocked.
        #expect(split.clocked - split.honest == 0)
    }

    @Test("a skipped review contributes nothing")
    func skippedReviewsAreNotAnAnswer() throws {
        let container = try TestStore.inMemory()
        let context = container.mainContext
        Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 10),
            segments: [(Clock.at(hour: 9), Clock.at(hour: 10))],
            reflectionState: .skipped
        )

        let sessions = try context.fetch(FetchDescriptor<WorkSession>())
        let split = DayReport.honestySplit(of: sessions)

        #expect(split.clocked == 0)
        #expect(split.honest == 0)
    }
}
