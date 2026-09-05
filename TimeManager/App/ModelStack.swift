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

    private static func storeURL() -> URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("TimeManager.store")
    }

    /// Earlier builds used the default `ModelConfiguration`, which writes to
    /// `~/Library/Application Support/default.store` — the shared root, not an
    /// app-specific folder, where it sits alongside every other unsandboxed
    /// SwiftData app's store. Move it into our own directory, taking the `-wal`
    /// and `-shm` siblings with it so no committed transactions are lost.
    private static func relocateLegacyStoreIfNeeded() {
        let manager = FileManager.default
        let legacy = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("default.store")
        let target = storeURL()
        guard manager.fileExists(atPath: legacy.path),
              !manager.fileExists(atPath: target.path) else { return }

        for suffix in storeSuffixes {
            let from = URL(fileURLWithPath: legacy.path + suffix)
            let to = URL(fileURLWithPath: target.path + suffix)
            guard manager.fileExists(atPath: from.path) else { continue }
            try? manager.moveItem(at: from, to: to)
        }
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
}
