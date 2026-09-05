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

    /// The day the main window is showing.
    var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private(set) var activeSession: WorkSession?

    /// A block just created from the toolbar, waiting for the timeline to open
    /// its editor.
    var pendingBlockEdit: TimeEntry?

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
    }

    // MARK: - Lifecycle

    func start() {
        ModelStack.seedCategoriesIfNeeded(in: context)
        ModelStack.loadAppRules(in: context)
        ModelStack.recoverStaleSessions(in: context)
        refreshActiveSession()
        tracker.start()
        retune()
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

    /// Finishes the session and hands it back so the caller can offer the
    /// reflection sheet.
    @discardableResult
    func finishSession() -> WorkSession? {
        guard let session = activeSession else { return nil }
        NotificationService.cancelReminder(for: session)
        session.complete()
        save()
        activeSession = nil
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
