import Foundation
import SwiftData
import Testing
@testable import Span

@MainActor
@Suite("WorkSession")
struct WorkSessionTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws { container = try TestStore.inMemory() }

    // MARK: - Defaults

    @Test("a new session starts active with no end")
    func newSessionDefaults() {
        let session = WorkSession(title: "Write", category: "Deep Work", plannedMinutes: 45)
        #expect(session.status == .active)
        #expect(session.endedAt == nil)
        #expect(session.pausedAt == nil)
        #expect(session.totalPausedSeconds == 0)
        #expect(session.segments.isEmpty)
        #expect(session.plannedDuration == 45 * 60)
        #expect(session.reflectionState == .pending)
    }

    @Test("an unknown status string reads as active rather than crashing")
    func unknownStatusFallsBack() {
        let session = WorkSession(title: "X", plannedMinutes: 10)
        session.statusRaw = "nonsense"
        #expect(session.status == .active)
    }

    @Test("an unknown reflection state reads as pending")
    func unknownReflectionStateFallsBack() {
        let session = WorkSession(title: "X", plannedMinutes: 10)
        session.reflectionStateRaw = "nonsense"
        #expect(session.reflectionState == .pending)
    }

    // MARK: - Segments

    @Test("beginSegment opens exactly one run")
    func beginSegmentOpensOne() {
        let session = WorkSession(title: "X", plannedMinutes: 60)
        context.insert(session)
        session.beginSegment(at: Clock.at(hour: 9))
        #expect(session.segments.count == 1)
        #expect(session.openSegment?.startedAt == Clock.at(hour: 9))
    }

    @Test("beginSegment does nothing while a run is already open")
    func beginSegmentIsIdempotent() {
        let session = WorkSession(title: "X", plannedMinutes: 60)
        context.insert(session)
        session.beginSegment(at: Clock.at(hour: 9))
        session.beginSegment(at: Clock.at(hour: 10))
        #expect(session.segments.count == 1)
        #expect(session.openSegment?.startedAt == Clock.at(hour: 9))
    }

    @Test("openSegment is the run with no end")
    func openSegmentIdentification() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 11), nil),
        ])
        #expect(session.openSegment?.startedAt == Clock.at(hour: 11))
    }

    @Test("a closed session has no open run")
    func noOpenSegmentWhenClosed() {
        let session = Fixture.session(in: context, segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        #expect(session.openSegment == nil)
    }

    @Test("a segment's duration runs to now while it is open")
    func segmentDurationOpen() {
        let segment = SessionSegment(startedAt: Clock.at(hour: 9))
        #expect(segment.duration(at: Clock.at(hour: 10)) == 3600)
        segment.endedAt = Clock.at(hour: 9.5)
        #expect(segment.duration(at: Clock.at(hour: 10)) == 1800)
    }

    @Test("a segment's duration is never negative")
    func segmentDurationFloor() {
        let segment = SessionSegment(startedAt: Clock.at(hour: 10))
        #expect(segment.duration(at: Clock.at(hour: 9)) == 0)
    }

    // MARK: - Transitions

    @Test("pause closes the open run and marks the session paused")
    func pauseClosesRun() {
        let session = WorkSession(title: "X", plannedMinutes: 60)
        context.insert(session)
        session.beginSegment(at: Clock.at(hour: 9))
        session.pause()
        #expect(session.status == .paused)
        #expect(session.pausedAt != nil)
        #expect(session.openSegment == nil)
        #expect(session.segments.count == 1)
    }

    @Test("pausing a session that is not running does nothing")
    func pauseOnlyFromActive() {
        let session = Fixture.session(in: context, status: .completed,
                                      segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        session.pause()
        #expect(session.status == .completed)
        #expect(session.pausedAt == nil)
    }

    @Test("resume opens a fresh run and banks the pause")
    func resumeOpensNewRun() {
        let session = WorkSession(title: "X", plannedMinutes: 60)
        context.insert(session)
        session.beginSegment(at: Clock.at(hour: 9))
        session.pause()
        session.resume()
        #expect(session.status == .active)
        #expect(session.pausedAt == nil)
        #expect(session.segments.count == 2)
        #expect(session.openSegment != nil)
        #expect(session.totalPausedSeconds >= 0)
    }

    @Test("resuming a session that is not paused does nothing")
    func resumeOnlyFromPaused() {
        let session = WorkSession(title: "X", plannedMinutes: 60)
        context.insert(session)
        session.beginSegment(at: Clock.at(hour: 9))
        session.resume()
        #expect(session.segments.count == 1)
    }

    @Test("complete closes the run and stamps the end")
    func completeFromActive() {
        let session = WorkSession(title: "X", plannedMinutes: 60)
        context.insert(session)
        session.beginSegment(at: Clock.at(hour: 9))
        session.complete(at: Clock.at(hour: 10))
        #expect(session.status == .completed)
        #expect(session.endedAt == Clock.at(hour: 10))
        #expect(session.openSegment == nil)
        #expect(session.segments.first?.endedAt == Clock.at(hour: 10))
    }

    @Test("completing while paused banks the outstanding pause")
    func completeFromPaused() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), pausedAt: Clock.at(hour: 9.5),
            status: .paused, segments: [(Clock.at(hour: 9), Clock.at(hour: 9.5))])
        session.complete(at: Clock.at(hour: 10))
        #expect(session.status == .completed)
        #expect(session.pausedAt == nil)
        #expect(session.totalPausedSeconds == 1800)
        #expect(session.endedAt == Clock.at(hour: 10))
    }

    @Test("completing a finished session moves its end forward")
    func completeTwice() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 10),
            status: .completed, segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        session.complete(at: Clock.at(hour: 11))
        #expect(session.endedAt == Clock.at(hour: 11))
        // The already-closed run is not reopened or re-stamped.
        #expect(session.segments.first?.endedAt == Clock.at(hour: 10))
        #expect(session.elapsed(at: Clock.at(hour: 12)) == 3600)
    }

    // MARK: - elapsed / remaining / span

    @Test("elapsed sums the runs and so excludes pauses")
    func elapsedSumsSegments() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 11), Clock.at(hour: 11.5)),
        ])
        #expect(session.elapsed(at: Clock.at(hour: 15)) == 5400)
    }

    @Test("elapsed grows with now while a run is open")
    func elapsedGrowsWhileOpen() {
        let session = Fixture.session(in: context, status: .active,
                                      segments: [(Clock.at(hour: 9), nil)])
        #expect(session.elapsed(at: Clock.at(hour: 9.5)) == 1800)
        #expect(session.elapsed(at: Clock.at(hour: 10)) == 3600)
    }

    @Test("a session with no runs falls back to the stored arithmetic")
    func elapsedLegacyPath() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 11),
            totalPausedSeconds: 1800)
        #expect(session.elapsed(at: Clock.at(hour: 15)) == 5400)
    }

    @Test("the legacy path uses the pause time when a session is still paused")
    func elapsedLegacyPaused() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), pausedAt: Clock.at(hour: 10),
            status: .paused)
        #expect(session.elapsed(at: Clock.at(hour: 15)) == 3600)
    }

    @Test("elapsed is never negative")
    func elapsedNeverNegative() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 10), endedAt: Clock.at(hour: 9))
        #expect(session.elapsed(at: Clock.at(hour: 15)) == 0)
    }

    // MARK: - elapsed(in:)

    @Test("elapsed in a window counts only the runs inside it")
    func elapsedInWindow() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 8), Clock.at(hour: 10)),
            (Clock.at(hour: 14), Clock.at(hour: 15)),
        ])
        let morning = Clock.at(hour: 9)...Clock.at(hour: 12)
        #expect(session.elapsed(in: morning, at: Clock.at(hour: 20)) == 3600)
    }

    @Test("a run straddling the window edge is counted in part")
    func elapsedInWindowClips() {
        let session = Fixture.session(in: context,
                                      segments: [(Clock.at(hour: 23), Clock.at(hour: 25))])
        let today = Clock.dayStart...Clock.at(hour: 24)
        #expect(session.elapsed(in: today, at: Clock.at(hour: 26)) == 3600)

        let tomorrow = Clock.at(hour: 24)...Clock.at(hour: 48)
        #expect(session.elapsed(in: tomorrow, at: Clock.at(hour: 26)) == 3600)
    }

    @Test("the two sides of a boundary add up to the whole")
    func elapsedInWindowPartitions() {
        let session = Fixture.session(in: context,
                                      segments: [(Clock.at(hour: 22), Clock.at(hour: 26))])
        let now = Clock.at(hour: 30)
        let before = session.elapsed(in: Clock.dayStart...Clock.at(hour: 24), at: now)
        let after = session.elapsed(in: Clock.at(hour: 24)...Clock.at(hour: 48), at: now)
        #expect(before + after == session.elapsed(at: now))
    }

    @Test("a window that misses the session entirely counts nothing")
    func elapsedInWindowDisjoint() {
        let session = Fixture.session(in: context,
                                      segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        #expect(session.elapsed(in: Clock.at(hour: 14)...Clock.at(hour: 16),
                                at: Clock.at(hour: 20)) == 0)
    }

    @Test("an open run is clipped to now as well as to the window")
    func elapsedInWindowOpenRun() {
        let session = Fixture.session(in: context, status: .active,
                                      segments: [(Clock.at(hour: 9), nil)])
        #expect(session.elapsed(in: Clock.dayStart...Clock.at(hour: 24),
                                at: Clock.at(hour: 10)) == 3600)
    }

    @Test("a legacy session spreads its pauses across the window")
    func elapsedInWindowLegacy() {
        // 9-11 with an hour of pauses somewhere inside; half the span falls in
        // the window, so half the pause does too.
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 11),
            totalPausedSeconds: 3600)
        #expect(session.elapsed(at: Clock.at(hour: 20)) == 3600)
        #expect(session.elapsed(in: Clock.at(hour: 10)...Clock.at(hour: 12),
                                at: Clock.at(hour: 20)) == 1800)
    }

    @Test("remaining counts down and stops at zero")
    func remaining() {
        let session = Fixture.session(in: context, plannedMinutes: 60, status: .active,
                                      segments: [(Clock.at(hour: 9), nil)])
        #expect(session.remaining(at: Clock.at(hour: 9)) == 3600)
        #expect(session.remaining(at: Clock.at(hour: 9.5)) == 1800)
        #expect(session.remaining(at: Clock.at(hour: 10)) == 0)
        #expect(session.remaining(at: Clock.at(hour: 12)) == 0)
    }

    @Test("span covers the whole stretch, breaks included")
    func spanIncludesBreaks() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 11),
            segments: [(Clock.at(hour: 9), Clock.at(hour: 9.5)),
                       (Clock.at(hour: 10.5), Clock.at(hour: 11))])
        let span = session.span(at: Clock.at(hour: 15))
        #expect(span.lowerBound == Clock.at(hour: 9))
        #expect(span.upperBound == Clock.at(hour: 11))
        #expect(session.elapsed(at: Clock.at(hour: 15)) == 3600)
    }

    @Test("an unfinished session spans up to now")
    func spanOpenEndedRunsToNow() {
        let session = Fixture.session(in: context, startedAt: Clock.at(hour: 9), status: .active)
        #expect(session.span(at: Clock.at(hour: 10)).upperBound == Clock.at(hour: 10))
    }

    @Test("span never inverts, even with a bad end date")
    func spanNeverInverts() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 10), endedAt: Clock.at(hour: 9))
        let span = session.span(at: Clock.at(hour: 15))
        #expect(span.lowerBound == Clock.at(hour: 10))
        #expect(span.upperBound == Clock.at(hour: 10))
    }

    // MARK: - Reflection

    @Test("a session counts as reviewed only when completed and rated", arguments: [
        (ReflectionState.completed, 4, true),
        (ReflectionState.completed, nil, false),
        (ReflectionState.skipped, 4, false),
        (ReflectionState.pending, 4, false),
        (ReflectionState.pending, nil, false),
    ])
    func isReflectedMatrix(state: ReflectionState, rating: Int?, expected: Bool) {
        let session = Fixture.session(in: context, status: .completed,
                                      focusRating: rating, reflectionState: state)
        #expect(session.isReflected == expected)
    }

    @Test("only a finished, unanswered session still owes a review", arguments: [
        (SessionStatus.completed, ReflectionState.pending, true),
        (SessionStatus.completed, ReflectionState.skipped, false),
        (SessionStatus.completed, ReflectionState.completed, false),
        (SessionStatus.active, ReflectionState.pending, false),
        (SessionStatus.paused, ReflectionState.pending, false),
    ])
    func needsReflectionMatrix(status: SessionStatus, state: ReflectionState, expected: Bool) {
        let session = Fixture.session(in: context, status: status, reflectionState: state)
        #expect(session.needsReflection == expected)
    }

    @Test("setting the reflection state writes through to the stored string")
    func reflectionStateWritesThrough() {
        let session = Fixture.session(in: context)
        session.reflectionState = .skipped
        #expect(session.reflectionStateRaw == "skipped")
    }

    @Test("the honest answer is what the user said, when it fits the session")
    func honestWorkWithinTheSession() {
        let session = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 9), Clock.at(hour: 11))],
            focusRating: 3, honestWorkMinutes: 75, reflectionState: .completed)
        #expect(session.honestWork(at: Clock.at(hour: 12)) == Clock.minutes(75))
    }

    @Test("an answer left behind by a shortened session cannot outgrow it")
    func honestWorkIsCappedByTheTimeWorked() {
        // Reviewed as a nineteen-hour session — one left running overnight —
        // and then corrected to the two hours actually worked.
        let session = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 19), Clock.at(hour: 21))],
            focusRating: 3, honestWorkMinutes: 1143, reflectionState: .completed)
        #expect(session.honestWork(at: Clock.at(hour: 22)) == Clock.hours(2))
    }

    @Test("an unanswered review is no honest work")
    func honestWorkWithoutAnAnswer() {
        let session = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 9), Clock.at(hour: 11))])
        #expect(session.honestWork(at: Clock.at(hour: 12)) == 0)
    }

    @Test("a session a hair short of the whole minute still measures the whole minute")
    func workedMinutesRoundsRatherThanTruncates() {
        // Times set by hand land fractionally short — this is a real two-hour
        // session, stored as 7199.999997 seconds.
        let session = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 19), Clock.at(hour: 21).addingTimeInterval(-0.000003))])
        #expect(session.workedMinutes(at: Clock.at(hour: 22)) == 120)

        session.honestWorkMinutes = 120
        session.clampReviewToWorkedTime(at: Clock.at(hour: 22))
        #expect(session.honestWorkMinutes == 120, "a minute was shaved off an answer that fitted")
    }

    @Test("clamping writes the ceiling down, and only ever downwards")
    func clampingLowersTheAnswer() {
        let stale = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 19), Clock.at(hour: 21))],
            focusRating: 3, honestWorkMinutes: 1143, reflectionState: .completed)
        stale.clampReviewToWorkedTime(at: Clock.at(hour: 22))
        #expect(stale.honestWorkMinutes == 120)

        let modest = Fixture.session(
            in: context, status: .completed,
            segments: [(Clock.at(hour: 9), Clock.at(hour: 11))],
            focusRating: 3, honestWorkMinutes: 40, reflectionState: .completed)
        modest.clampReviewToWorkedTime(at: Clock.at(hour: 12))
        #expect(modest.honestWorkMinutes == 40, "an answer that fits was rewritten")
    }

    // MARK: - Storage

    @Test("deleting a session takes its runs with it")
    func cascadeDelete() throws {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 11), Clock.at(hour: 12)),
        ])
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SessionSegment>()).count == 2)

        context.delete(session)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<SessionSegment>()).isEmpty)
    }

    @Test("a segment knows the session it belongs to")
    func segmentBackReference() {
        let session = Fixture.session(in: context, segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        #expect(session.segments.first?.session?.id == session.id)
    }
}

