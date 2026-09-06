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

    // Pre-formatted so a tick that doesn't change the displayed text doesn't
    // invalidate any view. Publishing a `Date` would re-render every second
    // regardless of whether anything visibly moved.
    private(set) var sessionClock: String = "00:00"
    private(set) var focusTodayText: String = "0m"
    private(set) var sinceBreakText: String = "--"
    private(set) var percentOfTargetText: String = "0%"

    /// The numeric companion to `percentOfTargetText`, for the HUD's target
    /// ring. Quantised to 1/200 of the sweep — a smaller step moves the ring by
    /// less than a point — for the same reason the rest of this block is
    /// pre-formatted: a tick that moves nothing on screen should invalidate
    /// nothing.
    private(set) var focusFraction: Double = 0

    /// Daily focus goal in minutes, used for the HUD's third stat.
    @ObservationIgnored
    @AppStorage("dailyFocusTargetMinutes") var dailyFocusTargetMinutes: Int = 300

    private let context: ModelContext
    private var loop: Task<Void, Never>?
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

        let session = WorkSession(title: title, category: category, plannedMinutes: minutes)
        session.beginSegment()
        context.insert(session)
        save()
        activeSession = session
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
    func finishSession() -> WorkSession? {
        guard let session = activeSession else { return nil }
        NotificationService.cancelReminder(for: session)
        session.complete()
        save()
        activeSession = nil
        pendingReflection = session
        refreshStats()
        return session
    }

    func extendSession(byMinutes minutes: Int) {
        guard let activeSession else { return }
        activeSession.plannedMinutes += minutes
        save()
        NotificationService.scheduleEndReminder(for: activeSession)
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

    private func refreshStats() {
        let now = Date.now
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)

        if let session = activeSession {
            sessionClock = Format.clock(session.remaining(at: now))
        } else {
            sessionClock = "00:00"
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
        let today = dayStart...max(dayStart, now)
        let focus = sessions.reduce(0) { $0 + $1.elapsed(in: today, at: now) }
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

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
