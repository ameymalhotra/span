import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// The single source of truth shared by the main window, the menu bar item and
/// the floating HUD.
///
/// All three used to be able to compute their own totals, which meant they
/// could disagree about the same day. They now read these values, so the number
/// in the menu bar is by construction the number in the window.
@MainActor
@Observable
final class AppModel {

    let tracker: ActivityTracker
    let accessibility = AccessibilityPermission()
    let updates = UpdateChecker()
    let installer = UpdateInstaller()

    /// The day the main window is showing.
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private(set) var activeSession: WorkSession?

    /// A block just created from the toolbar, waiting for the timeline to open
    /// its editor.
    var pendingBlockEdit: TimeEntry?

    /// Set after a reset so the window can offer the first-run questions again.
    var needsOnboarding = false

    /// Bumped whenever category colours or app rules change.
    ///
    /// The palette itself is a static lookup, which SwiftUI cannot observe, so
    /// recolouring a category would not repaint the timeline drawn from it.
    /// Views that paint category colours read this to pick the change up.
    private(set) var paletteGeneration = 0

    func paletteDidChange() {
        ModelStack.loadAppRules(in: context)
        paletteGeneration += 1
    }

    /// A session that has just finished and is owed a review.
    ///
    /// The main window presents the sheet. The menu bar and the HUD can finish
    /// a session but have nowhere to show one, so they hand it over here rather
    /// than dropping the review on the floor.
    var pendingReflection: WorkSession?

    /// Whether `pendingReflection` was ended by Span rather than by the user,
    /// so the sheet can say why a session the user never finished is over.
    private(set) var pendingReflectionWasAutomatic = false

    /// Set when a session the user finished themselves is owed the offer of a
    /// break, once its review has been dealt with. A session Span closed on its
    /// own sets nothing: whoever left it running is not sitting there waiting
    /// to be told to rest.
    var offersBreakAfterReview = false

    /// When the running break ends, if one is running.
    private(set) var breakEndsAt: Date?
    /// Pre-formatted, for the same reason as `sessionClock`.
    private(set) var breakClock: String = "00:00"
    /// How long the running break was set for, so its ring has a whole to be a
    /// fraction of.
    private(set) var breakLength: TimeInterval = 0
    /// Whether this break paused a session on its way in, so ending it early
    /// can put the user back to work rather than leaving a session paused for
    /// them to notice later — and so the pane can say as much.
    private(set) var sessionPausedForBreak = false

    var isOnBreak: Bool { breakEndsAt != nil }

    // Pre-formatted so a tick that doesn't change the displayed text doesn't
    // invalidate any view. Publishing a `Date` would re-render every second
    // regardless of whether anything visibly moved.
    private(set) var sessionClock: String = "00:00"
    private(set) var focusTodayText: String = "0m"
    /// The number behind `focusTodayText`, for the Focus pane's ring. Published
    /// rather than recomputed there: the ring and the status bar are the same
    /// claim about the same day and must not be able to disagree.
    private(set) var focusToday: TimeInterval = 0
    private(set) var sinceBreakText: String = "--"
    private(set) var percentOfTargetText: String = "0%"

    /// Whether the running session is past its planned end. The clock alone
    /// cannot say so — it stops at 00:00 and stays there, which reads exactly
    /// like a session about to start.
    private(set) var sessionIsOvertime = false

    /// The numeric companion to `percentOfTargetText`, for the HUD's target
    /// ring. Quantised to 1/200 of the sweep — a smaller step moves the ring by
    /// less than a point — for the same reason the rest of this block is
    /// pre-formatted: a tick that moves nothing on screen should invalidate
    /// nothing.
    private(set) var focusFraction: Double = 0

    /// Daily focus goal in minutes, used for the HUD's third stat.
    @ObservationIgnored
    @AppStorage("dailyFocusTargetMinutes") var dailyFocusTargetMinutes: Int = 300

    /// How long a session may go untouched before Span finishes it itself.
    /// Zero turns that off and puts the session back in the user's hands.
    @ObservationIgnored
    @AppStorage("autoFinishAfterMinutes") var autoFinishAfterMinutes: Int = 30

    /// How long the user has been away from the keyboard and mouse. Injected
    /// so tests can drive the abandonment check without the machine they run
    /// on deciding the answer.
    @ObservationIgnored
    var idleClock: () -> TimeInterval = { IdleMonitor.idleInterval() }

    private let context: ModelContext
    private var loop: Task<Void, Never>?
    /// The day boundary the last tick saw, so a rollover can be noticed.
    private var lastDayStart = Calendar.current.startOfDay(for: .now)
    /// Surfaces that need a one-second clock. The tick slows to 15s when none
    /// are on screen, which is most of the time.
    private var fastConsumers = 0

