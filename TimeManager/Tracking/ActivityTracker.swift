import AppKit
import Foundation
import Observation
import SwiftData

/// Records which app had focus, and when the user was away.
///
/// Everything here runs on the main actor. `ModelContext` is not `Sendable`,
/// `NSWorkspace` posts its notifications on the main thread, and the observed
/// state feeds three separate SwiftUI surfaces — while the actual work is a few
/// notifications a minute and one insert. A background actor would buy no
/// measurable throughput and cost a great deal of `Sendable` plumbing.
@MainActor
@Observable
final class ActivityTracker: NSObject {

    // MARK: - Tuning

    /// Spans shorter than this are treated as noise. Cmd-Tabbing through four
    /// apps should not leave four two-second records on the timeline.
    private let minimumRecordedDuration: TimeInterval = 10
    /// How often the open span is written through, bounding what a crash loses.
    private let flushInterval: TimeInterval = 60
    /// Sampling cadence. Also catches focus changes the notification missed and
    /// picks up window-title changes within the same app.
    private let sampleInterval: Duration = .seconds(5)

    // MARK: - Observed state

    private(set) var currentAppName: String = ""
    private(set) var currentCategory: String = ""
    private(set) var currentWindowTitle: String?
    private(set) var isIdle: Bool = false
    private(set) var isRunning: Bool = false
    /// When the user last came back from a break — the HUD's "time since last break".
    private(set) var lastBreakEnded: Date = .now