// MARK: - Blocks

/// A hand-made block is the third source of time in the app, and since it now
/// counts towards the day's focus its arithmetic has to hold up the same way a
/// session's does.
@MainActor
@Suite("TimeEntry")
struct TimeEntryTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws { container = try TestStore.inMemory() }

    @Test("a block inside the window counts whole")
    func wholeBlock() {
        let entry = Fixture.entry(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 11))
        #expect(entry.duration(in: Clock.dayStart...Clock.at(hour: 18)) == Clock.hours(2))
    }

    @Test("a block is clipped to the window at both ends")
    func clippedBlock() {
        let entry = Fixture.entry(in: context, from: Clock.at(hour: 8), to: Clock.at(hour: 12))
        #expect(entry.duration(in: Clock.at(hour: 9)...Clock.at(hour: 11)) == Clock.hours(2))
    }

    @Test("a block wholly outside the window counts for nothing")
    func blockOutsideTheWindow() {
        let entry = Fixture.entry(in: context, from: Clock.at(hour: 20), to: Clock.at(hour: 21))
        #expect(entry.duration(in: Clock.dayStart...Clock.at(hour: 18)) == 0)
    }

    @Test("a block that crosses midnight is split between the days")
    func blockAcrossMidnight() {
        let midnight = Clock.dayStart.addingTimeInterval(Clock.hours(24))
        let entry = Fixture.entry(in: context, from: Clock.at(hour: 23), to: midnight.addingTimeInterval(Clock.hours(1)))
        #expect(entry.duration(in: Clock.dayStart...midnight) == Clock.hours(1))
        #expect(entry.duration(in: midnight...midnight.addingTimeInterval(Clock.hours(24))) == Clock.hours(1))
    }
}