    init(container: ModelContainer) {
        // Deliberately the container's main context, the same one `@Query`
        // reads from. A private context would need its changes merged back
        // before any view noticed a session had started.
        self.context = container.mainContext
        self.tracker = ActivityTracker(context: context)

        // Colours have to be known before the first view draws, not after.
        // Loading these in start() — which runs from a .task once the window is
        // on screen — meant the first render found an empty registry and fell
        // back to a hash of each category's name, so blocks came up in colours
        // nobody had chosen. Nothing then repainted them, because a static
        // registry is invisible to SwiftUI.
        ModelStack.seedCategoriesIfNeeded(in: context)
        ModelStack.loadAppRules(in: context)
    }

    // MARK: - Lifecycle

    func start() {
        ModelStack.recoverStaleSessions(in: context)
        // After recovery, so a session closed just above is measured at the
        // length it is finally recorded with.
        ModelStack.clampReviewsToWorkedTime(in: context)
        refreshActiveSession()
        tracker.start()
        retune()
        Task { await updates.checkIfDue() }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        tracker.stop()
    }

    /// Views that show a running clock call this while visible.
    func beginFastUpdates() { fastConsumers += 1; retune() }
    func endFastUpdates() { fastConsumers = max(0, fastConsumers - 1); retune() }

    private func retune() {
        loop?.cancel()
        let interval: Duration = fastConsumers > 0 ? .seconds(1) : .seconds(15)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshStats()
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Clears tracked activity, optionally only today's.
    func deleteActivity(onlyToday: Bool) {
        // The tracker holds an unwritten span; pausing flushes it first so it
        // cannot reappear immediately after the delete.
        let wasPaused = tracker.isPaused
        tracker.isPaused = true
        ModelStack.deleteActivity(in: context, onlyToday: onlyToday)
        tracker.isPaused = wasPaused
        refreshStats()
    }

    /// Returns Span to a first run: nothing recorded, no preferences.
    func resetEverything() {
        let wasPaused = tracker.isPaused
        tracker.isPaused = true
        if let session = activeSession {
            NotificationService.cancelReminder(for: session)
        }
        activeSession = nil
        clearBreak(resumingWork: false)
        ModelStack.resetEverything(in: context)
        tracker.isPaused = wasPaused
        refreshStats()
        needsOnboarding = true
    }

    // MARK: - Session control

    /// Starts a session, unless one is already running.
    ///
    /// The guard is not just belt-and-braces for the toolbar's disabled state.
    /// A second session would take over `activeSession`, leaving the first
    /// unreachable — nothing could pause or finish it — while both kept
    /// accumulating against the day's total. The menu bar, the HUD and the
    /// keyboard shortcut all reach this directly.
    @discardableResult
    func startSession(title: String, category: String, minutes: Int) -> WorkSession? {
        if activeSession == nil { refreshActiveSession() }
        guard activeSession == nil else { return nil }

        // Starting work ends any break: the break's whole claim is that you
        // are not working, and it must not resume a session on its way out.
        clearBreak(resumingWork: false)

        let session = WorkSession(title: title, category: category, plannedMinutes: minutes)
        session.beginSegment()
        context.insert(session)
        save()
        activeSession = session
        NotificationService.requestAuthorizationIfUndetermined()
        NotificationService.scheduleEndReminder(for: session)
        refreshStats()
        return session
    }

    /// Turns a hand-made block into the session that is running now.
    ///
    /// The session starts where the block started, so time already inside it
    /// counts as worked, and is planned to run to the block's end — which is
    /// what the countdown then shows. The block itself is removed rather than
    /// left alongside: two records for one stretch of work would be counted
    /// twice in every total.
    func startSession(from entry: TimeEntry) {
        guard activeSession == nil else { return }
        clearBreak(resumingWork: false)
        let title = entry.title.trimmingCharacters(in: .whitespaces)
        let session = WorkSession(
            title: title.isEmpty ? "Untitled session" : title,
            category: entry.category,
            plannedMinutes: max(1, Int(entry.duration / 60))
        )
        session.startedAt = entry.startedAt
        let segment = SessionSegment(startedAt: entry.startedAt, session: session)
        session.segments.append(segment)

        context.insert(session)
        context.delete(entry)
        save()

        activeSession = session
        NotificationService.requestAuthorizationIfUndetermined()
        NotificationService.scheduleEndReminder(for: session)
        refreshStats()
    }

    func pauseSession() {
        guard let activeSession else { return }
        activeSession.pause()
        NotificationService.cancelReminder(for: activeSession)
        save()
        refreshStats()
    }

    func resumeSession() {
        guard let activeSession else { return }
        activeSession.resume()
        NotificationService.scheduleEndReminder(for: activeSession)
        save()
        refreshStats()
    }

    /// Finishes the session and queues its review.
    ///
    /// The review is queued rather than returned so that every surface offers
    /// it: the menu bar and the HUD used to call this and discard the result,
    /// which quietly skipped the review and left the session counted as
    /// finished but unreviewed for good.
    @discardableResult
    func finishSession(at date: Date = .now, automatically: Bool = false) -> WorkSession? {
        guard let session = activeSession else { return nil }
        NotificationService.cancelReminder(for: session)
        session.complete(at: date)
        save()
        activeSession = nil
        pendingReflection = session
        pendingReflectionWasAutomatic = automatically
        offersBreakAfterReview = !automatically && !isOnBreak
        refreshStats()
        return session
    }

    /// How long a session may sit untouched before it is finished for the
    /// user, or nil when they have turned that off.
    private var abandonmentGrace: TimeInterval? {
        guard autoFinishAfterMinutes > 0 else { return nil }
        return TimeInterval(autoFinishAfterMinutes * 60)
    }

    /// Ends a session the user has walked away from, at the moment they walked
    /// away rather than the moment we noticed.
    ///
    /// A session used to run until someone pressed Finish. Forget once at the
    /// end of an evening and the next morning's Finish banked the whole night:
    /// a thousand minutes of focus in the day's totals, and a review sheet
    /// asking how much of sixteen hours felt like real work.
    ///
    /// The idle clock is the system's own, the same one the tracker reads to
    /// decide you are away, and it keeps running while the Mac sleeps — so a
    /// laptop closed at 23:10 reports the whole night on waking and the
    /// session is closed back at 23:10.
    ///
    /// The end is never pulled back before the session started, so a session
    /// begun while the user was already away is measured from its own start
    /// rather than from input that predates it.
    @discardableResult
    func autoFinishIfAbandoned(at now: Date = .now, idleFor idle: TimeInterval) -> WorkSession? {
        guard let session = activeSession, let grace = abandonmentGrace else { return nil }

        // A paused session is not over-counting — its clock stopped when it was
        // paused — but until it is closed no new session can be started, so one
        // left paused overnight goes the same way, ending where it paused.
        let lastKnownGood: Date = switch session.status {
        case .paused: session.pausedAt ?? session.startedAt
        default: now.addingTimeInterval(-max(0, idle))
        }

        let end = max(session.startedAt, min(lastKnownGood, now))
        guard now.timeIntervalSince(end) >= grace else { return nil }
        return finishSession(at: end, automatically: true)
    }

    func extendSession(byMinutes minutes: Int) {
        guard let activeSession else { return }
        activeSession.plannedMinutes += minutes
        save()
        NotificationService.scheduleEndReminder(for: activeSession)
    }

    // MARK: - Breaks

    /// How long is left of the break, or zero when none is running.
    func breakRemaining(at date: Date = .now) -> TimeInterval {
        guard let breakEndsAt else { return 0 }
        return max(0, breakEndsAt.timeIntervalSince(date))
    }

    /// Starts a break, pausing a running session for its duration.
    ///
    /// The pause is the point: a break taken with the session still counting
    /// would be recorded as work, which is exactly the arithmetic the rest of
    /// the app goes to some trouble to avoid.
    func startBreak(minutes: Int, at date: Date = .now) {
        offersBreakAfterReview = false
        if activeSession?.status == .active {
            pauseSession()
            sessionPausedForBreak = true
        }
        let length = TimeInterval(max(1, minutes) * 60)
        let end = date.addingTimeInterval(length)
        breakEndsAt = end
        breakLength = length
        NotificationService.scheduleBreakEnd(at: end)
        refreshStats()
    }

    func extendBreak(byMinutes minutes: Int) {
        guard let breakEndsAt else { return }
        let end = breakEndsAt.addingTimeInterval(TimeInterval(minutes * 60))
        self.breakEndsAt = end
        breakLength += TimeInterval(minutes * 60)
        NotificationService.scheduleBreakEnd(at: end)
        refreshStats()
    }

    /// Ends the break. Coming back deliberately resumes the session the break
    /// paused; a break that simply ran out leaves it paused, since nobody has
    /// said they are back at the desk.
    func endBreak(resumingWork: Bool = true) {
        guard isOnBreak else { return }
        clearBreak(resumingWork: resumingWork)
        refreshStats()
    }

    private func clearBreak(resumingWork: Bool) {
        breakEndsAt = nil
        breakLength = 0
        NotificationService.cancelBreakEnd()
        let shouldResume = sessionPausedForBreak && resumingWork
        sessionPausedForBreak = false
        if shouldResume, activeSession?.status == .paused { resumeSession() }
    }

    /// Adds a hand-made block on `day`: at the current time when that is today,
    /// otherwise mid-morning, since a past day has no "now".
    func addBlock(on day: Date, minutes: Int = 30) {
        let calendar = Calendar.current
        let start: Date
        if calendar.isDateInToday(day) {
            let step = TimeInterval(5 * 60)
            start = Date(timeIntervalSinceReferenceDate:
                (Date.now.timeIntervalSinceReferenceDate / step).rounded() * step)
        } else {
            start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        let entry = TimeEntry(title: "", category: "",
                              startedAt: start,
                              endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)))
        context.insert(entry)
        save()
        pendingBlockEdit = entry
    }