    /// User-controlled pause. Kept separate from `isRunning` so the tracker can
    /// be stopped and restarted without losing the observers.
    var isPaused: Bool = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused { closeSpan(at: .now, force: true); save() } else { sample(at: .now) }
        }
    }

    /// Bundle identifiers the user has asked never to record. Window titles can
    /// be sensitive, so exclusion drops the span entirely rather than storing a
    /// redacted one.
    var excludedBundleIdentifiers: Set<String> = []

    // MARK: - Private

    private let context: ModelContext
    private var loop: Task<Void, Never>?
    private var lastFlush: Date = .now

    /// The span being accumulated. Held in memory so short-lived focus changes
    /// never reach the store; `record` is set once it has been written, after
    /// which it is extended in place instead of re-inserted.
    private struct Span {
        var appName: String
        var bundleID: String?
        var windowTitle: String?
        var category: String
        var isIdle: Bool
        var start: Date
        var end: Date
        var record: ActivityRecord?
    }
    private var span: Span?

    init(context: ModelContext) {
        self.context = context
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true

        let workspace = NSWorkspace.shared.notificationCenter
        // Selector-based observers rather than the block or async-sequence
        // forms: `Notification` is not `Sendable`, so those variants cannot
        // cleanly touch main-actor state under Swift 6.
        workspace.addObserver(self, selector: #selector(focusChanged),
                              name: NSWorkspace.didActivateApplicationNotification, object: nil)
        for name: NSNotification.Name in [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ] {
            workspace.addObserver(self, selector: #selector(systemWillPause), name: name, object: nil)
        }
        for name: NSNotification.Name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            workspace.addObserver(self, selector: #selector(systemDidResume), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification, object: nil)

        sample(at: .now)

        loop = Task { [weak self, sampleInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: sampleInterval)
                guard let self, self.isRunning, !self.isPaused else { continue }
                self.sample(at: .now)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        loop?.cancel()
        loop = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        closeSpan(at: .now, force: true)
        save()
    }

    // MARK: - Notification handling

    // The notifications are treated purely as signals; the frontmost app is
    // re-read from NSWorkspace instead of unpacking `userInfo`. That keeps
    // non-Sendable values out of the handler and reads the true current state
    // rather than whatever was true when the notification was posted.
    @objc private func focusChanged() { guard !isPaused else { return }; sample(at: .now) }
    @objc private func systemDidResume() { guard !isPaused else { return }; sample(at: .now) }

    @objc private func systemWillPause() {
        // Sleep gets a real break span so waking hours later doesn't read as
        // an all-night stretch in whatever app happened to be frontmost.
        let now = Date.now
        closeSpan(at: now, force: true)
        beginIdle(at: now)
        save()
    }

    @objc private func appWillTerminate() {
        closeSpan(at: .now, force: true)
        save()
    }

    // MARK: - Sampling

    private func sample(at now: Date) {
        let idleFor = IdleMonitor.idleInterval()

        if idleFor >= IdleMonitor.threshold {
            if isIdle {
                span?.end = now
            } else {
                // Back-date to when input actually stopped, not to when we
                // noticed: the five minutes that established the break were
                // themselves part of it.
                let breakStart = now.addingTimeInterval(-idleFor)
                closeSpan(at: breakStart, force: true)
                beginIdle(at: breakStart)
            }
        } else {
            if isIdle {
                closeSpan(at: now, force: true)
                isIdle = false
                lastBreakEnded = now
            }
            guard let app = NSWorkspace.shared.frontmostApplication,
                  app.activationPolicy == .regular else { return }
            let bundleID = app.bundleIdentifier
            guard !(bundleID.map(excludedBundleIdentifiers.contains) ?? false) else {
                closeSpan(at: now, force: true)
                return
            }
            let name = app.localizedName ?? bundleID ?? "Unknown"
            let title = FocusedWindow.title(forProcessIdentifier: app.processIdentifier)
            extendOrOpen(appName: name, bundleID: bundleID, windowTitle: title, at: now)
        }

        if now.timeIntervalSince(lastFlush) >= flushInterval {
            flush(at: now)
            lastFlush = now
        }
    }

    private func beginIdle(at date: Date) {
        isIdle = true
        currentAppName = "Away"
        currentCategory = "Away"
        currentWindowTitle = nil
        span = Span(appName: "Away", bundleID: nil, windowTitle: nil, category: "Away",
                    isIdle: true, start: date, end: date, record: nil)
    }

    private func extendOrOpen(appName: String, bundleID: String?, windowTitle: String?, at now: Date) {
        let category = AppCategorizer.category(forBundleIdentifier: bundleID, appName: appName)
        currentAppName = appName
        currentCategory = category
        currentWindowTitle = windowTitle

        if var open = span, !open.isIdle, open.bundleID == bundleID, open.windowTitle == windowTitle {
            open.end = now
            open.record?.endedAt = now
            span = open
            return
        }
        closeSpan(at: now, force: false)
        span = Span(appName: appName, bundleID: bundleID, windowTitle: windowTitle,
                    category: category, isIdle: false, start: now, end: now, record: nil)
    }

    /// Closes the open span.
    ///
    /// A span too short to be worth its own record is absorbed into the record
    /// before it rather than dropped, so flicking between windows doesn't punch
    /// holes in an otherwise continuous day.
    private func closeSpan(at date: Date, force: Bool) {
        guard var open = span else { return }
        span = nil
        open.end = max(open.end, date)
        let length = open.end.timeIntervalSince(open.start)

        if let existing = open.record {
            existing.endedAt = open.end
            return
        }
        guard length >= 1 else { return }
        if length < minimumRecordedDuration, !force {
            if let previous = mostRecentRecord(),
               open.start.timeIntervalSince(previous.endedAt) < 2 {
                previous.endedAt = open.end
                return
            }
        }
        context.insert(makeRecord(from: open))
    }

    /// Writes the open span through without closing it, so a crash loses at
    /// most `flushInterval` rather than the whole stretch.
    private func flush(at now: Date) {
        guard var open = span else { return }
        open.end = now
        if let existing = open.record {
            existing.endedAt = now
        } else if now.timeIntervalSince(open.start) >= minimumRecordedDuration {
            let record = makeRecord(from: open)
            context.insert(record)
            open.record = record
        }
        span = open
        save()
    }

    private func makeRecord(from span: Span) -> ActivityRecord {
        ActivityRecord(
            appName: span.appName,
            bundleIdentifier: span.bundleID,
            windowTitle: span.windowTitle,
            startedAt: span.start,
            endedAt: span.end,
            isIdle: span.isIdle,
            categoryName: span.category
        )
    }

    private func mostRecentRecord() -> ActivityRecord? {
        var descriptor = FetchDescriptor<ActivityRecord>(
            sortBy: [SortDescriptor(\.endedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
