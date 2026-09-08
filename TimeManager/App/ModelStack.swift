import Foundation
import SwiftData

/// Owns the SwiftData stack: where the store lives, how it opens, and the
/// one-time cleanup that has to happen before any view reads from it.
enum ModelStack {

    static let schema = Schema([
        WorkSession.self,
        SessionSegment.self,
        ActivityRecord.self,
        TimeEntry.self,
        TimeCategory.self,
        AppCategoryRule.self,
    ])

    static func makeContainer() -> ModelContainer {
        relocateLegacyStoreIfNeeded()
        let url = storeURL()
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        } catch {
            // A corrupt or unmigratable store must not brick launch. Move it
            // aside — it stays on disk for recovery — and start clean.
            let stamp = Int(Date.now.timeIntervalSince1970)
            let quarantine = url.deletingLastPathComponent()
                .appendingPathComponent("Recovered-\(stamp).store")
            for suffix in storeSuffixes {
                let from = URL(fileURLWithPath: url.path + suffix)
                let to = URL(fileURLWithPath: quarantine.path + suffix)
                try? FileManager.default.moveItem(at: from, to: to)
            }
            return try! ModelContainer(for: schema, configurations: ModelConfiguration(url: url))
        }
    }

    // MARK: - Store location

    private static let storeSuffixes = ["", "-wal", "-shm"]

    /// Set by the test harness to redirect the store into a temporary
    /// directory. Nothing in the shipping app writes it, so a normal launch
    /// takes the Application Support path below.
    static let storeDirectoryOverrideKey = "SPAN_STORE_DIRECTORY"

    private static var storeDirectoryOverride: URL? {
        guard let path = ProcessInfo.processInfo.environment[storeDirectoryOverrideKey],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func storeURL() -> URL {
        let directory = storeDirectoryOverride
            ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Span", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Span.store")
    }

    /// Earlier builds used the default `ModelConfiguration`, which writes to
    /// `~/Library/Application Support/default.store` — the shared root, not an
    /// app-specific folder, where it sits alongside every other unsandboxed
    /// SwiftData app's store. Move it into our own directory, taking the `-wal`
    /// and `-shm` siblings with it so no committed transactions are lost.
    private static func relocateLegacyStoreIfNeeded() {
        // A redirected store is a fresh sandbox; there is no legacy store to
        // adopt, and adopting one would drag real data into it.
        guard storeDirectoryOverride == nil else { return }
        let manager = FileManager.default
        let root = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let target = storeURL()
        guard !manager.fileExists(atPath: target.path) else { return }

        // Two earlier homes: the shared Application Support root, and a folder
        // named after the app before it was called Span.
        let candidates = [
            root.appendingPathComponent("TimeManager/TimeManager.store"),
            root.appendingPathComponent("default.store"),
        ]
        guard let legacy = candidates.first(where: { manager.fileExists(atPath: $0.path) })
        else { return }

        for suffix in storeSuffixes {
            let from = URL(fileURLWithPath: legacy.path + suffix)
            let to = URL(fileURLWithPath: target.path + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            try? manager.moveItem(at: from, to: to)
        }
        // Leave nothing behind that looks like live data.
        try? manager.removeItem(at: root.appendingPathComponent("TimeManager"))
    }

    // MARK: - Clearing data

    /// Every preference Span writes. Listed rather than wiping the domain, so a
    /// reset cannot take out anything the system keeps alongside them.
    static let preferenceKeys = [
        "userName", "personalNote", "dailyFocusTargetMinutes", "defaultSessionMinutes",
        "idleThresholdMinutes", "autoFinishAfterMinutes",
        "hud.visible", "hud.xFraction", "hud.topOffset",
        "hasOnboarded", "hasSeenGuide", "timeline.hourHeight", "timelineGrouping",
        "pickUpDismissed",
    ]

    /// Deletes tracked application activity, optionally only today's.
    @MainActor
    static func deleteActivity(in context: ModelContext, onlyToday: Bool) {
        if onlyToday {
            let dayStart = Calendar.current.startOfDay(for: .now)
            try? context.delete(model: ActivityRecord.self,
                                where: #Predicate { $0.startedAt >= dayStart })
        } else {
            try? context.delete(model: ActivityRecord.self)
        }
        try? context.save()
    }

    /// Removes everything Span has recorded and returns it to a first run.
    ///
    /// Categories are re-seeded rather than left empty, because an app with no
    /// categories cannot start a session.
    @MainActor
    static func resetEverything(in context: ModelContext) {
        try? context.delete(model: ActivityRecord.self)
        try? context.delete(model: TimeEntry.self)
        try? context.delete(model: SessionSegment.self)
        try? context.delete(model: WorkSession.self)
        try? context.delete(model: AppCategoryRule.self)
        try? context.delete(model: TimeCategory.self)
        try? context.save()

        for key in preferenceKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        AppCategorizer.updateOverrides([])
        seedCategoriesIfNeeded(in: context)
    }

    /// Creates the starting categories the first time the app runs. One per
    /// palette slot, so the initial set is fully distinguishable.
    @MainActor
    static func seedCategoriesIfNeeded(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<TimeCategory>())) ?? []
        guard existing.isEmpty else {
            CategoryPalette.updateRegistry(existing)
            return
        }
        let seeded = TimeCategory.defaults.enumerated().map { index, entry in
            TimeCategory(name: entry.0, colorSlot: entry.1, sortIndex: index)
        }
        seeded.forEach(context.insert)
        try? context.save()
        CategoryPalette.updateRegistry(seeded)
    }

    /// Loads the user's app-to-category rules into the categoriser.
    @MainActor
    static func loadAppRules(in context: ModelContext) {
        let rules = (try? context.fetch(FetchDescriptor<AppCategoryRule>())) ?? []
        AppCategorizer.updateOverrides(rules)
    }

    // MARK: - Launch recovery

    /// Closes sessions the app never got to finish.
    ///
    /// A session that was running when the app quit stays `.active` with no
    /// `endedAt`, so its `elapsed()` keeps growing against the wall clock — come
    /// back two days later and the UI claims a 48-hour session. Sessions are
    /// closed at the last moment we can actually vouch for, but only once
    /// they're clearly stale, so quitting and relaunching within a few minutes
    /// still lets the user pick up where they left off.
    @MainActor
    static func recoverStaleSessions(
        in context: ModelContext,
        now: Date = .now,
        grace: TimeInterval = 15 * 60
    ) {
        let active = SessionStatus.active.rawValue
        let paused = SessionStatus.paused.rawValue
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.statusRaw == active || $0.statusRaw == paused }
        )
        guard let stale = try? context.fetch(descriptor), !stale.isEmpty else { return }

        for session in stale {
            // Sessions predating segments get one synthesised, so they still
            // draw on the timeline instead of silently disappearing.
            if session.segments.isEmpty {
                let segment = SessionSegment(startedAt: session.startedAt, session: session)
                segment.endedAt = session.endedAt ?? session.pausedAt
                session.segments.append(segment)
            }

            let lastKnownGood = session.pausedAt
                ?? session.segments.compactMap(\.endedAt).max()
                ?? session.startedAt

            let isRecent = now.timeIntervalSince(lastKnownGood) < grace
                && Calendar.current.isDate(lastKnownGood, inSameDayAs: now)
            guard !isRecent else { continue }

            session.complete(at: lastKnownGood)
            NotificationService.cancelReminder(for: session)
        }
        try? context.save()
    }

    /// Brings review answers back inside the sessions they describe.
    ///
    /// The review asks how much of a session felt like real work, ceilinged by
    /// what the session had elapsed when it was answered. Shorten the session
    /// afterwards and that answer is left behind: a session left running
    /// overnight, reviewed at nineteen hours and then corrected to two, went on
    /// contributing nineteen hours to the day's honest-work total.
    ///
    /// Every reader now caps the answer as it reads it, so this is only about
    /// the stored number — but leaving a figure on disk that no view will agree
    /// with is how the next inconsistency starts.
    @MainActor
    static func clampReviewsToWorkedTime(in context: ModelContext, now: Date = .now) {
        let completed = SessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<WorkSession>(
            predicate: #Predicate { $0.statusRaw == completed && $0.honestWorkMinutes != nil }
        )
        guard let sessions = try? context.fetch(descriptor) else { return }
        for session in sessions {
            session.clampReviewToWorkedTime(at: now)
        }
        guard context.hasChanges else { return }
        try? context.save()
    }
}