    // MARK: - Derived values

    private func refreshActiveSession() {
        let active = SessionStatus.active.rawValue
        let paused = SessionStatus.paused.rawValue
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.statusRaw == active || $0.statusRaw == paused }
        )
        activeSession = try? context.fetch(descriptor).first
    }

    /// Moves the window on to the new day when midnight passes.
    ///
    /// `selectedDate` was set once, at launch, so a Mac left running overnight
    /// still showed yesterday in the morning: no now-line, today's work
    /// nowhere to be seen, and the "next day" arrow greyed out because it
    /// thought yesterday was today.
    ///
    /// The date only follows the clock if the window was showing the day that
    /// has just ended. Someone deliberately reading back over an earlier day is
    /// left where they are.
    func followClockPastMidnight(to dayStart: Date, calendar: Calendar = .current) {
        guard dayStart != lastDayStart else { return }
        let wasFollowingToday = calendar.isDate(selectedDate, inSameDayAs: lastDayStart)
        lastDayStart = dayStart
        guard wasFollowingToday else { return }
        selectedDate = dayStart
    }

    private func refreshStats() {
        let now = Date.now
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)

        followClockPastMidnight(to: dayStart, calendar: calendar)
        // Before anything is measured: a session the user left hours ago must
        // not spend this tick counting, nor be announced as ending.
        autoFinishIfAbandoned(at: now, idleFor: idleClock())
        NotificationService.announceEndIfDue(for: activeSession, at: now)

        finishBreakIfDue(at: now)
        breakClock = Format.clock(breakRemaining(at: now))

        if let session = activeSession {
            let remaining = session.remaining(at: now)
            sessionClock = Format.clock(remaining)
            sessionIsOvertime = remaining <= 0 && session.status == .active
        } else {
            sessionClock = "00:00"
            sessionIsOvertime = false
        }

        // Deliberately not `startedAt >= dayStart`: a session begun at 23:30 and
        // still running at 00:30 belongs partly to today, and filtering it out
        // reset this number to zero mid-session. The window reaches back a day
        // to catch it; `elapsed(in:)` then counts only today's share, so the
        // hours before midnight are not double-counted.
        let windowStart = dayStart.addingTimeInterval(-24 * 3600)
        let sessions = (try? context.fetch(FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.startedAt >= windowStart }
        ))) ?? []
        // Blocks the user drew by hand count too. They are the record of work
        // that happened away from the Mac, or earlier in the day than the app
        // was told about — leaving them out meant adding an hour you really
        // worked moved the timeline and nothing else, least of all the goal it
        // was meant to count towards. The range ends at now, so a block drawn
        // across the afternoon still only counts the part that has happened.
        let entries = (try? context.fetch(FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.startedAt >= windowStart }
        ))) ?? []
        let today = dayStart...max(dayStart, now)
        let focus = sessions.reduce(0) { $0 + $1.elapsed(in: today, at: now) }
            + entries.reduce(0) { $0 + $1.duration(in: today) }
        focusToday = focus
        focusTodayText = Format.compact(focus)

        let target = TimeInterval(max(1, dailyFocusTargetMinutes) * 60)
        let fraction = focus / target
        percentOfTargetText = Format.percent(fraction)
        focusFraction = (fraction * 200).rounded(.down) / 200

        // Falls back to the start of the day's first tracked activity, so the
        // stat reads sensibly before the first break has happened.
        let activity = (try? context.fetch(FetchDescriptor<ActivityRecord>(
            predicate: #Predicate { $0.startedAt >= dayStart }
        ))) ?? []
        if tracker.isPaused {
            sinceBreakText = "—"
        } else {
            let reference = DayReport.lastBreakEnd(in: activity, threshold: IdleMonitor.threshold)
                ?? activity.filter { !$0.isIdle }.map(\.startedAt).max()
            // Compact, not clock: this is a span of hours, and "12:42:10"
            // both reads as a countdown and overflows the pill.
            sinceBreakText = reference.map { Format.compact(now.timeIntervalSince($0)) } ?? "—"
        }
    }

    /// Backstop for the armed timer, for a Mac that slept through the end of a
    /// break — the same arrangement the session chime has. Internal so tests can
    /// drive it without waiting out a real break.
    func finishBreakIfDue(at date: Date) {
        guard let end = breakEndsAt, date >= end else { return }
        NotificationService.announceBreakEnd(at: end)
        clearBreak(resumingWork: false)
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
